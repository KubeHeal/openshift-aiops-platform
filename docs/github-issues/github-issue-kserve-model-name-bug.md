# ✅ RESOLVED: Bug: KServe Proxy Client Uses Hardcoded "model" Name Instead of Environment Variable

**Status**: Fixed in image `sha256:bbf0319d308be56539466ae05581582b67be1bbc02e664d4e9e9649c5f73c55e`
**Fixed Date**: 2026-01-28
**Verification**: Anomaly detection endpoint now returns HTTP 200 with successful analysis

## Summary
The coordination engine's KServe proxy client (`pkg/kserve/proxy.go`) uses a hardcoded model name `"model"` in API endpoints instead of reading the `KSERVE_ANOMALY_DETECTOR_MODEL` and `KSERVE_PREDICTIVE_ANALYTICS_MODEL` environment variables. This causes 404 errors when querying models that have explicit model names configured.

## Impact
- **MCP server queries fail** with "Model with name model does not exist" errors
- **Anomaly detection endpoint** (`/api/v1/anomalies/analyze`) returns HTTP 503
- **Integration with OpenShift Lightspeed** is broken
- **End-user AI queries** cannot access anomaly detection functionality

## Environment
- **Coordination Engine Image**: `quay.io/takinosh/openshift-coordination-engine:ocp-4.18-latest`
- **Image SHA**: `sha256:00fb058e49afac8438fbba2b190d302b587ec580152ce42076f766a5e35d95ec`
- **OpenShift Version**: 4.18
- **KServe InferenceServices**: Using RawDeployment mode

## Root Cause Analysis

### Bug Location
File: `pkg/kserve/proxy.go`

**Lines 306-309** (Predict method):
```go
// Build endpoint URL - KServe v1 protocol: /v1/models/<model>:predict
// Note: KServe defaults to model name "model" when spec.predictor.model.name is not set
// We use the hardcoded "model" name for KServe API paths, while keeping the logical
// model name (e.g., "anomaly-detector") for user-facing APIs and service resolution
endpoint := fmt.Sprintf("%s/v1/models/model:predict", model.URL)
```

**Line 412** (PredictFlexible method):
```go
endpoint := fmt.Sprintf("%s/v1/models/model:predict", model.URL)
```

**Lines 690-692** (CheckModelHealth method):
```go
// KServe v1 health endpoint: GET /v1/models/<model>
// Note: KServe defaults to model name "model" when spec.predictor.model.name is not set
endpoint := fmt.Sprintf("%s/v1/models/model", model.URL)
```

### Incorrect Assumption
The code comment states:
> "KServe defaults to model name 'model' when spec.predictor.model.name is not set"

However, our InferenceServices **DO have model names configured**:
- `KSERVE_ANOMALY_DETECTOR_MODEL=anomaly-detector`
- `KSERVE_PREDICTIVE_ANALYTICS_MODEL=predictive-analytics`

The models are trained with explicit names and stored in `/mnt/models/{model-name}/model.pkl`.

### What Should Happen
The code should use the model name from the environment variable `KSERVE_{MODEL}_MODEL`, not the hardcoded string `"model"`.

### Actual vs Expected API Calls

**Current (WRONG)**:
```
http://anomaly-detector-stable:8080/v1/models/model:predict
http://anomaly-detector-stable:8080/v1/models/model
```

**Expected (CORRECT)**:
```
http://anomaly-detector-stable:8080/v1/models/anomaly-detector:predict
http://anomaly-detector-stable:8080/v1/models/anomaly-detector
```

## Reproduction Steps

1. Deploy the coordination engine with environment variables:
   ```yaml
   env:
     - name: KSERVE_ANOMALY_DETECTOR_SERVICE
       value: anomaly-detector-stable
     - name: KSERVE_ANOMALY_DETECTOR_MODEL
       value: anomaly-detector
   ```

2. Query the MCP server for anomaly detection:
   ```bash
   curl -X POST http://mcp-server:8080/mcp \
     -H "Content-Type: application/json" \
     -d '{"tool":"analyze-anomalies","arguments":{"namespace":"default"}}'
   ```

3. **Expected**: Anomaly analysis results
4. **Actual**: Error: `model anomaly-detector not found (HTTP 404): KServe InferenceService may not be deployed or model files missing. Backend response: {"error":"Model with name model does not exist."}`

## Verification

### Model is trained and loaded:
```bash
$ oc exec -n self-healing-platform anomaly-detector-predictor-xxx -- \
    curl -s http://localhost:8080/v2/models

{"models":["anomaly-detector"]}  # ✅ Model exists with correct name
```

### Direct API call works with correct name:
```bash
$ oc exec -n self-healing-platform coordination-engine-xxx -- \
    curl -s http://anomaly-detector-stable:8080/v1/models/anomaly-detector

{"name":"anomaly-detector","versions":null,"platform":"","inputs":[],"outputs":[]}  # ✅ Works!
```

### But fails with hardcoded "model":
```bash
$ oc exec -n self-healing-platform coordination-engine-xxx -- \
    curl -s http://anomaly-detector-stable:8080/v1/models/model

{"error":"Model with name model does not exist."}  # ❌ Fails!
```

## Solution

### Option 1: Read Model Name from Environment (Recommended)
Add a field to `ModelInfo` struct to store the KServe model name:

```go
type ModelInfo struct {
    Name        string `json:"name"`         // Logical name (e.g., "anomaly-detector")
    ServiceName string `json:"service_name"` // Service DNS (e.g., "anomaly-detector-stable")
    ModelName   string `json:"model_name"`   // KServe model name (e.g., "anomaly-detector")
    Namespace   string `json:"namespace"`
    URL         string `json:"url"`
}
```

Update `loadModelsFromEnv()` to read `KSERVE_{MODEL}_MODEL`:

```go
func (c *ProxyClient) loadModelsFromEnv() {
    // ... existing code ...

    // After finding serviceName from KSERVE_ANOMALY_DETECTOR_SERVICE
    // Look for KSERVE_ANOMALY_DETECTOR_MODEL
    modelEnvKey := strings.TrimSuffix(envKey, "_SERVICE") + "_MODEL"
    kserveModelName := os.Getenv(modelEnvKey)
    if kserveModelName == "" {
        // Fallback to logical model name if MODEL env var not set
        kserveModelName = modelName
    }

    c.models[modelName] = &ModelInfo{
        Name:        modelName,
        ServiceName: serviceName,
        ModelName:   kserveModelName,  // ← Use this in API calls
        Namespace:   c.namespace,
        URL:         url,
    }
}
```

Update API endpoint construction:

```go
// Lines 309, 412
endpoint := fmt.Sprintf("%s/v1/models/%s:predict", model.URL, model.ModelName)

// Line 692
endpoint := fmt.Sprintf("%s/v1/models/%s", model.URL, model.ModelName)
```

### Option 2: Use Logical Model Name as Fallback
If the model name should match the logical name, simply use `modelName` instead of hardcoded `"model"`:

```go
endpoint := fmt.Sprintf("%s/v1/models/%s:predict", model.URL, modelName)
```

## Configuration Reference

Current environment variables in deployment:
```yaml
- name: KSERVE_NAMESPACE
  value: self-healing-platform
- name: KSERVE_PREDICTOR_PORT
  value: "8080"
- name: KSERVE_ANOMALY_DETECTOR_SERVICE
  value: anomaly-detector-stable
- name: KSERVE_ANOMALY_DETECTOR_MODEL  # ← Currently IGNORED by code
  value: anomaly-detector
- name: KSERVE_PREDICTIVE_ANALYTICS_SERVICE
  value: predictive-analytics-stable
- name: KSERVE_PREDICTIVE_ANALYTICS_MODEL  # ← Currently IGNORED by code
  value: predictive-analytics
- name: KSERVE_TIMEOUT
  value: "10s"
```

## Error Logs

### Coordination Engine Logs:
```json
{
  "level": "error",
  "model": "anomaly-detector",
  "msg": "KServe anomaly detection failed",
  "error": "model anomaly-detector not found (HTTP 404): KServe InferenceService may not be deployed or model files missing. Backend response: {\"error\":\"Model with name model does not exist.\"}",
  "time": "2026-01-28T02:20:35Z"
}
```

### MCP Server Logs:
```json
{
  "event": "tool_result",
  "tool_id": "call_RgUBFMtICLzyZNBdgZp9aPnY",
  "status": "error",
  "output_snippet": "Error executing tool 'analyze-anomalies': failed to get anomaly predictions: unexpected status code 503"
}
```

## Testing After Fix

1. Verify model name is read from environment:
   ```bash
   oc logs coordination-engine-xxx | grep "Registered KServe model"
   # Should show: model_name=anomaly-detector
   ```

2. Test MCP server query:
   ```bash
   # Should return anomaly analysis without errors
   curl -X POST http://mcp-server:8080/mcp -d '{"tool":"analyze-anomalies"}'
   ```

3. Test coordination engine directly:
   ```bash
   oc exec coordination-engine-xxx -- \
     curl -X POST http://localhost:8080/api/v1/anomalies/analyze \
     -d '{"model":"anomaly-detector","namespace":"default","time_range":"1h"}'
   # Should return HTTP 200 with anomaly analysis
   ```

## Related Files
- `pkg/kserve/proxy.go` (lines 309, 412, 692)
- `pkg/config/config.go` (environment variable loading)
- `charts/hub/templates/coordination-engine-deployment.yaml` (env vars definition)
- `charts/hub/values.yaml` (default values for model names)

## References
- KServe v1 Protocol: https://kserve.github.io/website/latest/modelserving/data_plane/v1_protocol/
- ADR-039: KServe Integration
- ADR-040: Dynamic Model Discovery

## Priority
**High** - This blocks all AI-powered anomaly detection queries through the MCP server and OpenShift Lightspeed integration.

## Labels
- `bug`
- `kserve`
- `coordination-engine`
- `mcp-integration`
- `high-priority`

---

## ✅ RESOLUTION VERIFICATION (2026-01-28)

### Fix Applied
The developers created a new image with the fix implemented. The coordination engine now correctly uses the model name from the `KSERVE_{MODEL}_MODEL` environment variable instead of the hardcoded `"model"` string.

### New Image Details
```
Image: quay.io/takinosh/openshift-coordination-engine:ocp-4.18-latest
SHA: sha256:bbf0319d308be56539466ae05581582b67be1bbc02e664d4e9e9649c5f73c55e
Pull Date: 2026-01-28T02:52:02Z
```

### Verification Steps Performed

1. **Pod Restart with New Image**:
   ```bash
   oc delete pod -l app.kubernetes.io/component=coordination-engine -n self-healing-platform
   # imagePullPolicy: Always ensured latest image was pulled
   ```

2. **Logs Verification**:
   ```json
   {"level":"info","model":"anomaly-detector","msg":"KServe model is healthy and ready"}
   ```
   ✅ No more "Model with name model does not exist" errors

3. **API Endpoint Test**:
   ```bash
   curl -X POST http://localhost:8080/api/v1/anomalies/analyze \
     -d '{"model":"anomaly-detector","namespace":"self-healing-platform","time_range":"1h"}'
   ```

   **Result**: ✅ HTTP 200 Success
   ```json
   {
     "status": "success",
     "model_used": "anomaly-detector",
     "anomalies_detected": 0,
     "summary": {
       "metrics_analyzed": 5,
       "features_generated": 45
     }
   }
   ```

4. **MCP Server Integration**:
   - ✅ MCP server can now successfully query anomaly detection
   - ✅ OpenShift Lightspeed integration functional
   - ✅ End-user AI queries for anomaly analysis working

### Before vs After

| Metric | Before Fix | After Fix |
|--------|-----------|-----------|
| HTTP Status | 503 Service Unavailable | 200 OK |
| Error Message | "Model with name model does not exist" | None |
| API Call | `/v1/models/model` | `/v1/models/anomaly-detector` |
| MCP Integration | ❌ Broken | ✅ Working |
| Anomaly Analysis | ❌ Failed | ✅ Successful |

### Logs Comparison

**Before Fix**:
```json
{
  "level": "error",
  "model": "anomaly-detector",
  "error": "model anomaly-detector not found (HTTP 404): Backend response: {\"error\":\"Model with name model does not exist.\"}"
}
```

**After Fix**:
```json
{
  "level": "info",
  "model": "anomaly-detector",
  "msg": "Anomaly analysis completed successfully",
  "anomalies_detected": 0,
  "status": 200
}
```

### Issue Status
**CLOSED** - Fix verified and working in production

### Credits
- Issue identified and documented by: Claude Code AI Analysis
- Fix implemented by: Development Team
- Verified by: Integration Testing
