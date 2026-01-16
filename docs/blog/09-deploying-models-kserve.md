# Deploying ML Models with KServe on OpenShift

*Part 9 of the OpenShift AI Ops Learning Series*

---

## Introduction

Training models is only half the battle. Deploying them to production with auto-scaling, canary deployments, and traffic management is where KServe shines. This guide covers deploying anomaly detection models to KServe, managing versions, and building inference pipelines.

---

## What You'll Learn

- KServe InferenceService deep dive
- Canary deployments for models
- A/B testing anomaly detectors
- Model versioning and rollback
- Building inference pipelines

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 3: Isolation Forest](03-isolation-forest-anomaly-detection.md)
- [ ] KServe installed on cluster
- [ ] Trained models saved to persistent storage
- [ ] Model storage PVC mounted

---

## Understanding KServe

### What is KServe?

KServe provides:
- ✅ **Standardized API**: `/v1/models/model:predict` for all models
- ✅ **Auto-scaling**: Scales based on request volume
- ✅ **Canary deployments**: Gradual traffic shifting
- ✅ **Multi-framework**: sklearn, PyTorch, TensorFlow, XGBoost
- ✅ **Traffic splitting**: A/B test model versions

### InferenceService Resource

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: anomaly-detector
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: pvc://model-storage-pvc/anomaly-detector
```

---

## Step 1: Package Models for KServe

### Open the KServe Deployment Notebook

1. Navigate to `notebooks/04-model-serving/`
2. Open `kserve-model-deployment.ipynb`

### Verify Model Format

```python
import joblib

# Load model
model = joblib.load('/opt/app-root/src/models/anomaly-detector/model.pkl')

# Verify it's KServe-compatible (sklearn Pipeline)
from sklearn.pipeline import Pipeline
assert isinstance(model, Pipeline), "Model must be sklearn Pipeline"

print("✅ Model is KServe-compatible")
```

### Save to PVC

```python
import shutil

# Copy model to PVC mount
pvc_path = '/mnt/models/anomaly-detector'
os.makedirs(pvc_path, exist_ok=True)

# Save model
joblib.dump(model, f'{pvc_path}/model.pkl')

# Save metadata
metadata = {
    'model_name': 'anomaly-detector',
    'version': '1.0.0',
    'framework': 'sklearn',
    'created_at': datetime.now().isoformat()
}

import json
with open(f'{pvc_path}/metadata.json', 'w') as f:
    json.dump(metadata, f, indent=2)

print(f"✅ Model saved to PVC: {pvc_path}")
```

---

## Step 2: Create InferenceService

### Basic InferenceService

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: anomaly-detector
  namespace: self-healing-platform
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: pvc://model-storage-pvc/anomaly-detector
      runtime: sklearn-pvc-runtime
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "2"
          memory: "2Gi"
```

### Apply InferenceService

```python
import yaml
import subprocess

# Create InferenceService YAML
inferenceservice_yaml = """
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: anomaly-detector
  namespace: self-healing-platform
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: pvc://model-storage-pvc/anomaly-detector
      runtime: sklearn-pvc-runtime
"""

# Apply to cluster
subprocess.run(['oc', 'apply', '-f', '-'],
               input=inferenceservice_yaml.encode(),
               check=True)

print("✅ InferenceService created")
```

---

## Step 3: Test Model Endpoint

### Wait for Ready

```python
import time

def wait_for_ready(name, namespace, timeout=300):
    """Wait for InferenceService to be ready"""
    import subprocess

    start_time = time.time()
    while time.time() - start_time < timeout:
        result = subprocess.run(
            ['oc', 'get', 'inferenceservice', name, '-n', namespace, '-o', 'json'],
            capture_output=True, text=True
        )

        if result.returncode == 0:
            import json
            data = json.loads(result.stdout)
            if data.get('status', {}).get('conditions', [{}])[-1].get('status') == 'True':
                print(f"✅ {name} is ready")
                return True

        time.sleep(5)

    return False

wait_for_ready('anomaly-detector', 'self-healing-platform')
```

### Test Prediction

```python
import requests

# Get service URL
service_url = 'http://anomaly-detector-predictor.self-healing-platform.svc.cluster.local:8080'

# Test prediction
response = requests.post(
    f'{service_url}/v1/models/model:predict',
    json={
        'instances': [[0.95, 0.88, 5]]  # High CPU, high memory, restarts
    }
)

print(f"Response: {response.json()}")
# Expected: {"predictions": [[-1]]}  # -1 = anomaly
```

---

## Step 4: Canary Deployment

### Deploy New Version

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: anomaly-detector-v2
  namespace: self-healing-platform
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: pvc://model-storage-pvc/anomaly-detector-v2
      runtime: sklearn-pvc-runtime
```

### Traffic Splitting

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: TrafficSplit
metadata:
  name: anomaly-detector-split
  namespace: self-healing-platform
spec:
  traffic:
  - service: anomaly-detector
    percent: 90  # 90% to v1
  - service: anomaly-detector-v2
    percent: 10  # 10% to v2
```

---

## Step 5: Model Versioning

### Version Management

```python
def deploy_model_version(model_name, version, model_path):
    """
    Deploy new model version.

    Args:
        model_name: Model name
        version: Version string (e.g., '1.1.0')
        model_path: Path to model file
    """
    # Create versioned InferenceService
    isvc_name = f"{model_name}-v{version.replace('.', '-')}"

    # Copy model to versioned path
    versioned_path = f'/mnt/models/{model_name}/v{version}'
    os.makedirs(versioned_path, exist_ok=True)
    shutil.copy(model_path, f'{versioned_path}/model.pkl')

    # Create InferenceService
    # ... (YAML creation and apply)

    print(f"✅ Deployed {model_name} version {version}")
```

---

## What Just Happened?

You've deployed models to production:

### 1. Model Packaging

- **Format validation**: Ensure KServe compatibility
- **PVC storage**: Persistent model storage
- **Metadata**: Version and framework info

### 2. InferenceService

- **Standardized API**: `/v1/models/model:predict`
- **Resource limits**: CPU and memory constraints
- **Auto-scaling**: Handles traffic spikes

### 3. Canary Deployment

- **Traffic splitting**: Gradual rollout
- **A/B testing**: Compare model versions
- **Rollback**: Revert if issues detected

### 4. Versioning

- **Multiple versions**: Run simultaneously
- **Traffic control**: Route to specific versions
- **Rollback**: Switch traffic back

---

## Next Steps

Explore advanced topics:

1. **Monitoring**: [Blog 13: Monitoring the Platform](13-monitoring-self-healing-platform.md)
2. **Predictive Scaling**: [Blog 14: Predictive Scaling](14-predictive-scaling-cost-optimization.md)
3. **Security**: [Blog 15: Security Automation](15-security-incident-automation.md)

---

## Related Resources

- **Notebook**: `notebooks/04-model-serving/kserve-model-deployment.ipynb`
- **ADRs**:
  - [ADR-004: KServe for Model Serving](docs/adrs/004-kserve-model-serving.md)
- **KServe Docs**: [InferenceService](https://kserve.github.io/website/modelserving/inferenceservice/)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/tosin2013/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/09-deploying-models-kserve.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 9 of 15 in the OpenShift AI Ops Learning Series*
