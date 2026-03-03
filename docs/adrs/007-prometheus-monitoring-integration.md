# ADR-007: Prometheus-Based Monitoring and Data Collection

## Status

Accepted

## Implementation Status
**Status:** ✅ IMPLEMENTED
**Verification Date:** 2026-01-25
**Implementation Score:** 10.0/10
**Verified On:** SNO + HA clusters
**Evidence:** Prometheus 2.55.1 operational (2 replicas). Monitoring integration fully deployed.

## Context

The Self-Healing Platform requires comprehensive monitoring and data collection to support:

- **Anomaly Detection**: Real-time metrics for AI model input
- **Predictive Analytics**: Historical data for trend analysis and failure prediction
- **Automated Remediation**: Metrics-driven decision making for self-healing actions
- **Observability**: Platform health monitoring and alerting
- **Data Pipeline**: Reliable data source for ML model training and inference

### Current Environment Analysis

Our OpenShift 4.18.21 cluster includes:
- **Prometheus Stack**: Built-in cluster monitoring with Prometheus 2.x
- **AlertManager**: Deployed for alert routing and notification
- **Grafana**: Available for visualization and dashboards
- **Thanos**: Deployed for long-term metrics storage and querying
- **Service Monitors**: Automatic service discovery and scraping

### Requirements from PRD

- Ingest hardware health metrics from various sources
- Provide data for AI model training (CPU, memory, network metrics)
- Support real-time anomaly detection with sub-minute resolution
- Integrate with alert correlation and incident management
- Maintain historical data for trend analysis and model training

## Decision

We will use **Prometheus** as the primary monitoring and data collection platform for the Self-Healing Platform, leveraging OpenShift's built-in monitoring stack.

### Key Prometheus Capabilities Utilized

1. **Metrics Collection**
   - Node-level metrics (CPU, memory, disk, network)
   - Container-level metrics (resource usage, performance)
   - Application-level metrics (custom business metrics)
   - GPU metrics via DCGM exporter

2. **Data Storage and Querying**
   - Time-series data storage with configurable retention
   - PromQL for complex metric queries and aggregations
   - Thanos for long-term storage and cross-cluster queries

3. **Service Discovery**
   - Automatic discovery of monitoring targets
   - ServiceMonitor CRDs for declarative monitoring configuration
   - PodMonitor for pod-level metric collection

4. **Integration Points**
   - REST API for external data access
   - Webhook integration for real-time alerts
   - Export capabilities for ML pipeline integration

## Alternatives Considered

### InfluxDB + Telegraf
- **Pros**: Purpose-built for time-series, good performance, SQL-like query language
- **Cons**: Additional infrastructure, not Kubernetes-native, separate ecosystem
- **Verdict**: Rejected - Prometheus is already deployed and integrated

### Elasticsearch + Beats
- **Pros**: Excellent for log analysis, good visualization, flexible data model
- **Cons**: Resource-intensive, complex setup, primarily for logs not metrics
- **Verdict**: Rejected - optimized for logs, not time-series metrics

### Cloud Monitoring Services (CloudWatch, Azure Monitor)
- **Pros**: Fully managed, scalable, integrated with cloud services
- **Cons**: Vendor lock-in, data egress costs, limited on-premises support
- **Verdict**: Rejected - conflicts with OpenShift-first strategy

### Custom Metrics Collection
- **Pros**: Tailored to specific needs, full control over data format
- **Cons**: Significant development effort, reinventing proven solutions
- **Verdict**: Rejected - Prometheus provides comprehensive solution

## Consequences

### Positive

- **Native Integration**: Built-in OpenShift monitoring with zero setup
- **Kubernetes Native**: ServiceMonitor CRDs for declarative configuration
- **Rich Ecosystem**: Extensive exporter ecosystem for various systems
- **Proven Scalability**: Battle-tested in large-scale environments
- **Query Language**: Powerful PromQL for complex metric analysis
- **Existing Deployment**: Already configured and collecting metrics

### Negative

- **Resource Usage**: Prometheus can be resource-intensive at scale
- **Query Complexity**: PromQL has a learning curve for complex queries
- **Cardinality Limits**: High-cardinality metrics can impact performance
- **Retention Limits**: Local storage retention limits require Thanos for long-term storage

### Neutral

- **Data Model**: Time-series data model may require adaptation for some use cases
- **Alerting**: AlertManager provides basic alerting, may need enhancement
- **Visualization**: Grafana integration available but may need customization

## Implementation Architecture

### Data Collection Strategy

```yaml
# ServiceMonitor for Self-Healing Platform components
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: self-healing-platform
  namespace: self-healing-platform
spec:
  selector:
    matchLabels:
      app.kubernetes.io/part-of: self-healing-platform
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### Key Metrics for AI Models

1. **Node Metrics**
   ```promql
   # CPU utilization rate
   rate(node_cpu_seconds_total[5m])

   # Memory usage
   node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

   # Network I/O rate
   rate(node_network_receive_bytes_total[5m])
   ```

2. **Container Metrics**
   ```promql
   # Container CPU usage
   rate(container_cpu_usage_seconds_total[5m])

   # Container memory working set
   container_memory_working_set_bytes

   # Container restart count
   increase(kube_pod_container_status_restarts_total[1h])
   ```

3. **GPU Metrics**
   ```promql
   # GPU utilization
   DCGM_FI_DEV_GPU_UTIL

   # GPU memory utilization
   DCGM_FI_DEV_MEM_COPY_UTIL

   # GPU temperature
   DCGM_FI_DEV_GPU_TEMP
   ```

### Data Pipeline Integration

```python
# Python client for Prometheus data access
from prometheus_api_client import PrometheusConnect

prom = PrometheusConnect(url="http://prometheus.openshift-monitoring.svc:9090")

# Query for anomaly detection model
cpu_query = 'rate(container_cpu_usage_seconds_total[5m])'
memory_query = 'container_memory_working_set_bytes'
network_query = 'rate(container_network_receive_bytes_total[5m])'

# Collect time series data for model training
cpu_data = prom.get_metric_range_data(cpu_query, start_time=start, end_time=end)
```

## Alert Configuration

### Self-Healing Platform Alerts

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: self-healing-platform-alerts
spec:
  groups:
  - name: self-healing.rules
    rules:
    - alert: AnomalyDetectionModelDown
      expr: up{job="anomaly-detector"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Anomaly detection model is down"

    - alert: HighNodeCPUUsage
      expr: (1 - rate(node_cpu_seconds_total{mode="idle"}[5m])) > 0.8
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High CPU usage detected on node {{ $labels.instance }}"

    - alert: PredictiveModelAccuracyDrop
      expr: model_accuracy < 0.8
      for: 15m
      labels:
        severity: warning
      annotations:
        summary: "Model accuracy has dropped below threshold"
```

## Data Retention and Storage

### Local Prometheus Storage
- **Retention**: 15 days for high-resolution metrics
- **Resolution**: 30-second intervals for real-time monitoring
- **Storage**: Persistent volumes for data durability

### Thanos Long-term Storage
- **Retention**: 2 years for historical analysis
- **Downsampling**: Automatic downsampling for older data
- **Storage Backend**: S3-compatible storage for cost efficiency

## Performance Optimization

### Query Optimization
- Use recording rules for frequently accessed complex queries
- Implement proper metric labeling strategies
- Monitor query performance and optimize slow queries

### Resource Management
- Configure appropriate resource limits for Prometheus pods
- Use horizontal sharding for high-scale deployments
- Implement metric relabeling to reduce cardinality

## Success Metrics

- **Data Availability**: >99.9% metrics collection uptime
- **Query Performance**: <5 seconds for 95% of PromQL queries
- **Storage Efficiency**: <10GB storage per million samples
- **Alert Latency**: <1 minute from metric threshold to alert firing

## Related ADRs

- [ADR-003: Red Hat OpenShift AI for ML Platform](003-openshift-ai-ml-platform.md)
- [ADR-005: Machine Config Operator for Node-Level Automation](005-machine-config-operator-automation.md)
- [ADR-006: NVIDIA GPU Operator for AI Workload Management](006-nvidia-gpu-management.md)

## References

- [OpenShift Monitoring Documentation](https://docs.openshift.com/container-platform/4.18/monitoring/monitoring-overview.html)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Self-Healing Platform PRD](../../PRD.md) - Section 5.3.2: Anomaly Detection Model Development
- Current cluster: Prometheus stack deployed with OpenShift 4.18.21
