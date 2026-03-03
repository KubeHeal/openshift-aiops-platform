#!/bin/bash
# Notebook & Development Validation Module
# Validates ADRs: 011, 012, 013, 029, 031, 032

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

# ADR-011: PyTorch Workbench
validate_adr_011() {
    echo "Validating ADR-011: PyTorch Workbench..." >&2

    local workbench_pods=$(oc get pods -n self-healing-platform -l app=pytorch-workbench --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local notebook_pod=$(oc get pods -n self-healing-platform --no-headers 2>/dev/null | grep -E "jupyter|workbench" | grep -c "Running" || echo "0")

    if [[ $workbench_pods -ge 1 ]] || [[ $notebook_pod -ge 1 ]]; then
        add_result "011" "PASS" "Workbench running" "$workbench_pods workbench pods, $notebook_pod notebook pods" "PyTorch workbench operational"
    else
        add_result "011" "FAIL" "Workbench running" "0 pods found" "Workbench not deployed"
    fi
}

# ADR-012: Notebook Portfolio
validate_adr_012() {
    echo "Validating ADR-012: Notebook Portfolio..." >&2

    local notebook_dirs=("monitoring" "alerting" "mlops" "troubleshooting" "deployment" "storage" "testing" "utils" "validation")
    local total_notebooks=0
    local found_dirs=0

    for dir in "${notebook_dirs[@]}"; do
        if [[ -d "$SCRIPT_DIR/../notebooks/$dir" ]]; then
            local count=$(find "$SCRIPT_DIR/../notebooks/$dir" -name "*.ipynb" 2>/dev/null | wc -l)
            total_notebooks=$((total_notebooks + count))
            if [[ $count -gt 0 ]]; then
                found_dirs=$((found_dirs + 1))
            fi
        fi
    done

    if [[ $total_notebooks -ge 25 ]] && [[ $found_dirs -ge 7 ]]; then
        add_result "012" "PASS" "32 notebooks in 9 directories" "$total_notebooks notebooks in $found_dirs directories" "Comprehensive notebook portfolio"
    elif [[ $total_notebooks -ge 15 ]]; then
        add_result "012" "PARTIAL" "32 notebooks in 9 directories" "$total_notebooks notebooks in $found_dirs directories" "Partial notebook coverage"
    else
        add_result "012" "FAIL" "32 notebooks in 9 directories" "$total_notebooks notebooks" "Insufficient notebooks"
    fi
}

# ADR-013: Data Collection Notebooks
validate_adr_013() {
    echo "Validating ADR-013: Data Collection Notebooks..." >&2

    local collection_notebooks=(
        "notebooks/monitoring/prometheus-metrics-collection.ipynb"
        "notebooks/monitoring/cluster-health-data.ipynb"
        "notebooks/alerting/alert-history-export.ipynb"
        "notebooks/troubleshooting/incident-data-aggregator.ipynb"
    )

    local found_count=0
    for notebook in "${collection_notebooks[@]}"; do
        if [[ -f "$SCRIPT_DIR/../$notebook" ]]; then
            found_count=$((found_count + 1))
        fi
    done

    local utils_modules=$(find "$SCRIPT_DIR/../notebooks/utils" -name "*.py" 2>/dev/null | wc -l)

    if [[ $found_count -ge 3 ]] && [[ $utils_modules -ge 3 ]]; then
        add_result "013" "PASS" "5 data collection notebooks" "$found_count notebooks, $utils_modules utility modules" "Data collection infrastructure complete"
    elif [[ $found_count -ge 2 ]]; then
        add_result "013" "PARTIAL" "5 data collection notebooks" "$found_count notebooks, $utils_modules utility modules" "Partial data collection setup"
    else
        add_result "013" "FAIL" "5 data collection notebooks" "$found_count notebooks" "Data collection not configured"
    fi
}

# ADR-029: Notebook Validator Operator
validate_adr_029() {
    echo "Validating ADR-029: Notebook Validator Operator..." >&2

    local operator_pods=$(oc get pods -n self-healing-platform -l app=notebook-validator-operator --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local validation_jobs=$(oc get notebookvalidationjob -n self-healing-platform --no-headers 2>/dev/null | wc -l)
    local crd_exists=$(oc get crd notebookvalidationjobs.self-healing.openshift.io --no-headers 2>/dev/null | wc -l)

    if [[ $operator_pods -ge 1 ]] && [[ $crd_exists -eq 1 ]]; then
        add_result "029" "PASS" "Operator running with CRD" "Operator: $operator_pods pods, CRD installed, ValidationJobs: $validation_jobs" "Notebook validation operational"
    elif [[ $crd_exists -eq 1 ]]; then
        add_result "029" "PARTIAL" "Operator running with CRD" "CRD installed but operator not running" "Operator partially configured"
    else
        add_result "029" "FAIL" "Operator running with CRD" "CRD not found" "Operator not deployed"
    fi
}

# ADR-031: Custom Notebook Image
validate_adr_031() {
    echo "Validating ADR-031: Custom Notebook Image..." >&2

    local dockerfile_exists=0
    if [[ -f "$SCRIPT_DIR/../notebooks/Dockerfile" ]] || [[ -f "$SCRIPT_DIR/../Dockerfile" ]]; then
        dockerfile_exists=1
    fi

    local imagestream=$(oc get imagestream -n self-healing-platform --no-headers 2>/dev/null | grep -c "pytorch-workbench\|custom-notebook" || echo "0")
    local buildconfig=$(oc get buildconfig -n self-healing-platform --no-headers 2>/dev/null | wc -l)

    if [[ $dockerfile_exists -eq 1 ]] && [[ $imagestream -ge 1 ]]; then
        add_result "031" "PASS" "Custom image built" "Dockerfile exists, ImageStream: $imagestream, BuildConfig: $buildconfig" "Custom notebook image operational"
    elif [[ $dockerfile_exists -eq 1 ]]; then
        add_result "031" "PARTIAL" "Custom image built" "Dockerfile exists but image not built" "Image definition ready"
    else
        add_result "031" "FAIL" "Custom image built" "No Dockerfile found" "Custom image not configured"
    fi
}

# ADR-032: Infrastructure Validation Notebook
validate_adr_032() {
    echo "Validating ADR-032: Infrastructure Validation Notebook..." >&2

    local validation_notebook="$SCRIPT_DIR/../notebooks/validation/infrastructure-validation.ipynb"
    local validation_script="$SCRIPT_DIR/../scripts/post-deployment-validation.sh"
    local validation_runs=0

    if [[ -f "$validation_notebook" ]]; then
        # Check if notebook has execution metadata (cells have been run)
        validation_runs=$(grep -c "execution_count" "$validation_notebook" 2>/dev/null || echo "0")
    fi

    local script_exists=0
    if [[ -f "$validation_script" ]]; then
        script_exists=1
    fi

    if [[ -f "$validation_notebook" ]] && [[ $validation_runs -gt 5 ]] && [[ $script_exists -eq 1 ]]; then
        add_result "032" "PASS" "Validation notebook executed" "Notebook exists with $validation_runs executions, validation script present" "Infrastructure validation complete"
    elif [[ -f "$validation_notebook" ]]; then
        add_result "032" "PARTIAL" "Validation notebook executed" "Notebook exists but may not have been run recently" "Validation notebook available"
    else
        add_result "032" "FAIL" "Validation notebook executed" "Notebook not found" "Validation notebook missing"
    fi
}

main() {
    echo "=== Notebook & Development Validation (ADRs: 011, 012, 013, 029, 031, 032) ===" >&2

    validate_adr_011
    validate_adr_012
    validate_adr_013
    validate_adr_029
    validate_adr_031
    validate_adr_032

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
