# Setting Up Your AI-Powered OpenShift Cluster

*Part 1 of the OpenShift AI Ops Learning Series*

---

## Introduction

Welcome to the OpenShift AI Ops Self-Healing Platform! Before you can start detecting anomalies, predicting resource usage, and automating remediation, you need to ensure your OpenShift cluster is properly configured.

This guide walks you through validating your cluster setup using the platform's readiness validation notebooks. By the end, you'll have a fully validated environment ready for AI-powered operations.

---

## What You'll Learn

- How to validate your OpenShift cluster meets platform requirements
- Understanding KServe and model serving infrastructure
- Setting up the self-healing workbench environment
- Verifying all platform components are operational

---

## Prerequisites

Before starting, ensure you have:

- [ ] OpenShift 4.18+ cluster with admin access
- [ ] `oc` CLI installed and authenticated
- [ ] OpenShift AI (RHODS) 2.22.2+ installed
- [ ] NVIDIA GPU Operator (if using GPU workloads)
- [ ] OpenShift Data Foundation (ODF) for storage
- [ ] OpenShift GitOps (ArgoCD) installed
- [ ] OpenShift Pipelines (Tekton) installed

> **Note**: If you haven't deployed the platform yet, see the [deployment guide](../DEPLOYMENT.md) first.

---

## Step 1: Access the Self-Healing Workbench

The platform provides a Jupyter workbench pre-configured with all necessary tools and libraries.

### Option A: Via OpenShift Console

1. Navigate to **OpenShift AI** → **Data Science Projects**
2. Select the **self-healing-platform** project
3. Click **Launch Notebook**
4. The workbench opens in your browser

### Option B: Via Port Forward

```bash
# Get the workbench pod name
oc get pods -n self-healing-platform | grep workbench

# Port forward to localhost
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform

# Open http://localhost:8888 in your browser
```

---

## Step 2: Run Platform Readiness Validation

The platform includes a comprehensive validation notebook that checks all infrastructure components.

### Open the Validation Notebook

1. In the Jupyter workbench, navigate to `notebooks/00-setup/`
2. Open `00-platform-readiness-validation.ipynb`
3. This notebook performs **35+ validation checks** across:
   - Basic environment (Python, PyTorch, GPU, storage)
   - Platform infrastructure (Coordination Engine, MCP Server)
   - OpenShift components (operators, RBAC, network policies)
   - Network connectivity (Prometheus, KServe, object storage)

### Execute the Validation

Run all cells in the notebook. You'll see output like:

```
📦 VALIDATING BASIC ENVIRONMENT
✅ Python 3.11.0 detected
✅ PyTorch 2.1.0 installed
✅ GPU available: NVIDIA A100
✅ Storage volumes mounted correctly

📊 Basic Environment: 6/6 passed

🏗️  VALIDATING PLATFORM INFRASTRUCTURE
✅ Coordination Engine: Healthy
✅ Coordination Engine Metrics: Operational
✅ KServe Proxy: Connected
✅ Model Serving: anomaly-detector READY
✅ Object Storage: S3 accessible
✅ MCP Server: Running

📊 Platform Infrastructure: 12/12 passed
```

### Understanding the Results

The validation notebook generates a comprehensive report showing:
- ✅ **PASSED**: Component is ready
- ⚠️ **WARNING**: Component works but may need attention
- ❌ **FAILED**: Component needs fixing before proceeding

**Common Issues and Fixes:**

| Issue | Solution |
|-------|----------|
| GPU not available | Verify GPU operator is installed: `oc get csv -n openshift-operators \| grep gpu-operator` |
| Storage volumes not mounted | Check PVC status: `oc get pvc -n self-healing-platform` |
| Coordination Engine unreachable | Verify service: `oc get svc coordination-engine -n self-healing-platform` |
| Prometheus not accessible | Check Prometheus operator: `oc get pods -n openshift-monitoring \| grep prometheus` |

---

## Step 3: Understand KServe Model Onboarding

KServe is the model serving infrastructure that powers the platform's ML predictions. Let's explore how models are registered and used.

### Open the KServe Onboarding Notebook

1. Navigate to `notebooks/00-setup/`
2. Open `01-kserve-model-onboarding.ipynb`

### Architecture Overview

```
┌─────────────┐     ┌──────────────────────┐     ┌─────────────────────┐
│  Notebook   │────▶│ Coordination Engine  │────▶│ KServe Inference    │
│  (You!)     │     │ /api/v1/detect       │     │ Services            │
└─────────────┘     └──────────────────────┘     └─────────────────────┘
```

**Key Benefits:**
- ✅ Central orchestration for all ML models
- ✅ Config-driven model registration
- ✅ No code changes to add new models
- ✅ GitOps-native workflow

### Discover Available Models

The notebook shows you how to:

1. **Connect to Coordination Engine**:
   ```python
   from coordination_engine_client import get_client
   client = get_client()
   ```

2. **List Available Models**:
   ```python
   models = client.list_models()
   for model in models:
       print(f"{model.name}: {model.status}")
   ```

3. **Check Model Health**:
   ```python
   health = client.get_model_health("anomaly-detector")
   print(f"Status: {health.status}")
   print(f"Ready: {health.ready}")
   ```

### Test a Model Prediction

```python
# Example: Detect anomaly in sample metrics
response = client.detect_anomaly(
    metrics={
        "cpu_usage": 0.95,  # 95% CPU
        "memory_usage": 0.88,  # 88% memory
        "pod_restarts": 5
    }
)

print(f"Anomaly detected: {response.is_anomaly}")
print(f"Confidence: {response.confidence}")
print(f"Severity: {response.severity}")
```

---

## Step 4: Verify Environment Setup

The environment setup notebook (`environment-setup.ipynb`) validates your Python environment and installs any missing dependencies.

### Run Environment Setup

1. Open `notebooks/00-setup/environment-setup.ipynb`
2. Execute all cells
3. The notebook will:
   - Check Python version (3.11+)
   - Verify required packages (pandas, numpy, scikit-learn, etc.)
   - Install missing dependencies
   - Validate GPU access (if available)
   - Test connectivity to platform services

### Expected Output

```
✅ Python 3.11.0 detected
✅ Required packages installed:
   - pandas 2.1.0
   - numpy 1.24.0
   - scikit-learn 1.3.0
   - torch 2.1.0
✅ GPU available: NVIDIA A100 (40GB)
✅ Coordination Engine: http://coordination-engine:8080
✅ Prometheus: http://prometheus-k8s:9090
✅ Object Storage: S3 endpoint accessible
```

---

## What Just Happened?

You've validated three critical aspects of the platform:

### 1. Infrastructure Readiness

The validation notebook checks that all platform components are:
- **Deployed**: Services are running
- **Accessible**: Network connectivity works
- **Configured**: RBAC, storage, and operators are set up correctly

### 2. Model Serving Infrastructure

KServe provides:
- **Standardized API**: All models use the same `/v1/models/model:predict` endpoint
- **Auto-scaling**: Models scale based on request volume
- **Canary deployments**: Test new model versions safely
- **Multi-framework support**: sklearn, PyTorch, TensorFlow, XGBoost

### 3. Development Environment

The workbench provides:
- **Pre-configured tools**: All ML libraries pre-installed
- **Persistent storage**: Your notebooks and data persist across restarts
- **GPU access**: For training deep learning models
- **Git integration**: Direct access to the platform repository

---

## Next Steps

Now that your cluster is validated, you're ready to:

1. **Collect Data**: Move to [Blog 2: Collecting the Data That Powers AI Ops](02-collecting-data-for-aiops.md) to learn how to gather metrics from Prometheus
2. **Train Your First Model**: Jump to [Blog 3: Your First Anomaly Detector](03-isolation-forest-anomaly-detection.md) to build an Isolation Forest model
3. **Explore Scenarios**: Try [Blog 10: Pod Crash Loop Healing](10-scenario-pod-crash-loops.md) for hands-on remediation

---

## Related Resources

- **Notebooks**: 
  - `notebooks/00-setup/00-platform-readiness-validation.ipynb`
  - `notebooks/00-setup/01-kserve-model-onboarding.ipynb`
  - `notebooks/00-setup/environment-setup.ipynb`
- **ADRs**:
  - [ADR-029: Infrastructure Validation Notebook](docs/adrs/029-infrastructure-validation-notebook.md)
  - [ADR-004: KServe for Model Serving](docs/adrs/004-kserve-model-serving.md)
- **Deployment Guide**: [DEPLOYMENT.md](../DEPLOYMENT.md)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/tosin2013/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/01-setting-up-ai-powered-cluster.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 1 of 15 in the OpenShift AI Ops Learning Series*
