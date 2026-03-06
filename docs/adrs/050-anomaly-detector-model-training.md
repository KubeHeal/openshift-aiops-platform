# ADR-050: Anomaly Detector Model Training and Data Strategy

## Status
accepted - 2026-01-27

## Context

The **anomaly-detector** InferenceService is the platform's primary real-time anomaly detection model, deployed to production via KServe. However, the model training process lacked clear documentation, leading to:

1. **Flaky models**: Inconsistent training results due to undocumented procedures
2. **Missing automation**: No NotebookValidationJob configured for regular retraining
3. **Unclear data sources**: Only synthetic data used, despite Prometheus metrics being available
4. **Manual intervention**: Models trained ad-hoc without automated deployment
5. **No model-to-notebook mapping**: When models fail, unclear which notebook to run

### Problem Scenario

When the anomaly-detector InferenceService encounters issues:
- ❌ No documented process for retraining the model
- ❌ No scheduled retraining (models become stale)
- ❌ No automatic deployment after training
- ❌ No validation that new models work before deployment
- ❌ Training data disconnected from production cluster metrics

### Requirements

1. Document the model architecture and training strategy
2. Define data source strategy (synthetic vs Prometheus vs hybrid)
3. Specify training frequency and automation approach
4. Map the model to its training notebook
5. Enable automatic InferenceService restart on successful training
6. Support both development (synthetic) and production (real metrics) scenarios

## Decision

Establish **anomaly-detector** as a production-grade model with documented training strategy:

### Model Specifications

| Property | Value |
|----------|-------|
| **Model Type** | Isolation Forest (scikit-learn) |
| **Purpose** | Real-time anomaly detection in cluster metrics |
| **Training Notebook** | `01-isolation-forest-implementation.ipynb` |
| **Model Location** | `/mnt/models/anomaly-detector/model.pkl` |
| **InferenceService** | `anomaly-detector` |
| **Training Frequency** | Weekly via NotebookValidationJob |
| **Auto-Deployment** | Yes (InferenceService restarts on training success) |

### Data Source Strategy

**Development Phase**: 100% synthetic data
- Fast iteration and testing
- Reproducible results
- Controlled anomaly injection
- No Prometheus dependency

**Staging Phase**: Hybrid (50% synthetic, 50% Prometheus)
- Validate model on real cluster behavior
- Maintain labeled anomalies from synthetic data
- Test Prometheus integration

**Production Phase**: Hybrid (80% Prometheus, 20% synthetic)
- Majority real cluster metrics
- Synthetic anomalies for labeled training data
- Continuous adaptation to cluster patterns

### Prometheus Metrics Used

Training data fetched from Prometheus (7-day lookback):

| Metric | Prometheus Query | Purpose |
|--------|------------------|---------|
| CPU usage | `rate(node_cpu_seconds_total{mode="user"}[5m])` | Detect CPU anomalies |
| Memory usage | `1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)` | Detect memory pressure |
| Pod restarts | `rate(kube_pod_container_status_restarts_total[5m])` | Detect crash loops |
| Network ingress | `rate(container_network_receive_bytes_total[5m])` | Detect traffic anomalies |
| Network egress | `rate(container_network_transmit_bytes_total[5m])` | Detect data exfiltration |
| Pod status | `kube_pod_status_phase` | Detect stuck pods |

Sample interval: **5 minutes** (matches production inference cadence)

### Training Configuration

**NotebookValidationJob Settings**:
```yaml
name: isolation-forest-implementation-validation
notebook: notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb
tier: tier2
blockNextWave: true  # Ensure model training completes before dependent services
inferenceServiceTrigger:
  name: anomaly-detector  # Auto-restart after successful training
validationConfig:
  level: production
  strictMode: true
  detectSilentFailures: true
comparisonConfig:
  strategy: normalized
  floatingPointTolerance: 0.01
  ignoreTimestamps: true
```

**Environment Variables**:
```yaml
env:
  - name: DATA_SOURCE
    value: "hybrid"  # synthetic|prometheus|hybrid
  - name: PROMETHEUS_URL
    value: "http://prometheus-k8s.openshift-monitoring.svc:9090"
  - name: TRAINING_DAYS
    value: "7"  # Prometheus lookback window
  - name: ANOMALY_RATE
    value: "0.03"  # 3% synthetic anomalies
```

### Model Parameters

**Isolation Forest Hyperparameters**:
```python
IsolationForest(
    n_estimators=100,        # Number of trees
    max_samples='auto',      # Subsample size
    contamination=0.03,      # Expected anomaly rate (3%)
    random_state=42,         # Reproducibility
    n_jobs=-1                # Parallel processing
)
```

**Feature Engineering**:
- Window size: 24 samples (2 hours at 5-min intervals)
- Rolling statistics: mean, std, min, max
- Lag features: 1, 3, 6 time steps
- Total features: ~25 per metric

### Automated Workflow

1. **Weekly Trigger**: NotebookValidationJob scheduled via CronJob
2. **Data Collection**: Fetch Prometheus metrics (last 7 days)
3. **Anomaly Injection**: Add synthetic anomalies (3% of samples)
4. **Model Training**: Train Isolation Forest on hybrid dataset
5. **Model Validation**: Test on held-out validation set
6. **Model Persistence**: Save to `/mnt/models/anomaly-detector/model.pkl`
7. **Auto-Deployment**: Trigger InferenceService restart
8. **Health Check**: Verify new model loads successfully

## Rationale

### Why Isolation Forest

**Alternatives Considered**:

1. **One-Class SVM**
   - ❌ Slower inference (kernel computations)
   - ❌ Harder to tune (gamma, nu parameters)
   - ❌ Not scalable to high-dimensional data
   - ✅ Better theoretical guarantees

2. **Autoencoder (Deep Learning)**
   - ❌ Requires significantly more training data
   - ❌ Longer training time
   - ❌ GPU dependency for training
   - ✅ Can learn complex patterns

3. **Prophet / ARIMA**
   - ❌ Designed for univariate time series
   - ❌ Not suitable for multivariate anomaly detection
   - ❌ Assumes specific seasonality patterns
   - ✅ Better for forecasting

**Isolation Forest Advantages**:
- ✅ Fast training and inference
- ✅ Handles high-dimensional data well
- ✅ Requires minimal hyperparameter tuning
- ✅ Works well with small datasets
- ✅ No GPU required
- ✅ Naturally handles multivariate anomalies

### Why Hybrid Data Source

**Synthetic-Only Approach** (Rejected):
- ❌ Doesn't adapt to real cluster behavior
- ❌ May miss production-specific patterns
- ✅ Reproducible and controllable

**Prometheus-Only Approach** (Rejected):
- ❌ No labeled anomalies for training
- ❌ Requires unsupervised learning only
- ✅ Real cluster patterns

**Hybrid Approach** (Chosen):
- ✅ Real cluster patterns from Prometheus
- ✅ Labeled anomalies from synthetic injection
- ✅ Adapts to cluster over time
- ✅ Fallback to synthetic if Prometheus unavailable
- ✅ Best of both worlds

### Why Weekly Retraining

**Daily Retraining** (Rejected):
- ❌ Excessive resource consumption
- ❌ Cluster patterns don't change that fast
- ❌ Risk of overfitting to recent noise

**Monthly Retraining** (Rejected):
- ❌ Too infrequent to adapt to cluster changes
- ❌ Seasonal patterns may drift

**Weekly Retraining** (Chosen):
- ✅ Balances resource usage and freshness
- ✅ Captures weekly seasonality patterns
- ✅ Adapts to gradual cluster changes
- ✅ Aligns with typical operational cadence

## Consequences

### Positive

- ✅ **Documented Training Process**: Clear runbook for model retraining
- ✅ **Automated Deployment**: No manual intervention required
- ✅ **Production Data Integration**: Models adapt to real cluster behavior
- ✅ **Validation Before Deployment**: NotebookValidationJob ensures models work
- ✅ **Clear Model Ownership**: Notebook-to-model mapping documented
- ✅ **Consistent Model Quality**: Repeatable training process reduces flakiness
- ✅ **Fallback Strategy**: Graceful degradation if Prometheus unavailable

### Negative

- ⚠️ **Prometheus Dependency**: Production training requires Prometheus access
- ⚠️ **Resource Overhead**: Weekly training jobs consume cluster resources
- ⚠️ **Potential Downtime**: InferenceService restarts during deployment
- ⚠️ **No Human Approval**: Models auto-deploy without review

### Neutral

- 📝 **Fixed Schedule**: Weekly retraining may not align with incident patterns
- 📝 **Single Model Architecture**: No A/B testing or canary deployments
- 📝 **No Model Versioning**: Latest model always deployed (no rollback)

## Implementation

### Files Created/Modified

1. **ADR Documentation**: `docs/adrs/050-anomaly-detector-model-training.md` (this file)
2. **Validation Job Config**: `charts/hub/values-notebooks-validation.yaml`
   - Add `inferenceServiceTrigger` for `isolation-forest-implementation`
   - Add validation config
3. **Notebook Updates**: `notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb`
   - Add Prometheus data fetching functions
   - Add hybrid data source logic
   - Add environment variable configuration
4. **Training Guide**: `docs/model-training-guide.md`
   - Document manual training procedure
   - Add troubleshooting runbook

### Validation

```bash
# Verify NotebookValidationJob exists
oc get notebookvalidationjobs -n self-healing-platform | grep isolation-forest

# Manually trigger training
oc create job --from=notebookvalidationjob/isolation-forest-implementation-validation \
  manual-train-$(date +%s) -n self-healing-platform

# Monitor training progress
oc logs -f job/manual-train-* -n self-healing-platform

# Verify model file updated
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  ls -lh /mnt/models/anomaly-detector/model.pkl

# Verify InferenceService restarted
oc get pods -l serving.kserve.io/inferenceservice=anomaly-detector \
  -n self-healing-platform --sort-by=.metadata.creationTimestamp

# Test model endpoint
PREDICTOR_IP=$(oc get pod -l serving.kserve.io/inferenceservice=anomaly-detector \
  -o jsonpath='{.items[0].status.podIP}')
curl -X POST http://${PREDICTOR_IP}:8080/v1/models/anomaly-detector:predict \
  -H 'Content-Type: application/json' \
  -d '{"instances": [[0.5, 0.6, 0.4, 100, 80]]}'
```

## Related ADRs

- [ADR-004: KServe for Model Serving Infrastructure](004-kserve-model-serving.md)
- [ADR-007: Prometheus Monitoring Integration](007-prometheus-monitoring-integration.md)
- [ADR-012: Notebook Architecture for End-to-End Workflows](012-notebook-architecture-for-end-to-end-workflows.md)
- [ADR-013: Data Collection and Preprocessing Workflows](013-data-collection-and-preprocessing-workflows.md)
- [ADR-029: Jupyter Notebook Validator Operator](029-jupyter-notebook-validator-operator.md)
- [ADR-037: MLOps Workflow Strategy](037-mlops-workflow-strategy.md)
- [ADR-041: Model Storage and Versioning Strategy](041-model-storage-and-versioning-strategy.md)
- [ADR-051: Predictive Analytics Model Training](051-predictive-analytics-model-training.md) (companion ADR)
- [ADR-052: Model Training Data Source Selection Strategy](052-model-training-data-sources.md) (companion ADR)

## References

- Isolation Forest paper: Liu et al. (2008) "Isolation Forest"
- scikit-learn documentation: https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.IsolationForest.html
- Prometheus query API: https://prometheus.io/docs/prometheus/latest/querying/api/
- KServe sklearn server: https://github.com/kserve/kserve/tree/master/python/sklearnserver
- Notebook: `notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb`

## Next Steps

**Immediate (This ADR)**:
1. ✅ Create NotebookValidationJob for isolation-forest notebook
2. ✅ Update notebook to support Prometheus data fetching
3. ✅ Configure automatic InferenceService restart
4. ✅ Document manual training procedure

**Future Enhancements**:
1. Add model performance monitoring (drift detection)
2. Implement A/B testing for model versions
3. Add human-in-the-loop approval for production deployments
4. Implement model rollback capability
5. Add continuous learning from production feedback
6. Evaluate SHAP for model explainability
