# ADR-013: Data Collection and Preprocessing Workflows for Self-Healing Platform

## Status
**IMPLEMENTED** - 2025-10-13 (Status updated 2026-01-15)

## Context

Building on ADR-012 (Notebook Architecture for End-to-End Workflows), the Self-Healing Platform requires robust data collection and preprocessing capabilities to feed AI/ML models with high-quality OpenShift operational data.

The platform's hybrid intelligence approach (ADR-002) depends on comprehensive data from multiple sources:
- **Prometheus Metrics**: System performance, resource utilization, application metrics
- **OpenShift Events**: Pod lifecycle, deployment events, cluster state changes
- **Application Logs**: Error patterns, performance indicators, business metrics
- **Infrastructure Telemetry**: Node health, network performance, storage metrics

### Current Challenges
- OpenShift environments generate massive amounts of telemetry data
- Data quality varies significantly across different sources
- Real-time processing requirements for anomaly detection
- Need for synthetic data generation for testing and validation
- Integration with existing monitoring stack (ADR-007)

### Requirements
- Scalable data collection from Prometheus and OpenShift APIs
- Real-time and batch processing capabilities
- Data quality validation and cleansing
- Feature engineering for ML model consumption
- Synthetic anomaly generation for model training
- Integration with persistent storage (ADR-010)

## Decision

**Implement comprehensive data collection and preprocessing workflows** through structured Jupyter notebooks that demonstrate best practices for gathering, cleaning, and preparing OpenShift operational data for AI/ML consumption.

### Data Collection Architecture

#### 1. **Prometheus Metrics Collection**
```python
# Key metrics categories
INFRASTRUCTURE_METRICS = [
    'node_cpu_utilization',
    'node_memory_utilization',
    'node_disk_io',
    'node_network_traffic'
]

APPLICATION_METRICS = [
    'pod_cpu_usage',
    'pod_memory_usage',
    'container_restart_count',
    'http_request_duration'
]

CLUSTER_METRICS = [
    'cluster_resource_quota',
    'namespace_pod_count',
    'persistent_volume_usage',
    'etcd_performance'
]
```

#### 2. **OpenShift Events Processing**
```python
# Event categories for anomaly detection
EVENT_TYPES = {
    'pod_lifecycle': ['Created', 'Started', 'Killed', 'Failed'],
    'resource_issues': ['FailedScheduling', 'OutOfMemory', 'DiskPressure'],
    'network_events': ['NetworkNotReady', 'CNIError', 'DNSError'],
    'storage_events': ['VolumeMount', 'PersistentVolumeError']
}
```

#### 3. **Data Pipeline Architecture**
```
Data Sources → Collection → Validation → Preprocessing → Feature Store → ML Models
     ↓              ↓           ↓            ↓             ↓           ↓
  Prometheus    Kubernetes   Quality     Normalization  Persistent   Training
  OpenShift     Events API   Checks      Aggregation    Storage      Inference
  Logs          Metrics      Anomaly     Time Windows   /models/     Serving
```

### Notebook Implementation Plan

#### **01-data-collection/prometheus-metrics-collection.ipynb**
- **Purpose**: Demonstrate Prometheus query patterns for self-healing use cases
- **Key Features**:
  - PromQL query optimization for large-scale data
  - Time-series data collection and windowing
  - Metric correlation analysis
  - Data export to persistent storage
- **Integration**: Direct connection to cluster Prometheus (ADR-007)

#### **01-data-collection/openshift-events-analysis.ipynb**
- **Purpose**: Process OpenShift events for anomaly pattern recognition
- **Key Features**:
  - Kubernetes API client integration
  - Event stream processing and filtering
  - Temporal pattern analysis
  - Event correlation with metrics
- **Integration**: OpenShift API with RBAC permissions

#### **01-data-collection/synthetic-anomaly-generation.ipynb**
- **Purpose**: Generate realistic anomaly scenarios for model training
- **Key Features**:
  - Synthetic time-series generation
  - Anomaly injection patterns
  - Realistic noise and seasonality
  - Labeled dataset creation
- **Integration**: Saves to `/opt/app-root/src/data/synthetic/`

### Data Quality Framework

#### **Quality Validation Checks**
```python
QUALITY_CHECKS = {
    'completeness': {
        'missing_values_threshold': 0.05,
        'time_gap_tolerance': '5m'
    },
    'consistency': {
        'metric_range_validation': True,
        'temporal_consistency': True
    },
    'accuracy': {
        'outlier_detection': 'isolation_forest',
        'statistical_validation': True
    }
}
```

#### **Preprocessing Pipeline**
```python
PREPROCESSING_STEPS = [
    'timestamp_normalization',
    'missing_value_imputation',
    'outlier_detection_and_handling',
    'feature_scaling_normalization',
    'time_window_aggregation',
    'feature_engineering'
]
```

### Feature Engineering Strategies

#### **Time-Series Features**
- Rolling statistics (mean, std, min, max)
- Lag features and differences
- Seasonal decomposition
- Fourier transform features
- Autocorrelation features

#### **Event-Based Features**
- Event frequency and patterns
- Time-to-event calculations
- Event sequence analysis
- Categorical encoding
- Interaction features

#### **Domain-Specific Features**
- Resource utilization ratios
- Performance degradation indicators
- Cascade failure patterns
- Recovery time metrics
- Business impact scores

## Alternatives Considered

### Alternative 1: Real-Time Streaming Pipeline
- **Pros**: Low latency, real-time processing
- **Cons**: Complex infrastructure, harder to debug and iterate
- **Verdict**: Future enhancement - start with batch processing

### Alternative 2: External Data Lake Solution
- **Pros**: Scalable, enterprise-grade
- **Cons**: Additional infrastructure, complexity, cost
- **Verdict**: Rejected - use OpenShift native storage (ADR-010)

### Alternative 3: Pre-Built Data Connectors
- **Pros**: Faster implementation, proven solutions
- **Cons**: Less flexibility, vendor lock-in, learning opportunity lost
- **Verdict**: Rejected - custom implementation provides better understanding

## Consequences

### Positive
- **Comprehensive Data Foundation**: High-quality data for ML model training
- **Reproducible Pipelines**: Standardized data collection and preprocessing
- **Educational Value**: Clear examples of data engineering best practices
- **Scalable Architecture**: Patterns that work from development to production
- **Quality Assurance**: Built-in validation and quality checks
- **Integration Ready**: Direct connection to existing monitoring infrastructure

### Negative
- **Development Complexity**: Sophisticated data pipelines require expertise
- **Storage Requirements**: Large datasets consume persistent storage
- **Performance Impact**: Data collection may impact cluster performance
- **Maintenance Overhead**: Pipelines require ongoing monitoring and updates

### Neutral
- **Learning Curve**: Team needs data engineering skills
- **Resource Usage**: Data processing consumes compute resources

## Implementation Plan

### Phase 1: Basic Collection (Week 1)
1. Implement Prometheus metrics collection notebook
2. Create OpenShift events processing notebook
3. Establish data quality validation framework
4. Set up persistent storage integration

### Phase 2: Advanced Processing (Week 2)
1. Develop synthetic anomaly generation
2. Implement comprehensive preprocessing pipeline
3. Create feature engineering workflows
4. Add performance optimization

### Phase 3: Integration and Validation (Week 3)
1. Integrate with coordination engine data requirements
2. Validate data quality and completeness
3. Performance testing and optimization
4. Documentation and examples

## Compliance and Validation

### ADR Compliance
- **ADR-002**: Provides data foundation for hybrid intelligence
- **ADR-007**: Integrates with Prometheus monitoring stack
- **ADR-010**: Uses OpenShift Data Foundation for storage
- **ADR-011**: Designed for PyTorch workbench environment
- **ADR-012**: Implements structured notebook architecture

### Success Criteria
- [x] Prometheus metrics collection at scale (>10k metrics/minute)
- [x] OpenShift events processing with <1 minute latency
- [x] Data quality validation with >95% accuracy
- [x] Synthetic data generation for training datasets
- [x] Integration with persistent storage working
- [x] Feature engineering pipeline producing ML-ready data

## References

- ADR-002: Hybrid Deterministic-AI Self-Healing Approach
- ADR-007: Prometheus-Based Monitoring and Data Collection
- ADR-010: OpenShift Data Foundation Requirement
- ADR-011: Self-Healing Workbench Base Image Selection
- ADR-012: Notebook Architecture for End-to-End Workflows
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [OpenShift Monitoring](https://docs.openshift.com/container-platform/4.18/observability/monitoring/monitoring-overview.html)
- [Time Series Data Engineering](https://www.oreilly.com/library/view/time-series-databases/9781492040651/)

## Approval

- **Architect**: [Pending]
- **Platform Team**: [Pending]
- **Data Engineering Team**: [Pending]

---
*This ADR establishes the data foundation required for effective AI/ML-driven self-healing capabilities in OpenShift environments.*
