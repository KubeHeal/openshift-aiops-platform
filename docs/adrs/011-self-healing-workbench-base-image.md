# ADR-011: Self-Healing Workbench Base Image Selection

## Status
ACCEPTED - 2025-10-13

## Implementation Status
**Status:** ✅ IMPLEMENTED
**Verification Date:** 2026-01-25
**Implementation Score:** 9.5/10
**Verified On:** SNO + HA clusters
**Evidence:** PyTorch 2025.1 in notebooks/Dockerfile. Self-healing workbench base image operational.

## Context

The Self-Healing Platform requires a Jupyter notebook workbench environment for AI/ML model development, anomaly detection research, and self-healing algorithm experimentation. The current workbench configuration uses a custom `jupyter-workbench:latest` image that is causing ImagePullBackOff issues.

Red Hat OpenShift AI provides several pre-built, enterprise-grade notebook images in the `redhat-ods-applications` namespace that are:
- Regularly updated and maintained by Red Hat
- Optimized for OpenShift AI workloads
- Include comprehensive ML/AI libraries
- Support GPU acceleration
- Provide security patches and compliance

### Available Red Hat OpenShift AI Images

| Image Stream | Description | GPU Support | Key Libraries | Use Case |
|--------------|-------------|-------------|---------------|----------|
| `s2i-generic-data-science-notebook` | Standard Data Science | No | Pandas, NumPy, Scikit-learn, Jupyter | General data science |
| `pytorch` | PyTorch Deep Learning | Yes (CUDA) | PyTorch, CUDA libraries | Deep learning, neural networks |
| `minimal-gpu` | CUDA Minimal | Yes (CUDA) | Minimal + CUDA support | GPU-accelerated computing |
| `odh-trustyai-notebook` | TrustyAI Explainability | No | TrustyAI toolkit, explainability | AI explainability, fairness |
| `tensorflow` | TensorFlow Deep Learning | Yes (CUDA) | TensorFlow, Keras | Deep learning, ML |

### Current Workbench Requirements

Based on ADR-003 (OpenShift AI ML Platform), the workbench needs:
- **Anomaly Detection**: PyOD, time series analysis libraries
- **Model Development**: TensorFlow, PyTorch, Scikit-learn
- **GPU Support**: NVIDIA GPU acceleration for training
- **Monitoring Integration**: Prometheus client, Kubernetes API
- **Model Serving**: KServe integration
- **Explainability**: For self-healing decision transparency

## Decision

**Selected Base Image**: `image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/pytorch:2025.1`

### Rationale

1. **GPU Acceleration**: PyTorch image includes CUDA support essential for GPU-accelerated anomaly detection and model training
2. **Deep Learning Capabilities**: PyTorch is excellent for time series anomaly detection and neural network-based self-healing algorithms
3. **Enterprise Support**: Red Hat maintained with regular security updates
4. **Comprehensive Libraries**: Includes scientific computing stack (NumPy, SciPy, Pandas)
5. **Latest Version**: 2025.1 tag provides most recent libraries and security patches
6. **OpenShift AI Integration**: Native integration with OpenShift AI platform features

### Implementation Strategy

1. **Base Image**: Use PyTorch 2025.1 as the foundation
2. **Custom Extensions**: Add self-healing specific libraries via requirements.txt
3. **Configuration**: Maintain existing Jupyter configuration and environment variables
4. **Volume Mounts**: Preserve data, model artifacts, and configuration volume mounts

## Alternatives Considered

### Alternative 1: s2i-generic-data-science-notebook
- **Pros**: Comprehensive data science libraries, stable
- **Cons**: No GPU support, limited deep learning capabilities
- **Verdict**: Insufficient for GPU-accelerated anomaly detection

### Alternative 2: minimal-gpu
- **Pros**: GPU support, minimal footprint
- **Cons**: Requires extensive library installation, longer build times
- **Verdict**: Too minimal for complex ML workloads

### Alternative 3: odh-trustyai-notebook
- **Pros**: Built-in explainability tools, excellent for AI transparency
- **Cons**: No GPU support, specialized for explainability only
- **Verdict**: Could be secondary image for explainability research

### Alternative 4: Custom Built Image
- **Pros**: Complete control over dependencies
- **Cons**: Maintenance overhead, security patching responsibility, longer build times
- **Verdict**: Unnecessary complexity when enterprise images available

## Consequences

### Positive
- **Immediate Resolution**: Fixes ImagePullBackOff issues with proven enterprise image
- **GPU Acceleration**: Enables CUDA-based anomaly detection algorithms
- **Reduced Maintenance**: Red Hat handles base image updates and security patches
- **Enterprise Support**: Backed by Red Hat support and documentation
- **Faster Development**: Pre-installed ML libraries accelerate development
- **Security Compliance**: Regular security updates from Red Hat

### Negative
- **Image Size**: Larger than minimal custom images (~2-3GB)
- **Dependency Coupling**: Tied to Red Hat's update schedule
- **Version Constraints**: Must work within Red Hat's library versions

### Neutral
- **Migration Effort**: One-time configuration update required
- **Learning Curve**: Team may need to adapt to Red Hat's image conventions

## Implementation Plan

### Phase 1: Update Base Configuration (Immediate)
1. Update `k8s/base/ai-ml-workbench.yaml` to use PyTorch base image
2. Modify requirements.txt to add self-healing specific libraries
3. Test workbench startup and GPU access
4. Validate volume mounts and configuration

### Phase 2: Optimize Dependencies (Week 1)
1. Review and optimize requirements.txt for PyTorch base
2. Add anomaly detection libraries (PyOD, Prophet, TSLearn)
3. Include monitoring and KServe integration libraries
4. Test model development workflow

### Phase 3: Development Workflow Setup (Week 2)
1. Document git clone workflow for immediate productivity
2. Create development guides and examples
3. Explore TrustyAI integration for explainable self-healing
4. Add custom Jupyter extensions for platform integration
5. Implement model artifact management workflows

## Development Workflow

### Git Clone Approach (Immediate Productivity)

Due to Jupyter web interface configuration complexities with the PyTorch base image, the recommended development workflow uses direct git access:

#### **Step 1: Access Workbench Terminal**
```bash
# Get workbench pod name
oc get pods -n self-healing-platform | grep workbench

# Access the workbench terminal
oc exec -it self-healing-workbench-dev-0 -c self-healing-workbench -n self-healing-platform -- /bin/bash
```

#### **Step 2: Clone Repository**
```bash
# Clone the Self-Healing Platform repository
git clone https://gitea-with-admin-gitea.apps.cluster-dzqpc.dzqpc.sandbox29.opentlc.com/user1/openshift-aiops-platform.git

# Navigate to project directory
cd openshift-aiops-platform

# Verify access to mounted volumes
ls -la /opt/app-root/src/data    # Persistent data storage
ls -la /opt/app-root/src/models  # Model artifacts storage
```

#### **Step 3: Development Environment Setup**
```bash
# Install additional self-healing specific libraries
pip install -r k8s/base/ai-ml-workbench.yaml | grep -A 30 "requirements.txt"

# Verify GPU access (if available)
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"

# Start development work
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root
```

### Benefits of Git Clone Workflow
- **Immediate Productivity**: Bypass Jupyter web interface configuration issues
- **Full Codebase Access**: Complete access to ADRs, source code, and configurations
- **Version Control**: Native git workflow for collaborative development
- **Flexible Development**: Use any editor or IDE within the container
- **Storage Integration**: Direct access to persistent volumes for data and models

## Compliance and Validation

### ADR Compliance
- **ADR-003**: Satisfies OpenShift AI ML Platform requirements
- **ADR-006**: Enables NVIDIA GPU utilization
- **ADR-010**: Compatible with OpenShift Data Foundation storage

### Validation Criteria
- [x] Workbench pod starts successfully without ImagePullBackOff
- [x] GPU resources are accessible from notebook environment
- [x] All required ML libraries are available
- [x] Volume mounts work correctly (data, models, config)
- [x] Git clone workflow enables immediate development
- [ ] Prometheus integration functions (future enhancement)
- [ ] KServe model serving integration works (future enhancement)

## References

- [Red Hat OpenShift AI Workbench Images](https://github.com/red-hat-data-services/notebooks)
- [PyTorch CUDA Documentation](https://pytorch.org/get-started/locally/)
- [OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)
- ADR-003: OpenShift AI ML Platform
- ADR-006: NVIDIA GPU Operator for AI Workload Management
- ADR-010: OpenShift Data Foundation Requirement

## Approval

- **Architect**: [Pending]
- **Platform Team**: [Pending]
- **Security Team**: [Pending]

---
*This ADR addresses the immediate ImagePullBackOff issue while establishing a foundation for enterprise-grade AI/ML development in the Self-Healing Platform.*
