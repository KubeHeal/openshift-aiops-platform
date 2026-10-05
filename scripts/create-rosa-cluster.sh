#!/bin/bash
# =============================================================================
# create-rosa-cluster.sh
# =============================================================================
# Provisions a ROSA Classic cluster for the AI Ops Self-Healing Platform.
#
# This script automates the full ROSA cluster lifecycle:
#   1. Validates prerequisites (rosa, aws, oc CLIs; active sessions)
#   2. Creates a ROSA Classic HA cluster with STS (3x m5.2xlarge default)
#   3. Waits for cluster to reach "ready" state (~35-45 min)
#   4. Creates a cluster-admin user
#   5. (Optional) Adds a GPU machine pool (g5.2xlarge default)
#   6. (Optional) Creates an S3 bucket for model storage
#   7. Logs into the cluster with oc
#   8. Prints next-step commands
#
# Supports all CLAUDE.md cluster configurations:
#   - ROSA Classic HA (default): 3x m5.2xlarge + optional GPU
#   - ROSA Classic Single-Worker: --replicas 1 --no-gpu
#   - Custom sizes: --instance-type, --gpu-instance-type overrides
#
# Usage:
#   ./scripts/create-rosa-cluster.sh [options]
#
# Options:
#   --cluster-name NAME       Cluster name (default: aiops-platform)
#   --region REGION            AWS region (default: us-east-1)
#   --instance-type TYPE       Worker instance type (default: m5.2xlarge)
#   --replicas N               Worker node count (default: 3)
#   --version VERSION          OpenShift version (default: auto-detect latest)
#   --gpu                      Add GPU machine pool (default)
#   --no-gpu                   Skip GPU machine pool
#   --gpu-instance-type TYPE   GPU instance type (default: g5.2xlarge)
#   --gpu-replicas N           GPU node count (default: 1)
#   --create-bucket            Create S3 bucket for model storage (default)
#   --no-bucket                Skip S3 bucket creation
#   --bucket-prefix PREFIX     S3 bucket name prefix (default: aiops-model-storage)
#   --dry-run                  Show commands without executing
#   --no-inject-creds          Skip writing S3 credentials into values-hub.yaml
#   --help                     Show this help message
#
# Prerequisites:
#   - rosa CLI installed and logged in (rosa login or rosa login --token=...)
#   - aws CLI installed and configured (aws configure)
#   - oc CLI installed
#
# Examples:
#   # Full HA cluster with GPU (matches CLAUDE.md spec)
#   ./scripts/create-rosa-cluster.sh
#
#   # Single-worker for dev/test
#   ./scripts/create-rosa-cluster.sh --replicas 1 --no-gpu --cluster-name aiops-dev
#
#   # Custom region, bigger GPU
#   ./scripts/create-rosa-cluster.sh --region us-west-2 --gpu-instance-type g5.4xlarge
#
#   # Dry run to preview
#   ./scripts/create-rosa-cluster.sh --dry-run
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration Defaults
# =============================================================================

CLUSTER_NAME="${CLUSTER_NAME:-aiops-platform}"
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-m5.2xlarge}"
REPLICAS="${REPLICAS:-3}"
OCP_VERSION="${OCP_VERSION:-}"
ENABLE_GPU="${ENABLE_GPU:-true}"
GPU_INSTANCE_TYPE="${GPU_INSTANCE_TYPE:-g5.2xlarge}"
GPU_REPLICAS="${GPU_REPLICAS:-1}"
ENABLE_BUCKET="${ENABLE_BUCKET:-true}"
BUCKET_PREFIX="${BUCKET_PREFIX:-aiops-model-storage}"
DRY_RUN="${DRY_RUN:-false}"
INJECT_CREDS="${INJECT_CREDS:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo ""
    echo -e "${CYAN}${BOLD}=== $1 ===${NC}"
}

run_cmd() {
    local description="$1"
    shift
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $description"
        echo -e "  ${CYAN}\$ $*${NC}"
        return 0
    fi
    log_info "$description"
    "$@"
}

show_help() {
    cat <<'EOF'
Usage: ./scripts/create-rosa-cluster.sh [options]

Provisions a ROSA Classic cluster for the AI Ops Self-Healing Platform.

Options:
  --cluster-name NAME       Cluster name (default: aiops-platform)
  --region REGION            AWS region (default: us-east-1)
  --instance-type TYPE       Worker instance type (default: m5.2xlarge)
  --replicas N               Worker node count (default: 3)
  --version VERSION          OpenShift version (default: auto-detect latest)
  --gpu                      Add GPU machine pool (default)
  --no-gpu                   Skip GPU machine pool
  --gpu-instance-type TYPE   GPU instance type (default: g5.2xlarge)
  --gpu-replicas N           GPU node count (default: 1)
  --create-bucket            Create S3 bucket for model storage (default)
  --no-bucket                Skip S3 bucket creation
  --bucket-prefix PREFIX     S3 bucket name prefix (default: aiops-model-storage)
  --dry-run                  Show commands without executing
  --no-inject-creds          Skip writing S3 credentials into values-hub.yaml
  --help                     Show this help message

Cluster Configurations (from CLAUDE.md):
  ROSA Classic HA (default):
    ./scripts/create-rosa-cluster.sh

  ROSA Classic Single-Worker:
    ./scripts/create-rosa-cluster.sh --replicas 1 --no-gpu

  Custom GPU instance:
    ./scripts/create-rosa-cluster.sh --gpu-instance-type g5.4xlarge

Environment Variables (override defaults):
  CLUSTER_NAME, AWS_REGION, INSTANCE_TYPE, REPLICAS, OCP_VERSION,
  ENABLE_GPU, GPU_INSTANCE_TYPE, GPU_REPLICAS, ENABLE_BUCKET, BUCKET_PREFIX
EOF
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cluster-name)
            CLUSTER_NAME="$2"; shift 2 ;;
        --region)
            AWS_REGION="$2"; shift 2 ;;
        --instance-type)
            INSTANCE_TYPE="$2"; shift 2 ;;
        --replicas)
            REPLICAS="$2"; shift 2 ;;
        --version)
            OCP_VERSION="$2"; shift 2 ;;
        --gpu)
            ENABLE_GPU="true"; shift ;;
        --no-gpu)
            ENABLE_GPU="false"; shift ;;
        --gpu-instance-type)
            GPU_INSTANCE_TYPE="$2"; shift 2 ;;
        --gpu-replicas)
            GPU_REPLICAS="$2"; shift 2 ;;
        --create-bucket)
            ENABLE_BUCKET="true"; shift ;;
        --no-bucket)
            ENABLE_BUCKET="false"; shift ;;
        --bucket-prefix)
            BUCKET_PREFIX="$2"; shift 2 ;;
        --dry-run)
            DRY_RUN="true"; shift ;;
        --no-inject-creds)
            INJECT_CREDS="false"; shift ;;
        --help|-h)
            show_help ;;
        *)
            log_error "Unknown option: $1"
            echo "Run with --help for usage information."
            exit 1 ;;
    esac
done

# =============================================================================
# Step 1: Validate Prerequisites
# =============================================================================

log_step "Step 1/9: Validating Prerequisites"

PREREQ_FAILED=false

# Check rosa CLI
if command -v rosa &>/dev/null; then
    ROSA_VERSION=$(rosa version 2>/dev/null | head -1 || echo "unknown")
    log_success "rosa CLI installed: ${ROSA_VERSION}"
else
    log_error "rosa CLI not found. Install from: https://console.redhat.com/openshift/downloads"
    PREREQ_FAILED=true
fi

# Check aws CLI
if command -v aws &>/dev/null; then
    AWS_VERSION=$(aws --version 2>/dev/null | head -1 || echo "unknown")
    log_success "aws CLI installed: ${AWS_VERSION}"
else
    log_error "aws CLI not found. Install from: https://aws.amazon.com/cli/"
    PREREQ_FAILED=true
fi

# Check oc CLI
if command -v oc &>/dev/null; then
    OC_VERSION=$(oc version --client 2>/dev/null | head -1 || echo "unknown")
    log_success "oc CLI installed: ${OC_VERSION}"
else
    log_error "oc CLI not found. Run: ./scripts/install-prerequisites-rhel.sh"
    PREREQ_FAILED=true
fi

# Check rosa login status
if [[ "$DRY_RUN" == "false" ]]; then
    if rosa whoami &>/dev/null; then
        ROSA_USER=$(rosa whoami 2>/dev/null | grep "OCM Account" | awk '{print $NF}' || echo "authenticated")
        log_success "rosa logged in: ${ROSA_USER}"
    else
        log_error "Not logged into ROSA. Run: rosa login (SSO browser login)"
        log_info "  Or for headless environments: ocm login --use-device-code"
        log_info "  Legacy token login: rosa login --token=<token> (https://console.redhat.com/openshift/token)"
        PREREQ_FAILED=true
    fi

    # Check AWS credentials
    if aws sts get-caller-identity &>/dev/null; then
        AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
        log_success "AWS credentials valid: account ${AWS_ACCOUNT}"
    else
        log_error "AWS credentials not configured. Run: aws configure"
        PREREQ_FAILED=true
    fi
fi

if [[ "$PREREQ_FAILED" == "true" ]]; then
    echo ""
    log_error "Prerequisites check failed. Fix the issues above and retry."
    exit 1
fi

log_success "All prerequisites validated"

# Ensure STS account roles exist (required for --sts --mode=auto)
if [[ "$DRY_RUN" == "false" ]]; then
    EXISTING_ROLES=$(aws iam list-roles --query "Roles[?starts_with(RoleName,'ManagedOpenShift-Installer')].RoleName" --output text 2>/dev/null || echo "")
    if [[ -z "$EXISTING_ROLES" ]]; then
        log_info "Creating ROSA STS account roles (first-time setup)..."
        rosa create account-roles --mode auto --yes
        log_success "STS account roles created"
    else
        log_success "STS account roles already exist"
    fi
else
    echo -e "${YELLOW}[DRY-RUN]${NC} Would verify/create STS account roles: rosa create account-roles --mode auto --yes"
fi

# =============================================================================
# Step 2: Create ROSA Classic Cluster
# =============================================================================

log_step "Step 2/9: Creating ROSA Classic Cluster"

echo ""
echo -e "  ${BOLD}Configuration:${NC}"
echo -e "    Cluster Name:    ${CYAN}${CLUSTER_NAME}${NC}"
echo -e "    Region:          ${CYAN}${AWS_REGION}${NC}"
echo -e "    Instance Type:   ${CYAN}${INSTANCE_TYPE}${NC}"
echo -e "    Replicas:        ${CYAN}${REPLICAS}${NC}"
echo -e "    GPU Pool:        ${CYAN}${ENABLE_GPU}${NC}"
if [[ "$ENABLE_GPU" == "true" ]]; then
    echo -e "    GPU Instance:    ${CYAN}${GPU_INSTANCE_TYPE}${NC}"
    echo -e "    GPU Replicas:    ${CYAN}${GPU_REPLICAS}${NC}"
fi
echo -e "    S3 Bucket:       ${CYAN}${ENABLE_BUCKET}${NC}"
echo -e "    Dry Run:         ${CYAN}${DRY_RUN}${NC}"
echo ""

# Check if cluster already exists
if [[ "$DRY_RUN" == "false" ]]; then
    EXISTING_CLUSTER=$(rosa list clusters -o json 2>/dev/null | \
        jq -r --arg name "$CLUSTER_NAME" '.[] | select(.name==$name) | .state' || echo "")
    if [[ -n "$EXISTING_CLUSTER" ]]; then
        if [[ "$EXISTING_CLUSTER" == "ready" ]]; then
            log_warn "Cluster '${CLUSTER_NAME}' already exists and is ready. Skipping creation."
        elif [[ "$EXISTING_CLUSTER" == "installing" || "$EXISTING_CLUSTER" == "pending" ]]; then
            log_warn "Cluster '${CLUSTER_NAME}' is already being created (state: ${EXISTING_CLUSTER}). Skipping to wait."
        else
            log_warn "Cluster '${CLUSTER_NAME}' exists in state: ${EXISTING_CLUSTER}"
        fi
    fi
fi

# Build rosa create command
ROSA_CREATE_ARGS=(
    rosa create cluster
    --cluster-name "$CLUSTER_NAME"
    --sts --mode=auto
    --region "$AWS_REGION"
    --compute-machine-type "$INSTANCE_TYPE"
    --replicas "$REPLICAS"
    --yes
)

if [[ -n "$OCP_VERSION" ]]; then
    ROSA_CREATE_ARGS+=(--version "$OCP_VERSION")
fi

# Only create if cluster doesn't exist
if [[ "$DRY_RUN" == "true" ]] || [[ -z "${EXISTING_CLUSTER:-}" ]]; then
    run_cmd "Creating ROSA Classic cluster '${CLUSTER_NAME}'" "${ROSA_CREATE_ARGS[@]}"
else
    log_info "Cluster already exists, proceeding to next step"
fi

# =============================================================================
# Step 3: Wait for Cluster Ready
# =============================================================================

log_step "Step 3/9: Waiting for Cluster to be Ready"

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} Would poll 'rosa describe cluster' until state=ready (~35-45 min)"
else
    log_info "This typically takes 35-45 minutes. Polling every 60 seconds..."
    WAIT_START=$(date +%s)
    POLL_INTERVAL=60
    MAX_WAIT=5400  # 90 minutes

    while true; do
        CLUSTER_STATE=$(rosa describe cluster --cluster "$CLUSTER_NAME" -o json 2>/dev/null | \
            jq -r '.state' || echo "unknown")

        ELAPSED=$(( $(date +%s) - WAIT_START ))
        ELAPSED_MIN=$(( ELAPSED / 60 ))

        case "$CLUSTER_STATE" in
            ready)
                log_success "Cluster '${CLUSTER_NAME}' is ready! (${ELAPSED_MIN} minutes)"
                break
                ;;
            error)
                log_error "Cluster creation failed. Check: rosa describe cluster --cluster ${CLUSTER_NAME}"
                rosa logs install --cluster "$CLUSTER_NAME" --tail 20 2>/dev/null || true
                exit 1
                ;;
            uninstalling)
                log_error "Cluster is being deleted."
                exit 1
                ;;
            *)
                if [[ $ELAPSED -ge $MAX_WAIT ]]; then
                    log_error "Timed out after ${ELAPSED_MIN} minutes. State: ${CLUSTER_STATE}"
                    log_info "Check status: rosa describe cluster --cluster ${CLUSTER_NAME}"
                    exit 1
                fi
                echo -ne "\r  State: ${YELLOW}${CLUSTER_STATE}${NC} | Elapsed: ${ELAPSED_MIN}m | Next check in ${POLL_INTERVAL}s   "
                sleep "$POLL_INTERVAL"
                ;;
        esac
    done
fi

# =============================================================================
# Step 4: Create Cluster-Admin User
# =============================================================================

log_step "Step 4/9: Creating Cluster-Admin User"

ADMIN_USER=""
ADMIN_PASS=""
API_URL=""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} Would run: rosa create admin --cluster ${CLUSTER_NAME}"
else
    # Check if admin already exists
    ADMIN_OUTPUT=$(rosa create admin --cluster "$CLUSTER_NAME" 2>&1 || true)

    if echo "$ADMIN_OUTPUT" | grep -q "already has an admin"; then
        log_warn "Cluster admin already exists."
        log_info "If you lost the password, delete and recreate:"
        log_info "  rosa delete admin --cluster ${CLUSTER_NAME} --yes"
        log_info "  rosa create admin --cluster ${CLUSTER_NAME}"

        API_URL=$(rosa describe cluster --cluster "$CLUSTER_NAME" -o json 2>/dev/null | \
            jq -r '.api.url' || echo "")
    else
        # Parse credentials from output
        ADMIN_PASS=$(echo "$ADMIN_OUTPUT" | grep -oP '(?<=--password )\S+' || echo "")
        API_URL=$(echo "$ADMIN_OUTPUT" | grep -oP '(?<=--server )\S+' || echo "")
        ADMIN_USER="cluster-admin"

        if [[ -n "$ADMIN_PASS" ]]; then
            log_success "Cluster admin created"
            echo ""
            echo -e "  ${BOLD}Admin Credentials:${NC}"
            echo -e "    Username:  ${CYAN}cluster-admin${NC}"
            echo -e "    Password:  ${CYAN}${ADMIN_PASS}${NC}"
            echo -e "    API URL:   ${CYAN}${API_URL}${NC}"
            echo ""
            log_warn "Save these credentials -- the password cannot be retrieved later!"
        else
            log_warn "Could not parse admin credentials from output:"
            echo "$ADMIN_OUTPUT"
        fi
    fi

    # Get API URL if not parsed from admin output
    if [[ -z "$API_URL" ]]; then
        API_URL=$(rosa describe cluster --cluster "$CLUSTER_NAME" -o json 2>/dev/null | \
            jq -r '.api.url' || echo "")
    fi
fi

# =============================================================================
# Step 5: Add GPU Machine Pool (Optional)
# =============================================================================

log_step "Step 5/9: GPU Machine Pool"

if [[ "$ENABLE_GPU" == "false" ]]; then
    log_info "GPU machine pool disabled (--no-gpu). Skipping."
else
    GPU_POOL_NAME="gpu-workers"

    if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd "Adding GPU machine pool '${GPU_POOL_NAME}'" \
            rosa create machinepool \
            --cluster "$CLUSTER_NAME" \
            --name "$GPU_POOL_NAME" \
            --instance-type "$GPU_INSTANCE_TYPE" \
            --replicas "$GPU_REPLICAS" \
            --labels "nvidia.com/gpu.present=true" \
            --taints "nvidia.com/gpu=True:NoSchedule"
    else
        # Check if GPU pool already exists
        EXISTING_GPU=$(rosa list machinepools --cluster "$CLUSTER_NAME" -o json 2>/dev/null | \
            jq -r --arg name "$GPU_POOL_NAME" '.[] | select(.id==$name) | .id' || echo "")

        if [[ -n "$EXISTING_GPU" ]]; then
            log_warn "GPU machine pool '${GPU_POOL_NAME}' already exists. Skipping."
            rosa list machinepools --cluster "$CLUSTER_NAME" 2>/dev/null || true
        else
            log_info "Creating GPU machine pool: ${GPU_INSTANCE_TYPE} x${GPU_REPLICAS}"
            rosa create machinepool \
                --cluster "$CLUSTER_NAME" \
                --name "$GPU_POOL_NAME" \
                --instance-type "$GPU_INSTANCE_TYPE" \
                --replicas "$GPU_REPLICAS" \
                --labels "nvidia.com/gpu.present=true" \
                --taints "nvidia.com/gpu=True:NoSchedule" \
                --yes

            log_success "GPU machine pool '${GPU_POOL_NAME}' created"
            log_info "GPU nodes may take 5-10 minutes to provision"
        fi
    fi
fi

# =============================================================================
# Step 6: Create S3 Bucket
# =============================================================================

log_step "Step 6/9: S3 Model Storage Bucket"

BUCKET_NAME=""

if [[ "$ENABLE_BUCKET" == "false" ]]; then
    log_info "S3 bucket creation disabled (--no-bucket). Skipping."
else
    # Generate unique bucket name using cluster ID
    if [[ "$DRY_RUN" == "true" ]]; then
        CLUSTER_ID_SHORT="XXXXXXXX"
    else
        CLUSTER_ID_SHORT=$(rosa describe cluster --cluster "$CLUSTER_NAME" -o json 2>/dev/null | \
            jq -r '.id' | cut -c1-8 || echo "unknown")
    fi

    BUCKET_NAME="${BUCKET_PREFIX}-${CLUSTER_ID_SHORT}"

    if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd "Creating S3 bucket '${BUCKET_NAME}'" \
            aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
    else
        # Check if bucket already exists
        if aws s3 ls "s3://${BUCKET_NAME}" &>/dev/null 2>&1; then
            log_warn "S3 bucket '${BUCKET_NAME}' already exists. Skipping."
        else
            log_info "Creating S3 bucket: ${BUCKET_NAME}"

            if [[ "$AWS_REGION" == "us-east-1" ]]; then
                aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
            else
                aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION" \
                    --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
            fi

            # Enable versioning for model artifact safety
            aws s3api put-bucket-versioning \
                --bucket "$BUCKET_NAME" \
                --versioning-configuration Status=Enabled \
                --region "$AWS_REGION"

            # Block public access
            aws s3api put-public-access-block \
                --bucket "$BUCKET_NAME" \
                --public-access-block-configuration \
                    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
                --region "$AWS_REGION"

            log_success "S3 bucket '${BUCKET_NAME}' created with versioning and public access blocked"
        fi
    fi
fi

# =============================================================================
# Step 7: Create S3 IAM Credentials
# =============================================================================

log_step "Step 7/9: S3 IAM Credentials"

S3_ACCESS_KEY_ID=""
S3_SECRET_ACCESS_KEY=""

if [[ "$ENABLE_BUCKET" == "false" ]] || [[ -z "${BUCKET_NAME}" ]]; then
    log_info "No S3 bucket configured. Skipping IAM credential creation."
else
    IAM_USER="${CLUSTER_NAME}-s3-access"
    IAM_POLICY_NAME="${CLUSTER_NAME}-s3-policy"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would create IAM user '${IAM_USER}' with S3 access to '${BUCKET_NAME}'"
    else
        # Check if user already exists
        if aws iam get-user --user-name "$IAM_USER" &>/dev/null 2>&1; then
            log_warn "IAM user '${IAM_USER}' already exists."
            # Check for existing access keys
            EXISTING_KEY=$(aws iam list-access-keys --user-name "$IAM_USER" \
                --query 'AccessKeyMetadata[0].AccessKeyId' --output text 2>/dev/null || echo "")
            if [[ -n "$EXISTING_KEY" && "$EXISTING_KEY" != "None" ]]; then
                log_info "Using existing access key: ${EXISTING_KEY}"
                S3_ACCESS_KEY_ID="$EXISTING_KEY"
                log_warn "Cannot retrieve existing secret key. If needed, delete and recreate:"
                echo -e "  ${CYAN}aws iam delete-access-key --user-name ${IAM_USER} --access-key-id ${EXISTING_KEY}${NC}"
                echo -e "  ${CYAN}Re-run this script to generate a new key${NC}"
            fi
        else
            log_info "Creating IAM user: ${IAM_USER}"
            aws iam create-user --user-name "$IAM_USER" >/dev/null 2>&1

            # Create scoped IAM policy
            POLICY_DOC=$(cat <<POLICYEOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    }
  ]
}
POLICYEOF
)

            POLICY_ARN=$(aws iam create-policy \
                --policy-name "$IAM_POLICY_NAME" \
                --policy-document "$POLICY_DOC" \
                --query 'Policy.Arn' --output text 2>/dev/null || echo "")

            if [[ -z "$POLICY_ARN" ]]; then
                # Policy may already exist
                AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
                POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"
            fi

            aws iam attach-user-policy --user-name "$IAM_USER" --policy-arn "$POLICY_ARN" 2>/dev/null || true

            log_success "IAM user '${IAM_USER}' created with S3 policy"
        fi

        # Create access key if we don't have one
        if [[ -z "$S3_ACCESS_KEY_ID" ]]; then
            KEY_OUTPUT=$(aws iam create-access-key --user-name "$IAM_USER" 2>/dev/null || echo "")
            if [[ -n "$KEY_OUTPUT" ]]; then
                S3_ACCESS_KEY_ID=$(echo "$KEY_OUTPUT" | jq -r '.AccessKey.AccessKeyId')
                S3_SECRET_ACCESS_KEY=$(echo "$KEY_OUTPUT" | jq -r '.AccessKey.SecretAccessKey')
                log_success "Access key created: ${S3_ACCESS_KEY_ID}"
            else
                log_warn "Could not create access key. IAM user may already have 2 keys (max)."
            fi
        fi
    fi
fi

# =============================================================================
# Step 8: Log Into Cluster
# =============================================================================

log_step "Step 8/9: Logging Into Cluster"

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} Would run: oc login <api-url> --username cluster-admin --password <password>"
else
    if [[ -n "$ADMIN_PASS" ]] && [[ -n "$API_URL" ]]; then
        log_info "Waiting 60 seconds for OAuth server to initialize..."
        sleep 60

        MAX_LOGIN_ATTEMPTS=5
        LOGIN_ATTEMPT=0
        LOGIN_SUCCESS=false

        while [[ $LOGIN_ATTEMPT -lt $MAX_LOGIN_ATTEMPTS ]]; do
            LOGIN_ATTEMPT=$((LOGIN_ATTEMPT + 1))
            log_info "Login attempt ${LOGIN_ATTEMPT}/${MAX_LOGIN_ATTEMPTS}..."

            if oc login "$API_URL" \
                --username cluster-admin \
                --password "$ADMIN_PASS" \
                --insecure-skip-tls-verify=true 2>/dev/null; then
                LOGIN_SUCCESS=true
                break
            fi

            if [[ $LOGIN_ATTEMPT -lt $MAX_LOGIN_ATTEMPTS ]]; then
                log_warn "Login not ready yet. Waiting 30 seconds..."
                sleep 30
            fi
        done

        if [[ "$LOGIN_SUCCESS" == "true" ]]; then
            log_success "Logged into cluster as cluster-admin"
            oc whoami 2>/dev/null || true
        else
            log_warn "Could not log in automatically. The OAuth server may need more time."
            log_info "Log in manually:"
            echo -e "  ${CYAN}oc login ${API_URL} --username cluster-admin --password ${ADMIN_PASS}${NC}"
        fi
    else
        log_warn "Admin credentials not available for automatic login."
        if [[ -n "$API_URL" ]]; then
            log_info "Log in manually:"
            echo -e "  ${CYAN}oc login ${API_URL} --username cluster-admin --password <your-password>${NC}"
        fi
    fi
fi

# =============================================================================
# Step 8.5: Inject S3 Credentials into values-hub.yaml
# =============================================================================

if [[ "$INJECT_CREDS" == "true" ]] && [[ -n "$S3_ACCESS_KEY_ID" ]] && [[ -n "$S3_SECRET_ACCESS_KEY" ]]; then
    VALUES_HUB="values-hub.yaml"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    VALUES_HUB_PATH="${REPO_ROOT}/${VALUES_HUB}"

    if [[ -f "$VALUES_HUB_PATH" ]]; then
        log_step "Injecting S3 credentials into ${VALUES_HUB}"

        if command -v yq &>/dev/null; then
            yq -i ".objectStore.aws.accessKeyId = \"${S3_ACCESS_KEY_ID}\"" "$VALUES_HUB_PATH"
            yq -i ".objectStore.aws.secretAccessKey = \"${S3_SECRET_ACCESS_KEY}\"" "$VALUES_HUB_PATH"
            if [[ -n "${BUCKET_NAME:-}" ]]; then
                yq -i ".objectStore.aws.bucketName = \"${BUCKET_NAME}\"" "$VALUES_HUB_PATH"
            fi
            if [[ -n "${REGION:-}" ]]; then
                yq -i ".objectStore.aws.region = \"${REGION}\"" "$VALUES_HUB_PATH"
            fi
            log_success "S3 credentials written to ${VALUES_HUB}"
            log_warn "${VALUES_HUB} is gitignored — credentials will NOT be committed."
        else
            log_warn "yq not found. Skipping credential injection."
            log_info "Manually add S3 credentials to ${VALUES_HUB}:"
            echo -e "  ${CYAN}objectStore.aws.accessKeyId: ${S3_ACCESS_KEY_ID}${NC}"
            echo -e "  ${CYAN}objectStore.aws.secretAccessKey: ****${NC}"
        fi
    else
        log_warn "${VALUES_HUB} not found at ${VALUES_HUB_PATH}. Skipping credential injection."
        log_info "After creating ${VALUES_HUB}, set the S3 credentials manually."
    fi
elif [[ "$INJECT_CREDS" == "false" ]]; then
    log_info "Credential injection skipped (--no-inject-creds)."
fi

# =============================================================================
# Step 8: Summary and Next Steps
# =============================================================================

log_step "Step 9/9: Summary"

echo ""
echo -e "${GREEN}${BOLD}ROSA Cluster Provisioning Complete${NC}"
echo ""
echo -e "  ${BOLD}Cluster:${NC}"
echo -e "    Name:            ${CYAN}${CLUSTER_NAME}${NC}"
echo -e "    Region:          ${CYAN}${AWS_REGION}${NC}"
echo -e "    Workers:         ${CYAN}${REPLICAS}x ${INSTANCE_TYPE}${NC}"
if [[ "$ENABLE_GPU" == "true" ]]; then
    echo -e "    GPU Pool:        ${CYAN}${GPU_REPLICAS}x ${GPU_INSTANCE_TYPE}${NC}"
fi
if [[ -n "${BUCKET_NAME:-}" ]]; then
    echo -e "    S3 Bucket:       ${CYAN}${BUCKET_NAME}${NC}"
fi
if [[ -n "${S3_ACCESS_KEY_ID:-}" ]]; then
    echo -e "    S3 Access Key:   ${CYAN}${S3_ACCESS_KEY_ID}${NC}"
fi
if [[ -n "${API_URL:-}" ]]; then
    echo -e "    API URL:         ${CYAN}${API_URL}${NC}"
fi
echo ""
echo -e "  ${BOLD}Next Steps:${NC}"
echo ""
echo -e "    ${CYAN}1.${NC} Clone and configure your fork:"
echo -e "       git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git"
echo -e "       cd openshift-aiops-platform"
echo -e "       cp values-global.yaml.example values-global.yaml"
echo -e "       cp values-hub.yaml.example values-hub.yaml"
echo ""
echo -e "    ${CYAN}2.${NC} Update repoURL in both values files to YOUR fork"
echo ""
if [[ -n "${BUCKET_NAME:-}" ]]; then
    echo -e "    ${CYAN}3.${NC} Set S3 bucket in values-hub.yaml:"
    echo -e "       objectStore:"
    echo -e "         backend: \"aws-s3\""
    echo -e "         aws:"
    echo -e "           region: \"${AWS_REGION}\""
    echo -e "           bucketName: \"${BUCKET_NAME}\""
    if [[ -n "${S3_ACCESS_KEY_ID:-}" && -n "${S3_SECRET_ACCESS_KEY:-}" ]]; then
        echo -e "         accessKey: \"${S3_ACCESS_KEY_ID}\""
        echo -e "         secretKey: \"<see output above>\""
        echo ""
        echo -e "    ${YELLOW}IMPORTANT:${NC} Set S3 credentials in values-hub.yaml (NOT committed to git):"
        echo -e "       objectStore:"
        echo -e "         accessKey: \"${S3_ACCESS_KEY_ID}\""
        echo -e "         secretKey: \"${S3_SECRET_ACCESS_KEY}\""
    fi
    echo ""
    NEXT_STEP=4
    echo -e "    ${CYAN}${NEXT_STEP}.${NC} Deploy the platform:"
else
    echo -e "    ${CYAN}3.${NC} Deploy the platform:"
fi
echo -e "       make show-cluster-info"
echo -e "       make configure-cluster --skip-odf"
echo -e "       make operator-deploy"
echo ""
if [[ "$ENABLE_GPU" == "true" ]]; then
    echo -e "    ${YELLOW}Note:${NC} GPU nodes may still be provisioning. Check with:"
    echo -e "       rosa list machinepools --cluster ${CLUSTER_NAME}"
    echo -e "       oc get nodes -l nvidia.com/gpu.present=true"
    echo ""
fi
echo -e "  ${BOLD}Useful Commands:${NC}"
echo -e "    rosa describe cluster --cluster ${CLUSTER_NAME}"
echo -e "    rosa list machinepools --cluster ${CLUSTER_NAME}"
echo -e "    rosa logs install --cluster ${CLUSTER_NAME}"
echo ""
echo -e "  ${BOLD}Cleanup (when done):${NC}"
echo -e "    rosa delete cluster --cluster ${CLUSTER_NAME} --yes --watch"
if [[ -n "${BUCKET_NAME:-}" ]]; then
    echo -e "    aws s3 rb s3://${BUCKET_NAME} --force --region ${AWS_REGION}"
fi
if [[ -n "${IAM_USER:-}" ]]; then
    echo -e "    aws iam delete-user --user-name ${IAM_USER}  # delete IAM user after detaching policy and keys"
fi
echo ""
