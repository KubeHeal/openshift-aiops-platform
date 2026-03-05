#!/bin/bash
# Deployment & GitOps Validation Module
# Validates ADRs: 019, 030

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

# ADR-019: Validated Patterns Operator
validate_adr_019() {
    echo "Validating ADR-019: Validated Patterns Operator..." >&2

    # Check for Patterns Operator
    local patterns_operator=$(oc get deployment -n openshift-operators --no-headers 2>/dev/null | grep -c "patterns-operator" || echo "0")

    # Check GitOps version
    local gitops_version=$(oc get csv -n openshift-gitops --no-headers 2>/dev/null | grep "openshift-gitops-operator" | awk '{print $1}' || echo "NotFound")
    local gitops_ready=0
    if [[ $gitops_version == *"1.1"[8-9]* ]] || [[ $gitops_version == *"1.2"* ]]; then
        gitops_ready=1
    fi

    # Check for Pattern CR
    local pattern_cr=$(oc get pattern --all-namespaces --no-headers 2>/dev/null | wc -l)

    # Check ArgoCD applications
    local argocd_apps=$(oc get application -n openshift-gitops --no-headers 2>/dev/null | wc -l)

    if [[ $patterns_operator -ge 1 ]] && [[ $gitops_ready -eq 1 ]] && [[ $pattern_cr -ge 1 ]]; then
        add_result "019" "PASS" "Patterns Operator + GitOps 1.19.1+" "Operator: $patterns_operator, GitOps: $gitops_version, Patterns: $pattern_cr, Apps: $argocd_apps" "Validated Patterns operational"
    elif [[ $gitops_ready -eq 1 ]] && [[ $argocd_apps -ge 1 ]]; then
        add_result "019" "PARTIAL" "Patterns Operator + GitOps 1.19.1+" "GitOps operational but Patterns Operator may not be installed" "GitOps ready, Patterns partial"
    else
        add_result "019" "FAIL" "Patterns Operator + GitOps 1.19.1+" "GitOps: $gitops_version" "Validated Patterns not configured"
    fi
}

# ADR-030: Namespaced ArgoCD with Cluster RBAC
validate_adr_030() {
    echo "Validating ADR-030: Namespaced ArgoCD with Cluster RBAC..." >&2

    # Fixed: Check self-healing-platform-hub namespace (where hub-gitops ArgoCD instance is deployed)
    local namespaced_argocd=$(oc get argocd -n self-healing-platform-hub --no-headers 2>/dev/null | wc -l)

    # Check for cluster-scoped RBAC (deployed via Ansible, not ArgoCD)
    local cluster_roles=$(oc get clusterrole --no-headers 2>/dev/null | grep -c "self-healing" || echo "0")
    local cluster_role_bindings=$(oc get clusterrolebinding --no-headers 2>/dev/null | grep -c "self-healing\|hub-gitops" || echo "0")

    # Check ArgoCD server deployment in hub namespace
    local argocd_server=$(oc get deployment -n self-healing-platform-hub --no-headers 2>/dev/null | grep -c "gitops-server" || echo "0")
    local argocd_repo=$(oc get deployment -n self-healing-platform-hub --no-headers 2>/dev/null | grep -c "gitops-repo-server" || echo "0")

    # Check ArgoCD status
    local argocd_status=$(oc get argocd hub-gitops -n self-healing-platform-hub -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [[ $namespaced_argocd -ge 1 ]] && [[ $cluster_roles -ge 5 ]] && [[ $argocd_server -ge 1 ]] && [[ "$argocd_status" == "Available" ]]; then
        add_result "030" "PASS" "Namespaced ArgoCD with cluster RBAC" "ArgoCD: hub-gitops (Available), ClusterRoles: $cluster_roles, ClusterRoleBindings: $cluster_role_bindings" "Hybrid management model operational"
    elif [[ $argocd_server -ge 1 ]] || [[ $cluster_roles -ge 1 ]]; then
        add_result "030" "PARTIAL" "Namespaced ArgoCD with cluster RBAC" "Some components present but not fully configured" "Partial ArgoCD setup"
    else
        add_result "030" "FAIL" "Namespaced ArgoCD with cluster RBAC" "No namespaced ArgoCD found" "Namespaced ArgoCD not configured"
    fi
}

main() {
    echo "=== Deployment & GitOps Validation (ADRs: 019, 030) ===" >&2

    validate_adr_019
    validate_adr_030

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
