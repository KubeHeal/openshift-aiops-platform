# MCP Server: Implement Feature Engineering for Anomaly Detection Model

## Summary

The `analyze-anomalies` MCP tool needs to be updated to call the coordination engine's anomaly analysis endpoint instead of KServe directly. The coordination engine will handle the feature engineering (45 numeric features from Prometheus metrics).

**Depends on**: [`coordination-engine-anomaly-analysis-endpoint.md`](./coordination-engine-anomaly-analysis-endpoint.md)

## Current Behavior (Bug)

The MCP server sends:
```json
{
  "instances": [{
    "metric": "cpu_usage",
    "namespace": "self-healing-platform",
    "deployment": "broken-app",
    "time_range": "1h"
  }]
}
```

## Expected Behavior

The MCP server should:
1. Query Prometheus for the 5 base metrics
2. Perform feature engineering (45 features total)
3. Send properly formatted numeric array to KServe

```json
{
  "instances": [[0.65, 0.62, 0.08, 0.52, 0.78, 0.64, 0.61, 0.01, 0.016, ...]]
}
```

## Feature Engineering Requirements

The model expects **45 features** derived from 5 base metrics. For each metric, create 9 features:

### Base Metrics (from Prometheus)
1. `node_cpu_utilization`
2. `node_memory_utilization`  
3. `pod_cpu_usage`
4. `pod_memory_usage`
5. `container_restart_count`

### Feature Engineering per Metric (9 features each)
| Feature | Description | Prometheus Window |
|---------|-------------|-------------------|
| `{metric}_value` | Current value | instant |
| `{metric}_mean_5m` | 5-minute rolling mean | `avg_over_time(...[5m])` |
| `{metric}_std_5m` | 5-minute rolling stddev | `stddev_over_time(...[5m])` |
| `{metric}_min_5m` | 5-minute rolling min | `min_over_time(...[5m])` |
| `{metric}_max_5m` | 5-minute rolling max | `max_over_time(...[5m])` |
| `{metric}_lag_1` | 1-minute lagged value | `...offset 1m` |
| `{metric}_lag_5` | 5-minute lagged value | `...offset 5m` |
| `{metric}_diff` | Difference from previous | `current - lag_1` |
| `{metric}_pct_change` | Percent change | `(current - lag_1) / lag_1` |

### Total: 5 metrics × 9 features = 45 features

## Implementation Options

### Option A: Implement in MCP Server (Not Recommended)

> **Note**: Option B (Coordination Engine) is preferred. This option is documented for reference only.

Add feature engineering to `internal/tools/analyze_anomalies.go`:

```go
func (t *AnalyzeAnomaliesTool) buildFeatureVector(ctx context.Context, input AnalyzeAnomaliesInput) ([]float64, error) {
    features := make([]float64, 0, 45)
    
    baseMetrics := []string{
        "node_cpu_utilization",
        "node_memory_utilization", 
        "pod_cpu_usage",
        "pod_memory_usage",
        "container_restart_count",
    }
    
    for _, metric := range baseMetrics {
        // Query current value
        current := t.queryPrometheus(ctx, metric, input.Namespace, input.Pod)
        
        // Query rolling stats
        mean5m := t.queryPrometheus(ctx, fmt.Sprintf("avg_over_time(%s[5m])", metric), ...)
        std5m := t.queryPrometheus(ctx, fmt.Sprintf("stddev_over_time(%s[5m])", metric), ...)
        min5m := t.queryPrometheus(ctx, fmt.Sprintf("min_over_time(%s[5m])", metric), ...)
        max5m := t.queryPrometheus(ctx, fmt.Sprintf("max_over_time(%s[5m])", metric), ...)
        
        // Query lag values
        lag1 := t.queryPrometheus(ctx, fmt.Sprintf("%s offset 1m", metric), ...)
        lag5 := t.queryPrometheus(ctx, fmt.Sprintf("%s offset 5m", metric), ...)
        
        // Calculate derived features
        diff := current - lag1
        pctChange := 0.0
        if lag1 != 0 {
            pctChange = (current - lag1) / lag1
        }
        
        features = append(features, current, mean5m, std5m, min5m, max5m, lag1, lag5, diff, pctChange)
    }
    
    return features, nil
}
```

### Option B: Call Coordination Engine (Recommended) ✅

The coordination engine handles Prometheus queries and feature engineering, exposing a higher-level API.

**See**: [`coordination-engine-anomaly-analysis-endpoint.md`](./coordination-engine-anomaly-analysis-endpoint.md)

**MCP Server Change Required**:
Update `analyze-anomalies` tool to call coordination engine instead of KServe directly:

```go
// internal/tools/analyze_anomalies.go

// Change from:
// prediction, err := t.kserveClient.Predict(ctx, input.ModelName, instances)

// To:
response, err := t.coordinationEngine.AnalyzeAnomalies(ctx, &AnalyzeAnomaliesRequest{
    TimeRange:   input.TimeRange,
    Namespace:   input.Namespace,
    Deployment:  input.Deployment,
    Pod:         input.Pod,
    LabelSelector: input.LabelSelector,
    Threshold:   input.Threshold,
    ModelName:   input.ModelName,
})
```

This is a small change once the coordination engine endpoint exists.

### Option C: Create KServe Transformer (Not Recommended)

Deploy a KServe transformer that handles preprocessing before the Isolation Forest predictor.

> **Note**: This adds deployment complexity. Option B is simpler.

## Prometheus Query Examples

For namespace-scoped analysis:
```promql
# Current CPU utilization
sum(rate(container_cpu_usage_seconds_total{namespace="self-healing-platform"}[5m])) 
  / sum(kube_pod_container_resource_requests{resource="cpu",namespace="self-healing-platform"})

# 5-minute rolling mean
avg_over_time(
  sum(rate(container_cpu_usage_seconds_total{namespace="self-healing-platform"}[5m]))[5m:]
)

# Memory utilization
sum(container_memory_working_set_bytes{namespace="self-healing-platform"})
  / sum(kube_pod_container_resource_limits{resource="memory",namespace="self-healing-platform"})
```

## Testing

After implementation, verify with:
```bash
# Test that model receives 45 features
curl -X POST http://anomaly-detector-predictor:8080/v1/models/model:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[<45 float values>]]}'

# Expected response
{"predictions": [-1]}  # -1 = anomaly, 1 = normal
```

## Files to Modify

### MCP Server
- `internal/tools/analyze_anomalies.go` - Update to call coordination engine
- `pkg/clients/coordination_engine.go` - Add `AnalyzeAnomalies` method (if not exists)

### Documentation
- Update tool description to reflect actual behavior

## Scope

With the coordination engine handling feature engineering, this MCP server issue is now a **small change**:
- ~20 lines of code to update the tool
- ~30 lines for coordination engine client method

## References

- **Model Training Notebook**: `notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb`
- **Feature Engineering Code**: Cell 6 `create_feature_matrix()` function
- **KServe Model Path**: `/mnt/models/anomaly-detector/model.pkl`

## Priority

**High** - This blocks the end-to-end self-healing demo with Lightspeed.

## Labels

`bug`, `mcp-server`, `ml-integration`, `feature-engineering`
