# Bug: Prometheus Metrics Not Normalized for Cluster Capacity

## Summary

The coordination engine's Prometheus queries for `cpu_rolling_mean` and `memory_rolling_mean` return values that are not properly normalized to the cluster's actual capacity. This causes the ML model to receive incorrect input features, resulting in unreliable predictions.

**Repository**: `openshift-coordination-engine`
**Type**: Bug / Enhancement
**Priority**: High
**Labels**: `bug`, `prometheus`, `ml-integration`, `metrics`

---

## Problem Statement

### Current Behavior

When Lightspeed asks "What will CPU and memory be at 3 PM?", the response shows:

```
Current baseline the model used: CPU ~0% and memory ~43.0%
```

But actual cluster utilization is much higher. The model's predictions are based on incorrect baseline values.

### Root Cause

The Prometheus queries don't account for:
1. **Multiple CPUs**: Cluster has N cores, but query returns per-container average
2. **Cluster capacity**: No normalization against allocatable resources
3. **Pod aggregation**: Not summing across all pods correctly

---

## Technical Analysis

### Current CPU Query (Line 157)

```go
query := `avg(rate(container_cpu_usage_seconds_total{container!="",pod!=""}[24h]))`
```

**What it returns**: Average CPU cores per container (~0.09 cores)
**What model expects**: Cluster CPU utilization as ratio (0.0-1.0)

**Example**:
- Cluster has 100 allocatable CPU cores
- Total usage is 30 cores
- Query returns: `avg(0.1, 0.05, 0.2, ...) ≈ 0.09` (per-container average)
- Should return: `30 / 100 = 0.30` (30% cluster utilization)

### Current Memory Query (Lines 193, 199)

```go
// Primary - often fails when containers don't have limits
query := `avg(container_memory_usage_bytes / container_spec_memory_limit_bytes > 0)`

// Fallback - returns NODE level, not container
query = `1 - avg(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)`
```

**What fallback returns**: Node-level memory ratio (~1.0 = 100%)
**What model expects**: Cluster memory utilization as ratio (0.0-1.0)

**Problem with fallback**:
- Node memory includes kernel caches, buffers
- Shows ~100% because Linux uses available RAM for caching
- Not representative of actual workload memory pressure

---

## Proposed Fix

### New CPU Query

```go
// Cluster CPU utilization = total CPU used / total allocatable CPU
query := `
  sum(rate(container_cpu_usage_seconds_total{container!="",pod!=""}[5m]))
  /
  sum(kube_node_status_allocatable{resource="cpu"})
`
```

**Why this works**:
- `sum(rate(...))` = Total CPU cores used across all containers
- `sum(kube_node_status_allocatable{resource="cpu"})` = Total allocatable CPU cores
- Result: 0.0-1.0 ratio representing cluster CPU utilization

### New Memory Query

```go
// Cluster memory utilization = total memory used / total allocatable memory
query := `
  sum(container_memory_working_set_bytes{container!="",pod!=""})
  /
  sum(kube_node_status_allocatable{resource="memory"})
`
```

**Why this works**:
- `container_memory_working_set_bytes` = Actual memory in use (excludes cache)
- `sum(kube_node_status_allocatable{resource="memory"})` = Total allocatable memory
- Result: 0.0-1.0 ratio representing cluster memory utilization

### Alternative Queries (if kube_node_status_allocatable unavailable)

```go
// CPU fallback using node_cpu metrics
query := `
  1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))
`

// Memory fallback using node_memory metrics (more accurate than current)
query := `
  1 - (
    sum(node_memory_MemAvailable_bytes)
    /
    sum(node_memory_MemTotal_bytes)
  )
`
```

---

## Implementation Plan

### File to Modify

`internal/integrations/prometheus_client.go`

### Changes Required

#### 1. Update `GetCPURollingMean` (Line 142-177)

```go
func (c *PrometheusClient) GetCPURollingMean(ctx context.Context) (float64, error) {
    if !c.IsAvailable() {
        return 0, fmt.Errorf("prometheus client not available")
    }

    cacheKey := "cpu_rolling_mean"
    if value, ok := c.getCached(cacheKey); ok {
        return value, nil
    }

    // Primary query: Cluster CPU utilization as ratio of allocatable
    query := `sum(rate(container_cpu_usage_seconds_total{container!="",pod!=""}[5m])) / sum(kube_node_status_allocatable{resource="cpu"})`
    
    value, err := c.queryInstant(ctx, query)
    if err != nil {
        // Fallback: Use node-level CPU idle time
        c.log.WithError(err).Debug("Primary CPU query failed, trying node-level fallback")
        query = `1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))`
        value, err = c.queryInstant(ctx, query)
        if err != nil {
            c.log.WithError(err).Debug("Failed to query CPU rolling mean from Prometheus")
            return 0, err
        }
    }

    // Value should already be 0-1 range
    normalizedValue := clampToUnitRange(value)

    c.setCached(cacheKey, normalizedValue)
    c.log.WithFields(logrus.Fields{
        "raw_value":        value,
        "normalized_value": normalizedValue,
        "query":            query,
    }).Debug("Retrieved CPU rolling mean from Prometheus")

    return normalizedValue, nil
}
```

#### 2. Update `GetMemoryRollingMean` (Line 179-218)

```go
func (c *PrometheusClient) GetMemoryRollingMean(ctx context.Context) (float64, error) {
    if !c.IsAvailable() {
        return 0, fmt.Errorf("prometheus client not available")
    }

    cacheKey := "memory_rolling_mean"
    if value, ok := c.getCached(cacheKey); ok {
        return value, nil
    }

    // Primary query: Cluster memory utilization as ratio of allocatable
    query := `sum(container_memory_working_set_bytes{container!="",pod!=""}) / sum(kube_node_status_allocatable{resource="memory"})`
    
    value, err := c.queryInstant(ctx, query)
    if err != nil {
        // Fallback: Use node-level available memory
        c.log.WithError(err).Debug("Primary memory query failed, trying node-level fallback")
        query = `1 - (sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))`
        value, err = c.queryInstant(ctx, query)
        if err != nil {
            c.log.WithError(err).Debug("Failed to query memory rolling mean from Prometheus")
            return 0, err
        }
    }

    // Value should already be 0-1 range
    normalizedValue := clampToUnitRange(value)

    c.setCached(cacheKey, normalizedValue)
    c.log.WithFields(logrus.Fields{
        "raw_value":        value,
        "normalized_value": normalizedValue,
        "query":            query,
    }).Debug("Retrieved memory rolling mean from Prometheus")

    return normalizedValue, nil
}
```

#### 3. Update Scoped Queries

Similar changes needed for:
- `GetScopedCPURollingMean` (Line 270-308)
- `GetScopedMemoryRollingMean` (Line 310-353)
- `buildScopedCPUQuery` (Line 355-379)
- `buildScopedMemoryQuery` (Line 381-405)

For scoped queries:
- **Namespace scope**: Sum container metrics in namespace / namespace quota (or cluster allocatable)
- **Deployment scope**: Sum container metrics for deployment pods / deployment resource requests
- **Pod scope**: Pod container metrics / pod resource requests

---

## Testing

### Verification Queries

Run these in Prometheus UI or via curl to verify new queries work:

```bash
# Test CPU utilization query
curl -s "http://prometheus:9090/api/v1/query" \
  --data-urlencode 'query=sum(rate(container_cpu_usage_seconds_total{container!="",pod!=""}[5m])) / sum(kube_node_status_allocatable{resource="cpu"})' \
  | jq '.data.result[0].value[1]'

# Test memory utilization query  
curl -s "http://prometheus:9090/api/v1/query" \
  --data-urlencode 'query=sum(container_memory_working_set_bytes{container!="",pod!=""}) / sum(kube_node_status_allocatable{resource="memory"})' \
  | jq '.data.result[0].value[1]'
```

### Expected Results

| Metric | Before Fix | After Fix | Reason |
|--------|------------|-----------|--------|
| CPU | ~0.09 (9%) | ~0.30-0.60 | Now ratio of total capacity |
| Memory | ~1.0 (100%) | ~0.40-0.70 | Uses working_set, not node cache |

### Integration Test

After fix, verify via Lightspeed:
```
"What will CPU and memory be at 3 PM today?"
```

Should show:
- Current CPU baseline: 30-60% (realistic)
- Current Memory baseline: 40-70% (realistic)
- Predictions with confidence: 0.85

---

## Model Training Considerations

### Option A: Retrain Model (Recommended)

After fixing the queries, the model should be retrained with data that uses the corrected metrics. This ensures:
1. Training data matches inference data
2. Model learns correct patterns
3. Predictions are calibrated to actual cluster behavior

### Option B: Model Works As-Is

The current model was trained with synthetic data that uses 0-1 ratios. If the fixed queries also return 0-1 ratios, the model should work without retraining. However, retraining with real cluster data would improve accuracy.

---

## Related Issues

- `coordination-engine-flexible-model-response-parsing.md` - Model response format fix
- `mcp-server-kserve-url-bug.md` - KServe URL construction fix

## References

- [Prometheus container_cpu_usage_seconds_total](https://prometheus.io/docs/guides/cadvisor/)
- [kube-state-metrics allocatable resources](https://github.com/kubernetes/kube-state-metrics/blob/main/docs/node-metrics.md)
- [container_memory_working_set_bytes vs container_memory_usage_bytes](https://blog.freshtracks.io/a-deep-dive-into-kubernetes-metrics-part-3-container-resource-metrics-361c5ee46e66)

---

## Acceptance Criteria

- [ ] CPU rolling mean returns cluster CPU utilization (0.0-1.0)
- [ ] Memory rolling mean returns cluster memory utilization (0.0-1.0)
- [ ] Scoped queries return namespace/deployment/pod level utilization
- [ ] Fallback queries work when primary metrics unavailable
- [ ] Unit tests cover all query variants
- [ ] Integration test: Lightspeed shows realistic baseline values
- [ ] Model predictions align with actual cluster behavior
