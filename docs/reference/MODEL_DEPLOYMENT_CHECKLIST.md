# Model Deployment Checklist

This checklist ensures ML models are deployed correctly to the self-healing platform and prevents common configuration errors.

## Quick Start: Adding a New Model

To add a new model to the platform, simply add it to the `models:` array in `charts/hub/values.yaml`:

```yaml
models:
  - name: anomaly-detector
    cpu: "500m"
    memory: "1Gi"
    cpuLimit: "2"
    memoryLimit: "4Gi"
    syncWave: "2"
  - name: predictive-analytics
    cpu: "1"
    memory: "2Gi"
    cpuLimit: "2"
    memoryLimit: "4Gi"
    syncWave: "2"
  # Add your new model here:
  - name: your-model-name
    cpu: "1"
    memory: "2Gi"
    cpuLimit: "2"
    memoryLimit: "4Gi"
    syncWave: "2"
```

That's it! The Helm chart will automatically:
- ✅ Create an InferenceService with correct `--model_name` parameter
- ✅ Configure proper resource limits
- ✅ Set up ArgoCD sync wave ordering
- ✅ Mount the model storage PVC

## Detailed Deployment Steps

### 1. Train and Save Model

**Notebook Requirements:**
- [ ] Model is saved to `/mnt/models/{model-name}/model.pkl`
- [ ] Model name in directory path **exactly matches** the name in values.yaml
- [ ] Model is in KServe-compatible format (pickle for sklearn)
- [ ] Model file size is reasonable (< 1GB recommended)

**Example (in Jupyter notebook):**
```python
import joblib
import os

# Model name MUST match values.yaml entry
model_name = "your-model-name"
model_dir = f"/mnt/models/{model_name}"

# Create directory if needed
os.makedirs(model_dir, exist_ok=True)

# Save model
joblib.dump(model, f"{model_dir}/model.pkl")

# Verify file exists and size
import subprocess
result = subprocess.run(['ls', '-lh', f'{model_dir}/model.pkl'],
                       capture_output=True, text=True)
print(result.stdout)
```

### 2. Configure Model in values.yaml

**File:** `charts/hub/values.yaml`

- [ ] Add model entry to `models:` array
- [ ] Set appropriate CPU/memory requests based on model size
- [ ] Configure CPU/memory limits (usually 2x requests)
- [ ] Set sync wave (usually "2" for models that depend on storage)

**Resource Sizing Guidelines:**
- **Small models** (< 50MB): `cpu: "500m"`, `memory: "1Gi"`
- **Medium models** (50MB-500MB): `cpu: "1"`, `memory: "2Gi"`
- **Large models** (> 500MB): `cpu: "2"`, `memory: "4Gi"`

### 3. Configure Model Validation

**File:** `k8s/operators/jupyter-notebook-validator/notebooks/predictive-analytics-validation.yaml`

Create a NotebookValidationJob for your model:

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: your-model-name-validation
  namespace: self-healing-platform
spec:
  notebookPath: notebooks/your-model-name.ipynb
  sourceURL: https://github.com/your-org/your-repo.git
  sourceBranch: main
  modelValidation:
    enabled: true
    inferenceServiceName: your-model-name  # MUST match model name
```

- [ ] `notebookPath` points to correct notebook
- [ ] `inferenceServiceName` **exactly matches** model name in values.yaml
- [ ] `modelValidation.enabled: true` is set

### 4. Commit and Deploy

```bash
cd /home/lab-user/openshift-aiops-platform

# Review changes
git status
git diff

# Commit changes
git add charts/hub/values.yaml
git add k8s/operators/jupyter-notebook-validator/notebooks/
git commit -m "feat: Add your-model-name model serving

- Add your-model-name to models configuration
- Configure resources: 1 CPU, 2Gi memory
- Add NotebookValidationJob for model validation"

# Push to repository
git push

# Sync ArgoCD application
argocd app sync self-healing-platform --prune
```

### 5. Verify Deployment

**Wait for pods to start:**
```bash
# Watch pod creation
oc get pods -n self-healing-platform -l serving.kserve.io/inferenceservice=your-model-name -w

# Wait for Ready status (timeout after 5 minutes)
oc wait --for=condition=Ready \
  pod -l serving.kserve.io/inferenceservice=your-model-name \
  -n self-healing-platform --timeout=300s
```

**Check model registration:**
```bash
# Get predictor pod IP
PREDICTOR_IP=$(oc get pod \
  -l serving.kserve.io/inferenceservice=your-model-name \
  -n self-healing-platform \
  -o jsonpath='{.items[0].status.podIP}')

# Check model is registered with CORRECT name
curl http://${PREDICTOR_IP}:8080/v1/models

# Expected output: {"models":["your-model-name"]}
# ❌ WRONG: {"models":["model"]} - means --model_name is missing!
```

**Verify model metadata:**
```bash
curl http://${PREDICTOR_IP}:8080/v1/models/your-model-name

# Expected output:
# {
#   "name": "your-model-name",
#   "ready": true,
#   "versions": ["1"]
# }
```

**Test prediction endpoint:**
```bash
# Make test prediction (adjust payload for your model)
curl -X POST http://${PREDICTOR_IP}:8080/v1/models/your-model-name:predict \
  -H 'Content-Type: application/json' \
  -d '{
    "instances": [
      [0.5, 0.6, 0.4, 100, 80]
    ]
  }'

# Expected: JSON response with predictions
# Status code should be 200
```

**Check pod logs:**
```bash
# Check for successful model loading
oc logs -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=your-model-name \
  --tail=50 | grep -i "model\|load\|error"

# ✅ GOOD: "Model your-model-name loaded successfully"
# ❌ BAD: "failed to locate model file for model model"
```

### 6. Integration Testing

**Test coordination engine integration:**
```bash
# Get coordination engine pod
COORD_POD=$(oc get pod \
  -l app.kubernetes.io/component=coordination-engine \
  -n self-healing-platform \
  -o jsonpath='{.items[0].metadata.name}')

# Verify coordination engine can reach model
oc exec -n self-healing-platform $COORD_POD -- \
  curl -s http://your-model-name-predictor:8080/v1/models

# Expected: {"models":["your-model-name"]}
```

**Test MCP server integration:**
```bash
# Check MCP server can query model
# This should be tested via OpenShift Lightspeed or MCP client
# MCP tools should return predictions without errors
```

## Common Mistakes to Avoid

### ❌ MISTAKE #1: Missing --model_name Parameter
**Symptom:** KServe registers model as `"model"` instead of actual name
```bash
curl http://${PREDICTOR_IP}:8080/v1/models
# Returns: {"models":["model"]}  # ❌ WRONG!
```

**Solution:**
- This is now **automatically handled** by the Helm template
- The `--model_name={{ .name }}` parameter is set automatically from values.yaml
- If you see this error, ensure your model is in the `models:` array in values.yaml

### ❌ MISTAKE #2: Model Name Mismatch
**Symptom:** Model not found, 404 errors
```
Error: Model with name your-model-name does not exist
```

**Solution:** Ensure consistency across ALL locations:
- ✅ Directory path: `/mnt/models/your-model-name/model.pkl`
- ✅ values.yaml: `models[].name: "your-model-name"`
- ✅ NotebookValidationJob: `inferenceServiceName: "your-model-name"`

### ❌ MISTAKE #3: Model File Not Found
**Symptom:** Pod logs show "failed to locate model file"
```
failed to locate model file for model your-model-name under dir /mnt/models/your-model-name
```

**Solution:**
1. Verify model file exists:
   ```bash
   oc exec -n self-healing-platform \
     deployment/your-model-name-predictor -- \
     ls -lh /mnt/models/your-model-name/model.pkl
   ```
2. Ensure notebook saved model to correct path
3. Check PVC is mounted correctly

### ❌ MISTAKE #4: Insufficient Resources
**Symptom:** Pod OOMKilled or CPU throttling
```
Last State: Terminated
Reason: OOMKilled
```

**Solution:**
- Increase memory limits in values.yaml
- Monitor actual usage: `oc adm top pod -l serving.kserve.io/inferenceservice=your-model-name`
- Adjust resources based on model size and request volume

### ❌ MISTAKE #5: Not Waiting for Model to Load
**Symptom:** Early requests fail, later requests succeed

**Solution:**
- KServe models can take 30-60 seconds to load on first start
- Use the `oc wait --for=condition=Ready` command before testing
- NotebookValidationJob should wait for InferenceService Ready status

### ❌ MISTAKE #6: Skipping Validation
**Symptom:** Errors discovered only when MCP server queries model

**Solution:**
- Always create a NotebookValidationJob with `modelValidation.enabled: true`
- Test prediction endpoints before declaring model ready
- Add integration tests in the validation notebook

## Troubleshooting Guide

### Model Not Registering
```bash
# Check InferenceService status
oc get inferenceservice your-model-name -n self-healing-platform

# Check predictor deployment
oc get deployment your-model-name-predictor -n self-healing-platform

# Check pod status
oc get pods -l serving.kserve.io/inferenceservice=your-model-name -n self-healing-platform

# View detailed events
oc describe inferenceservice your-model-name -n self-healing-platform
```

### Prediction Errors
```bash
# Check pod logs for errors
oc logs -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=your-model-name \
  --tail=100

# Test with verbose curl
curl -v -X POST http://${PREDICTOR_IP}:8080/v1/models/your-model-name:predict \
  -H 'Content-Type: application/json' \
  -d '{"instances": [[1, 2, 3]]}'

# Check if model is ready
curl http://${PREDICTOR_IP}:8080/v1/models/your-model-name
```

### MCP Server Can't Reach Model
```bash
# Check coordination engine logs
oc logs -n self-healing-platform \
  deployment/coordination-engine \
  --tail=100 | grep -i "model\|predict\|error"

# Check MCP server logs
oc logs -n self-healing-platform \
  deployment/mcp-server \
  --tail=100 | grep -i "model\|predict\|error"

# Test DNS resolution
oc exec -n self-healing-platform deployment/coordination-engine -- \
  nslookup your-model-name-predictor.self-healing-platform.svc.cluster.local
```

## Success Criteria Checklist

Before marking a model deployment as complete, verify:

- [ ] ✅ KServe pod logs show model loaded with **correct name**
- [ ] ✅ `curl /v1/models` returns `{"models":["your-model-name"]}`
- [ ] ✅ `curl /v1/models/your-model-name` returns `"ready": true`
- [ ] ✅ `curl /v1/models/your-model-name:predict` returns predictions (200 status)
- [ ] ✅ NotebookValidationJob status is Success
- [ ] ✅ MCP server tools work without "model does not exist" errors
- [ ] ✅ Coordination engine successfully calls prediction endpoints
- [ ] ✅ No errors in coordination engine logs
- [ ] ✅ No errors in MCP server logs
- [ ] ✅ Model responds to test predictions within acceptable latency

## Historical Context

### Why This Checklist Exists

**Issue #13 - KServe Model Registration Fix (2026-01-27)**

**Problem:** MCP server was receiving errors when trying to use model prediction tools:
```
Error: Model with name model does not exist.
```

**Root Cause:** KServe's sklearnserver defaults to model name `"model"` when no `--model_name` parameter is specified. Our InferenceService configurations were missing this parameter.

**Impact:**
- ❌ Models registered as `"model"` instead of actual names
- ❌ API calls to `/v1/models/predictive-analytics:predict` returned 404
- ❌ Coordination engine got 503 errors when calling models
- ❌ MCP server tools completely non-functional

**Solution Implemented:**
1. **Immediate Fix:** Added `--model_name` parameter to InferenceServices
2. **Long-term Fix:** Refactored to values.yaml driven configuration
3. **Prevention:** Created this checklist and templated model deployment

**Key Lesson:** Always explicitly set `--model_name` parameter in KServe InferenceServices. The default value of `"model"` is rarely what you want.

## Related Documentation

- [KServe SKLearn Server Documentation](https://github.com/kserve/kserve/tree/master/python/sklearnserver)
- [InferenceService API Reference](https://kserve.github.io/website/0.11/reference/api/)
- [Jupyter Notebook Validator Operator](../k8s/operators/jupyter-notebook-validator/README.md)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

## Quick Reference: Add a Model in 3 Steps

```bash
# 1. Add to values.yaml models array
models:
  - name: new-model
    cpu: "1"
    memory: "2Gi"

# 2. Commit and push
git add charts/hub/values.yaml
git commit -m "feat: Add new-model serving"
git push

# 3. Sync ArgoCD
argocd app sync self-healing-platform

# That's it! ✅
```
