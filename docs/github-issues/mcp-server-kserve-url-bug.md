# Bug: KServe client uses wrong URL pattern - model name instead of literal "model"

## Repository
`https://github.com/tosin2013/openshift-cluster-health-mcp`

## Labels
`bug`, `kserve`, `critical`

## Summary

The KServe client in the MCP server builds incorrect URLs for model endpoints. It uses the model name (e.g., `anomaly-detector`) in the URL path instead of the literal string `model`.

## Error Observed

```
Error executing tool 'analyze-anomalies': failed to get anomaly predictions: 
prediction failed (code 404): {"error":"Model with name anomaly-detector does not exist."}
```

## Root Cause

**File:** `pkg/clients/kserve.go`

The URL construction uses `modelName` variable instead of literal `"model"`:

### Bug Location 1: Line 217-218 (v2 protocol)
```go
// WRONG:
return fmt.Sprintf("http://%s-predictor.%s.svc.cluster.local:%d/v2/models/%s/%s",
    modelName, c.namespace, c.predictorPort, modelName, operation)
// Produces: /v2/models/anomaly-detector/infer ❌
```

### Bug Location 2: Line 462-463 (health check)
```go
// WRONG:
url := fmt.Sprintf("http://%s-predictor.%s.svc.cluster.local:%d/v2/models/%s",
    modelName, c.namespace, c.predictorPort, modelName)
// Produces: /v2/models/anomaly-detector ❌
```

### Bug Location 3: Line 510-511 (model status)
```go
// WRONG:
url := fmt.Sprintf("http://%s-predictor.%s.svc.cluster.local:%d/v2/models/%s",
    modelName, c.namespace, c.predictorPort, modelName)
// Produces: /v2/models/anomaly-detector ❌
```

### Bug Location 4: Line 573-574 (v1 prediction)
```go
// WRONG:
url := fmt.Sprintf("http://%s-predictor.%s.svc.cluster.local:%d/v1/models/%s:predict",
    modelName, c.namespace, c.predictorPort, modelName)
// Produces: /v1/models/anomaly-detector:predict ❌
```

## Proof of Bug

Tested from utilities pod in the cluster:

```bash
# WRONG URL (what MCP server uses):
$ curl http://anomaly-detector-predictor:8080/v1/models/anomaly-detector
{"error":"Model with name anomaly-detector does not exist."}

# CORRECT URL (what it should use):
$ curl http://anomaly-detector-predictor:8080/v1/models/model
{"name":"model","ready":true}
```

## Proposed Fix

Change all occurrences to use literal `"model"` instead of `modelName` in the URL path:

### Fix 1: getModelURL function (line 217-218)
```go
// FIXED:
return fmt.Sprintf("http://%s-predictor.%s.svc.cluster.local:%d/v2/models/model/%s",
    modelName, c.namespace, c.predictorPort, operation)
// Produces: /v2/models/model/infer ✅
```

### Fix 2: HealthCheck function (line 462-463)
```go
// FIXED:
url := fmt.Sprintf("http://%s-predictor.%s.svc.cluster.local:%d/v2/models/model",
    modelName, c.namespace, c.predictorPort)
// Produces: /v2/models/model ✅
```

### Fix 3: GetModelStatus function (line 510-511)
```go
// FIXED:
url := fmt.Sprintf("http://%s-predictor.%s.svc.cluster.local:%d/v2/models/model",
    modelName, c.namespace, c.predictorPort)
// Produces: /v2/models/model ✅
```

### Fix 4: Predict function (line 573-574)
```go
// FIXED:
url := fmt.Sprintf("http://%s-predictor.%s.svc.cluster.local:%d/v1/models/model:predict",
    modelName, c.namespace, c.predictorPort)
// Produces: /v1/models/model:predict ✅
```

## Why This Happens

KServe InferenceServices deployed with RawDeployment mode use a generic model name `model` in the URL path, regardless of the InferenceService name. The service name (`anomaly-detector-predictor`) is used for DNS routing, but the model path is always `/v1/models/model` or `/v2/models/model`.

## Impact

- **Severity:** Critical
- **Affected Tools:** `analyze-anomalies`, `predict-resource-usage`, `get-model-status`
- **User Impact:** All ML-powered features fail with 404 errors

## Testing After Fix

```bash
# Test v1 prediction
curl -X POST http://anomaly-detector-predictor:8080/v1/models/model:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[0.5, 1.2, 0.8]]}'

# Test v2 model status
curl http://anomaly-detector-predictor:8080/v2/models/model
```
