# Feature: Complete Model-Aware Validation Implementation per ADR-020

## Priority
**P2 (Medium)** - Valuable for MLOps workflows, depends on ADR-020 implementation status

## Summary
Implement native operator support for validating trained models against serving platforms (KServe, OpenShift AI, vLLM, etc.) as proposed in [ADR-020](https://github.com/tosin2013/jupyter-notebook-validator-operator/blob/main/docs/adrs/020-model-aware-validation.md). This complements init containers (Issue #1) by providing **post-execution** validation that trained models are compatible with model serving platforms.

## Status Note

**This issue depends on ADR-020 status**:
- If ADR-020 is still **PROPOSED** (not ACCEPTED), this feature should be reconsidered after architectural review
- If ADR-020 is **ACCEPTED**, this issue provides implementation plan
- **Recommend**: Review ADR-020 acceptance before starting implementation

## Problem Statement

Data science teams train models in notebooks but encounter deployment failures when moving to production:

1. **Format Incompatibility**
   - Model saved as `.pkl` but KServe expects ONNX
   - TensorFlow SavedModel format incorrect for TorchServe
   - Missing model metadata files

2. **Platform-Specific Issues**
   - Model loads in notebook but fails in InferenceService
   - Prediction API schema mismatch (input/output shape)
   - Missing dependencies in serving runtime

3. **Delayed Failure Detection**
   - Issues discovered during deployment, not during training
   - Manual testing required before pushing to production
   - No automated validation in CI/CD pipelines

### Current Workarounds

Users manually validate models:
- Deploy test InferenceService, hope it works
- Write custom validation scripts in notebooks (duplicates platform logic)
- Use init containers to check model serving health (checks infrastructure, not model compatibility)

### Difference from Init Containers (Issue #1)

| Aspect | Init Containers (Issue #1) | Model Validation (This Issue) |
|--------|----------------------------|------------------------------|
| **Timing** | BEFORE notebook execution | AFTER notebook execution |
| **Purpose** | Wait for infrastructure dependencies | Validate model outputs |
| **Provided By** | User (custom images) | Operator (built-in capability) |
| **Use Case** | "Is KServe API ready?" | "Is trained model compatible with KServe?" |
| **Example** | Wait for Prometheus endpoint | Check InferenceService can load model |

**Both are complementary**:
- Init containers ensure infrastructure is ready for notebook
- Model validation ensures notebook output is ready for infrastructure

## Proposed Solution

Implement model validation capabilities in the operator as specified in ADR-020.

### API Design

Add `ModelValidation` section to NotebookValidationJob spec:

```go
type NotebookValidationJobSpec struct {
    // ... existing fields (notebook, podConfig, etc.) ...

    // ModelValidation (optional) validates trained models against serving platforms
    // +optional
    ModelValidation *ModelValidationSpec `json:"modelValidation,omitempty"`
}

type ModelValidationSpec struct {
    // Enabled controls whether model validation runs after notebook execution
    Enabled bool `json:"enabled"`

    // Platform is the model serving platform (kserve, openshift-ai, vllm, torchserve, etc.)
    // +optional
    // +kubebuilder:validation:Enum=kserve;openshift-ai;vllm;torchserve;mlflow;bentoml;seldon;ray-serve;triton
    Platform string `json:"platform,omitempty"`

    // TargetModels lists model names to validate (e.g., ["anomaly-detector", "predictor"])
    // +optional
    TargetModels []string `json:"targetModels,omitempty"`

    // StorageURI is the base path where models are stored (e.g., "pvc://model-storage-pvc/")
    // +optional
    StorageURI string `json:"storageURI,omitempty"`

    // PredictionValidation tests model inference (optional)
    // +optional
    PredictionValidation *PredictionValidationSpec `json:"predictionValidation,omitempty"`
}

type PredictionValidationSpec struct {
    // Enabled controls whether prediction validation runs
    Enabled bool `json:"enabled"`

    // TestData is sample input for prediction testing (JSON format)
    // +optional
    TestData string `json:"testData,omitempty"`

    // ExpectedOutput is expected prediction result (JSON format, optional)
    // +optional
    ExpectedOutput string `json:"expectedOutput,omitempty"`

    // Timeout for prediction request
    // +optional
    Timeout metav1.Duration `json:"timeout,omitempty"`
}
```

### Workflow

```
1. Notebook executes (trains model, saves to PVC)
   └─ Model saved: /mnt/models/my-model/model.pkl

2. Model validation phase starts (if enabled)
   ├─ Platform detection (auto-detect or use spec.platform)
   ├─ Model format verification
   │  └─ Check /mnt/models/my-model/model.pkl exists
   │  └─ Verify format compatible with platform
   ├─ Model health check (optional)
   │  └─ Query InferenceService: GET /v1/models/my-model/ready
   └─ Prediction validation (optional)
      └─ POST /v1/models/my-model:predict with test data

3. Status updated with validation results
   ├─ Phase: ModelValidationSucceeded / ModelValidationFailed
   └─ Conditions: FormatValid, HealthCheckPassed, PredictionValid
```

## Use Cases

### General Use Cases (Any Organization)

1. **MLOps Teams with KServe**
   - Train model in notebook, automatically validate KServe compatibility
   - Catch format issues before deploying InferenceService
   - CI/CD: Only deploy models that pass validation

2. **Multi-Platform Model Serving**
   - Train once, deploy to multiple platforms (KServe, vLLM, Triton)
   - Validate model compatible with all target platforms
   - Prevent runtime failures from format mismatches

3. **Model Governance and Compliance**
   - Ensure all models meet format standards before production
   - Audit trail: Which models passed/failed validation?
   - Regulatory compliance: Models must be validated before deployment

4. **Data Science Team Productivity**
   - Immediate feedback on model compatibility (don't wait for deployment)
   - Reduce iteration time (fail fast on format issues)
   - Self-service: Data scientists don't need platform expertise

### Specific Example: openshift-aiops-platform

The [openshift-aiops-platform](https://github.com/KubeHeal/openshift-aiops-platform) trains 2 KServe models:

**Current Workflow** (No Model Validation):
```yaml
# Tier 4: Train anomaly detector
apiVersion: notebook.validation.io/v1alpha1
kind: NotebookValidationJob
metadata:
  name: train-anomaly-detector
spec:
  notebook:
    path: "04-model-training/01-anomaly-detector.ipynb"
  podConfig:
    volumes:
    - name: models
      persistentVolumeClaim:
        claimName: model-storage-pvc
    volumeMounts:
    - name: models
      mountPath: /mnt/models
```

**Problem**: If notebook saves model in wrong format, InferenceService fails later (sync wave 2).

**With Model Validation**:
```yaml
apiVersion: notebook.validation.io/v1alpha1
kind: NotebookValidationJob
metadata:
  name: train-anomaly-detector
spec:
  notebook:
    path: "04-model-training/01-anomaly-detector.ipynb"

  podConfig:
    volumes:
    - name: models
      persistentVolumeClaim:
        claimName: model-storage-pvc
    volumeMounts:
    - name: models
      mountPath: /mnt/models

  # NEW: Validate model after training
  modelValidation:
    enabled: true
    platform: kserve  # Or auto-detect
    targetModels: ["anomaly-detector"]
    storageURI: "pvc://model-storage-pvc/"

    predictionValidation:
      enabled: true
      testData: |
        {
          "instances": [[0.5, 0.2, 0.8, 0.1]]
        }
      expectedOutput: |
        {
          "predictions": [0]
        }
      timeout: 30s
```

**Benefits**:
- ✅ Catch format issues during training (sync wave -2), not deployment (sync wave 2)
- ✅ InferenceService won't be created if model is invalid (ArgoCD dependency)
- ✅ Prediction validation ensures inference works before production

## Technical Design

### Platform Detection

```go
type PlatformDetector interface {
    Detect(ctx context.Context, namespace string) (string, error)
}

// KServePlatformDetector checks for KServe CRDs
type KServePlatformDetector struct {
    Client client.Client
}

func (d *KServePlatformDetector) Detect(ctx context.Context, namespace string) (string, error) {
    // Check if InferenceService CRD exists
    crd := &apiextensionsv1.CustomResourceDefinition{}
    err := d.Client.Get(ctx, types.NamespacedName{
        Name: "inferenceservices.serving.kserve.io",
    }, crd)
    if err == nil {
        return "kserve", nil
    }
    return "", fmt.Errorf("KServe not detected")
}
```

### Model Format Verification

```go
type ModelValidator interface {
    ValidateFormat(ctx context.Context, modelPath string, platform string) error
}

type KServeModelValidator struct{}

func (v *KServeModelValidator) ValidateFormat(ctx context.Context, modelPath string, platform string) error {
    // For sklearn: Check model.pkl exists
    if _, err := os.Stat(filepath.Join(modelPath, "model.pkl")); err != nil {
        return fmt.Errorf("sklearn model.pkl not found: %w", err)
    }

    // For TensorFlow: Check saved_model.pb exists
    // For PyTorch: Check model.pth exists
    // For ONNX: Check model.onnx exists

    return nil
}
```

### Model Health Check

```go
type ModelHealthChecker interface {
    CheckHealth(ctx context.Context, modelName string, namespace string) error
}

type KServeHealthChecker struct {
    Client client.Client
}

func (c *KServeHealthChecker) CheckHealth(ctx context.Context, modelName string, namespace string) error {
    // Get InferenceService
    isvc := &kservev1beta1.InferenceService{}
    err := c.Client.Get(ctx, types.NamespacedName{
        Name:      modelName,
        Namespace: namespace,
    }, isvc)
    if err != nil {
        return fmt.Errorf("InferenceService not found: %w", err)
    }

    // Check if ready
    if !isvc.Status.IsReady() {
        return fmt.Errorf("InferenceService not ready")
    }

    // Query /v1/models/{name}/ready endpoint
    url := isvc.Status.URL + "/v1/models/" + modelName + "/ready"
    resp, err := http.Get(url)
    if err != nil {
        return fmt.Errorf("health check failed: %w", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode != 200 {
        return fmt.Errorf("health check returned %d", resp.StatusCode)
    }

    return nil
}
```

### Prediction Validation

```go
type PredictionValidator interface {
    ValidatePrediction(ctx context.Context, modelName string, namespace string, testData string, expectedOutput string) error
}

type KServePredictionValidator struct {
    Client client.Client
}

func (v *KServePredictionValidator) ValidatePrediction(
    ctx context.Context,
    modelName string,
    namespace string,
    testData string,
    expectedOutput string,
) error {
    // Get InferenceService URL
    isvc := &kservev1beta1.InferenceService{}
    err := v.Client.Get(ctx, types.NamespacedName{
        Name:      modelName,
        Namespace: namespace,
    }, isvc)
    if err != nil {
        return err
    }

    // POST to /v1/models/{name}:predict
    url := isvc.Status.URL + "/v1/models/" + modelName + ":predict"
    resp, err := http.Post(url, "application/json", strings.NewReader(testData))
    if err != nil {
        return fmt.Errorf("prediction request failed: %w", err)
    }
    defer resp.Body.Close()

    // Parse response
    body, _ := io.ReadAll(resp.Body)

    // If expectedOutput provided, compare
    if expectedOutput != "" {
        if !jsonEqual(body, []byte(expectedOutput)) {
            return fmt.Errorf("prediction mismatch: got %s, expected %s", body, expectedOutput)
        }
    }

    return nil
}
```

## Implementation Phases

### Phase 1: API and Basic Validation (Week 1-2)
- [ ] Add ModelValidation API fields
- [ ] Implement platform detection (KServe only)
- [ ] Implement model format verification (sklearn, TensorFlow)
- [ ] Update CRD with new fields
- [ ] Unit tests for validators

### Phase 2: Health Check and Prediction Validation (Week 3)
- [ ] Implement KServe health checker
- [ ] Implement KServe prediction validator
- [ ] Integration tests with test InferenceService
- [ ] Status condition updates

### Phase 3: Multi-Platform Support (Week 4-5)
- [ ] Add vLLM platform support
- [ ] Add TorchServe platform support
- [ ] Add Triton platform support
- [ ] Platform-specific validators

### Phase 4: Documentation and Examples (Week 6)
- [ ] User guide for model validation
- [ ] Example NotebookValidationJobs with model validation
- [ ] Integration guide for openshift-aiops-platform
- [ ] Troubleshooting guide

## Benefits

### For MLOps Teams
- **Fail fast**: Catch model issues during training, not deployment
- **CI/CD integration**: Automated model validation in pipelines
- **Reduced debugging time**: Clear error messages on incompatibility

### For Data Scientists
- **Confidence**: Know model will deploy successfully before pushing
- **Self-service**: Don't need to understand platform internals
- **Faster iteration**: Immediate feedback on model format

### For Platform Teams
- **Reliability**: Fewer failed deployments from format issues
- **Standardization**: Enforce model format standards
- **Audit trail**: Track which models validated successfully

## Alternatives Considered

### Alternative 1: Manual Validation in Notebooks
Data scientists add validation code to notebooks.

**Rejected**:
- Duplicates platform logic in every notebook
- Inconsistent validation across teams
- Requires deep platform knowledge

### Alternative 2: Separate Validation Job
Users create a second job to validate models.

**Rejected**:
- More complex workflow (two jobs instead of one)
- Coordination issues (when to run validation?)
- No integration with NotebookValidationJob lifecycle

### Alternative 3: Init Containers for Validation
Use init containers to validate models.

**Rejected**:
- Init containers run BEFORE notebook, validation needs AFTER
- Wrong phase of lifecycle
- See "Difference from Init Containers" section above

## Priority Justification

**Why P2 (Medium Priority)**:

1. **Depends on ADR-020**: If ADR still PROPOSED, architectural review needed first
2. **Optional Feature**: Not required for basic operator functionality
3. **Platform-Specific**: Only benefits users deploying to model serving platforms
4. **Higher Implementation Cost**: Requires platform-specific validators (3-6 weeks)
5. **Complementary to Init Containers**: Init containers (Issue #1) address broader use case

**Consider P1 if**:
- ADR-020 is ACCEPTED
- Multiple users request this feature
- MLOps workflow automation is strategic priority

## Related Work

### Existing ADRs in jupyter-notebook-validator-operator

- **ADR-020: Model-Aware Validation** - Proposes this feature (check status: PROPOSED vs ACCEPTED)
- **ADR-045: Volume Support** - Required for model storage access
- **ADR-010: Observability** - Model validation metrics should be exposed

### Related Issues

- **Issue #1: Init Container Support** - Complementary feature (pre-execution vs post-execution)
- **Issue #2: Prometheus Metrics** - Should track model validation success/failure

## Acceptance Criteria

- [ ] ADR-020 reviewed and status confirmed (ACCEPTED required to proceed)
- [ ] ModelValidation API implemented in NotebookValidationJob CRD
- [ ] Platform detection supports KServe (minimum)
- [ ] Model format verification supports sklearn, TensorFlow, PyTorch
- [ ] Health check queries InferenceService status
- [ ] Prediction validation tests inference with sample data
- [ ] Status conditions reflect validation results (FormatValid, HealthCheckPassed, PredictionValid)
- [ ] Unit tests cover validators
- [ ] E2E tests with real KServe deployment
- [ ] Documentation includes user guide and examples
- [ ] Tested with openshift-aiops-platform models (anomaly-detector, predictive-analytics)

## References

- **ADR-020**: https://github.com/tosin2013/jupyter-notebook-validator-operator/blob/main/docs/adrs/020-model-aware-validation.md
- **openshift-aiops-platform**: https://github.com/KubeHeal/openshift-aiops-platform
- **KServe Prediction API**: https://kserve.github.io/website/latest/modelserving/v1beta1/sklearn/v2/
- **KServe InferenceService**: https://kserve.github.io/website/latest/get_started/first_isvc/

---

**Labels**: `enhancement`, `medium-priority`, `mlops`, `model-validation`, `depends-on-adr-020`

**Estimated Effort**: 3-6 weeks (depends on platform support scope)

**Recommendation**: Review ADR-020 acceptance status before starting implementation. If ADR-020 is still PROPOSED, prioritize architectural review first.
