# KServe Model Integration Quickstart

## Overview

The OpenShift Coordination Engine provides a proxy to KServe InferenceServices, enabling notebooks to call ML models through a central orchestrator.

```
Notebooks → Coordination Engine → KServe InferenceServices
            /api/v1/detect        (user-deployed models)
```

**Reference:** [ADR-039](./adrs/039-user-deployed-kserve-models.md), [ADR-040](./adrs/040-extensible-kserve-model-registry.md), [GitHub Issue #18](https://github.com/tosin2013/openshift-coordination-engine/issues/18)

---

## Quick Start

### 1. Import the Client

```python
from utils.coordination_engine_client import get_client

client = get_client()
```

### 2. List Available Models

```python
models = client.list_models()
print(models)  # ['anomaly-detector', 'predictive-analytics']
```

### 3. Make Predictions

```python
result = client.detect_anomaly(
    model_name="anomaly-detector",
    instances=[[0.5, 1.2, 0.8], [0.3, 0.9, 1.1]]
)

print(result.predictions)      # [-1, 1] → anomaly, normal
print(result.has_anomalies())  # True
print(result.anomaly_rate())   # 0.5
```

### 4. Check Model Health

```python
health = client.check_model_health("anomaly-detector")
print(health.status)  # "ready"
print(health.is_healthy())  # True
```

---

## API Reference

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/detect` | Call KServe model for predictions |
| GET | `/api/v1/models` | List all registered models |
| GET | `/api/v1/models/{model}/health` | Check model health |

### Request Format (POST /api/v1/detect)

```json
{
  "model": "anomaly-detector",
  "instances": [[0.5, 1.2, 0.8], [0.3, 0.9, 1.1]]
}
```

### Response Format

```json
{
  "predictions": [-1, 1],
  "model_name": "anomaly-detector",
  "model_version": "v1"
}
```

**Prediction Values:**
- `-1` = Anomaly detected
- `1` = Normal

---

## Adding Custom Models

### Step 1: Deploy KServe InferenceService

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: disk-failure-predictor
  namespace: self-healing-platform
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: "pvc://model-storage-pvc/disk-failure-predictor"
```

### Step 2: Register in values-hub.yaml

```yaml
coordinationEngine:
  kserve:
    enabled: true
    namespace: self-healing-platform
    services:
      anomaly_detector: "anomaly-detector-predictor"
      predictive_analytics: "predictive-analytics-predictor"
      # ADD YOUR CUSTOM MODEL:
      disk_failure_predictor: "disk-failure-predictor-predictor"
```

### Step 3: Use from Notebook

```python
result = client.detect_anomaly(
    model_name="disk-failure-predictor",
    instances=[[85.5, 5000, 365]]
)
```

**No code changes required!** The coordination engine automatically discovers models from environment variables.

---

## Environment Variables

The coordination engine reads model configuration from environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `ENABLE_KSERVE_INTEGRATION` | Enable KServe proxy | `true` |
| `KSERVE_NAMESPACE` | Namespace for KServe services | `self-healing-platform` |
| `KSERVE_<MODEL>_SERVICE` | KServe service name | `anomaly-detector-predictor` |

**Pattern:** `KSERVE_<MODEL_NAME>_SERVICE` → `model-name` in API

Examples:
- `KSERVE_ANOMALY_DETECTOR_SERVICE=anomaly-detector-predictor` → model: `anomaly-detector`
- `KSERVE_DISK_FAILURE_PREDICTOR_SERVICE=disk-failure-predictor` → model: `disk-failure-predictor`

---

## Client Configuration

```python
from utils.coordination_engine_client import CoordinationEngineClient

client = CoordinationEngineClient(
    base_url="http://coordination-engine:8080",  # Optional, auto-detected
    timeout=30,           # Request timeout in seconds
    max_retries=3,        # Retry failed requests
    verify_ssl=True       # SSL verification
)
```

### Environment Variable

Set `COORDINATION_ENGINE_URL` to override the default URL:

```bash
# In-cluster (recommended for notebooks):
export COORDINATION_ENGINE_URL=http://coordination-engine:8080

# External access via port-forward:
# oc port-forward -n self-healing-platform svc/coordination-engine 8080:8080
# export COORDINATION_ENGINE_URL=http://localhost:8080

# Cross-namespace access (if needed):
# export COORDINATION_ENGINE_URL=http://coordination-engine.self-healing-platform.svc:8080
```

### URL Patterns

The coordination engine client supports different URL patterns for different access scenarios:

| Scenario | URL Pattern | Example |
|----------|-------------|---------|
| **In-cluster** (notebooks, services) | `http://<service>:<port>` | `http://coordination-engine:8080` |
| **External** (laptop, local dev) | `http://localhost:<port>` | `http://localhost:8080` |
| **Cross-namespace** | `http://<service>.<namespace>.svc:<port>` | `http://coordination-engine.self-healing-platform.svc:8080` |

**Default**: The `coordination_engine_client.py` defaults to `http://coordination-engine:8080` for in-cluster access.

**Override**: Set `COORDINATION_ENGINE_URL` environment variable to use a different URL.

---

## Error Handling

```python
from utils.coordination_engine_client import (
    ModelNotFoundError,
    ModelUnavailableError,
    InvalidRequestError
)

try:
    result = client.detect_anomaly("model-name", instances)
except ModelNotFoundError:
    print("Model not registered")
except ModelUnavailableError:
    print("Model service is down")
except InvalidRequestError:
    print("Check request format")
```

---

## Batch Predictions

For large datasets, use batch prediction:

```python
# Process in batches of 100
result = client.batch_predict(
    model_name="anomaly-detector",
    instances=large_dataset,
    batch_size=100
)
```

---

## Wait for Model Ready

Wait for a model to become available:

```python
is_ready = client.wait_for_model_ready(
    model_name="anomaly-detector",
    timeout=300,  # 5 minutes
    interval=5    # Check every 5 seconds
)

if is_ready:
    result = client.detect_anomaly("anomaly-detector", instances)
```

---

## Onboarding Notebook

See the interactive tutorial:

```
notebooks/00-setup/01-kserve-model-onboarding.ipynb
```

---

## Related Documentation

- [ADR-039: User-Deployed KServe Models](./adrs/039-user-deployed-kserve-models.md)
- [ADR-040: Extensible KServe Model Registry](./adrs/040-extensible-kserve-model-registry.md)
- [Coordination Engine Repository](https://github.com/tosin2013/openshift-coordination-engine)
- [KServe v1 Protocol](https://kserve.github.io/website/latest/modelserving/data_plane/v1_protocol/)


