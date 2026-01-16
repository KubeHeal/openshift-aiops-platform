# ADR-004: KServe for Model Serving Infrastructure

## Status

Accepted

## Context

The Self-Healing Platform requires a scalable, production-ready model serving infrastructure to support:

- **Real-time Anomaly Detection**: Sub-100ms inference latency for operational metrics
- **Predictive Analytics**: Batch and real-time predictions for hardware failure detection
- **Auto-scaling**: Dynamic scaling based on inference load
- **Multi-framework Support**: Support for scikit-learn, TensorFlow, PyTorch models
- **Production Features**: A/B testing, canary deployments, monitoring, and observability

### Current Environment Analysis

Our cluster has:
- **KServe Controllers**: Deployed via OpenShift AI 2.22.2
- **Knative Serving**: 1.36.1 providing serverless infrastructure
- **Istio Service Mesh**: 2.6.11 for traffic management and security
- **ModelMesh**: Available for multi-model serving scenarios
- **GPU Support**: NVIDIA GPU Operator for GPU-accelerated inference

### Requirements from PRD

- Deploy anomaly detection models as scalable inference services
- Support for custom predictor implementations
- Integration with S3-compatible storage for model artifacts
- Real-time inference with <100ms latency requirements
- Automated model deployment from MLOps pipelines

## Decision

We will use **KServe** as the primary model serving infrastructure for the Self-Healing Platform.

### Key Capabilities Leveraged

1. **Multi-Framework Support**
   - Native support for scikit-learn, TensorFlow, PyTorch
   - Custom runtime support for specialized models
   - Standardized prediction API across frameworks

2. **Serverless Scaling**
   - Knative-based auto-scaling from 0 to N replicas
   - Scale-to-zero for cost optimization
   - Burst scaling for high-demand scenarios

3. **Production Features**
   - Canary deployments for safe model updates
   - Traffic splitting for A/B testing
   - Built-in monitoring and observability
   - Request/response logging

4. **Integration Capabilities**
   - Native Kubernetes integration
   - Istio service mesh integration
   - Prometheus metrics export
   - OpenShift AI pipeline integration

## Alternatives Considered

### Seldon Core
- **Pros**: Rich ML deployment features, good monitoring, multi-armed bandits
- **Cons**: More complex setup, additional CRDs, overlapping functionality with KServe
- **Verdict**: Rejected - KServe provides sufficient features with simpler architecture

### TorchServe/TensorFlow Serving (Direct)
- **Pros**: Framework-native serving, optimized performance
- **Cons**: Framework-specific, no unified API, manual scaling and management
- **Verdict**: Rejected - lacks unified multi-framework approach

### Custom Flask/FastAPI Services
- **Pros**: Full control, simple implementation, familiar technology
- **Cons**: Manual scaling, no production features, significant operational overhead
- **Verdict**: Rejected - insufficient for production requirements

### MLflow Model Serving
- **Pros**: Integrated with MLflow ecosystem, simple deployment
- **Cons**: Limited scaling capabilities, basic production features
- **Verdict**: Rejected - insufficient for high-performance requirements

## Consequences

### Positive

- **Unified API**: Consistent prediction interface across all model types
- **Auto-scaling**: Automatic scaling based on traffic with scale-to-zero
- **Production Ready**: Built-in features for canary deployments and monitoring
- **Cloud Native**: Native Kubernetes integration with GitOps workflows
- **Performance**: Optimized inference with GPU support when needed
- **Existing Integration**: Already deployed and configured in current cluster

### Negative

- **Complexity**: Additional abstraction layer over direct model serving
- **Learning Curve**: Team needs to learn KServe-specific concepts and APIs
- **Dependency**: Relies on Knative Serving and Istio infrastructure
- **Resource Overhead**: Additional components consume cluster resources

### Neutral

- **Vendor Neutrality**: Open source project with broad industry support
- **Migration Path**: Can migrate existing models gradually
- **Monitoring Integration**: Good integration with existing Prometheus setup

## Implementation Architecture

### Model Storage Configuration

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: storage-config
  namespace: self-healing-platform
stringData:
  AWS_ACCESS_KEY_ID: "storage-access-key"
  AWS_SECRET_ACCESS_KEY: "storage-secret-key"
  AWS_S3_ENDPOINT: "https://s3.openshift-storage.svc:443"
  AWS_S3_BUCKET: "model-storage"
```

### Anomaly Detection InferenceService

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: anomaly-detector
  namespace: self-healing-platform
spec:
  predictor:
    sklearn:
      storageUri: "s3://model-storage/anomaly-detector/"
      resources:
        requests:
          cpu: "1"
          memory: "2Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
```

### Custom Predictor for Complex Models

```python
import kserve
import joblib
import numpy as np
from typing import Dict

class AnomalyDetectorModel(kserve.Model):
    def __init__(self, name: str):
        super().__init__(name)
        self.model = None
        self.scaler = None
        self.ready = False

    def load(self):
        self.model = joblib.load('/mnt/models/anomaly_detector.pkl')
        self.scaler = joblib.load('/mnt/models/scaler.pkl')
        self.ready = True

    def predict(self, payload: Dict) -> Dict:
        inputs = np.array(payload["instances"])
        scaled_inputs = self.scaler.transform(inputs)
        predictions = self.model.predict(scaled_inputs)
        scores = self.model.decision_function(scaled_inputs)

        return {
            "predictions": predictions.tolist(),
            "anomaly_scores": scores.tolist()
        }
```

## Performance Requirements

- **Latency**: <100ms for anomaly detection inference
- **Throughput**: Support 1000+ requests per second during peak load
- **Availability**: 99.9% uptime for critical inference services
- **Scaling**: Scale from 0 to 50 replicas within 30 seconds

## Monitoring and Observability

- **Metrics**: Request latency, throughput, error rates via Prometheus
- **Logging**: Request/response logging for model debugging
- **Tracing**: Distributed tracing through Istio service mesh
- **Alerting**: Automated alerts for performance degradation

## Related ADRs

- [ADR-003: Red Hat OpenShift AI for ML Platform](003-openshift-ai-ml-platform.md)
- [ADR-008: Kubeflow Pipelines for MLOps Automation](008-kubeflow-pipelines-mlops.md) - ⚠️ DEPRECATED
- [ADR-007: Prometheus-Based Monitoring and Data Collection](007-prometheus-monitoring-integration.md)
- [ADR-021: Tekton Pipeline for Post-Deployment Validation](021-tekton-pipeline-deployment-validation.md)
- [ADR-039: User-Deployed KServe Models](039-user-deployed-kserve-models.md) - Platform-agnostic ML integration
- [ADR-040: Extensible KServe Model Registry](040-extensible-kserve-model-registry.md) - Custom model registration

## References

- [KServe Documentation](https://kserve.github.io/website/)
- [Self-Healing Platform PRD](../../PRD.md) - Section 5.3.3: KServe Model Deployment
- Current cluster: KServe controllers deployed via OpenShift AI 2.22.2
