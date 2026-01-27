# ADR-051: Predictive Analytics Model Training and Data Strategy

## Status
**ACCEPTED** - 2026-01-27

## Context

The **predictive-analytics** InferenceService provides resource usage forecasting for proactive scaling and capacity planning. Unlike the anomaly-detector model (ADR-050), this model already has a NotebookValidationJob configured. However, several gaps remain:

1. **No architectural documentation**: Training strategy not formally documented
2. **Synthetic-only data**: Only uses synthetic time series, not real Prometheus metrics
3. **Unclear forecast horizon**: No documentation of prediction window
4. **No production data integration**: Models trained without real cluster patterns
5. **Missing data strategy**: No plan for hybrid synthetic/Prometheus approach

### Problem Scenario

The predictive-analytics model currently:
- ✅ Has NotebookValidationJob configured (isolation-forest does not)
- ✅ Automatically restarts InferenceService on successful training
- ❌ Only trains on synthetic data (disconnected from real cluster)
- ❌ No documented forecast methodology
- ❌ No strategy for using Prometheus historical data

### Requirements

1. Document the model architecture and forecasting strategy
2. Define forecast horizon and lookback window
3. Specify data source strategy (synthetic vs Prometheus vs hybrid)
4. Maintain existing NotebookValidationJob automation
5. Enable Prometheus historical data integration
6. Support both development (synthetic) and production (real metrics) scenarios

## Decision

Establish **predictive-analytics** as a production-grade forecasting model with documented training strategy:

### Model Specifications

| Property | Value |
|----------|-------|
| **Model Type** | Random Forest Regressor (ensemble forecasting) |
| **Purpose** | Predict future resource usage (1 hour ahead) |
| **Training Notebook** | `05-predictive-analytics-kserve.ipynb` |
| **Model Location** | `/mnt/models/predictive-analytics/model.pkl` |
| **InferenceService** | `predictive-analytics` |
| **Training Frequency** | Weekly via NotebookValidationJob |
| **Auto-Deployment** | ✅ Already configured (maintain) |
| **Forecast Horizon** | 12 time steps (1 hour at 5-min intervals) |
| **Lookback Window** | 24 time steps (2 hours of history) |

### Data Source Strategy

**Development Phase**: 100% synthetic time series
- Fast iteration and testing
- Reproducible results
- Controlled seasonal patterns (daily, weekly)
- No Prometheus dependency

**Staging Phase**: Hybrid (50% synthetic, 50% Prometheus)
- Validate model on real cluster time series
- Test Prometheus historical query integration
- Compare synthetic vs real patterns

**Production Phase**: Hybrid (80% Prometheus, 20% synthetic)
- Majority real historical metrics (30-day lookback)
- Synthetic data for edge cases and seasonality testing
- Continuous adaptation to cluster growth patterns

### Prometheus Metrics Predicted

Training data fetched from Prometheus (30-day historical lookback):

| Metric | Prometheus Query | Forecast Purpose |
|--------|------------------|------------------|
| CPU usage | `avg(rate(node_cpu_seconds_total{mode!="idle"}[5m]))` | Predict CPU demand |
| Memory usage | `avg(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))` | Predict memory pressure |
| Disk usage | `avg(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes))` | Predict storage needs |
| Network ingress | `avg(rate(container_network_receive_bytes_total[5m]))` | Predict inbound traffic |
| Network egress | `avg(rate(container_network_transmit_bytes_total[5m]))` | Predict outbound traffic |

Sample interval: **5 minutes** (matches production inference cadence)
Historical range: **30 days** (captures monthly seasonality patterns)

### Training Configuration

**NotebookValidationJob Settings** (already configured):
```yaml
name: predictive-analytics-kserve-validation
notebook: notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb
tier: tier3  # Higher tier due to computational requirements
blockNextWave: true  # Ensure forecasting works before dependent services
inferenceServiceTrigger:
  name: predictive-analytics  # Auto-restart after successful training
validationConfig:
  level: production
  strictMode: true
  detectSilentFailures: true
comparisonConfig:
  strategy: normalized
  floatingPointTolerance: 0.01
  ignoreTimestamps: true
```

**Environment Variables** (to be added):
```yaml
env:
  - name: DATA_SOURCE
    value: "hybrid"  # synthetic|prometheus|hybrid
  - name: PROMETHEUS_URL
    value: "http://prometheus-k8s.openshift-monitoring.svc:9090"
  - name: TRAINING_DAYS
    value: "30"  # Prometheus lookback window (30 days for seasonality)
  - name: FORECAST_HORIZON
    value: "12"  # Number of future time steps (1 hour)
  - name: LOOKBACK_WINDOW
    value: "24"  # Number of historical time steps (2 hours)
```

### Model Parameters

**Random Forest Hyperparameters**:
```python
RandomForestRegressor(
    n_estimators=100,          # Number of trees in forest
    max_depth=20,              # Maximum tree depth
    min_samples_split=5,       # Minimum samples to split node
    min_samples_leaf=2,        # Minimum samples at leaf node
    random_state=42,           # Reproducibility
    n_jobs=-1                  # Parallel processing
)
```

**Feature Engineering**:
- Lookback window: 24 samples (2 hours)
- Rolling statistics: mean, std, min, max over [6, 12, 24] windows
- Lag features: 1, 3, 6, 12 time steps
- Time features: hour of day, day of week, is_weekend
- Trend features: linear trend over lookback window
- Total features: ~40 per predicted metric

**Multi-Output Strategy**:
```python
# Train separate model for each forecast time step
models = {}
for horizon in range(1, 13):  # 12 time steps ahead
    models[f'horizon_{horizon}'] = RandomForestRegressor(...)
    models[f'horizon_{horizon}'].fit(X_train, y_train[:, horizon-1])
```

### Forecasting Workflow

**Input**: Current metrics (last 2 hours, 24 samples)
```json
{
  "instances": [
    [0.45, 0.62, 0.38, 1024.5, 512.8, ...]  // 24 samples × 5 metrics = 120 values
  ]
}
```

**Output**: Future predictions (next 1 hour, 12 samples)
```json
{
  "predictions": [
    {
      "cpu": [0.47, 0.48, 0.50, 0.52, 0.54, 0.56, 0.58, 0.59, 0.60, 0.61, 0.62, 0.63],
      "memory": [0.64, 0.65, 0.66, 0.67, 0.68, 0.69, 0.70, 0.71, 0.72, 0.73, 0.74, 0.75],
      "disk": [...],
      "network_in": [...],
      "network_out": [...]
    }
  ]
}
```

### Automated Workflow

1. **Weekly Trigger**: NotebookValidationJob scheduled via CronJob
2. **Data Collection**: Fetch Prometheus historical metrics (last 30 days)
3. **Synthetic Blending**: Add synthetic time series for edge cases
4. **Feature Engineering**: Create lagged features and rolling statistics
5. **Model Training**: Train 12 Random Forest models (one per forecast step)
6. **Model Validation**: Test on held-out validation set (RMSE, MAE metrics)
7. **Model Persistence**: Save to `/mnt/models/predictive-analytics/model.pkl`
8. **Auto-Deployment**: Trigger InferenceService restart (already configured)
9. **Health Check**: Verify new model loads and predictions are reasonable

## Rationale

### Why Random Forest for Forecasting

**Alternatives Considered**:

1. **LSTM (Deep Learning)**
   - ❌ Requires significantly more training data
   - ❌ Longer training time (hours vs minutes)
   - ❌ GPU dependency for reasonable training speed
   - ❌ Harder to interpret predictions
   - ✅ Better at capturing complex temporal patterns

2. **ARIMA / Prophet**
   - ❌ Designed for univariate time series (we need multivariate)
   - ❌ Assumes specific seasonality patterns (hourly, daily, weekly)
   - ❌ Slower inference for multiple metrics
   - ✅ Better theoretical guarantees for stationary series
   - ✅ Better uncertainty quantification

3. **XGBoost**
   - ✅ Comparable accuracy to Random Forest
   - ✅ Often faster training
   - ⚠️ More hyperparameters to tune
   - ⚠️ Less robust to outliers

**Random Forest Advantages**:
- ✅ Fast training and inference (no GPU required)
- ✅ Handles multivariate forecasting naturally
- ✅ Robust to outliers and missing data
- ✅ Requires minimal hyperparameter tuning
- ✅ Works well with moderate-sized datasets
- ✅ Feature importance for interpretability

### Why 1-Hour Forecast Horizon

**Shorter Horizon (15-30 minutes)** (Rejected):
- ❌ Too short for proactive scaling decisions
- ❌ Not enough lead time for human intervention
- ✅ Higher accuracy

**Longer Horizon (4-12 hours)** (Rejected):
- ❌ Prediction accuracy degrades significantly
- ❌ Too many uncertainties (workload changes, deployments)
- ✅ Better for capacity planning

**1-Hour Horizon** (Chosen):
- ✅ Sufficient time for autoscaling actions
- ✅ Reasonable prediction accuracy
- ✅ Aligns with typical operational response time
- ✅ Captures short-term trends without excessive drift

### Why 30-Day Historical Lookback

**7-Day Lookback** (Rejected):
- ❌ Misses monthly seasonality patterns
- ❌ Not enough data for robust training
- ✅ Faster queries

**90-Day Lookback** (Rejected):
- ❌ Slower Prometheus queries
- ❌ Older data may not reflect current cluster state
- ✅ More robust to weekly anomalies

**30-Day Lookback** (Chosen):
- ✅ Captures weekly and monthly patterns
- ✅ Sufficient data for model training
- ✅ Recent enough to reflect current cluster behavior
- ✅ Balances query performance and data richness

## Consequences

### Positive

- ✅ **Documented Forecasting Strategy**: Clear model architecture and methodology
- ✅ **Production Data Integration**: Models trained on real cluster patterns
- ✅ **Already Automated**: NotebookValidationJob and auto-restart exist
- ✅ **Interpretable Predictions**: Feature importance shows what drives forecasts
- ✅ **Multivariate Support**: Predicts all key resource metrics simultaneously
- ✅ **Fast Training**: No GPU required, completes in minutes
- ✅ **Fallback Strategy**: Graceful degradation if Prometheus unavailable

### Negative

- ⚠️ **Prometheus Dependency**: Production training requires Prometheus historical data
- ⚠️ **Limited Horizon**: Only 1 hour ahead (not suitable for long-term planning)
- ⚠️ **No Uncertainty Quantification**: Point predictions only (no confidence intervals)
- ⚠️ **Resource Overhead**: Weekly training consumes cluster resources
- ⚠️ **Potential Downtime**: InferenceService restarts during deployment

### Neutral

- 📝 **Fixed Forecast Horizon**: 1-hour window may not suit all use cases
- 📝 **Multi-Model Complexity**: 12 separate models per metric (60 total)
- 📝 **No Online Learning**: Models retrain weekly, not continuously

## Implementation

### Files Created/Modified

1. **ADR Documentation**: `docs/adrs/051-predictive-analytics-model-training.md` (this file)
2. **Validation Job Config**: `charts/hub/values-notebooks-validation.yaml`
   - ✅ Already configured (no changes needed)
   - Add environment variables for Prometheus integration
3. **Notebook Updates**: `notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb`
   - Add Prometheus historical data fetching functions
   - Add hybrid data source logic
   - Add environment variable configuration
4. **Training Guide**: `docs/model-training-guide.md`
   - Document manual training procedure
   - Add troubleshooting runbook

### Validation

```bash
# Verify NotebookValidationJob exists (should already exist)
oc get notebookvalidationjobs -n self-healing-platform | grep predictive-analytics

# Manually trigger training
oc create job --from=notebookvalidationjob/predictive-analytics-kserve-validation \
  manual-train-$(date +%s) -n self-healing-platform

# Monitor training progress
oc logs -f job/manual-train-* -n self-healing-platform

# Verify model file updated
oc exec deployment/model-troubleshooting-utilities -n self-healing-platform -- \
  ls -lh /mnt/models/predictive-analytics/model.pkl

# Verify InferenceService restarted
oc get pods -l serving.kserve.io/inferenceservice=predictive-analytics \
  -n self-healing-platform --sort-by=.metadata.creationTimestamp

# Test forecast endpoint
PREDICTOR_IP=$(oc get pod -l serving.kserve.io/inferenceservice=predictive-analytics \
  -o jsonpath='{.items[0].status.podIP}')
curl -X POST http://${PREDICTOR_IP}:8080/v1/models/predictive-analytics:predict \
  -H 'Content-Type: application/json' \
  -d '{"instances": [[0.45, 0.62, 0.38, ...]]}'  # 120 values (24 samples × 5 metrics)

# Expected: 12-step forecast for each metric
```

## Related ADRs

- [ADR-004: KServe for Model Serving Infrastructure](004-kserve-model-serving.md)
- [ADR-007: Prometheus Monitoring Integration](007-prometheus-monitoring-integration.md)
- [ADR-012: Notebook Architecture for End-to-End Workflows](012-notebook-architecture-for-end-to-end-workflows.md)
- [ADR-013: Data Collection and Preprocessing Workflows](013-data-collection-and-preprocessing-workflows.md)
- [ADR-029: Jupyter Notebook Validator Operator](029-jupyter-notebook-validator-operator.md)
- [ADR-037: MLOps Workflow Strategy](037-mlops-workflow-strategy.md)
- [ADR-041: Model Storage and Versioning Strategy](041-model-storage-and-versioning-strategy.md)
- [ADR-050: Anomaly Detector Model Training](050-anomaly-detector-model-training.md) (companion ADR)
- [ADR-052: Model Training Data Source Selection Strategy](052-model-training-data-sources.md) (companion ADR)

## References

- Random Forest paper: Breiman (2001) "Random Forests"
- scikit-learn documentation: https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.RandomForestRegressor.html
- Prometheus query API: https://prometheus.io/docs/prometheus/latest/querying/api/
- KServe sklearn server: https://github.com/kserve/kserve/tree/master/python/sklearnserver
- Notebook: `notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb`

## Next Steps

**Immediate (This ADR)**:
1. ✅ NotebookValidationJob already exists (maintain configuration)
2. ✅ Update notebook to support Prometheus historical data fetching
3. ✅ Add environment variables for data source configuration
4. ✅ Document manual training procedure

**Future Enhancements**:
1. Add uncertainty quantification (prediction intervals)
2. Implement multi-horizon forecasting (15min, 1hr, 4hr, 24hr)
3. Add model performance monitoring (forecast accuracy tracking)
4. Evaluate LSTM for longer-term forecasting
5. Implement online learning for continuous adaptation
6. Add SHAP for forecast explainability (which features drive predictions)
7. Integrate with cluster autoscaler for proactive scaling
