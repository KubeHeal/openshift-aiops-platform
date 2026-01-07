# User Model Deployment Guide

## Overview

The Self-Healing Platform follows a **user-deployed model architecture** where **you are responsible** for training and deploying your own ML models via KServe. The platform provides the coordination engine and infrastructure, while you maintain full control over your models.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  YOUR RESPONSIBILITY: Model Training & Deployment       │
│                                                          │
│  1. Train models in notebooks (OpenShift AI workbench)  │
│  2. Deploy models via KServe InferenceServices          │
│  3. Maintain model versions and updates                 │
└─────────────────────────────────────────────────────────┘
                           ▲
                           │ Calls your models via KServe API
                           │
┌─────────────────────────────────────────────────────────┐
│  PLATFORM RESPONSIBILITY: Coordination & Infrastructure │
│                                                          │
│  - Go Coordination Engine (anomaly processing)          │
│  - KServe Infrastructure (model serving)                │
│  - Monitoring & Observability (Prometheus/Grafana)      │
└─────────────────────────────────────────────────────────┘
```

## Platform Compatibility

| Platform | KServe Support | Installation Method |
|----------|----------------|---------------------|
| **OpenShift** | ✅ Native | Via OpenShift AI / Red Hat OpenShift Serverless |
| **Vanilla Kubernetes** | ✅ Supported | Install Knative Serving + KServe Operator |
| **ACM Spoke Clusters** | ✅ Supported | Deploy via ApplicationSet (see ADR-022) |

## Prerequisites

### OpenShift
- OpenShift 4.18+ cluster
- OpenShift AI operator installed
- OpenShift Serverless operator installed
- Storage class for PVC (e.g., `gp3-csi`, `ocs-storagecluster-ceph-rbd`)

### Vanilla Kubernetes
- Kubernetes 1.28+
- Knative Serving installed ([install guide](https://knative.dev/docs/install/))
- KServe operator installed ([install guide](https://kserve.github.io/website/latest/admin/serverless/))
- Storage class for PVC

## Model API Contract

Your deployed models MUST implement the KServe v1 prediction API for coordination engine integration:

### Required Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/v1/models/<model>` | GET | Model metadata |
| `/v1/models/<model>:predict` | POST | Inference |
| `/v1/models` | GET | List available models |

### Request Format

```json
POST /v1/models/anomaly-detector:predict
Content-Type: application/json

{
  "instances": [
    [0.5, 1.2, 0.8],  // Feature vector
    [0.3, 0.9, 1.1]
  ]
}
```

### Response Format

```json
{
  "predictions": [
    -1,  // -1 = anomaly, 1 = normal
    1
  ],
  "model_name": "anomaly-detector",
  "model_version": "v2"
}
```

### Coordination Engine Integration

The coordination engine will call your models at these service endpoints:
- **Anomaly Detector**: `http://anomaly-detector-predictor.self-healing-platform.svc.cluster.local/v1/models/anomaly-detector:predict`
- **Predictive Analytics**: `http://predictive-analytics-predictor.self-healing-platform.svc.cluster.local/v1/models/predictive-analytics:predict`

## Deployment Workflow

### Step 1: Train Your Model

Use OpenShift AI workbenches or local notebooks to train your model:

```python
# Example: Train anomaly detection model
from sklearn.ensemble import IsolationForest
import joblib

# Train model
model = IsolationForest(n_estimators=100, contamination=0.1, random_state=42)
model.fit(training_data)

# Save to PVC
joblib.dump(model, '/opt/app-root/src/models/anomaly-detector/v2/model.pkl')
```

**Reference**: See `notebooks/02-anomaly-detection/` for complete training examples.

### Step 2: Prepare Model Storage

#### Option A: PVC Storage (Recommended for OpenShift)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-storage-pvc
  namespace: self-healing-platform
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: gp3-csi  # Adjust for your platform
```

**Directory Structure**:
```
/models/
├── anomaly-detector/
│   ├── v1/
│   │   └── model.pkl
│   ├── v2/
│   │   └── model.pkl
│   └── metadata.json
└── predictive-analytics/
    ├── v1/
    │   └── model.pkl
    └── metadata.json
```

#### Option B: S3 Storage (Cloud-Native)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: model-storage-config
  namespace: self-healing-platform
stringData:
  AWS_ACCESS_KEY_ID: "your-access-key"
  AWS_SECRET_ACCESS_KEY: "your-secret-key"
  AWS_S3_ENDPOINT: "https://s3.amazonaws.com"
  AWS_DEFAULT_REGION: "us-east-1"
```

### Step 3: Deploy InferenceService

#### OpenShift Example (PVC-based)

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
      runtime: sklearn-pvc-runtime  # Use PVC-compatible runtime
      storageUri: "pvc://model-storage-pvc/anomaly-detector/v2"
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
```

#### Vanilla Kubernetes Example (S3-based)

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
      storageUri: "s3://my-bucket/models/anomaly-detector/v2"
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
```

### Step 4: Verify Deployment

```bash
# Check InferenceService status
kubectl get inferenceservice anomaly-detector -n self-healing-platform

# Expected output:
# NAME                URL                                           READY   PREV   LATEST   AGE
# anomaly-detector    http://anomaly-detector.example.com           True    100                 2m

# Test inference endpoint
kubectl run -it --rm test-client --image=curlimages/curl --restart=Never -- \
  curl -X POST http://anomaly-detector-predictor.self-healing-platform.svc.cluster.local/v1/models/anomaly-detector:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[0.5, 1.2, 0.8]]}'

# Expected response:
# {"predictions": [-1], "model_name": "anomaly-detector"}
```

## Model Versioning & Updates

### Canary Deployment (Zero Downtime)

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: anomaly-detector
spec:
  predictor:
    canaryTrafficPercent: 10  # Send 10% traffic to new version
    model:
      modelFormat: {name: sklearn}
      storageUri: "pvc://model-storage-pvc/anomaly-detector/v3"  # New version
```

### Progressive Rollout

```bash
# Stage 1: Deploy v3 with 10% traffic
kubectl patch inferenceservice anomaly-detector --type merge \
  -p '{"spec":{"predictor":{"canaryTrafficPercent":10}}}'

# Stage 2: Monitor for 1 hour, check metrics

# Stage 3: Increase to 50%
kubectl patch inferenceservice anomaly-detector --type merge \
  -p '{"spec":{"predictor":{"canaryTrafficPercent":50}}}'

# Stage 4: Full rollout (100%)
kubectl patch inferenceservice anomaly-detector --type merge \
  -p '{"spec":{"predictor":{"canaryTrafficPercent":100}}}'
```

### Instant Rollback

```bash
# Rollback to previous version
kubectl patch inferenceservice anomaly-detector --type merge \
  -p '{"spec":{"predictor":{"model":{"storageUri":"pvc://model-storage-pvc/anomaly-detector/v2"}}}}'
```

## Model Monitoring

### Health Checks

```bash
# Check model health
kubectl exec -it deployment/coordination-engine -n self-healing-platform -- \
  curl http://anomaly-detector-predictor:80/v1/models/anomaly-detector

# Expected output:
# {
#   "name": "anomaly-detector",
#   "version": "v2",
#   "ready": true
# }
```

### Prometheus Metrics

KServe automatically exposes metrics at `/metrics`:

```promql
# Inference request rate
rate(kserve_inference_requests_total{model="anomaly-detector"}[5m])

# Inference latency (95th percentile)
histogram_quantile(0.95, rate(kserve_inference_latency_bucket[5m]))

# Error rate
rate(kserve_inference_errors_total{model="anomaly-detector"}[5m])
```

## Troubleshooting

### InferenceService Not Ready

```bash
# Check pod status
kubectl get pods -n self-healing-platform -l serving.kserve.io/inferenceservice=anomaly-detector

# Check pod logs
kubectl logs -n self-healing-platform <predictor-pod-name>

# Common issues:
# 1. Model file not found in storage
# 2. Insufficient resources (CPU/memory)
# 3. Storage credentials incorrect (S3)
# 4. Model format mismatch (sklearn vs pytorch)
```

### Predictions Failing

```bash
# Test prediction directly
kubectl run -it --rm test-client --image=curlimages/curl --restart=Never -- \
  curl -v -X POST http://anomaly-detector-predictor.self-healing-platform.svc.cluster.local/v1/models/anomaly-detector:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[0.5, 1.2, 0.8]]}'

# Check response code and error message
```

### Coordination Engine Not Calling Models

```bash
# Check coordination engine logs
kubectl logs -n self-healing-platform deployment/coordination-engine

# Verify KSERVE environment variables
kubectl exec -it deployment/coordination-engine -n self-healing-platform -- env | grep KSERVE

# Expected:
# ENABLE_KSERVE_INTEGRATION=true
# KSERVE_NAMESPACE=self-healing-platform
# KSERVE_ANOMALY_DETECTOR_SERVICE=anomaly-detector-predictor
# KSERVE_PREDICTIVE_ANALYTICS_SERVICE=predictive-analytics-predictor
```

## Example: Complete Deployment

See the complete notebook example: [`notebooks/04-model-serving/kserve-model-deployment.ipynb`](../../notebooks/04-model-serving/kserve-model-deployment.ipynb)

This notebook demonstrates:
1. ✅ Training a model in OpenShift AI workbench
2. ✅ Saving model to PVC
3. ✅ Creating InferenceService via Python
4. ✅ Testing the deployed model
5. ✅ Integration with coordination engine

## Related Documentation

- **ADR-004**: [KServe for Model Serving Infrastructure](../adrs/004-kserve-model-serving.md)
- **ADR-037**: [MLOps Workflow for Model Training, Versioning, and Deployment](../adrs/037-mlops-workflow-strategy.md)
- **ADR-039**: [User-Deployed KServe Models](../adrs/039-user-deployed-kserve-models.md)
- **Notebook Reference**: [Notebook Quick Reference](../NOTEBOOK-QUICK-REFERENCE.md)

## Support

For issues or questions:
1. Check [Troubleshooting Guide](../guides/TROUBLESHOOTING-GUIDE.md)
2. Review [KServe Documentation](https://kserve.github.io/website/)
3. Open an issue on [GitHub](https://github.com/tosin2013/openshift-aiops-platform/issues)
