#!/bin/bash
# Post-Deployment Validation Script
# OpenShift AI Ops Platform
# Validates Pattern deployment, ArgoCD apps, and platform components

# Don't exit on errors - we want to run all checks
set -u

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Validation counters
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_CHECKS=8

# Helper functions
print_header() {
    echo -e "\n${BLUE}=====================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=====================================================================${NC}"
}

print_section() {
    echo -e "\n${CYAN}[$1/$TOTAL_CHECKS] $2${NC}"
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "  ${NC}$1${NC}"
}

check_result() {
    local status=$1
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}[PASS]${NC}"
        ((PASS_COUNT++))
    else
        echo -e "${RED}[FAIL]${NC}"
        ((FAIL_COUNT++))
    fi
}

# Get cluster info
get_cluster_info() {
    CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "unknown")
    CLUSTER_VERSION=$(oc version -o json 2>/dev/null | jq -r '.openshiftVersion // "unknown"')
}

# Main validation
print_header "OpenShift AI Ops Platform - Post-Deployment Validation"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
get_cluster_info
echo "Cluster: ${CLUSTER_DOMAIN}"
echo "OpenShift Version: ${CLUSTER_VERSION}"

# ============================================================
# 1. Pattern CR Validation
# ============================================================
print_section "1" "Pattern CR Status"
PATTERN_STATUS="FAIL"

if oc get pattern self-healing-platform -n openshift-operators &>/dev/null; then
    print_pass "Pattern CR exists: self-healing-platform"

    LAST_STEP=$(oc get pattern self-healing-platform -n openshift-operators -o jsonpath='{.status.lastStep}' 2>/dev/null || echo "unknown")
    print_info "Last step: ${LAST_STEP}"

    GIT_PATH=$(oc get pattern self-healing-platform -n openshift-operators -o jsonpath='{.status.path}' 2>/dev/null || echo "unknown")
    print_info "Git clone path: ${GIT_PATH}"

    CLUSTER_ID=$(oc get pattern self-healing-platform -n openshift-operators -o jsonpath='{.status.clusterID}' 2>/dev/null || echo "unknown")
    print_info "Cluster ID: ${CLUSTER_ID}"

    PATTERN_STATUS="PASS"
else
    print_fail "Pattern CR not found"
fi

check_result "$PATTERN_STATUS"

# ============================================================
# 2. ArgoCD Applications
# ============================================================
print_section "2" "ArgoCD Applications"
ARGOCD_STATUS="FAIL"

if oc get applications.argoproj.io -n openshift-gitops &>/dev/null; then
    APP_COUNT=$(oc get applications.argoproj.io -n openshift-gitops --no-headers 2>/dev/null | wc -l)
    print_info "Found ${APP_COUNT} ArgoCD application(s)"

    if [ "$APP_COUNT" -gt 0 ]; then
        echo ""
        while IFS= read -r line; do
            APP_NAME=$(echo "$line" | awk '{print $1}')
            SYNC_STATUS=$(echo "$line" | awk '{print $2}')
            HEALTH_STATUS=$(echo "$line" | awk '{print $3}')

            if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH_STATUS" = "Healthy" ]; then
                print_pass "Application: ${APP_NAME} - ${SYNC_STATUS}/${HEALTH_STATUS}"
            elif [ "$SYNC_STATUS" = "Unknown" ]; then
                print_warn "Application: ${APP_NAME} - ${SYNC_STATUS}/${HEALTH_STATUS} (syncing or error)"
            else
                print_fail "Application: ${APP_NAME} - ${SYNC_STATUS}/${HEALTH_STATUS}"
            fi
        done < <(oc get applications.argoproj.io -n openshift-gitops --no-headers 2>/dev/null)

        # Check for sync errors
        echo ""
        print_info "Checking for sync errors..."
        if oc get application.argoproj.io self-healing-platform-hub -n openshift-gitops &>/dev/null; then
            ERROR_MSG=$(oc get application.argoproj.io self-healing-platform-hub -n openshift-gitops -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || echo "")
            if [ -n "$ERROR_MSG" ]; then
                print_fail "Sync Error Detected:"
                echo "$ERROR_MSG" | fold -w 80 -s | sed 's/^/    /'
            else
                print_pass "No sync errors"
                ARGOCD_STATUS="PASS"
            fi
        fi
    fi
else
    print_fail "Cannot access ArgoCD applications"
fi

check_result "$ARGOCD_STATUS"

# ============================================================
# 3. Namespace Verification
# ============================================================
print_section "3" "Namespace Verification"
NAMESPACE_STATUS="FAIL"

if oc get namespace self-healing-platform &>/dev/null; then
    print_pass "Namespace 'self-healing-platform' exists"

    NS_STATUS=$(oc get namespace self-healing-platform -o jsonpath='{.status.phase}' 2>/dev/null)
    print_info "Status: ${NS_STATUS}"

    # Check for unwanted example namespaces
    EXAMPLE_NS=$(oc get namespaces --no-headers 2>/dev/null | grep -E "imperative|self-healing-platform-example" || true)
    if [ -z "$EXAMPLE_NS" ]; then
        print_pass "No example namespaces found (good)"
        NAMESPACE_STATUS="PASS"
    else
        print_fail "Example namespaces found (should not exist):"
        echo "$EXAMPLE_NS" | sed 's/^/    /'
    fi
else
    print_fail "Namespace 'self-healing-platform' not found"
fi

check_result "$NAMESPACE_STATUS"

# ============================================================
# 4. Resource Deployment
# ============================================================
print_section "4" "Resource Deployment"
RESOURCE_STATUS="PASS"

# Pods
POD_COUNT=$(oc get pods -n self-healing-platform --no-headers 2>/dev/null | wc -l || echo "0")
print_info "Total pods: ${POD_COUNT}"

if [ "$POD_COUNT" -eq 0 ]; then
    print_warn "No pods found in self-healing-platform namespace"
    RESOURCE_STATUS="FAIL"
fi

# Deployments
DEPLOY_COUNT=$(oc get deployments -n self-healing-platform --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$DEPLOY_COUNT" -gt 0 ]; then
    print_info "Deployments found: ${DEPLOY_COUNT}"
    while IFS= read -r line; do
        DEPLOY_NAME=$(echo "$line" | awk '{print $1}')
        READY=$(echo "$line" | awk '{print $2}')
        print_info "  ${DEPLOY_NAME}: ${READY}"
    done < <(oc get deployments -n self-healing-platform --no-headers 2>/dev/null)
else
    print_info "No deployments found"
fi

# ObjectBucketClaim
if oc get objectbucketclaim -n self-healing-platform &>/dev/null; then
    OBC_COUNT=$(oc get objectbucketclaim -n self-healing-platform --no-headers 2>/dev/null | wc -l)
    if [ "$OBC_COUNT" -gt 0 ]; then
        print_pass "ObjectBucketClaim(s) found: ${OBC_COUNT}"
    else
        print_info "No ObjectBucketClaims found"
    fi
else
    print_info "ObjectBucketClaim CRD not available"
fi

# SecretStore
if oc get secretstore -n self-healing-platform &>/dev/null; then
    SS_COUNT=$(oc get secretstore -n self-healing-platform --no-headers 2>/dev/null | wc -l)
    if [ "$SS_COUNT" -gt 0 ]; then
        print_pass "SecretStore(s) found: ${SS_COUNT}"
    else
        print_warn "No SecretStores found"
    fi
else
    print_warn "SecretStore CRD not available"
fi

# ExternalSecrets
if oc get externalsecrets -n self-healing-platform &>/dev/null; then
    ES_COUNT=$(oc get externalsecrets -n self-healing-platform --no-headers 2>/dev/null | wc -l)
    if [ "$ES_COUNT" -gt 0 ]; then
        print_pass "ExternalSecret(s) found: ${ES_COUNT}"
    else
        print_info "No ExternalSecrets found"
    fi
else
    print_info "ExternalSecret CRD not available"
fi

check_result "$RESOURCE_STATUS"

# ============================================================
# 5. Pod Health Validation (Comprehensive)
# ============================================================
print_section "5" "Pod Health Validation"
POD_HEALTH_STATUS="PASS"

if [ "$POD_COUNT" -gt 0 ]; then
    echo ""
    RUNNING_PODS=0
    PENDING_PODS=0
    FAILED_PODS=0
    UNHEALTHY_PODS=0

    while IFS= read -r line; do
        POD_NAME=$(echo "$line" | awk '{print $1}')
        READY=$(echo "$line" | awk '{print $2}')
        STATUS=$(echo "$line" | awk '{print $3}')
        RESTARTS=$(echo "$line" | awk '{print $4}')
        AGE=$(echo "$line" | awk '{print $5}')

        echo -e "\n${CYAN}Pod: ${POD_NAME}${NC}"

        # Check pod phase
        if [ "$STATUS" = "Running" ]; then
            print_pass "Status: ${STATUS}"
            ((RUNNING_PODS++))
        elif [ "$STATUS" = "Pending" ]; then
            print_warn "Status: ${STATUS}"
            ((PENDING_PODS++))
            ((UNHEALTHY_PODS++))
            POD_HEALTH_STATUS="FAIL"
        else
            print_fail "Status: ${STATUS}"
            ((FAILED_PODS++))
            ((UNHEALTHY_PODS++))
            POD_HEALTH_STATUS="FAIL"
        fi

        # Check container readiness
        READY_CONTAINERS=$(echo "$READY" | cut -d'/' -f1)
        TOTAL_CONTAINERS=$(echo "$READY" | cut -d'/' -f2)
        if [ "$READY_CONTAINERS" = "$TOTAL_CONTAINERS" ]; then
            print_pass "Ready: ${READY}"
        else
            print_fail "Ready: ${READY} (not all containers ready)"
            ((UNHEALTHY_PODS++))
            POD_HEALTH_STATUS="FAIL"
        fi

        # Check restart count
        RESTART_NUM=$(echo "$RESTARTS" | grep -oE '[0-9]+' | head -1)
        if [ -n "$RESTART_NUM" ] && [ "$RESTART_NUM" -gt 3 ]; then
            print_warn "Restarts: ${RESTARTS} (high restart count)"
            POD_HEALTH_STATUS="FAIL"
        else
            print_pass "Restarts: ${RESTARTS}"
        fi

        print_info "Age: ${AGE}"

        # Check for container issues
        if [ "$STATUS" != "Running" ] || [ "$READY_CONTAINERS" != "$TOTAL_CONTAINERS" ]; then
            print_info "Container States:"
            oc get pod "$POD_NAME" -n self-healing-platform -o jsonpath='{range .status.containerStatuses[*]}{.name}{": "}{.state}{"\n"}{end}' 2>/dev/null | sed 's/^/    /' || true

            # Show recent events
            print_info "Recent Events:"
            oc get events -n self-healing-platform --field-selector involvedObject.name="$POD_NAME" --sort-by='.lastTimestamp' 2>/dev/null | tail -5 | sed 's/^/    /' || true

            # Show container logs if failed
            if [ "$STATUS" = "CrashLoopBackOff" ] || [ "$STATUS" = "Error" ]; then
                print_info "Last 20 log lines:"
                oc logs "$POD_NAME" -n self-healing-platform --tail=20 2>/dev/null | sed 's/^/    /' || echo "    (unable to retrieve logs)"
            fi
        fi

    done < <(oc get pods -n self-healing-platform --no-headers 2>/dev/null)

    echo ""
    print_info "Pod Summary:"
    print_info "  Running: ${RUNNING_PODS}"
    print_info "  Pending: ${PENDING_PODS}"
    print_info "  Failed: ${FAILED_PODS}"
    print_info "  Unhealthy: ${UNHEALTHY_PODS}"

    if [ "$UNHEALTHY_PODS" -eq 0 ] && [ "$RUNNING_PODS" -gt 0 ]; then
        print_pass "All pods are healthy"
    elif [ "$POD_COUNT" -eq 0 ]; then
        print_warn "No pods to validate"
        POD_HEALTH_STATUS="FAIL"
    fi
else
    print_warn "No pods found in namespace"
    POD_HEALTH_STATUS="FAIL"
fi

check_result "$POD_HEALTH_STATUS"

# ============================================================
# 6. Platform Component Health
# ============================================================
print_section "6" "Platform Component Health"
COMPONENT_STATUS="PASS"

echo ""
# Coordination Engine
if oc get pods -n self-healing-platform -l app=coordination-engine &>/dev/null 2>&1; then
    CE_POD=$(oc get pods -n self-healing-platform -l app=coordination-engine -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$CE_POD" ]; then
        CE_STATUS=$(oc get pod "$CE_POD" -n self-healing-platform -o jsonpath='{.status.phase}' 2>/dev/null)
        CE_READY=$(oc get pod "$CE_POD" -n self-healing-platform -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
        if [ "$CE_STATUS" = "Running" ] && [ "$CE_READY" = "true" ]; then
            print_pass "Coordination Engine: Running and ready"
        else
            print_fail "Coordination Engine: ${CE_STATUS}, ready=${CE_READY}"
            COMPONENT_STATUS="FAIL"
        fi
    else
        print_warn "Coordination Engine: Pod not found"
    fi
else
    print_info "Coordination Engine: Not deployed yet"
fi

# Workbench
if oc get pods -n self-healing-platform -l app=self-healing-workbench &>/dev/null 2>&1; then
    WB_POD=$(oc get pods -n self-healing-platform -l app=self-healing-workbench -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$WB_POD" ]; then
        WB_STATUS=$(oc get pod "$WB_POD" -n self-healing-platform -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$WB_STATUS" = "Running" ]; then
            print_pass "Workbench: Running"
        else
            print_fail "Workbench: ${WB_STATUS}"
            COMPONENT_STATUS="FAIL"
        fi
    else
        print_warn "Workbench: Pod not found"
    fi
else
    print_info "Workbench: Not deployed yet"
fi

# Model Serving (KServe InferenceServices)
if oc get inferenceservices -n self-healing-platform &>/dev/null 2>&1; then
    ISVC_COUNT=$(oc get inferenceservices -n self-healing-platform --no-headers 2>/dev/null | wc -l)
    if [ "$ISVC_COUNT" -gt 0 ]; then
        print_info "InferenceService(s) found: ${ISVC_COUNT}"
        while IFS= read -r line; do
            ISVC_NAME=$(echo "$line" | awk '{print $1}')
            ISVC_READY=$(echo "$line" | awk '{print $2}')
            print_info "  ${ISVC_NAME}: ${ISVC_READY}"
        done < <(oc get inferenceservices -n self-healing-platform --no-headers 2>/dev/null)
    else
        print_info "Model Serving: No InferenceServices deployed"
    fi
else
    print_info "Model Serving: KServe not available"
fi

# External Secrets sync status
if oc get externalsecrets -n self-healing-platform &>/dev/null 2>&1; then
    ES_SYNCED=0
    ES_FAILED=0
    while IFS= read -r es_name; do
        ES_STATUS=$(oc get externalsecret "$es_name" -n self-healing-platform -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [ "$ES_STATUS" = "True" ]; then
            ((ES_SYNCED++))
        else
            ((ES_FAILED++))
        fi
    done < <(oc get externalsecrets -n self-healing-platform -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    if [ "$ES_FAILED" -eq 0 ] && [ "$ES_SYNCED" -gt 0 ]; then
        print_pass "External Secrets: ${ES_SYNCED} synced, ${ES_FAILED} failed"
    elif [ "$ES_FAILED" -gt 0 ]; then
        print_fail "External Secrets: ${ES_SYNCED} synced, ${ES_FAILED} failed"
        COMPONENT_STATUS="FAIL"
    fi
fi

# Storage (PVCs)
PVC_COUNT=$(oc get pvc -n self-healing-platform --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$PVC_COUNT" -gt 0 ]; then
    PVC_BOUND=$(oc get pvc -n self-healing-platform --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
    if [ "$PVC_BOUND" -eq "$PVC_COUNT" ]; then
        print_pass "Storage: ${PVC_BOUND}/${PVC_COUNT} PVCs bound"
    else
        print_fail "Storage: ${PVC_BOUND}/${PVC_COUNT} PVCs bound"
        COMPONENT_STATUS="FAIL"
    fi
else
    print_info "Storage: No PVCs found"
fi

check_result "$COMPONENT_STATUS"

# ============================================================
# 7. InferenceService Model Health Check
# ============================================================
print_section "7" "InferenceService Model Health Check"
INFERENCE_STATUS="PASS"

if oc get inferenceservices -n self-healing-platform &>/dev/null 2>&1; then
    ISVC_COUNT=$(oc get inferenceservices -n self-healing-platform --no-headers 2>/dev/null | wc -l)
    if [ "$ISVC_COUNT" -gt 0 ]; then
        echo ""
        print_info "Testing inference endpoints for ${ISVC_COUNT} InferenceService(s)..."
        
        while IFS= read -r line; do
            ISVC_NAME=$(echo "$line" | awk '{print $1}')
            ISVC_READY=$(echo "$line" | awk '{print $2}')
            
            echo ""
            echo -e "${CYAN}Testing: ${ISVC_NAME}${NC}"
            print_info "Status: ${ISVC_READY}"
            
            # Get predictor pod IP (RawDeployment mode uses headless service)
            POD_IP=$(oc get pods -n self-healing-platform \
              -l serving.kserve.io/inferenceservice="$ISVC_NAME" \
              -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "")
            
            if [ -z "$POD_IP" ]; then
                print_fail "No predictor pod found for ${ISVC_NAME}"
                INFERENCE_STATUS="FAIL"
                continue
            fi
            
            print_info "Pod IP: ${POD_IP}"
            
            # Determine test data size based on model name
            if [ "$ISVC_NAME" = "anomaly-detector" ]; then
                TEST_DATA_SIZE=45
            elif [ "$ISVC_NAME" = "predictive-analytics" ]; then
                TEST_DATA_SIZE=120
            else
                TEST_DATA_SIZE=45  # Default
            fi
            
            # Generate test payload (simple array of random floats)
            TEST_PAYLOAD=$(python3 -c "
import json
import random
random.seed(42)
test_data = [round(random.random(), 4) for _ in range($TEST_DATA_SIZE)]
print(json.dumps({'instances': [test_data]}))
" 2>/dev/null || echo "")
            
            if [ -z "$TEST_PAYLOAD" ]; then
                print_warn "Could not generate test payload (python3 not available), skipping test"
                continue
            fi
            
            # Test inference endpoint
            URL="http://${POD_IP}:8080/v1/models/${ISVC_NAME}:predict"
            print_info "Testing endpoint: ${URL}"
            
            # Retry logic (service might be starting up)
            MAX_RETRIES=5
            RETRY_DELAY=5
            TEST_PASSED=false
            
            for attempt in $(seq 1 $MAX_RETRIES); do
                print_info "Attempt ${attempt}/${MAX_RETRIES}..."
                
                # Send prediction request
                RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$URL" \
                  -H "Content-Type: application/json" \
                  -d "$TEST_PAYLOAD" \
                  --max-time 10 2>/dev/null || echo "")
                
                HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
                RESPONSE_BODY=$(echo "$RESPONSE" | head -n-1)
                
                if [ "$HTTP_CODE" = "200" ]; then
                    # Check if response contains predictions (not an error)
                    if echo "$RESPONSE_BODY" | grep -q "predictions\|predictions\|\"error\""; then
                        if echo "$RESPONSE_BODY" | grep -q "\"error\""; then
                            ERROR_MSG=$(echo "$RESPONSE_BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('error', 'Unknown error'))" 2>/dev/null || echo "Unknown error")
                            if echo "$ERROR_MSG" | grep -qi "model.*not.*exist\|ModelMissingError"; then
                                print_fail "Model not loaded: ${ERROR_MSG}"
                                print_info "This indicates the predictor started before the model was trained."
                                print_info "Solution: Wait for restart-predictors-after-models-ready job to complete, or manually restart:"
                                print_info "  oc rollout restart deployment/${ISVC_NAME}-predictor -n self-healing-platform"
                                INFERENCE_STATUS="FAIL"
                                TEST_PASSED=false
                                break
                            else
                                print_fail "Inference error: ${ERROR_MSG}"
                                INFERENCE_STATUS="FAIL"
                                TEST_PASSED=false
                                break
                            fi
                        else
                            print_pass "Inference successful (HTTP ${HTTP_CODE})"
                            print_info "Response preview: $(echo "$RESPONSE_BODY" | head -c 100)..."
                            TEST_PASSED=true
                            break
                        fi
                    else
                        print_pass "Inference successful (HTTP ${HTTP_CODE})"
                        print_info "Response: ${RESPONSE_BODY}"
                        TEST_PASSED=true
                        break
                    fi
                elif [ "$HTTP_CODE" = "000" ] || [ -z "$HTTP_CODE" ]; then
                    print_warn "Connection failed (service may be starting up)"
                    if [ $attempt -lt $MAX_RETRIES ]; then
                        print_info "Retrying in ${RETRY_DELAY}s..."
                        sleep $RETRY_DELAY
                    fi
                else
                    print_fail "Unexpected HTTP status: ${HTTP_CODE}"
                    print_info "Response: ${RESPONSE_BODY}"
                    INFERENCE_STATUS="FAIL"
                    TEST_PASSED=false
                    break
                fi
            done
            
            if [ "$TEST_PASSED" = false ]; then
                print_fail "Inference test failed for ${ISVC_NAME} after ${MAX_RETRIES} attempts"
                INFERENCE_STATUS="FAIL"
            fi
            
        done < <(oc get inferenceservices -n self-healing-platform --no-headers 2>/dev/null)
        
        if [ "$INFERENCE_STATUS" = "PASS" ]; then
            print_pass "All inference endpoints are healthy and serving predictions"
        fi
    else
        print_info "No InferenceServices found (model serving not deployed)"
    fi
else
    print_info "KServe not available (InferenceService CRD not installed)"
fi

check_result "$INFERENCE_STATUS"

# ============================================================
# 8. Error Diagnostics
# ============================================================
print_section "8" "Error Diagnostics"

echo ""
# ArgoCD Application Errors
if oc get application.argoproj.io self-healing-platform-hub -n openshift-gitops &>/dev/null; then
    ERROR_CONDITIONS=$(oc get application.argoproj.io self-healing-platform-hub -n openshift-gitops -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")]}' 2>/dev/null || echo "")
    if [ -n "$ERROR_CONDITIONS" ]; then
        print_fail "ArgoCD Application Error Found:"
        echo "$ERROR_CONDITIONS" | jq -r '.message' 2>/dev/null | fold -w 80 -s | sed 's/^/    /' || echo "$ERROR_CONDITIONS" | sed 's/^/    /'

        # Suggest fix based on error
        if echo "$ERROR_CONDITIONS" | grep -q "disabled"; then
            echo ""
            print_info "Suggested Fix:"
            print_info "  The clustergroup chart expects operators with 'disabled' field."
            print_info "  Current values-hub.yaml uses 'enabled: true/false' structure."
            print_info "  Need to update operator definitions to match chart expectations."
        fi
    else
        print_pass "No ArgoCD application errors"
    fi
fi

# Pattern Operator Logs
echo ""
print_info "Pattern Operator Recent Activity:"
oc logs -n openshift-operators deployment/patterns-operator-controller-manager --tail=10 2>/dev/null | grep -v "Counting\|Compressing" | sed 's/^/    /' || echo "    (unable to retrieve logs)"

# Recent Events in Platform Namespace
echo ""
print_info "Recent Events in self-healing-platform namespace:"
oc get events -n self-healing-platform --sort-by='.lastTimestamp' 2>/dev/null | tail -10 | sed 's/^/    /' || echo "    (no events found)"

# ============================================================
# Summary Report
# ============================================================
print_header "Summary Report"

HEALTH_SCORE=$((PASS_COUNT * 100 / TOTAL_CHECKS))

echo -e "\n${CYAN}Overall Health Score: ${HEALTH_SCORE}% (${PASS_COUNT}/${TOTAL_CHECKS} checks passed)${NC}"
echo ""

if [ "$HEALTH_SCORE" -eq 100 ]; then
    print_pass "Deployment is fully healthy and operational"
elif [ "$HEALTH_SCORE" -ge 70 ]; then
    print_warn "Deployment is mostly healthy but has some issues"
elif [ "$HEALTH_SCORE" -ge 40 ]; then
    print_warn "Deployment has significant issues requiring attention"
else
    print_fail "Deployment is unhealthy and requires immediate attention"
fi

echo ""
echo -e "${CYAN}RECOMMENDATIONS:${NC}"
echo ""

if [ "$ARGOCD_STATUS" = "FAIL" ]; then
    echo "1. Fix ArgoCD Application Sync Error:"
    echo "   - The Helm template error indicates operator configuration mismatch"
    echo "   - Update values-hub.yaml operator definitions to use 'disabled' field"
    echo "   - Commit changes to Git and allow ArgoCD to resync"
fi

if [ "$POD_HEALTH_STATUS" = "FAIL" ] && [ "$POD_COUNT" -eq 0 ]; then
    echo "2. No Pods Deployed:"
    echo "   - ArgoCD application must sync successfully first"
    echo "   - Fix the Helm template error before pods can be created"
fi

if [ "$INFERENCE_STATUS" = "FAIL" ]; then
    echo "4. InferenceService Model Not Loaded:"
    echo "   - Predictor pods started before models were trained (race condition)"
    echo "   - Wait for restart-predictors-after-models-ready job to complete"
    echo "   - Or manually restart: oc rollout restart deployment/<model-name>-predictor -n self-healing-platform"
    echo "   - Reference: Issue #34, ADR-054"
fi

if [ "$NAMESPACE_STATUS" = "FAIL" ]; then
    echo "3. Create Required Namespace:"
    echo "   - Run: oc create namespace self-healing-platform"
fi

echo ""
echo -e "${CYAN}NEXT STEPS:${NC}"
echo ""

if [ "$HEALTH_SCORE" -lt 70 ]; then
    echo "1. Review error diagnostics above"
    echo "2. Fix ArgoCD application sync error (operator configuration)"
    echo "3. Re-run this validation script after fixes"
    echo "4. Monitor pod deployment progress"
else
    echo "1. Monitor application health in ArgoCD"
    echo "2. Access platform components via OpenShift Console"
    echo "3. Run integration tests to verify functionality"
fi

echo ""
print_header "Validation Complete"
echo ""

# Exit with status based on health score
if [ "$HEALTH_SCORE" -ge 70 ]; then
    exit 0
else
    exit 1
fi
