# Bootstrap Testing Guide

This guide provides comprehensive testing procedures for the Self-Healing Platform Bootstrap system, ensuring reliable deployment automation.

## 🎯 **Testing Overview**

The bootstrap system requires testing at multiple levels:
1. **Unit Testing**: Individual script functions and Kustomize configurations
2. **Integration Testing**: End-to-end deployment workflows
3. **Environment Testing**: Development and production environment validation
4. **Failure Testing**: Error handling and recovery scenarios
5. **Performance Testing**: Deployment timing and resource usage

## 🧪 **Pre-Deployment Testing**

### **1. Container Image Testing**

```bash
# Test image build process
./build-images.sh

# Verify images are created
podman images | grep -E "(coordination-engine|anomaly-detector)"

# Test coordination engine locally
podman run --rm -p 8080:8080 -p 8090:8090 coordination-engine:latest &
sleep 10

# Test health endpoint
curl -f http://localhost:8080/health
echo "Health check: $?"

# Test metrics endpoint
curl -f http://localhost:8090/metrics
echo "Metrics check: $?"

# Cleanup
pkill -f coordination-engine
```

### **2. Kustomize Configuration Testing**

```bash
# Validate base configuration
kustomize build k8s/base/
echo "Base build status: $?"

# Validate development overlay
kustomize build k8s/overlays/development/
echo "Development build status: $?"

# Validate production overlay
kustomize build k8s/overlays/production/
echo "Production build status: $?"

# Test dry-run deployment
kustomize build k8s/overlays/development/ | oc apply --dry-run=client -f -
echo "Dry-run status: $?"

# Validate YAML syntax
find k8s/ -name "*.yaml" -exec yamllint {} \;
```

### **3. Script Validation Testing**

```bash
# Test bootstrap script help
./bootstrap.sh --help
echo "Help display status: $?"

# Test invalid environment parameter
./bootstrap.sh --environment invalid 2>&1 | grep -q "Unknown option"
echo "Error handling status: $?"

# Test prerequisite checking (without deployment)
# Modify bootstrap.sh temporarily to exit after prerequisites
sed -i.bak 's/phase1_kustomize_deployment/echo "Prerequisites passed"; exit 0/' bootstrap.sh
./bootstrap.sh --environment development
PREREQ_STATUS=$?
mv bootstrap.sh.bak bootstrap.sh
echo "Prerequisites status: $PREREQ_STATUS"
```

## 🚀 **Deployment Testing**

### **1. Development Environment Testing**

```bash
# Full development deployment test
echo "=== Development Deployment Test ==="
./bootstrap.sh --environment development 2>&1 | tee deployment-dev.log

# Check deployment status
DEPLOYMENT_STATUS=$?
echo "Deployment exit code: $DEPLOYMENT_STATUS"

# Verify namespace creation
oc get namespace self-healing-platform-dev
echo "Namespace status: $?"

# Check all pods are running
oc get pods -n self-healing-platform-dev
PODS_READY=$(oc get pods -n self-healing-platform-dev --no-headers | grep -c "Running")
TOTAL_PODS=$(oc get pods -n self-healing-platform-dev --no-headers | wc -l)
echo "Pods ready: $PODS_READY/$TOTAL_PODS"

# Test service accessibility
oc port-forward -n self-healing-platform-dev svc/coordination-engine 8080:8080 &
PF_PID=$!
sleep 5
curl -f http://localhost:8080/health
HEALTH_STATUS=$?
kill $PF_PID
echo "Service health status: $HEALTH_STATUS"
```

### **2. Validation Testing**

```bash
# Run comprehensive validation
echo "=== Validation Testing ==="
./validate_bootstrap.sh 2>&1 | tee validation.log

VALIDATION_STATUS=$?
echo "Validation exit code: $VALIDATION_STATUS"

# Count passed/failed checks
PASSED_CHECKS=$(grep -c "✅" validation.log)
FAILED_CHECKS=$(grep -c "❌" validation.log)
WARNING_CHECKS=$(grep -c "⚠️" validation.log)

echo "Validation Results:"
echo "  Passed: $PASSED_CHECKS"
echo "  Failed: $FAILED_CHECKS"
echo "  Warnings: $WARNING_CHECKS"

# Check critical validations
CRITICAL_FAILURES=$(grep -A5 -B5 "❌.*critical" validation.log | wc -l)
echo "Critical failures: $CRITICAL_FAILURES"
```

### **3. Component Functionality Testing**

```bash
# Test Jupyter notebook accessibility
echo "=== Component Testing ==="

# Check if notebook is ready
NOTEBOOK_STATUS=$(oc get notebook self-healing-workbench -n self-healing-platform-dev -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
echo "Notebook ready status: $NOTEBOOK_STATUS"

# Test model serving endpoints (if deployed)
ANOMALY_DETECTOR=$(oc get inferenceservice anomaly-detector -n self-healing-platform-dev -o jsonpath='{.status.url}' 2>/dev/null)
if [ -n "$ANOMALY_DETECTOR" ]; then
    echo "Anomaly detector URL: $ANOMALY_DETECTOR"
    # Test with sample data (if accessible)
    # curl -X POST "$ANOMALY_DETECTOR/v1/models/anomaly-detector:predict" -d '{"instances": [[1,2,3,4,5]]}'
fi

# Test Prometheus integration
PROMETHEUS_TARGETS=$(oc get servicemonitor self-healing-platform-monitor -n self-healing-platform-dev -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null)
echo "Prometheus targets configured: $?"

# Test storage accessibility
PVC_STATUS=$(oc get pvc -n self-healing-platform-dev --no-headers | grep -c "Bound")
TOTAL_PVCS=$(oc get pvc -n self-healing-platform-dev --no-headers | wc -l)
echo "PVCs bound: $PVC_STATUS/$TOTAL_PVCS"
```

## 🔄 **Failure Scenario Testing**

### **1. Prerequisite Failure Testing**

```bash
# Test cluster access failure
echo "=== Prerequisite Failure Testing ==="

# Temporarily break cluster access
export KUBECONFIG="/tmp/invalid-kubeconfig"
./bootstrap.sh --environment development 2>&1 | grep -q "Not logged into OpenShift"
CLUSTER_FAIL_TEST=$?
unset KUBECONFIG
echo "Cluster access failure test: $CLUSTER_FAIL_TEST"

# Test missing operator scenario
# (This would require temporarily removing an operator, which is destructive)
echo "Operator failure test: SKIPPED (destructive)"
```

### **2. Deployment Failure Testing**

```bash
# Test invalid Kustomize configuration
echo "=== Deployment Failure Testing ==="

# Create invalid configuration
cp k8s/base/kustomization.yaml k8s/base/kustomization.yaml.bak
echo "invalid: yaml: content" >> k8s/base/kustomization.yaml

# Test deployment with invalid config
./bootstrap.sh --environment development 2>&1 | grep -q "Failed to build Kustomize"
INVALID_CONFIG_TEST=$?

# Restore configuration
mv k8s/base/kustomization.yaml.bak k8s/base/kustomization.yaml
echo "Invalid configuration test: $INVALID_CONFIG_TEST"

# Test resource quota exceeded (if applicable)
# This would require setting up resource quotas
echo "Resource quota test: SKIPPED (requires quota setup)"
```

### **3. Recovery Testing**

```bash
# Test deployment cleanup and retry
echo "=== Recovery Testing ==="

# Deploy once
./bootstrap.sh --environment development > /dev/null 2>&1

# Delete some resources to simulate partial failure
oc delete deployment coordination-engine -n self-healing-platform-dev --ignore-not-found

# Retry deployment
./bootstrap.sh --environment development 2>&1 | tee recovery.log
RECOVERY_STATUS=$?

# Check if missing resources were recreated
oc get deployment coordination-engine -n self-healing-platform-dev
RECOVERY_SUCCESS=$?

echo "Recovery test status: $RECOVERY_STATUS"
echo "Resource recreation: $RECOVERY_SUCCESS"
```

## 📊 **Performance Testing**

### **1. Deployment Timing**

```bash
# Measure deployment time
echo "=== Performance Testing ==="

# Clean environment
oc delete namespace self-healing-platform-dev --ignore-not-found
oc wait --for=delete namespace/self-healing-platform-dev --timeout=300s

# Time the deployment
START_TIME=$(date +%s)
./bootstrap.sh --environment development > /dev/null 2>&1
DEPLOYMENT_STATUS=$?
END_TIME=$(date +%s)

DEPLOYMENT_TIME=$((END_TIME - START_TIME))
echo "Deployment time: ${DEPLOYMENT_TIME}s"
echo "Deployment status: $DEPLOYMENT_STATUS"

# Time validation
START_TIME=$(date +%s)
./validate_bootstrap.sh > /dev/null 2>&1
VALIDATION_STATUS=$?
END_TIME=$(date +%s)

VALIDATION_TIME=$((END_TIME - START_TIME))
echo "Validation time: ${VALIDATION_TIME}s"
echo "Validation status: $VALIDATION_STATUS"
```

### **2. Resource Usage Testing**

```bash
# Monitor resource usage during deployment
echo "=== Resource Usage Testing ==="

# Get baseline resource usage
BASELINE_CPU=$(oc adm top nodes --no-headers | awk '{sum+=$3} END {print sum}')
BASELINE_MEMORY=$(oc adm top nodes --no-headers | awk '{sum+=$5} END {print sum}')

echo "Baseline CPU: ${BASELINE_CPU}m"
echo "Baseline Memory: ${BASELINE_MEMORY}Mi"

# Deploy and monitor
./bootstrap.sh --environment development &
DEPLOY_PID=$!

# Monitor during deployment
for i in {1..10}; do
    sleep 30
    if ! kill -0 $DEPLOY_PID 2>/dev/null; then
        break
    fi

    CURRENT_CPU=$(oc adm top nodes --no-headers | awk '{sum+=$3} END {print sum}')
    CURRENT_MEMORY=$(oc adm top nodes --no-headers | awk '{sum+=$5} END {print sum}')

    echo "Time ${i}0s - CPU: ${CURRENT_CPU}m, Memory: ${CURRENT_MEMORY}Mi"
done

wait $DEPLOY_PID
FINAL_STATUS=$?

# Get final resource usage
FINAL_CPU=$(oc adm top nodes --no-headers | awk '{sum+=$3} END {print sum}')
FINAL_MEMORY=$(oc adm top nodes --no-headers | awk '{sum+=$5} END {print sum}')

echo "Final CPU: ${FINAL_CPU}m"
echo "Final Memory: ${FINAL_MEMORY}Mi"
echo "Deployment status: $FINAL_STATUS"
```

## 🧹 **Cleanup Testing**

### **1. Complete Environment Cleanup**

```bash
# Test cleanup procedures
echo "=== Cleanup Testing ==="

# Record initial state
INITIAL_NAMESPACES=$(oc get namespaces --no-headers | wc -l)
INITIAL_PVCS=$(oc get pvc --all-namespaces --no-headers | wc -l)

# Deploy environment
./bootstrap.sh --environment development > /dev/null 2>&1

# Record deployed state
DEPLOYED_NAMESPACES=$(oc get namespaces --no-headers | wc -l)
DEPLOYED_PVCS=$(oc get pvc --all-namespaces --no-headers | wc -l)

# Cleanup
oc delete namespace self-healing-platform-dev
oc wait --for=delete namespace/self-healing-platform-dev --timeout=300s

# Verify cleanup
FINAL_NAMESPACES=$(oc get namespaces --no-headers | wc -l)
FINAL_PVCS=$(oc get pvc --all-namespaces --no-headers | wc -l)

echo "Namespace count - Initial: $INITIAL_NAMESPACES, Deployed: $DEPLOYED_NAMESPACES, Final: $FINAL_NAMESPACES"
echo "PVC count - Initial: $INITIAL_PVCS, Deployed: $DEPLOYED_PVCS, Final: $FINAL_PVCS"

# Check for resource leaks
if [ "$FINAL_NAMESPACES" -eq "$INITIAL_NAMESPACES" ] && [ "$FINAL_PVCS" -eq "$INITIAL_PVCS" ]; then
    echo "Cleanup test: PASSED"
else
    echo "Cleanup test: FAILED (resource leak detected)"
fi
```

## 📋 **Test Automation Script**

```bash
#!/bin/bash
# automated-bootstrap-test.sh - Comprehensive bootstrap testing

set -e

RESULTS_DIR="test-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "Starting comprehensive bootstrap testing..."
echo "Results will be saved to: $RESULTS_DIR"

# Run all test categories
{
    echo "=== PRE-DEPLOYMENT TESTS ==="
    # Container image tests
    # Kustomize configuration tests
    # Script validation tests

    echo "=== DEPLOYMENT TESTS ==="
    # Development environment tests
    # Validation tests
    # Component functionality tests

    echo "=== FAILURE SCENARIO TESTS ==="
    # Prerequisite failure tests
    # Deployment failure tests
    # Recovery tests

    echo "=== PERFORMANCE TESTS ==="
    # Deployment timing tests
    # Resource usage tests

    echo "=== CLEANUP TESTS ==="
    # Complete environment cleanup tests

} 2>&1 | tee "$RESULTS_DIR/test-execution.log"

# Generate test report
cat > "$RESULTS_DIR/test-report.md" << EOF
# Bootstrap Testing Report

**Date**: $(date)
**Environment**: $(oc cluster-info | head -1)
**OpenShift Version**: $(oc version -o json | jq -r '.openshiftVersion')

## Test Results Summary

- **Pre-deployment Tests**: [PASS/FAIL]
- **Deployment Tests**: [PASS/FAIL]
- **Failure Scenario Tests**: [PASS/FAIL]
- **Performance Tests**: [PASS/FAIL]
- **Cleanup Tests**: [PASS/FAIL]

## Detailed Results

See test-execution.log for detailed output.

## Recommendations

[Add any recommendations based on test results]
EOF

echo "Testing completed. Results available in: $RESULTS_DIR"
```

## 🎯 **Success Criteria**

### **Deployment Success Metrics**
- ✅ All container images build successfully
- ✅ Kustomize configurations validate without errors
- ✅ Bootstrap deployment completes in <10 minutes
- ✅ All validation checks pass (>95% success rate)
- ✅ All critical components are healthy
- ✅ No resource leaks after cleanup

### **Performance Benchmarks**
- **Development Deployment**: <5 minutes
- **Production Deployment**: <15 minutes
- **Validation Execution**: <2 minutes
- **Resource Overhead**: <10% cluster capacity
- **Recovery Time**: <3 minutes

### **Reliability Targets**
- **Deployment Success Rate**: >95%
- **Validation Accuracy**: >98%
- **Error Recovery**: 100% for transient failures
- **Documentation Coverage**: 100% of failure scenarios

## 📚 **References**

- [ADR-009: Bootstrap Deployment Automation](adrs/009-bootstrap-deployment-automation.md)
- [Pre-Bootstrap Checklist](PRE_BOOTSTRAP_CHECKLIST.md)
- [Development Workflow](DEVELOPMENT_WORKFLOW.md)
- [Bootstrap Architecture Diagrams](diagrams/bootstrap-architecture.md)

---

**Note**: Run these tests in a dedicated test cluster to avoid impacting production environments. Always backup important data before running destructive tests.
