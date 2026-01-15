# Bug: Cannot parse predictive-analytics model response - type mismatch for predictions field

## Labels
`bug`, `api`, `ml-integration`, `prediction`

## Bug Description

The coordination engine fails to parse responses from the `predictive-analytics` KServe model when called via the MCP `predict-resource-usage` tool.

**Error Message:**
```
failed to decode response from model predictive-analytics: json: cannot unmarshal array into Go struct field .predictions of type int
```

**HTTP Response Code:** 503

## Root Cause

The prediction response struct in the coordination engine expects `.predictions` to be `int`, but the `predictive-analytics` model returns a nested dictionary structure.

### Current Model Response Formats

**Anomaly-detector** returns (currently handled correctly):
```json
{
  "predictions": [-1, 1],
  "model_name": "anomaly-detector",
  "model_version": "1.0.0"
}
```

**Predictive-analytics** returns (NOT handled - causes the bug):
```json
{
  "predictions": {
    "cpu_usage": {
      "forecast": [0.5, 0.6, 0.7],
      "forecast_horizon": 12,
      "confidence": [0.9, 0.88, 0.85]
    },
    "memory_usage": {
      "forecast": [0.7, 0.8, 0.75],
      "forecast_horizon": 12,
      "confidence": [0.85, 0.82, 0.80]
    }
  },
  "model_name": "predictive-analytics",
  "model_version": "1.0.0",
  "timestamp": "2026-01-14T15:00:00Z",
  "lookback_window": 24
}
```

### Code References

The model response format is defined in:
- `src/models/predictive_analytics.py` - `predict()` method (lines 214-267)
- `src/models/model_server.py` - `/v1/models/:predict` endpoint (lines 96-108)

## Suggested Fix

In the coordination engine Go code (likely `pkg/handlers/prediction.go` or `pkg/kserve/client.go`), update the response struct to handle different model response formats:

### Option 1: Use interface{} for flexibility

```go
type ModelResponse struct {
    Predictions  interface{} `json:"predictions"`
    ModelName    string      `json:"model_name"`
    ModelVersion string      `json:"model_version,omitempty"`
    Timestamp    string      `json:"timestamp,omitempty"`
}
```

### Option 2: Create model-specific response types

```go
// For anomaly-detector
type AnomalyResponse struct {
    Predictions  []int  `json:"predictions"`
    ModelName    string `json:"model_name"`
    ModelVersion string `json:"model_version,omitempty"`
}

// For predictive-analytics
type ForecastResponse struct {
    Predictions  map[string]ForecastResult `json:"predictions"`
    ModelName    string                    `json:"model_name"`
    ModelVersion string                    `json:"model_version,omitempty"`
    Timestamp    string                    `json:"timestamp,omitempty"`
    LookbackWindow int                     `json:"lookback_window,omitempty"`
}

type ForecastResult struct {
    Forecast        []float64 `json:"forecast"`
    ForecastHorizon int       `json:"forecast_horizon"`
    Confidence      []float64 `json:"confidence"`
}
```

### Option 3: Type switch based on model name

```go
func parseModelResponse(modelName string, body []byte) (interface{}, error) {
    switch modelName {
    case "anomaly-detector":
        var resp AnomalyResponse
        err := json.Unmarshal(body, &resp)
        return resp, err
    case "predictive-analytics":
        var resp ForecastResponse
        err := json.Unmarshal(body, &resp)
        return resp, err
    default:
        var resp map[string]interface{}
        err := json.Unmarshal(body, &resp)
        return resp, err
    }
}
```

## Reproduction Steps

1. Ensure OpenShift cluster has `predictive-analytics` model deployed via KServe
2. Access OpenShift Lightspeed chat
3. Ask: "What will the CPU and memory usage be at 3 PM today?"
4. MCP server calls `predict-resource-usage` tool with `metric=both, scope=cluster`
5. Observe 503 error with JSON unmarshal failure

## Expected Behavior

The coordination engine should successfully parse the `predictive-analytics` response and return a formatted prediction with CPU and memory forecasts.

## Actual Behavior

503 Service Unavailable with error:
```json
{
  "status": "error",
  "error": "Prediction failed",
  "details": "failed to decode response from model predictive-analytics: json: cannot unmarshal array into Go struct field .predictions of type int",
  "code": "PREDICTION_FAILED"
}
```

## Environment

- **OpenShift Version:** 4.18.21
- **Coordination Engine:** current
- **KServe Model:** `predictive-analytics`
- **MCP Server:** `openshift-cluster-health-mcp`

## Impact

- **Severity:** High
- **Component:** Coordination Engine → KServe Proxy
- **User Impact:** Users cannot get resource usage predictions via Lightspeed

## Related

- MCP tool: `predict-resource-usage`
- ADR-039: User-Deployed KServe Models
- ADR-040: Extensible KServe Model Registry
