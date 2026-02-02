# Your First Anomaly Detector: Isolation Forest

*Part 3 of the OpenShift AI Ops Learning Series*

---

## Introduction

Anomaly detection is the foundation of self-healing systems. Before you can automatically fix problems, you need to detect them. Isolation Forest is an excellent starting point because it's simple, effective, and doesn't require labeled training data.

This guide walks you through building your first anomaly detection model using Isolation Forest, training it on synthetic data, and deploying it to KServe for real-time inference.

---

## What You'll Learn

- What anomaly detection is and why it matters
- How the Isolation Forest algorithm works
- Training your first ML model on cluster metrics
- Evaluating model performance (precision, recall, F1)
- Interpreting anomaly scores
- Deploying to KServe for production use

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 1: Setting Up Your AI-Powered Cluster](01-setting-up-ai-powered-cluster.md)
- [ ] Completed [Blog 2: Collecting Data for AI Ops](02-collecting-data-for-aiops.md)
- [ ] Synthetic anomaly data generated (from `synthetic-anomaly-generation.ipynb`)
- [ ] Self-healing workbench running

---

## Understanding Anomaly Detection

### What is an Anomaly?

An anomaly is a data point that deviates significantly from normal behavior. In Kubernetes:

- **Normal**: CPU usage at 30-50% during business hours
- **Anomaly**: CPU usage suddenly spikes to 95%
- **Normal**: Pod restarts once per day
- **Anomaly**: Pod restarts 10 times in 5 minutes (crash loop)

### Why Isolation Forest?

Isolation Forest is ideal for Kubernetes because:

- ✅ **Unsupervised**: Doesn't need labeled "anomaly" examples
- ✅ **Fast**: O(n log n) complexity, handles large datasets
- ✅ **Effective**: Works well on high-dimensional data
- ✅ **Interpretable**: Provides anomaly scores (0-1 scale)

### How It Works

Isolation Forest builds random decision trees:

1. **Randomly select features** (e.g., CPU, memory, restart count)
2. **Randomly split values** (e.g., CPU < 50% or CPU >= 50%)
3. **Isolate anomalies**: Anomalies are "easier" to isolate (fewer splits needed)
4. **Score**: Average path length = anomaly score (lower = more anomalous)

```
Normal point:  [CPU: 40%, Memory: 60%] → Needs 8 splits to isolate
Anomaly point: [CPU: 95%, Memory: 5%]  → Needs 2 splits to isolate
```

---

## Step 1: Prepare Your Data

### Open the Isolation Forest Notebook

1. Navigate to `notebooks/02-anomaly-detection/`
2. Open `01-isolation-forest-implementation.ipynb`

### Why Synthetic Data?

The notebook uses synthetic anomalies because:

- **Real anomalies are rare**: <1% in production clusters
- **Labeled data is hard to get**: Requires months of incident tracking
- **Synthetic data is controlled**: You know exactly what anomalies exist
- **Balanced dataset**: 50% normal, 50% anomaly (vs. 99% normal in real data)

### Load Training Data

```python
import pandas as pd

# Load synthetic anomalies from Blog 2
data = pd.read_parquet('/opt/app-root/src/data/processed/synthetic_anomalies.parquet')

print(f"📊 Dataset shape: {data.shape}")
print(f"✅ Normal samples: {(data['is_anomaly'] == False).sum()}")
print(f"⚠️ Anomaly samples: {(data['is_anomaly'] == True).sum()}")
```

### Feature Selection

Select metrics that indicate problems:

```python
TARGET_METRICS = [
    'node_cpu_utilization',      # High CPU = potential overload
    'node_memory_utilization',   # High memory = OOM risk
    'pod_cpu_usage',             # Pod-level CPU spikes
    'pod_memory_usage',          # Pod memory leaks
    'container_restart_count'    # Crash loops
]

# Extract features
X = data[TARGET_METRICS]
y = data['is_anomaly']  # Labels for evaluation
```

---

## Step 2: Train the Model

### Configure Isolation Forest

```python
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline

# Configuration
ISOLATION_FOREST_CONFIG = {
    'contamination': 0.05,      # Expected 5% anomalies
    'n_estimators': 200,        # Number of trees
    'max_samples': 'auto',      # Sample size per tree
    'max_features': 1.0,       # Use all features
    'random_state': 42          # Reproducibility
}

# Create pipeline: Scale → Detect
model = Pipeline([
    ('scaler', StandardScaler()),
    ('isolation_forest', IsolationForest(**ISOLATION_FOREST_CONFIG))
])
```

### Train on Data

```python
# Train the model
model.fit(X)

print("✅ Model trained successfully!")
print(f"🌲 Trees: {ISOLATION_FOREST_CONFIG['n_estimators']}")
print(f"📊 Features: {len(TARGET_METRICS)}")
```

### Understanding the Output

Isolation Forest returns:
- **-1**: Anomaly (score < threshold)
- **1**: Normal (score >= threshold)

The model also provides `decision_function()` which returns raw scores (lower = more anomalous).

---

## Step 3: Evaluate Performance

### Make Predictions

```python
# Predict on test data
predictions = model.predict(X_test)

# Convert to binary (anomaly = True, normal = False)
anomaly_predictions = (predictions == -1)
```

### Calculate Metrics

```python
from sklearn.metrics import classification_report, confusion_matrix

print("📊 Classification Report:")
print(classification_report(y_test, anomaly_predictions))

print("\n🔢 Confusion Matrix:")
print(confusion_matrix(y_test, anomaly_predictions))
```

### Expected Output

```
              precision    recall  f1-score   support

       False       0.98      0.95      0.96      4500
        True       0.85      0.92      0.88       500

    accuracy                           0.95      5000
   macro avg       0.91      0.93      0.92      5000
weighted avg       0.95      0.95      0.95      5000
```

**Interpreting Metrics:**
- **Precision (0.85)**: When model says "anomaly", it's correct 85% of the time
- **Recall (0.92)**: Model catches 92% of actual anomalies
- **F1-Score (0.88)**: Balanced measure of precision and recall

### Visualize Results

```python
import matplotlib.pyplot as plt

# Plot anomaly scores
scores = model.decision_function(X_test)
plt.hist(scores[y_test == False], bins=50, alpha=0.5, label='Normal')
plt.hist(scores[y_test == True], bins=50, alpha=0.5, label='Anomaly')
plt.xlabel('Anomaly Score (lower = more anomalous)')
plt.ylabel('Frequency')
plt.legend()
plt.title('Anomaly Score Distribution')
plt.show()
```

---

## Step 4: Save the Model

### Save for KServe

```python
import joblib

# Save the pipeline (scaler + model)
model_path = '/opt/app-root/src/models/anomaly-detector/model.pkl'
os.makedirs(os.path.dirname(model_path), exist_ok=True)

joblib.dump(model, model_path)
print(f"✅ Model saved: {model_path}")
```

### Create Model Metadata

```python
import json

metadata = {
    'model_name': 'anomaly-detector',
    'model_type': 'isolation_forest',
    'version': '1.0.0',
    'features': TARGET_METRICS,
    'training_date': datetime.now().isoformat(),
    'performance': {
        'precision': 0.85,
        'recall': 0.92,
        'f1_score': 0.88
    }
}

with open('/opt/app-root/src/models/anomaly-detector/metadata.json', 'w') as f:
    json.dump(metadata, f, indent=2)
```

---

## Step 5: Deploy to KServe

> **💡 Architecture Note**: The notebooks are **Python** (for ML training), but they interact with:
> - **KServe**: Model serving infrastructure (handles sklearn, PyTorch, TensorFlow models)
> - **Coordination Engine**: Go service that orchestrates model calls and remediation
> - **MCP Server**: Go service that connects OpenShift Lightspeed to the platform
>
> Your Python notebooks call these Go services via REST APIs. You don't need to write Go code to use the platform!

### Create InferenceService

The model is automatically deployed via the platform's GitOps workflow. To manually deploy:

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
```

### Test the Model

The Python client calls the Go-based Coordination Engine via HTTP:

```python
from coordination_engine_client import get_client

client = get_client()  # Connects to Go service at http://coordination-engine:8080

# Test prediction
response = client.detect_anomaly(
    metrics={
        'node_cpu_utilization': 0.95,      # High CPU
        'node_memory_utilization': 0.88,   # High memory
        'pod_cpu_usage': 0.92,
        'pod_memory_usage': 0.85,
        'container_restart_count': 5       # Multiple restarts
    }
)

print(f"Anomaly detected: {response.is_anomaly}")
print(f"Confidence: {response.confidence}")
print(f"Severity: {response.severity}")
```

---

## What Just Happened?

You've built a complete anomaly detection pipeline:

### 1. Algorithm Selection

Isolation Forest was chosen because:
- **Unsupervised**: No need for labeled anomaly examples
- **Fast**: Handles large datasets efficiently
- **Effective**: Works well on high-dimensional Kubernetes metrics

### 2. Model Training

- **Data**: Synthetic anomalies provide balanced training set
- **Features**: CPU, memory, restart counts capture key failure modes
- **Pipeline**: Scaling + detection ensures consistent performance

### 3. Evaluation

- **Metrics**: Precision, recall, F1-score measure model quality
- **Visualization**: Score distributions help understand model behavior
- **Threshold tuning**: Adjust contamination parameter for your cluster

### 4. Deployment

- **KServe**: Production-ready model serving
- **Coordination Engine**: Centralized API for all models
- **Real-time**: Sub-second inference for live monitoring

---

## Tuning Tips

### Adjust Contamination

If you get too many false positives:

```python
# Lower contamination = fewer anomalies detected
ISOLATION_FOREST_CONFIG['contamination'] = 0.01  # Expect 1% anomalies
```

If you miss real anomalies:

```python
# Higher contamination = more anomalies detected
ISOLATION_FOREST_CONFIG['contamination'] = 0.10  # Expect 10% anomalies
```

### Add More Features

Include additional metrics:

```python
TARGET_METRICS.extend([
    'network_latency',        # Network issues
    'disk_io_utilization',    # Storage problems
    'http_error_rate',        # Application errors
    'pod_eviction_count'      # Resource pressure
])
```

### Ensemble Methods

Combine multiple models (see [Blog 6: Ensemble Methods](06-ensemble-anomaly-methods.md)):

```python
from sklearn.ensemble import VotingClassifier

# Combine Isolation Forest + Local Outlier Factor
ensemble = VotingClassifier([
    ('isolation_forest', isolation_forest_model),
    ('lof', local_outlier_factor_model)
])
```

---

## Next Steps

Now that you have your first anomaly detector, explore:

1. **Time Series Analysis**: [Blog 4: Time Series Anomaly Detection](04-time-series-anomaly-detection.md) for detecting gradual degradation
2. **Deep Learning**: [Blog 5: LSTM Deep Learning](05-lstm-deep-learning-anomalies.md) for sequence-based detection
3. **Ensemble Methods**: [Blog 6: Ensemble Anomaly Methods](06-ensemble-anomaly-methods.md) to combine multiple detectors
4. **Real Scenarios**: [Blog 10: Pod Crash Loops](10-scenario-pod-crash-loops.md) to see it in action

---

## Related Resources

- **Notebook**: `notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb`
- **ADRs**:
  - [ADR-002: Hybrid Deterministic-AI Self-Healing](docs/adrs/002-hybrid-self-healing-approach.md)
  - [ADR-012: Notebook Architecture](docs/adrs/012-notebook-architecture-for-end-to-end-workflows.md)
- **Research**: [Isolation Forest Paper](https://cs.nju.edu.cn/zhouzh/zhouzh.files/publication/icdm08b.pdf) (Liu, Ting & Zhou, 2008)
- **Scikit-learn Docs**: [Isolation Forest](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.IsolationForest.html)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/KubeHeal/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/03-isolation-forest-anomaly-detection.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 3 of 15 in the OpenShift AI Ops Learning Series*
