# AGENTS.md - OpenShift AI Ops Platform

## Project Identity

**Name**: OpenShift AI Ops Self-Healing Platform
**Type**: Enterprise AI/ML Operations Platform
**Purpose**: Hybrid deterministic-AI self-healing system for OpenShift clusters
**License**: GNU General Public License v3.0

**⚠️ CRITICAL DISTINCTION**: This is the **Self-Healing Platform** itself, NOT the Validated Patterns Ansible Toolkit. For toolkit-specific guidance, see:
- [`my-pattern/AGENTS.md`](my-pattern/AGENTS.md) - Validated Patterns Ansible Toolkit (REFERENCE ONLY - DO NOT PUSH TO GIT)
- [`reference/ansible-execution-environment/AGENTS.md`](reference/ansible-execution-environment/AGENTS.md) - Ansible Execution Environment

**⚠️ IMPORTANT**: The `my-pattern/` directory is used for **REFERENCE PURPOSES ONLY** during development. It contains the Validated Patterns Ansible Toolkit and should **NEVER** be committed or pushed to this repository's git. It should be in `.gitignore`.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Setup Instructions](#setup-instructions)
4. [Development Workflows](#development-workflows)
5. [Notebook Development](#notebook-development)
6. [MCP Server Development](#mcp-server-development)
7. [Coordination Engine](#coordination-engine)
8. [Secrets Management](#secrets-management)
9. [Testing Strategy](#testing-strategy)
10. [Deployment](#deployment)
11. [ADR Management](#adr-management)
12. [Common Pitfalls](#common-pitfalls)
13. [References](#references)

---

## Project Overview

### What is This Platform?

The **OpenShift AI Ops Self-Healing Platform** is an integrated AIOps ecosystem that combines:

- **Deterministic Automation**: For known failure states (Machine Config Operator, rule-based remediation)
- **AI-Driven Analysis**: For novel/complex anomalies (ML models, anomaly detection, root cause analysis)
- **Coordination Engine**: Orchestrates both layers to prevent conflicts and manage priorities
- **OpenShift Lightspeed Integration**: Natural language interface via MCP (Model Context Protocol) server

### Core Philosophy

From **[PRD.md](PRD.md)**:
> The Self-Healing Platform leverages the robust, operator-driven foundation of OpenShift 4.19, employs Red Hat OpenShift AI as its central intelligence and decision-making engine, and integrates Red Hat OpenShift Lightspeed as the advanced interface between human operators and the automated system.

### Key Goals

1. **Reduce MTTR**: Target 50% reduction in mean time to resolution
2. **Minimize Human Error**: Automate routine operational tasks
3. **Enable Proactive Management**: Anticipate issues before they impact service
4. **Improve Operational Efficiency**: Free up SREs for higher-value work
5. **Unified AI Experience**: Natural language interface via OpenShift Lightspeed

### Technology Stack

| Component | Version | Role |
|-----------|---------|------|
| Red Hat OpenShift | 4.18.21+ | Foundation platform |
| Red Hat OpenShift AI | 2.22.2 | ML platform |
| NVIDIA GPU Operator | 24.9.2 | GPU management |
| KServe | 1.36.1 | Model serving |
| Knative Serving | 1.36.1 | Serverless infrastructure |
| Istio Service Mesh | 2.6.11 | Service mesh |
| OpenShift GitOps (ArgoCD) | 1.15.4 | GitOps deployment |
| OpenShift Pipelines (Tekton) | 1.17.2 | CI/CD automation |
| OpenShift Data Foundation | Latest | Storage infrastructure |

---

## Architecture

### Hybrid Self-Healing Approach

**Reference**: [ADR-002: Hybrid Deterministic-AI Self-Healing Approach](docs/adrs/002-hybrid-self-healing-approach.md)

```
┌─────────────────────────────────────────────────────────────┐
│                 Self-Healing Platform                        │
├─────────────────────────────────────────────────────────────┤
│  Coordination Engine (Python)                               │
│  ├─ Conflict Resolution                                     │
│  ├─ Priority Management                                     │
│  └─ Action Orchestration                                    │
├─────────────────────────────────────────────────────────────┤
│  Deterministic Layer    │    AI-Driven Layer               │
│  ├─ Machine Config      │    ├─ Anomaly Detection          │
│  │  Operator            │    ├─ Root Cause Analysis        │
│  ├─ Known Remediation   │    ├─ Predictive Analytics       │
│  │  Procedures          │    └─ Adaptive Responses         │
│  └─ Rule-Based Actions  │         (Jupyter Notebooks)      │
├─────────────────────────────────────────────────────────────┤
│  Shared Observability Layer                                │
│  ├─ Prometheus Metrics                                     │
│  ├─ Alert Manager                                          │
│  └─ Incident Correlation                                   │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Prometheus Metrics → Notebooks (Data Collection) → Feature Store
                                    ↓
                          Anomaly Detection Models
                                    ↓
                          Coordination Engine API
                                    ↓
                     ┌──────────────┴──────────────┐
                     ↓                             ↓
            Deterministic Actions         AI-Driven Actions
                     ↓                             ↓
                     └──────────────┬──────────────┘
                                    ↓
                        Self-Healing Execution
                                    ↓
                     OpenShift Lightspeed (via MCP)
```

### Component Directory Structure

```
/openshift-aiops-platform/
├── notebooks/                # Jupyter notebooks (AI/ML workflows)
│   ├── 00-setup/            # Platform readiness validation
│   ├── 01-data-collection/  # Metrics, logs, events
│   ├── 02-anomaly-detection/# ML models (Isolation Forest, LSTM)
│   ├── 03-self-healing-logic/# Integration with coordination engine
│   ├── 04-model-serving/    # KServe deployment
│   ├── 05-end-to-end-scenarios/# Complete use cases
│   ├── 06-mcp-lightspeed-integration/# MCP and Lightspeed
│   ├── 07-monitoring-operations/# Performance tracking
│   └── 08-advanced-scenarios/# Multi-cluster, security
├── src/
│   ├── coordination-engine/ # Python coordination engine (Flask REST API)
│   └── models/              # Pre-trained ML models
├── ansible/
│   └── roles/               # 8 Validated Patterns roles
├── tekton/                  # CI/CD pipelines (26 validation checks)
├── charts/                  # Helm charts for deployment
├── docs/
│   └── adrs/                # 29+ Architectural Decision Records
└── my-pattern/              # REFERENCE ONLY (DO NOT COMMIT TO GIT)
                             # Validated Patterns Toolkit for reference
```

**⚠️ Git Ignore Configuration**: Ensure `my-pattern/` is in your `.gitignore`:

```bash
# .gitignore
my-pattern/
```

### Integration Points

1. **Notebooks → Coordination Engine**: REST API (`http://coordination-engine:8080/api/v1/anomalies`)
2. **Coordination Engine → OpenShift**: Kubernetes API (remediation actions)
3. **MCP Server → Lightspeed**: MCP protocol (stdio/HTTP transport)
4. **KServe Models → Inference**: Real-time anomaly detection
5. **Tekton Pipelines → Validation**: Post-deployment health checks

---

## Setup Instructions

### Prerequisites

**Cluster Requirements**:
- OpenShift 4.18+ (currently running 4.18.21)
- 6+ nodes (3 control-plane, 3 workers, 1 GPU-enabled)
- 24+ CPU cores, 96+ GB RAM, 500+ GB storage
- OpenShift Data Foundation (ODF) deployed

**Operators (Pre-installed)**:
- Red Hat OpenShift AI 2.22.2
- NVIDIA GPU Operator 24.9.2
- OpenShift GitOps 1.15.4
- OpenShift Pipelines 1.17.2
- OpenShift Serverless (Knative, Istio)

**Local Tools**:
- `oc` CLI (OpenShift)
- `kubectl` CLI
- `helm` 3.12+
- `ansible-navigator` (for Ansible roles)
- `tkn` CLI (for Tekton pipelines)
- `git`

### Initial Setup

**Step 1: Validate Cluster Prerequisites**

```bash
# Check OpenShift version
oc version

# Validate operators
oc get csv -n openshift-operators | grep -E 'rhods-operator|gpu-operator|openshift-gitops|openshift-pipelines'

# Check GPU availability
oc get nodes -l nvidia.com/gpu.present=true

# Validate storage
oc get storageclass
```

**Reference**: [ADR-001: OpenShift 4.18+ as Foundation Platform](docs/adrs/001-openshift-platform-selection.md)

**Step 2: Deploy Platform via Makefile Workflow**

**📖 See Complete Guide**: [DEPLOYMENT.md](DEPLOYMENT.md) - Comprehensive deployment documentation

```bash
# Clone repository
git clone https://github.com/openshift-aiops/openshift-aiops-platform.git
cd openshift-aiops-platform

# Step 2a: Get the Execution Environment (REQUIRED)
#
# Option A: Pull pre-built image (Recommended)
podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest \
  openshift-aiops-platform-ee:latest
#
# Option B: Build locally (requires ANSIBLE_HUB_TOKEN)
# export ANSIBLE_HUB_TOKEN='your-token-here'  # Get from console.redhat.com
# make build-ee

# Step 2b: Install Jupyter Notebook Validator (REQUIRED)
make install-jupyter-validator

# Step 2c: Deploy Prerequisites (CRITICAL - Creates ServiceAccounts & RBAC)
make deploy-prereqs-only

# Step 2d: Deploy Pattern using VP Operator (RECOMMENDED)
make -f common/Makefile operator-deploy

# Step 2e: Validate deployment
make -f common/Makefile argo-healthcheck
make validate-deployment  # Runs Tekton validation pipeline
```

**Why this workflow?**:
- ✅ **Execution Environment**: Pull pre-built image from `quay.io/takinosh/openshift-aiops-platform-ee` or build locally with `make build-ee`
- ✅ **install-jupyter-validator**: Deploys NotebookValidationJob CRD and operator
- ✅ **deploy-prereqs-only**: Creates ServiceAccounts/RBAC BEFORE ArgoCD sync (breaks circular dependency)
- ✅ **operator-deploy**: Uses VP Operator for production-ready deployment
- ✅ **validate-deployment**: Runs 26 comprehensive Tekton validation checks

**Reference**: [ADR-019: Validated Patterns Framework Adoption](docs/adrs/019-validated-patterns-framework-adoption.md)

**⚠️ CRITICAL**: The `deploy-prereqs-only` step is **MANDATORY**. It creates ServiceAccounts that ArgoCD sync hooks require. Without it, deployment will fail with "serviceaccount not found" errors.

**Step 2.5: Verify Git Ignore Configuration (IMPORTANT)**

```bash
# Ensure my-pattern/ is NOT tracked by git
echo "my-pattern/" >> .gitignore

# Verify it's ignored
git status | grep -q "my-pattern" || echo "✅ my-pattern/ is properly ignored"

# If my-pattern/ was previously committed, remove it from git tracking
git rm -r --cached my-pattern/ 2>/dev/null || echo "✅ my-pattern/ not in git history"
```

**⚠️ CRITICAL**: The `my-pattern/` directory contains the Validated Patterns Ansible Toolkit and is used as a **REFERENCE ONLY**. It should NEVER be committed to this repository.

**Step 3: Verify Notebook Environment**

```bash
# Check workbench deployment
oc get notebook -n self-healing-platform

# Port-forward to Jupyter
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform

# Access Jupyter at http://localhost:8888
```

**Reference**: [ADR-011: Self-Healing Workbench Base Image](docs/adrs/011-self-healing-workbench-base-image.md)

**Step 4: Run Infrastructure Validation Notebook**

```bash
# Navigate to notebooks directory
cd notebooks/00-setup

# Open 00-platform-readiness-validation.ipynb
# Execute all cells to validate:
# - OpenShift cluster connectivity
# - Required operators
# - GPU availability
# - Storage configuration
# - Network policies
# - RBAC permissions
```

**Reference**: [ADR-029: Infrastructure Validation Notebook](docs/adrs/029-infrastructure-validation-notebook.md)

---

## Development Workflows

### Primary Development Pattern

The platform uses a **notebook-centric development workflow** where Jupyter notebooks are the primary interface for:
1. Data collection and preprocessing
2. ML model development and training
3. Integration with coordination engine
4. Model deployment to KServe
5. End-to-end scenario testing

### Workflow Stages

```
1. Setup & Validation
   └─> notebooks/00-setup/00-platform-readiness-validation.ipynb
          ↓
2. Data Collection
   └─> notebooks/01-data-collection/prometheus-metrics-collection.ipynb
   └─> notebooks/01-data-collection/openshift-events-analysis.ipynb
          ↓
3. Anomaly Detection
   └─> notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb
   └─> notebooks/02-anomaly-detection/02-time-series-anomaly-detection.ipynb
          ↓
4. Self-Healing Logic
   └─> notebooks/03-self-healing-logic/coordination-engine-integration.ipynb
   └─> notebooks/03-self-healing-logic/hybrid-healing-workflows.ipynb
          ↓
5. Model Serving
   └─> notebooks/04-model-serving/kserve-model-deployment.ipynb
          ↓
6. End-to-End Scenarios
   └─> notebooks/05-end-to-end-scenarios/pod-crash-loop-healing.ipynb
   └─> notebooks/05-end-to-end-scenarios/resource-exhaustion-detection.ipynb
          ↓
7. MCP/Lightspeed Integration
   └─> notebooks/06-mcp-lightspeed-integration/mcp-server-integration.ipynb
   └─> notebooks/06-mcp-lightspeed-integration/openshift-lightspeed-integration.ipynb
          ↓
8. Monitoring & Operations
   └─> notebooks/07-monitoring-operations/model-performance-monitoring.ipynb
```

### Development Environment Access

**Option 1: JupyterLab (Recommended)**
```bash
# Access via OpenShift Console
# Navigate to: OpenShift AI → Data Science Projects → self-healing-platform
# Click: "Launch Notebook"

# Or via CLI port-forward
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
# Open http://localhost:8888
```

**Option 2: VS Code with Jupyter Extension**
```bash
# Install Jupyter extension in VS Code
# Configure Jupyter server URL: http://localhost:8888
# Open notebooks directly in VS Code
```

**Option 3: Command Line Execution**
```bash
# Convert notebook to Python script
jupyter nbconvert --to script notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb

# Execute Python script
python notebooks/02-anomaly-detection/01-isolation-forest-implementation.py
```

---

## Notebook Development

### Notebook Architecture

**Reference**: [ADR-012: Notebook Architecture for End-to-End Workflows](docs/adrs/012-notebook-architecture-for-end-to-end-workflows.md)

### Notebook Standards

Every notebook MUST follow this structure:

```python
# ============================================================
# HEADER SECTION
# ============================================================
# Title: [Descriptive Title]
# Purpose: [What this notebook does]
# Prerequisites: [Required setup and dependencies]
# Expected Outcomes: [What you'll achieve]
# Related ADRs: [Link to relevant ADRs]
# ============================================================

# ============================================================
# SETUP SECTION
# ============================================================
import sys
sys.path.append('../utils')

from common_functions import setup_environment, validate_prerequisites
from mcp_client import CoordinationEngineClient

# Validate environment
env_info = setup_environment()
validate_prerequisites(required_operators=['gpu', 'openshift-ai', 'kserve'])

# ============================================================
# IMPLEMENTATION SECTION
# ============================================================
# Core logic with detailed markdown explanations
# ...

# ============================================================
# VALIDATION SECTION
# ============================================================
# Test and verify results
# ...

# ============================================================
# INTEGRATION SECTION
# ============================================================
# Connect to coordination engine
client = CoordinationEngineClient(base_url='http://coordination-engine:8080')
client.submit_anomaly(anomaly_data)

# ============================================================
# CLEANUP SECTION
# ============================================================
# Resource cleanup and next steps
# ...
```

### Shared Utilities

**Location**: `notebooks/utils/`

**Key Files**:
- `common_functions.py` - Environment setup, Prometheus queries, OpenShift API helpers
- `mcp_client.py` - Coordination engine REST client
- `validation_helpers.py` - Health checks, deployment validation

**Usage**:
```python
import sys
sys.path.append('../utils')

from common_functions import (
    setup_environment,
    query_prometheus,
    get_pod_metrics,
    save_to_parquet
)

# Setup
env = setup_environment()

# Query Prometheus
metrics = query_prometheus(
    query='container_cpu_usage_seconds_total',
    start_time='1h',
    step='30s'
)

# Save to persistent storage
save_to_parquet(metrics, '/opt/app-root/src/data/processed/metrics.parquet')
```

### Data Management

**Persistent Storage Paths**:
- **Input Data**: `/opt/app-root/src/data/`
- **Processed Data**: `/opt/app-root/src/data/processed/`
- **Models**: `/opt/app-root/src/models/`
- **Outputs**: `/opt/app-root/src/outputs/`

**Format**: Use Parquet for efficient storage and versioning

```python
import pandas as pd

# Save DataFrame to Parquet
df.to_parquet('/opt/app-root/src/data/processed/anomalies.parquet',
               compression='snappy',
               index=False)

# Read Parquet
df = pd.read_parquet('/opt/app-root/src/data/processed/anomalies.parquet')
```

### Integration with Coordination Engine

**Coordination Engine API**:
- **Base URL**: `http://coordination-engine.self-healing-platform.svc.cluster.local:8080`
- **Health Check**: `GET /health`
- **Submit Anomaly**: `POST /api/v1/anomalies`
- **Get Status**: `GET /api/v1/status`
- **Metrics**: `GET /metrics`

**Example Integration**:
```python
from mcp_client import CoordinationEngineClient

# Initialize client
client = CoordinationEngineClient(
    base_url='http://coordination-engine:8080',
    timeout=30
)

# Submit anomaly
response = client.submit_anomaly({
    'timestamp': '2025-11-06T12:00:00Z',
    'type': 'resource_exhaustion',
    'severity': 'critical',
    'details': {
        'node': 'worker-1',
        'metric': 'memory_usage',
        'threshold': 90,
        'current_value': 95
    },
    'recommended_action': 'scale_down_pods',
    'confidence_score': 0.92
})

print(f"Anomaly submitted: {response['anomaly_id']}")
```

### Notebook Testing

**Before Committing**:
1. **Clear all outputs**: `jupyter nbconvert --ClearOutputPreprocessor.enabled=True --inplace notebook.ipynb`
2. **Run all cells**: Verify no errors
3. **Test in clean environment**: Delete kernel, restart, run all
4. **Validate integration**: Ensure coordination engine connectivity
5. **Check persistent storage**: Verify data saved correctly

**Automated Validation**:
```bash
# Run notebook validation script
python scripts/validate_notebooks.py notebooks/02-anomaly-detection/

# Check for:
# - Import errors
# - Missing dependencies
# - Broken integration endpoints
# - Invalid data paths
```

---

## MCP Server (Standalone Project)

### ⚠️ IMPORTANT: MCP Server Moved to Standalone Repository

The MCP server has been **migrated to a standalone Go-based project** for better maintainability, performance, and reusability.

**New Standalone Project**:
- **Repository**: `openshift-cluster-health-mcp` (separate repository)
- **Location**: `$HOME/openshift-cluster-health-mcp/` (local development)
- **Language**: Go 1.21+ (changed from TypeScript/Node.js)
- **MCP SDK**: [modelcontextprotocol/go-sdk](https://github.com/modelcontextprotocol/go-sdk)
- **Documentation**: See `openshift-cluster-health-mcp/PRD.md`
- **Architecture**: [ADR-036: Go-Based Standalone MCP Server](docs/adrs/036-go-based-standalone-mcp-server.md)

**Superseded ADR**: [ADR-014](docs/adrs/014-openshift-aiops-platform-mcp-server.md) (TypeScript implementation, now deprecated)

### Why Standalone Go Project?

**Key Benefits**:
1. **Ecosystem Alignment**: Go is native for Kubernetes/OpenShift (client-go)
2. **Performance**: ~30MB binary vs ~256MB Node.js runtime
3. **Reusability**: Deploy on any OpenShift cluster independently
4. **Proven Architecture**: Leverages [containers/kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server) (856 stars)
5. **Simpler Deployment**: Single binary, no npm dependencies

### Integration with This Platform

The standalone MCP server integrates via HTTP REST APIs:

```
OpenShift Lightspeed <--MCP--> Go MCP Server
                                   │
                                   ├──HTTP──> Coordination Engine (this repo)
                                   ├──HTTP──> KServe Models (this repo)
                                   ├──HTTP──> Prometheus (OpenShift)
                                   └──K8s──> Kubernetes API
```

**Integration Points**:
- **Coordination Engine**: `http://coordination-engine:8080/api/v1/` (remediation workflows)
- **KServe Models**: `http://predictive-analytics-predictor:8080/v1/models/` (ML inference)
- **Notebooks**: Training notebooks remain in this repo (`notebooks/02-anomaly-detection/`)

### Development & Deployment

For MCP server development, see the standalone repository:

```bash
# Navigate to standalone project
cd $HOME/openshift-cluster-health-mcp

# Read comprehensive PRD
less PRD.md
```

**Deployment** (from standalone repo):
```bash
# Via Helm
helm install cluster-health-mcp ./charts/openshift-cluster-health-mcp

# Via Kustomize
oc apply -k k8s/base/
```

### Reference Documentation

- **Architecture**: [ADR-036](docs/adrs/036-go-based-standalone-mcp-server.md)
- **PRD**: `openshift-cluster-health-mcp/PRD.md`
- **Reference**: [containers/kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server)

---

## Coordination Engine

### Purpose

The **Coordination Engine** (Python Flask application) orchestrates the interaction between:
- Deterministic automation layer (Machine Config Operator, rule-based remediation)
- AI-driven analysis layer (ML models, anomaly detection)

**Reference**: [ADR-002: Hybrid Deterministic-AI Self-Healing Approach](docs/adrs/002-hybrid-self-healing-approach.md)

### API Endpoints

**Base URL**: `http://coordination-engine.self-healing-platform.svc.cluster.local:8080`

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Health check |
| `/api/v1/anomalies` | POST | Submit anomaly for processing |
| `/api/v1/anomalies/<id>` | GET | Get anomaly status |
| `/api/v1/remediate` | POST | Trigger remediation action |
| `/api/v1/status` | GET | Get engine status |
| `/metrics` | GET | Prometheus metrics |

### Development

**Location**: `src/coordination-engine/`

**Files**:
- `app.py` - Flask application
- `Dockerfile` - Container image
- `requirements.txt` - Python dependencies

**Run Locally**:
```bash
cd src/coordination-engine
pip install -r requirements.txt
python app.py
```

**Build Container**:
```bash
podman build -t coordination-engine:latest .
```

### Coordination Rules

From [ADR-002](docs/adrs/002-hybrid-self-healing-approach.md):

1. **Deterministic Priority**: Known issues handled by deterministic layer first
2. **AI Escalation**: Novel issues automatically routed to AI layer
3. **Conflict Resolution**: Prevents simultaneous conflicting actions
4. **Confidence Thresholds**: AI actions require minimum 80% confidence
5. **Human Override**: Operators can override both layers via Lightspeed

### Integration from Notebooks

```python
import requests

# Submit anomaly to coordination engine
response = requests.post(
    'http://coordination-engine:8080/api/v1/anomalies',
    json={
        'timestamp': '2025-11-06T12:00:00Z',
        'type': 'memory_leak',
        'severity': 'high',
        'source': 'notebook-anomaly-detection',
        'details': {
            'namespace': 'production',
            'pod': 'app-server-abc123',
            'memory_usage_mb': 7800,
            'threshold_mb': 6000
        },
        'confidence_score': 0.89,
        'recommended_action': 'restart_pod'
    }
)

print(f"Anomaly ID: {response.json()['anomaly_id']}")
```

---

## Secrets Management

### CRITICAL: External Secrets Operator (MANDATORY)

**⚠️ IMPORTANT**: Secrets management is **NOT OPTIONAL**. Every pattern deployment MUST implement proper secrets management using the External Secrets Operator.

**Reference**:
- [ADR-026: Secrets Management Automation with External Secrets Operator](docs/adrs/026-secrets-management-automation.md)
- [Red Hat Official Documentation: External Secrets Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/security_and_compliance/external-secrets-operator-for-red-hat-openshift)

### What Requires Secrets Management

- 🔐 **Database credentials** (PostgreSQL, MongoDB for coordination engine)
- 🔑 **API keys** (OpenAI, Prometheus, external APIs)
- 📝 **TLS certificates** (service mesh, ingress)
- 🔓 **SSH keys** (Git repository access)
- 🛡️ **OAuth tokens** (GitHub webhooks, SSO)
- 🔑 **Model storage credentials** (S3, ODF)
- 🔐 **Gitea credentials** (development repositories)

### Secrets Backends Supported

**Recommended Priority Order**:

1. **External Secrets Operator + AWS Secrets Manager** (PRODUCTION)
   - Centralized storage, automatic rotation, enterprise security
   - See: [ESO AWS SecretStore](https://external-secrets.io/latest/provider/aws-secrets-manager/)

2. **External Secrets Operator + HashiCorp Vault** (ENTERPRISE)
   - Complete secrets platform, policy-based access, audit logging
   - See: [ESO Vault Documentation](https://external-secrets.io/latest/provider/hashicorp-vault/)

3. **External Secrets Operator + Azure Key Vault** (AZURE CLOUD)
   - Native Azure integration, managed service
   - See: [ESO Azure Documentation](https://external-secrets.io/latest/provider/azure-key-vault/)

4. **Sealed Secrets** (DEVELOPMENT)
   - GitOps-friendly, version-controlled
   - NOT recommended for production sensitive data

### Implementation Using Validated Patterns Role

**Ansible Role**: `ansible/roles/validated_patterns_secrets/`

**Deploy Secrets Management**:
```bash
ansible-playbook ansible/playbooks/deploy_secrets.yml \
  --extra-vars "secrets_backend=aws"
```

**Or via End-User Workflow**:
```bash
# Configure in values-hub.yaml
secrets_management:
  enabled: true
  backend: aws  # or vault, azure, sealed-secrets
  aws:
    region: us-east-1
    secretsmanager_endpoint: https://secretsmanager.us-east-1.amazonaws.com

# Deploy
make -f common/Makefile operator-deploy
```

### Deployment Checklist

Before deploying any pattern component, verify:

- ✅ **Backend selected** (AWS, Vault, Azure, or Sealed Secrets)
- ✅ **Backend credentials configured** in cluster or via OIDC
- ✅ **validated_patterns_secrets role** included in playbook
- ✅ **SecretStore created** in namespace
- ✅ **External Secrets defined** for each credential type
- ✅ **Rotation policies configured** (if backend supports it)
- ✅ **RBAC policies set** (who can read/write secrets)
- ✅ **Audit logging enabled** (for compliance)
- ✅ **Tested with dummy values** first

### Example: Creating External Secret

```yaml
# k8s/base/coordination-engine-secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: coordination-engine-db-credentials
  namespace: self-healing-platform
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretstore
    kind: SecretStore
  target:
    name: coordination-engine-db-credentials
    creationPolicy: Owner
  data:
    - secretKey: database_url
      remoteRef:
        key: self-healing-platform/coordination-engine
        property: database_url
    - secretKey: db_password
      remoteRef:
        key: self-healing-platform/coordination-engine
        property: db_password
```

### Common Secrets Mistakes (AVOID)

- ❌ **Storing secrets in ConfigMaps** - Use External Secrets Operator
- ❌ **Committing secrets to git** - Even encrypted secrets should use proper backend
- ❌ **Using base64 "secrets"** - Base64 is NOT encryption
- ❌ **Hardcoding credentials in notebooks** - Use environment variables from secrets
- ❌ **Single shared credentials** - Use per-application and per-environment
- ❌ **No rotation** - Implement automatic rotation policies
- ❌ **No audit logging** - Track all secret access for compliance

---

## Testing Strategy

### Testing Pyramid

```
                    ┌─────────────────────┐
                    │   E2E Tests         │
                    │   (Tekton Pipelines)│
                    └─────────────────────┘
                          /         \
               ┌──────────────────────────────┐
               │   Integration Tests          │
               │   (Notebook Validation)      │
               └──────────────────────────────┘
                        /           \
             ┌──────────────────────────────────┐
             │   Unit Tests                     │
             │   (MCP Server, Coordination Eng.)│
             └──────────────────────────────────┘
```

### 1. Unit Tests

**Coordination Engine (Python)**:
```bash
cd src/coordination-engine
pytest tests/
```

### 2. Notebook Validation

**Prerequisites Validation Notebook**:
```bash
# Execute 00-platform-readiness-validation.ipynb
# Validates:
# - OpenShift connectivity
# - Required operators
# - GPU availability
# - Storage configuration
```

**Reference**: [ADR-029: Infrastructure Validation Notebook](docs/adrs/029-infrastructure-validation-notebook.md)

**Integration Tests in Notebooks**:
```python
# In any notebook, include validation section:

# ============================================================
# VALIDATION SECTION
# ============================================================
import requests

# Test coordination engine connectivity
response = requests.get('http://coordination-engine:8080/health')
assert response.status_code == 200, "Coordination engine not healthy"

# Test model serving endpoint
response = requests.post(
    'http://anomaly-detector-predictor:8080/v1/models/anomaly-detector:predict',
    json={'instances': [[0.5, 0.3, 0.8]]}
)
assert response.status_code == 200, "Model serving endpoint not responding"

print("✅ All integration tests passed")
```

### 3. End-to-End Tests (Ansible-based)

**Using Validated Patterns Roles**:

```yaml
# tests/integration/playbooks/test_end_to_end.yml
- name: E2E Test with Role-Based Approach
  hosts: localhost
  tasks:
    # 1. Pre-test cleanup using role (MANDATORY)
    - include_role:
        name: validated_patterns_cleanup
      # Default behavior retains shared infrastructure

    # 2. Deploy using role
    - include_role:
        name: validated_patterns_operator

    # 3. Validate using specific task files (not entire roles)
    - include_tasks: ../../ansible/roles/validated_patterns_validate/tasks/validate_health.yml

    # 4. Validate notebooks execution
    - name: Execute validation notebook
      shell: |
        oc exec -it self-healing-workbench-0 -n self-healing-platform -- \
          jupyter nbconvert --to notebook --execute \
          /opt/app-root/src/notebooks/00-setup/00-platform-readiness-validation.ipynb

    # 5. Post-test cleanup using role
    - include_role:
        name: validated_patterns_cleanup
```

**Run E2E Tests**:
```bash
ansible-navigator run tests/integration/playbooks/test_end_to_end.yml \
  --container-engine podman \
  --execution-environment-image openshift-aiops-platform-ee:latest \
  --mode stdout
```

**Reference**: See [`my-pattern/AGENTS.md`](my-pattern/AGENTS.md) for detailed Ansible role testing guidelines.

### 4. Tekton Pipelines (Post-Deployment Validation)

**Reference**: [ADR-021: Tekton Pipeline for Post-Deployment Validation](docs/adrs/021-tekton-pipeline-deployment-validation.md)

**Main Validation Pipeline**: `tekton/pipelines/deployment-validation-pipeline.yaml`

**26 Validation Checks**:
- Prerequisites (5 checks): cluster, tools, RBAC, namespace
- Operators (5 checks): GitOps, AI, KServe, GPU, ODF
- Storage (4 checks): classes, PVCs, ODF, S3
- Model Serving (4 checks): InferenceServices, endpoints, pods, metrics
- Coordination Engine (4 checks): deployment, health, API, DB
- Monitoring (4 checks): Prometheus, alerts, Grafana, logging

**Run Validation Pipeline**:
```bash
# Manual execution
tkn pipeline start deployment-validation-pipeline \
  --param namespace=self-healing-platform \
  --param cluster-version=4.18 \
  --showlog

# View pipeline runs
tkn pipelinerun list -n openshift-pipelines

# View logs
tkn pipelinerun logs <run-name> -n openshift-pipelines
```

**Automated Execution (GitHub Webhook)**:
```bash
# Apply webhook trigger
oc apply -f tekton/triggers/deployment-validation-trigger.yaml

# Get webhook URL
oc get route deployment-validation-trigger -n openshift-pipelines -o jsonpath='{.spec.host}'

# Configure in GitHub:
# Settings → Webhooks → Add webhook
# URL: <route-url-from-above>
# Events: push
```

**CI/CD Integration**:
```bash
# After deployment
make -f common/Makefile operator-deploy

# Run validation
tkn pipeline start deployment-validation-pipeline --showlog

# Check exit code
if [ $? -eq 0 ]; then
  echo "✅ Deployment validation passed"
else
  echo "❌ Deployment validation failed"
  exit 1
fi
```

### Testing Best Practices

1. **Always clean up before testing**: Run cleanup role to ensure fresh state
2. **Reuse role tasks, not entire roles**: Include specific task files for efficiency
3. **Test in isolation**: Each test should be independently runnable
4. **Validate cleanup**: Ensure all resources removed after test completion
5. **Document test scenarios**: Clearly explain what each test validates
6. **Use Tekton pipelines**: Automate post-deployment validation

---

## Deployment

### Deployment Options

The platform supports **two deployment workflows**:

1. **Development Workflow** (Granular Control)
   - Uses Ansible roles 1-2, 4-7 for step-by-step deployment
   - Best for: Pattern development, debugging, learning, customization

2. **End-User Workflow** (Simplified) - **RECOMMENDED**
   - Uses Validated Patterns Operator (role 3)
   - Best for: Production deployment, operations teams, existing patterns

**Reference**: [ADR-019: Validated Patterns Framework Adoption](docs/adrs/019-validated-patterns-framework-adoption.md)

### Development Workflow (Ansible Roles)

**Playbook**: `ansible/playbooks/deploy_complete_pattern.yml`

**Execution Order**:
1. `validated_patterns_prerequisites` - Validate cluster readiness
2. `validated_patterns_common` - Install foundation (Helm, ArgoCD)
3. `validated_patterns_gitea` - (Optional) Setup local git for development
4. `validated_patterns_secrets` - Configure secrets management
5. `validated_patterns_deploy` - Deploy application patterns
6. `validated_patterns_validate` - Post-deployment validation

**Deploy**:
```bash
ansible-navigator run ansible/playbooks/deploy_complete_pattern.yml \
  --container-engine podman \
  --execution-environment-image openshift-aiops-platform-ee:latest \
  --mode stdout
```

**Reference**: See [`my-pattern/AGENTS.md`](my-pattern/AGENTS.md) for detailed Ansible role documentation.

### End-User Workflow (VP Operator) - **RECOMMENDED**

**Simplest Deployment**:
```bash
# Configure values
vi values-hub.yaml
vi values-secret.yaml

# Deploy
make -f common/Makefile operator-deploy

# Validate
make -f common/Makefile argo-healthcheck

# Run post-deployment validation
tkn pipeline start deployment-validation-pipeline --showlog
```

**Benefits**:
- ✅ Single command deployment
- ✅ Automatic prerequisite validation
- ✅ Built-in error handling and recovery
- ✅ No need to understand Ansible roles
- ✅ Production-ready with health checks

### GitOps Deployment (ArgoCD)

**ArgoCD Application**:
```yaml
# Automatically created by Validated Patterns framework
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: self-healing-platform
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/openshift-aiops/openshift-aiops-platform
    targetRevision: main
    path: charts/hub
    helm:
      values: |
        global:
          pattern: self-healing-platform
  destination:
    server: https://kubernetes.default.svc
    namespace: self-healing-platform
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Monitor Deployment**:
```bash
# View ArgoCD applications
oc get applications -n openshift-gitops

# Check sync status
make -f common/Makefile argo-healthcheck
```

**Reference**: [ADR-027: CI/CD Pipeline Automation with Tekton and ArgoCD](docs/adrs/027-cicd-pipeline-automation.md)

### Cleanup

**Using Cleanup Role** (RECOMMENDED):
```bash
ansible-navigator run ansible/playbooks/cleanup_pattern.yml \
  --container-engine podman \
  --execution-environment-image openshift-aiops-platform-ee:latest \
  --mode stdout
```

**Default Behavior** (retains shared infrastructure):
- `cleanup_gitops: false` → Keep ArgoCD (shared infrastructure)
- `cleanup_gitea: false` → Keep Gitea (for development)
- `cleanup_operator: false` → Keep VP Operator (reusable)

**Manual Cleanup** (if needed):
```bash
# Delete Pattern CR
oc delete pattern self-healing-platform -n openshift-operators

# Delete ArgoCD applications
oc delete applications --all -n openshift-gitops

# Delete application namespaces
oc delete namespace self-healing-platform
```

**Reference**: See [`my-pattern/AGENTS.md`](my-pattern/AGENTS.md) for comprehensive cleanup procedures.

---

## ADR Management

### What are ADRs?

**Architectural Decision Records (ADRs)** document significant architectural decisions made during platform development.

**Location**: `docs/adrs/`
**Count**: 29+ ADRs (and growing)

**Format**: [MADR (Markdown Architectural Decision Records)](https://adr.github.io/madr/)

### ADR Index

See [`docs/adrs/README.md`](docs/adrs/README.md) for complete index. Key ADRs:

| ADR | Title | Status | Relevance |
|-----|-------|--------|-----------|
| [ADR-001](docs/adrs/001-openshift-platform-selection.md) | OpenShift 4.18+ as Foundation | Accepted | Platform choice |
| [ADR-002](docs/adrs/002-hybrid-self-healing-approach.md) | Hybrid Deterministic-AI Approach | Accepted | Core architecture |
| [ADR-003](docs/adrs/003-openshift-ai-ml-platform.md) | Red Hat OpenShift AI for ML | Accepted | ML platform |
| [ADR-004](docs/adrs/004-kserve-model-serving.md) | KServe for Model Serving | Accepted | Model deployment |
| [ADR-012](docs/adrs/012-notebook-architecture-for-end-to-end-workflows.md) | Notebook Architecture | Proposed | Notebook workflows |
| [ADR-036](docs/adrs/036-go-based-standalone-mcp-server.md) | Go-Based Standalone MCP Server | Proposed | **Supersedes ADR-014** |
| [ADR-019](docs/adrs/019-validated-patterns-framework-adoption.md) | Validated Patterns Framework | Accepted | Deployment framework |
| [ADR-021](docs/adrs/021-tekton-pipeline-deployment-validation.md) | Tekton Pipelines | Accepted | CI/CD validation |
| [ADR-026](docs/adrs/026-secrets-management-automation.md) | Secrets Management | Accepted | External Secrets Operator |

### When to Create/Update ADRs

**⚠️ CRITICAL FOR AI AGENTS**: You MUST create or update ADRs when making architectural changes.

**Create New ADR When**:
- ✅ Changing platform components (e.g., switching from Isolation Forest to LSTM for anomaly detection)
- ✅ Adding new integration points (e.g., integrating with external monitoring systems)
- ✅ Modifying deployment patterns (e.g., adding multi-cluster support)
- ✅ Changing security models (e.g., switching secrets backends)
- ✅ Adding new workflows (e.g., introducing new notebook categories)
- ✅ Modifying API contracts (e.g., changing coordination engine endpoints)

**Update Existing ADR When**:
- ✅ Implementation status changes (Proposed → Accepted → Implemented)
- ✅ Technical details evolve (e.g., operator version upgrades)
- ✅ Consequences become clearer (e.g., performance metrics validated)
- ✅ Related decisions emerge (e.g., linking to new ADRs)

**ADR Template**:
```markdown
# ADR-XXX: [Title]

## Status
[Proposed | Accepted | Deprecated | Superseded]

## Context
[What is the issue we're trying to solve? What forces are at play?]

## Decision
[What is the architectural decision we're making?]

## Consequences
### Positive
[Benefits of this decision]

### Negative
[Drawbacks and tradeoffs]

### Neutral
[Observations and considerations]

## Related ADRs
[Link to related ADRs]

## References
[External documentation, PRD sections, etc.]
```

**Example: Creating ADR for New Anomaly Detection Algorithm**:
```bash
# 1. Create new ADR file
touch docs/adrs/030-autoencoder-anomaly-detection.md

# 2. Use ADR template
cat > docs/adrs/030-autoencoder-anomaly-detection.md <<'EOF'
# ADR-030: Autoencoder-Based Anomaly Detection

## Status
Proposed

## Context
Current Isolation Forest algorithm (ADR-013) works well for tabular data but
struggles with high-dimensional time series data. We need better detection for
complex temporal patterns in metrics like network traffic and pod resource usage.

## Decision
We will implement an Autoencoder-based anomaly detection model using TensorFlow
to complement the existing Isolation Forest approach.

### Architecture
- LSTM Autoencoder with 3 hidden layers
- Trained on normal cluster behavior (7 days of metrics)
- Reconstruction error as anomaly score
- Deployed via KServe for real-time inference

## Consequences
### Positive
- Better detection of temporal anomalies
- Reduced false positives for time series data
- Improved accuracy for network-related incidents

### Negative
- Higher computational cost (requires GPU)
- More complex model training pipeline
- Longer training time (4-6 hours vs. 15 minutes)

## Related ADRs
- [ADR-013: Data Collection and Preprocessing](013-data-collection-and-preprocessing-workflows.md)
- [ADR-004: KServe for Model Serving](004-kserve-model-serving.md)

## References
- Notebook: notebooks/02-anomaly-detection/05-autoencoder-lstm.ipynb
- Research paper: "Anomaly Detection in Time Series with LSTM Autoencoders"
EOF

# 3. Update ADR index
vi docs/adrs/README.md
# Add: | [ADR-030](030-autoencoder-anomaly-detection.md) | Autoencoder Anomaly Detection | Proposed | 2025-11-06 |

# 4. Commit with clear message
git add docs/adrs/030-autoencoder-anomaly-detection.md docs/adrs/README.md
git commit -m "docs(adr): add ADR-030 for autoencoder anomaly detection"
git push
```

### ADR Review Process

**Before Implementing Major Changes**:
1. ✅ **Check existing ADRs**: Read related ADRs to understand context
2. ✅ **Create draft ADR**: Document your decision with template
3. ✅ **Review with team**: Share ADR for feedback (if working with team)
4. ✅ **Update status**: Mark as "Accepted" when ready to implement
5. ✅ **Link to implementation**: Reference notebooks, code, or configs

**After Implementation**:
1. ✅ **Update status**: Mark as "Implemented"
2. ✅ **Document consequences**: Add actual performance metrics, issues encountered
3. ✅ **Link related work**: Connect to new notebooks, code changes, PRs
4. ✅ **Update index**: Ensure README.md reflects current state

---

## Common Pitfalls

### 1. GPU Resource Allocation

**Pitfall**: Notebooks or model serving pods fail with "GPU not available" despite GPU nodes existing.

**Solution**:
```bash
# Check GPU availability
oc get nodes -l nvidia.com/gpu.present=true

# Check GPU allocation
oc describe node <gpu-node-name> | grep -A 10 "Allocated resources"

# Verify GPU operator
oc get csv -n openshift-operators | grep gpu-operator

# Check notebook GPU request
oc get notebook self-healing-workbench -n self-healing-platform -o yaml | grep -A 5 nvidia.com/gpu
```

**Reference**: [ADR-006: NVIDIA GPU Operator for AI Workload Management](docs/adrs/006-nvidia-gpu-management.md)

### 2. Notebook Kernel Crashes

**Pitfall**: Jupyter kernel crashes when running memory-intensive operations.

**Solution**:
```python
# Clear memory periodically in notebooks
import gc

# After large operations
gc.collect()

# Use chunking for large datasets
import pandas as pd

# Instead of: df = pd.read_parquet('large_file.parquet')
# Use:
chunks = pd.read_parquet('large_file.parquet', chunksize=10000)
for chunk in chunks:
    process_chunk(chunk)
    gc.collect()
```

**Check Memory Limits**:
```bash
oc get notebook self-healing-workbench -n self-healing-platform -o yaml | grep -A 5 memory
```

### 3. MCP Server Connectivity

**Pitfall**: OpenShift Lightspeed cannot connect to MCP server.

**Note**: The MCP server is now a standalone Go-based project. See [ADR-036](docs/adrs/036-go-based-standalone-mcp-server.md).

**Solution**:
```bash
# Check MCP server pod status (if deployed from standalone repo)
oc get pods -n self-healing-platform | grep cluster-health-mcp

# Check logs
oc logs -n self-healing-platform <mcp-server-pod> --tail=100

# Verify OLSConfig
oc get olsconfig cluster -o yaml
```

**Reference**: [ADR-036: Go-Based Standalone MCP Server](docs/adrs/036-go-based-standalone-mcp-server.md)

### 4. Coordination Engine Not Responding

**Pitfall**: Notebooks cannot submit anomalies to coordination engine.

**Solution**:
```bash
# Check coordination engine health
curl http://coordination-engine.self-healing-platform.svc.cluster.local:8080/health

# Check pod status
oc get pods -n self-healing-platform | grep coordination-engine

# Check logs
oc logs -n self-healing-platform <coordination-engine-pod> --tail=100

# Test from within workbench pod
oc exec -it self-healing-workbench-0 -n self-healing-platform -- \
  curl http://coordination-engine:8080/health
```

### 5. Persistent Storage Issues

**Pitfall**: Notebooks fail to save data to persistent storage.

**Solution**:
```bash
# Check PVC status
oc get pvc -n self-healing-platform

# Check PVC binding
oc describe pvc <pvc-name> -n self-healing-platform

# Verify storage class
oc get storageclass

# Test write permissions in notebook
import os
test_file = '/opt/app-root/src/data/test.txt'
with open(test_file, 'w') as f:
    f.write('test')
os.remove(test_file)
print("✅ Write permissions OK")
```

**Reference**: [ADR-010: OpenShift Data Foundation as Storage Infrastructure](docs/adrs/010-openshift-data-foundation-requirement.md)

### 6. Model Serving Endpoint Not Ready

**Pitfall**: KServe InferenceService shows "READY=False".

**Solution**:
```bash
# Check InferenceService status
oc get inferenceservices -n self-healing-platform

# Check predictor pod logs
oc logs -n self-healing-platform <predictor-pod> --tail=100

# Verify model storage
oc get pvc -n self-healing-platform | grep model

# Check KServe operator
oc get csv -n openshift-operators | grep kserve
```

**Reference**: [ADR-004: KServe for Model Serving Infrastructure](docs/adrs/004-kserve-model-serving.md)

### 7. Secrets Not Syncing

**Pitfall**: External Secrets not creating Kubernetes secrets.

**Solution**:
```bash
# Check ExternalSecret status
oc get externalsecrets -n self-healing-platform

# Check SecretStore
oc get secretstore -n self-healing-platform

# Check External Secrets Operator logs
oc logs -n openshift-operators <external-secrets-operator-pod> --tail=100

# Verify backend connectivity (for AWS)
oc exec -it <pod-with-aws-cli> -- \
  aws secretsmanager get-secret-value --secret-id self-healing-platform/test
```

**Reference**: [ADR-026: Secrets Management Automation with External Secrets Operator](docs/adrs/026-secrets-management-automation.md)

### 8. ArgoCD Application Out of Sync

**Pitfall**: ArgoCD shows "OutOfSync" status for platform applications.

**Solution**:
```bash
# Check application status
oc get applications -n openshift-gitops

# View sync status details
oc describe application self-healing-platform -n openshift-gitops

# Manual sync
argocd app sync self-healing-platform

# Or via Make target
make -f common/Makefile argo-healthcheck
```

### 9. Tekton Pipeline Fails

**Pitfall**: Post-deployment validation pipeline fails unexpectedly.

**Solution**:
```bash
# View pipeline run logs
tkn pipelinerun logs <run-name> -n openshift-pipelines

# Check task status
tkn taskrun list -n openshift-pipelines

# View specific task logs
tkn taskrun logs <task-name> -n openshift-pipelines

# Re-run failed pipeline
tkn pipeline start deployment-validation-pipeline --showlog
```

**Reference**: [ADR-021: Tekton Pipeline for Post-Deployment Validation](docs/adrs/021-tekton-pipeline-deployment-validation.md)

### 10. Common Subtree Out of Sync

**Pitfall**: Pattern deployment fails due to outdated `common/` subtree.

**Solution**:
```bash
# Update common subtree
curl -s https://raw.githubusercontent.com/validatedpatterns/utilities/main/scripts/update-common-everywhere.sh | bash

# Or manual update
git remote add -f common-upstream https://github.com/validatedpatterns/common.git
git merge -s subtree -Xtheirs -Xsubtree=common common-upstream/main

# Verify common Makefile
make -f common/Makefile help
```

**Reference**: [ADR-019: Validated Patterns Framework Adoption](docs/adrs/019-validated-patterns-framework-adoption.md) - Section: Common Subtree Management

---

## References

### Documentation Structure

```
/openshift-aiops-platform/
├── AGENTS.md (THIS FILE)           # Root-level AI agent guidance
├── PRD.md                          # Product Requirements Document
├── README.md                       # Project overview (from common/)
├── my-pattern/
│   ├── AGENTS.md                   # Validated Patterns Ansible Toolkit guidance
│   ├── ONBOARDING.md               # User onboarding guide
│   └── README.md                   # Toolkit documentation
├── reference/
│   └── ansible-execution-environment/
│       └── AGENTS.md               # Ansible EE guidance
├── docs/
│   ├── adrs/                       # 29+ Architectural Decision Records
│   │   ├── README.md               # ADR index
│   │   ├── 001-openshift-platform-selection.md
│   │   ├── 002-hybrid-self-healing-approach.md
│   │   ├── 012-notebook-architecture-for-end-to-end-workflows.md
│   │   ├── 014-openshift-aiops-platform-mcp-server.md
│   │   ├── 019-validated-patterns-framework-adoption.md
│   │   ├── 021-tekton-pipeline-deployment-validation.md
│   │   └── 026-secrets-management-automation.md
│   ├── tutorials/                  # Learning-oriented guides
│   ├── how-to/                     # Task-oriented guides
│   ├── reference/                  # Information-oriented docs
│   └── explanation/                # Understanding-oriented content
├── notebooks/
│   └── README.md                   # Notebook architecture and workflows
├── tekton/
│   └── README.md                   # Tekton pipelines documentation
└── src/
    └── coordination-engine/README.md  # Python Flask REST API service
```

### Key Documentation

**Platform Documentation**:
- [PRD.md](PRD.md) - Product Requirements Document (vision, goals, acceptance criteria)
- [README.md](README.md) - Common subtree README (Validated Patterns overview)
- [notebooks/README.md](notebooks/README.md) - Notebook workflows and structure
- [tekton/README.md](tekton/README.md) - Tekton pipeline validation details

**Subdirectory AGENTS.md Files** (for specific subsystems):
- [`my-pattern/AGENTS.md`](my-pattern/AGENTS.md) - Validated Patterns Ansible Toolkit (**REFERENCE ONLY - DO NOT COMMIT**)
- [`reference/ansible-execution-environment/AGENTS.md`](reference/ansible-execution-environment/AGENTS.md) - Ansible EE

**⚠️ IMPORTANT NOTE**: The `my-pattern/` directory is for **reference purposes only** and should be in `.gitignore`. It contains toolkit examples and should not be pushed to this repository.

**Architectural Decision Records** (29+ ADRs):
- [`docs/adrs/README.md`](docs/adrs/README.md) - Complete ADR index
- Start with: ADR-001, ADR-002, ADR-012, ADR-014, ADR-019, ADR-021, ADR-026

**Onboarding & Guides**:
- [`my-pattern/ONBOARDING.md`](my-pattern/ONBOARDING.md) - User onboarding (git subtree, Gitea, development workflow)

### External References

**Red Hat Official Documentation**:
- [OpenShift 4.18 Documentation](https://docs.openshift.com/container-platform/4.18/)
- [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
- [External Secrets Operator for OpenShift](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/security_and_compliance/external-secrets-operator-for-red-hat-openshift)
- [OpenShift GitOps Documentation](https://docs.openshift.com/gitops/latest/)
- [OpenShift Pipelines (Tekton) Documentation](https://docs.openshift.com/pipelines/latest/)

**Upstream Projects**:
- [Validated Patterns Framework](https://validatedpatterns.io/)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io/)
- [KServe Documentation](https://kserve.github.io/website/)
- [Kubeflow Pipelines](https://www.kubeflow.org/docs/components/pipelines/)

**Best Practices**:
- [MADR (Markdown ADR Format)](https://adr.github.io/madr/)
- [Diátaxis Documentation Framework](https://diataxis.fr/)

---

## Methodological Pragmatism Considerations

As Sophia, I approach this platform with explicit awareness of error architectures:

### 1. Explicit Fallibilism
- **Acknowledge limitations**: AI models have false positives; deterministic rules can be incomplete
- **Uncertainty quantification**: Confidence scores required for all AI-driven actions (minimum 80%)
- **Human override**: Always available via OpenShift Lightspeed interface

### 2. Systematic Verification
- **Multi-layer testing**: Unit → Integration → E2E → Tekton validation
- **ADR-driven architecture**: Every major decision documented and reviewable
- **Continuous validation**: 26 Tekton checks ensure deployment health

### 3. Pragmatic Success Criteria
- **MTTR reduction**: Target 50% (measurable, specific)
- **False positive rate**: <5% (quantifiable constraint)
- **Coverage**: 80% automated handling within 6 months (time-bound goal)

### 4. Cognitive Systematization
- **Notebook-centric workflow**: Organized knowledge (8 categories, clear dependencies)
- **ADR knowledge base**: Architectural context preserved and linked
- **Coordination engine**: Centralized orchestration preventing conflicts

### 5. Error Architecture Awareness

**Human-Cognitive Errors to Watch**:
- Confusing "Self-Healing Platform" (this project) with "Validated Patterns Toolkit" (subdirectory)
- **Committing my-pattern/ to git** (it's reference-only and should be in .gitignore)
- Skipping ADR creation when making architectural changes
- Forgetting to update common/ subtree before major development
- Not implementing secrets management (treating as optional instead of mandatory)

**Artificial-Stochastic Errors to Watch**:
- Pattern completion merging incompatible code patterns (e.g., mixing MCP stdio with HTTP)
- Assuming notebook execution order is arbitrary (it's not - dependencies exist)
- Generating code without checking ADRs for established decisions
- Creating secrets management code that doesn't use External Secrets Operator

### 6. Confidence Scores

When suggesting significant changes, I'll provide confidence levels:
- **Confidence: 95%** - Based on explicit ADR, PRD requirement, or proven pattern
- **Confidence: 85%** - Based on best practices and related implementations
- **Confidence: 70%** - Speculative but informed by domain knowledge
- **Confidence: 50%** - Exploratory; requires verification and ADR creation

### 7. Verification Framework

For major recommendations, I'll include:
1. **ADR Check**: Link to relevant ADRs that support or contradict the recommendation
2. **Testing Path**: How to validate the change (notebooks, E2E tests, Tekton)
3. **Rollback Plan**: How to revert if the change causes issues
4. **Documentation**: Which ADRs/docs need updating

---

## Quick Reference Commands

### Setup & Validation
```bash
# Validate cluster prerequisites
make check-prerequisites

# Deploy platform (end-user workflow)
make -f common/Makefile operator-deploy

# Validate deployment
make -f common/Makefile argo-healthcheck
tkn pipeline start deployment-validation-pipeline --showlog
```

### Development
```bash
# Access Jupyter notebooks
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform

# Deploy using Ansible roles (development workflow)
ansible-navigator run ansible/playbooks/deploy_complete_pattern.yml --mode stdout

# Test coordination engine
cd src/coordination-engine && pytest
```

### Troubleshooting
```bash
# Check GPU availability
oc get nodes -l nvidia.com/gpu.present=true

# Check all pods
oc get pods -n self-healing-platform

# View coordination engine logs
oc logs -n self-healing-platform <coordination-engine-pod> --tail=100

# Check secrets sync status
oc get externalsecrets -n self-healing-platform
```

### Cleanup
```bash
# Cleanup using role (retains shared infrastructure)
ansible-navigator run ansible/playbooks/cleanup_pattern.yml --mode stdout

# Manual cleanup
oc delete pattern self-healing-platform -n openshift-operators
oc delete applications --all -n openshift-gitops
```

### ADR Management
```bash
# View ADR index
cat docs/adrs/README.md

# Create new ADR
cp docs/adrs/template.md docs/adrs/XXX-new-decision.md

# Update ADR index
vi docs/adrs/README.md
```

---

## Final Notes

**This is the Self-Healing Platform** - a production AI/ML operations platform, NOT a deployment toolkit. For toolkit-specific guidance, see:
- **Ansible Roles**: [`my-pattern/AGENTS.md`](my-pattern/AGENTS.md) - **REFERENCE ONLY, DO NOT COMMIT TO GIT**
- **Execution Environment**: [`reference/ansible-execution-environment/AGENTS.md`](reference/ansible-execution-environment/AGENTS.md)

**⚠️ GIT REMINDER**: The `my-pattern/` directory is for reference purposes only and should be in your `.gitignore`. Never commit or push it to this repository.

**When in Doubt**:
1. ✅ **Check ADRs**: Start with `docs/adrs/README.md`
2. ✅ **Run validation notebook**: `notebooks/00-setup/00-platform-readiness-validation.ipynb`
3. ✅ **Test integration**: Use coordination engine health checks
4. ✅ **Validate with Tekton**: Run post-deployment validation pipeline
5. ✅ **Create/Update ADRs**: Document architectural changes
6. ✅ **Implement secrets management**: Use External Secrets Operator (MANDATORY)

**Remember**: The platform uses a **hybrid deterministic-AI approach** (ADR-002). Always consider both layers when making changes and ensure the coordination engine can orchestrate them effectively.

---

**Made with methodological pragmatism by Sophia 🤖**
**Last Updated**: 2025-11-06
**Platform Version**: 1.0
**Confidence**: 92%
