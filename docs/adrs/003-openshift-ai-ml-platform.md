# ADR-003: Red Hat OpenShift AI for ML Platform

**Status:** ACCEPTED

## Status

accepted

## Implementation Status
**Status:** implemented
**Verification Date:** 2026-01-25
**Implementation Score:** 10.0/10
**Verified On:** SNO + HA clusters
**Evidence:** RHODS 2.25.1 operational with all components. OpenShift AI platform fully deployed.

## Context

The Self-Healing Platform requires a comprehensive AI/ML infrastructure to support:

- **Anomaly Detection Models**: Real-time analysis of operational metrics
- **Predictive Analytics**: Hardware failure prediction and capacity planning
- **Model Training Pipeline**: Automated MLOps for continuous model improvement
- **Model Serving**: Scalable inference services for real-time decision making
- **Data Science Environment**: Jupyter notebooks for model development and experimentation

### Current Environment Analysis

Our cluster currently has:
- **Red Hat OpenShift AI**: Version 2.22.2 installed
- **GPU Resources**: NVIDIA GPU Operator 24.9.2 with GPU-enabled worker node
- **Knative Serving**: 1.36.1 for serverless model serving
- **Data Science Pipelines**: Available through OpenShift AI
- **Model Serving**: KServe and ModelMesh controllers deployed

### Requirements from PRD

- Jupyter notebook environment with GPU support
- Automated MLOps pipeline using Kubeflow Pipelines
- KServe for model serving infrastructure
- Integration with Prometheus for operational data
- Support for multiple ML frameworks (TensorFlow, PyTorch, scikit-learn)

## Decision

We will use **Red Hat OpenShift AI 2.6+** (currently 2.22.2) as the comprehensive ML platform for the Self-Healing Platform.

### Key Components Utilized

1. **Data Science Environment**
   - Jupyter notebooks with GPU support
   - Pre-configured workbench images
   - Integrated development environment

2. **Model Training & MLOps**
   - Data Science Pipelines (Kubeflow Pipelines)
   - Automated model training workflows
   - Model versioning and experiment tracking

3. **Model Serving**
   - KServe for real-time inference
   - ModelMesh for multi-model serving
   - Serverless scaling capabilities

4. **Resource Management**
   - GPU resource allocation and scheduling
   - Workload isolation and resource quotas
   - Integration with cluster autoscaling

## Alternatives Considered

### Kubeflow (Standalone)
- **Pros**: Open source, comprehensive ML platform, large community
- **Cons**: Complex installation, requires significant operational overhead
- **Verdict**: Rejected - OpenShift AI provides managed Kubeflow components

### MLflow + Custom Infrastructure
- **Pros**: Flexible, open source, good experiment tracking
- **Cons**: Requires building serving infrastructure, limited GPU support
- **Verdict**: Rejected - lacks comprehensive platform capabilities

### Cloud ML Services (AWS SageMaker, Azure ML)
- **Pros**: Fully managed, scalable, integrated with cloud services
- **Cons**: Vendor lock-in, data egress costs, limited on-premises support
- **Verdict**: Rejected - conflicts with OpenShift-first strategy

### Ray on Kubernetes
- **Pros**: Excellent for distributed ML, good Python ecosystem
- **Cons**: Primarily focused on training, limited serving capabilities
- **Verdict**: Rejected - insufficient serving infrastructure

## Consequences

### Positive

- **Integrated Platform**: Seamless integration with OpenShift ecosystem
- **Enterprise Support**: Red Hat support and security updates
- **GPU Optimization**: Native GPU support with NVIDIA GPU Operator
- **Simplified Operations**: Managed components reduce operational overhead
- **Compliance**: Enterprise-grade security and compliance features
- **Existing Investment**: Already deployed and configured in current cluster

### Negative

- **Vendor Lock-in**: Tied to Red Hat ecosystem and release cycles
- **Cost**: Commercial licensing costs for enterprise features
- **Limited Customization**: Less flexibility compared to building custom stack
- **Version Dependencies**: Must align with OpenShift release cycles

### Neutral

- **Learning Curve**: Team needs OpenShift AI-specific knowledge
- **Migration Path**: Clear path for migrating existing ML workloads
- **Ecosystem Integration**: Good integration with other Red Hat products

## Implementation Details

### Data Science Environment Setup

```yaml
apiVersion: kubeflow.org/v1
kind: Notebook
metadata:
  name: self-healing-workbench
  namespace: self-healing-platform
spec:
  template:
    spec:
      containers:
      - name: self-healing-workbench
        image: quay.io/opendatahub/workbench-images:jupyter-datascience-c9s-py311_2024a_20240301
        resources:
          requests:
            cpu: "2"
            memory: "8Gi"
            nvidia.com/gpu: "1"
          limits:
            cpu: "4"
            memory: "16Gi"
            nvidia.com/gpu: "1"
```

### Required Python Libraries

- **Data Processing**: pandas, numpy, scikit-learn, scipy
- **Time Series Analysis**: statsmodels, prophet, tslearn
- **Machine Learning**: tensorflow, pytorch, xgboost, lightgbm
- **Anomaly Detection**: pyod, isolation-forest, sklearn.ensemble
- **Monitoring Integration**: prometheus-client, kubernetes
- **Model Serving**: kserve, seldon-core

### MLOps Pipeline Integration

- **Data Ingestion**: Automated collection from Prometheus
- **Feature Engineering**: Time-based and statistical features
- **Model Training**: Automated retraining on schedule
- **Model Validation**: Performance and drift detection
- **Model Deployment**: Automated KServe deployment

## Success Metrics

- **Model Development Velocity**: Reduce time from idea to production by 60%
- **Resource Utilization**: >80% GPU utilization during training
- **Model Performance**: <100ms inference latency for anomaly detection
- **Operational Efficiency**: 90% reduction in manual ML operations tasks

## Related ADRs

- [ADR-001: OpenShift 4.18+ as Foundation Platform](001-openshift-platform-selection.md)
- [ADR-004: KServe for Model Serving Infrastructure](004-kserve-model-serving.md)
- [ADR-006: NVIDIA GPU Operator for AI Workload Management](006-nvidia-gpu-management.md)
- [ADR-008: Kubeflow Pipelines for MLOps Automation](008-kubeflow-pipelines-mlops.md)

## References

- [OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)
- [Self-Healing Platform PRD](../../PRD.md) - Section 5.2: AI/ML Infrastructure
- Current cluster: Red Hat OpenShift AI 2.22.2 installed
