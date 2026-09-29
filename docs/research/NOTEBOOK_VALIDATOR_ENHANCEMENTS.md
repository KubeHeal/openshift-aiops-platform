# Notebook Validator Operator Enhancements

## Overview

This document specifies **generic, reusable enhancements** to the Jupyter Notebook Validator Operator to improve model serving validation for **any project** using KServe, OpenShift AI, or other model serving platforms.

> **Important**: This operator is used by multiple projects. All enhancements must be:
> - ✅ **Generic and configurable** - not hardcoded to any specific project
> - ✅ **Opt-in via CRD fields** - backward compatible with existing users
> - ✅ **Platform-agnostic** - support KServe, OpenShift AI, vLLM, TensorFlow Serving, etc.
> - ✅ **Documented with clear examples** - easy for other projects to adopt

## Context

**Use Case (Self-Healing Platform)**: The self-healing platform discovered that KServe InferenceServices were missing the `--model_name` parameter, causing models to register as `"model"` instead of their actual names. This caused downstream integration errors.

**Generic Problem**: Model serving platforms often have configuration nuances that are hard to catch until runtime. Notebooks may train and save models correctly, but the serving configuration may be incorrect.

**Current Notebook Validator Capabilities:**
- ✅ Validates notebooks execute successfully
- ✅ Compares output with golden notebooks
- ✅ Checks model serving platform availability (spec.modelValidation.enabled)
- ✅ Validates predictions match expected output
- ⚠️ **MISSING**: Does not verify model registration names match expectations
- ⚠️ **MISSING**: Does not test platform-specific endpoints comprehensively
- ⚠️ **MISSING**: Does not validate downstream integration (optional external service checks)

## Design Principles

All enhancements follow these principles to ensure the operator remains generic and reusable:

### 1. **Platform Abstraction**
- ✅ Support multiple platforms: KServe, OpenShift AI, vLLM, TensorFlow Serving, Triton, etc.
- ✅ Platform-specific logic isolated in configuration dictionaries
- ✅ Easy to add new platforms without core logic changes

### 2. **Configuration Over Convention**
- ✅ All validations are **opt-in via CRD fields**
- ✅ Sensible defaults that work for most projects
- ✅ Projects can override defaults with custom configurations

### 3. **Backward Compatibility**
- ✅ All new fields are **optional**
- ✅ Existing NotebookValidationJobs continue to work without changes
- ✅ Default behavior remains unchanged

### 4. **Project-Specific Customization**
- ✅ Projects define their own downstream services to test
- ✅ No hardcoded service names in operator code
- ✅ Each project configures validation to match their architecture

### 5. **Clear Error Messages**
- ✅ Generic errors with platform-specific hints
- ✅ Actionable guidance (not just "failed")
- ✅ Projects can provide custom documentation references

## Proposed Enhancements

### Enhancement 1: Model Registration Name Validation (Platform-Agnostic)

**What:** Verify that models register with expected names on the model serving platform.

**Why:** Many platforms have default registration names that may not match what users expect:
- **KServe**: Defaults to `"model"` if `--model_name` not specified
- **OpenShift AI**: May use InferenceService name or custom names
- **vLLM**: Uses model path or explicit `--model-name` parameter
- **TensorFlow Serving**: Uses model version path conventions

**Configuration (via CRD):**

```yaml
spec:
  modelValidation:
    enabled: true
    targetModels:
      - "expected-model-name"  # Expected registration name
    registrationValidation:  # NEW SECTION
      enabled: true
      allowDefaultNames: false  # Fail if model registers as "model", "default", etc.
      customValidation:  # Optional: platform-specific checks
        kserve:
          checkModelNameParameter: true  # Verify --model_name in args
```

**Implementation (Generic):**

1. **Detect platform** from `spec.modelValidation.platform` (kserve, openshift-ai, vllm, etc.)
2. **Get model endpoint** using platform-specific service discovery
3. **Query registration endpoint** (platform-specific)
4. **Verify expected model name** is registered

**Pseudo-code:**

```python
def validate_model_registration(
    model_name: str,
    namespace: str,
    platform: str = "kserve",
    allow_default_names: bool = False
) -> ValidationResult:
    """
    Generic model registration validation that works across platforms.

    Args:
        model_name: Expected model name (e.g., "predictive-analytics")
        namespace: Kubernetes namespace
        platform: Model serving platform (kserve, openshift-ai, vllm, etc.)
        allow_default_names: Whether to allow default names like "model"

    Returns:
        ValidationResult with success status and message
    """
    # Platform-specific endpoint discovery
    endpoint_config = get_platform_endpoint_config(platform)

    # Get model service endpoint (platform-specific)
    model_endpoint = discover_model_endpoint(
        model_name=model_name,
        namespace=namespace,
        platform=platform,
        endpoint_config=endpoint_config
    )

    if not model_endpoint:
        return ValidationResult(
            success=False,
            message=f"Model endpoint for {model_name} not found on platform {platform}"
        )

    # Query models list (platform-specific)
    try:
        models_list = query_models_list(model_endpoint, platform)

        # Generic check for default names (configurable)
        default_names = ["model", "default", "default-model"]
        if not allow_default_names:
            if any(name in models_list for name in default_names) and model_name not in models_list:
                return ValidationResult(
                    success=False,
                    message=f"Model registered with default name instead of '{model_name}'. "
                            f"Found: {models_list}. "
                            f"Check platform-specific configuration (e.g., --model_name for KServe)."
                )

        # Verify expected model name is registered
        if model_name not in models_list:
            return ValidationResult(
                success=False,
                message=f"Model {model_name} not found in registered models. "
                        f"Found: {models_list}"
            )

    except Exception as e:
        return ValidationResult(
            success=False,
            message=f"Failed to query models list: {str(e)}"
        )

    return ValidationResult(
        success=True,
        message=f"Model {model_name} registered correctly on {platform}"
    )

# Platform-specific implementations
def get_platform_endpoint_config(platform: str) -> dict:
    """Returns platform-specific endpoint configuration."""
    configs = {
        "kserve": {
            "list_endpoint": "/v1/models",
            "metadata_endpoint": "/v1/models/{model_name}",
            "predict_endpoint": "/v1/models/{model_name}:predict",
            "port": 8080,
            "label_selector": "serving.kserve.io/inferenceservice={model_name}"
        },
        "openshift-ai": {
            "list_endpoint": "/v2/models",
            "metadata_endpoint": "/v2/models/{model_name}",
            "predict_endpoint": "/v2/models/{model_name}/infer",
            "port": 8080,
            "label_selector": "serving.kserve.io/inferenceservice={model_name}"
        },
        "vllm": {
            "list_endpoint": "/v1/models",
            "metadata_endpoint": "/v1/models/{model_name}",
            "predict_endpoint": "/v1/completions",
            "port": 8000,
            "label_selector": "app={model_name}"
        },
        # Add more platforms as needed
    }
    return configs.get(platform, configs["kserve"])  # Default to KServe
```

**CRD Changes:** None required - this uses existing `spec.modelValidation.targetModels` field.

**Status Update:** Add to `status.modelValidationResult.existingEnvironmentCheck.modelsChecked[]`:
```yaml
modelsChecked:
  - modelName: predictive-analytics
    available: true
    healthy: true
    registrationNameCorrect: true  # NEW FIELD
    message: "Model registered with correct name 'predictive-analytics'"
```

### Enhancement 2: KServe Endpoint Testing

**What:** Test all critical KServe endpoints to ensure model is fully operational.

**Why:** Catches configuration issues, model loading errors, and network problems before deployment.

**Endpoints to Test:**

1. **GET /v1/models** - List all models
2. **GET /v1/models/{name}** - Get model metadata and ready status
3. **POST /v1/models/{name}:predict** - Test prediction with sample data

**Implementation:**

```python
def validate_kserve_endpoints(model_name: str, namespace: str, test_data: dict = None) -> ValidationResult:
    """
    Validates all KServe endpoints for a model.

    Args:
        model_name: Model name (e.g., "predictive-analytics")
        namespace: Kubernetes namespace
        test_data: Optional test data for prediction (from spec.modelValidation.predictionValidation.testData)

    Returns:
        ValidationResult with detailed endpoint test results
    """
    pod_ip = get_predictor_pod_ip(
        label_selector=f"serving.kserve.io/inferenceservice={model_name}",
        namespace=namespace
    )

    results = {
        "list_models": False,
        "get_metadata": False,
        "predict": False
    }
    messages = []

    # Test 1: List models
    try:
        response = requests.get(f"http://{pod_ip}:8080/v1/models", timeout=10)
        response.raise_for_status()
        models = response.json().get("models", [])

        if model_name in models:
            results["list_models"] = True
            messages.append(f"✅ GET /v1/models - Model found in list")
        else:
            messages.append(f"❌ GET /v1/models - Model {model_name} not in list: {models}")
    except Exception as e:
        messages.append(f"❌ GET /v1/models - Failed: {str(e)}")

    # Test 2: Get model metadata
    try:
        response = requests.get(f"http://{pod_ip}:8080/v1/models/{model_name}", timeout=10)
        response.raise_for_status()
        metadata = response.json()

        # Check model is ready
        if metadata.get("ready") == True:
            results["get_metadata"] = True
            messages.append(f"✅ GET /v1/models/{model_name} - Model ready")
        else:
            messages.append(f"❌ GET /v1/models/{model_name} - Model not ready: {metadata}")
    except Exception as e:
        messages.append(f"❌ GET /v1/models/{model_name} - Failed: {str(e)}")

    # Test 3: Prediction endpoint
    if test_data:
        try:
            response = requests.post(
                f"http://{pod_ip}:8080/v1/models/{model_name}:predict",
                json=test_data,
                headers={"Content-Type": "application/json"},
                timeout=30
            )
            response.raise_for_status()
            prediction = response.json()

            if "predictions" in prediction:
                results["predict"] = True
                messages.append(f"✅ POST /v1/models/{model_name}:predict - Prediction successful")
            else:
                messages.append(f"❌ POST /v1/models/{model_name}:predict - No predictions in response: {prediction}")
        except Exception as e:
            messages.append(f"❌ POST /v1/models/{model_name}:predict - Failed: {str(e)}")
    else:
        messages.append(f"⚠️ POST /v1/models/{model_name}:predict - Skipped (no test data)")
        results["predict"] = True  # Don't fail if no test data provided

    all_passed = all(results.values())

    return ValidationResult(
        success=all_passed,
        message="\n".join(messages),
        endpoint_results=results  # NEW: Detailed per-endpoint results
    )
```

**CRD Usage:** Use existing fields:
- `spec.modelValidation.predictionValidation.testData` - JSON test data
- `spec.modelValidation.predictionValidation.expectedOutput` - Expected prediction result
- `spec.modelValidation.timeout` - Timeout for all tests

**Example NotebookValidationJob:**
```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: predictive-analytics-validation
spec:
  notebook:
    path: notebooks/predictive-analytics.ipynb
    git:
      url: https://github.com/org/repo.git
      ref: main
  modelValidation:
    enabled: true
    targetModels:
      - predictive-analytics
    predictionValidation:
      enabled: true
      testData: |
        {
          "instances": [
            [0.5, 0.6, 0.4, 100, 80]
          ]
        }
      tolerance: "0.01"
  podConfig:
    containerImage: quay.io/jupyter/minimal-notebook:latest
```

### Enhancement 3: Downstream Integration Testing (Generic)

**What:** Verify downstream services/applications can reach and query the model.

**Why:** Catches network policy issues, service discovery problems, and integration errors. Different projects have different downstream services that consume models:
- **Self-healing platform**: Coordination engine, MCP server
- **ML pipelines**: Orchestrators, serving gateways
- **Applications**: API gateways, microservices
- **Monitoring**: Prometheus, custom health checkers

**Configuration (via CRD - Fully Optional):**

```yaml
spec:
  modelValidation:
    enabled: true
    downstreamIntegration:  # NEW SECTION (optional)
      enabled: true
      services:  # List of downstream services to test
        - name: "coordination-engine"
          url: "http://coordination-engine:8080"
          testConnectivity: true  # Test network connectivity
          testModelAccess: true   # Test can query model endpoints
          healthEndpoint: "/health"  # Optional health check
        - name: "api-gateway"
          url: "http://api-gateway:8000"
          testConnectivity: true
          testModelAccess: false  # Gateway may not directly query models
```

**Implementation (Generic):**

```python
def validate_downstream_integration(
    model_name: str,
    namespace: str,
    platform: str,
    downstream_services: list = None
) -> ValidationResult:
    """
    Generic validation that downstream services can reach the model.

    Args:
        model_name: Model name
        namespace: Kubernetes namespace
        platform: Model serving platform
        downstream_services: List of downstream service configurations

    Returns:
        ValidationResult with downstream integration status
    """
    if not downstream_services:
        # No downstream services configured - skip this validation
        return ValidationResult(
            success=True,
            message="No downstream services configured - skipping integration tests",
            skipped=True
        )

    # Get model service endpoint
    endpoint_config = get_platform_endpoint_config(platform)
    predictor_service = f"{model_name}-predictor.{namespace}.svc.cluster.local"
    port = endpoint_config.get("port", 8080)

    results = []
    all_passed = True

    for service in downstream_services:
        service_name = service.get("name")
        service_url = service.get("url")
        test_connectivity = service.get("testConnectivity", True)
        test_model_access = service.get("testModelAccess", False)

        service_results = {
            "service": service_name,
            "dns_resolution": False,
            "network_connectivity": False,
            "model_access": False
        }

        # Test 1: DNS resolution (from validation pod perspective)
        if test_connectivity:
            try:
                dns_result = socket.getaddrinfo(predictor_service, port)
                service_results["dns_resolution"] = True
            except Exception as e:
                all_passed = False
                results.append(f"❌ {service_name}: DNS resolution failed for {predictor_service}: {str(e)}")
                continue

        # Test 2: Network connectivity (model service reachable from validation pod)
        if test_connectivity:
            try:
                list_endpoint = endpoint_config["list_endpoint"]
                response = requests.get(
                    f"http://{predictor_service}:{port}{list_endpoint}",
                    timeout=10
                )
                response.raise_for_status()
                service_results["network_connectivity"] = True
                results.append(f"✅ {service_name}: Can reach model service")
            except Exception as e:
                all_passed = False
                results.append(f"❌ {service_name}: Network connectivity failed: {str(e)}")
                continue

        # Test 3: Model access (if downstream service should query model directly)
        # Note: This tests from validation pod, not from downstream service pod
        # For true end-to-end testing, would need to exec into downstream service pod
        if test_model_access:
            try:
                predict_endpoint = endpoint_config["predict_endpoint"].format(model_name=model_name)
                # Make a simple test request
                test_data = {"instances": [[1.0]]}  # Minimal test data
                response = requests.post(
                    f"http://{predictor_service}:{port}{predict_endpoint}",
                    json=test_data,
                    timeout=10
                )
                response.raise_for_status()
                service_results["model_access"] = True
                results.append(f"✅ {service_name}: Can query model predictions")
            except Exception as e:
                # Don't fail - model access from downstream service may require specific auth/network
                results.append(f"⚠️ {service_name}: Model access test inconclusive: {str(e)}")

    return ValidationResult(
        success=all_passed,
        message="\n".join(results),
        downstream_results=service_results  # Detailed per-service results
    )
```

**CRD Enhancement (Optional):**

```yaml
spec:
  modelValidation:
    # Downstream integration testing (optional - project-specific)
    downstreamIntegration:
      enabled: false  # Default: disabled (opt-in)
      services:
        - name: "my-orchestrator"
          url: "http://my-orchestrator:8080"
          testConnectivity: true
          testModelAccess: false
          healthEndpoint: "/health"
```

**Status Update:**
```yaml
status:
  modelValidationResult:
    existingEnvironmentCheck:
      downstreamIntegration:  # NEW SECTION (only if configured)
        enabled: true
        servicesChecked:
          - serviceName: "coordination-engine"
            dnsResolution: true
            networkConnectivity: true
            modelAccess: true
            message: "All checks passed"
        success: true
```

**Usage Example (Self-Healing Platform):**

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: predictive-analytics-validation
spec:
  modelValidation:
    enabled: true
    targetModels:
      - predictive-analytics
    downstreamIntegration:
      enabled: true
      services:
        - name: "coordination-engine"
          url: "http://coordination-engine:8080"
          testConnectivity: true
          testModelAccess: true
        - name: "mcp-server"
          url: "http://mcp-server:8080"
          testConnectivity: true
          testModelAccess: false
```

### Enhancement 4: Retry Logic for Model Loading

**What:** Wait for models to load before running validation tests.

**Why:** KServe models can take 30-60 seconds to load after pod starts. Current validation may fail if run too early.

**Implementation:**

```python
def wait_for_model_ready(model_name: str, namespace: str, timeout: int = 300, retry_interval: int = 10) -> bool:
    """
    Waits for a KServe model to become ready.

    Args:
        model_name: Model name
        namespace: Kubernetes namespace
        timeout: Maximum wait time in seconds (default 5 minutes)
        retry_interval: Time between retries in seconds (default 10s)

    Returns:
        True if model becomes ready, False if timeout
    """
    start_time = time.time()

    while time.time() - start_time < timeout:
        try:
            # Check InferenceService status
            inference_service = get_inference_service(model_name, namespace)

            if inference_service.status.ready:
                # Also verify pod is actually serving
                pod_ip = get_predictor_pod_ip(
                    label_selector=f"serving.kserve.io/inferenceservice={model_name}",
                    namespace=namespace
                )

                if pod_ip:
                    try:
                        response = requests.get(f"http://{pod_ip}:8080/v1/models/{model_name}", timeout=5)
                        if response.status_code == 200 and response.json().get("ready"):
                            return True
                    except:
                        pass  # Not ready yet, continue waiting
        except Exception as e:
            logger.debug(f"Waiting for model {model_name}: {str(e)}")

        time.sleep(retry_interval)

    return False
```

**CRD Usage:** Use existing `spec.modelValidation.timeout` field (default: 5m)

**Logging:**
```
[INFO] Waiting for model predictive-analytics to become ready...
[INFO] Model predictive-analytics ready after 45 seconds
```

## Implementation Checklist

### Operator Code Changes

- [ ] Add `validate_model_registration()` function to existing environment check phase
- [ ] Add `validate_kserve_endpoints()` function with comprehensive endpoint testing
- [ ] Add `validate_coordination_engine_integration()` function for integration testing
- [ ] Add `wait_for_model_ready()` with retry logic and configurable timeout
- [ ] Update reconciliation loop to call new validation functions
- [ ] Add detailed error messages referencing MODEL_DEPLOYMENT_CHECKLIST.md

### Status Reporting Enhancements

- [ ] Add `registrationNameCorrect` field to `modelsChecked[]` status
- [ ] Add `endpointResults` section with per-endpoint test results
- [ ] Add `coordinationEngineIntegration` section to status
- [ ] Include specific error messages for common issues:
  - Missing `--model_name` parameter
  - Model file not found
  - Network connectivity issues
  - RBAC permission errors

### CRD Enhancements (Optional)

These are **optional** - existing CRD fields are sufficient for basic functionality:

```yaml
spec:
  modelValidation:
    # OPTIONAL: Coordination engine URL (defaults to http://coordination-engine:8080)
    coordinationEngineURL: "http://coordination-engine:8080"

    # OPTIONAL: Retry configuration for model readiness
    readinessCheck:
      enabled: true  # Default: true
      timeout: "5m"  # Default: same as spec.modelValidation.timeout
      retryInterval: "10s"  # Default: 10 seconds

    # OPTIONAL: Endpoint validation configuration
    endpointValidation:
      enabled: true  # Default: true
      testListModels: true  # Test GET /v1/models
      testMetadata: true  # Test GET /v1/models/{name}
      testPredict: true  # Test POST /v1/models/{name}:predict
```

### Documentation

- [ ] Update operator README with new validation features
- [ ] Add troubleshooting guide for common model registration issues
- [ ] Document how to use `spec.modelValidation.predictionValidation.testData`
- [ ] Add examples of NotebookValidationJob with model validation enabled

## Testing Strategy

### Unit Tests

```python
def test_validate_model_registration_success():
    """Test successful model registration validation."""
    # Mock KServe API responses
    mock_response = {"models": ["predictive-analytics"]}

    result = validate_model_registration("predictive-analytics", "default")

    assert result.success == True
    assert "registered correctly" in result.message

def test_validate_model_registration_default_name():
    """Test detection of default 'model' name issue."""
    # Mock KServe API responses
    mock_response = {"models": ["model"]}  # BUG: Using default name

    result = validate_model_registration("predictive-analytics", "default")

    assert result.success == False
    assert "Missing --model_name parameter" in result.message
    assert "MODEL_DEPLOYMENT_CHECKLIST.md" in result.message

def test_validate_kserve_endpoints():
    """Test KServe endpoint validation."""
    test_data = {"instances": [[1, 2, 3]]}

    result = validate_kserve_endpoints("predictive-analytics", "default", test_data)

    assert result.success == True
    assert result.endpoint_results["list_models"] == True
    assert result.endpoint_results["get_metadata"] == True
    assert result.endpoint_results["predict"] == True

def test_wait_for_model_ready_timeout():
    """Test timeout when model doesn't become ready."""
    result = wait_for_model_ready("nonexistent-model", "default", timeout=5)

    assert result == False
```

### Integration Tests

1. **Deploy InferenceService WITHOUT --model_name** → Validation should FAIL with helpful error
2. **Deploy InferenceService WITH --model_name** → Validation should PASS
3. **Deploy model with invalid model file** → Validation should FAIL with file not found error
4. **Deploy model with network policy blocking coordination engine** → Integration test should FAIL

### E2E Test Scenario

```bash
# 1. Create NotebookValidationJob with model validation
oc apply -f - <<EOF
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: test-model-validation
  namespace: self-healing-platform
spec:
  notebook:
    path: notebooks/predictive-analytics.ipynb
    git:
      url: https://github.com/org/repo.git
      ref: main
  modelValidation:
    enabled: true
    targetModels:
      - predictive-analytics
    predictionValidation:
      enabled: true
      testData: '{"instances": [[0.5, 0.6, 0.4, 100, 80]]}'
  podConfig:
    containerImage: quay.io/jupyter/minimal-notebook:latest
EOF

# 2. Wait for completion
oc wait --for=jsonpath='{.status.phase}'=Succeeded \
  notebookvalidationjob/test-model-validation \
  -n self-healing-platform \
  --timeout=10m

# 3. Check validation results
oc get notebookvalidationjob test-model-validation -n self-healing-platform -o yaml

# Expected status:
# status:
#   phase: Succeeded
#   modelValidationResult:
#     success: true
#     existingEnvironmentCheck:
#       modelsChecked:
#         - modelName: predictive-analytics
#           available: true
#           healthy: true
#           registrationNameCorrect: true  # ✅ NEW CHECK
#           message: "Model registered with correct name 'predictive-analytics'"
```

## Benefits

### Immediate Benefits

1. **Catches configuration errors early** - Missing `--model_name` detected during validation, not at runtime
2. **Better error messages** - Specific guidance on how to fix issues (references MODEL_DEPLOYMENT_CHECKLIST.md)
3. **Prevents MCP server failures** - Models validated before MCP server tries to query them
4. **Faster troubleshooting** - Validation results show exactly what's wrong

### Long-term Benefits

1. **Repeatability** - Same validation process for all future models
2. **Confidence** - Know models will work before deploying to production
3. **Documentation** - Validation results document what was tested
4. **Integration testing** - Verifies end-to-end integration with coordination engine

## Migration Path

### Phase 1: Implement in Operator (v1.0.6)

- Add new validation functions to operator code
- Update status reporting with new fields
- No CRD changes required (use existing fields)
- **Backward compatible** - existing NotebookValidationJobs continue to work

### Phase 2: Update Documentation

- Create MODEL_DEPLOYMENT_CHECKLIST.md (✅ Done)
- Update operator README
- Add troubleshooting guide
- Document best practices

### Phase 3: Update Existing NotebookValidationJobs

- Add `modelValidation.enabled: true` to predictive-analytics validation
- Add `predictionValidation.testData` for realistic test inputs
- Verify all models pass new validation checks

### Phase 4: CRD Enhancements (v1.1.0 - Optional)

- Add optional fields for coordination engine URL
- Add retry configuration
- Add endpoint validation toggles
- **Backward compatible** - all fields are optional with sensible defaults

## Success Criteria

- [ ] Validation detects missing `--model_name` parameter
- [ ] Validation tests all KServe endpoints (list, metadata, predict)
- [ ] Validation verifies coordination engine can reach model
- [ ] Validation waits for model to load before testing (retry logic)
- [ ] Error messages reference MODEL_DEPLOYMENT_CHECKLIST.md
- [ ] All existing NotebookValidationJobs continue to work (backward compatibility)
- [ ] New validation catches the exact issue from Issue #13

## Example Error Messages

### Missing --model_name Parameter

```
❌ Model Validation Failed: Model Registration Issue

Model 'predictive-analytics' is registered as 'model' instead of 'predictive-analytics'.

This usually means the InferenceService is missing the --model_name parameter.

Fix:
1. Edit charts/hub/templates/model-serving.yaml (or charts/hub/values.yaml if using model loop)
2. Add --model_name parameter to InferenceService args:

   args:
   - --model_name=predictive-analytics  # ← Add this line
   - --model_dir=/mnt/models/predictive-analytics
   - --http_port=8080

3. Commit and sync with ArgoCD

See docs/MODEL_DEPLOYMENT_CHECKLIST.md for detailed instructions.
```

### Model File Not Found

```
❌ Model Validation Failed: Model File Not Found

KServe logs show: "failed to locate model file for model predictive-analytics under dir /mnt/models/predictive-analytics"

This usually means:
1. Notebook didn't save model to correct path
2. PVC mount is not working
3. Directory path doesn't match model name

Fix:
1. Verify model file exists:
   oc exec deployment/predictive-analytics-predictor -- ls -lh /mnt/models/predictive-analytics/model.pkl

2. Check notebook saves to correct path:
   joblib.dump(model, "/mnt/models/predictive-analytics/model.pkl")

See docs/MODEL_DEPLOYMENT_CHECKLIST.md for detailed instructions.
```

## Related Resources

- [MODEL_DEPLOYMENT_CHECKLIST.md](MODEL_DEPLOYMENT_CHECKLIST.md) - Deployment checklist for models
- [KServe SKLearn Server Documentation](https://github.com/kserve/kserve/tree/master/python/sklearnserver)
- [Jupyter Notebook Validator Operator Repository](https://github.com/org/jupyter-notebook-validator-operator)
- ADR-XXX: Model Validation Enhancement (to be created)

## Multi-Project Usage Examples

### Example 1: Self-Healing Platform (KServe + Downstream Integration)

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: predictive-analytics-validation
  namespace: self-healing-platform
spec:
  notebook:
    path: notebooks/predictive-analytics.ipynb
    git:
      url: https://github.com/org/openshift-aiops-platform.git
      ref: main
  modelValidation:
    enabled: true
    platform: kserve
    targetModels:
      - predictive-analytics
    registrationValidation:
      enabled: true
      allowDefaultNames: false  # Fail if model registers as "model"
    predictionValidation:
      enabled: true
      testData: '{"instances": [[0.5, 0.6, 0.4, 100, 80]]}'
    downstreamIntegration:
      enabled: true
      services:
        - name: "coordination-engine"
          url: "http://coordination-engine:8080"
          testConnectivity: true
          testModelAccess: true
        - name: "mcp-server"
          url: "http://mcp-server:8080"
          testConnectivity: true
  podConfig:
    containerImage: quay.io/jupyter/minimal-notebook:latest
```

### Example 2: ML Pipeline (OpenShift AI + API Gateway)

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: fraud-detection-validation
  namespace: ml-pipeline
spec:
  notebook:
    path: models/fraud-detection.ipynb
    git:
      url: https://github.com/org/ml-pipeline.git
      ref: main
  modelValidation:
    enabled: true
    platform: openshift-ai  # Different platform
    targetModels:
      - fraud-detection-v2
    registrationValidation:
      enabled: true
      allowDefaultNames: false
    predictionValidation:
      enabled: true
      testData: '{"inputs": [{"transaction_amount": 100.0, "location": "US"}]}'
    downstreamIntegration:
      enabled: true
      services:
        - name: "api-gateway"
          url: "http://api-gateway:8000"
          testConnectivity: true
          testModelAccess: false  # Gateway doesn't directly query models
        - name: "monitoring-service"
          url: "http://prometheus:9090"
          testConnectivity: true
  podConfig:
    containerImage: quay.io/opendatahub/workbench-images:latest
```

### Example 3: LLM Serving (vLLM + Simple Validation)

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: llama-fine-tune-validation
  namespace: llm-serving
spec:
  notebook:
    path: fine-tuning/llama-7b.ipynb
    git:
      url: https://github.com/org/llm-serving.git
      ref: main
  modelValidation:
    enabled: true
    platform: vllm  # LLM-specific platform
    targetModels:
      - llama-7b-fine-tuned
    registrationValidation:
      enabled: true
    predictionValidation:
      enabled: true
      testData: '{"prompt": "Hello, how are you?", "max_tokens": 50}'
    # No downstream integration - just model validation
  podConfig:
    containerImage: vllm/vllm-openai:latest
```

### Example 4: Minimal Validation (Just Check Model Exists)

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: simple-model-validation
  namespace: data-science
spec:
  notebook:
    path: experiments/model-v1.ipynb
    git:
      url: https://github.com/org/data-science.git
      ref: main
  modelValidation:
    enabled: true
    platform: kserve
    targetModels:
      - simple-model
    # Only basic checks - just verify model is deployed and ready
    # No registration validation, prediction tests, or downstream integration
  podConfig:
    containerImage: jupyter/scipy-notebook:latest
```

## Key Takeaways for Other Projects

### ✅ What You Need to Configure

1. **Platform**: Set `spec.modelValidation.platform` to your model serving platform
2. **Model Names**: List expected model names in `spec.modelValidation.targetModels`
3. **Downstream Services** (optional): Define services that need to reach your models
4. **Test Data** (optional): Provide sample input for prediction validation

### ✅ What the Operator Handles

1. **Platform Detection**: Automatically uses correct endpoints for your platform
2. **Service Discovery**: Finds model pods using platform-specific label selectors
3. **Validation Logic**: Runs appropriate checks based on your configuration
4. **Error Reporting**: Provides platform-specific error messages

### ✅ Adding a New Platform

If you need to support a new platform:

1. Add platform configuration to `get_platform_endpoint_config()`:
```python
"my-platform": {
    "list_endpoint": "/api/models",
    "metadata_endpoint": "/api/models/{model_name}",
    "predict_endpoint": "/api/models/{model_name}/predict",
    "port": 8000,
    "label_selector": "app.kubernetes.io/name={model_name}"
}
```

2. Use in your NotebookValidationJob:
```yaml
spec:
  modelValidation:
    platform: my-platform
```

3. Submit PR to operator to add platform configuration permanently

## Questions for Implementation

1. **Where is the operator source code?** Need to locate the operator repository to implement these changes
2. **What version should include these enhancements?** Suggest v1.0.6 for bug fix, v1.1.0 for CRD changes
3. **Should this be opt-in or opt-out?** Suggest opt-in via `spec.modelValidation.enabled: true` (current behavior)
4. **Should we add Prometheus metrics?** Could track validation success/failure rates, model load times, etc.
5. **Integration with ArgoCD health checks?** Could use validation results in ArgoCD Application health status
6. **Community feedback on platform support?** Which platforms should we prioritize?
7. **Documentation for other projects?** Where should we publish examples for different use cases?
