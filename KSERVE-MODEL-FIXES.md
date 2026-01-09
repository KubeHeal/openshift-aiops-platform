# KServe Model Loading Fixes - Implementation Guide

**Status**: Phase 1 Complete (Python engine removed), Phase 2 Ready to Start
**Date**: 2026-01-09
**Critical**: Yes - Required for KServe predictors to work

## Background

Testing revealed that both KServe predictors are failing to load models:

1. **anomaly-detector-predictor**: CrashLoopBackOff
   - Error: `RuntimeError: More than one model file is detected, Only one is allowed within model_dir: [PosixPath('/mnt/models/prophet_model.pkl'), PosixPath('/mnt/models/arima_model.pkl')]`

2. **predictive-analytics-predictor**: Running but empty `/mnt/models/` directory
   - No model files present, causing connection refused errors

**Root Cause**: Notebooks save models incorrectly for KServe consumption.

## KServe Requirements

KServe sklearn server expects:
- **ONE** .pkl file per model: `/mnt/models/{model-name}/model.pkl`
- File must contain a single serializable object (Pipeline recommended)
- Cannot have multiple .pkl files in the same directory

## Required Fixes

### Fix 1: Time-Series Anomaly Detection Notebook

**File**: `notebooks/02-anomaly-detection/02-time-series-anomaly-detection.ipynb`

**Current Problem**:
```python
# Current code (BROKEN)
with open(MODEL_DIR / 'arima_model.pkl', 'wb') as f:
    pickle.dump(arima_model, f)
with open(MODEL_DIR / 'prophet_model.pkl', 'wb') as f:
    pickle.dump(prophet_model, f)
```

**Solution**: Create a wrapper class that combines both models:

```python
from sklearn.base import BaseEstimator, TransformerMixin
import pickle

class TimeSeriesEnsemble(BaseEstimator, TransformerMixin):
    """
    Wrapper class that combines ARIMA and Prophet models for KServe compatibility.
    KServe requires a single .pkl file, not multiple model files.
    """
    def __init__(self, arima_model=None, prophet_model=None):
        self.arima_model = arima_model
        self.prophet_model = prophet_model

    def predict(self, X, periods=None):
        """
        Make predictions using both models and return ensemble result.

        Args:
            X: Input data (DataFrame or array-like)
            periods: Number of periods to forecast (for time series)

        Returns:
            Dictionary with predictions from both models
        """
        results = {}

        if self.arima_model is not None:
            try:
                # ARIMA forecast
                arima_forecast = self.arima_model.forecast(steps=periods or len(X))
                results['arima'] = arima_forecast
            except Exception as e:
                results['arima_error'] = str(e)

        if self.prophet_model is not None:
            try:
                # Prophet forecast
                import pandas as pd
                future = self.prophet_model.make_future_dataframe(periods=periods or len(X))
                prophet_forecast = self.prophet_model.predict(future)
                results['prophet'] = prophet_forecast['yhat'].values
            except Exception as e:
                results['prophet_error'] = str(e)

        # Return ensemble (average of both predictions)
        if 'arima' in results and 'prophet' in results:
            results['ensemble'] = (results['arima'] + results['prophet']) / 2
        elif 'arima' in results:
            results['ensemble'] = results['arima']
        elif 'prophet' in results:
            results['ensemble'] = results['prophet']

        return results

    def get_params(self, deep=True):
        return {
            'arima_model': self.arima_model,
            'prophet_model': self.prophet_model
        }

    def set_params(self, **params):
        for key, value in params.items():
            setattr(self, key, value)
        return self

# Updated saving code
ensemble_model = TimeSeriesEnsemble(
    arima_model=arima_model,
    prophet_model=prophet_model
)

# Save as SINGLE .pkl file for KServe
model_path = MODEL_DIR / 'model.pkl'
with open(model_path, 'wb') as f:
    pickle.dump(ensemble_model, f)
logger.info(f"Saved ensemble model to {model_path}")

# Verify only ONE file exists
pkl_files = list(MODEL_DIR.glob('*.pkl'))
assert len(pkl_files) == 1, f"ERROR: Expected 1 .pkl file, found {len(pkl_files)}: {pkl_files}"
print(f"✅ Model saved correctly for KServe: {pkl_files[0]}")
```

**Cell to Update**: Cell #10 (the "Save models with KServe-compatible paths" cell)

### Fix 2: Identify Predictive-Analytics Model Notebook

**Problem**: Empty `/mnt/models/` directory - no files being saved

**Action Required**:
1. Search for which notebook trains the predictive-analytics model:
   ```bash
   grep -r "predictive.analytics\|predictive_analytics" notebooks/
   ```
2. Verify the model saving path is: `/mnt/models/predictive-analytics/model.pkl`
3. Ensure only ONE .pkl file is saved
4. Add validation to confirm file exists after saving

**Likely Candidates**:
- `notebooks/02-anomaly-detection/03-lstm-based-prediction.ipynb`
- Check for notebooks that reference "predictive-analytics" model name

### Fix 3: Verify Isolation Forest Notebook

**File**: `notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb`

**Commit 98d993c** already updated this to use sklearn Pipeline:
```python
isolation_forest_pipeline = Pipeline([
    ('scaler', RobustScaler()),
    ('isolation_forest', IsolationForest(**ISOLATION_FOREST_CONFIG))
])
joblib.dump(isolation_forest_pipeline, MODEL_DIR / 'model.pkl')
```

**Action**: Verify this is working correctly:
1. Check that only ONE .pkl file exists in MODEL_DIR
2. Confirm path is `/mnt/models/anomaly-detector/model.pkl`
3. Test that KServe can load it

### Fix 4: Update Model Storage Helpers

**File**: `notebooks/utils/model_storage_helpers.py`

Add validation function:

```python
def validate_kserve_model_structure(model_dir: Path, model_name: str) -> bool:
    """
    Validate that model directory structure is KServe-compatible.

    KServe Requirements:
    - Only ONE .pkl file per model directory
    - File must be named 'model.pkl' (recommended)
    - Directory path: /mnt/models/{model-name}/

    Args:
        model_dir: Path to model directory
        model_name: Name of the model

    Returns:
        True if valid, raises exception if invalid
    """
    # Check directory exists
    if not model_dir.exists():
        raise FileNotFoundError(f"Model directory not found: {model_dir}")

    # Find all .pkl files
    pkl_files = list(model_dir.glob('*.pkl'))

    if len(pkl_files) == 0:
        raise FileNotFoundError(
            f"No .pkl files found in {model_dir}. "
            f"KServe requires exactly ONE .pkl file."
        )

    if len(pkl_files) > 1:
        raise RuntimeError(
            f"KServe ERROR: Found {len(pkl_files)} .pkl files in {model_dir}. "
            f"KServe sklearn server requires EXACTLY ONE .pkl file per model.\n"
            f"Files found: {[f.name for f in pkl_files]}\n"
            f"Solution: Combine multiple models into a single wrapper class."
        )

    logger.info(f"✅ KServe validation passed: {pkl_files[0]}")
    return True

def save_model_to_pvc(model, model_name: str, pvc_mount='/mnt/models'):
    """
    Save model to PVC with KServe-compatible structure.

    Args:
        model: Model object to save (should be Pipeline or wrapper)
        model_name: Name of model (e.g., 'anomaly-detector')
        pvc_mount: PVC mount point
    """
    import joblib
    from pathlib import Path

    # Create model-specific subdirectory
    model_dir = Path(pvc_mount) / model_name
    model_dir.mkdir(parents=True, exist_ok=True)

    # Save as model.pkl (KServe convention)
    model_path = model_dir / 'model.pkl'
    joblib.dump(model, model_path)
    logger.info(f"Saved model to: {model_path}")

    # Validate structure
    try:
        validate_kserve_model_structure(model_dir, model_name)
    except Exception as e:
        logger.error(f"KServe validation failed: {e}")
        raise

    return model_path
```

## Testing Steps

After making the fixes:

### 1. Re-run Notebooks
```bash
# Execute time-series notebook with fixes
jupyter nbconvert --execute --to notebook \
  notebooks/02-anomaly-detection/02-time-series-anomaly-detection.ipynb \
  --output /tmp/test-output.ipynb

# Check model saved correctly
ls -la /mnt/models/anomaly-detector/
# Should show ONLY: model.pkl (one file)

# Execute predictive-analytics notebook
jupyter nbconvert --execute --to notebook \
  notebooks/02-anomaly-detection/[predictive-analytics-notebook].ipynb \
  --output /tmp/test-output-pa.ipynb

# Check model saved
ls -la /mnt/models/predictive-analytics/
# Should show ONLY: model.pkl (one file)
```

### 2. Restart KServe Predictors
```bash
# Delete failing pods to trigger restart with new models
oc delete pod -n self-healing-platform \
  -l app=isvc.anomaly-detector-predictor

oc delete pod -n self-healing-platform \
  -l app=isvc.predictive-analytics-predictor

# Wait for pods to restart
oc get pods -n self-healing-platform -w
```

### 3. Verify Model Loading
```bash
# Check anomaly-detector logs (should NOT crash)
oc logs -n self-healing-platform \
  -l app=isvc.anomaly-detector-predictor \
  --tail=50

# Should see: "Model loaded successfully" or similar
# Should NOT see: "RuntimeError: More than one model file"

# Check predictive-analytics logs
oc logs -n self-healing-platform \
  -l app=isvc.predictive-analytics-predictor \
  --tail=50

# Should see model loaded, NOT empty directory errors
```

### 4. Test Coordination Engine Integration
```bash
# Port-forward coordination engine
oc port-forward -n self-healing-platform \
  svc/coordination-engine 8080:8080 &

# List models (should show both)
curl http://localhost:8080/api/v1/models
# Expected: {"models":["anomaly-detector","predictive-analytics"],"count":2}

# Test anomaly-detector prediction
curl -X POST http://localhost:8080/api/v1/detect \
  -H "Content-Type: application/json" \
  -d '{
    "model": "anomaly-detector",
    "instances": [[0.5, 1.2, 0.8, 0.3, 0.9]]
  }'
# Expected: {"predictions": [1] or [-1], ...}  (not error)

# Test predictive-analytics prediction
curl -X POST http://localhost:8080/api/v1/detect \
  -H "Content-Type: application/json" \
  -d '{
    "model": "predictive-analytics",
    "instances": [[1.0, 2.0, 3.0, 4.0, 5.0]]
  }'
# Expected: {"predictions": [...], ...}  (not connection refused)
```

### 5. Verify Pod Status
```bash
# Both should be Running (not CrashLoopBackOff)
oc get pods -n self-healing-platform | grep predictor
# anomaly-detector-predictor-xxx      1/1   Running   0   5m
# predictive-analytics-predictor-xxx  1/1   Running   0   5m
```

## Success Criteria

- [ ] Time-series notebook saves single model.pkl file
- [ ] Predictive-analytics notebook saves single model.pkl file
- [ ] Isolation forest notebook verified (already fixed in commit 98d993c)
- [ ] Model storage helpers include KServe validation
- [ ] anomaly-detector pod Running (no crash)
- [ ] predictive-analytics pod Running (no crash)
- [ ] `/api/v1/models` returns both models
- [ ] `/api/v1/detect` successfully calls both models
- [ ] End-to-end test: notebook → save model → KServe loads → coordination engine calls → prediction returned

## Additional Notes

- KServe sklearn server source: https://github.com/kserve/kserve/tree/master/python/sklearnserver
- The server uses joblib.load() internally, expecting a single object
- Multiple .pkl files cause: "More than one model file is detected, Only one is allowed"
- Empty directory causes: Connection refused (server can't start without model)

## Next Steps

1. Implement TimeSeriesEnsemble wrapper class (copy code above into notebook)
2. Update notebook cell to use ensemble wrapper
3. Find and fix predictive-analytics model notebook
4. Add validation to model_storage_helpers.py
5. Test end-to-end as described above
6. Document any issues found for Go coordination engine repo
