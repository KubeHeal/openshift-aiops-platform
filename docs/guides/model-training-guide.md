# Model Training Guide

## Overview

This guide documents how to train and deploy the two production models in the OpenShift AIOps platform:
1. **anomaly-detector** - Isolation Forest for real-time anomaly detection
2. **predictive-analytics** - Random Forest for resource usage prediction

Both models are automatically retrained weekly via NotebookValidationJobs and auto-deploy to KServe InferenceServices.

## Architecture References

- [ADR-050: Anomaly Detector Model Training](../docs/adrs/050-anomaly-detector-model-training.md)
- [ADR-051: Predictive Analytics Model Training](../docs/adrs/051-predictive-analytics-model-training.md)
- [ADR-052: Model Training Data Sources](../docs/adrs/052-model-training-data-sources.md)

## Model Inventory

### Production Models

| Model | Notebook | Validation Job | InferenceService | Auto-Restart | Data Source |
|-------|----------|----------------|-------------------|--------------|-------------|
| **anomaly-detector** | `01-isolation-forest-implementation.ipynb` | `isolation-forest-implementation-validation` | ✅ anomaly-detector | ✅ Yes | Hybrid (Prometheus + synthetic) |
| **predictive-analytics** | `05-predictive-analytics-kserve.ipynb` | `predictive-analytics-kserve-validation` | ✅ predictive-analytics | ✅ Yes | Hybrid (Prometheus + synthetic) |

### Experimental Models (Not Deployed)

| Model | Notebook | Purpose |
|-------|----------|---------|
| timeseries-predictor | `02-time-series-anomaly-detection.ipynb` | ARIMA/Prophet time series forecasting |
| lstm-predictor | `03-lstm-based-prediction.ipynb` | LSTM autoencoder anomaly detection |
| ensemble | `04-ensemble-anomaly-methods.ipynb` | Ensemble of multiple detection methods |

## Training Schedule

### Automated Training

Models are automatically retrained **weekly** via NotebookValidationJobs:

```yaml
# Configured in charts/hub/values-notebooks-validation.yaml
wave3:
  notebooks:
    - name: "isolation-forest-implementation"
      blockNextWave: true
      inferenceServiceTrigger:
        name: "anomaly-detector"  # Auto-restart on success

    - name: "predictive-analytics-kserve"
      blockNextWave: true
      inferenceServiceTrigger:
        name: "predictive-analytics"  # Auto-restart on success
```

### Workflow

1. **Weekly Trigger**: ArgoCD sync wave 3 executes NotebookValidationJobs
2. **Data Collection**: Fetch Prometheus metrics (7-30 days historical)
3. **Data Blending**: Mix Prometheus data with synthetic anomalies
4. **Model Training**: Train model on hybrid dataset
5. **Model Validation**: Execute notebook validation checks
6. **Model Persistence**: Save to `/mnt/models/{model-name}/model.pkl`
7. **Auto-Deployment**: InferenceService automatically restarts
8. **Health Check**: Verify new model loads successfully

## Manual Training

### Anomaly Detector

If you need to manually retrain the anomaly-detector model:

```bash
# 1. Run the validation job manually
oc create job --from=notebookvalidationjob/isolation-forest-implementation-validation \
  manual-train-anomaly-$(date +%s) -n self-healing-platform

# 2. Monitor training progress
oc logs -f job/manual-train-anomaly-* -n self-healing-platform

# 3. Verify model updated
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  ls -lh /mnt/models/anomaly-detector/model.pkl

# 4. Check file modification time
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  stat /mnt/models/anomaly-detector/model.pkl

# 5. Verify InferenceService restarted
oc get pods -l serving.kserve.io/inferenceservice=anomaly-detector \
  -n self-healing-platform --sort-by=.metadata.creationTimestamp

# 6. Test model endpoint
PREDICTOR_POD=$(oc get pod -l serving.kserve.io/inferenceservice=anomaly-detector \
  -o jsonpath='{.items[0].metadata.name}' -n self-healing-platform)

oc exec $PREDICTOR_POD -n self-healing-platform -c kserve-container -- \
  curl -X POST http://localhost:8080/v1/models/anomaly-detector:predict \
  -H 'Content-Type: application/json' \
  -d '{"instances": [[0.5, 0.6, 0.4, 100, 80]]}'

# Expected response:
# {"predictions": [[-1]]}  or  {"predictions": [[1]]}
# -1 = anomaly, 1 = normal
```

### Predictive Analytics

If you need to manually retrain the predictive-analytics model:

```bash
# 1. Run the validation job manually
oc create job --from=notebookvalidationjob/predictive-analytics-kserve-validation \
  manual-train-predictive-$(date +%s) -n self-healing-platform

# 2. Monitor training progress
oc logs -f job/manual-train-predictive-* -n self-healing-platform

# 3. Verify model updated
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  ls -lh /mnt/models/predictive-analytics/model.pkl

# 4. Check file modification time
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  stat /mnt/models/predictive-analytics/model.pkl

# 5. Verify InferenceService restarted
oc get pods -l serving.kserve.io/inferenceservice=predictive-analytics \
  -n self-healing-platform --sort-by=.metadata.creationTimestamp

# 6. Test model endpoint
PREDICTOR_POD=$(oc get pod -l serving.kserve.io/inferenceservice=predictive-analytics \
  -o jsonpath='{.items[0].metadata.name}' -n self-healing-platform)

oc exec $PREDICTOR_POD -n self-healing-platform -c kserve-container -- \
  curl -X POST http://localhost:8080/v1/models/predictive-analytics:predict \
  -H 'Content-Type: application/json' \
  -d '{"instances": [[...]]}'  # 120 values (24 samples × 5 metrics)

# Expected response:
# {"predictions": [[<12 forecast values>]]}
```

## Data Source Configuration

### Environment Variables

Control data sources via environment variables in NotebookValidationJob:

```yaml
# Example: Override data source in validation job
env:
  - name: DATA_SOURCE
    value: "prometheus"  # synthetic|prometheus|hybrid
  - name: PROMETHEUS_URL
    value: "http://prometheus-k8s.openshift-monitoring.svc:9090"
  - name: TRAINING_DAYS
    value: "7"  # 7 for anomaly-detector, 30 for predictive-analytics
  - name: ANOMALY_RATE
    value: "0.03"  # 3% synthetic anomalies
```

### Data Source Modes

| Mode | Synthetic % | Prometheus % | Use Case |
|------|-------------|--------------|----------|
| **synthetic** | 100% | 0% | Development, testing, CI/CD |
| **prometheus** | 20% | 80% | Production (real cluster patterns) |
| **hybrid** | 50% | 50% | Staging, validation |

**Default**: `synthetic` (for reproducibility)

**Production Recommendation**: `prometheus` or `hybrid` (for real cluster adaptation)

### Testing Different Data Sources

```bash
# Test with synthetic data only (default)
oc create job --from=notebookvalidationjob/isolation-forest-implementation-validation \
  test-synthetic-$(date +%s) -n self-healing-platform

# Test with Prometheus data (80% real metrics)
oc create job --from=notebookvalidationjob/isolation-forest-implementation-validation \
  test-prometheus-$(date +%s) -n self-healing-platform \
  --overrides='{
    "spec": {
      "template": {
        "spec": {
          "containers": [{
            "name": "notebook-validator",
            "env": [
              {"name": "DATA_SOURCE", "value": "prometheus"},
              {"name": "TRAINING_DAYS", "value": "7"}
            ]
          }]
        }
      }
    }
  }'

# Test with hybrid data (50/50)
oc create job --from=notebookvalidationjob/isolation-forest-implementation-validation \
  test-hybrid-$(date +%s) -n self-healing-platform \
  --overrides='{
    "spec": {
      "template": {
        "spec": {
          "containers": [{
            "name": "notebook-validator",
            "env": [
              {"name": "DATA_SOURCE", "value": "hybrid"},
              {"name": "TRAINING_DAYS", "value": "7"}
            ]
          }]
        }
      }
    }
  }'

# Monitor logs to verify data source
oc logs -f job/test-* -n self-healing-platform | grep -E "(Using data source|Prometheus|Fetching metrics)"
```

## Model Storage

### File System Layout

```
/mnt/models/  (PVC: model-storage-pvc)
├── anomaly-detector/
│   └── model.pkl          # Isolation Forest pipeline (scaler + model)
└── predictive-analytics/
    └── model.pkl          # Random Forest forecasting pipeline
```

**Important**: KServe sklearn server expects models at `{model-name}/model.pkl`

### Inspecting Models

```bash
# List all models
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  ls -lah /mnt/models/

# Check anomaly-detector model
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  ls -lh /mnt/models/anomaly-detector/

# Check predictive-analytics model
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  ls -lh /mnt/models/predictive-analytics/

# Verify model file integrity (check size > 0)
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  file /mnt/models/anomaly-detector/model.pkl

# Expected output:
# /mnt/models/anomaly-detector/model.pkl: data
```

## Troubleshooting

### Model Not Loading

**Symptoms**: InferenceService pods in `CrashLoopBackOff` or `Error` state

```bash
# 1. Check InferenceService status
oc get inferenceservices -n self-healing-platform

# 2. Check predictor pod logs
oc logs -l serving.kserve.io/inferenceservice=anomaly-detector \
  -n self-healing-platform -c kserve-container

# Common errors:
# - "FileNotFoundError: [Errno 2] No such file or directory: '/mnt/models/...'"
#   → Model file missing, run training job
# - "RuntimeError: More than one model file detected"
#   → Multiple .pkl files in directory, clean up old files
# - "ModuleNotFoundError: No module named 'sklearn'"
#   → Wrong container image, check InferenceService spec
```

**Solutions**:

```bash
# Solution 1: Verify model file exists
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  test -f /mnt/models/anomaly-detector/model.pkl && echo "Model exists" || echo "Model missing"

# Solution 2: Re-run training job
oc create job --from=notebookvalidationjob/isolation-forest-implementation-validation \
  retrain-$(date +%s) -n self-healing-platform

# Solution 3: Check for multiple model files (KServe doesn't allow this)
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  ls -1 /mnt/models/anomaly-detector/*.pkl

# If multiple files exist, remove old ones:
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  rm /mnt/models/anomaly-detector/old_model.pkl
```

### Training Job Failures

**Symptoms**: NotebookValidationJob status shows `Failed`

```bash
# 1. Check validation job status
oc get notebookvalidationjobs -n self-healing-platform

# 2. Find recent validation jobs
oc get jobs -n self-healing-platform --sort-by=.metadata.creationTimestamp | grep validation

# 3. Check job pod logs
JOB_POD=$(oc get pods -l job-name=<job-name> -o jsonpath='{.items[0].metadata.name}')
oc logs $JOB_POD -n self-healing-platform

# Common errors:
# - "Prometheus not available"
#   → Prometheus service unreachable, will fallback to synthetic
# - "MemoryError" or "OOMKilled"
#   → Increase resources in values-notebooks-validation.yaml
# - "ModuleNotFoundError"
#   → Missing Python package, update notebook-validator image
```

**Solutions**:

```bash
# Solution 1: Check Prometheus connectivity
oc run test-prometheus --image=curlimages/curl:latest -it --rm -- \
  curl -I http://prometheus-k8s.openshift-monitoring.svc:9090/api/v1/status/config

# Expected: HTTP 200 OK

# Solution 2: Increase notebook validation job resources
# Edit charts/hub/values-notebooks-validation.yaml:
# resources:
#   tier2:
#     requests:
#       memory: "4Gi"  # Increase from 2Gi
#       cpu: "2000m"   # Increase from 1000m

# Solution 3: Re-run with synthetic data only
oc create job --from=notebookvalidationjob/isolation-forest-implementation-validation \
  retrain-synthetic-$(date +%s) -n self-healing-platform \
  --overrides='{"spec":{"template":{"spec":{"containers":[{"name":"notebook-validator","env":[{"name":"DATA_SOURCE","value":"synthetic"}]}]}}}}'
```

### Model Predictions Failing

**Symptoms**: Model endpoint returns errors or unexpected results

```bash
# 1. Test model endpoint directly
PREDICTOR_POD=$(oc get pod -l serving.kserve.io/inferenceservice=anomaly-detector \
  -o jsonpath='{.items[0].metadata.name}' -n self-healing-platform)

oc exec $PREDICTOR_POD -n self-healing-platform -c kserve-container -- \
  curl -X POST http://localhost:8080/v1/models/anomaly-detector:predict \
  -H 'Content-Type: application/json' \
  -d '{"instances": [[0.5, 0.6, 0.4, 100, 80]]}'

# Common errors:
# - "Invalid input shape"
#   → Wrong number of features, check model training
# - "Model not found"
#   → Model file corrupt or wrong format
# - "500 Internal Server Error"
#   → Check predictor pod logs for stack trace
```

**Solutions**:

```bash
# Solution 1: Verify model format
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  python3 -c "import joblib; model = joblib.load('/mnt/models/anomaly-detector/model.pkl'); print(type(model))"

# Expected output: <class 'sklearn.pipeline.Pipeline'>

# Solution 2: Check model input requirements
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  python3 -c "
import joblib
model = joblib.load('/mnt/models/anomaly-detector/model.pkl')
print(f'Model expects {model.n_features_in_} features')
"

# Solution 3: Retrain model and redeploy
oc create job --from=notebookvalidationjob/isolation-forest-implementation-validation \
  retrain-$(date +%s) -n self-healing-platform
```

### InferenceService Not Auto-Restarting

**Symptoms**: Training succeeds but InferenceService doesn't restart

```bash
# 1. Check if inferenceServiceTrigger is configured
oc get notebookvalidationjob isolation-forest-implementation-validation \
  -n self-healing-platform -o yaml | grep -A 5 inferenceServiceTrigger

# Expected:
# inferenceServiceTrigger:
#   name: anomaly-detector

# 2. Check NotebookValidationJob status
oc get notebookvalidationjob isolation-forest-implementation-validation \
  -n self-healing-platform -o yaml | grep -A 10 status

# 3. Check ArgoCD Application sync status
oc get application self-healing-platform -n openshift-gitops -o yaml | grep syncResult
```

**Solutions**:

```bash
# Solution 1: Verify operator version supports inferenceServiceTrigger
oc get deployment jupyter-notebook-validator-operator-controller-manager \
  -n operators -o jsonpath='{.spec.template.spec.containers[0].image}'

# Expected: v1.0.5 or later

# Solution 2: Manually restart InferenceService
oc delete pod -l serving.kserve.io/inferenceservice=anomaly-detector \
  -n self-healing-platform

# Solution 3: Update values-notebooks-validation.yaml if missing
# See "Model Inventory" section above for correct configuration
```

## Prometheus Queries Reference

### Anomaly Detector Metrics (7-day lookback)

```promql
# CPU usage
rate(node_cpu_seconds_total{mode="user"}[5m])

# Memory usage
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# Pod restarts
rate(kube_pod_container_status_restarts_total[5m])

# Network ingress
rate(container_network_receive_bytes_total[5m])

# Network egress
rate(container_network_transmit_bytes_total[5m])

# Pod status
kube_pod_status_phase
```

### Predictive Analytics Metrics (30-day lookback)

```promql
# Average CPU usage across cluster
avg(rate(node_cpu_seconds_total{mode!="idle"}[5m]))

# Average memory usage across cluster
avg(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))

# Average disk usage across cluster
avg(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes))

# Average network ingress across cluster
avg(rate(container_network_receive_bytes_total[5m]))

# Average network egress across cluster
avg(rate(container_network_transmit_bytes_total[5m]))
```

### Testing Prometheus Queries

```bash
# Test query directly
oc run test-prom --image=curlimages/curl:latest -it --rm -- \
  curl -G http://prometheus-k8s.openshift-monitoring.svc:9090/api/v1/query \
  --data-urlencode 'query=rate(node_cpu_seconds_total{mode="user"}[5m])'

# Test query_range for historical data
oc run test-prom --image=curlimages/curl:latest -it --rm -- \
  curl -G http://prometheus-k8s.openshift-monitoring.svc:9090/api/v1/query_range \
  --data-urlencode 'query=rate(node_cpu_seconds_total{mode="user"}[5m])' \
  --data-urlencode 'start='$(date -d '7 days ago' +%s) \
  --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=5m'
```

## Monitoring Model Health

### Check Model Serving Status

```bash
# List all InferenceServices
oc get inferenceservices -n self-healing-platform

# Check anomaly-detector health
oc get inferenceservice anomaly-detector -n self-healing-platform -o yaml | grep -A 5 status

# Check predictive-analytics health
oc get inferenceservice predictive-analytics -n self-healing-platform -o yaml | grep -A 5 status

# Expected status:
# status:
#   conditions:
#   - status: "True"
#     type: Ready
```

### Test Model Endpoints

```bash
# Test anomaly-detector
PREDICTOR_IP=$(oc get pod -l serving.kserve.io/inferenceservice=anomaly-detector \
  -o jsonpath='{.items[0].status.podIP}')

curl -X POST http://${PREDICTOR_IP}:8080/v1/models/anomaly-detector:predict \
  -H 'Content-Type: application/json' \
  -d '{"instances": [[0.5, 0.6, 0.4, 100, 80]]}'

# Test predictive-analytics
PREDICTOR_IP=$(oc get pod -l serving.kserve.io/inferenceservice=predictive-analytics \
  -o jsonpath='{.items[0].status.podIP}')

# Generate 120 values (24 samples × 5 metrics)
curl -X POST http://${PREDICTOR_IP}:8080/v1/models/predictive-analytics:predict \
  -H 'Content-Type: application/json' \
  -d '{"instances": [[0.45, 0.62, 0.38, ...]]}'
```

## Best Practices

### Model Training

1. **Use Hybrid Data in Production**: Combine Prometheus metrics with synthetic anomalies for best results
2. **Validate Before Deployment**: NotebookValidationJob ensures models work before auto-restart
3. **Monitor Training Frequency**: Weekly retraining balances freshness and resource usage
4. **Check Prometheus Availability**: Ensure Prometheus is accessible before production training

### Model Deployment

1. **Single Pipeline File**: Always save models as sklearn Pipeline (scaler + model combined)
2. **KServe Path Convention**: Use `/mnt/models/{model-name}/model.pkl`
3. **Avoid Multiple Files**: KServe sklearn server only supports one .pkl file per directory
4. **Test After Deployment**: Always verify model endpoint responds correctly

### Troubleshooting

1. **Check Logs First**: Start with InferenceService and NotebookValidationJob logs
2. **Verify File Exists**: Ensure model file is present and non-zero size
3. **Test Incrementally**: Start with synthetic data, then add Prometheus
4. **Use Manual Jobs**: Test training manually before relying on automation

## References

- [ADR-050: Anomaly Detector Model Training](../docs/adrs/050-anomaly-detector-model-training.md)
- [ADR-051: Predictive Analytics Model Training](../docs/adrs/051-predictive-analytics-model-training.md)
- [ADR-052: Model Training Data Sources](../docs/adrs/052-model-training-data-sources.md)
- [ADR-029: Jupyter Notebook Validator Operator](../docs/adrs/029-jupyter-notebook-validator-operator.md)
- [ADR-041: Model Storage and Versioning Strategy](../docs/adrs/041-model-storage-and-versioning-strategy.md)
- [KServe sklearn server documentation](https://github.com/kserve/kserve/tree/master/python/sklearnserver)
- [Prometheus query API documentation](https://prometheus.io/docs/prometheus/latest/querying/api/)
