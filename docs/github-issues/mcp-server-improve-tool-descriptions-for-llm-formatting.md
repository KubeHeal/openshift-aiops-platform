# Enhancement: Improve MCP Tool Descriptions for Better LLM Response Formatting

## Summary

The MCP server tool descriptions should be enhanced to guide LLMs (like OpenShift Lightspeed) on how to properly interpret and present prediction results to users. Currently, Lightspeed sometimes shows confusing "Current reported CPU: 0.0%" when the actual rolling mean is ~3.7%.

**Repository**: `openshift-cluster-health-mcp`
**Type**: Enhancement
**Priority**: Medium
**Labels**: `enhancement`, `ux`, `mcp-tools`, `llm-prompting`
**Status**: ✅ **IMPLEMENTED** (commit `c39302f`)

---

## Problem Statement

### Current Behavior

When users ask "What will CPU and memory be at 3 PM?", Lightspeed responds with:

```
CPU usage: ~23.10% (predicted). Confidence: 85%. Current reported CPU: 0.0% (odd — may indicate missing/zeroed metrics).
Memory usage: ~24.28% (predicted). Current reported memory: 43.03%.
```

The "Current reported CPU: 0.0%" is confusing because:
1. The API actually returns `cpu_rolling_mean: 3.66%` (correct value)
2. The LLM may be misinterpreting which field represents "current" values
3. Users see a warning about "missing/zeroed metrics" when data is actually fine

### Root Cause

The tool description for `predict-resource-usage` doesn't clearly explain:
- What `current_metrics` fields mean (24h rolling mean vs. instant value)
- How to present predictions vs. current baseline to users
- The difference between `predictions` and `current_metrics` in the response

---

## Proposed Solution

### 1. Update `predict-resource-usage` Tool Description

**Current** (`pkg/tools/predict_resource_usage.go`):
```go
Description: "Predict future CPU and memory usage using ML models. Supports cluster, namespace, deployment, or pod scope.",
```

**Proposed**:
```go
Description: `Predict future CPU and memory usage using ML models trained on historical cluster data.

RESPONSE INTERPRETATION:
- predictions.cpu_percent / memory_percent: Forecasted usage at target time
- current_metrics.cpu_rolling_mean: Current 24-hour average CPU utilization (0-100%)
- current_metrics.memory_rolling_mean: Current 24-hour average memory utilization (0-100%)
- model_info.confidence: Model confidence score (0.0-1.0, multiply by 100 for percentage)

PRESENTATION GUIDELINES:
- Present predictions as "Predicted CPU: X%" not "CPU usage: ~X%"
- Present current_metrics as "Current baseline (24h avg): CPU X%, Memory Y%"
- If confidence < 0.7, warn user predictions may be unreliable
- If rolling_mean values are 0, this likely indicates Prometheus scraping issues

SCOPES:
- cluster: Entire cluster resource usage
- namespace: Single namespace (requires namespace parameter)
- deployment: Specific deployment (requires namespace + deployment)
- pod: Individual pod (requires namespace + pod)`,
```

### 2. Update `analyze-anomalies` Tool Description

**Proposed Enhancement**:
```go
Description: `Detect anomalies in cluster resource usage using ML models (Isolation Forest).

RESPONSE INTERPRETATION:
- is_anomaly: true if current metrics deviate significantly from baseline
- anomaly_score: -1.0 to 1.0 (negative = anomaly, positive = normal)
- anomaly_type: Classification (e.g., "resource_exhaustion", "memory_leak", "cpu_spike")
- severity: "low", "medium", "high", "critical"
- features_analyzed: Which metrics were evaluated

PRESENTATION GUIDELINES:
- If is_anomaly=false: "No anomalies detected. Cluster is operating normally."
- If is_anomaly=true: "ANOMALY DETECTED: [anomaly_type] with [severity] severity"
- Always include recommended_action if provided
- For memory_leak: Suggest checking pod memory limits and application code
- For cpu_spike: Suggest checking for runaway processes or scale issues`,
```

### 3. Update `calculate-pod-capacity` Tool Description

**Proposed Enhancement**:
```go
Description: `Calculate remaining pod capacity based on current resource usage and cluster limits.

RESPONSE INTERPRETATION:
- remaining_pods: Number of additional pods that can be scheduled
- cpu_headroom_percent: Percentage of CPU capacity still available
- memory_headroom_percent: Percentage of memory capacity still available
- limiting_factor: What will run out first ("cpu", "memory", or "pod_limit")

PRESENTATION GUIDELINES:
- Present as "You can run approximately X more medium-sized pods"
- If headroom < 20%, warn about capacity constraints
- If limiting_factor is "pod_limit", mention cluster pod limits not resources
- Always mention both CPU and memory headroom for context

DEFAULT ASSUMPTIONS (use if user doesn't specify):
- pod_cpu_request: 100m (0.1 cores) - typical small workload
- pod_memory_request: 256Mi - typical small workload
- scope: cluster (unless namespace specified in context)`,
```

---

## Implementation

### Files to Modify

1. `pkg/tools/predict_resource_usage.go` - Update Description field
2. `pkg/tools/analyze_anomalies.go` - Update Description field  
3. `pkg/tools/calculate_pod_capacity.go` - Update Description field

### Example Implementation

```go
// pkg/tools/predict_resource_usage.go

func NewPredictResourceUsageTool(ceClient *clients.CoordinationEngineClient) *PredictResourceUsageTool {
    return &PredictResourceUsageTool{
        BaseTool: BaseTool{
            ToolName: "predict-resource-usage",
            Description: `Predict future CPU and memory usage using ML models trained on historical cluster data.

RESPONSE INTERPRETATION:
- predictions.cpu_percent / memory_percent: Forecasted usage at target time (0-100%)
- current_metrics.cpu_rolling_mean: Current 24-hour average CPU utilization (0-100%)
- current_metrics.memory_rolling_mean: Current 24-hour average memory utilization (0-100%)
- model_info.confidence: Model confidence score (0.85 = 85% confident)

PRESENTATION TO USER:
- Lead with prediction: "Predicted CPU at [time]: [X]%"
- Include baseline: "Current baseline (24h average): CPU [Y]%, Memory [Z]%"
- Include confidence: "Confidence: [N]%"
- If current_metrics values are near 0, note potential metrics collection issues

SCOPES: cluster (default), namespace, deployment, pod`,
        },
        ceClient: ceClient,
    }
}
```

---

## Testing

### Before Enhancement

Ask Lightspeed: "What will CPU and memory be at 3 PM?"

**Current Response** (confusing):
```
CPU usage: ~23.10% (predicted). Current reported CPU: 0.0% (odd — may indicate missing metrics).
```

### After Enhancement

**Expected Response** (clear):
```
Predicted CPU at 3 PM: 23.1%
Predicted Memory at 3 PM: 24.3%
Current baseline (24h average): CPU 3.7%, Memory 29.2%
Confidence: 85%

The prediction shows normal resource levels. No immediate action needed.
```

---

## Acceptance Criteria

- [x] `predict-resource-usage` description updated with response interpretation guide
- [x] `analyze-anomalies` description updated with presentation guidelines
- [x] `calculate-pod-capacity` description updated with default assumptions
- [x] Tool descriptions include field-by-field interpretation
- [x] Lightspeed presents predictions vs. current baselines clearly
- [x] No more "0.0% (odd)" warnings when data is valid (after coordination engine fix)

---

## Related Issues

- `coordination-engine-prometheus-metrics-normalization.md` - Fixed baseline metrics queries
- `mcp-server-tool-default-behavior.md` - Default parameter handling

## References

- [MCP Tool Description Best Practices](https://modelcontextprotocol.io/docs/concepts/tools#best-practices)
- [OpenShift Lightspeed Integration](https://docs.openshift.com/container-platform/4.18/lightspeed/)
