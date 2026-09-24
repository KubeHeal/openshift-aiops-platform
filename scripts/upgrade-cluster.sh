#!/bin/bash
# =============================================================================
# upgrade-cluster.sh
# =============================================================================
# Safely upgrades an OpenShift cluster to a target version (multi-hop) and
# upgrades Red Hat OpenShift AI (RHOAI) to a target channel/version.
# Optionally updates all repository configuration files for compatibility.
#
# Usage:
#   ./scripts/upgrade-cluster.sh [options]
#
# Options:
#   --target-ocp VERSION     Target OCP version (default: 4.22)
#   --target-rhoai CHANNEL   Target RHOAI channel (default: auto-detect)
#   --dry-run                Show what would be done without changes (DEFAULT)
#   --execute                Actually execute the upgrade (disables dry-run)
#   --yes                    Skip manual confirmation prompts
#   --skip-ocp               Skip OCP cluster upgrade
#   --skip-rhoai             Skip RHOAI operator upgrade
#   --skip-config            Skip repository config file updates
#   --fix-cco-manual         If Upgradeable=False due to missing root cloud creds,
#                            switch CCO to Manual mode and annotate for target version
#   --hop-timeout MINUTES    Timeout per upgrade hop in minutes (default: 90)
#   --poll-interval SECONDS  Polling interval during upgrade wait (default: 60)
#   --help                   Show this help message
#
# Prerequisites:
#   - oc CLI installed and logged into cluster as cluster-admin
#   - jq installed
#   - yq installed (for repo config updates)
#   - git (for repo config updates)
#
# Safety Features:
#   - Dry-run mode enabled by default (use --execute to apply)
#   - Pre-flight health checks before every phase
#   - Health gates between each upgrade hop
#   - Manual confirmation prompts (unless --yes)
#   - SNO-aware: retry logic for API unavailability during node reboot
#   - Rollback guidance on failure
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration Defaults
# =============================================================================

TARGET_OCP="${TARGET_OCP:-4.22}"
TARGET_RHOAI="${TARGET_RHOAI:-}"
DRY_RUN="${DRY_RUN:-true}"
AUTO_YES="${AUTO_YES:-false}"
SKIP_OCP="${SKIP_OCP:-false}"
SKIP_RHOAI="${SKIP_RHOAI:-false}"
SKIP_CONFIG="${SKIP_CONFIG:-false}"
FIX_CCO_MANUAL="${FIX_CCO_MANUAL:-false}"
CCO_FIX_NEEDED="${CCO_FIX_NEEDED:-false}"
HOP_TIMEOUT_MINUTES="${HOP_TIMEOUT_MINUTES:-90}"
POLL_INTERVAL="${POLL_INTERVAL:-60}"
SNO_RETRY_INTERVAL="${SNO_RETRY_INTERVAL:-30}"
SNO_RETRY_MAX="${SNO_RETRY_MAX:-60}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# =============================================================================
# Colors and Logging (matches configure-cluster-infrastructure.sh)
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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

log_dry_run() {
    echo -e "${YELLOW}[DRY RUN]${NC} Would execute: $1"
}

show_help() {
    head -40 "$0" | tail -33
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --target-ocp)
                TARGET_OCP="$2"
                shift 2
                ;;
            --target-rhoai)
                TARGET_RHOAI="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --execute)
                DRY_RUN="false"
                shift
                ;;
            --yes|-y)
                AUTO_YES="true"
                shift
                ;;
            --skip-ocp)
                SKIP_OCP="true"
                shift
                ;;
            --skip-rhoai)
                SKIP_RHOAI="true"
                shift
                ;;
            --skip-config)
                SKIP_CONFIG="true"
                shift
                ;;
            --fix-cco-manual)
                FIX_CCO_MANUAL="true"
                shift
                ;;
            --hop-timeout)
                HOP_TIMEOUT_MINUTES="$2"
                shift 2
                ;;
            --poll-interval)
                POLL_INTERVAL="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Utility Functions
# =============================================================================

confirm_prompt() {
    local message="$1"
    if [[ "$AUTO_YES" == "true" ]]; then
        log_info "Auto-confirmed: ${message}"
        return 0
    fi
    echo ""
    echo -e "${BOLD}${message}${NC}"
    read -r -p "Continue? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log_warn "Aborted by user."
            exit 0
            ;;
    esac
}

# Run oc with SNO-aware retry logic (API may be unavailable during node reboot)
oc_retry() {
    local max_retries=${SNO_RETRY_MAX}
    local interval=${SNO_RETRY_INTERVAL}
    local attempt=0
    local result

    while [[ $attempt -lt $max_retries ]]; do
        if result=$(oc "$@" 2>&1); then
            echo "$result"
            return 0
        fi
        if echo "$result" | grep -qiE "connection refused|no route to host|i/o timeout|EOF|TLS handshake timeout"; then
            attempt=$((attempt + 1))
            if [[ $attempt -lt $max_retries ]]; then
                log_warn "API unavailable (attempt ${attempt}/${max_retries}), retrying in ${interval}s..."
                sleep "$interval"
            fi
        else
            echo "$result" >&2
            return 1
        fi
    done
    log_error "API unavailable after ${max_retries} retries."
    return 1
}

# Extract major.minor from a full version string like "4.20.15"
major_minor() {
    echo "$1" | cut -d. -f1-2
}

# Compare two major.minor versions: returns 0 if $1 < $2
version_lt() {
    local a_major a_minor b_major b_minor
    a_major=$(echo "$1" | cut -d. -f1)
    a_minor=$(echo "$1" | cut -d. -f2)
    b_major=$(echo "$2" | cut -d. -f1)
    b_minor=$(echo "$2" | cut -d. -f2)
    if [[ $a_major -lt $b_major ]]; then return 0; fi
    if [[ $a_major -eq $b_major && $a_minor -lt $b_minor ]]; then return 0; fi
    return 1
}

# Compare: returns 0 if $1 == $2 (major.minor)
version_eq() {
    [[ "$(major_minor "$1")" == "$(major_minor "$2")" ]]
}

# =============================================================================
# CCO Manual Mode Fix (--fix-cco-manual)
# =============================================================================
# When the root cloud credential secret (e.g. kube-system/aws-creds) is missing
# or expired, the CCO blocks upgrades with Upgradeable=False / MissingRootCredential.
# Switching CCO to Manual mode tells the operator to stop managing credentials
# and rely on pre-existing (minted) secrets. This clears the upgrade gate.
#
# Works for AWS, Azure, and GCP clusters on OCP 4.18+.
# =============================================================================

fix_cco_manual() {
    log_step "CCO Fix: Switching Cloud Credential Operator to Manual Mode"

    # Check if CCO is already in Manual mode
    local current_mode
    current_mode=$(oc get cloudcredential cluster -o jsonpath='{.spec.credentialsMode}' 2>/dev/null || echo "")

    if [[ "$current_mode" == "Manual" ]]; then
        log_info "CCO is already in Manual mode"
    else
        log_info "Current CCO mode: '${current_mode:-Mint (default)}'"
        log_info "Switching to Manual mode..."

        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "oc patch cloudcredential cluster --type merge -p '{\"spec\":{\"credentialsMode\":\"Manual\"}}'"
        else
            oc patch cloudcredential cluster --type merge \
                -p '{"spec":{"credentialsMode":"Manual"}}' 2>/dev/null
            log_success "CCO patched to Manual mode"
        fi
    fi

    # Verify all CredentialsRequest secrets exist
    log_info "Verifying CredentialsRequest secrets exist..."
    local platform
    platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}' 2>/dev/null || echo "unknown")

    local provider_kind=""
    case "$platform" in
        AWS)   provider_kind="AWSProviderSpec" ;;
        Azure) provider_kind="AzureProviderSpec" ;;
        GCP)   provider_kind="GCPProviderSpec" ;;
        *)     log_warn "Unknown platform '${platform}'; skipping CredentialsRequest verification" ;;
    esac

    if [[ -n "$provider_kind" ]]; then
        local missing=0
        while IFS='|' read -r cr_name ns secret_name; do
            if oc get secret "$secret_name" -n "$ns" &>/dev/null 2>&1; then
                log_success "  ${ns}/${secret_name} exists (CR: ${cr_name})"
            else
                log_error "  ${ns}/${secret_name} MISSING (CR: ${cr_name})"
                missing=$((missing + 1))
            fi
        done < <(oc get credentialsrequest -n openshift-cloud-credential-operator -o json 2>/dev/null | \
            jq -r ".items[] | select(.spec.providerSpec.kind == \"${provider_kind}\") |
                \"\(.metadata.name)|\(.spec.secretRef.namespace)|\(.spec.secretRef.name)\"" 2>/dev/null)

        if [[ $missing -gt 0 ]]; then
            log_error "${missing} CredentialsRequest secret(s) are missing."
            log_error "In Manual mode, YOU must create these secrets before upgrading."
            log_error "Extract requirements with: oc adm release extract --credentials-requests --to=<dir>"
            exit 1
        fi
        log_success "All CredentialsRequest secrets verified"
    fi

    # Add upgradeable-to annotation
    log_info "Adding upgradeable-to annotation for ${TARGET_OCP}..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "oc annotate cloudcredential cluster cloudcredential.openshift.io/upgradeable-to=\"${TARGET_OCP}\" --overwrite"
    else
        oc annotate cloudcredential cluster \
            "cloudcredential.openshift.io/upgradeable-to=${TARGET_OCP}" \
            --overwrite 2>/dev/null
        log_success "Annotation set: upgradeable-to=${TARGET_OCP}"
    fi

    # Wait for Upgradeable condition to clear
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Waiting for Upgradeable condition to clear (up to 3 minutes)..."
        local wait_elapsed=0
        local wait_max=180
        while [[ $wait_elapsed -lt $wait_max ]]; do
            local up_status up_reason
            up_status=$(oc get clusterversion version -o json 2>/dev/null | \
                jq -r '.status.conditions[] | select(.type=="Upgradeable") | .status' 2>/dev/null || echo "")
            up_reason=$(oc get clusterversion version -o json 2>/dev/null | \
                jq -r '.status.conditions[] | select(.type=="Upgradeable") | .reason' 2>/dev/null || echo "")

            if [[ -z "$up_status" || "$up_status" == "True" ]]; then
                log_success "Upgradeable gate cleared!"
                break
            fi

            if (( wait_elapsed % 30 == 0 )); then
                log_info "  Still waiting... Upgradeable=${up_status} (${up_reason}) [${wait_elapsed}s/${wait_max}s]"
            fi
            sleep 10
            wait_elapsed=$((wait_elapsed + 10))
        done

        if [[ $wait_elapsed -ge $wait_max ]]; then
            log_warn "Upgradeable condition did not clear within ${wait_max}s."
            log_warn "Check: oc get clusterversion version -o json | jq '.status.conditions[]'"
            log_warn "The upgrade may still proceed -- some clusters take longer to reconcile."
        fi
    fi

    log_success "CCO Manual mode fix complete"
}

# =============================================================================
# Phase 1: Pre-flight Checks
# =============================================================================

preflight_checks() {
    log_step "Phase 1: Pre-flight Checks"

    # 1. Verify oc is available
    if ! command -v oc &>/dev/null; then
        log_error "'oc' command not found. Please install the OpenShift CLI."
        exit 1
    fi
    log_success "oc CLI found: $(oc version --client 2>/dev/null | head -1)"

    # 2. Verify jq is available
    if ! command -v jq &>/dev/null; then
        log_error "'jq' command not found. Please install jq."
        exit 1
    fi
    log_success "jq found"

    # 3. Verify logged in
    if ! oc whoami &>/dev/null; then
        log_error "Not logged into an OpenShift cluster. Please run 'oc login'."
        exit 1
    fi
    local current_user
    current_user=$(oc whoami 2>/dev/null)
    log_success "Logged in as: ${current_user}"

    # 4. Verify cluster-admin
    if ! oc auth can-i '*' '*' --all-namespaces &>/dev/null; then
        log_error "Current user does not have cluster-admin privileges."
        exit 1
    fi
    log_success "Cluster-admin privileges confirmed"

    # 5. Detect current OCP version
    local cv_json
    cv_json=$(oc get clusterversion version -o json 2>/dev/null)
    CURRENT_OCP_FULL=$(echo "$cv_json" | jq -r '.status.desired.version // "unknown"')
    CURRENT_OCP=$(major_minor "$CURRENT_OCP_FULL")
    CURRENT_CHANNEL=$(echo "$cv_json" | jq -r '.spec.channel // "unknown"')
    log_success "Current OCP version: ${CURRENT_OCP_FULL} (channel: ${CURRENT_CHANNEL})"

    if version_eq "$CURRENT_OCP" "$TARGET_OCP"; then
        log_info "Cluster is already at target major.minor version ${TARGET_OCP}"
        if [[ "$SKIP_OCP" == "false" ]]; then
            log_info "Setting --skip-ocp since cluster is already at ${TARGET_OCP}"
            SKIP_OCP="true"
        fi
    fi

    # 6. Verify no upgrade in progress
    local progressing
    progressing=$(echo "$cv_json" | jq -r '.status.conditions[] | select(.type=="Progressing") | .status')
    if [[ "$progressing" == "True" ]]; then
        log_error "An upgrade is already in progress. Wait for it to complete before starting a new one."
        local progress_msg
        progress_msg=$(echo "$cv_json" | jq -r '.status.conditions[] | select(.type=="Progressing") | .message')
        log_error "Progress: ${progress_msg}"
        exit 1
    fi
    log_success "No upgrade in progress"

    # 7. Check ClusterOperators health
    log_info "Checking ClusterOperator health..."
    local degraded_cos
    degraded_cos=$(oc get clusteroperators -o json 2>/dev/null | jq -r '
        .items[] |
        select(
            (.status.conditions[] | select(.type=="Degraded") | .status) == "True" or
            (.status.conditions[] | select(.type=="Available") | .status) == "False"
        ) | .metadata.name')

    if [[ -n "$degraded_cos" ]]; then
        log_error "The following ClusterOperators are degraded or unavailable:"
        echo "$degraded_cos" | while read -r co; do
            log_error "  - ${co}"
        done
        log_error "Fix these before upgrading."
        exit 1
    fi
    log_success "All ClusterOperators are healthy"

    # 8. Check nodes
    log_info "Checking node health..."
    local not_ready_nodes
    not_ready_nodes=$(oc get nodes -o json 2>/dev/null | jq -r '
        .items[] |
        select(
            (.status.conditions[] | select(.type=="Ready") | .status) != "True"
        ) | .metadata.name')

    if [[ -n "$not_ready_nodes" ]]; then
        log_error "The following nodes are not Ready:"
        echo "$not_ready_nodes" | while read -r node; do
            log_error "  - ${node}"
        done
        exit 1
    fi
    local node_count
    node_count=$(oc get nodes --no-headers 2>/dev/null | wc -l)
    log_success "All ${node_count} node(s) are Ready"

    # 9. Detect cluster topology
    CLUSTER_TOPOLOGY="ha"
    if [[ $node_count -eq 1 ]]; then
        CLUSTER_TOPOLOGY="sno"
    fi
    log_info "Cluster topology: ${CLUSTER_TOPOLOGY}"
    if [[ "$CLUSTER_TOPOLOGY" == "sno" ]]; then
        log_warn "SNO cluster detected. The node will reboot during upgrade."
        log_warn "API will be temporarily unavailable. Script has SNO-aware retry logic."
    fi

    # 10. Check Upgradeable condition (CCO root credential gate)
    log_info "Checking Upgradeable condition..."
    local up_status up_reason
    up_status=$(echo "$cv_json" | jq -r '.status.conditions[] | select(.type=="Upgradeable") | .status // empty')
    up_reason=$(echo "$cv_json" | jq -r '.status.conditions[] | select(.type=="Upgradeable") | .reason // empty')

    if [[ "$up_status" == "False" ]]; then
        log_warn "Cluster reports Upgradeable=False (reason: ${up_reason})"
        if [[ "$up_reason" == "MissingRootCredential" || "$up_reason" == "MissingUpgradeableAnnotation" ]]; then
            if [[ "$FIX_CCO_MANUAL" == "true" ]]; then
                log_info "  --fix-cco-manual specified; will fix after pre-flight checks."
                CCO_FIX_NEEDED="true"
            elif [[ "$SKIP_OCP" == "false" ]]; then
                log_error "  Root cloud credential secret is missing."
                log_error "  The CCO blocks minor version upgrades without it."
                log_error "  Options:"
                log_error "    1. Restore the root secret (e.g. kube-system/aws-creds)"
                log_error "    2. Re-run with --fix-cco-manual to switch CCO to Manual mode"
                log_error "    3. Re-run with --skip-ocp to skip the OCP upgrade"
                exit 1
            fi
        else
            log_warn "  Unexpected reason: ${up_reason}"
            log_warn "  The upgrade may be blocked. Investigate before proceeding."
        fi
    else
        log_success "No Upgradeable blockers"
    fi

    # 11. Check ODF/storage health (non-fatal)
    log_info "Checking storage health..."
    if oc get storagecluster -n openshift-storage &>/dev/null 2>&1; then
        local sc_phase
        sc_phase=$(oc get storagecluster ocs-storagecluster -n openshift-storage -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
        if [[ "$sc_phase" == "Ready" ]]; then
            log_success "ODF StorageCluster is Ready"
        else
            log_warn "ODF StorageCluster phase: ${sc_phase} (may need attention after upgrade)"
        fi
    else
        log_info "No ODF StorageCluster found (storage checks skipped)"
    fi

    # 11. Detect current RHOAI version
    log_info "Checking RHOAI version..."
    CURRENT_RHOAI_CSV=""
    CURRENT_RHOAI_CHANNEL=""
    if oc get subscription rhods-operator -n redhat-ods-operator &>/dev/null 2>&1; then
        CURRENT_RHOAI_CSV=$(oc get csv -n redhat-ods-operator -o json 2>/dev/null | \
            jq -r '.items[] | select(.metadata.name | startswith("rhods-operator")) | .spec.version // "unknown"' | head -1)
        CURRENT_RHOAI_CHANNEL=$(oc get subscription rhods-operator -n redhat-ods-operator -o jsonpath='{.spec.channel}' 2>/dev/null || echo "unknown")
        log_success "Current RHOAI: v${CURRENT_RHOAI_CSV} (channel: ${CURRENT_RHOAI_CHANNEL})"
    else
        log_warn "RHOAI subscription not found in redhat-ods-operator namespace"
        if [[ "$SKIP_RHOAI" == "false" ]]; then
            log_warn "Skipping RHOAI upgrade (operator not installed)"
            SKIP_RHOAI="true"
        fi
    fi

    # 12. Auto-detect RHOAI target channel if not specified
    if [[ -z "$TARGET_RHOAI" && "$SKIP_RHOAI" == "false" ]]; then
        log_info "Auto-detecting available RHOAI channels..."
        local available_channels
        available_channels=$(oc get packagemanifest rhods-operator -n openshift-marketplace -o json 2>/dev/null | \
            jq -r '.status.channels[].name' 2>/dev/null | sort -V || echo "")
        if [[ -n "$available_channels" ]]; then
            log_info "Available RHOAI channels:"
            echo "$available_channels" | while read -r ch; do
                echo "    - ${ch}"
            done
            # Try to find a channel matching "stable-3.5" or "fast-3.5", fall back to latest stable
            if echo "$available_channels" | grep -q "stable-3.5"; then
                TARGET_RHOAI="stable-3.5"
            elif echo "$available_channels" | grep -q "fast-3.5"; then
                TARGET_RHOAI="fast-3.5"
            else
                # Use the latest stable channel available
                TARGET_RHOAI=$(echo "$available_channels" | grep "stable" | tail -1)
                if [[ -z "$TARGET_RHOAI" ]]; then
                    TARGET_RHOAI=$(echo "$available_channels" | tail -1)
                fi
            fi
            log_info "Selected RHOAI target channel: ${TARGET_RHOAI}"
        else
            log_warn "Could not detect RHOAI channels. Using 'stable' as default."
            TARGET_RHOAI="stable"
        fi
    fi

    # Summary
    echo ""
    log_step "Upgrade Plan Summary"
    echo -e "  ${BOLD}Current OCP version:${NC}  ${CURRENT_OCP_FULL} (${CURRENT_CHANNEL})"
    echo -e "  ${BOLD}Target OCP version:${NC}   ${TARGET_OCP}"
    echo -e "  ${BOLD}Current RHOAI:${NC}        v${CURRENT_RHOAI_CSV:-N/A} (${CURRENT_RHOAI_CHANNEL:-N/A})"
    echo -e "  ${BOLD}Target RHOAI channel:${NC} ${TARGET_RHOAI:-N/A}"
    echo -e "  ${BOLD}Cluster topology:${NC}     ${CLUSTER_TOPOLOGY}"
    echo -e "  ${BOLD}Dry-run mode:${NC}         ${DRY_RUN}"
    echo ""
    echo -e "  ${BOLD}Phases to execute:${NC}"
    if [[ "$SKIP_OCP" == "true" ]]; then
        echo -e "    OCP Upgrade:    ${YELLOW}SKIPPED${NC}"
    else
        echo -e "    OCP Upgrade:    ${GREEN}ENABLED${NC} (multi-hop to ${TARGET_OCP})"
    fi
    if [[ "$SKIP_RHOAI" == "true" ]]; then
        echo -e "    RHOAI Upgrade:  ${YELLOW}SKIPPED${NC}"
    else
        echo -e "    RHOAI Upgrade:  ${GREEN}ENABLED${NC} (channel: ${TARGET_RHOAI})"
    fi
    if [[ "$SKIP_CONFIG" == "true" ]]; then
        echo -e "    Config Updates: ${YELLOW}SKIPPED${NC}"
    else
        echo -e "    Config Updates: ${GREEN}ENABLED${NC}"
    fi
    if [[ "$CCO_FIX_NEEDED" == "true" ]]; then
        echo -e "    CCO Fix:        ${GREEN}ENABLED${NC} (switch to Manual mode)"
    fi
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY-RUN MODE: No changes will be made. Use --execute to apply."
    fi

    confirm_prompt "Proceed with upgrade?"
}

# =============================================================================
# Phase 2: OCP Multi-Hop Upgrade
# =============================================================================

build_upgrade_path() {
    local current="$1"
    local target="$2"

    UPGRADE_HOPS=()
    local cur_major cur_minor tgt_major tgt_minor
    cur_major=$(echo "$current" | cut -d. -f1)
    cur_minor=$(echo "$current" | cut -d. -f2)
    tgt_major=$(echo "$target" | cut -d. -f1)
    tgt_minor=$(echo "$target" | cut -d. -f2)

    local next_minor=$((cur_minor + 1))
    while [[ $next_minor -le $tgt_minor && $cur_major -eq $tgt_major ]]; do
        UPGRADE_HOPS+=("${cur_major}.${next_minor}")
        next_minor=$((next_minor + 1))
    done

    if [[ ${#UPGRADE_HOPS[@]} -eq 0 ]]; then
        log_info "No upgrade hops needed (already at target or same minor version)."
    else
        log_info "Upgrade path: ${CURRENT_OCP} -> $(IFS=' -> '; echo "${UPGRADE_HOPS[*]}")"
    fi
}

wait_for_upgrade_completion() {
    local target_minor="$1"
    local timeout_seconds=$(( HOP_TIMEOUT_MINUTES * 60 ))
    local elapsed=0
    local last_status=""

    log_info "Waiting for upgrade to ${target_minor}.x to complete (timeout: ${HOP_TIMEOUT_MINUTES}m)..."

    while [[ $elapsed -lt $timeout_seconds ]]; do
        local cv_json version state progress_pct message
        cv_json=$(oc_retry get clusterversion version -o json 2>/dev/null || echo "{}")

        version=$(echo "$cv_json" | jq -r '.status.desired.version // "unknown"' 2>/dev/null || echo "unknown")
        state=$(echo "$cv_json" | jq -r '.status.history[0].state // "unknown"' 2>/dev/null || echo "unknown")
        message=$(echo "$cv_json" | jq -r '.status.conditions[] | select(.type=="Progressing") | .message // ""' 2>/dev/null || echo "")

        local current_status="version=${version} state=${state}"
        if [[ "$current_status" != "$last_status" ]]; then
            log_info "Status: ${version} - ${state}"
            if [[ -n "$message" ]]; then
                log_info "  ${message}"
            fi
            last_status="$current_status"
        fi

        if [[ "$state" == "Completed" ]] && [[ "$(major_minor "$version")" == "$target_minor" ]]; then
            log_success "Upgrade to ${version} completed successfully!"
            return 0
        fi

        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))

        # Progress indicator every 5 minutes
        if (( elapsed % 300 == 0 )); then
            local minutes=$((elapsed / 60))
            log_info "Still waiting... (${minutes}m / ${HOP_TIMEOUT_MINUTES}m)"
        fi
    done

    log_error "Upgrade timed out after ${HOP_TIMEOUT_MINUTES} minutes."
    log_error "The upgrade may still be in progress. Check with: oc get clusterversion"
    return 1
}

post_hop_validation() {
    local target_minor="$1"
    log_info "Running post-hop validation for ${target_minor}..."

    # Wait a moment for things to stabilize
    sleep 30

    # Verify version
    local current_version
    current_version=$(oc_retry get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
    if [[ "$(major_minor "$current_version")" != "$target_minor" ]]; then
        log_error "Expected version ${target_minor}.x but got ${current_version}"
        return 1
    fi
    log_success "Version confirmed: ${current_version}"

    # Wait for ClusterOperators to stabilize (may take a few minutes after upgrade)
    log_info "Waiting for ClusterOperators to stabilize..."
    local co_wait=0
    local co_max_wait=600
    while [[ $co_wait -lt $co_max_wait ]]; do
        local degraded_count
        degraded_count=$(oc_retry get clusteroperators -o json 2>/dev/null | jq '[
            .items[] |
            select(
                (.status.conditions[] | select(.type=="Degraded") | .status) == "True" or
                (.status.conditions[] | select(.type=="Available") | .status) == "False" or
                (.status.conditions[] | select(.type=="Progressing") | .status) == "True"
            )
        ] | length' 2>/dev/null || echo "99")

        if [[ "$degraded_count" == "0" ]]; then
            log_success "All ClusterOperators are healthy and stable"
            break
        fi

        if (( co_wait % 60 == 0 )); then
            log_info "Waiting for ${degraded_count} ClusterOperator(s) to stabilize... (${co_wait}s / ${co_max_wait}s)"
        fi
        sleep 15
        co_wait=$((co_wait + 15))
    done

    if [[ $co_wait -ge $co_max_wait ]]; then
        log_warn "Some ClusterOperators may still be settling. Listing status:"
        oc_retry get clusteroperators 2>/dev/null || true
    fi

    # Verify nodes
    local not_ready
    not_ready=$(oc_retry get nodes -o json 2>/dev/null | jq -r '
        .items[] |
        select((.status.conditions[] | select(.type=="Ready") | .status) != "True") |
        .metadata.name' 2>/dev/null || echo "")
    if [[ -n "$not_ready" ]]; then
        log_warn "Some nodes are not Ready (may still be rebooting):"
        echo "$not_ready" | while read -r n; do log_warn "  - ${n}"; done
    else
        log_success "All nodes are Ready"
    fi

    return 0
}

ocp_upgrade() {
    if [[ "$SKIP_OCP" == "true" ]]; then
        log_step "Phase 2: OCP Upgrade (SKIPPED)"
        return 0
    fi

    log_step "Phase 2: OCP Multi-Hop Upgrade"

    build_upgrade_path "$CURRENT_OCP" "$TARGET_OCP"

    if [[ ${#UPGRADE_HOPS[@]} -eq 0 ]]; then
        log_success "No OCP upgrade hops required."
        return 0
    fi

    local hop_num=0
    for target_minor in "${UPGRADE_HOPS[@]}"; do
        hop_num=$((hop_num + 1))
        echo ""
        log_step "Upgrade Hop ${hop_num}/${#UPGRADE_HOPS[@]}: -> ${target_minor}"

        local target_channel="stable-${target_minor}"

        # Step 1: Set channel
        log_info "Setting cluster channel to '${target_channel}'..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "oc patch clusterversion version --type merge -p '{\"spec\":{\"channel\":\"${target_channel}\"}}'"
        else
            oc patch clusterversion version --type merge \
                -p "{\"spec\":{\"channel\":\"${target_channel}\"}}" 2>/dev/null
            log_success "Channel set to ${target_channel}"
            sleep 10
        fi

        # Step 2: Check available updates
        log_info "Querying available updates..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "oc adm upgrade"
            log_info "(In dry-run mode, cannot verify available updates)"
        else
            local upgrade_output
            upgrade_output=$(oc adm upgrade 2>&1 || true)
            echo "$upgrade_output"

            if echo "$upgrade_output" | grep -qi "no updates available"; then
                log_error "No updates available on channel ${target_channel}."
                log_error "The target version may not yet be released or may require an EUS channel."
                log_error "Check: https://access.redhat.com/labs/ocpupgradegraph/update_channel"
                exit 1
            fi
        fi

        # Step 3: Confirm
        confirm_prompt "Trigger upgrade to ${target_minor} (hop ${hop_num}/${#UPGRADE_HOPS[@]})?"

        # Step 4: Trigger upgrade
        log_info "Triggering upgrade to latest ${target_minor}.x..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "oc adm upgrade --to-latest"
        else
            local upgrade_result
            upgrade_result=$(oc adm upgrade --to-latest 2>&1 || true)
            echo "$upgrade_result"

            if echo "$upgrade_result" | grep -qi "error"; then
                log_error "Failed to trigger upgrade. See output above."
                log_error "You may need to specify an exact version with: oc adm upgrade --to=<version>"
                exit 1
            fi
            log_success "Upgrade triggered"
        fi

        # Step 5: Wait for completion
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would wait up to ${HOP_TIMEOUT_MINUTES}m for upgrade completion"
        else
            if ! wait_for_upgrade_completion "$target_minor"; then
                log_error "Upgrade hop to ${target_minor} failed or timed out."
                log_error "Check cluster status: oc get clusterversion; oc get clusteroperators"
                exit 1
            fi
        fi

        # Step 6: Post-hop validation
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would run post-hop validation"
        else
            if ! post_hop_validation "$target_minor"; then
                log_warn "Post-hop validation had issues. Review before continuing."
                confirm_prompt "Continue to next hop despite warnings?"
            fi
        fi

        # Step 7: Prompt before next hop
        if [[ $hop_num -lt ${#UPGRADE_HOPS[@]} ]]; then
            confirm_prompt "Proceed to next upgrade hop?"
        fi
    done

    log_success "OCP upgrade path complete!"
}

# =============================================================================
# Phase 3: RHOAI Upgrade
# =============================================================================

rhoai_upgrade() {
    if [[ "$SKIP_RHOAI" == "true" ]]; then
        log_step "Phase 3: RHOAI Upgrade (SKIPPED)"
        return 0
    fi

    log_step "Phase 3: RHOAI Upgrade to channel '${TARGET_RHOAI}'"

    # Check current state
    local current_channel
    current_channel=$(oc get subscription rhods-operator -n redhat-ods-operator \
        -o jsonpath='{.spec.channel}' 2>/dev/null || echo "unknown")

    if [[ "$current_channel" == "$TARGET_RHOAI" ]]; then
        log_info "RHOAI subscription is already on channel '${TARGET_RHOAI}'"
        log_info "Checking if a newer CSV is available on this channel..."
    else
        log_info "Current RHOAI channel: ${current_channel}"
        log_info "Target RHOAI channel:  ${TARGET_RHOAI}"
    fi

    confirm_prompt "Upgrade RHOAI to channel '${TARGET_RHOAI}'?"

    # Patch subscription channel
    log_info "Patching RHOAI subscription channel to '${TARGET_RHOAI}'..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "oc patch subscription rhods-operator -n redhat-ods-operator --type merge -p '{\"spec\":{\"channel\":\"${TARGET_RHOAI}\"}}'"
    else
        oc patch subscription rhods-operator -n redhat-ods-operator \
            --type merge -p "{\"spec\":{\"channel\":\"${TARGET_RHOAI}\"}}" 2>/dev/null
        log_success "Subscription channel updated to '${TARGET_RHOAI}'"
    fi

    # Wait for new CSV
    log_info "Waiting for RHOAI operator to update..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Would wait for new CSV to reach 'Succeeded' phase"
    else
        local csv_wait=0
        local csv_max_wait=900
        local target_csv_ready=false

        while [[ $csv_wait -lt $csv_max_wait ]]; do
            # Check for pending InstallPlans
            local pending_ip
            pending_ip=$(oc get installplan -n redhat-ods-operator -o json 2>/dev/null | \
                jq -r '.items[] | select(.spec.approved==false) | .metadata.name' 2>/dev/null || echo "")
            if [[ -n "$pending_ip" ]]; then
                log_info "Auto-approving InstallPlan: ${pending_ip}"
                oc patch installplan "$pending_ip" -n redhat-ods-operator \
                    --type merge -p '{"spec":{"approved":true}}' 2>/dev/null || true
            fi

            # Check CSV status
            local csv_phase
            csv_phase=$(oc get csv -n redhat-ods-operator -o json 2>/dev/null | \
                jq -r '.items[] | select(.metadata.name | startswith("rhods-operator")) | .status.phase // "unknown"' 2>/dev/null | head -1 || echo "unknown")

            if [[ "$csv_phase" == "Succeeded" ]]; then
                local new_csv_version
                new_csv_version=$(oc get csv -n redhat-ods-operator -o json 2>/dev/null | \
                    jq -r '.items[] | select(.metadata.name | startswith("rhods-operator")) | .spec.version // "unknown"' 2>/dev/null | head -1)
                log_success "RHOAI CSV is Succeeded: v${new_csv_version}"
                target_csv_ready=true
                break
            fi

            if (( csv_wait % 60 == 0 )); then
                log_info "RHOAI CSV phase: ${csv_phase} (${csv_wait}s / ${csv_max_wait}s)"
            fi
            sleep 15
            csv_wait=$((csv_wait + 15))
        done

        if [[ "$target_csv_ready" != "true" ]]; then
            log_error "RHOAI CSV did not reach 'Succeeded' within ${csv_max_wait}s."
            log_error "Check: oc get csv -n redhat-ods-operator"
            exit 1
        fi
    fi

    # Verify DataScienceCluster health
    log_info "Verifying DataScienceCluster health..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Would check DataScienceCluster status"
    else
        local dsc_ready=false
        local dsc_wait=0
        local dsc_max_wait=300

        while [[ $dsc_wait -lt $dsc_max_wait ]]; do
            local dsc_phase
            dsc_phase=$(oc get datasciencecluster -o json 2>/dev/null | \
                jq -r '.items[0].status.phase // "unknown"' 2>/dev/null || echo "unknown")

            if [[ "$dsc_phase" == "Ready" ]]; then
                log_success "DataScienceCluster is Ready"
                dsc_ready=true
                break
            fi

            if (( dsc_wait % 60 == 0 )); then
                log_info "DataScienceCluster phase: ${dsc_phase} (${dsc_wait}s / ${dsc_max_wait}s)"
            fi
            sleep 15
            dsc_wait=$((dsc_wait + 15))
        done

        if [[ "$dsc_ready" != "true" ]]; then
            log_warn "DataScienceCluster may still be reconciling. Phase: $(
                oc get datasciencecluster -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo 'unknown'
            )"
        fi
    fi

    log_success "RHOAI upgrade phase complete!"
}

# =============================================================================
# Phase 4: Repository Config Updates
# =============================================================================

update_repo_configs() {
    if [[ "$SKIP_CONFIG" == "true" ]]; then
        log_step "Phase 4: Repository Config Updates (SKIPPED)"
        return 0
    fi

    log_step "Phase 4: Repository Config Updates"

    # Detect actual cluster version after upgrade (or use TARGET_OCP in dry-run)
    local new_version="$TARGET_OCP"
    if [[ "$DRY_RUN" == "false" && "$SKIP_OCP" == "false" ]]; then
        new_version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null | cut -d. -f1-2 || echo "$TARGET_OCP")
    fi

    # Check for required tools
    if ! command -v yq &>/dev/null; then
        log_warn "'yq' not found. Falling back to sed for config updates."
        local USE_SED=true
    else
        local USE_SED=false
    fi

    local files_updated=0

    # --- values-hub.yaml ---
    local values_hub="${REPO_ROOT}/values-hub.yaml"
    if [[ -f "$values_hub" ]]; then
        log_info "Updating ${values_hub} ..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Set cluster.version to '${new_version}' in values-hub.yaml"
            if [[ -n "$TARGET_RHOAI" && "$SKIP_RHOAI" == "false" ]]; then
                log_dry_run "Set openshift-ai subscription channel to '${TARGET_RHOAI}' in values-hub.yaml"
            fi
        else
            if [[ "$USE_SED" == "true" ]]; then
                sed -i "s/^\(  version: \"\)[0-9]\+\.[0-9]\+\(\".*\)/\1${new_version}\2/" "$values_hub"
            else
                yq -i ".cluster.version = \"${new_version}\"" "$values_hub"
            fi
            log_success "Updated cluster.version to '${new_version}'"

            if [[ -n "$TARGET_RHOAI" && "$SKIP_RHOAI" == "false" ]]; then
                if [[ "$USE_SED" == "true" ]]; then
                    sed -i "/openshift-ai:/,/channel:/ s/^\(      channel: \).*/\1${TARGET_RHOAI}/" "$values_hub"
                else
                    yq -i ".clusterGroup.subscriptions.openshift-ai.channel = \"${TARGET_RHOAI}\"" "$values_hub"
                fi
                log_success "Updated RHOAI subscription channel to '${TARGET_RHOAI}'"
            fi
            files_updated=$((files_updated + 1))
        fi
    else
        log_warn "values-hub.yaml not found at ${values_hub}"
    fi

    # --- values-hub.yaml.example ---
    local values_hub_example="${REPO_ROOT}/values-hub.yaml.example"
    if [[ -f "$values_hub_example" ]]; then
        log_info "Updating ${values_hub_example} ..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Set cluster.version to '${new_version}' in values-hub.yaml.example"
        else
            sed -i "s/^\(  version: \"\)[0-9]\+\.[0-9]\+\(\".*\)/\1${new_version}\2/" "$values_hub_example"
            log_success "Updated values-hub.yaml.example"
            files_updated=$((files_updated + 1))
        fi
    fi

    # --- charts/hub/values.yaml ---
    local chart_values="${REPO_ROOT}/charts/hub/values.yaml"
    if [[ -f "$chart_values" ]]; then
        log_info "Updating ${chart_values} ..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Set cluster.version to '${new_version}' in charts/hub/values.yaml"
        else
            if [[ "$USE_SED" == "true" ]]; then
                sed -i "s/^\(  version: \"\)[0-9]\+\.[0-9]\+\(\".*\)/\1${new_version}\2/" "$chart_values"
            else
                yq -i ".cluster.version = \"${new_version}\"" "$chart_values"
            fi
            log_success "Updated charts/hub/values.yaml"
            files_updated=$((files_updated + 1))
        fi
    fi

    # --- pattern-metadata.yaml ---
    local pattern_meta="${REPO_ROOT}/pattern-metadata.yaml"
    if [[ -f "$pattern_meta" ]]; then
        log_info "Updating ${pattern_meta} ..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Set openshift_version to '${new_version}+'"
        else
            sed -i "s/^\(  openshift_version: \"\)[0-9]\+\.[0-9]\+\+\?\(\".*\)/\1${new_version}+\2/" "$pattern_meta"
            log_success "Updated pattern-metadata.yaml"
            files_updated=$((files_updated + 1))
        fi
    fi

    # --- charts/hub/templates/_helpers.tpl ---
    local helpers_tpl="${REPO_ROOT}/charts/hub/templates/_helpers.tpl"
    if [[ -f "$helpers_tpl" ]]; then
        log_info "Updating default version fallbacks in ${helpers_tpl} ..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Update default version fallbacks from '4.20' to '${new_version}'"
        else
            sed -i "s/\.Values\.cluster\.version | default \"4\.[0-9]\+\"/.Values.cluster.version | default \"${new_version}\"/g" "$helpers_tpl"
            log_success "Updated _helpers.tpl default version fallbacks"
            files_updated=$((files_updated + 1))
        fi
    fi

    # --- charts/hub/templates/ai-ml-workbench.yaml ---
    local workbench_yaml="${REPO_ROOT}/charts/hub/templates/ai-ml-workbench.yaml"
    if [[ -f "$workbench_yaml" ]]; then
        log_info "Updating default version in ${workbench_yaml} ..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Update default version from '4.18' to '${new_version}'"
        else
            sed -i "s/\.Values\.cluster\.version | default \"4\.[0-9]\+\"/.Values.cluster.version | default \"${new_version}\"/g" "$workbench_yaml"
            log_success "Updated ai-ml-workbench.yaml default version"
            files_updated=$((files_updated + 1))
        fi
    fi

    # --- ansible/roles/validated_patterns_operator/defaults/main.yml ---
    local vp_defaults="${REPO_ROOT}/ansible/roles/validated_patterns_operator/defaults/main.yml"
    if [[ -f "$vp_defaults" ]]; then
        log_info "Updating minimum OCP version in ${vp_defaults} ..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Update vp_min_openshift_version to '4.20'"
        else
            sed -i 's/^\(vp_min_openshift_version: "\)[0-9]\+\.[0-9]\+\(".*\)/\14.20\2/' "$vp_defaults"
            log_success "Updated vp_min_openshift_version to '4.20'"
            files_updated=$((files_updated + 1))
        fi
    fi

    # --- charts/hub/templates/pre-deployment-validation.yaml ---
    local pre_deploy="${REPO_ROOT}/charts/hub/templates/pre-deployment-validation.yaml"
    if [[ -f "$pre_deploy" ]]; then
        log_info "Updating minimum version check in ${pre_deploy} ..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Update minimum version check from '4.14' to '4.18'"
        else
            sed -i 's/"4\.14"/"4.18"/g' "$pre_deploy"
            log_success "Updated pre-deployment-validation.yaml minimum version to 4.18"
            files_updated=$((files_updated + 1))
        fi
    fi

    # --- Tekton validation default ---
    local tekton_validation="${REPO_ROOT}/charts/hub/templates/tekton-deployment-validation.yaml"
    if [[ -f "$tekton_validation" ]]; then
        log_info "Updating Tekton validation default version in ${tekton_validation} ..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Update default min-cluster-version to '4.20'"
        else
            sed -i 's/default: "4\.18"/default: "4.20"/' "$tekton_validation"
            log_success "Updated Tekton validation default to 4.20"
            files_updated=$((files_updated + 1))
        fi
    fi

    # --- scripts/install-prerequisites-rhel.sh ---
    local prereqs_script="${REPO_ROOT}/scripts/install-prerequisites-rhel.sh"
    if [[ -f "$prereqs_script" ]]; then
        log_info "Updating OC_VERSION default in ${prereqs_script} ..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Update OC_VERSION default to '${new_version}'"
        else
            sed -i "s/OC_VERSION=\"\${OC_VERSION:-4\.[0-9]\+}\"/OC_VERSION=\"\${OC_VERSION:-${new_version}}\"/" "$prereqs_script"
            log_success "Updated install-prerequisites-rhel.sh OC_VERSION to ${new_version}"
            files_updated=$((files_updated + 1))
        fi
    fi

    # --- Create Kustomize overlays for new versions ---
    local overlays_base="${REPO_ROOT}/k8s/operators/jupyter-notebook-validator/overlays"
    local reference_overlay="${overlays_base}/dev-ocp4.20/kustomization.yaml"

    if [[ -f "$reference_overlay" ]]; then
        # Build list of missing overlays between current supported and target
        local cur_minor tgt_minor
        cur_minor=20
        tgt_minor=$(echo "$new_version" | cut -d. -f2)

        local next=$((cur_minor + 1))
        while [[ $next -le $tgt_minor ]]; do
            local overlay_dir="${overlays_base}/dev-ocp4.${next}"
            if [[ ! -d "$overlay_dir" ]]; then
                log_info "Creating kustomize overlay: dev-ocp4.${next}"
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_dry_run "mkdir -p ${overlay_dir} && cp ${reference_overlay} ${overlay_dir}/"
                else
                    mkdir -p "$overlay_dir"
                    cp "$reference_overlay" "$overlay_dir/kustomization.yaml"
                    log_success "Created ${overlay_dir}/kustomization.yaml"
                    files_updated=$((files_updated + 1))
                fi
            else
                log_info "Overlay dev-ocp4.${next} already exists"
            fi
            next=$((next + 1))
        done
    else
        log_warn "Reference overlay not found at ${reference_overlay}, skipping overlay creation"
    fi

    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry-run complete. ${files_updated} file(s) would be updated."
    else
        log_success "Repository config updates complete. ${files_updated} file(s) updated."
        log_info "Review changes with: git diff"
        log_info "Commit with: git add -A && git commit -s -m 'feat: upgrade platform to OCP ${new_version} + RHOAI ${TARGET_RHOAI}'"
    fi
}

# =============================================================================
# Phase 5: Post-Upgrade Validation
# =============================================================================

post_upgrade_validation() {
    log_step "Phase 5: Post-Upgrade Validation"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry-run mode: showing what validation would be performed"
        echo ""
        log_dry_run "oc get clusterversion"
        log_dry_run "oc get clusteroperators"
        log_dry_run "oc get csv -A | grep -E 'rhods|gpu|pipelines|gitops|external-secrets'"
        log_dry_run "oc get applications -n self-healing-platform-hub"
        log_dry_run "oc get datasciencecluster"
        log_dry_run "tkn pipeline start deployment-validation-pipeline --showlog"
        echo ""
        log_info "All validation checks would be performed after upgrade."
        return 0
    fi

    local validation_errors=0

    # 1. Verify OCP version
    log_info "1. Checking OCP version..."
    local final_version
    final_version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
    log_success "OCP version: ${final_version}"

    # 2. ClusterOperators
    log_info "2. Checking ClusterOperators..."
    local co_issues
    co_issues=$(oc get clusteroperators -o json 2>/dev/null | jq '[
        .items[] |
        select(
            (.status.conditions[] | select(.type=="Degraded") | .status) == "True" or
            (.status.conditions[] | select(.type=="Available") | .status) == "False"
        ) | .metadata.name
    ]' 2>/dev/null || echo "[]")

    if [[ "$co_issues" == "[]" ]]; then
        log_success "All ClusterOperators healthy"
    else
        log_warn "Some ClusterOperators have issues: ${co_issues}"
        validation_errors=$((validation_errors + 1))
    fi

    # 3. CSV status
    log_info "3. Checking operator CSVs..."
    local failed_csvs
    failed_csvs=$(oc get csv -A --no-headers 2>/dev/null | grep -v "Succeeded" | grep -v "NAMESPACE" || true)
    if [[ -z "$failed_csvs" ]]; then
        log_success "All operator CSVs are Succeeded"
    else
        log_warn "Some CSVs are not in Succeeded state:"
        echo "$failed_csvs"
        validation_errors=$((validation_errors + 1))
    fi

    # 4. ArgoCD applications
    log_info "4. Checking ArgoCD applications..."
    if oc get applications -n self-healing-platform-hub &>/dev/null 2>&1; then
        local unhealthy_apps
        unhealthy_apps=$(oc get applications -n self-healing-platform-hub -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.health.status != "Healthy" or .status.sync.status != "Synced") | .metadata.name' 2>/dev/null || echo "")
        if [[ -z "$unhealthy_apps" ]]; then
            log_success "All ArgoCD applications are Healthy and Synced"
        else
            log_warn "Some ArgoCD applications need attention:"
            echo "$unhealthy_apps" | while read -r app; do log_warn "  - ${app}"; done
            validation_errors=$((validation_errors + 1))
        fi
    else
        log_info "No ArgoCD applications found (skipping)"
    fi

    # 5. RHOAI health
    log_info "5. Checking RHOAI health..."
    if oc get datasciencecluster &>/dev/null 2>&1; then
        local dsc_phase
        dsc_phase=$(oc get datasciencecluster -o json 2>/dev/null | \
            jq -r '.items[0].status.phase // "unknown"' 2>/dev/null || echo "unknown")
        if [[ "$dsc_phase" == "Ready" ]]; then
            log_success "DataScienceCluster is Ready"
        else
            log_warn "DataScienceCluster phase: ${dsc_phase}"
            validation_errors=$((validation_errors + 1))
        fi
    else
        log_info "No DataScienceCluster found (skipping)"
    fi

    # Summary
    echo ""
    if [[ $validation_errors -eq 0 ]]; then
        log_success "All post-upgrade validation checks passed!"
    else
        log_warn "${validation_errors} validation issue(s) found. Review the warnings above."
    fi

    echo ""
    log_info "Recommended next steps:"
    echo "  1. Review changes: git diff"
    echo "  2. Run pre-commit checks: pre-commit run --all-files"
    echo "  3. Commit and push config updates"
    echo "  4. Run Tekton validation: tkn pipeline start deployment-validation-pipeline --showlog"
    echo "  5. Verify ArgoCD sync: make argo-healthcheck"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║       OpenShift Cluster + RHOAI Upgrade Script                         ║${NC}"
    echo -e "${BOLD}║       Target: OCP ${TARGET_OCP} + RHOAI ${TARGET_RHOAI:-auto-detect}                           ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}*** DRY-RUN MODE (default) -- no changes will be made ***${NC}"
        echo -e "  ${YELLOW}*** Use --execute to actually perform the upgrade      ***${NC}"
        echo ""
    fi

    # Phase 1: Pre-flight
    preflight_checks

    # Phase 1.5: CCO Manual mode fix (if needed)
    if [[ "$CCO_FIX_NEEDED" == "true" ]]; then
        fix_cco_manual
    fi

    # Phase 2: OCP upgrade
    ocp_upgrade

    # Phase 3: RHOAI upgrade
    rhoai_upgrade

    # Phase 4: Repo config updates
    update_repo_configs

    # Phase 5: Post-upgrade validation
    post_upgrade_validation

    echo ""
    log_success "Upgrade process complete!"
    echo ""
}

parse_args "$@"
main
