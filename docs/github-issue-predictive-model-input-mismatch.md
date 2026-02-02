# Predictive Analytics Model Input Mismatch with Coordination Engine

## Summary

The `predictive-analytics` KServe model expects 3264 features, but the coordination engine sends only 4 features (raw metrics), causing prediction failures with error:

```
X has 4 features, but StandardScaler is expecting 3264 features as input.
```

## Environment

- **OpenShift**: 4.18.21
- **Coordination Engine**: `quay.io/takinosh/openshift-coordination-engine:ocp-4.18-latest`
- **MCP Server**: `quay.io/takinosh/openshift-cluster-health-mcp:ocp-4.18-latest`
- **KServe**: sklearn server with `predictive-analytics` InferenceService

## Root Cause Analysis

### Training Side (Notebook)
The predictive analytics notebook (`notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb`) performs extensive **feature engineering**:
- Lag features (1, 2, 3, 6, 12, 24 hours)
- Rolling statistics (mean, std, max, min for windows 3, 6, 12, 24)
- Trend features (diff, pct_change)
- Time-based features (hour, day_of_week, is_weekend, etc.)

This results in **3264 features** for the model:
- 5 metrics × ~136 engineered features per metric × 24 lookback window

### Inference Side (Coordination Engine)
The coordination engine's KServe client (`pkg/clients/kserve.go:buildPredictiveAnalyticsRequest`) sends raw metrics without feature engineering:

```go
func (c *KServeClient) buildPredictiveAnalyticsRequest(req *PredictiveAnalyticsRequest) *InferenceRequest {
    var data [][]interface{}
    for _, metric := range req.Metrics {
        row := make([]interface{}, len(metric.Values))
        for i, val := range metric.Values {
            row[i] = val
        }
        data = append(data, row)
    }
    // ...
}
```

This sends only 4 features (cpu, memory, disk, network values).

## Logs

```json
{"error":"model predictive-analytics returned status 500: {\"error\":\"X has 4 features, but StandardScaler is expecting 3264 features as input.\"}","level":"error","model":"predictive-analytics","msg":"KServe prediction failed","time":"2026-01-28T23:45:12Z"}
```

## Proposed Solutions

### Option 1: Feature Engineering Preprocessor Service (Recommended)
Create a preprocessing service that sits between the coordination engine and KServe:

```
Coordination Engine → Feature Engineering Service → KServe Model
         (4 raw metrics)     (transforms to 3264)      (prediction)
```

**Pros**: Clean separation, reusable, model-agnostic
**Cons**: Additional service to deploy/maintain

### Option 2: Simpler Model Architecture
Train a model that works with raw metrics directly (without extensive feature engineering):

```python
# Simple sklearn Pipeline without lookback features
pipeline = Pipeline([
    ('scaler', StandardScaler()),
    ('regressor', RandomForestRegressor())
])
# Input: 4-5 raw metrics
```

**Pros**: Simple, no changes to coordination engine needed
**Cons**: Potentially lower accuracy without temporal features

### Option 3: Client-Side Feature Engineering
Add feature engineering logic to the coordination engine's Go code:

```go
func (c *KServeClient) engineerFeatures(metrics []MetricData) [][]float64 {
    // Implement lag, rolling, trend features in Go
}
```

**Pros**: No additional services
**Cons**: Duplicates Python logic in Go, harder to maintain

### Option 4: KServe Transformer
Use KServe's built-in Transformer feature to preprocess inputs:

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
spec:
  transformer:
    containers:
    - image: feature-engineering-transformer:latest
      name: transformer
  predictor:
    sklearn:
      storageUri: pvc://model-storage-pvc/predictive-analytics
```

**Pros**: KServe-native, clean architecture
**Cons**: Requires custom transformer image

## Acceptance Criteria

- [ ] Predictions from Lightspeed ("What will CPU be at 7 PM?") work correctly
- [ ] Coordination engine `/api/v1/predict` endpoint returns valid predictions
- [ ] Feature engineering is consistent between training and inference
- [ ] Model accuracy metrics are tracked (MAE, RMSE, R²)

## Related

- ADR-051: Predictive Analytics Model Training Strategy
- ADR-052: Model Training Data Source Selection Strategy
- Issue #13: Model registering as "model" instead of "predictive-analytics"

## Workaround

Until fixed, use the **PromQL-based linear projection** method shown by Lightspeed:

```promql
# Current cluster CPU %
sum(rate(container_cpu_usage_seconds_total[5m])) / sum(kube_node_status_capacity{resource="cpu"}) * 100

# Linear projection: slope * hours_until_target + current_value
```
