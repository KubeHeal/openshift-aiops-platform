# ADR-052: Model Training Data Source Selection Strategy

## Status
**ACCEPTED** - 2026-01-27

## Context

Machine learning models in the OpenShift AIOps platform require training data to learn patterns and make predictions. Currently, all model-training notebooks use **only synthetic data**, which creates a disconnect between training and production environments.

### Problem Scenario

**Current State**:
- ✅ Synthetic data is reproducible and fast to generate
- ✅ Synthetic data allows controlled anomaly injection (labeled training data)
- ❌ Synthetic data doesn't reflect real cluster behavior
- ❌ Models trained on synthetic data may not generalize to production
- ❌ No integration with Prometheus, despite being available

**Real-World Example**:
A model trained on synthetic CPU patterns (smooth sine waves) fails to detect anomalies in production when:
- Batch jobs create spiky workload patterns
- Autoscaling causes rapid resource changes
- Pod evictions create restart cascades

**Requirements**:
1. Enable models to learn from real cluster behavior (Prometheus metrics)
2. Maintain labeled training data for supervised learning (synthetic anomalies)
3. Support development environments without Prometheus access
4. Provide fallback mechanisms for resilience
5. Document when to use synthetic vs Prometheus vs hybrid data

## Decision

Implement a **hybrid data source strategy** with three operational modes:

### Data Source Modes

| Mode | Synthetic % | Prometheus % | Use Case |
|------|-------------|--------------|----------|
| **synthetic** | 100% | 0% | Development, testing, CI/CD |
| **prometheus** | 20% | 80% | Production, real cluster patterns |
| **hybrid** | 50% | 50% | Staging, validation, experimentation |

Configurable via environment variable:
```bash
export DATA_SOURCE=hybrid  # synthetic|prometheus|hybrid
```

### Mode Details

#### 1. Synthetic Mode (Development)

**When to Use**:
- Local development without cluster access
- CI/CD pipeline testing
- Reproducible unit tests
- Initial model prototyping

**Advantages**:
- ✅ Fast data generation (no network calls)
- ✅ Reproducible results (fixed random seed)
- ✅ Controlled anomaly patterns (ground truth labels)
- ✅ No dependencies on external services

**Data Characteristics**:
```python
# Synthetic time series patterns
patterns = {
    'cpu_usage': sine_wave + daily_seasonality + weekly_seasonality + noise,
    'memory_usage': linear_trend + daily_seasonality + noise,
    'pod_restarts': poisson_process(lambda=0.01),  # Rare events
    'network_traffic': sine_wave + burst_anomalies + noise
}

# Injected anomalies (3% of samples)
anomalies = {
    'cpu_spike': gaussian_spike(mean=0.9, std=0.05),
    'memory_leak': linear_increase(slope=0.01),
    'restart_storm': poisson_burst(lambda=5.0),
    'network_ddos': exponential_spike(scale=10.0)
}
```

**Configuration**:
```yaml
env:
  - name: DATA_SOURCE
    value: "synthetic"
  - name: N_SAMPLES
    value: "2000"  # 7 days at 5-min intervals
  - name: ANOMALY_RATE
    value: "0.03"  # 3% anomalies
  - name: RANDOM_SEED
    value: "42"  # Reproducibility
```

#### 2. Prometheus Mode (Production)

**When to Use**:
- Production cluster with Prometheus deployed
- Model retraining on real workload patterns
- Validating model performance on actual data
- Continuous learning from production

**Advantages**:
- ✅ Real cluster behavior patterns
- ✅ Actual seasonality (daily, weekly, monthly)
- ✅ Production workload characteristics
- ✅ Adapts to cluster growth over time

**Data Characteristics**:
```python
# Prometheus queries (30-day lookback for predictive-analytics)
queries = {
    'cpu_usage': 'avg(rate(node_cpu_seconds_total{mode!="idle"}[5m]))',
    'memory_usage': 'avg(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))',
    'pod_restarts': 'sum(rate(kube_pod_container_status_restarts_total[5m]))',
    'network_in': 'sum(rate(container_network_receive_bytes_total[5m]))',
    'network_out': 'sum(rate(container_network_transmit_bytes_total[5m]))'
}

# 20% synthetic anomalies still injected for labeled training
# (Prometheus data is mostly normal, needs anomaly examples)
```

**Configuration**:
```yaml
env:
  - name: DATA_SOURCE
    value: "prometheus"
  - name: PROMETHEUS_URL
    value: "http://prometheus-k8s.openshift-monitoring.svc:9090"
  - name: TRAINING_DAYS
    value: "30"  # Historical lookback (predictive-analytics)
    # value: "7"   # For anomaly-detector (shorter lookback)
  - name: ANOMALY_RATE
    value: "0.03"  # Still inject 3% synthetic anomalies
```

**Fallback Behavior**:
```python
# If Prometheus unavailable, fall back to synthetic
try:
    response = requests.get(f"{PROMETHEUS_URL}/api/v1/status/config", timeout=5)
    if response.status_code != 200:
        print("⚠️ Prometheus unavailable, falling back to synthetic data")
        DATA_SOURCE = 'synthetic'
except Exception as e:
    print(f"⚠️ Prometheus error: {e}, falling back to synthetic data")
    DATA_SOURCE = 'synthetic'
```

#### 3. Hybrid Mode (Staging & Validation)

**When to Use**:
- Staging environments
- Validating model generalization
- Comparing synthetic vs real patterns
- Gradual transition to production data

**Advantages**:
- ✅ Best of both worlds (real patterns + labeled anomalies)
- ✅ Validates model works on both synthetic and real data
- ✅ Provides diverse training examples
- ✅ Balances reproducibility and realism

**Data Blending Strategy**:
```python
# 50/50 split between synthetic and Prometheus
synthetic_data = generate_synthetic_anomalies(n_samples=1000)
prometheus_data = fetch_prometheus_metrics(days=7)

# Inject synthetic anomalies into Prometheus data (for labels)
prometheus_data = inject_synthetic_anomalies(prometheus_data, anomaly_rate=0.03)

# Concatenate datasets
train_data = pd.concat([synthetic_data, prometheus_data])
train_data = train_data.sample(frac=1).reset_index(drop=True)  # Shuffle
```

**Configuration**:
```yaml
env:
  - name: DATA_SOURCE
    value: "hybrid"
  - name: PROMETHEUS_URL
    value: "http://prometheus-k8s.openshift-monitoring.svc:9090"
  - name: SYNTHETIC_RATIO
    value: "0.5"  # 50% synthetic, 50% Prometheus
  - name: TRAINING_DAYS
    value: "7"
  - name: ANOMALY_RATE
    value: "0.03"
```

### Model-Specific Recommendations

| Model | Recommended Mode | Rationale |
|-------|------------------|-----------|
| **anomaly-detector** | `prometheus` (prod)<br>`hybrid` (staging)<br>`synthetic` (dev) | Needs real anomaly patterns from production |
| **predictive-analytics** | `prometheus` (prod)<br>`hybrid` (staging)<br>`synthetic` (dev) | Needs real seasonality patterns (30 days) |
| **timeseries-predictor** | `synthetic` | Not deployed to production (experimental) |
| **lstm-predictor** | `synthetic` | Not deployed to production (experimental) |
| **ensemble-predictor** | `synthetic` | Not deployed to production (experimental) |

### Prometheus Query Strategy

**Time Range Selection**:
- **anomaly-detector**: 7-day lookback (captures weekly patterns)
- **predictive-analytics**: 30-day lookback (captures monthly seasonality)

**Sample Interval**: 5 minutes (matches production inference cadence)

**Query Optimization**:
```python
# Use Thanos for long-term storage (if available)
THANOS_URL = os.getenv('THANOS_URL', PROMETHEUS_URL)

# Chunk large queries to avoid timeouts
def fetch_prometheus_chunked(query, start, end, chunk_days=7):
    chunks = []
    current = start
    while current < end:
        chunk_end = min(current + timedelta(days=chunk_days), end)
        data = fetch_prometheus_range(query, current, chunk_end)
        chunks.append(data)
        current = chunk_end
    return pd.concat(chunks)
```

**Error Handling**:
```python
# Retry logic for transient failures
@retry(max_attempts=3, backoff=exponential)
def fetch_prometheus_metrics(query, start, end):
    response = requests.get(
        f"{PROMETHEUS_URL}/api/v1/query_range",
        params={'query': query, 'start': start, 'end': end, 'step': '5m'}
    )
    response.raise_for_status()
    return parse_prometheus_response(response.json())
```

## Rationale

### Why Not Synthetic-Only

**Rejected Approach**:
```python
# Only use synthetic data forever
DATA_SOURCE = 'synthetic'
```

**Problems**:
- ❌ Models never adapt to real cluster behavior
- ❌ May miss production-specific patterns (burst workloads, autoscaling)
- ❌ Can't validate model performance on real data
- ❌ Ignores available Prometheus infrastructure

**When Acceptable**:
- ✅ Development and testing environments
- ✅ CI/CD pipelines (reproducibility required)
- ✅ Experimental models not deployed to production

### Why Not Prometheus-Only

**Rejected Approach**:
```python
# Only use Prometheus data, no synthetic
DATA_SOURCE = 'prometheus'
# No anomaly injection
```

**Problems**:
- ❌ No labeled anomalies for supervised learning
- ❌ Real cluster data is mostly "normal" (imbalanced training data)
- ❌ Can't test model on controlled anomaly scenarios
- ❌ Breaks in development environments without Prometheus

**When Acceptable**:
- ✅ Unsupervised learning (clustering, dimensionality reduction)
- ✅ Models that don't require labeled anomalies

### Why Hybrid Approach

**Chosen Strategy**:
```python
# Mix of Prometheus (real patterns) + Synthetic (labeled anomalies)
DATA_SOURCE = 'hybrid'
prometheus_data = fetch_prometheus_metrics(days=7)
synthetic_anomalies = inject_synthetic_anomalies(prometheus_data, rate=0.03)
```

**Advantages**:
- ✅ Real cluster patterns from Prometheus
- ✅ Labeled anomalies from synthetic injection
- ✅ Adapts to cluster behavior over time
- ✅ Fallback to synthetic if Prometheus unavailable
- ✅ Best generalization (diverse training examples)

### Why Environment Variable Configuration

**Alternative 1: Hardcoded in Notebook** (Rejected)
```python
# Hardcoded
DATA_SOURCE = 'synthetic'
```
- ❌ Requires notebook editing to change mode
- ❌ Can't override for different environments

**Alternative 2: Function Parameter** (Rejected)
```python
# Function parameter
train_model(data_source='synthetic')
```
- ❌ Requires notebook execution with parameters
- ❌ Harder to configure in NotebookValidationJob

**Alternative 3: Environment Variable** (Chosen)
```python
# Environment variable
DATA_SOURCE = os.getenv('DATA_SOURCE', 'synthetic')
```
- ✅ Easy to configure in NotebookValidationJob
- ✅ Can override without editing notebooks
- ✅ Standard practice for 12-factor apps

## Consequences

### Positive

- ✅ **Flexible Training Data**: Support development, staging, and production
- ✅ **Real Cluster Patterns**: Models learn from actual workload behavior
- ✅ **Labeled Anomalies**: Synthetic injection maintains supervised learning
- ✅ **Resilient**: Fallback to synthetic if Prometheus unavailable
- ✅ **Environment-Agnostic**: Works with or without Prometheus access
- ✅ **Easy Configuration**: Environment variables for mode selection

### Negative

- ⚠️ **Prometheus Dependency**: Production mode requires Prometheus access
- ⚠️ **Increased Complexity**: Three data modes to understand and configure
- ⚠️ **Potential Inconsistency**: Models trained on different data sources may behave differently
- ⚠️ **Query Overhead**: Fetching 30 days of Prometheus data can be slow

### Neutral

- 📝 **No Automatic Selection**: Must explicitly configure DATA_SOURCE
- 📝 **Fixed Anomaly Rate**: 3% synthetic anomalies (not dynamically adjusted)
- 📝 **No Data Caching**: Prometheus queries execute on every training run

## Implementation

### Files Created/Modified

1. **ADR Documentation**: `docs/adrs/052-model-training-data-sources.md` (this file)
2. **Notebook Updates** (both notebooks get same changes):
   - `notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb`
   - `notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb`
   - Add `DATA_SOURCE` environment variable handling
   - Add `fetch_prometheus_metrics()` function
   - Add `inject_synthetic_anomalies()` function
   - Add fallback logic
3. **Validation Job Config**: `charts/hub/values-notebooks-validation.yaml`
   - Add environment variables for data source configuration
4. **Documentation**: `docs/model-training-guide.md`
   - Document data source modes and configuration

### Code Template

**Common Notebook Cell** (add to both notebooks):
```python
import os
import requests
from datetime import datetime, timedelta
import pandas as pd

# ====================
# Data Source Configuration
# ====================
DATA_SOURCE = os.getenv('DATA_SOURCE', 'synthetic')  # synthetic|prometheus|hybrid
PROMETHEUS_URL = os.getenv('PROMETHEUS_URL', 'http://prometheus-k8s.openshift-monitoring.svc:9090')
TRAINING_DAYS = int(os.getenv('TRAINING_DAYS', '7'))  # 7 for anomaly-detector, 30 for predictive-analytics
ANOMALY_RATE = float(os.getenv('ANOMALY_RATE', '0.03'))
PROMETHEUS_AVAILABLE = False

# Check Prometheus availability
if DATA_SOURCE in ['prometheus', 'hybrid']:
    try:
        response = requests.get(f"{PROMETHEUS_URL}/api/v1/status/config", timeout=5)
        PROMETHEUS_AVAILABLE = response.status_code == 200
        print(f"✅ Prometheus available at {PROMETHEUS_URL}")
    except Exception as e:
        print(f"⚠️ Prometheus not available: {e}")
        print(f"   Falling back to synthetic data")
        DATA_SOURCE = 'synthetic'

print(f"📊 Using data source: {DATA_SOURCE}")
print(f"   Training days: {TRAINING_DAYS}")
print(f"   Anomaly rate: {ANOMALY_RATE}")
```

### Validation

```bash
# Test synthetic mode (default)
oc create job --from=notebookvalidationjob/isolation-forest-implementation-validation \
  test-synthetic-$(date +%s) -n self-healing-platform

# Test prometheus mode
oc create job --from=notebookvalidationjob/isolation-forest-implementation-validation \
  test-prometheus-$(date +%s) -n self-healing-platform \
  --overrides='{"spec":{"template":{"spec":{"containers":[{"name":"notebook-validator","env":[{"name":"DATA_SOURCE","value":"prometheus"}]}]}}}}'

# Test hybrid mode
oc create job --from=notebookvalidationjob/isolation-forest-implementation-validation \
  test-hybrid-$(date +%s) -n self-healing-platform \
  --overrides='{"spec":{"template":{"spec":{"containers":[{"name":"notebook-validator","env":[{"name":"DATA_SOURCE","value":"hybrid"}]}]}}}}'

# Monitor logs to verify data source
oc logs -f job/test-* -n self-healing-platform | grep "Using data source"
```

## Related ADRs

- [ADR-007: Prometheus Monitoring Integration](007-prometheus-monitoring-integration.md)
- [ADR-013: Data Collection and Preprocessing Workflows](013-data-collection-and-preprocessing-workflows.md)
- [ADR-037: MLOps Workflow Strategy](037-mlops-workflow-strategy.md)
- [ADR-050: Anomaly Detector Model Training](050-anomaly-detector-model-training.md) (companion ADR)
- [ADR-051: Predictive Analytics Model Training](051-predictive-analytics-model-training.md) (companion ADR)

## References

- Prometheus query API: https://prometheus.io/docs/prometheus/latest/querying/api/
- Thanos long-term storage: https://thanos.io/
- 12-Factor App methodology: https://12factor.net/config
- Notebooks:
  - `notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb`
  - `notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb`

## Next Steps

**Immediate (This ADR)**:
1. ✅ Update notebooks to support all three data modes
2. ✅ Add Prometheus data fetching functions
3. ✅ Add synthetic anomaly injection functions
4. ✅ Add environment variable configuration
5. ✅ Add fallback logic

**Future Enhancements**:
1. Add data caching to reduce Prometheus query overhead
2. Implement automatic data source selection based on environment detection
3. Add data quality checks (missing values, outliers, drift detection)
4. Integrate with Thanos for efficient long-term historical queries
5. Add data versioning (track which data produced which model)
6. Implement incremental training (only fetch new Prometheus data since last training)
