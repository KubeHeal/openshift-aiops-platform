# Feature Contract Mismatch: Coordination Engine vs Predictive Model

## Repository
`openshift-coordination-engine`

## Summary
The coordination engine's raw metrics mode sends 4 features (`hour`, `dayOfWeek`, `cpuRollingMean`, `memoryRollingMean`) but the trained predictive analytics model expects 5 features (`cpu_usage`, `memory_usage`, `disk_usage`, `network_in`, `network_out`).

## Severity
**High** - Predictions fail with feature count mismatch when feature engineering is disabled.

## Context
After fixing the `ENABLE_FEATURE_ENGINEERING` env var bug (now correctly reads from config), predictions fail because the feature sets don't match.

## Current Behavior

**Coordination Engine (`buildRawMetricInstances`)**:
```go
// pkg/api/v1/prediction.go line 695
func (h *PredictionHandler) buildRawMetricInstances(hour, dayOfWeek int, cpuRollingMean, memoryRollingMean float64) [][]float64 {
    return [][]float64{{
        float64(hour),         // Feature 1: Time of day
        float64(dayOfWeek),    // Feature 2: Day of week
        cpuRollingMean,        // Feature 3: Rolling mean CPU
        memoryRollingMean,     // Feature 4: Rolling mean memory
    }}
}
```

**Trained Model Expects**:
```python
# 5 raw metrics from training data
features = ['cpu_usage', 'memory_usage', 'disk_usage', 'network_in', 'network_out']
```

## Error Message
```json
{
  "status": "error",
  "error": "Prediction failed",
  "details": "model predictive-analytics returned status 500: {\"error\":\"X has 4 features, but StandardScaler is expecting 5 features as input.\"}",
  "code": "PREDICTION_FAILED"
}
```

## Options to Resolve

### Option A: Update Coordination Engine (Recommended)
Change `buildRawMetricInstances` to send 5 metrics that match the model:

```go
func (h *PredictionHandler) buildRawMetricInstances(ctx context.Context) ([][]float64, error) {
    // Fetch current metrics from Prometheus
    cpuUsage := h.getMetric(ctx, "cluster:node_cpu:ratio_rate5m")
    memoryUsage := h.getMetric(ctx, "avg(instance:node_memory_utilisation:ratio)")
    diskUsage := h.getMetric(ctx, "1 - sum(node_filesystem_avail_bytes) / sum(node_filesystem_size_bytes)")
    networkIn := h.getMetric(ctx, "sum(rate(container_network_receive_bytes_total[5m]))")
    networkOut := h.getMetric(ctx, "sum(rate(container_network_transmit_bytes_total[5m]))")

    return [][]float64{{
        cpuUsage,
        memoryUsage,
        diskUsage,
        networkIn,
        networkOut,
    }}, nil
}
```

**Pros**:
- Aligns with standard ML model training approach
- Uses actual current metrics for predictions
- More accurate predictions based on real values

**Cons**:
- Requires more Prometheus queries
- Breaking change to API contract

### Option B: Retrain Model to Match Coordination Engine
Retrain the model to accept 4 features (hour, dayOfWeek, cpuRollingMean, memoryRollingMean).

**Pros**:
- No coordination engine changes needed
- Simpler feature set

**Cons**:
- Model has less information for predictions
- Time-based predictions may not capture actual system state

### Option C: Support Both Feature Sets (Most Flexible)
Add a new endpoint or parameter to support different feature sets:

```go
type PredictRequest struct {
    // ... existing fields ...
    FeatureMode string `json:"feature_mode"` // "time_based" (4 features) or "metrics" (5 features)
}
```

## Recommendation
**Option A** is recommended because:
1. The model should predict based on current system state (actual metrics)
2. Using time-based features alone limits prediction accuracy
3. The model was designed to predict future resource usage based on current values

## Related Issues
- Fixed: ENABLE_FEATURE_ENGINEERING env var bug
- Related: Bug 3 - KServe response parsing (separate issue)

## Testing After Fix
```bash
# Test prediction with metrics-based input
curl -X POST http://coordination-engine:8080/api/v1/predict \
  -H 'Content-Type: application/json' \
  -d '{}' | jq .

# Expected: 200 OK with predictions array
```

---

**Labels**: `bug`, `feature-request`, `prediction-api`, `breaking-change`

**Assignee**: @tosin2013
