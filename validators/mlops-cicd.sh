#!/bin/bash
# MLOps & CI/CD Validation Module
# Validates ADRs: 021, 023, 024, 025, 026, 042, 043

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

# ADR-021: Tekton Pipelines
validate_adr_021() {
    echo "Validating ADR-021: Tekton Pipelines..." >&2

    # Use pipelines.tekton.dev for Tekton v1 API
    local pipelines=$(oc get pipelines.tekton.dev -n self-healing-platform --no-headers 2>/dev/null | wc -l)
    local tasks=$(oc get task -n self-healing-platform --no-headers 2>/dev/null | wc -l)
    local recent_runs=$(oc get pipelinerun -n self-healing-platform --no-headers 2>/dev/null | head -5 | wc -l)
    # Fixed: Check for tekton-pipelines-controller (actual deployment name in OpenShift Pipelines)
    local tekton_operator=$(oc get deployment -n openshift-pipelines tekton-pipelines-controller --no-headers 2>/dev/null | wc -l)

    if [[ $pipelines -ge 4 ]] && [[ $tekton_operator -ge 1 ]]; then
        add_result "021" "PASS" "4+ pipelines operational" "Pipelines: $pipelines, Tasks: $tasks, Recent runs: $recent_runs" "Tekton CI/CD operational"
    elif [[ $pipelines -ge 2 ]]; then
        add_result "021" "PARTIAL" "4+ pipelines operational" "Pipelines: $pipelines, Tasks: $tasks" "Partial pipeline setup"
    else
        add_result "021" "FAIL" "4+ pipelines operational" "Pipelines: $pipelines" "Tekton not fully configured"
    fi
}

# ADR-023: S3 Configuration Pipeline
validate_adr_023() {
    echo "Validating ADR-023: S3 Configuration Pipeline..." >&2

    # Use pipelines.tekton.dev for Tekton v1 API
    local s3_pipeline=$(oc get pipelines.tekton.dev -n self-healing-platform --no-headers 2>/dev/null | grep -c "s3-config\|configure-s3" || echo "0")
    local s3_tasks=$(oc get task -n self-healing-platform --no-headers 2>/dev/null | grep -c "s3" || echo "0")
    local external_secrets=$(oc get externalsecret -n self-healing-platform --no-headers 2>/dev/null | wc -l)

    if [[ $s3_pipeline -ge 1 ]] && [[ $external_secrets -ge 1 ]]; then
        add_result "023" "PASS" "S3 pipeline with ExternalSecrets" "S3 pipeline: $s3_pipeline, Tasks: $s3_tasks, ExternalSecrets: $external_secrets" "S3 configuration automated"
    elif [[ $s3_tasks -ge 1 ]]; then
        add_result "023" "PARTIAL" "S3 pipeline with ExternalSecrets" "S3 tasks exist but pipeline incomplete" "Partial S3 automation"
    else
        add_result "023" "FAIL" "S3 pipeline with ExternalSecrets" "No S3 pipeline found" "S3 automation not configured"
    fi
}

# ADR-024: ExternalSecrets for S3
validate_adr_024() {
    echo "Validating ADR-024: ExternalSecrets for S3..." >&2

    local external_secrets=$(oc get externalsecret -n self-healing-platform --no-headers 2>/dev/null | wc -l)
    local synced_secrets=$(oc get externalsecret -n self-healing-platform -o json 2>/dev/null | jq '[.items[] | select(.status.conditions[]? | select(.type=="SecretSynced" and .status=="True"))] | length' || echo "0")
    local secret_store=$(oc get secretstore -n self-healing-platform --no-headers 2>/dev/null | wc -l)

    if [[ $external_secrets -ge 4 ]] && [[ $synced_secrets -eq $external_secrets ]]; then
        add_result "024" "PASS" "4 ExternalSecrets synced" "ExternalSecrets: $external_secrets, Synced: $synced_secrets, SecretStore: $secret_store" "Secret management operational"
    elif [[ $external_secrets -ge 2 ]]; then
        add_result "024" "PARTIAL" "4 ExternalSecrets synced" "ExternalSecrets: $external_secrets, Synced: $synced_secrets" "Partial secret sync"
    else
        add_result "024" "FAIL" "4 ExternalSecrets synced" "ExternalSecrets: $external_secrets" "ExternalSecrets not configured"
    fi
}

# ADR-025: S3 ObjectBucketClaim
validate_adr_025() {
    echo "Validating ADR-025: S3 ObjectBucketClaim..." >&2

    local obc=$(sanitize_number "$(oc get objectbucketclaim -n self-healing-platform --no-headers 2>/dev/null | wc -l)")
    local obc_bound=$(sanitize_number "$(oc get objectbucketclaim -n self-healing-platform --no-headers 2>/dev/null | grep -c Bound || echo 0)")
    local noobaa_endpoint=$(oc get route s3 -n openshift-storage -o jsonpath='{.spec.host}' 2>/dev/null || echo "NotFound")
    local noobaa_pods=$(sanitize_number "$(oc get pods -n openshift-storage -l app=noobaa --no-headers 2>/dev/null | grep -c Running || echo 0)")
    if [[ $obc_bound -ge 1 ]] && [[ $noobaa_pods -ge 4 ]] && [[ $noobaa_endpoint != "NotFound" ]]; then
        add_result "025" "PASS" "OBC Bound with NooBaa S3" "OBC: $obc_bound Bound, NooBaa pods: $noobaa_pods, Endpoint: $noobaa_endpoint" "S3 storage operational"
    elif [[ $obc -ge 1 ]]; then
        add_result "025" "PARTIAL" "OBC Bound with NooBaa S3" "OBC exists but not fully bound or NooBaa not ready" "S3 storage partially configured"
    else
        add_result "025" "FAIL" "OBC Bound with NooBaa S3" "No OBC found" "S3 storage not configured"
    fi
}

# ADR-026: External Secrets Operator
validate_adr_026() {
    echo "Validating ADR-026: External Secrets Operator..." >&2

    local eso_operator=$(sanitize_number "$(oc get deployment -n external-secrets-operator --no-headers 2>/dev/null | wc -l)")
    local eso_webhook=$(sanitize_number "$(oc get deployment -n external-secrets-operator external-secrets-webhook --no-headers 2>/dev/null | grep -c 1/1 || echo 0)")
    local eso_cert_controller=$(sanitize_number "$(oc get deployment -n external-secrets-operator external-secrets-cert-controller --no-headers 2>/dev/null | grep -c 1/1 || echo 0)")
    local secret_stores=$(sanitize_number "$(oc get secretstore --all-namespaces --no-headers 2>/dev/null | wc -l)")

    local ready_components=$((eso_webhook + eso_cert_controller))

    if [[ $eso_operator -ge 3 ]] && [[ $ready_components -ge 2 ]]; then
        add_result "026" "PASS" "ESO with 3 components" "Deployments: $eso_operator, Webhook: $eso_webhook, CertController: $eso_cert_controller, SecretStores: $secret_stores" "ESO fully operational"
    elif [[ $eso_operator -ge 1 ]]; then
        add_result "026" "PARTIAL" "ESO with 3 components" "Operator present but not all components ready" "ESO partially deployed"
    else
        add_result "026" "FAIL" "ESO with 3 components" "ESO operator not found" "ESO not deployed"
    fi
}

# ADR-042: ArgoCD Custom Health Checks
validate_adr_042() {
    echo "Validating ADR-042: ArgoCD Custom Health Checks..." >&2

    local argocd_cm=$(oc get configmap -n openshift-gitops argocd-cm -o json 2>/dev/null | jq -r '.data."resource.customizations"' || echo "NotFound")
    local health_checks=0
    if [[ $argocd_cm != "NotFound" ]] && [[ $argocd_cm != "null" ]]; then
        health_checks=$(echo "$argocd_cm" | grep -c "health.lua" || echo "0")
    fi

    local buildconfig_count=$(oc get buildconfig -n self-healing-platform --no-headers 2>/dev/null | wc -l)

    if [[ $health_checks -ge 1 ]] && [[ $buildconfig_count -ge 1 ]]; then
        add_result "042" "PASS" "Custom health checks configured" "Health checks: $health_checks, BuildConfigs: $buildconfig_count" "ArgoCD health monitoring operational"
    elif [[ $buildconfig_count -ge 1 ]]; then
        add_result "042" "PARTIAL" "Custom health checks configured" "BuildConfigs exist but custom health checks may not be configured" "Partial health monitoring"
    else
        add_result "042" "FAIL" "Custom health checks configured" "No BuildConfigs found" "Custom health checks not configured"
    fi
}

# ADR-043: Init Containers & Health Checks
validate_adr_043() {
    echo "Validating ADR-043: Init Containers & Health Checks..." >&2

    local pods_with_init=$(oc get pods -n self-healing-platform -o json 2>/dev/null | jq '[.items[] | select(.spec.initContainers | length > 0)] | length' || echo "0")
    local pods_with_probes=$(oc get pods -n self-healing-platform -o json 2>/dev/null | jq '[.items[] | select(.spec.containers[].startupProbe != null)] | length' || echo "0")

    # Check for healthcheck binary in deployments
    local healthcheck_binary=0
    if [[ -f "$SCRIPT_DIR/../cmd/healthcheck/main.go" ]] || [[ -f "$SCRIPT_DIR/../healthcheck/main.go" ]]; then
        healthcheck_binary=1
    fi

    if [[ $pods_with_init -ge 2 ]] && [[ $pods_with_probes -ge 2 ]]; then
        add_result "043" "PASS" "Init containers with probes" "Pods with init: $pods_with_init, Pods with probes: $pods_with_probes, Healthcheck binary: $healthcheck_binary" "Startup health checks operational"
    elif [[ $pods_with_probes -ge 1 ]]; then
        add_result "043" "PARTIAL" "Init containers with probes" "Some pods have probes configured" "Partial health check coverage"
    else
        add_result "043" "FAIL" "Init containers with probes" "No init containers or probes found" "Health checks not configured"
    fi
}

main() {
    echo "=== MLOps & CI/CD Validation (ADRs: 021, 023, 024, 025, 026, 042, 043) ===" >&2

    validate_adr_021
    validate_adr_023
    validate_adr_024
    validate_adr_025
    validate_adr_026
    validate_adr_042
    validate_adr_043

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
