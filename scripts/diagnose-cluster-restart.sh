#!/bin/bash

################################################################################
# Cluster Restart Health Diagnostic Script
#
# Purpose: Diagnose root cause of platform health issues after cluster restart
#
# Usage:
#   ./diagnose-cluster-restart.sh --phase pre-restart
#   ./diagnose-cluster-restart.sh --phase post-restart --monitor-duration 600
#   ./diagnose-cluster-restart.sh --phase report
#
# Phases:
#   pre-restart:  Capture baseline state before cluster restart
#   post-restart: Monitor startup sequence and capture failures
#   report:       Generate comprehensive diagnostic report
################################################################################

set -euo pipefail

# Configuration
NAMESPACE="self-healing-platform"
DIAGNOSTICS_DIR="/tmp/cluster-restart-diagnostics"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${DIAGNOSTICS_DIR}/diagnostic-${TIMESTAMP}.log"
MONITOR_DURATION=600  # Default 10 minutes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create diagnostics directory
mkdir -p "${DIAGNOSTICS_DIR}"

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

################################################################################
# Pre-Restart Snapshot Functions
################################################################################

capture_pre_restart_snapshot() {
    log_info "=== Capturing Pre-Restart Baseline Snapshot ==="

    local snapshot_dir="${DIAGNOSTICS_DIR}/pre-restart-${TIMESTAMP}"
    mkdir -p "${snapshot_dir}"

    log_info "Capturing cluster node status..."
    oc get nodes -o wide > "${snapshot_dir}/nodes.txt" 2>&1 || true

    log_info "Capturing all namespaces..."
    oc get namespaces > "${snapshot_dir}/namespaces.txt" 2>&1 || true

    log_info "Capturing platform namespace resources..."
    oc get all -n "${NAMESPACE}" -o wide > "${snapshot_dir}/platform-resources.txt" 2>&1 || true

    log_info "Capturing platform pod status..."
    oc get pods -n "${NAMESPACE}" -o wide > "${snapshot_dir}/platform-pods.txt" 2>&1 || true
    oc get pods -n "${NAMESPACE}" -o yaml > "${snapshot_dir}/platform-pods.yaml" 2>&1 || true

    log_info "Capturing cross-namespace dependencies..."

    # Prometheus
    oc get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o wide > "${snapshot_dir}/prometheus-pods.txt" 2>&1 || true
    oc get svc -n openshift-monitoring -l app.kubernetes.io/name=prometheus > "${snapshot_dir}/prometheus-services.txt" 2>&1 || true

    # ArgoCD
    oc get pods -n openshift-gitops -o wide > "${snapshot_dir}/argocd-pods.txt" 2>&1 || true
    oc get svc -n openshift-gitops > "${snapshot_dir}/argocd-services.txt" 2>&1 || true

    # ODF/NooBaa Storage
    oc get pods -n openshift-storage -o wide > "${snapshot_dir}/storage-pods.txt" 2>&1 || true
    oc get svc -n openshift-storage > "${snapshot_dir}/storage-services.txt" 2>&1 || true

    log_info "Capturing storage resources..."
    oc get pvc -n "${NAMESPACE}" -o wide > "${snapshot_dir}/pvcs.txt" 2>&1 || true
    oc get pvc -n "${NAMESPACE}" -o yaml > "${snapshot_dir}/pvcs.yaml" 2>&1 || true
    oc get pv > "${snapshot_dir}/pvs.txt" 2>&1 || true
    oc get storageclass > "${snapshot_dir}/storageclasses.txt" 2>&1 || true

    log_info "Capturing CSI driver status..."
    oc get csidrivers > "${snapshot_dir}/csidrivers.txt" 2>&1 || true
    oc get csinodes > "${snapshot_dir}/csinodes.txt" 2>&1 || true

    log_info "Capturing InferenceServices..."
    oc get inferenceservices -n "${NAMESPACE}" -o wide > "${snapshot_dir}/inferenceservices.txt" 2>&1 || true
    oc get inferenceservices -n "${NAMESPACE}" -o yaml > "${snapshot_dir}/inferenceservices.yaml" 2>&1 || true

    log_info "Capturing service endpoints..."
    oc get endpoints -n "${NAMESPACE}" > "${snapshot_dir}/endpoints.txt" 2>&1 || true

    log_info "Capturing recent events..."
    oc get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' > "${snapshot_dir}/events.txt" 2>&1 || true

    log_info "Testing service health endpoints..."
    local coord_engine_pod=$(oc get pods -n "${NAMESPACE}" -l app=coordination-engine -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "${coord_engine_pod}" ]]; then
        oc exec -n "${NAMESPACE}" "${coord_engine_pod}" -- curl -s http://localhost:8080/health > "${snapshot_dir}/coordination-engine-health.txt" 2>&1 || true
    fi

    local mcp_pod=$(oc get pods -n "${NAMESPACE}" -l app=mcp-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "${mcp_pod}" ]]; then
        oc exec -n "${NAMESPACE}" "${mcp_pod}" -- curl -s http://localhost:8080/health > "${snapshot_dir}/mcp-server-health.txt" 2>&1 || true
    fi

    log_success "Pre-restart snapshot captured in: ${snapshot_dir}"
    echo "${snapshot_dir}" > "${DIAGNOSTICS_DIR}/latest-pre-restart.txt"
}

################################################################################
# Post-Restart Monitoring Functions
################################################################################

check_namespace_ready() {
    local ns=$1
    local label=$2

    if ! oc get namespace "${ns}" &>/dev/null; then
        echo "NOT_FOUND"
        return
    fi

    if [[ -z "${label}" ]]; then
        echo "EXISTS"
        return
    fi

    local ready_pods=$(oc get pods -n "${ns}" -l "${label}" -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
    local total_pods=$(oc get pods -n "${ns}" -l "${label}" --no-headers 2>/dev/null | wc -l)

    if [[ ${ready_pods} -gt 0 ]] && [[ ${ready_pods} -eq ${total_pods} ]]; then
        echo "READY"
    elif [[ ${total_pods} -gt 0 ]]; then
        echo "PARTIAL:${ready_pods}/${total_pods}"
    else
        echo "NO_PODS"
    fi
}

check_pvc_status() {
    local pvc_name=$1
    local ns=$2

    local phase=$(oc get pvc "${pvc_name}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NOT_FOUND")
    echo "${phase}"
}

check_pod_status() {
    local pod_label=$1
    local ns=$2

    local pod_name=$(oc get pods -n "${ns}" -l "${pod_label}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "${pod_name}" ]]; then
        echo "NO_POD"
        return
    fi

    local phase=$(oc get pod "${pod_name}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    local ready=$(oc get pod "${pod_name}" -n "${ns}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    local reason=$(oc get pod "${pod_name}" -n "${ns}" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")

    if [[ "${ready}" == "True" ]]; then
        echo "READY"
    elif [[ -n "${reason}" ]]; then
        echo "${phase}:${reason}"
    else
        echo "${phase}"
    fi
}

monitor_post_restart() {
    log_info "=== Starting Post-Restart Monitoring (${MONITOR_DURATION}s) ==="

    local monitor_dir="${DIAGNOSTICS_DIR}/post-restart-${TIMESTAMP}"
    mkdir -p "${monitor_dir}"

    local start_time=$(date +%s)
    local end_time=$((start_time + MONITOR_DURATION))
    local interval=10  # Check every 10 seconds

    # Timeline tracking
    local timeline_file="${monitor_dir}/startup-timeline.csv"
    echo "Timestamp,Elapsed,Component,Status,Details" > "${timeline_file}"

    log_info "Monitoring cluster startup sequence..."
    log_info "Start time: $(date)"
    log_info "Monitor duration: ${MONITOR_DURATION} seconds"

    while [[ $(date +%s) -lt ${end_time} ]]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local timestamp=$(date +%Y-%m-%d\ %H:%M:%S)

        log_info "--- Elapsed: ${elapsed}s ---"

        # Check cross-namespace dependencies
        log_info "Checking cross-namespace dependencies..."

        # Prometheus
        local prom_status=$(check_namespace_ready "openshift-monitoring" "app.kubernetes.io/name=prometheus")
        echo "${timestamp},${elapsed},Prometheus,${prom_status}," >> "${timeline_file}"
        log_info "  Prometheus: ${prom_status}"

        # ArgoCD
        local argocd_status=$(check_namespace_ready "openshift-gitops" "app.kubernetes.io/name=argocd-server")
        echo "${timestamp},${elapsed},ArgoCD,${argocd_status}," >> "${timeline_file}"
        log_info "  ArgoCD: ${argocd_status}"

        # ODF Storage
        local odf_status=$(check_namespace_ready "openshift-storage" "")
        echo "${timestamp},${elapsed},ODF Storage,${odf_status}," >> "${timeline_file}"
        log_info "  ODF Storage: ${odf_status}"

        # CSI Drivers
        local csi_count=$(oc get csidrivers --no-headers 2>/dev/null | wc -l || echo "0")
        echo "${timestamp},${elapsed},CSI Drivers,${csi_count} available," >> "${timeline_file}"
        log_info "  CSI Drivers: ${csi_count} available"

        # Storage Classes
        local sc_count=$(oc get storageclass --no-headers 2>/dev/null | wc -l || echo "0")
        echo "${timestamp},${elapsed},Storage Classes,${sc_count} available," >> "${timeline_file}"
        log_info "  Storage Classes: ${sc_count} available"

        # Platform namespace
        log_info "Checking platform namespace..."
        local ns_status=$(check_namespace_ready "${NAMESPACE}" "")
        echo "${timestamp},${elapsed},Platform Namespace,${ns_status}," >> "${timeline_file}"
        log_info "  Platform Namespace: ${ns_status}"

        # PVC Status
        log_info "Checking storage resources..."
        local pvc_status=$(check_pvc_status "model-storage-pvc" "${NAMESPACE}")
        echo "${timestamp},${elapsed},model-storage-pvc,${pvc_status}," >> "${timeline_file}"
        log_info "  model-storage-pvc: ${pvc_status}"

        # Platform Pods
        log_info "Checking platform pods..."

        local coord_status=$(check_pod_status "app=coordination-engine" "${NAMESPACE}")
        echo "${timestamp},${elapsed},coordination-engine,${coord_status}," >> "${timeline_file}"
        log_info "  coordination-engine: ${coord_status}"

        local mcp_status=$(check_pod_status "app=mcp-server" "${NAMESPACE}")
        echo "${timestamp},${elapsed},mcp-server,${mcp_status}," >> "${timeline_file}"
        log_info "  mcp-server: ${mcp_status}"

        # Init Models Job
        local job_status=$(oc get job init-models-job -n "${NAMESPACE}" -o jsonpath='{.status.conditions[0].type}:{.status.conditions[0].reason}' 2>/dev/null || echo "NOT_FOUND")
        echo "${timestamp},${elapsed},init-models-job,${job_status}," >> "${timeline_file}"
        log_info "  init-models-job: ${job_status}"

        # InferenceServices
        local isvc_count=$(oc get inferenceservices -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l || echo "0")
        local isvc_ready=$(oc get inferenceservices -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
        echo "${timestamp},${elapsed},InferenceServices,${isvc_ready}/${isvc_count} ready," >> "${timeline_file}"
        log_info "  InferenceServices: ${isvc_ready}/${isvc_count} ready"

        # Capture snapshots at key intervals
        if [[ $((elapsed % 60)) -eq 0 ]]; then
            log_info "Capturing snapshot at ${elapsed}s..."
            local snapshot_subdir="${monitor_dir}/snapshot-${elapsed}s"
            mkdir -p "${snapshot_subdir}"

            oc get pods -n "${NAMESPACE}" -o wide > "${snapshot_subdir}/pods.txt" 2>&1 || true
            oc get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' | tail -50 > "${snapshot_subdir}/recent-events.txt" 2>&1 || true

            # Capture logs of failed/restarting pods
            for pod in $(oc get pods -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
                local pod_phase=$(oc get pod "${pod}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null)
                if [[ "${pod_phase}" != "Running" ]] || oc get pod "${pod}" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[*].restartCount}' 2>/dev/null | grep -q "[1-9]"; then
                    log_warning "Capturing logs for problematic pod: ${pod} (${pod_phase})"
                    oc logs "${pod}" -n "${NAMESPACE}" --all-containers=true --tail=100 > "${snapshot_subdir}/${pod}-logs.txt" 2>&1 || true
                    oc logs "${pod}" -n "${NAMESPACE}" --all-containers=true --previous --tail=100 > "${snapshot_subdir}/${pod}-previous-logs.txt" 2>&1 || true
                    oc describe pod "${pod}" -n "${NAMESPACE}" > "${snapshot_subdir}/${pod}-describe.txt" 2>&1 || true
                fi
            done
        fi

        sleep ${interval}
    done

    log_info "Monitoring complete. Capturing final state..."

    # Final comprehensive snapshot
    local final_dir="${monitor_dir}/final-state"
    mkdir -p "${final_dir}"

    oc get all -n "${NAMESPACE}" -o wide > "${final_dir}/all-resources.txt" 2>&1 || true
    oc get pods -n "${NAMESPACE}" -o yaml > "${final_dir}/pods.yaml" 2>&1 || true
    oc get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' > "${final_dir}/all-events.txt" 2>&1 || true
    oc get pvc -n "${NAMESPACE}" -o yaml > "${final_dir}/pvcs.yaml" 2>&1 || true
    oc get inferenceservices -n "${NAMESPACE}" -o yaml > "${final_dir}/inferenceservices.yaml" 2>&1 || true

    # Capture all pod logs
    for pod in $(oc get pods -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
        oc logs "${pod}" -n "${NAMESPACE}" --all-containers=true --tail=500 > "${final_dir}/${pod}-logs.txt" 2>&1 || true
    done

    log_success "Post-restart monitoring complete. Data saved in: ${monitor_dir}"
    echo "${monitor_dir}" > "${DIAGNOSTICS_DIR}/latest-post-restart.txt"
}

################################################################################
# Report Generation Functions
################################################################################

generate_diagnostic_report() {
    log_info "=== Generating Diagnostic Report ==="

    local pre_restart_dir=$(cat "${DIAGNOSTICS_DIR}/latest-pre-restart.txt" 2>/dev/null || echo "")
    local post_restart_dir=$(cat "${DIAGNOSTICS_DIR}/latest-post-restart.txt" 2>/dev/null || echo "")

    if [[ -z "${pre_restart_dir}" ]] || [[ ! -d "${pre_restart_dir}" ]]; then
        log_error "No pre-restart data found. Run with --phase pre-restart first."
        exit 1
    fi

    if [[ -z "${post_restart_dir}" ]] || [[ ! -d "${post_restart_dir}" ]]; then
        log_error "No post-restart data found. Run with --phase post-restart first."
        exit 1
    fi

    local report_file="${DIAGNOSTICS_DIR}/diagnostic-report-${TIMESTAMP}.md"

    cat > "${report_file}" <<EOF
# Cluster Restart Diagnostic Report

**Generated**: $(date)
**Pre-Restart Snapshot**: ${pre_restart_dir}
**Post-Restart Monitoring**: ${post_restart_dir}

---

## Executive Summary

EOF

    # Analyze timeline
    local timeline_file="${post_restart_dir}/startup-timeline.csv"

    if [[ -f "${timeline_file}" ]]; then
        echo "### Startup Timeline Analysis" >> "${report_file}"
        echo "" >> "${report_file}"

        # Find when key dependencies became ready
        local prom_ready=$(grep "Prometheus,READY" "${timeline_file}" | head -1 | cut -d',' -f2 || echo "NOT_READY")
        local argocd_ready=$(grep "ArgoCD,READY" "${timeline_file}" | head -1 | cut -d',' -f2 || echo "NOT_READY")
        local pvc_bound=$(grep "model-storage-pvc,Bound" "${timeline_file}" | head -1 | cut -d',' -f2 || echo "NOT_BOUND")
        local coord_ready=$(grep "coordination-engine,READY" "${timeline_file}" | head -1 | cut -d',' -f2 || echo "NOT_READY")
        local mcp_ready=$(grep "mcp-server,READY" "${timeline_file}" | head -1 | cut -d',' -f2 || echo "NOT_READY")

        echo "| Component | Time to Ready |" >> "${report_file}"
        echo "|-----------|---------------|" >> "${report_file}"
        echo "| Prometheus | ${prom_ready}s |" >> "${report_file}"
        echo "| ArgoCD | ${argocd_ready}s |" >> "${report_file}"
        echo "| model-storage-pvc | ${pvc_bound}s |" >> "${report_file}"
        echo "| coordination-engine | ${coord_ready}s |" >> "${report_file}"
        echo "| mcp-server | ${mcp_ready}s |" >> "${report_file}"
        echo "" >> "${report_file}"
    fi

    # Analyze failures
    echo "### Failure Analysis" >> "${report_file}"
    echo "" >> "${report_file}"

    local final_pods="${post_restart_dir}/final-state/pods.yaml"
    if [[ -f "${final_pods}" ]]; then
        # Check for CrashLoopBackOff
        local crash_loops=$(grep -c "CrashLoopBackOff" "${final_pods}" 2>/dev/null || echo "0")
        echo "- **CrashLoopBackOff pods**: ${crash_loops}" >> "${report_file}"

        # Check for ImagePullBackOff
        local image_pull=$(grep -c "ImagePullBackOff\|ErrImagePull" "${final_pods}" 2>/dev/null || echo "0")
        echo "- **ImagePullBackOff pods**: ${image_pull}" >> "${report_file}"

        # Check for Init errors
        local init_errors=$(grep -c "Init:Error\|Init:CrashLoopBackOff" "${final_pods}" 2>/dev/null || echo "0")
        echo "- **Init container failures**: ${init_errors}" >> "${report_file}"

        # Check for pending pods
        local pending=$(grep "phase: Pending" "${final_pods}" 2>/dev/null | wc -l)
        echo "- **Pending pods**: ${pending}" >> "${report_file}"

        echo "" >> "${report_file}"
    fi

    # Root cause analysis
    echo "## Root Cause Analysis" >> "${report_file}"
    echo "" >> "${report_file}"

    # Check if coordination-engine failed before Prometheus was ready
    if [[ "${coord_ready}" == "NOT_READY" ]] || [[ "${prom_ready}" == "NOT_READY" ]]; then
        echo "### ⚠️ Cross-Namespace Dependency Race Condition Detected" >> "${report_file}"
        echo "" >> "${report_file}"
        echo "**Finding**: coordination-engine may have started before Prometheus was available." >> "${report_file}"
        echo "" >> "${report_file}"
        echo "**Evidence**:" >> "${report_file}"
        echo "- Prometheus ready at: ${prom_ready}s" >> "${report_file}"
        echo "- coordination-engine ready at: ${coord_ready}s" >> "${report_file}"
        echo "" >> "${report_file}"
        echo "**Recommendation**: Add init container to coordination-engine to wait for Prometheus readiness." >> "${report_file}"
        echo "" >> "${report_file}"
    fi

    # Check for storage timing issues
    if [[ "${pvc_bound}" != "NOT_BOUND" ]] && [[ ${pvc_bound} -gt 60 ]]; then
        echo "### ⚠️ Storage Mount Timing Issue Detected" >> "${report_file}"
        echo "" >> "${report_file}"
        echo "**Finding**: model-storage-pvc took ${pvc_bound}s to become bound (>${pvc_bound}s delay)." >> "${report_file}"
        echo "" >> "${report_file}"
        echo "**Impact**: init-models-job and InferenceServices may have failed waiting for storage." >> "${report_file}"
        echo "" >> "${report_file}"
        echo "**Recommendation**: Add init containers to verify PVC binding before mounting." >> "${report_file}"
        echo "" >> "${report_file}"
    fi

    # Check init-models-job status
    local job_final_status=$(grep "init-models-job" "${timeline_file}" | tail -1 | cut -d',' -f4 || echo "UNKNOWN")
    if [[ "${job_final_status}" == *"Failed"* ]] || [[ "${job_final_status}" == *"BackoffLimitExceeded"* ]]; then
        echo "### ⚠️ Init Models Job Failure Detected" >> "${report_file}"
        echo "" >> "${report_file}"
        echo "**Finding**: init-models-job failed with status: ${job_final_status}" >> "${report_file}"
        echo "" >> "${report_file}"
        echo "**Recommendation**: Increase backoffLimit and add storage readiness verification." >> "${report_file}"
        echo "" >> "${report_file}"
    fi

    # Detailed pod failure analysis
    echo "## Detailed Pod Status" >> "${report_file}"
    echo "" >> "${report_file}"

    if [[ -f "${final_pods}" ]]; then
        echo '```' >> "${report_file}"
        oc get pods -n "${NAMESPACE}" -o wide 2>/dev/null >> "${report_file}" || true
        echo '```' >> "${report_file}"
        echo "" >> "${report_file}"
    fi

    # Event analysis
    echo "## Critical Events" >> "${report_file}"
    echo "" >> "${report_file}"

    local events_file="${post_restart_dir}/final-state/all-events.txt"
    if [[ -f "${events_file}" ]]; then
        echo '```' >> "${report_file}"
        grep -E "Warning|Error|Failed" "${events_file}" | tail -30 >> "${report_file}" 2>/dev/null || true
        echo '```' >> "${report_file}"
        echo "" >> "${report_file}"
    fi

    # Recommendations
    echo "## Recommended Actions" >> "${report_file}"
    echo "" >> "${report_file}"
    echo "Based on the analysis, implement these fixes in order of priority:" >> "${report_file}"
    echo "" >> "${report_file}"
    echo "1. **Add init containers** to coordination-engine and mcp-server to wait for cross-namespace dependencies" >> "${report_file}"
    echo "2. **Add startup probes** with longer timeouts (5-minute window) to allow for dependency startup" >> "${report_file}"
    echo "3. **Increase backoffLimit** for init-models-job from 3 to 10" >> "${report_file}"
    echo "4. **Add storage verification** init containers to verify PVC binding before mounting" >> "${report_file}"
    echo "5. **Review InferenceService** startup if model serving issues persist" >> "${report_file}"
    echo "" >> "${report_file}"

    # Data locations
    echo "## Data Locations" >> "${report_file}"
    echo "" >> "${report_file}"
    echo "- **Pre-restart snapshot**: \`${pre_restart_dir}\`" >> "${report_file}"
    echo "- **Post-restart monitoring**: \`${post_restart_dir}\`" >> "${report_file}"
    echo "- **Startup timeline**: \`${timeline_file}\`" >> "${report_file}"
    echo "- **This report**: \`${report_file}\`" >> "${report_file}"
    echo "" >> "${report_file}"

    log_success "Diagnostic report generated: ${report_file}"

    # Display report summary
    echo ""
    log_info "=== REPORT SUMMARY ==="
    echo ""
    cat "${report_file}"
}

################################################################################
# Main
################################################################################

show_usage() {
    cat <<EOF
Usage: $0 --phase <phase> [options]

Phases:
  pre-restart   Capture baseline state before cluster restart
  post-restart  Monitor startup sequence after cluster restart
  report        Generate comprehensive diagnostic report

Options:
  --monitor-duration SECONDS    Duration to monitor post-restart (default: 600)
  --namespace NAMESPACE         Platform namespace (default: self-healing-platform)
  --help                        Show this help message

Examples:
  # Before cluster restart
  $0 --phase pre-restart

  # After cluster restart (monitor for 10 minutes)
  $0 --phase post-restart --monitor-duration 600

  # Generate diagnostic report
  $0 --phase report

EOF
}

# Parse arguments
PHASE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --monitor-duration)
            MONITOR_DURATION="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

if [[ -z "${PHASE}" ]]; then
    log_error "Phase is required"
    show_usage
    exit 1
fi

# Execute phase
case "${PHASE}" in
    pre-restart)
        capture_pre_restart_snapshot
        ;;
    post-restart)
        monitor_post_restart
        ;;
    report)
        generate_diagnostic_report
        ;;
    *)
        log_error "Invalid phase: ${PHASE}"
        show_usage
        exit 1
        ;;
esac

log_success "Phase '${PHASE}' completed successfully"
