# KServe Model Registration Fix (Issue #13)

This document explains the fix for [Issue #13](https://github.com/tosin2013/openshift-aiops-platform/issues/13) where KServe InferenceServices were registering models as `"model"` instead of their InferenceService names.

## Problem Summary

**Before the fix:**
- Models registered as `"model"` instead of `"predictive-analytics"` and `"anomaly-detector"`
- Prediction requests failed: `/v1/models/predictive-analytics:predict` → 404 error
- Only `/v1/models/model:predict` worked (wrong name)

**Root cause:**
The `predictive_analytics.py` script saved models in a flat directory structure instead of KServe's expected subdirectory structure.

## Solution Implemented

### 1. Updated `predictive_analytics.py`

**Changes made:**
- Modified `save_models()` to create KServe-compatible directory structure
- Added KServe wrapper class support for sklearn server compatibility
- Updated `load_models()` to support both new and legacy formats
- Automatic migration from old flat structure to new structure

**Directory structure (before → after):**

```diff
# BEFORE (❌ Incorrect)
/mnt/models/
├── cpu_usage_step_0_model.pkl
├── cpu_usage_step_1_model.pkl
├── memory_usage_step_0_model.pkl
└── metadata.json

# AFTER (✅ Correct)
/mnt/models/
└── predictive-analytics/
    └── model.pkl  # Single file containing all models + scalers + metadata
```

### 2. Created `kserve_wrapper.py`

A wrapper class that provides sklearn-compatible interface for KServe's sklearn server:
- Implements `predict()` method that KServe expects
- Handles feature engineering internally
- Returns predictions in KServe-compatible format

### 3. Created `train_predictive_analytics.py`

A training script that demonstrates proper model saving:

```bash
# Train and save model with KServe compatibility
python src/models/train_predictive_analytics.py \
    --model-dir /mnt/models \
    --samples 2000 \
    --forecast-horizon 12 \
    --lookback-window 24
```

## How to Use

### Option 1: Use the Training Script (Recommended)

```bash
# Inside the model-serving pod or notebook
cd /workspace/repo/src/models
python train_predictive_analytics.py
```

This will:
1. Generate sample training data
2. Train the predictive analytics model
3. Save it in KServe-compatible format at `/mnt/models/predictive-analytics/model.pkl`

### Option 2: Update Existing Code

If you have existing training code, update it to use the new format:

```python
from predictive_analytics import PredictiveAnalytics

# Train your model
predictor = PredictiveAnalytics(forecast_horizon=12, lookback_window=24)
predictor.train(training_data)

# Save with KServe compatibility (NEW)
predictor.save_models('/mnt/models', kserve_compatible=True)  # ✅ Creates /mnt/models/predictive-analytics/model.pkl

# Old way (DEPRECATED)
# predictor.save_models('/mnt/models', kserve_compatible=False)  # ❌ Creates flat structure
```

### Option 3: Update Notebooks

Update Jupyter notebooks to use KServe-compatible saving:

```python
# In your notebook cell
from pathlib import Path
from predictive_analytics import PredictiveAnalytics

# Use /mnt/models for persistent storage (model-storage-pvc)
MODELS_DIR = Path('/mnt/models') if Path('/mnt/models').exists() else Path('/opt/app-root/src/models')

# Train model
predictor = PredictiveAnalytics()
predictor.train(data)

# Save with KServe compatibility
predictor.save_models(str(MODELS_DIR), kserve_compatible=True)

print(f"✅ Model saved to: {MODELS_DIR}/predictive-analytics/model.pkl")
```

## Verification

After deploying the fix, verify that models are correctly registered:

```bash
# Get the InferenceService pod IP
PREDICTOR_IP=$(oc get pod -l serving.kserve.io/inferenceservice=predictive-analytics -o jsonpath='{.items[0].status.podIP}')

# List available models
curl http://${PREDICTOR_IP}:8080/v1/models
# Expected: {"models":["predictive-analytics"]}  ✅

# Check model status
curl http://${PREDICTOR_IP}:8080/v1/models/predictive-analytics
# Expected: {"name":"predictive-analytics","ready":true}  ✅

# Test prediction
curl -X POST http://${PREDICTOR_IP}:8080/v1/models/predictive-analytics:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[...]]}'
# Expected: Predictions returned successfully  ✅
```

## Migration Path

### For Existing Deployments

The code automatically migrates old models to the new structure:

1. **Deploy updated code** to the cluster
2. **Run the training script** - it will:
   - Detect old model files (`*_step_*_model.pkl`, `*_scaler.pkl`)
   - Create new KServe-compatible structure
   - Migrate old files to new location
   - Clean up old files
3. **Restart InferenceService** to pick up new model structure:
   ```bash
   oc delete pod -l serving.kserve.io/inferenceservice=predictive-analytics
   ```

### Backward Compatibility

The updated `load_models()` method supports both formats:
- ✅ **New format** (KServe-compatible): `/mnt/models/predictive-analytics/model.pkl`
- ✅ **Old format** (legacy): `/mnt/models/*_step_*_model.pkl` + metadata.json

## Files Modified

1. **`src/models/predictive_analytics.py`**
   - Updated `save_models()` method
   - Updated `load_models()` method
   - Added KServe wrapper integration

2. **`src/models/kserve_wrapper.py`** (NEW)
   - Provides sklearn-compatible interface for KServe

3. **`src/models/train_predictive_analytics.py`** (NEW)
   - Training script with KServe-compatible model saving

## Testing Checklist

After implementing the fix:

- [x] Code changes implemented
- [ ] Models saved in correct directory structure
- [ ] `GET /v1/models` returns `["predictive-analytics"]`
- [ ] `GET /v1/models/predictive-analytics` returns model metadata
- [ ] `POST /v1/models/predictive-analytics:predict` succeeds
- [ ] Coordination engine predictions work end-to-end
- [ ] MCP server tools complete successfully

## Related Files

- **InferenceService config**: `charts/hub/templates/model-serving.yaml`
- **ServingRuntime config**: `charts/hub/templates/kserve-runtimes.yaml`
- **Coordination engine client**: `internal/integrations/kserve_client.go`

## References

- [KServe v1 Protocol](https://kserve.github.io/website/latest/modelserving/data_plane/v1_protocol/)
- [KServe PVC Storage](https://kserve.github.io/website/latest/modelserving/storage/pvc/)
- [Issue #13](https://github.com/tosin2013/openshift-aiops-platform/issues/13)
