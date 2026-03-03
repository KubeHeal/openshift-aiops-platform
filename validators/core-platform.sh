#!/bin/bash
# Core Platform Validation Module
# Validates ADRs: 001, 003, 004, 006, 007, 010

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# JSON output array
RESULTS=()

# Helper function to sanitize numeric output
sanitize_number() {
    local value="$1"
    # Remove whitespace and newlines, keep only digits
    value=$(echo "$value" | tr -d '[:space:]' | grep -o '^[0-9]*' || echo "0")
    # Default to 0 if empty
    echo "${value:-0}"
}

# Helper function to add result
add_result() {
    local adr=$1
    local status=$2
    local expected=$3
    local actual=$4
    local details=$5

    RESULTS+=("{\"adr\":\"$adr\",\"status\":\"$status\",\"expected\":\"$expected\",\"actual\":\"$actual\",\"details\":\"$details\",\"timestamp\":\"$TIMESTAMP\"}")
}

# ADR-001: OpenShift 4.18+ Cluster
validate_adr_001() {
    echo "Validating ADR-001: OpenShift Cluster Version..." >&2

    local version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "ERROR")
    local node_count=$(oc get nodes --no-headers 2>/dev/null | wc -l)
    local topology=$(oc get infrastructure cluster -o jsonpath='{.status.controlPlaneTopology}' 2>/dev/null || echo "Unknown")

    if [[ $version == ERROR ]]; then
        add_result "001" "ERROR" "4.18+" "$version" "Failed to get cluster version"
    elif [[ $version == 4.1[8-9].* ]] || [[ $version == 4.2* ]]; then
        add_result "001" "PASS" "4.18+" "$version (nodes: $node_count, topology: $topology)" "Cluster operational"
    else
        add_result "001" "FAIL" "4.18+" "$version" "Version too old"
    fi
}

# ADR-003: RHODS/RHOAI Deployment
validate_adr_003() {
    echo "Validating ADR-003: RHODS/RHOAI..." >&2

    local rhods_pods=$(oc get pods -n redhat-ods-operator --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local kserve_controller=$(oc get deployment kserve-controller-manager -n redhat-ods-applications -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local dashboard=$(oc get deployment rhods-dashboard -n redhat-ods-applications -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

    # Clean and ensure numeric values
    rhods_pods=$(echo "$rhods_pods" | tr -d '[:space:]')
    kserve_controller=$(echo "$kserve_controller" | tr -d '[:space:]')
    dashboard=$(echo "$dashboard" | tr -d '[:space:]')

    rhods_pods=${rhods_pods:-0}
    kserve_controller=${kserve_controller:-0}
    dashboard=${dashboard:-0}

    # Validate numeric
    [[ ! "$rhods_pods" =~ ^[0-9]+$ ]] && rhods_pods=0
    [[ ! "$kserve_controller" =~ ^[0-9]+$ ]] && kserve_controller=0
    [[ ! "$dashboard" =~ ^[0-9]+$ ]] && dashboard=0

    local total=$((rhods_pods + kserve_controller + dashboard))

    if [[ $total -ge 5 ]]; then
        add_result "003" "PASS" "RHODS operational" "Operator: $rhods_pods pods, KServe: $kserve_controller, Dashboard: $dashboard" "RHODS fully deployed"
    elif [[ $total -ge 1 ]]; then
        add_result "003" "PARTIAL" "RHODS operational" "Operator: $rhods_pods pods, KServe: $kserve_controller, Dashboard: $dashboard" "Some components missing"
    else
        add_result "003" "FAIL" "RHODS operational" "No pods found" "RHODS not deployed"
    fi
}

# ADR-004: KServe InferenceServices
validate_adr_004() {
    echo "Validating ADR-004: KServe InferenceServices..." >&2

    local isvc_count=$(sanitize_number "$(oc get inferenceservice -n self-healing-platform --no-headers 2>/dev/null | wc -l)")
    local ready_count=$(sanitize_number "$(oc get inferenceservice -n self-healing-platform -o json 2>/dev/null | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')")
    local predictor_pods=$(sanitize_number "$(oc get pods -n self-healing-platform -l component=predictor --no-headers 2>/dev/null | grep -c "Running" || echo "0")")

    if [[ $ready_count -eq 2 ]] && [[ $predictor_pods -ge 2 ]]; then
        add_result "004" "PASS" "2 InferenceServices" "$ready_count/$isvc_count ready, $predictor_pods predictor pods" "KServe operational"
    elif [[ $ready_count -ge 1 ]]; then
        add_result "004" "PARTIAL" "2 InferenceServices" "$ready_count/$isvc_count ready, $predictor_pods predictor pods" "Partial deployment"
    else
        add_result "004" "FAIL" "2 InferenceServices" "0 ready" "InferenceServices not deployed"
    fi
}

# ADR-006: GPU Operator
validate_adr_006() {
    echo "Validating ADR-006: GPU Operator..." >&2

    local gpu_operator=$(sanitize_number "$(oc get deployment -n nvidia-gpu-operator gpu-operator --no-headers 2>/dev/null | grep -c "1/1" || echo "0")")
    local gpu_nodes=$(sanitize_number "$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l)")
    local gpu_driver_pods=$(sanitize_number "$(oc get pods -n nvidia-gpu-operator -l app=nvidia-driver-daemonset --no-headers 2>/dev/null | grep -c "Running" || echo "0")")

    if [[ $gpu_operator -eq 1 ]] && [[ $gpu_nodes -ge 1 ]]; then
        add_result "006" "PASS" "GPU Operator deployed" "Operator ready, $gpu_nodes GPU nodes, $gpu_driver_pods driver pods" "GPU support operational"
    elif [[ $gpu_operator -eq 1 ]]; then
        add_result "006" "PARTIAL" "GPU Operator deployed" "Operator ready but no GPU nodes labeled" "Operator deployed, awaiting GPU nodes"
    else
        add_result "006" "FAIL" "GPU Operator deployed" "Operator not found" "GPU Operator not deployed"
    fi
}

# ADR-007: Prometheus & Monitoring
validate_adr_007() {
    echo "Validating ADR-007: Prometheus Monitoring..." >&2

    local prometheus_pods=$(oc get statefulset -n openshift-monitoring prometheus-k8s -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local alertmanager=$(oc get statefulset -n openshift-monitoring alertmanager-main -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local servicemonitors=$(oc get servicemonitor -n self-healing-platform --no-headers 2>/dev/null | wc -l)

    if [[ $prometheus_pods -ge 2 ]] && [[ $alertmanager -ge 1 ]]; then
        add_result "007" "PASS" "Prometheus HA" "Prometheus: $prometheus_pods replicas, AlertManager: $alertmanager, ServiceMonitors: $servicemonitors" "Monitoring operational"
    elif [[ $prometheus_pods -ge 1 ]]; then
        add_result "007" "PARTIAL" "Prometheus HA" "Prometheus: $prometheus_pods replicas" "Single replica mode"
    else
        add_result "007" "FAIL" "Prometheus HA" "No Prometheus pods" "Monitoring not operational"
    fi
}

# ADR-010: OpenShift Data Foundation (ODF)
validate_adr_010() {
    echo "Validating ADR-010: ODF Storage..." >&2

    local odf_operator=$(sanitize_number "$(oc get csv -n openshift-storage --no-headers 2>/dev/null | grep -c "odf-operator" || echo "0")")
    local storage_cluster=$(sanitize_number "$(oc get storagecluster -n openshift-storage --no-headers 2>/dev/null | wc -l)")
    local noobaa_status=$(oc get noobaa -n openshift-storage noobaa -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    local storage_classes=$(sanitize_number "$(oc get storageclass --no-headers 2>/dev/null | grep -c "ocs-storagecluster\|gp3-csi" || echo "0")")

    if [[ $odf_operator -ge 1 ]] && [[ $storage_cluster -ge 1 ]] && [[ $noobaa_status == "Ready" ]]; then
        add_result "010" "PASS" "ODF operational" "Operator installed, StorageCluster: $storage_cluster, NooBaa: $noobaa_status, StorageClasses: $storage_classes" "ODF fully deployed"
    elif [[ $odf_operator -ge 1 ]]; then
        add_result "010" "PARTIAL" "ODF operational" "Operator found but cluster not ready" "ODF partially configured"
    else
        add_result "010" "FAIL" "ODF operational" "ODF operator not found" "ODF not deployed"
    fi
}

# Main execution
main() {
    echo "=== Core Platform Validation (ADRs: 001, 003, 004, 006, 007, 010) ===" >&2

    validate_adr_001
    validate_adr_003
    validate_adr_004
    validate_adr_006
    validate_adr_007
    validate_adr_010

    # Output JSON array
    echo "["
    for i in "${!RESULTS[@]}"; do
        echo "  ${RESULTS[$i]}"
        if [[ $i -lt $((${#RESULTS[@]} - 1)) ]]; then
            echo ","
        fi
    done
    echo "]"
}

main "$@"
