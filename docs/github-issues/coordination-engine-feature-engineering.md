# GitHub Issue: Feature Engineering Mismatch and Prometheus Query Failure

**Repository**: [openshift-coordination-engine](https://github.com/KubeHeal/openshift-coordination-engine)
**Created**: 2026-01-29
**Priority**: High
**Labels**: `bug`, `feature-engineering`, `predictive-analytics`

---

## Bug Report: Feature Engineering Mismatch and Prometheus Query Failure

### Summary

Predictive analytics predictions fail with two related issues:
1. **Feature count mismatch**: Go code generates 3200 features, model expects 3264
2. **Prometheus range query bug**: Queries return "No data" despite working when called directly via curl

### Environment

- **Coordination Engine Image**: `quay.io/takinosh/openshift-coordination-engine:ocp-4.18-latest`
- **Model**: `predictive-analytics` (sklearn Pipeline with StandardScaler expecting 3264 features)
- **OpenShift Version**: 4.18.21
- **KServe**: sklearnserver:latest

### Bug 1: Feature Count Mismatch

#### Expected Behavior
Model receives 3264 features matching the trained StandardScaler expectation.

#### Actual Behavior
Coordination engine generates 3200 features, causing model rejection:
```
{"error":"X has 3200 features, but StandardScaler is expecting 3264 features as input."}
```

#### Root Cause Analysis

| Component | Time Features | Formula | Total |
|-----------|---------------|---------|-------|
| **Python notebook** | 6 | `24 × (5 + 6 + 25×5) = 24 × 136` | **3264** |
| **Go code** | 8 | `(5×25×24) + (8×24) + 8` | **3200** |

**Python time features (6)** in `src/models/predictive_analytics.py`:
- `hour`
- `day_of_week`
- `day_of_month`
- `month`
- `is_weekend`
- `is_business_hours`

**Go time features (8)** in `pkg/features/predictive.go`:
- `hour_of_day`
- `day_of_week`
- `is_weekend`
- `month`
- `quarter` ← **EXTRA**
- `day_of_month`
- `week_of_year` ← **EXTRA**
- `is_business_hours`

#### Proposed Fix

Update `pkg/features/predictive.go` to use 6 time features matching the Python notebook:

```go
// Time-based feature names - MUST match Python notebook exactly
var timeFeatureNames = []string{
    "hour",             // 0-23 (was hour_of_day)
    "day_of_week",      // 0-6 (Monday=0)
    "day_of_month",     // 1-31
    "month",            // 1-12
    "is_weekend",       // 0 or 1
    "is_business_hours", // 0 or 1 (9-17 weekdays)
}

// TimeFeatureCount is the number of time-based features
const TimeFeatureCount = 6  // Changed from 8
```

And update the formula calculation to match Python:
```go
// Python formula: lookback × (metrics + time_features + features_per_metric × metrics)
// = 24 × (5 + 6 + 25×5) = 24 × 136 = 3264
func (b *PredictiveFeatureBuilder) calculateTotalFeatures() int {
    columnsPerTimestep := len(predictiveBaseMetrics) + TimeFeatureCount +
                          (FeaturesPerMetric * len(predictiveBaseMetrics))
    return b.config.LookbackHours * columnsPerTimestep
}
```

---

### Bug 2: Prometheus Range Query Failure

#### Expected Behavior
Prometheus range queries return time series data for feature engineering.

#### Actual Behavior
All range queries return empty results:
```json
{"level":"debug","msg":"No data returned for predictive range query","query":"avg(rate(container_cpu_usage_seconds_total{container!=\"\",pod!=\"\"}[5m]))"}
```

#### Direct curl WORKS

When testing the same query directly from the pod:
```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://prometheus-k8s.openshift-monitoring.svc:9091/api/v1/query_range?query=avg(rate(container_cpu_usage_seconds_total%7Bcontainer!=%22%22,pod!=%22%22%7D%5B5m%5D))&start=${START}&end=${NOW}&step=300"
```

Returns valid matrix data:
```json
{"status":"success","data":{"resultType":"matrix","result":[{"metric":{},"values":[[1769647825,"0.003554019"],...]}]}}
```

#### Root Cause Hypothesis

The `pkg/features/prometheus_adapter.go` likely has an issue parsing the Prometheus API matrix response format. Possible causes:
1. Not handling `resultType: "matrix"` correctly (only handling `"vector"`)
2. URL encoding issues with the query string
3. Response body not being read/parsed correctly

#### Proposed Fix

Review and fix `pkg/features/prometheus_adapter.go`:

1. Ensure matrix responses are parsed correctly:
```go
type PrometheusResponse struct {
    Status string `json:"status"`
    Data   struct {
        ResultType string `json:"resultType"`
        Result     []struct {
            Metric map[string]string `json:"metric"`
            Values [][]interface{}   `json:"values"` // For matrix
            Value  []interface{}     `json:"value"`  // For vector
        } `json:"result"`
    } `json:"data"`
}
```

2. Add debug logging for raw response body
3. Verify URL encoding of query parameters

---

### Enhancement: Configurable Training Windows

#### Current Limitation
Training data window and prediction lookback are conflated.

#### Proposed Enhancement
Add separate configuration for training data duration while keeping prediction lookback fixed:

| Parameter | Purpose | Default | Options |
|-----------|---------|---------|---------|
| `TRAINING_DATA_HOURS` | Historical data for model training | 168 | 24, 168, 720 |
| `FEATURE_ENGINEERING_LOOKBACK_HOURS` | Prediction input window | 24 | Fixed at 24 |

This allows:
- **24h** training for development/testing
- **168h** (1 week) training for production anomaly detection
- **720h** (30 days) training for seasonal pattern capture

Without affecting the feature vector size (stays at 3264).

---

### Files to Modify

1. **`pkg/features/predictive.go`**
   - Update `timeFeatureNames` to 6 features
   - Update `TimeFeatureCount` constant to 6
   - Fix feature calculation formula

2. **`pkg/features/prometheus_adapter.go`**
   - Fix matrix response parsing
   - Add debug logging for response body

3. **`docs/FEATURE-ENGINEERING-GUIDE.md`**
   - Update formula: `lookback × (metrics + time_features + features_per_metric × metrics)`
   - Update time features table (remove `quarter`, `week_of_year`)
   - Update expected feature count: 3200 → 3264
   - Add section on training vs prediction windows

---

### Verification Steps

After fixes are applied:

1. Set expected feature count for validation:
   ```yaml
   env:
     - name: FEATURE_ENGINEERING_EXPECTED_COUNT
       value: "3264"
   ```

2. Enable debug logging:
   ```yaml
   env:
     - name: LOG_LEVEL
       value: "debug"
   ```

3. Test prediction:
   ```bash
   curl -X POST http://coordination-engine:8080/api/v1/predict \
     -H "Content-Type: application/json" \
     -d '{"scope":"cluster","metric":"cpu","target_date":"2026-01-29","target_time":"19:00"}'
   ```

4. Verify logs show:
   - Prometheus queries returning data
   - Feature count = 3264
   - Successful prediction response

---

### Related Documentation

- **Training Notebook**: `notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb`
- **Python Model**: `src/models/predictive_analytics.py`
- **Feature Engineering Guide**: `docs/FEATURE-ENGINEERING-GUIDE.md`
- **Blog Post**: `docs/blog/17-training-ml-models-with-tekton.md`

### Related Issues

- Issue #13: KServe model name registration
- Issue #54: Feature engineering implementation

---

### Bug 3: KServe Response Parsing Failure (NEW - 2026-01-29)

**Status**: Discovered after Bug 1 and Bug 2 were fixed in version `ocp-4.18-b44ea29`

#### Expected Behavior
Coordination engine parses KServe model response and returns prediction results.

#### Actual Behavior
JSON parsing fails when processing the model response:
```json
{"error":"failed to parse forecast response from model predictive-analytics: json: cannot unmarshal number into Go struct field .predictions of type []float64","level":"error","model":"predictive-analytics","msg":"KServe prediction failed","time":"2026-01-29T02:41:21Z"}
```

#### KServe Model Returns Correct Format

Direct test to KServe model works correctly:
```bash
# Test with 3264 zero features
curl -X POST "http://predictive-analytics-stable:8080/v1/models/predictive-analytics:predict" \
  -H "Content-Type: application/json" \
  -d '{"instances": [[0.0, 0.0, ... (3264 zeros) ...]]}'

# Response (CORRECT):
{"predictions":[0.12351758718119261]}
```

The model returns `{"predictions": [0.123...]}` (array format), which is correct.

#### Root Cause Hypothesis

The Go code in `pkg/clients/kserve.go` or response parsing has a struct field mismatch. The error suggests:
- The code expects `predictions` to be `[]float64` (array)
- But it's receiving what appears to be a single number

Possible causes:
1. The struct has nested fields and `.predictions` refers to an inner field
2. The response parsing is looking at a different JSON path
3. There may be a different response format when using batch predictions vs single predictions

#### Proposed Fix

Review `pkg/clients/kserve.go` response parsing:

```go
// Current struct might be something like:
type ForecastResponse struct {
    Predictions float64 `json:"predictions"`  // WRONG - expects number
}

// Should be:
type ForecastResponse struct {
    Predictions []float64 `json:"predictions"`  // CORRECT - expects array
}

// Or handle both cases:
type KServeResponse struct {
    Predictions interface{} `json:"predictions"` // Can be []float64 or float64
}
```

Also verify the response parsing logic handles sklearn server output format:
```go
// sklearn server returns: {"predictions": [value1, value2, ...]}
// NOT: {"predictions": {"values": [...]}} or other nested formats
```

#### Verification

After fix:
```bash
# Test prediction
curl -X POST http://coordination-engine:8080/api/v1/predict \
  -H "Content-Type: application/json" \
  -d '{"scope":"cluster","metric":"cpu","target_date":"2026-01-29","target_time":"19:00"}'

# Expected response (example):
{"status":"success","prediction":{"cpu_usage":0.45,"confidence":0.85}}
```

---

### Files to Modify (Updated)

1. **`pkg/features/predictive.go`** ✅ Fixed in b44ea29
   - Update `timeFeatureNames` to 6 features
   - Update `TimeFeatureCount` constant to 6
   - Fix feature calculation formula

2. **`pkg/features/prometheus_adapter.go`** ✅ Fixed in b44ea29
   - Fix matrix response parsing
   - Add debug logging for response body

3. **`pkg/clients/kserve.go`** ❌ NEW BUG
   - Fix `ForecastResponse` struct to use `[]float64` for predictions
   - Handle sklearn server response format correctly

4. **`docs/FEATURE-ENGINEERING-GUIDE.md`**
   - Update formula: `lookback × (metrics + time_features + features_per_metric × metrics)`
   - Update time features table (remove `quarter`, `week_of_year`)
   - Update expected feature count: 3200 → 3264
   - Add section on training vs prediction windows

---

### Acceptance Criteria

- [x] Feature count matches model expectation (3264) ✅ Fixed in b44ea29
- [x] Prometheus range queries return valid data ✅ Fixed in b44ea29
- [ ] **KServe response parsing handles sklearn server format** ❌ NEW BUG
- [ ] Predictions complete successfully within timeout
- [ ] FEATURE-ENGINEERING-GUIDE.md updated with correct formula
- [ ] Unit tests pass with new feature count

---

### Timeline

| Date | Version | Status |
|------|---------|--------|
| 2026-01-28 | Pre-b44ea29 | Feature count: 3200, Prometheus queries: failing |
| 2026-01-29 | ocp-4.18-b44ea29 | Feature count: 3264 ✅, Prometheus: working ✅, Response parsing: failing ❌ |

### Configuration Applied

```yaml
# charts/hub/values.yaml
coordinationEngine:
  kserve:
    timeout: "120s"  # Increased from 10s for feature engineering
  featureEngineering:
    enabled: true
    lookbackHours: 24
    expectedFeatureCount: 3264
```
