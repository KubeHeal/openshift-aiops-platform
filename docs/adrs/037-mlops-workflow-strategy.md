# ADR-037: MLOps Workflow for Model Training, Versioning, and Deployment

**Status:** ACCEPTED
**Date:** 2025-12-10
**Decision Makers:** Architecture Team, ML Engineering Team
**Consulted:** DevOps Team, Operations Team
**Informed:** Development Team, Security Team

## Context

**ADR-008 (Kubeflow Pipelines for MLOps Automation) was deprecated** on 2025-12-01 because the proposed implementation was never realized. This left a gap in clearly documenting the **actual MLOps workflow** used by the Self-Healing Platform.

### Current State Analysis

**What We Actually Use:**
- ✅ **Jupyter Notebooks** in OpenShift AI workbenches for model training (ADR-011, ADR-012)
- ✅ **Jupyter Notebook Validator Operator** for automated notebook execution (ADR-029)
- ✅ **Tekton Pipelines** for infrastructure validation and CI/CD (ADR-021, ADR-027)
- ✅ **KServe** for model serving with PVC-based storage (ADR-004, ADR-031)
- ✅ **ArgoCD** for GitOps-based deployment automation (ADR-027)
- ✅ **Git + Gitea** for version control and webhook triggers (ADR-028)

**What We Don't Use:**
- ❌ Kubeflow Pipelines (never implemented)
- ❌ MLflow for experiment tracking (not integrated)
- ❌ Model registries (using simple PVC-based storage)

### Requirements from PRD

- **Continuous Model Training**: Automated retraining based on new operational data
- **Model Validation**: Automated testing of model performance before deployment
- **Model Deployment**: Seamless deployment of validated models to production
- **Version Control**: Track model versions and enable rollback
- **Reproducibility**: Ensure training runs are reproducible
- **Monitoring**: Track model performance in production

## Decision

We will formalize the **Notebook-Centric MLOps Workflow** that leverages OpenShift AI workbenches, Jupyter Notebook Validator Operator, and KServe for a complete model lifecycle.

### Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    MLOps Workflow Architecture               │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  1. Data Collection & Preparation       │
        │  notebooks/01-data-collection/*.ipynb   │
        │  ├─ Prometheus metrics ingestion        │
        │  ├─ OpenShift events analysis           │
        │  ├─ Synthetic data generation           │
        │  └─ Feature engineering                 │
        └─────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  2. Model Training                      │
        │  notebooks/02-anomaly-detection/*.ipynb │
        │  ├─ Isolation Forest (sklearn)          │
        │  ├─ LSTM Autoencoder (PyTorch)          │
        │  ├─ Time-series models (ARIMA)          │
        │  └─ Ensemble methods                    │
        └─────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  3. Model Storage (Version Control)     │
        │  PVC: model-storage-pvc                 │
        │  ├─ /anomaly-detector/v1/model.pkl      │
        │  ├─ /anomaly-detector/v2/model.pkl      │
        │  ├─ /predictive-analytics/v1/model.pkl  │
        │  └─ /lstm-autoencoder/v1/model.pt       │
        └─────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  4. Model Deployment                    │
        │  notebooks/04-model-serving/*.ipynb     │
        │  ├─ Package models for KServe           │
        │  ├─ Create InferenceService manifests   │
        │  └─ Deploy via kubectl/oc               │
        └─────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  5. Validation & Testing                │
        │  Tekton: model-serving-validation-pipeline│
        │  ├─ Check InferenceService status       │
        │  ├─ Test inference endpoints            │
        │  ├─ Validate predictions                │
        │  └─ Performance benchmarking            │
        └─────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  6. Production Monitoring               │
        │  notebooks/07-monitoring-operations/*.ipynb│
        │  ├─ Model accuracy tracking             │
        │  ├─ Drift detection                     │
        │  ├─ Performance metrics                 │
        │  └─ Retraining triggers                 │
        └─────────────────────────────────────────┘
```

## Model Training Strategy

### 1. Development Workflow (Manual)

**For Experimentation and Development:**

```bash
# Access OpenShift AI workbench
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform

# Execute notebooks interactively
# notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb
```

**Training Process:**
1. Data scientist opens notebook in JupyterLab
2. Executes cells interactively
3. Tunes hyperparameters
4. Saves trained model to PVC: `/opt/app-root/src/models/`
5. Model automatically available to KServe via PVC mount

### 2. Automated Workflow (Production)

**For Scheduled Retraining:**

```bash
# Create NotebookValidationJob for automated execution
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: retrain-anomaly-detector
  namespace: self-healing-platform
spec:
  notebook:
    git:
      url: "https://github.com/KubeHeal/openshift-aiops-platform.git"
      ref: "main"
    path: "notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb"
  podConfig:
    containerImage: "quay.io/takinosh/self-healing-workbench:latest"
    serviceAccountName: "notebook-validator-sa"
    resources:
      limits:
        cpu: "4"
        memory: "16Gi"
  schedule: "0 2 * * 0"  # Weekly Sunday at 2 AM
  timeout: "2h"
```

**Reference**: ADR-029 (Jupyter Notebook Validator Operator)

### 3. CI/CD Integration

**Triggered by Git Push:**

```yaml
# Gitea webhook → Tekton EventListener → PipelineRun
# .github/workflows/model-training.yaml (conceptual)
on:
  push:
    paths:
      - 'notebooks/02-anomaly-detection/**'
      - 'notebooks/01-data-collection/**'

jobs:
  validate-notebooks:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Notebook Execution
        run: |
          oc create -f tekton/pipelineruns/notebook-training-run.yaml
```

**Reference**: ADR-027 (CI/CD Pipeline Automation)

## Model Versioning Strategy

### 1. Storage Structure (ADR-031)

**PVC Directory Layout:**
```
/opt/app-root/src/models/
├── anomaly-detector/
│   ├── v1/
│   │   └── model.pkl           # Production version
│   ├── v2/
│   │   └── model.pkl           # Candidate version
│   └── metadata.json           # Version metadata
├── predictive-analytics/
│   ├── v1/
│   │   └── model.pkl
│   └── metadata.json
└── lstm-autoencoder/
    ├── v1/
    │   ├── model.pt
    │   └── scaler.pkl
    └── metadata.json
```

**Why This Structure?**
- ✅ **KServe Compatibility**: sklearn runtime expects one model per directory (ADR-031)
- ✅ **Simple Versioning**: Directory names indicate version
- ✅ **Rollback Support**: Keep previous versions for instant rollback
- ✅ **No External Dependencies**: Works without model registry

### 2. Version Metadata

**metadata.json** (stored alongside models):
```json
{
  "model_name": "anomaly-detector",
  "version": "v2",
  "created_at": "2025-12-10T14:30:00Z",
  "training_notebook": "notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb",
  "git_commit": "e856a747",
  "training_data": {
    "start_date": "2025-11-01",
    "end_date": "2025-12-01",
    "rows": 1000000
  },
  "hyperparameters": {
    "n_estimators": 100,
    "contamination": 0.1,
    "max_samples": 256
  },
  "performance_metrics": {
    "accuracy": 0.94,
    "precision": 0.91,
    "recall": 0.89,
    "f1_score": 0.90
  },
  "validation_status": "passed",
  "deployed_to": "production"
}
```

### 3. Git-Based Version Control

**Git Tags for Model Versions:**
```bash
# Tag model version in git
git tag -a model-anomaly-detector-v2 -m "Anomaly detector v2 - improved accuracy to 94%"
git push origin model-anomaly-detector-v2

# List all model versions
git tag | grep "model-"
```

**Notebook Cell for Version Tracking:**
```python
import json
from datetime import datetime

# Save model metadata
metadata = {
    "model_name": "anomaly-detector",
    "version": "v2",
    "created_at": datetime.utcnow().isoformat(),
    "git_commit": os.popen('git rev-parse HEAD').read().strip(),
    "training_notebook": "notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb",
    # ... other metadata
}

with open('/opt/app-root/src/models/anomaly-detector/v2/metadata.json', 'w') as f:
    json.dump(metadata, f, indent=2)
```

## Model Deployment Strategy

### 1. KServe InferenceService Deployment

**Notebook-Based Deployment** (`notebooks/04-model-serving/kserve-model-deployment.ipynb`):

```python
from kubernetes import client, config

# Load kubeconfig
config.load_incluster_config()

# Define InferenceService
inference_service = {
    "apiVersion": "serving.kserve.io/v1beta1",
    "kind": "InferenceService",
    "metadata": {
        "name": "anomaly-detector",
        "namespace": "self-healing-platform"
    },
    "spec": {
        "predictor": {
            "model": {
                "modelFormat": {"name": "sklearn"},
                "runtime": "sklearn-pvc-runtime",
                "storageUri": "pvc://model-storage-pvc/anomaly-detector/v2",  # Version v2
                "resources": {
                    "requests": {"cpu": "500m", "memory": "1Gi"},
                    "limits": {"cpu": "2", "memory": "4Gi"}
                }
            }
        }
    }
}

# Deploy via Kubernetes API
custom_api = client.CustomObjectsApi()
custom_api.patch_namespaced_custom_object(
    group="serving.kserve.io",
    version="v1beta1",
    namespace="self-healing-platform",
    plural="inferenceservices",
    name="anomaly-detector",
    body=inference_service
)

print("✅ Model v2 deployed to KServe")
```

### 2. Blue-Green Deployment (Zero Downtime)

**Canary Deployment with Traffic Splitting:**
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: anomaly-detector
spec:
  predictor:
    canaryTrafficPercent: 10  # Send 10% traffic to v2
    model:
      modelFormat: {name: sklearn}
      runtime: sklearn-pvc-runtime
      storageUri: "pvc://model-storage-pvc/anomaly-detector/v2"  # New version
  # Previous version automatically becomes "default"
```

**Progressive Rollout:**
```bash
# Stage 1: Deploy v2 with 10% traffic
oc patch inferenceservice anomaly-detector --type merge -p '{"spec":{"predictor":{"canaryTrafficPercent":10}}}'

# Stage 2: Monitor for 1 hour, check metrics
# notebooks/07-monitoring-operations/model-performance-monitoring.ipynb

# Stage 3: Increase to 50% if metrics look good
oc patch inferenceservice anomaly-detector --type merge -p '{"spec":{"predictor":{"canaryTrafficPercent":50}}}'

# Stage 4: Full rollout (100%)
oc patch inferenceservice anomaly-detector --type merge -p '{"spec":{"predictor":{"canaryTrafficPercent":100}}}'
```

### 3. Rollback Strategy

**Instant Rollback to Previous Version:**
```bash
# Change storageUri to previous version
oc patch inferenceservice anomaly-detector --type merge -p '
{
  "spec": {
    "predictor": {
      "model": {
        "storageUri": "pvc://model-storage-pvc/anomaly-detector/v1"
      }
    }
  }
}'

# KServe automatically redeploys with v1
```

## Model Validation Strategy

### 1. Pre-Deployment Validation (in Notebooks)

**Validation Checklist:**
```python
# In training notebook
def validate_model(model, test_data):
    """Validate model before deployment"""
    # 1. Performance metrics
    accuracy = model.score(test_data)
    assert accuracy > 0.85, f"Accuracy too low: {accuracy}"

    # 2. Inference latency
    import time
    start = time.time()
    model.predict(test_data[:100])
    latency = (time.time() - start) / 100
    assert latency < 0.1, f"Latency too high: {latency}s"

    # 3. Model size
    import pickle
    model_bytes = len(pickle.dumps(model))
    assert model_bytes < 100_000_000, f"Model too large: {model_bytes} bytes"

    print("✅ Model validation passed")
    return True
```

### 2. Post-Deployment Validation (Tekton Pipeline)

**Pipeline**: `tekton/pipelines/model-serving-validation-pipeline.yaml`

**Validation Steps:**
1. ✅ Check InferenceService is Ready
2. ✅ Test inference endpoint responds
3. ✅ Validate prediction format
4. ✅ Benchmark inference latency (<100ms)
5. ✅ Check resource utilization
6. ✅ Verify Prometheus metrics exported

**Run Validation:**
```bash
tkn pipeline start model-serving-validation-pipeline \
  -p namespace=self-healing-platform \
  -p model-name=anomaly-detector \
  -n openshift-pipelines \
  --showlog
```

## Model Monitoring Strategy

### 1. Performance Tracking

**Notebook**: `notebooks/07-monitoring-operations/model-performance-monitoring.ipynb`

**Metrics Tracked:**
```python
import prometheus_api_client

prom = PrometheusConnect(url="http://prometheus:9090")

# 1. Inference rate
inference_rate = prom.custom_query(
    'rate(kserve_inference_requests_total{model="anomaly-detector"}[5m])'
)

# 2. Inference latency
latency_p95 = prom.custom_query(
    'histogram_quantile(0.95, rate(kserve_inference_latency_bucket[5m]))'
)

# 3. Error rate
error_rate = prom.custom_query(
    'rate(kserve_inference_errors_total{model="anomaly-detector"}[5m])'
)

# 4. Model accuracy (custom metric)
accuracy = prom.custom_query(
    'model_prediction_accuracy{model="anomaly-detector"}'
)
```

### 2. Drift Detection

**Detect data/concept drift:**
```python
import numpy as np
from scipy.stats import ks_2samp

def detect_drift(training_data, production_data):
    """Kolmogorov-Smirnov test for distribution drift"""
    statistic, p_value = ks_2samp(training_data, production_data)

    if p_value < 0.05:
        print("⚠️  Data drift detected - consider retraining")
        return True
    return False

# Run weekly
if detect_drift(training_features, production_features):
    # Trigger retraining via NotebookValidationJob
    trigger_retraining()
```

### 3. Automated Retraining Triggers

**Conditions for Automatic Retraining:**
1. ✅ Scheduled (weekly on Sundays)
2. ✅ Accuracy drops below 85%
3. ✅ Data drift detected (p < 0.05)
4. ✅ Manual trigger via Lightspeed

**Implementation:**
```yaml
# PrometheusRule for retraining alert
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: model-retraining-alerts
spec:
  groups:
  - name: model_health
    rules:
    - alert: ModelAccuracyDegraded
      expr: model_prediction_accuracy < 0.85
      for: 1h
      annotations:
        summary: "Model accuracy below threshold - retraining required"
      # Trigger NotebookValidationJob via webhook
```

## Reproducibility Strategy

### 1. Pinned Dependencies

**requirements.txt** (in notebooks):
```txt
scikit-learn==1.3.0
numpy==1.24.3
pandas==2.0.3
prometheus-api-client==0.5.3

# Pin all dependencies for reproducibility
```

### 2. Random Seed Control

**In training notebooks:**
```python
import random
import numpy as np
from sklearn.utils import check_random_state

# Set seeds for reproducibility
RANDOM_SEED = 42
random.seed(RANDOM_SEED)
np.random.seed(RANDOM_SEED)

# Pass to sklearn models
model = IsolationForest(random_state=RANDOM_SEED)
```

### 3. Training Data Versioning

**Save training data hash:**
```python
import hashlib
import pandas as pd

def hash_dataframe(df):
    """Generate hash of training data for reproducibility"""
    return hashlib.sha256(pd.util.hash_pandas_object(df).values).hexdigest()

training_data_hash = hash_dataframe(training_df)
metadata['training_data_hash'] = training_data_hash
```

## Comparison: Current vs. Deprecated Approach

| Aspect | **Deprecated (ADR-008)** | **Current (This ADR)** |
|--------|--------------------------|------------------------|
| **Orchestration** | Kubeflow Pipelines | Jupyter notebooks + Notebook Validator Operator |
| **Workflow** | DAG-based pipeline YAML | Interactive notebooks |
| **Execution** | Argo Workflows | OpenShift AI workbenches + scheduled jobs |
| **Versioning** | MLflow model registry | Git tags + PVC directory structure |
| **Deployment** | KFP components | Notebooks + kubectl/oc |
| **Validation** | KFP pipeline steps | Tekton pipelines |
| **Monitoring** | MLflow tracking | Prometheus + custom notebooks |
| **Complexity** | HIGH (many moving parts) | MEDIUM (notebook-centric) |
| **Status** | ❌ Never implemented | ✅ Implemented & working |

## Consequences

### Positive

1. **✅ Simplicity**: Notebook-centric approach is easier to understand and debug
2. **✅ Flexibility**: Data scientists work in familiar Jupyter environment
3. **✅ No External Dependencies**: No need for MLflow, Kubeflow Pipelines
4. **✅ Git-Native Versioning**: Leverage existing Git workflows
5. **✅ Rapid Prototyping**: Quick iteration in notebooks, production via operator
6. **✅ Cost-Effective**: Reuses existing OpenShift AI infrastructure

### Negative

1. **⚠️ Limited Experiment Tracking**: No centralized UI for experiment comparison (vs. MLflow)
2. **⚠️ Manual Workflow Orchestration**: No visual DAG editor (vs. Kubeflow Pipelines)
3. **⚠️ Simple Versioning**: Directory-based versioning less sophisticated than model registries
4. **⚠️ Scale Limitations**: Notebook-based training may not scale to very large models
5. **⚠️ Dependency on Notebooks**: Tightly coupled to Jupyter ecosystem

### Neutral

1. **📊 Hybrid Execution**: Manual (development) + automated (production) workflows
2. **📊 Gradual Automation**: Can add more automation incrementally
3. **📊 Tool Familiarity**: Requires Jupyter + Kubernetes knowledge

## Migration Path (from deprecated ADR-008)

**No migration needed** - ADR-008 was never implemented.

If you were evaluating Kubeflow Pipelines:
1. Use **Notebook Validator Operator** (ADR-029) for pipeline execution
2. Use **Tekton** (ADR-021, ADR-027) for infrastructure/validation pipelines
3. Keep notebooks as the primary development interface

## Related ADRs

- **ADR-004**: [KServe for Model Serving Infrastructure](004-kserve-model-serving.md) - Model serving platform
- **ADR-008**: [Kubeflow Pipelines for MLOps Automation](008-kubeflow-pipelines-mlops.md) - ⚠️ DEPRECATED (superseded by this ADR)
- **ADR-011**: [Self-Healing Workbench Base Image](011-self-healing-workbench-base-image.md) - Jupyter environment
- **ADR-012**: [Notebook Architecture for End-to-End Workflows](012-notebook-architecture-for-end-to-end-workflows.md) - Notebook structure
- **ADR-021**: [Tekton Pipeline for Post-Deployment Validation](021-tekton-pipeline-deployment-validation.md) - Validation pipelines
- **ADR-027**: [CI/CD Pipeline Automation with Tekton and ArgoCD](027-cicd-pipeline-automation.md) - CI/CD workflows
- **ADR-029**: [Jupyter Notebook Validator Operator](029-jupyter-notebook-validator-operator.md) - Automated notebook execution
- **ADR-031**: [Model Storage and Versioning Strategy](031-model-storage-and-versioning-strategy.md) - Storage structure

## References

- [OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
- [KServe Documentation](https://kserve.github.io/website/)
- [Tekton Pipelines](https://tekton.dev/)
- [Jupyter Notebook Validator Operator CRD](../../k8s/operators/jupyter-notebook-validator/)
- [Self-Healing Platform PRD](../../PRD.md) - Section 5.3: Model Training and Deployment
