# Training ML Models with Tekton Pipelines

**Published**: 2026-01-28
**Author**: Platform Team
**Tags**: `ml-training`, `tekton`, `automation`, `kserve`

## Introduction

This guide demonstrates how to train and deploy machine learning models using Tekton pipelines in the Self-Healing Platform. Automated model training ensures models stay current with cluster behavior, improving prediction accuracy and anomaly detection reliability.

**What you'll learn:**
- Train models manually with custom time windows
- Schedule automated weekly retraining
- Integrate real Prometheus metrics with synthetic data
- Validate model health before deployment
- Add your own custom models

## Quick Start: Train a Model

### Manual Training with Default Settings (24h Data)

Train the anomaly detector with 24 hours of recent data:

```bash
oc create -f - <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: train-anomaly-detector-
  namespace: self-healing-platform
spec:
  pipelineRef:
    name: model-training-pipeline
  params:
    - name: model-name
      value: "anomaly-detector"
    - name: notebook-path
      value: "notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb"
    - name: data-source
      value: "prometheus"
    - name: training-hours
      value: "24"
    - name: inference-service-name
      value: "anomaly-detector"
    - name: git-url
      value: "https://github.com/KubeHeal/openshift-aiops-platform.git"
    - name: git-ref
      value: "main"
  timeout: 30m
EOF
```

Monitor the training progress:

```bash
# Watch pipeline execution
tkn pipelinerun logs -f -n self-healing-platform

# Check training job status
oc get notebookvalidationjobs -n self-healing-platform

# View model file
oc exec -n self-healing-platform deployment/model-troubleshooting-utilities -- \
  ls -lh /mnt/models/anomaly-detector/
```

### Manual Training with Custom Time Window

Train the predictive analytics model with 30 days of data for capturing seasonal patterns:

```bash
oc create -f - <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: train-predictive-analytics-
  namespace: self-healing-platform
spec:
  pipelineRef:
    name: model-training-pipeline
  params:
    - name: model-name
      value: "predictive-analytics"
    - name: notebook-path
      value: "notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb"
    - name: data-source
      value: "prometheus"
    - name: training-hours
      value: "720"
    - name: inference-service-name
      value: "predictive-analytics"
    - name: git-url
      value: "https://github.com/KubeHeal/openshift-aiops-platform.git"
    - name: git-ref
      value: "main"
  timeout: 45m
EOF
```

### GPU-Accelerated Training with NotebookValidationJob

For faster training, use GPU resources with `NotebookValidationJob`:

```bash
oc create -f - <<'EOF'
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: train-predictive-gpu
  namespace: self-healing-platform
  labels:
    model-name: predictive-analytics
spec:
  notebook:
    git:
      ref: main
      url: https://github.com/KubeHeal/openshift-aiops-platform.git
    path: notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb
  podConfig:
    containerImage: image-registry.openshift-image-registry.svc:5000/self-healing-platform/notebook-validator:latest
    env:
    - name: DATA_SOURCE
      value: prometheus
    - name: PROMETHEUS_URL
      value: https://prometheus-k8s.openshift-monitoring.svc:9091
    - name: TRAINING_HOURS
      value: "168"
    - name: MODEL_NAME
      value: predictive-analytics
    nodeSelector:
      nvidia.com/gpu.present: "true"
    resources:
      limits:
        cpu: "4"
        memory: 8Gi
        nvidia.com/gpu: "1"
      requests:
        cpu: "2"
        memory: 4Gi
        nvidia.com/gpu: "1"
    serviceAccountName: self-healing-workbench
    tolerations:
    - effect: NoSchedule
      key: nvidia.com/gpu
      operator: Exists
    volumeMounts:
    - mountPath: /mnt/models
      name: model-storage
    volumes:
    - name: model-storage
      persistentVolumeClaim:
        claimName: gpu-training-pvc  # Use GP3 for GPU nodes (CephFS may not be available)
  timeout: 45m
EOF
```

**Note**: GPU nodes may not have CephFS drivers. Use `gpu-training-pvc` (GP3 storage class) instead of `model-storage-pvc` (CephFS) for GPU-accelerated training. Copy the model to CephFS after training completes.

## Training Time Windows

Choose the appropriate time window based on your use case:

| Duration | Hours | Use Case | Example |
|----------|-------|----------|---------|
| **1 day** | 24 | Quick iteration, development, testing | Testing notebook changes |
| **1 week** | 168 | Weekly retraining, production anomaly detection | Anomaly detector scheduled training |
| **30 days** | 720 | Initial training, seasonal patterns, forecasting | Predictive analytics scheduled training |

**Recommended defaults:**
- **Anomaly Detector**: 168h (1 week) - Captures weekly patterns without excessive noise
- **Predictive Analytics**: 720h (30 days) - Captures monthly trends and seasonality

## Data Sources

The platform supports three data source modes for model training:

### Synthetic Data (`DATA_SOURCE=synthetic`)

**Use case**: Development, testing, CI/CD, when Prometheus is unavailable

- ✅ Fast and reproducible
- ✅ Known anomaly labels for validation
- ✅ No external dependencies
- ⚠️  May not capture real cluster patterns

```yaml
params:
  - name: data-source
    value: "synthetic"
```

### Prometheus Data (`DATA_SOURCE=prometheus`)

**Use case**: Production training with real cluster metrics

- ✅ Real cluster behavior patterns
- ✅ Adapts to actual workload characteristics
- ✅ Improves model accuracy
- ⚠️  Requires Prometheus access
- ⚠️  Real anomalies are rare (<1%)

```yaml
params:
  - name: data-source
    value: "prometheus"
```

Training notebooks automatically:
1. Fetch real metrics from Prometheus (80% of data)
2. Inject synthetic anomalies (20% of data) for balanced training
3. Combine datasets for robust model training

### Hybrid Data (`DATA_SOURCE=hybrid`)

**Use case**: Staging, validation, best of both worlds

- ✅ 50% Prometheus + 50% synthetic
- ✅ Balanced representation
- ✅ Good for validation environments

```yaml
params:
  - name: data-source
    value: "hybrid"
```

**Recommendation**: Use `prometheus` mode for production scheduled training to ensure models learn real cluster patterns.

## Automated Scheduled Training

The platform automatically retrains models weekly via CronJobs:

### Anomaly Detector (Weekly, Sunday 2 AM UTC)

```bash
# View CronJob configuration
oc get cronjob weekly-anomaly-detector-training -n self-healing-platform -o yaml

# View recent training runs
oc get pipelineruns -n self-healing-platform -l model-name=anomaly-detector

# Check latest training job
tkn pipelinerun logs -n self-healing-platform $(oc get pipelinerun -n self-healing-platform \
  -l model-name=anomaly-detector --sort-by=.metadata.creationTimestamp -o name | tail -1)
```

### Predictive Analytics (Weekly, Sunday 3 AM UTC)

```bash
# View CronJob configuration
oc get cronjob weekly-predictive-analytics-training -n self-healing-platform -o yaml

# View recent training runs
oc get pipelineruns -n self-healing-platform -l model-name=predictive-analytics

# Check latest training job
tkn pipelinerun logs -n self-healing-platform $(oc get pipelinerun -n self-healing-platform \
  -l model-name=predictive-analytics --sort-by=.metadata.creationTimestamp -o name | tail -1)
```

### Customizing Schedules

Edit the CronJob schedules in `charts/hub/values.yaml`:

```yaml
tekton:
  modelTraining:
    anomalyDetector:
      schedule: "0 2 * * 0"  # Sunday 2 AM UTC (cron format)
      dataSource: "prometheus"

    predictiveAnalytics:
      schedule: "0 3 * * 0"  # Sunday 3 AM UTC
      dataSource: "prometheus"
```

Deploy the changes:

```bash
helm upgrade --install self-healing-platform charts/hub \
  --namespace self-healing-platform \
  --values charts/hub/values.yaml
```

## Monitoring Training Runs

### Check Pipeline Status

```bash
# List all pipeline runs
tkn pipelinerun list -n self-healing-platform

# Watch specific run
tkn pipelinerun logs train-anomaly-detector-abc123 -f -n self-healing-platform
```

### Verify Model Deployment

```bash
# Check InferenceService status
oc get inferenceservice anomaly-detector -n self-healing-platform

# Check predictor pod status
oc get pods -l serving.kserve.io/inferenceservice=anomaly-detector \
  -n self-healing-platform

# View model file details
oc exec -n self-healing-platform deployment/model-troubleshooting-utilities -- \
  ls -lh /mnt/models/anomaly-detector/model.pkl
```

### Test Model Endpoint

```bash
# Get predictor pod IP
PREDICTOR_IP=$(oc get pod -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=anomaly-detector \
  -o jsonpath='{.items[0].status.podIP}')

# Test anomaly detector (single output)
curl -X POST http://${PREDICTOR_IP}:8080/v1/models/anomaly-detector:predict \
  -H 'Content-Type: application/json' \
  -d '{"instances": [[0.5, 0.6, 0.4, 0.3, 0.8]]}'
```

### Predictive Analytics Multi-Output Model

The predictive analytics model returns **all 5 metrics** in a single prediction:

```bash
# Get predictive-analytics predictor IP
PREDICTOR_IP=$(oc get pod -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=predictive-analytics \
  -o jsonpath='{.items[0].status.podIP}')

# Test prediction (requires 3264 features from coordination engine)
# For testing, use zeros:
curl -X POST http://${PREDICTOR_IP}:8080/v1/models/predictive-analytics:predict \
  -H 'Content-Type: application/json' \
  -d "{\"instances\": [$(python3 -c 'print([0.0] * 3264)')]}"
```

**Response format** (all 5 metrics):
```json
{
  "predictions": [[0.45, 0.62, 0.38, 150.2, 89.5]]
}
```

| Index | Metric |
|-------|--------|
| 0 | `cpu_usage` |
| 1 | `memory_usage` |
| 2 | `disk_usage` |
| 3 | `network_in` |
| 4 | `network_out` |

## Adding Your Own Custom Model

### Step 1: Create Training Notebook

Create a Jupyter notebook in `notebooks/`:

```python
# your-model-training.ipynb

import os
import joblib
from pathlib import Path
from sklearn.ensemble import YourAlgorithm

# 1. Get environment variables
data_source = os.getenv('DATA_SOURCE', 'synthetic')
training_hours = int(os.getenv('TRAINING_HOURS', '168'))
model_name = os.getenv('MODEL_NAME', 'your-model')

# 2. Load data based on source
if data_source == 'prometheus':
    data = fetch_prometheus_data(hours=training_hours)
else:
    data = generate_synthetic_data(hours=training_hours)

# 3. Train model
model = YourAlgorithm()
model.fit(data)

# 4. Save to mounted storage (KServe-compatible structure)
MODELS_DIR = Path('/mnt/models') if Path('/mnt/models').exists() \
             else Path('/opt/app-root/src/models')
MODEL_DIR = MODELS_DIR / model_name
MODEL_DIR.mkdir(parents=True, exist_ok=True)

model_path = MODEL_DIR / 'model.pkl'
joblib.dump(model, model_path)

print(f"✅ Model saved to {model_path}")
```

### Step 2: Add to Tekton Pipeline

Update `charts/hub/values.yaml`:

```yaml
models:
  - name: your-model
    cpu: "1000m"
    memory: "2Gi"
    cpuLimit: "2"
    memoryLimit: "4Gi"
    syncWave: "2"
```

### Step 3: Create CronJob for Scheduled Training

Add to `charts/hub/templates/tekton-model-training-cronjobs.yaml`:

```yaml
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: weekly-your-model-training
  namespace: {{ .Values.main.namespace }}
spec:
  schedule: "0 4 * * 0"  # Sundays 4 AM UTC
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: trigger-training
              image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
              command:
                - /bin/bash
                - -c
                - |
                  oc create -f - <<EOF
                  apiVersion: tekton.dev/v1beta1
                  kind: PipelineRun
                  metadata:
                    generateName: train-your-model-
                  spec:
                    pipelineRef:
                      name: model-training-pipeline
                    params:
                      - name: model-name
                        value: "your-model"
                      - name: notebook-path
                        value: "notebooks/your-model-training.ipynb"
                      - name: training-hours
                        value: "168"
                      - name: data-source
                        value: "prometheus"
                      - name: inference-service-name
                        value: "your-model"
                      - name: git-url
                        value: "{{ .Values.global.git.repoURL }}"
                      - name: git-ref
                        value: "{{ .Values.global.git.revision }}"
                  EOF
```

### Step 4: Create InferenceService

Add to `charts/hub/templates/model-serving.yaml`:

```yaml
---
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: your-model
  namespace: {{ .Values.main.namespace }}
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: pvc://model-storage-pvc/your-model/
      resources:
        requests:
          cpu: "1000m"
          memory: "2Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
```

### Step 5: Test Your Model

```bash
# Manual training
oc create -f - <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: train-your-model-
spec:
  pipelineRef:
    name: model-training-pipeline
  params:
    - name: model-name
      value: "your-model"
    - name: notebook-path
      value: "notebooks/your-model-training.ipynb"
    - name: training-hours
      value: "24"
    - name: data-source
      value: "synthetic"
    - name: inference-service-name
      value: "your-model"
    - name: git-url
      value: "https://github.com/KubeHeal/openshift-aiops-platform.git"
    - name: git-ref
      value: "main"
EOF

# Validate deployment
./scripts/validate-models.sh

# Test prediction
PREDICTOR_IP=$(oc get pod -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=your-model \
  -o jsonpath='{.items[0].status.podIP}')

curl -X POST http://${PREDICTOR_IP}:8080/v1/models/your-model:predict \
  -H 'Content-Type: application/json' \
  -d '{"instances": [[...your input data...]]}'
```

## Troubleshooting

### Model Training Fails

**Symptoms**: Pipeline run fails, NotebookValidationJob shows error

**Diagnosis**:
```bash
# Check pipeline logs
tkn pipelinerun logs <pipelinerun-name> -f -n self-healing-platform

# Check NotebookValidationJob status
oc get notebookvalidationjobs -n self-healing-platform
oc describe notebookvalidationjob <job-name> -n self-healing-platform

# View training pod logs
oc logs -n self-healing-platform <training-pod-name>
```

**Common causes**:
- Insufficient memory (increase `memoryLimit` in values.yaml)
- Prometheus unavailable (check `PROMETHEUS_URL` connectivity)
- Git repository inaccessible (verify `git-url` and credentials)
- Notebook syntax errors (test notebook locally first)

### Model Won't Load

**Symptoms**: Predictor pod crashes, OOMKilled, CrashLoopBackOff

**Diagnosis**:
```bash
# Check predictor pod logs
oc logs -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=anomaly-detector

# Check model file exists
oc exec -n self-healing-platform deployment/model-troubleshooting-utilities -- \
  ls -lh /mnt/models/anomaly-detector/

# Test model loading manually
oc exec -it -n self-healing-platform deployment/model-troubleshooting-utilities -- \
  python3 -c "import joblib; m = joblib.load('/mnt/models/anomaly-detector/model.pkl'); print(type(m))"
```

**Common causes**:
- Model file corrupted (retrain model)
- Model too large (increase predictor memory limits)
- Incompatible sklearn version (check runtime image)

### Predictions Are Inaccurate

**Symptoms**: Model returns unexpected results, poor precision/recall

**Diagnosis**:
```bash
# Check training data source
oc get pipelinerun -n self-healing-platform \
  -l model-name=anomaly-detector -o yaml | grep data-source

# Check training time window
oc get pipelinerun -n self-healing-platform \
  -l model-name=anomaly-detector -o yaml | grep training-hours

# Review training metrics from notebook output
oc logs -n self-healing-platform <training-pod-name> | grep -A 10 "Model Evaluation"
```

**Solutions**:
- Increase training window (more data = better patterns)
- Use `prometheus` data source instead of `synthetic`
- Adjust model hyperparameters in notebook
- Retrain more frequently (weekly → daily)

### Prometheus Data Issues

**Symptoms**: Training falls back to synthetic data, empty Prometheus queries

**Important**: OpenShift Prometheus requires **bearer token authentication** over HTTPS port 9091.

**Diagnosis**:
```bash
# Check Prometheus accessibility with bearer token
oc exec -n self-healing-platform deployment/model-troubleshooting-utilities -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://prometheus-k8s.openshift-monitoring.svc:9091/api/v1/status/config" | head -c 200
'

# Test metric query with authentication
oc exec -n self-healing-platform deployment/model-troubleshooting-utilities -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://prometheus-k8s.openshift-monitoring.svc:9091/api/v1/query?query=instance:node_memory_utilisation:ratio"
'

# Check ServiceAccount permissions
oc auth can-i get pods --as=system:serviceaccount:self-healing-platform:self-healing-workbench \
  -n openshift-monitoring
```

**Solutions**:
- Use HTTPS port 9091 (not HTTP port 9090) for authenticated access
- Ensure ServiceAccount token is mounted (automatically done by Kubernetes)
- Verify ServiceAccount has `cluster-monitoring-view` ClusterRole
- Check that required metrics exist (some metrics may have different names)
- Use `hybrid` mode as fallback if some metrics missing

## Validation Scripts

The platform includes validation scripts to verify model health:

```bash
# Validate all models
./scripts/validate-models.sh

# Test specific model endpoint
./scripts/test-model-endpoint.sh anomaly-detector

# Check training status
./scripts/check-training-status.sh
```

## References

- **ADR-050**: Anomaly Detector Model Training and Data Strategy
- **ADR-051**: Predictive Analytics Model Training Strategy
- **ADR-052**: Model Training Data Source Selection Strategy
- **ADR-053**: Separation of Model Training from ArgoCD Sync Waves
- **KServe Documentation**: https://kserve.github.io/website/
- **Tekton Pipelines**: https://tekton.dev/docs/pipelines/

## Next Steps

1. **Explore notebooks**: Review training notebooks in `notebooks/02-anomaly-detection/`
2. **Monitor scheduled training**: Watch CronJobs run weekly and verify model updates
3. **Integrate with coordination engine**: Use trained models for self-healing workflows
4. **Add custom models**: Implement domain-specific models for your use cases
5. **Tune hyperparameters**: Optimize model performance for your cluster characteristics

## Related Blog Posts

- [End-to-End Self-Healing with Lightspeed](./16-end-to-end-self-healing-with-lightspeed.md)
- [KServe Model Deployment](./15-kserve-model-deployment.md)
- [Architecture Decision Records](../docs/adr/)
