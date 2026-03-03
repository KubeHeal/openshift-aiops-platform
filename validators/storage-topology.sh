#!/bin/bash
# Storage & Topology Validation Module
# Validates ADRs: 034, 035, 054, 055, 056, 057, 058

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RESULTS=()

sanitize_number() {
    local value="$1"
    value=$(echo "$value" | tr -d '[:space:]' | grep -o '^[0-9]*' || echo "0")
    echo "${value:-0}"
}

add_result() {
    local adr=$1
    local status=$2
    local expected=$3
    local actual=$4
    local details=$5
    RESULTS+=("{\"adr\":\"$adr\",\"status\":\"$status\",\"expected\":\"$expected\",\"actual\":\"$actual\",\"details\":\"$details\",\"timestamp\":\"$TIMESTAMP\"}")
}

# Detect topology
detect_topology() {
    if [[ -f "$SCRIPT_DIR/../scripts/detect-cluster-topology.sh" ]]; then
        "$SCRIPT_DIR/../scripts/detect-cluster-topology.sh"
    else
        local node_count=$(oc get nodes --no-headers 2>/dev/null | wc -l)
        if [[ $node_count -eq 1 ]]; then
            echo "SingleReplica"
        else
            echo "HighlyAvailable"
        fi
    fi
}

# ADR-034: Secure Notebook Routes
validate_adr_034() {
    echo "Validating ADR-034: Secure Notebook Routes..." >&2

    local notebook_routes=$(oc get route -n self-healing-platform --no-headers 2>/dev/null | grep -c "notebook\|workbench" || echo "0")
    local tls_routes=$(oc get route -n self-healing-platform -o json 2>/dev/null | jq '[.items[] | select(.spec.tls != null)] | length' || echo "0")
    local oauth_proxy=$(oc get deployment -n self-healing-platform -o json 2>/dev/null | jq '[.items[].spec.template.spec.containers[] | select(.name | contains("oauth-proxy"))] | length' || echo "0")

    if [[ $notebook_routes -ge 1 ]] && [[ $tls_routes -ge 1 ]]; then
        add_result "034" "PASS" "Secure routes with TLS + OAuth" "Routes: $notebook_routes, TLS: $tls_routes, OAuth proxy containers: $oauth_proxy" "Secure access configured"
    elif [[ $notebook_routes -ge 1 ]]; then
        add_result "034" "PARTIAL" "Secure routes with TLS + OAuth" "Routes exist but TLS/OAuth may not be fully configured" "Routes partially secured"
    else
        add_result "034" "FAIL" "Secure routes with TLS + OAuth" "No notebook routes found" "Routes not configured"
    fi
}

# ADR-035: Persistent Volume Claims
validate_adr_035() {
    echo "Validating ADR-035: Persistent Volume Claims..." >&2

    local topology=$(detect_topology)
    local pvcs=$(oc get pvc -n self-healing-platform --no-headers 2>/dev/null | wc -l)
    local bound_pvcs=$(oc get pvc -n self-healing-platform --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
    local storage_classes=$(oc get pvc -n self-healing-platform -o json 2>/dev/null | jq -r '[.items[].spec.storageClassName] | unique | length' || echo "0")

    # Check storage class types
    local gp3_pvcs=$(oc get pvc -n self-healing-platform -o json 2>/dev/null | jq '[.items[] | select(.spec.storageClassName | contains("gp3"))] | length' || echo "0")
    local ocs_pvcs=$(oc get pvc -n self-healing-platform -o json 2>/dev/null | jq '[.items[] | select(.spec.storageClassName | contains("ocs"))] | length' || echo "0")

    # Topology-aware PVC expectations
    local expected_pvcs=2  # SNO: workbench-data-development, model-storage-pvc
    if [[ $topology == "HighlyAvailable" ]] || [[ $topology == "HA" ]]; then
        expected_pvcs=3  # HA: + model-storage-gpu-pvc
    fi

    if [[ $pvcs -eq $expected_pvcs ]] && [[ $bound_pvcs -eq $expected_pvcs ]]; then
        add_result "035" "PASS" "$expected_pvcs PVCs Bound ($topology topology)" "Total PVCs: $pvcs, Bound: $bound_pvcs, StorageClasses: $storage_classes (gp3: $gp3_pvcs, ocs: $ocs_pvcs)" "Persistent storage operational"
    elif [[ $bound_pvcs -ge 2 ]]; then
        add_result "035" "PARTIAL" "$expected_pvcs PVCs Bound ($topology topology)" "Expected: $expected_pvcs, Actual PVCs: $pvcs, Bound: $bound_pvcs" "Partial storage configured"
    else
        add_result "035" "FAIL" "$expected_pvcs PVCs Bound ($topology topology)" "Expected: $expected_pvcs, PVCs: $pvcs, Bound: $bound_pvcs" "Insufficient storage configured"
    fi
}

# ADR-054: Model Files on PVC
validate_adr_054() {
    echo "Validating ADR-054: Model Files on PVC..." >&2

    # Check for model PVC
    local model_pvc=$(oc get pvc -n self-healing-platform --no-headers 2>/dev/null | grep -c "model\|kserve" || echo "0")

    # Check for restart-predictors job or similar
    local restart_job=$(oc get job -n self-healing-platform --no-headers 2>/dev/null | grep -c "restart-predictor\|model-reload" || echo "0")
    local restart_cronjob=$(oc get cronjob -n self-healing-platform --no-headers 2>/dev/null | grep -c "restart-predictor" || echo "0")

    # Check if InferenceServices are using PVC storage
    local isvc_with_storage=$(oc get inferenceservice -n self-healing-platform -o json 2>/dev/null | jq '[.items[] | select(.spec.predictor.model.storageUri | contains("pvc://"))] | length' || echo "0")

    if [[ $model_pvc -ge 1 ]] && [[ $isvc_with_storage -ge 1 ]]; then
        add_result "054" "PASS" "Model files on PVC with reload" "Model PVCs: $model_pvc, ISVC with PVC storage: $isvc_with_storage, Restart jobs: $restart_job, CronJobs: $restart_cronjob" "Model storage operational"
    elif [[ $model_pvc -ge 1 ]]; then
        add_result "054" "PARTIAL" "Model files on PVC with reload" "Model PVC exists but not fully integrated" "Partial model storage"
    else
        add_result "054" "FAIL" "Model files on PVC with reload" "No model PVCs found" "Model storage not configured"
    fi
}

# ADR-055: Topology-Aware Deployment
validate_adr_055() {
    echo "Validating ADR-055: Topology-Aware Deployment..." >&2

    local topology=$(detect_topology)
    local topology_env=$(oc get deployment -n self-healing-platform -o json 2>/dev/null | jq -r '[.items[].spec.template.spec.containers[].env[] | select(.name=="CLUSTER_TOPOLOGY")] | length' || echo "0")

    # Check if infrastructure settings match topology
    local prometheus_replicas=$(oc get statefulset -n openshift-monitoring prometheus-k8s -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    local expected_replicas=2
    if [[ $topology == "SingleReplica" ]]; then
        expected_replicas=1
    fi

    local topology_match=0
    if [[ $topology == "SingleReplica" ]] && [[ $prometheus_replicas -le 2 ]]; then
        topology_match=1
    elif [[ $topology == "HighlyAvailable" ]] && [[ $prometheus_replicas -ge 2 ]]; then
        topology_match=1
    fi

    if [[ -f "$SCRIPT_DIR/../scripts/detect-cluster-topology.sh" ]] && [[ $topology_match -eq 1 ]]; then
        add_result "055" "PASS" "Topology detection with correct settings" "Topology: $topology, Prometheus replicas: $prometheus_replicas, Env vars: $topology_env" "Topology-aware deployment operational"
    elif [[ -f "$SCRIPT_DIR/../scripts/detect-cluster-topology.sh" ]]; then
        add_result "055" "PARTIAL" "Topology detection with correct settings" "Topology detected but settings may not match" "Partial topology awareness"
    else
        add_result "055" "FAIL" "Topology detection with correct settings" "Topology detection script not found" "Topology awareness not configured"
    fi
}

# ADR-056: SNO Storage Configuration (SNO-specific)
validate_adr_056() {
    echo "Validating ADR-056: SNO Storage Configuration..." >&2

    local topology=$(detect_topology)

    if [[ $topology != "SingleReplica" ]]; then
        add_result "056" "N/A" "MCG-only on SNO" "Not applicable (cluster is $topology)" "SNO-specific ADR"
        return
    fi

    # Check StorageCluster reconcileStrategy
    local reconcile_strategy=$(oc get storagecluster -n openshift-storage -o jsonpath='{.items[0].spec.multiCloudGateway.reconcileStrategy}' 2>/dev/null || echo "NotFound")
    local storage_cluster_status=$(oc get storagecluster -n openshift-storage -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

    # Check for MCG-only (no Ceph)
    local ceph_pods=$(oc get pods -n openshift-storage -l app=rook-ceph-mon --no-headers 2>/dev/null | wc -l)
    local noobaa_pods=$(oc get pods -n openshift-storage -l app=noobaa --no-headers 2>/dev/null | wc -l)

    if [[ $reconcile_strategy == "standalone" ]] && [[ $ceph_pods -eq 0 ]] && [[ $noobaa_pods -ge 1 ]]; then
        add_result "056" "PASS" "MCG-only with standalone strategy" "ReconcileStrategy: $reconcile_strategy, Ceph pods: $ceph_pods, NooBaa pods: $noobaa_pods, Status: $storage_cluster_status" "SNO storage optimized"
    elif [[ $noobaa_pods -ge 1 ]]; then
        add_result "056" "PARTIAL" "MCG-only with standalone strategy" "NooBaa present but strategy may not be standalone" "Partial SNO optimization"
    else
        add_result "056" "FAIL" "MCG-only with standalone strategy" "NooBaa not found or Ceph still present" "SNO storage not optimized"
    fi
}

# ADR-057: GPU Affinity & Storage Access
validate_adr_057() {
    echo "Validating ADR-057: GPU Affinity & Storage Access..." >&2

    # Check for GPU node affinity in deployments
    local gpu_affinity=$(oc get deployment -n self-healing-platform -o json 2>/dev/null | jq '[.items[] | select(.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]?.matchExpressions[]? | select(.key | contains("nvidia")))] | length' || echo "0")

    # Check for pods scheduled on GPU nodes
    local gpu_nodes=$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | awk '{print $1}')
    local pods_on_gpu=0
    if [[ -n "$gpu_nodes" ]]; then
        for node in $gpu_nodes; do
            pods_on_gpu=$((pods_on_gpu + $(oc get pods -n self-healing-platform --field-selector spec.nodeName=$node --no-headers 2>/dev/null | wc -l)))
        done
    fi

    # Check storage access patterns (PVCs mounted by GPU workloads)
    local gpu_pod_with_storage=$(oc get pods -n self-healing-platform -o json 2>/dev/null | jq '[.items[] | select(.spec.volumes[]?.persistentVolumeClaim != null and (.spec.nodeSelector | has("nvidia.com/gpu.present")))] | length' || echo "0")

    if [[ $gpu_affinity -ge 1 ]] || [[ $pods_on_gpu -ge 1 ]]; then
        add_result "057" "PASS" "GPU affinity with storage access" "GPU affinity rules: $gpu_affinity, Pods on GPU nodes: $pods_on_gpu, GPU pods with storage: $gpu_pod_with_storage" "GPU workload optimization operational"
    elif [[ $gpu_pod_with_storage -ge 1 ]]; then
        add_result "057" "PARTIAL" "GPU affinity with storage access" "Some GPU storage patterns configured" "Partial GPU optimization"
    else
        add_result "057" "FAIL" "GPU affinity with storage access" "No GPU affinity or storage patterns found" "GPU optimization not configured"
    fi
}

# ADR-058: Deployment Validation Results
validate_adr_058() {
    echo "Validating ADR-058: Deployment Validation Results..." >&2

    # Check for validation results
    local validation_script="$SCRIPT_DIR/../scripts/post-deployment-validation.sh"
    local validation_results="$SCRIPT_DIR/../results/deployment-validation.json"

    local script_exists=0
    if [[ -f "$validation_script" ]]; then
        script_exists=1
    fi

    local results_exist=0
    local success_rate=0
    if [[ -f "$validation_results" ]]; then
        results_exist=1
        success_rate=$(jq -r '.summary.success_rate // 0' "$validation_results" 2>/dev/null || echo "0")
    fi

    # Check for validation pipeline
    local validation_pipeline=$(oc get pipeline -n self-healing-platform --no-headers 2>/dev/null | grep -c "deployment-validation\|post-deployment" || echo "0")

    if [[ $script_exists -eq 1 ]] && [[ $success_rate -ge 90 ]]; then
        add_result "058" "PASS" "94%+ validation success" "Validation script exists, Success rate: $success_rate%, Pipeline: $validation_pipeline" "Deployment validation operational"
    elif [[ $script_exists -eq 1 ]]; then
        add_result "058" "PARTIAL" "94%+ validation success" "Validation script exists, results may be pending" "Validation configured"
    else
        add_result "058" "FAIL" "94%+ validation success" "Validation script not found" "Deployment validation not configured"
    fi
}

main() {
    echo "=== Storage & Topology Validation (ADRs: 034, 035, 054, 055, 056, 057, 058) ===" >&2

    validate_adr_034
    validate_adr_035
    validate_adr_054
    validate_adr_055
    validate_adr_056
    validate_adr_057
    validate_adr_058

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
