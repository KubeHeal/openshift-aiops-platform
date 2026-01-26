# Notebook Validation Job Samples

This directory contains example NotebookValidationJob manifests demonstrating v1.0.5 features.

## Features Demonstrated

### 1. ArgoCD Integration (ADR-049)

**Auto-Restart InferenceServices**:
```yaml
annotations:
  mlops.dev/on-success-trigger: |
    - apiVersion: serving.kserve.io/v1beta1
      kind: InferenceService
      name: predictive-analytics
      namespace: self-healing-platform
      action: restart
```

This solves the manual pod deletion issue for InferenceServices that need to reload models after training.

**Sync Wave Coordination**:
```yaml
annotations:
  argocd.argoproj.io/sync-wave: "3"  # Run this in wave 3
  mlops.dev/block-wave: "4"           # Block wave 4 until success
```

### 2. Model Validation (ADR-020)

Validate notebooks work with deployed KServe models:

```yaml
modelValidation:
  enabled: true
  platform: kserve
  phase: both  # Clean + existing environments
  targetModels:
    - predictive-analytics
  predictionValidation:
    enabled: true
    testData: |
      {"instances": [[1.0, 2.0, 3.0, 4.0, 5.0]]}
    expectedOutput: |
      {"predictions": [[0.8, 0.2]]}
    tolerance: "0.1"
```

### 3. Exit Code Validation (ADR-041)

Catch silent failures (None returns, NaN values):

```yaml
validationConfig:
  level: "production"
  strictMode: true
  detectSilentFailures: true
  checkOutputTypes: true
```

### 4. Advanced Comparison (ADR-030)

Handle non-deterministic ML outputs:

```yaml
comparisonConfig:
  strategy: "normalized"
  floatingPointTolerance: "0.01"
  ignoreTimestamps: true
  ignoreExecutionCount: true
```

## Usage

### Apply Validation Job

```bash
kubectl apply -f predictive-analytics-validation-job.yaml
```

### Monitor Progress

```bash
# Watch validation job status
kubectl get notebookvalidationjob predictive-analytics-kserve-validation -n self-healing-platform -w

# Check logs
oc logs -n self-healing-platform \
  -l mlops.dev/validation-job=predictive-analytics-kserve-validation \
  --tail=100

# Watch InferenceService auto-restart
oc get pods -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=predictive-analytics -w
```

### Verify Success

```bash
# Check InferenceService is ready after auto-restart
oc get inferenceservice predictive-analytics -n self-healing-platform
# Expected: 2/2 ready (READY predictor)

# Check ArgoCD UI for health status (if ArgoCD integration enabled)
```

## Prerequisites

1. **Operator**: jupyter-notebook-validator-operator v1.0.5+ deployed
2. **RBAC**: Updated ClusterRole with InferenceService patch permissions
3. **ArgoCD**: Health check ConfigMap applied (optional, for UI visibility)
4. **Storage**: PVC `model-storage-pvc` exists in `self-healing-platform` namespace
5. **KServe**: InferenceService `predictive-analytics` deployed

## Troubleshooting

### InferenceService Not Auto-Restarting

Check RBAC permissions:
```bash
oc auth can-i patch inferenceservices.serving.kserve.io \
  --as=system:serviceaccount:jupyter-notebook-validator-operator:jupyter-notebook-validator-controller-manager \
  -n self-healing-platform
```

Should return `yes`. If not, apply updated ClusterRole:
```bash
kubectl apply -f ../base/rbac/role.yaml
```

### Model Validation Failing

Check InferenceService is ready:
```bash
oc get inferenceservice predictive-analytics -n self-healing-platform
```

Check prediction endpoint:
```bash
oc logs -n self-healing-platform \
  -l mlops.dev/validation-job=predictive-analytics-kserve-validation \
  | grep "Model validation"
```

### Silent Failure Detection

If validation passes but notebook has logical errors, increase strictMode:
```yaml
validationConfig:
  level: "production"
  strictMode: true
  checkOutputTypes: true
  expectedOutputs:
    - cell: 10
      type: "object"
      notEmpty: true
```

## References

- Platform ADR-029: Jupyter Notebook Validator Operator
- Operator ADR-020: Model-Aware Validation Strategy
- Operator ADR-041: Exit Code Validation Developer Safety
- Operator ADR-049: ArgoCD Integration Strategy
- Operator docs: `/home/lab-user/jupyter-notebook-validator-operator/docs/ARGOCD_INTEGRATION.md`
