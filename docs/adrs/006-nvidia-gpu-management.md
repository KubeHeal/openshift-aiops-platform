# ADR-006: NVIDIA GPU Operator for AI Workload Management

## Status

Accepted

## Implementation Status
**Status:** ✅ IMPLEMENTED
**Verification Date:** 2026-01-25
**Implementation Score:** 10.0/10
**Verified On:** SNO + HA clusters
**Evidence:** GPU Operator 24.9.2 deployed. NVIDIA GPU management fully operational.

## Context

The Self-Healing Platform requires GPU acceleration for AI/ML workloads, specifically:

- **Model Training**: GPU-accelerated training for anomaly detection models
- **Real-time Inference**: GPU-accelerated inference for low-latency predictions
- **Resource Management**: Efficient allocation and scheduling of GPU resources
- **Driver Management**: Automated GPU driver installation and updates
- **Monitoring**: GPU utilization and health monitoring

### Current Environment Analysis

Our cluster currently has:
- **NVIDIA GPU Operator**: Version 24.9.2 installed
- **GPU-enabled Node**: 1 worker node with GPU capabilities (ip-10-0-3-186)
- **Node Feature Discovery**: Deployed for hardware feature detection
- **GPU Device Plugin**: Automatically deployed by GPU Operator
- **DCGM Exporter**: Deployed for GPU metrics collection

### Requirements from PRD

- GPU management for AI workloads using NVIDIA GPU Operator and NFD
- Support for model training and inference workloads
- Integration with OpenShift AI for data science environments
- Monitoring and observability for GPU resources

## Decision

We will use the **NVIDIA GPU Operator 24.9+** for comprehensive GPU resource management in the Self-Healing Platform.

### Key GPU Operator Components

1. **Driver Management**
   - Automated NVIDIA driver installation via DaemonSet
   - Driver lifecycle management and updates
   - Container runtime integration (CRI-O)

2. **Resource Management**
   - GPU device plugin for Kubernetes scheduling
   - GPU resource allocation and isolation
   - Multi-instance GPU (MIG) support when available

3. **Monitoring and Observability**
   - DCGM (Data Center GPU Manager) for metrics collection
   - GPU utilization, temperature, and health monitoring
   - Prometheus integration for alerting

4. **Validation and Testing**
   - Automated GPU validation workloads
   - CUDA compatibility testing
   - Performance benchmarking

## Alternatives Considered

### Manual GPU Driver Installation
- **Pros**: Full control over driver versions, simple setup
- **Cons**: Manual maintenance, no automation, difficult to scale
- **Verdict**: Rejected - not suitable for production automation

### Cloud Provider GPU Services
- **Pros**: Fully managed, no driver management, easy scaling
- **Cons**: Vendor lock-in, cost implications, not on-premises compatible
- **Verdict**: Rejected - conflicts with OpenShift-first strategy

### Custom GPU Management Solution
- **Pros**: Tailored to specific needs, full control
- **Cons**: Significant development effort, maintenance overhead
- **Verdict**: Rejected - GPU Operator provides proven solution

### Alternative GPU Operators (AMD, Intel)
- **Pros**: Support for different GPU vendors
- **Cons**: Limited ecosystem support, less mature tooling
- **Verdict**: Rejected - NVIDIA has best AI/ML ecosystem support

## Consequences

### Positive

- **Automated Management**: Complete GPU lifecycle automation
- **Production Ready**: Battle-tested in enterprise environments
- **Comprehensive Monitoring**: Built-in GPU metrics and alerting
- **OpenShift Integration**: Native integration with OpenShift AI
- **Existing Deployment**: Already installed and configured (v24.9.2)
- **Ecosystem Support**: Excellent support for AI/ML frameworks

### Negative

- **Vendor Lock-in**: Tied to NVIDIA GPU hardware and software stack
- **Resource Overhead**: Additional operators and DaemonSets consume resources
- **Complexity**: Additional layer of abstraction for GPU management
- **Update Dependencies**: GPU Operator updates tied to NVIDIA driver releases

### Neutral

- **Hardware Requirements**: Requires NVIDIA GPU hardware
- **Learning Curve**: Team needs GPU Operator-specific knowledge
- **Cost**: GPU hardware and software licensing costs

## Implementation Details

### Current Deployment Status

```bash
# GPU Operator pods running in nvidia-gpu-operator namespace:
- gpu-operator-554b748fdc-rv9gm (GPU Operator controller)
- nvidia-driver-daemonset-418.94.202507221927-0-g5q9p (Driver DaemonSet)
- nvidia-device-plugin-daemonset-qvkb2 (Device Plugin)
- nvidia-dcgm-exporter-n2gzs (Metrics Exporter)
- gpu-feature-discovery-5cjff (Feature Discovery)
- nvidia-container-toolkit-daemonset-rz2xk (Container Toolkit)
```

### GPU Resource Allocation

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-workload
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:11.8-runtime-ubuntu20.04
    resources:
      limits:
        nvidia.com/gpu: 1
      requests:
        nvidia.com/gpu: 1
```

### OpenShift AI Integration

```yaml
apiVersion: kubeflow.org/v1
kind: Notebook
metadata:
  name: gpu-notebook
spec:
  template:
    spec:
      containers:
      - name: notebook
        resources:
          limits:
            nvidia.com/gpu: 1
          requests:
            nvidia.com/gpu: 1
```

## Monitoring and Alerting

### GPU Metrics Available

- `DCGM_FI_DEV_GPU_UTIL`: GPU utilization percentage
- `DCGM_FI_DEV_MEM_COPY_UTIL`: GPU memory utilization
- `DCGM_FI_DEV_GPU_TEMP`: GPU temperature
- `DCGM_FI_DEV_POWER_USAGE`: GPU power consumption
- `DCGM_FI_DEV_PCIE_REPLAY_COUNTER`: PCIe error counters

### Alert Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gpu-alerts
spec:
  groups:
  - name: gpu.rules
    rules:
    - alert: GPUHighUtilization
      expr: DCGM_FI_DEV_GPU_UTIL > 90
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "GPU utilization is high"

    - alert: GPUHighTemperature
      expr: DCGM_FI_DEV_GPU_TEMP > 80
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "GPU temperature is critically high"
```

## Resource Planning

### Current GPU Resources

- **GPU Nodes**: 1 worker node (ip-10-0-3-186) with GPU capability
- **GPU Type**: Detected and managed by GPU Operator
- **Scheduling**: GPU resources schedulable via Kubernetes resource requests

### Scaling Considerations

- **Horizontal Scaling**: Add more GPU-enabled worker nodes
- **Vertical Scaling**: Upgrade to higher-performance GPUs
- **Multi-Instance GPU**: Enable MIG for GPU sharing when supported
- **Resource Quotas**: Implement GPU resource quotas per namespace

## Success Metrics

- **GPU Utilization**: Target >70% average GPU utilization
- **Workload Scheduling**: <30 seconds for GPU workload scheduling
- **Driver Stability**: >99.9% GPU driver uptime
- **Performance**: Maintain baseline GPU performance benchmarks

## Related ADRs

- [ADR-003: Red Hat OpenShift AI for ML Platform](003-openshift-ai-ml-platform.md)
- [ADR-004: KServe for Model Serving Infrastructure](004-kserve-model-serving.md)
- [ADR-007: Prometheus-Based Monitoring and Data Collection](007-prometheus-monitoring-integration.md)

## References

- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
- [OpenShift GPU Support](https://docs.openshift.com/container-platform/4.18/architecture/nvidia-gpu-architecture-overview.html)
- [Self-Healing Platform PRD](../../PRD.md) - Section 5.2: AI/ML Infrastructure
- Current cluster: NVIDIA GPU Operator 24.9.2 with 1 GPU-enabled worker node
