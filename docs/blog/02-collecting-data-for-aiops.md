# Collecting the Data That Powers AI Ops

*Part 2 of the OpenShift AI Ops Learning Series*

---

## Introduction

Data is the foundation of AI-powered operations. Before you can detect anomalies or predict resource usage, you need to collect, process, and understand the metrics flowing through your OpenShift cluster.

This guide walks you through the data collection notebooks that gather metrics from Prometheus, analyze OpenShift events, parse application logs, and build a feature store for ML models.

---

## What You'll Learn

- How to query Prometheus for cluster and application metrics
- Analyzing OpenShift events for pattern recognition
- Parsing application logs for anomaly signals
- Building a feature store for ML model training
- Generating synthetic data for testing

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 1: Setting Up Your AI-Powered Cluster](01-setting-up-ai-powered-cluster.md)
- [ ] Access to Prometheus in your OpenShift cluster
- [ ] RBAC permissions to read cluster events
- [ ] Self-healing workbench running

---

## Step 1: Collect Prometheus Metrics

Prometheus is the primary source of time-series data for the platform. Let's explore how to query and collect metrics.

### Open the Metrics Collection Notebook

1. Navigate to `notebooks/01-data-collection/`
2. Open `prometheus-metrics-collection.ipynb`

### Understanding Prometheus Queries

The notebook demonstrates three categories of metrics:

#### Infrastructure Metrics

```python
INFRASTRUCTURE_METRICS = {
    'node_cpu_utilization': 'node:node_cpu_utilisation:rate5m',
    'node_memory_utilization': 'node:node_memory_utilisation:',
    'node_disk_io': 'node:node_disk_io_utilisation:rate5m',
    'node_network_traffic': 'node:node_net_utilisation:rate5m'
}
```

These metrics track cluster-wide resource usage at the node level.

#### Application Metrics

```python
APPLICATION_METRICS = {
    'pod_cpu_usage': 'pod:container_cpu_usage:rate5m',
    'pod_memory_usage': 'pod:container_memory_usage_bytes:sum',
    'container_restart_count': 'kube_pod_container_status_restarts_total',
    'http_request_duration': 'http_request_duration_seconds'
}
```

These metrics track individual pod and container behavior.

#### Cluster Metrics

```python
CLUSTER_METRICS = {
    'cluster_resource_quota': 'kube_resourcequota',
    'namespace_pod_count': 'kube_namespace_status_phase',
    'persistent_volume_usage': 'kubelet_volume_stats_used_bytes',
    'etcd_performance': 'etcd_request_duration_seconds'
}
```

These metrics track cluster-level state and performance.

### Querying Prometheus

The notebook shows how to query Prometheus using the Python `requests` library:

```python
import requests
import pandas as pd

def query_prometheus(query, start_time, end_time, step='30s'):
    """Query Prometheus for time-series data"""
    url = 'https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091/api/v1/query_range'

    params = {
        'query': query,
        'start': start_time.timestamp(),
        'end': end_time.timestamp(),
        'step': step
    }

    response = requests.get(url, params=params, verify=False)
    data = response.json()

    # Convert to pandas DataFrame
    df = pd.DataFrame(data['data']['result'][0]['values'],
                      columns=['timestamp', 'value'])
    df['timestamp'] = pd.to_datetime(df['timestamp'], unit='s')
    df['value'] = pd.to_numeric(df['value'])

    return df
```

### Saving Metrics for ML Training

```python
# Collect metrics for the last 7 days
end_time = datetime.now()
start_time = end_time - timedelta(days=7)

cpu_metrics = query_prometheus(
    'node:node_cpu_utilisation:rate5m',
    start_time, end_time
)

# Save to persistent storage
cpu_metrics.to_parquet('/opt/app-root/src/data/prometheus/cpu_metrics.parquet')
```

---

## Step 2: Analyze OpenShift Events

OpenShift events provide rich context about cluster state changes. Let's analyze them for patterns.

### Open the Events Analysis Notebook

1. Navigate to `notebooks/01-data-collection/`
2. Open `openshift-events-analysis.ipynb`

### Understanding Event Types

OpenShift generates events for:
- **Pod lifecycle**: Created, Started, Failed, Killed
- **Resource changes**: Scaled, Updated, Deleted
- **Health checks**: Liveness probe failures, Readiness changes
- **Errors**: Image pull errors, OOMKilled, CrashLoopBackOff

### Collecting Events

```python
from kubernetes import client, config, watch

# Load in-cluster config
config.load_incluster_config()
v1 = client.CoreV1Api()

# Watch events in a namespace
w = watch.Watch()
for event in w.stream(v1.list_namespaced_event, namespace='self-healing-platform'):
    event_obj = event['object']
    print(f"{event_obj.last_timestamp}: {event_obj.reason} - {event_obj.message}")
```

### Pattern Recognition

The notebook demonstrates identifying patterns like:

- **Crash loop patterns**: Multiple restart events in short time
- **Resource pressure**: Frequent OOMKilled or eviction events
- **Network issues**: Connection refused or timeout events
- **Image problems**: ImagePullBackOff or ImagePullError events

```python
# Analyze restart patterns
restart_events = events[events['reason'].str.contains('Started|Failed|Killed')]
restart_counts = restart_events.groupby('involvedObject.name').size()

# Identify crash loops (5+ restarts in 10 minutes)
crash_loops = restart_counts[restart_counts >= 5]
print(f"Found {len(crash_loops)} potential crash loops")
```

---

## Step 3: Parse Application Logs

Application logs contain valuable signals for anomaly detection. Let's parse them.

### Open the Log Parsing Notebook

1. Navigate to `notebooks/01-data-collection/`
2. Open `log-parsing-analysis.ipynb`

### Log Collection Strategies

The notebook demonstrates:

1. **Direct pod log access**: Using `kubectl logs` or Kubernetes API
2. **Log aggregation**: Collecting from multiple pods
3. **Pattern extraction**: Using regex to extract structured data
4. **Anomaly signals**: Identifying error patterns, exceptions, warnings

### Example: Parsing Error Logs

```python
import re
from collections import Counter

def parse_log_errors(logs):
    """Extract error patterns from logs"""
    error_patterns = {
        'exception': r'Exception: (.+)',
        'timeout': r'timeout after (\d+)',
        'connection_error': r'ConnectionError: (.+)',
        'oom': r'OOMKilled|OutOfMemory'
    }

    errors = []
    for line in logs:
        for error_type, pattern in error_patterns.items():
            match = re.search(pattern, line, re.IGNORECASE)
            if match:
                errors.append({
                    'type': error_type,
                    'message': match.group(1) if match.groups() else line,
                    'timestamp': extract_timestamp(line)
                })

    return pd.DataFrame(errors)
```

---

## Step 4: Build a Feature Store

A feature store centralizes processed data for ML model training and inference.

### Open the Feature Store Demo

1. Navigate to `notebooks/01-data-collection/`
2. Open `feature-store-demo.ipynb`

### Feature Engineering

The notebook shows how to:

1. **Aggregate metrics**: Roll up pod metrics to namespace/cluster level
2. **Create time features**: Hour of day, day of week, time since last event
3. **Calculate statistics**: Rolling means, standard deviations, percentiles
4. **Encode categoricals**: One-hot encoding for event types, pod phases

```python
# Create time-based features
df['hour_of_day'] = df['timestamp'].dt.hour
df['day_of_week'] = df['timestamp'].dt.dayofweek
df['is_weekend'] = df['day_of_week'].isin([5, 6])

# Calculate rolling statistics
df['cpu_rolling_mean_1h'] = df['cpu_usage'].rolling(window='1h').mean()
df['cpu_rolling_std_1h'] = df['cpu_usage'].rolling(window='1h').std()

# Save to feature store
df.to_parquet('/opt/app-root/src/data/feature-store/features.parquet')
```

### Feature Store Structure

```
/opt/app-root/src/data/feature-store/
├── raw/              # Raw metrics from Prometheus
├── processed/        # Cleaned and validated data
├── features/         # Engineered features for ML
└── metadata/         # Feature definitions and schemas
```

---

## Step 5: Generate Synthetic Data (Optional)

For testing and development, synthetic data helps validate models without waiting for real incidents.

### Open the Synthetic Anomaly Generation Notebook

1. Navigate to `notebooks/01-data-collection/`
2. Open `synthetic-anomaly-generation.ipynb`

### Generating Realistic Anomalies

The notebook demonstrates creating:

- **CPU spikes**: Sudden increases in CPU usage
- **Memory leaks**: Gradual memory growth over time
- **Crash loops**: Periodic pod restarts
- **Network issues**: Increased latency or connection failures

```python
import numpy as np

def generate_cpu_spike(base_cpu=0.3, spike_magnitude=0.8, duration=30):
    """Generate a CPU spike anomaly"""
    normal_data = np.random.normal(base_cpu, 0.05, 100)
    spike_start = 50
    spike_data = np.random.normal(spike_magnitude, 0.1, duration)

    data = np.concatenate([
        normal_data[:spike_start],
        spike_data,
        normal_data[spike_start:]
    ])

    return data
```

---

## What Just Happened?

You've learned how the platform collects and processes data:

### 1. Prometheus Metrics Collection

- **Time-series queries**: Using PromQL to extract historical data
- **Metric categories**: Infrastructure, application, and cluster-level metrics
- **Data persistence**: Saving to Parquet format for efficient ML training

### 2. Event Analysis

- **Real-time monitoring**: Watching cluster events as they happen
- **Pattern recognition**: Identifying crash loops, resource pressure, network issues
- **Context enrichment**: Combining events with metrics for richer features

### 3. Log Parsing

- **Structured extraction**: Using regex to parse unstructured logs
- **Error detection**: Identifying exceptions, timeouts, and failures
- **Signal aggregation**: Counting error types and frequencies

### 4. Feature Store

- **Centralized data**: Single source of truth for ML features
- **Feature engineering**: Creating derived features from raw metrics
- **Version control**: Tracking feature definitions and schemas

---

## Next Steps

Now that you understand data collection, you're ready to:

1. **Train Your First Model**: Move to [Blog 3: Your First Anomaly Detector](03-isolation-forest-anomaly-detection.md) to build an Isolation Forest model using this data
2. **Explore Time Series**: Jump to [Blog 4: Time Series Anomaly Detection](04-time-series-anomaly-detection.md) for advanced time-based analysis
3. **Try a Scenario**: See [Blog 10: Pod Crash Loop Healing](10-scenario-pod-crash-loops.md) to see how this data powers remediation

---

## Related Resources

- **Notebooks**:
  - `notebooks/01-data-collection/prometheus-metrics-collection.ipynb`
  - `notebooks/01-data-collection/openshift-events-analysis.ipynb`
  - `notebooks/01-data-collection/log-parsing-analysis.ipynb`
  - `notebooks/01-data-collection/feature-store-demo.ipynb`
  - `notebooks/01-data-collection/synthetic-anomaly-generation.ipynb`
- **ADRs**:
  - [ADR-007: Prometheus-Based Monitoring](docs/adrs/007-prometheus-based-monitoring.md)
  - [ADR-013: Data Collection and Preprocessing](docs/adrs/013-data-collection-and-preprocessing-workflows.md)
- **Prometheus Documentation**: [PromQL Guide](https://prometheus.io/docs/prometheus/latest/querying/basics/)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/KubeHeal/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/02-collecting-data-for-aiops.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 2 of 15 in the OpenShift AI Ops Learning Series*
