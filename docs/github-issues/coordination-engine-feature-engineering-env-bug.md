# Bug: ENABLE_FEATURE_ENGINEERING env var is ignored - always defaults to true

## Repository
`openshift-coordination-engine`

## Summary
The `ENABLE_FEATURE_ENGINEERING` environment variable is ignored by the prediction handler. The `DefaultPredictionHandlerConfig()` function hardcodes `EnableFeatureEngineering: true` instead of reading from the environment variable, making it impossible to disable feature engineering via configuration.

## Severity
**High** - This prevents users from deploying models trained with different feature counts (e.g., 5 features vs 3264 features).

## Environment
- Coordination Engine Version: `ocp-4.18-da9ffdc`
- OpenShift Version: 4.18.21
- KServe: Working correctly
- Model: sklearn Pipeline with 5 features (trained in fast mode)

## Steps to Reproduce

1. Deploy coordination engine with `ENABLE_FEATURE_ENGINEERING=false`:
```yaml
env:
- name: ENABLE_FEATURE_ENGINEERING
  value: "false"
- name: FEATURE_ENGINEERING_EXPECTED_COUNT
  value: "5"
```

2. Verify env var is set:
```bash
oc exec -n self-healing-platform deployment/coordination-engine -- printenv ENABLE_FEATURE_ENGINEERING
# Output: false
```

3. Check coordination engine startup logs:
```bash
oc logs -n self-healing-platform deployment/coordination-engine | grep -i feature
```

4. **Observe**: Log shows `"msg":"Predictive feature engineering enabled"` despite env var being `false`

## Expected Behavior
When `ENABLE_FEATURE_ENGINEERING=false`, the coordination engine should:
1. Log `"Predictive feature engineering disabled"` or skip the feature engineering log
2. Send only 5 raw features to the KServe model
3. Not attempt to build 3264 engineered features from Prometheus

## Actual Behavior
- Logs show `"Predictive feature engineering enabled"` regardless of env var
- Coordination engine attempts to send 3264 features to a model expecting 5 features
- KServe prediction requests fail with `context canceled` errors

## Root Cause Analysis

**File**: `pkg/api/v1/prediction.go`

**Problem**: The `DefaultPredictionHandlerConfig()` function hardcodes the value instead of reading from the config:

```go
// Current code (BUG)
func DefaultPredictionHandlerConfig() PredictionHandlerConfig {
    defaultConfig := features.DefaultPredictiveConfig()
    return PredictionHandlerConfig{
        EnableFeatureEngineering: true,  // <-- HARDCODED, ignores env var!
        LookbackHours:            defaultConfig.LookbackHours,
        ExpectedFeatureCount:     0,
    }
}
```

**Why it happens**:
- `main.go` calls `NewPredictionHandler()` without passing config
- `NewPredictionHandler()` calls `DefaultPredictionHandlerConfig()`
- `DefaultPredictionHandlerConfig()` returns hardcoded `true` instead of reading from `config.Get().FeatureEngineering.Enabled`

## Proposed Fix

### Option 1: Fix DefaultPredictionHandlerConfig (Recommended)

```go
// pkg/api/v1/prediction.go
func DefaultPredictionHandlerConfig() PredictionHandlerConfig {
    cfg := config.Get()  // Read from environment
    return PredictionHandlerConfig{
        EnableFeatureEngineering: cfg.FeatureEngineering.Enabled,
        LookbackHours:            cfg.FeatureEngineering.LookbackHours,
        ExpectedFeatureCount:     cfg.FeatureEngineering.ExpectedFeatureCount,
    }
}
```

### Option 2: Pass config from main.go

```go
// cmd/coordination-engine/main.go
cfg := config.Get()
predictionConfig := v1.PredictionHandlerConfig{
    EnableFeatureEngineering: cfg.FeatureEngineering.Enabled,
    LookbackHours:            cfg.FeatureEngineering.LookbackHours,
    ExpectedFeatureCount:     cfg.FeatureEngineering.ExpectedFeatureCount,
}
predictionHandler = v1.NewPredictionHandlerWithConfig(
    kserveProxyHandler.GetProxyClient(),
    prometheusClient,
    log,
    predictionConfig,
)
```

## Evidence from Logs

**Startup log (with ENABLE_FEATURE_ENGINEERING=false)**:
```json
{
  "base_metrics": 5,
  "expected_feature_count": 0,
  "feature_count": 3264,
  "level": "info",
  "lookback_hours": 24,
  "msg": "Predictive feature engineering enabled",
  "time": "2026-01-29T21:56:36Z"
}
```

**Prediction errors**:
```json
{
  "duration": 0,
  "endpoint": "http://predictive-analytics-stable...:8080/v1/models/predictive-analytics:predict",
  "error": "context canceled",
  "level": "error",
  "model": "predictive-analytics",
  "msg": "KServe predict request failed"
}
```

## Related Files

| File | Issue |
|------|-------|
| `pkg/api/v1/prediction.go` | `DefaultPredictionHandlerConfig()` hardcodes `true` |
| `pkg/config/config.go` | Correctly reads env var into `FeatureEngineering.Enabled` |
| `cmd/coordination-engine/main.go` | Uses default config instead of passing env-based config |

## Verification Steps After Fix

1. Deploy with `ENABLE_FEATURE_ENGINEERING=false`
2. Check startup logs - should NOT show "feature engineering enabled"
3. Test prediction endpoint:
```bash
curl -X POST http://coordination-engine:8080/api/v1/predict \
  -H 'Content-Type: application/json' \
  -d '{}'
```
4. Should return predictions from the 5-feature model without errors

## Workaround (None)
There is currently no workaround - the env var is completely ignored.

## Additional Context

This bug was discovered while testing the predictive analytics model training pipeline. Models trained in "fast mode" use 5 features (raw metrics), while production models use 3264 engineered features. The inability to disable feature engineering prevents testing simple models.

### Config reading works correctly
The `pkg/config/config.go` correctly reads the env var:
```go
Enabled: getEnvAsBool("ENABLE_FEATURE_ENGINEERING", DefaultFeatureEngineeringEnabled),
```

The bug is that `DefaultPredictionHandlerConfig()` doesn't use this config.

---

**Labels**: `bug`, `high-priority`, `feature-engineering`, `prediction-api`

**Assignee**: @tosin2013

**Milestone**: v1.0.1
