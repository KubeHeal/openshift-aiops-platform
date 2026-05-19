---
title: Deploy Your First ML Model to KServe
description: A hands-on tutorial to train an anomaly detection model and deploy it as a scalable inference service
---

# Deploy Your First ML Model to KServe

**Time**: 45 minutes | **Difficulty**: Beginner | **Prerequisites**: Access to OpenShift AIOps Platform

## What You'll Build

By the end of this tutorial, you will have:

✅ Trained a simple anomaly detection model using real cluster metrics
✅ Saved the model to persistent storage
✅ Deployed the model as a KServe InferenceService
✅ Made predictions via HTTP REST API
✅ Monitored model performance metrics

## What You'll Learn

- How to access and collect Prometheus metrics
- Training a scikit-learn model in a Jupyter notebook
- Model serialization and storage patterns
- Creating KServe InferenceService resources
- Testing deployed models with curl
- Basic model monitoring

## Prerequisites

Before you begin:

- ✅ OpenShift AIOps Platform deployed (see [Fresh Cluster Deployment Guide](../guides/FRESH-CLUSTER-DEPLOYMENT.md))
- ✅ Access to the workbench at `self-healing-workbench-0` pod
- ✅ Basic familiarity with Python and Jupyter notebooks
- ✅ `oc` CLI configured and logged in

**Check your access**:

```bash
# Verify you can access the platform namespace
oc get pods -n self-healing-platform

# You should see self-healing-workbench-0 Running
```

---

## Step 1: Access the Workbench

### 1.1 Port-Forward to the Workbench

```bash
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
```

**Expected output**:
```
Forwarding from 127.0.0.1:8888 -> 8888
Forwarding from [::1]:8888 -> 8888
```

### 1.2 Open Jupyter in Your Browser

1. Open http://localhost:8888 in your browser
2. You'll see the Jupyter file browser

**✅ Success check**: You should see folders like `notebooks/`, `src/`, `data/`

---

## Step 2: Create Your Training Notebook

### 2.1 Create a New Notebook

1. Navigate to `notebooks/02-anomaly-detection/`
2. Click **New** → **Python 3 (ipykernel)**
3. Rename the notebook to `my-first-model.ipynb`

### 2.2 Install Required Libraries

In the first cell, install dependencies:

```python
# Cell 1: Install dependencies
!pip install -q prometheus-api-client scikit-learn joblib pandas numpy matplotlib
```

**Run the cell** (Shift+Enter). Wait for installation to complete.

### 2.3 Import Libraries

```python
# Cell 2: Import libraries
import numpy as np
import pandas as pd
from prometheus_api_client import PrometheusConnect
from sklearn.ensemble import IsolationForest
import joblib
import os
from datetime import datetime, timedelta

print("✅ Libraries imported successfully")
```

**✅ Success check**: You should see "✅ Libraries imported successfully"

---

## Step 3: Collect Training Data from Prometheus

### 3.1 Connect to Prometheus

```python
# Cell 3: Connect to Prometheus
# Platform Prometheus is accessible at this service
PROMETHEUS_URL = "http://prometheus-k8s.openshift-monitoring.svc:9090"

prom = PrometheusConnect(url=PROMETHEUS_URL, disable_ssl=True)

# Test connection
try:
    prom.check_prometheus_connection()
    print("✅ Connected to Prometheus")
except Exception as e:
    print(f"❌ Connection failed: {e}")
```

**✅ Success check**: You should see "✅ Connected to Prometheus"

### 3.2 Query CPU Metrics

```python
# Cell 4: Query CPU usage data
# Get 7 days of CPU usage across all pods
query = 'sum(rate(container_cpu_usage_seconds_total{namespace="self-healing-platform"}[5m])) by (pod)'
end_time = datetime.now()
start_time = end_time - timedelta(days=7)

print(f"Querying Prometheus from {start_time} to {end_time}...")

metric_data = prom.get_metric_range_data(
    metric_name=query,
    start_time=start_time,
    end_time=end_time,
    chunk_size=timedelta(hours=1)
)

print(f"✅ Retrieved {len(metric_data)} time series")
```

**What's happening**: This queries Prometheus for CPU usage patterns over the last 7 days. This real data will train your anomaly detector.

### 3.3 Process Data into DataFrame

```python
# Cell 5: Convert to DataFrame
data_points = []

for metric in metric_data:
    pod_name = metric['metric'].get('pod', 'unknown')
    for value in metric['values']:
        timestamp, cpu_usage = value
        data_points.append({
            'timestamp': pd.to_datetime(timestamp, unit='s'),
            'pod': pod_name,
            'cpu_usage': float(cpu_usage)
        })

df = pd.DataFrame(data_points)

print(f"✅ Processed {len(df)} data points")
print(f"\nSample data:")
print(df.head())
```

**✅ Success check**: You should see a DataFrame with columns: `timestamp`, `pod`, `cpu_usage`

---

## Step 4: Train the Anomaly Detection Model

### 4.1 Prepare Features

```python
# Cell 6: Feature engineering
# Create time-based features
df['hour'] = df['timestamp'].dt.hour
df['day_of_week'] = df['timestamp'].dt.dayofweek

# Create rolling statistics (5-minute windows)
df = df.sort_values('timestamp')
df['cpu_rolling_mean'] = df.groupby('pod')['cpu_usage'].transform(
    lambda x: x.rolling(window=5, min_periods=1).mean()
)
df['cpu_rolling_std'] = df.groupby('pod')['cpu_usage'].transform(
    lambda x: x.rolling(window=5, min_periods=1).std()
)

# Fill NaN values
df = df.fillna(0)

# Select features for training
features = ['cpu_usage', 'hour', 'day_of_week', 'cpu_rolling_mean', 'cpu_rolling_std']
X = df[features]

print(f"✅ Features prepared: {features}")
print(f"Training data shape: {X.shape}")
```

### 4.2 Train Isolation Forest Model

```python
# Cell 7: Train the model
# Isolation Forest is great for anomaly detection
model = IsolationForest(
    n_estimators=100,      # Number of trees
    contamination=0.1,      # Expected proportion of anomalies (10%)
    random_state=42,        # Reproducibility
    n_jobs=-1              # Use all CPU cores
)

print("Training Isolation Forest model...")
model.fit(X)

print("✅ Model trained successfully!")
print(f"Model has {model.n_estimators} trees")
```

**What's happening**: The Isolation Forest algorithm learns normal CPU usage patterns. It will later identify deviations from these patterns as anomalies.

### 4.3 Test the Model Locally

```python
# Cell 8: Make predictions on training data
predictions = model.predict(X)
anomaly_scores = model.decision_function(X)

# -1 = anomaly, 1 = normal
num_anomalies = (predictions == -1).sum()
num_normal = (predictions == 1).sum()

print(f"✅ Predictions complete:")
print(f"   Normal points: {num_normal}")
print(f"   Anomalies detected: {num_anomalies}")
print(f"   Anomaly rate: {num_anomalies / len(predictions) * 100:.2f}%")

# Show sample anomalies
anomaly_df = df[predictions == -1][['timestamp', 'pod', 'cpu_usage']].head(10)
print(f"\nSample anomalies detected:")
print(anomaly_df)
```

**✅ Success check**: You should see anomalies detected (around 10% of data points)

---

## Step 5: Save the Model

### 5.1 Create Model Directory

```python
# Cell 9: Save model to persistent storage
model_dir = "/opt/app-root/src/models/my-first-model"
os.makedirs(model_dir, exist_ok=True)

model_path = os.path.join(model_dir, "model.joblib")
metadata_path = os.path.join(model_dir, "metadata.txt")

print(f"✅ Created model directory: {model_dir}")
```

### 5.2 Serialize the Model

```python
# Cell 10: Save model with joblib
joblib.dump(model, model_path)

# Save metadata
metadata = f"""Model: Isolation Forest Anomaly Detector
Trained: {datetime.now().isoformat()}
Features: {features}
Training samples: {len(X)}
Anomalies detected: {num_anomalies}
Expected contamination: 10%
"""

with open(metadata_path, 'w') as f:
    f.write(metadata)

print(f"✅ Model saved to: {model_path}")
print(f"✅ Metadata saved to: {metadata_path}")
print(f"\nModel size: {os.path.getsize(model_path) / 1024:.2f} KB")
```

**✅ Success check**: Model file should be created (~50-100 KB)

---

## Step 6: Deploy Model to KServe

### 6.1 Create InferenceService Manifest

Switch to terminal (File → New → Terminal) and create the InferenceService YAML:

```bash
cat > /tmp/my-first-inferenceservice.yaml <<'EOF'
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: my-first-model
  namespace: self-healing-platform
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: pvc://model-storage/my-first-model
      resources:
        requests:
          cpu: "100m"
          memory: "256Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"
EOF

echo "✅ InferenceService manifest created"
```

### 6.2 Deploy to Kubernetes

```bash
oc apply -f /tmp/my-first-inferenceservice.yaml
```

**Expected output**:
```
inferenceservice.serving.kserve.io/my-first-model created
```

### 6.3 Wait for Model to Deploy

```bash
# Watch deployment progress
oc get inferenceservice my-first-model -n self-healing-platform -w
```

**Wait for**:
```
NAME              URL                                                 READY   PREV   LATEST   ...
my-first-model    http://my-first-model.self-healing-platform...     True    100
```

**Press Ctrl+C** when `READY` shows `True`.

**⏱️ This takes 2-3 minutes** - KServe is:
1. Creating a predictor pod
2. Loading your model
3. Starting the inference server
4. Health checking the endpoint

---

## Step 7: Test Your Deployed Model

### 7.1 Get the Inference Endpoint

```bash
# Get the route URL
MODEL_URL=$(oc get route my-first-model -n self-healing-platform -o jsonpath='{.spec.host}')
echo "Model endpoint: https://${MODEL_URL}"
```

### 7.2 Create Test Data

Back in your notebook:

```python
# Cell 11: Prepare test inference data
test_data = {
    "instances": [
        [0.5, 10, 1, 0.45, 0.05],  # Normal CPU usage at 10am on Monday
        [2.5, 3, 6, 2.3, 0.8],     # High CPU at 3am on Saturday (anomaly)
        [0.3, 14, 2, 0.35, 0.02]   # Normal usage at 2pm on Tuesday
    ]
}

# Features: cpu_usage, hour, day_of_week, cpu_rolling_mean, cpu_rolling_std
print("Test instances:")
for i, instance in enumerate(test_data["instances"]):
    print(f"  {i+1}. CPU={instance[0]}, Hour={instance[1]}, Day={instance[2]}")
```

### 7.3 Make Predictions via HTTP

```python
# Cell 12: Call the inference endpoint
import requests
import json

# You'll need the MODEL_URL from the terminal above
MODEL_URL = "my-first-model-self-healing-platform.apps.cluster-xxxxx.xxxxx.example.com"
endpoint = f"https://{MODEL_URL}/v1/models/my-first-model:predict"

response = requests.post(
    endpoint,
    json=test_data,
    headers={"Content-Type": "application/json"},
    verify=False  # Skip SSL verification for demo
)

if response.status_code == 200:
    predictions = response.json()
    print("✅ Predictions received:")
    print(json.dumps(predictions, indent=2))

    # Interpret results
    for i, pred in enumerate(predictions['predictions']):
        label = "🔴 ANOMALY" if pred == -1 else "🟢 Normal"
        print(f"Instance {i+1}: {label}")
else:
    print(f"❌ Request failed: {response.status_code}")
    print(response.text)
```

**✅ Success check**: You should see predictions like:
```
Instance 1: 🟢 Normal
Instance 2: 🔴 ANOMALY
Instance 3: 🟢 Normal
```

**Congratulations!** 🎉 Your model is now serving predictions via HTTP!

---

## Step 8: Monitor Your Model

### 8.1 Check Predictor Pods

```bash
# See the running predictor pod
oc get pods -n self-healing-platform -l serving.kserve.io/inferenceservice=my-first-model

# View model server logs
oc logs -n self-healing-platform -l serving.kserve.io/inferenceservice=my-first-model -c kserve-container --tail=50
```

### 8.2 View Model Metrics (Optional)

If Prometheus ServiceMonitor is configured:

```python
# Cell 13: Query model serving metrics
query = 'sum(rate(http_requests_total{service="my-first-model"}[5m]))'
result = prom.custom_query(query=query)

if result:
    print(f"✅ Model request rate: {result[0]['value'][1]} requests/sec")
else:
    print("ℹ️ Metrics not yet available (make a few more requests)")
```

---

## What You've Learned

In this tutorial, you:

✅ **Collected real data** from Prometheus
✅ **Engineered features** for time-series anomaly detection
✅ **Trained an Isolation Forest** model on cluster CPU metrics
✅ **Serialized and stored** the model
✅ **Deployed to KServe** as a scalable inference service
✅ **Made predictions** via HTTP REST API
✅ **Monitored** model deployment and logs

## Next Steps

Now that you have a working model, try:

### 1. Improve the Model

- **Add more features**: Memory usage, network I/O, disk I/O
- **Tune hyperparameters**: Adjust `n_estimators`, `contamination`
- **Try different algorithms**: LSTM, Autoencoders, Prophet
- **Cross-validate**: Split data into train/test sets

**See**: [Workbench Development Guide](./workbench-development-guide.md)

### 2. Automate Model Training

- **Set up Tekton pipelines**: Auto-retrain on new data
- **Schedule periodic updates**: Daily or weekly retraining
- **Version your models**: Keep track of model iterations

**See**: [ADR-053: Tekton Pipelines for Model Training](../adrs/053-tekton-model-training-pipelines.md)

### 3. Integrate with Self-Healing

- **Connect to coordination engine**: Send anomaly alerts
- **Trigger remediations**: Auto-scale pods, restart services
- **Build feedback loops**: Improve model with remediation outcomes

**See**: [ADR-002: Hybrid Self-Healing Approach](../adrs/002-hybrid-self-healing-approach.md)

### 4. Production Deployment

- **Add canary rollouts**: Gradual model deployment
- **Implement A/B testing**: Compare model versions
- **Set up alerting**: Monitor prediction drift
- **Enable autoscaling**: Scale based on traffic

**See**: [ADR-040: Extensible KServe Model Registry](../adrs/040-extensible-kserve-model-registry.md)

## Troubleshooting

### Issue: "Connection to Prometheus failed"

**Solution**: Check if Prometheus is accessible:

```bash
oc get svc -n openshift-monitoring prometheus-k8s
```

If missing, you may need cluster-admin to access monitoring namespace.

### Issue: "InferenceService not becoming Ready"

**Check predictor pod logs**:

```bash
oc get pods -n self-healing-platform -l serving.kserve.io/inferenceservice=my-first-model
oc logs <predictor-pod-name> -c kserve-container
```

Common causes:
- Model file not found (check PVC mount)
- Insufficient resources (increase CPU/memory limits)
- Model format mismatch (verify sklearn version)

### Issue: "Predictions return errors"

**Verify input shape**:

```python
# Model expects 5 features: cpu_usage, hour, day_of_week, cpu_rolling_mean, cpu_rolling_std
# Each instance must be a list of 5 numbers
test_data = {
    "instances": [
        [0.5, 10, 1, 0.45, 0.05]  # ✅ Correct: 5 features
        # [0.5, 10, 1] ❌ Wrong: only 3 features
    ]
}
```

## Clean Up

When you're done experimenting:

```bash
# Delete the InferenceService
oc delete inferenceservice my-first-model -n self-healing-platform

# Delete model files (from notebook)
!rm -rf /opt/app-root/src/models/my-first-model
```

---

## Additional Resources

- **[KServe Documentation](https://kserve.github.io/website/)** - Official KServe docs
- **[Scikit-learn Isolation Forest](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.IsolationForest.html)** - Algorithm details
- **[ADR-004: KServe for Model Serving](../adrs/004-kserve-model-serving.md)** - Architecture decision
- **[ADR-039: User-Deployed KServe Models](../adrs/039-user-deployed-kserve-models.md)** - Model deployment patterns

**Questions or stuck?** Open an issue: https://github.com/KubeHeal/openshift-aiops-platform/issues

---

**Tutorial last updated**: 2026-05-18
**Tested on**: OpenShift 4.20, RHOAI 2.22.2, KServe 1.36.1
