#!/bin/bash
# =============================================================================
# configure-cluster-infrastructure.sh
# =============================================================================
# Configures OpenShift cluster infrastructure for the AI Ops Self-Healing Platform:
# 1. Scales worker nodes (via MachineSet) to meet minimum requirements
# 2. Installs OpenShift Data Foundation (ODF) operator
# 3. Creates StorageSystem and StorageCluster for persistent storage
# 4. Validates storage classes are available
#
# This script works on AWS IPI-installed OpenShift clusters.
# It auto-detects cluster infrastructure and adapts accordingly.
#
# Usage:
#   ./scripts/configure-cluster-infrastructure.sh [options]
#
# Options:
#   --min-workers N        Minimum number of worker nodes (default: 3)
#   --enable-odf           Install and configure ODF (default: true)
#   --skip-odf             Skip ODF installation
#   --odf-storage-size     Size per OSD in Gi (default: 512Gi)
#   --dry-run              Show what would be done without making changes
#   --help                 Show this help message
#
# Prerequisites:
#   - oc CLI installed and logged into cluster as cluster-admin
#   - Cluster running on AWS (IPI installation)
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration Defaults
# =============================================================================

MIN_WORKERS="${MIN_WORKERS:-3}"
ENABLE_ODF="${ENABLE_ODF:-true}"
ODF_STORAGE_SIZE="${ODF_STORAGE_SIZE:-512Gi}"
DRY_RUN="${DRY_RUN:-false}"
ODF_CHANNEL="${ODF_CHANNEL:-stable-4.18}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

show_help() {
    head -35 "$0" | tail -25
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --min-workers)
                MIN_WORKERS="$2"
                shift 2
                ;;
            --enable-odf)
                ENABLE_ODF="true"
                shift
                ;;
            --skip-odf)
                ENABLE_ODF="false"
                shift
                ;;
            --odf-storage-size)
                ODF_STORAGE_SIZE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

check_prerequisites() {
    log_step "Pre-flight Checks"
    
    # Check oc CLI
    if ! command -v oc &> /dev/null; then
        log_error "oc CLI not found. Please install it first."
        log_info "Run: ./scripts/install-prerequisites-rhel.sh"
        exit 1
    fi
    log_success "oc CLI found: $(oc version --client -o json | jq -r '.clientVersion.gitVersion' 2>/dev/null || oc version --client | head -1)"
    
    # Check cluster login
    if ! oc whoami &> /dev/null; then
        log_error "Not logged into OpenShift cluster."
        log_info "Run: oc login <cluster-api-url>"
        exit 1
    fi
    log_success "Logged in as: $(oc whoami)"
    
    # Check cluster-admin access
    if ! oc auth can-i '*' '*' --all-namespaces &> /dev/null; then
        log_error "Current user does not have cluster-admin privileges."
        log_info "Run: oc login as a cluster-admin user"
        exit 1
    fi
    log_success "Cluster-admin access confirmed"
    
    # Get cluster info
    CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    PLATFORM_TYPE=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
    API_URL=$(oc whoami --show-server)
    
    log_success "Cluster: $CLUSTER_NAME"
    log_success "Platform: $PLATFORM_TYPE"
    log_success "API URL: $API_URL"
    
    if [[ "$PLATFORM_TYPE" != "AWS" ]]; then
        log_warn "This script is optimized for AWS. Platform detected: $PLATFORM_TYPE"
        log_warn "MachineSet scaling may not work as expected on other platforms."
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    export CLUSTER_NAME PLATFORM_TYPE API_URL
}

# =============================================================================
# Node Management
# =============================================================================

get_worker_machinesets() {
    # Get all worker MachineSets (including GPU)
    oc get machinesets -n openshift-machine-api -o json | \
        jq -r '.items[] | select(.spec.template.metadata.labels["machine.openshift.io/cluster-api-machine-role"]=="worker") | .metadata.name'
}

get_regular_worker_machineset() {
    # Get the primary (non-GPU) worker MachineSet
    # GPU MachineSets typically contain "gpu" in the name
    local all_machinesets
    all_machinesets=$(get_worker_machinesets)
    
    # Prefer non-GPU MachineSets
    local regular_ms
    regular_ms=$(echo "$all_machinesets" | grep -v -i gpu | head -1)
    
    if [[ -n "$regular_ms" ]]; then
        echo "$regular_ms"
    else
        # Fallback to first MachineSet if no non-GPU found
        echo "$all_machinesets" | head -1
    fi
}

get_machineset_replicas() {
    local machineset=$1
    oc get machineset "$machineset" -n openshift-machine-api -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0"
}

get_machineset_ready_replicas() {
    local machineset=$1
    oc get machineset "$machineset" -n openshift-machine-api -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0"
}

scale_worker_nodes() {
    log_step "Scaling Worker Nodes"
    
    # Get all worker MachineSets
    local all_machinesets
    all_machinesets=$(get_worker_machinesets)
    
    if [[ -z "$all_machinesets" ]]; then
        log_error "No worker MachineSets found. Cannot scale nodes automatically."
        log_info "For bare-metal or non-IPI clusters, add nodes manually."
        exit 1
    fi
    
    log_info "Available MachineSets:"
    echo "$all_machinesets" | while read -r ms; do
        local replicas ready
        replicas=$(get_machineset_replicas "$ms")
        ready=$(get_machineset_ready_replicas "$ms")
        if echo "$ms" | grep -qi gpu; then
            echo "  - $ms (replicas: $replicas, ready: $ready) [GPU]"
        else
            echo "  - $ms (replicas: $replicas, ready: $ready) [Regular Worker]"
        fi
    done
    
    # Get the target MachineSet (non-GPU worker)
    local target_machineset
    target_machineset=$(get_regular_worker_machineset)
    
    if [[ -z "$target_machineset" ]]; then
        log_error "Could not determine target MachineSet for scaling."
        exit 1
    fi
    
    log_info ""
    log_info "Target MachineSet for scaling: $target_machineset"
    
    # Check replicas on the target MachineSet (not total cluster workers)
    local current_replicas
    current_replicas=$(get_machineset_replicas "$target_machineset")
    
    log_info "Current replicas in target MachineSet: $current_replicas"
    log_info "Minimum required replicas: $MIN_WORKERS"
    
    if [[ $current_replicas -ge $MIN_WORKERS ]]; then
        log_success "MachineSet $target_machineset meets requirements ($current_replicas >= $MIN_WORKERS)"
        return 0
    fi
    
    local replicas_needed=$((MIN_WORKERS - current_replicas))
    log_info "Need to add $replicas_needed more replica(s) to MachineSet"
    
    log_info "Scaling MachineSet: $target_machineset"
    log_info "  Current replicas: $current_replicas"
    log_info "  New replicas: $MIN_WORKERS"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would run: oc scale machineset $target_machineset --replicas=$MIN_WORKERS -n openshift-machine-api"
        return 0
    fi
    
    oc scale machineset "$target_machineset" --replicas="$MIN_WORKERS" -n openshift-machine-api
    log_success "MachineSet scaled to $MIN_WORKERS replicas"
    
    # Wait for the MachineSet to have all replicas ready
    wait_for_machineset_ready "$target_machineset" "$MIN_WORKERS"
}

wait_for_machineset_ready() {
    local machineset=$1
    local required_replicas=$2
    local timeout=600  # 10 minutes
    local interval=15
    local elapsed=0
    
    log_info "Waiting for MachineSet $machineset to have $required_replicas ready replicas (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        local ready_replicas
        ready_replicas=$(get_machineset_ready_replicas "$machineset")
        
        if [[ $ready_replicas -ge $required_replicas ]]; then
            log_success "MachineSet $machineset has $ready_replicas ready replicas"
            oc get machineset "$machineset" -n openshift-machine-api
            return 0
        fi
        
        log_info "  Ready replicas: $ready_replicas / $required_replicas (waiting...)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "Timeout waiting for MachineSet replicas to be Ready"
    log_info "Current MachineSet status:"
    oc get machineset "$machineset" -n openshift-machine-api -o wide
    log_info "Current node status:"
    oc get nodes -l 'node-role.kubernetes.io/worker'
    exit 1
}

# =============================================================================
# OpenShift Data Foundation (ODF)
# =============================================================================

check_odf_installed() {
    if oc get csv -n openshift-storage 2>/dev/null | grep -q "odf-operator"; then
        return 0
    fi
    return 1
}

install_odf_operator() {
    log_step "Installing OpenShift Data Foundation Operator"
    
    if check_odf_installed; then
        log_success "ODF operator is already installed"
        oc get csv -n openshift-storage | grep odf
        return 0
    fi
    
    log_info "Creating openshift-storage namespace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would create namespace and operator subscription"
        return 0
    fi
    
    # Create namespace
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-storage
  labels:
    openshift.io/cluster-monitoring: "true"
EOF
    
    # Create OperatorGroup
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-storage-operatorgroup
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
EOF
    
    # Create Subscription
    log_info "Subscribing to ODF operator (channel: $ODF_CHANNEL)..."
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: odf-operator
  namespace: openshift-storage
spec:
  channel: "$ODF_CHANNEL"
  installPlanApproval: Automatic
  name: odf-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
    
    log_success "ODF operator subscription created"
    
    # Wait for operator to be ready
    wait_for_odf_operator
}

wait_for_odf_operator() {
    local timeout=300  # 5 minutes
    local interval=10
    local elapsed=0
    
    log_info "Waiting for ODF operator to be ready (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        if oc get csv -n openshift-storage 2>/dev/null | grep -q "odf-operator.*Succeeded"; then
            log_success "ODF operator is ready"
            oc get csv -n openshift-storage | grep odf
            return 0
        fi
        
        log_info "  Waiting for operator... (${elapsed}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "Timeout waiting for ODF operator"
    log_info "Current CSV status:"
    oc get csv -n openshift-storage
    exit 1
}

label_storage_nodes() {
    log_info "Labeling worker nodes for ODF storage..."
    
    # Get worker nodes (excluding GPU nodes for ODF)
    local worker_nodes
    worker_nodes=$(oc get nodes -l 'node-role.kubernetes.io/worker,!node-role.kubernetes.io/worker-gpu' --no-headers -o custom-columns=NAME:.metadata.name | head -3)
    
    if [[ -z "$worker_nodes" ]]; then
        # Fall back to any worker nodes
        worker_nodes=$(oc get nodes -l 'node-role.kubernetes.io/worker' --no-headers -o custom-columns=NAME:.metadata.name | head -3)
    fi
    
    local node_count
    node_count=$(echo "$worker_nodes" | wc -l)
    
    if [[ $node_count -lt 3 ]]; then
        log_warn "ODF requires at least 3 nodes. Found: $node_count"
        log_warn "ODF will be deployed but may not be fully redundant."
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would label nodes for ODF:"
        echo "$worker_nodes"
        return 0
    fi
    
    echo "$worker_nodes" | while read -r node; do
        log_info "  Labeling node: $node"
        oc label node "$node" cluster.ocs.openshift.io/openshift-storage='' --overwrite
    done
    
    log_success "Storage nodes labeled"
}

create_storage_cluster() {
    log_step "Creating ODF StorageCluster"
    
    # Check if StorageCluster already exists
    if oc get storagecluster -n openshift-storage 2>/dev/null | grep -q "ocs-storagecluster"; then
        log_success "StorageCluster already exists"
        oc get storagecluster -n openshift-storage
        return 0
    fi
    
    # Label nodes for storage
    label_storage_nodes
    
    log_info "Creating StorageSystem..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would create StorageSystem and StorageCluster"
        return 0
    fi
    
    # Create StorageSystem
    cat <<EOF | oc apply -f -
apiVersion: odf.openshift.io/v1alpha1
kind: StorageSystem
metadata:
  name: ocs-storagecluster-storagesystem
  namespace: openshift-storage
spec:
  kind: storagecluster.ocs.openshift.io/v1
  name: ocs-storagecluster
  namespace: openshift-storage
EOF
    
    log_info "Creating StorageCluster (storage size: $ODF_STORAGE_SIZE)..."
    
    # Create StorageCluster
    cat <<EOF | oc apply -f -
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  name: ocs-storagecluster
  namespace: openshift-storage
spec:
  arbiter: {}
  encryption:
    kms: {}
  externalStorage: {}
  managedResources:
    cephObjectStoreUsers: {}
    cephCluster: {}
    cephConfig: {}
    cephDashboard: {}
    cephObjectStores: {}
    cephBlockPools: {}
    cephNonResilientPools: {}
    cephFilesystems: {}
    cephRBDMirror: {}
    cephToolbox: {}
  mirroring: {}
  monDataDirHostPath: /var/lib/rook
  storageDeviceSets:
  - config: {}
    count: 1
    dataPVCTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: $ODF_STORAGE_SIZE
        storageClassName: gp2-csi
        volumeMode: Block
    name: ocs-deviceset-gp2-csi
    placement: {}
    preparePlacement: {}
    replica: 3
    resources:
      limits:
        cpu: "2"
        memory: 5Gi
      requests:
        cpu: "1"
        memory: 5Gi
EOF
    
    log_success "StorageCluster created"
    
    # Wait for StorageCluster to be ready
    wait_for_storage_cluster
}

wait_for_storage_cluster() {
    local timeout=900  # 15 minutes (ODF takes time)
    local interval=30
    local elapsed=0
    
    log_info "Waiting for StorageCluster to be Ready (timeout: ${timeout}s)..."
    log_info "This may take 10-15 minutes..."
    
    while [[ $elapsed -lt $timeout ]]; do
        local phase
        phase=$(oc get storagecluster ocs-storagecluster -n openshift-storage -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
        
        if [[ "$phase" == "Ready" ]]; then
            log_success "StorageCluster is Ready"
            oc get storagecluster -n openshift-storage
            return 0
        fi
        
        log_info "  StorageCluster phase: $phase (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_warn "Timeout waiting for StorageCluster (may still be provisioning)"
    log_info "Current status:"
    oc get storagecluster -n openshift-storage
    oc get pods -n openshift-storage
}

validate_storage() {
    log_step "Validating Storage Configuration"
    
    log_info "Checking storage classes..."
    
    local storage_classes
    storage_classes=$(oc get sc --no-headers -o custom-columns=NAME:.metadata.name)
    
    echo "$storage_classes" | while read -r sc; do
        local is_default
        is_default=$(oc get sc "$sc" -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null || echo "false")
        if [[ "$is_default" == "true" ]]; then
            echo "  ✅ $sc (default)"
        else
            echo "  ✓ $sc"
        fi
    done
    
    # Check for OCS storage classes
    if echo "$storage_classes" | grep -q "ocs-storagecluster"; then
        log_success "ODF storage classes are available"
    else
        log_warn "ODF storage classes not yet available (may still be provisioning)"
    fi
    
    # Check for default storage class
    local default_sc
    default_sc=$(oc get sc -o json | jq -r '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true") | .metadata.name' | head -1)
    
    if [[ -n "$default_sc" ]]; then
        log_success "Default storage class: $default_sc"
    else
        log_warn "No default storage class set"
        log_info "Setting gp2-csi as default (if available)..."
        if echo "$storage_classes" | grep -q "gp2-csi"; then
            if [[ "$DRY_RUN" != "true" ]]; then
                oc patch storageclass gp2-csi -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
                log_success "Set gp2-csi as default storage class"
            fi
        fi
    fi
}

# =============================================================================
# Summary
# =============================================================================

print_summary() {
    log_step "Configuration Summary"
    
    echo -e "\n${GREEN}Cluster Infrastructure Configuration Complete!${NC}\n"
    
    echo "Cluster Details:"
    echo "  Name:      $CLUSTER_NAME"
    echo "  Platform:  $PLATFORM_TYPE"
    echo "  API URL:   $API_URL"
    echo ""
    
    echo "Node Configuration:"
    local worker_count
    worker_count=$(get_current_worker_count)
    echo "  Worker Nodes: $worker_count"
    oc get nodes -l 'node-role.kubernetes.io/worker' --no-headers | awk '{print "    - " $1 " (" $2 ")"}'
    echo ""
    
    if [[ "$ENABLE_ODF" == "true" ]]; then
        echo "Storage Configuration:"
        if check_odf_installed; then
            echo "  ODF Status: Installed"
            local sc_phase
            sc_phase=$(oc get storagecluster ocs-storagecluster -n openshift-storage -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            echo "  StorageCluster: $sc_phase"
        else
            echo "  ODF Status: Not Installed"
        fi
        echo ""
    fi
    
    echo "Storage Classes:"
    oc get sc --no-headers | awk '{print "  - " $1}'
    echo ""
    
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Continue with platform deployment:"
    echo "     make operator-deploy"
    echo ""
    echo "  2. Or run the full deployment workflow:"
    echo "     ./scripts/install-prerequisites-rhel.sh  # If not done already"
    echo "     source ~/.bashrc"
    echo "     make token"
    echo "     make build-ee"
    echo "     make operator-deploy"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo "============================================================================="
    echo " OpenShift Cluster Infrastructure Configuration"
    echo " For: AI Ops Self-Healing Platform"
    echo "============================================================================="
    echo ""
    
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    # Pre-flight checks
    check_prerequisites
    
    # Scale worker nodes if needed
    scale_worker_nodes
    
    # Install and configure ODF
    if [[ "$ENABLE_ODF" == "true" ]]; then
        install_odf_operator
        create_storage_cluster
        validate_storage
    else
        log_info "Skipping ODF installation (--skip-odf specified)"
    fi
    
    # Print summary
    print_summary
    
    log_success "Cluster infrastructure configuration complete!"
}

# Run main function
main "$@"
