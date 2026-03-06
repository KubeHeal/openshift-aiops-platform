# CLAUDE.md - AI Agent Quick Reference for OpenShift AI Ops Self-Healing Platform

**Purpose**: This guide helps AI assistants (Claude Code, ChatGPT, etc.) quickly understand and assist users with deploying and troubleshooting the OpenShift AI Ops Self-Healing Platform.

**Target Audience**: AI agents helping users with deployment, configuration, and troubleshooting.

**Last Updated**: 2026-03-06

---

## Table of Contents

1. [Project Overview](#section-1-project-overview)
2. [RHEL 9/10 Workstation Setup](#section-2-rhel-910-workstation-setup)
3. [Complete Deployment Workflow](#section-3-complete-deployment-workflow)
4. [SNO vs HA Differences](#section-4-sno-vs-ha-differences)
5. [Common Troubleshooting](#section-5-common-troubleshooting)
6. [Key Architecture Decisions](#section-6-key-architecture-decisions)
7. [Quick Reference Commands](#section-7-quick-reference-commands)
8. [File Locations Reference](#section-8-file-locations-reference)
9. [Agent Response Patterns](#section-9-agent-response-patterns)
10. [Important Reminders + Glossary](#section-10-important-reminders--glossary)

---

## Section 1: Project Overview

### What is This Platform?

The **OpenShift AI Ops Self-Healing Platform** is a production-ready AIOps solution that combines:

- **🤖 Hybrid Approach**: Deterministic automation (Machine Config Operator, rule-based) + AI-driven analysis (ML models, anomaly detection)
- **🔧 Self-Healing**: Automatically detects and remediates common cluster issues
- **📊 ML-Powered**: Uses Isolation Forest and LSTM models for anomaly detection
- **🚀 OpenShift Native**: Built on Red Hat OpenShift AI, KServe, Tekton, ArgoCD
- **💬 Natural Language Interface**: Integrates with OpenShift Lightspeed via MCP (Model Context Protocol)
- **🌐 Platform Agnostic**: Supports both vanilla Kubernetes and OpenShift clusters

### Key Components

| Component | Version | Purpose |
|-----------|---------|---------|
| **Red Hat OpenShift AI** | 2.22.2 | ML platform for model training and serving |
| **KServe** | 1.36.1 | Model serving infrastructure |
| **Coordination Engine** | Go-based | Orchestrates hybrid deterministic-AI approach |
| **Tekton Pipelines** | 1.17.2 | CI/CD automation and validation |
| **OpenShift GitOps (ArgoCD)** | 1.15.4 | GitOps deployment |
| **GPU Operator** | 24.9.2 | NVIDIA GPU management |
| **External Secrets Operator** | Latest | Secrets management automation |
| **MCP Server** | Standalone (Go) | Model Context Protocol for Lightspeed integration |

### Repository Structure

```
openshift-aiops-platform/
├── ansible/                    # Ansible roles and playbooks
│   ├── roles/                  # 8 production-ready reusable roles
│   └── playbooks/              # Deployment, validation, cleanup
├── charts/                     # Helm charts
│   └── hub/                    # Main pattern chart
├── docs/                       # Documentation
│   ├── adrs/                   # Architectural Decision Records (58+ ADRs)
│   ├── guides/                 # How-to guides
│   └── how-to/                 # Deployment guides
├── k8s/                        # Kubernetes manifests
│   ├── operators/              # Operator deployments
│   └── mcp-server/             # MCP server manifests
├── notebooks/                  # Jupyter notebooks (ML workflows)
│   ├── 00-setup/               # Platform validation
│   ├── 01-data-collection/     # Metrics, logs, events
│   ├── 02-anomaly-detection/   # ML models
│   ├── 03-self-healing-logic/  # Integration
│   ├── 04-model-serving/       # KServe deployment
│   └── 05-end-to-end-scenarios/# Complete use cases
├── src/                        # Source code (models, utilities)
├── tekton/                     # CI/CD pipelines (26 validation checks)
├── tests/                      # Test suites
├── scripts/                    # Automation scripts
├── Makefile                    # Main build/deploy/test targets
├── AGENTS.md                   # 🤖 AI agent development guide (comprehensive)
├── CLAUDE.md                   # 🤖 AI agent quick reference (this file)
└── README.md                   # Quick start guide
```

### Documentation Links

| Document | Purpose |
|----------|---------|
| **[AGENTS.md](AGENTS.md)** | 📖 Comprehensive AI agent development guide (1,800+ lines) |
| **[CLAUDE.md](CLAUDE.md)** | 🚀 AI agent quick reference (deployment and troubleshooting) |
| **[README.md](README.md)** | ⚡ Quick start guide for users |
| **[DEPLOYMENT.md](DEPLOYMENT.md)** | 📋 Step-by-step deployment guide |
| **[docs/adrs/](docs/adrs/)** | 🏛️ Architectural Decision Records (58+ ADRs) |
| **[docs/guides/TROUBLESHOOTING-GUIDE.md](docs/guides/TROUBLESHOOTING-GUIDE.md)** | 🔧 Troubleshooting guide |
| **[docs/guides/JUNIOR-DEVELOPER-DEPLOYMENT-GUIDE.md](docs/guides/JUNIOR-DEVELOPER-DEPLOYMENT-GUIDE.md)** | 👨‍💻 Junior developer guide |
| **[docs/how-to/deploy-on-sno.md](docs/how-to/deploy-on-sno.md)** | 🖥️ SNO deployment guide |

---

## Section 2: RHEL 9/10 Workstation Setup

### Prerequisites Script Location

**Script**: `scripts/install-prerequisites-rhel.sh`

**Purpose**: One-time automated setup of all required tools for deploying the platform from a RHEL 9 or RHEL 10 workstation.

### Quick Start

```bash
# Run from the cloned repository directory
./scripts/install-prerequisites-rhel.sh

# Activate environment (start new terminal or run)
source ~/.bashrc
```

### What the Script Installs

#### System Packages (via `dnf`)

- **Container runtime**: `podman`, `skopeo`
- **Development tools**: `git`, `make`, `jq`, `gcc`, `gcc-c++`
- **Python**: `python3`, `python3-pip`, `python3-devel`
- **Development headers**: `openssl-devel`, `libcurl-devel`, `openldap-devel`, `libpq-devel`
- **Utilities**: `rsync`, `unzip`, `tar`, `curl`, `wget`, `gettext` (envsubst)

#### Python Virtual Environment (`~/.venv/aiops-platform`)

- `ansible-navigator` (with ansible-core)
- `ansible-builder`
- `ansible-lint`
- `molecule`
- `kubernetes`
- `openshift-client`
- `jmespath`
- `netaddr`

#### Ansible Collections

- `kubernetes.core`
- `community.general`
- `ansible.posix`

#### CLI Tools (installed to `/usr/local/bin/`)

| Tool | Version | Purpose |
|------|---------|---------|
| **oc** | 4.18 | OpenShift CLI |
| **kubectl** | 4.18 | Kubernetes CLI |
| **helm** | v3.16.4 | Kubernetes package manager |
| **yq** | v4.44.6 | YAML processor |
| **tkn** | 0.38.1 | Tekton CLI (pipeline management) |

### Script Features

✅ **Idempotent** - Safe to run multiple times
✅ **Interactive prompts** - Asks before reinstalling existing tools
✅ **RHEL version validation** - Warns on non-RHEL systems
✅ **Auto-configures shell** - Updates `.bashrc` or `.zshrc`
✅ **Validates installation** - Confirms all tools are working

### Requirements

- **OS**: RHEL 9.x or RHEL 10.x (may work on Fedora/CentOS Stream 9+)
- **Permissions**: sudo access
- **Network**: Internet connectivity

### Installation Steps

```bash
# 1. Clone the repository (see Section 3 for full workflow)
git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
cd openshift-aiops-platform

# 2. Run prerequisites installer
./scripts/install-prerequisites-rhel.sh

# 3. Activate environment
source ~/.bashrc
# OR start a new terminal
```

### Verification Commands

After running the script, verify installation:

```bash
# Check CLI tools
oc version
helm version
yq --version
tkn version

# Check Python tools (venv should be auto-activated)
ansible-navigator --version
ansible-builder --version

# Check Ansible collections
ansible-galaxy collection list | grep -E 'kubernetes.core|community.general'

# Check podman
podman --version
```

### Expected Output

```
Tool                 Status          Version
----                 ------          -------
podman               ✓ OK            podman version 4.9.4
git                  ✓ OK            git version 2.43.0
make                 ✓ OK            GNU Make 4.3
jq                   ✓ OK            jq-1.6
oc                   ✓ OK            Client Version: 4.18.21
kubectl              ✓ OK            Client Version: v1.31.0
helm                 ✓ OK            v3.16.4
yq                   ✓ OK            yq (https://github.com/mikefarah/yq/) version v4.44.6
tkn                  ✓ OK            Client version: 0.38.1
ansible-navigator    ✓ OK            ansible-navigator 24.11.0
ansible-builder      ✓ OK            ansible-builder 3.1.0
ansible-lint         ✓ OK            ansible-lint 24.12.0
kubernetes.core      ✓ OK            Ansible collection
community.general    ✓ OK            Ansible collection
ansible.posix        ✓ OK            Ansible collection

All prerequisites installed successfully!
```

### Next Steps After Script Completion

1. **Start a new terminal** or run: `source ~/.bashrc`
2. **Log into your OpenShift cluster**: `oc login <cluster-url>`
3. **Get your Ansible Hub token**: https://console.redhat.com/ansible/automation-hub/token
4. **Continue with deployment** (see Section 3)

### Alternative Setup (Non-RHEL Systems)

If not using RHEL 9/10, manually install the tools listed above using your system's package manager. Refer to:
- [README.md lines 79-87](README.md) - Prerequisites list
- [AGENTS.md](AGENTS.md) - Detailed setup instructions

---

## Section 3: Complete Deployment Workflow

### Cluster Requirements

#### HA (HighlyAvailable) Cluster

- **Nodes**: 6+ nodes (3 control-plane, 3+ workers, 1 GPU-enabled recommended)
- **CPU**: 24+ cores
- **RAM**: 96+ GB
- **Storage**: 500+ GB
- **ODF**: Full ODF (Ceph + NooBaa)
- **Use Case**: Production, full features

#### SNO (Single Node OpenShift) Cluster

- **Nodes**: 1 node (all roles: control-plane, master, worker)
- **CPU**: 8+ cores (16+ recommended)
- **RAM**: 32+ GB (64+ recommended)
- **Storage**: 120+ GB
- **ODF**: MCG-only (NooBaa S3 without Ceph)
- **Use Case**: Edge, development, testing

**Supported OpenShift Versions**: 4.18, 4.19, 4.20 (auto-detected during deployment)

### 17-Step Fork-and-Deploy Workflow

#### Step 1: Fork on GitHub

```bash
# Click "Fork" at https://github.com/KubeHeal/openshift-aiops-platform
# This creates YOUR fork at https://github.com/YOUR-USERNAME/openshift-aiops-platform
```

**⚠️ CRITICAL**: Always fork first! This allows you to customize values files and maintain your own deployment configuration.

#### Step 2: Clone YOUR Fork

```bash
git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
cd openshift-aiops-platform
```

#### Step 3: Install Prerequisites (RHEL 9/10 Only)

```bash
./scripts/install-prerequisites-rhel.sh
source ~/.bashrc
```

**Skip if tools already installed** or if not using RHEL 9/10.

#### Step 4: Login to Your Cluster

```bash
oc login <cluster-api-url>
# Example: oc login https://api.cluster.example.com:6443
```

#### Step 5: Create Values Files (REQUIRED)

```bash
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml
```

**⚠️ CRITICAL**: These files are **required before any `make` target**. The Makefile reads `values-global.yaml` on startup.

#### Step 6: Update repoURL in Both Files

```bash
# Edit values-global.yaml
vi values-global.yaml
# Change: repoURL: "https://github.com/KubeHeal/openshift-aiops-platform.git"
# To:     repoURL: "https://github.com/YOUR-USERNAME/openshift-aiops-platform.git"

# Edit values-hub.yaml
vi values-hub.yaml
# Change: repoURL: "https://gitea-with-admin-gitea.apps.cluster-pvbs6..."
# To:     repoURL: "https://github.com/YOUR-USERNAME/openshift-aiops-platform.git"
```

**⚠️ CRITICAL**: Update to YOUR fork's URL, not the upstream repository.

#### Step 7: Verify Cluster Topology

```bash
make show-cluster-info
```

**Expected Output**:

```
Cluster Information:
  Topology: ha        # or "sno"
  OpenShift Version: 4.20
  Platform: AWS
  ODF Channel: stable-4.20

Cluster Topology Information:
  Type: HA (HighlyAvailable)  # or "SNO (Single Node OpenShift)"
  Control Plane: HighlyAvailable
  Infrastructure: HighlyAvailable
  Platform: AWS
```

**🖥️ IMPORTANT**: If topology shows `sno`, also update `values-hub.yaml`:
```yaml
cluster:
  topology: "sno"

storage:
  modelStorage:
    storageClass: "gp3-csi"  # Changed from ocs-storagecluster-cephfs
```

#### Step 8: Configure Cluster Infrastructure (ODF)

```bash
make configure-cluster
```

**What this does**:
- **HA clusters**: Installs full ODF (Ceph + NooBaa), scales MachineSets (takes 10-15 min)
- **SNO clusters**: Installs MCG-only ODF (NooBaa S3 without Ceph)

**Skip ODF on HA clusters with existing storage**:
```bash
./scripts/configure-cluster-infrastructure.sh --skip-odf
```

#### Step 9: Get the Execution Environment

**Option A: Pull Pre-Built Image (Recommended)**

```bash
podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest \
  openshift-aiops-platform-ee:latest
```

**Option B: Build Locally (Requires ANSIBLE_HUB_TOKEN)**

```bash
export ANSIBLE_HUB_TOKEN='your-token-here'
podman login registry.redhat.io
make token
make build-ee
```

Get your token from: https://console.redhat.com/ansible/automation-hub/token

#### Step 10: Validate Cluster Prerequisites

```bash
make check-prerequisites
```

Verifies cluster readiness (operators, storage, networking).

#### Step 11: Run Ansible Prerequisites

```bash
make operator-deploy-prereqs
```

**What this does**:
- Creates namespaces (`self-healing-platform`, `self-healing-platform-hub`)
- Deploys RBAC resources (ServiceAccounts, Roles, ClusterRoles)
- Creates secrets (External Secrets Operator configuration)
- Grants hub-gitops ArgoCD cluster-admin permissions

#### Step 12: Deploy the Platform via Validated Patterns Operator

```bash
make operator-deploy
```

**What this does**:
- Deploys Validated Patterns Operator
- Creates Pattern CR pointing to your fork
- Operator creates ArgoCD application
- ArgoCD deploys all platform components

**Note**: Step 12 automatically runs step 11 as a dependency.

#### Step 13: Wait for ArgoCD Application

```bash
oc wait --for=jsonpath='{.kind}'=Application \
  application/self-healing-platform -n self-healing-platform-hub --timeout=120s
```

Waits for the operator to create the ArgoCD Application resource.

#### Step 14: Sync ArgoCD (If Needed)

```bash
# Manual sync or refresh may be required
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite
```

Triggers ArgoCD to sync the application.

#### Step 15: Validate Deployment

```bash
make argo-healthcheck
```

Verifies all ArgoCD applications are healthy and synced.

#### Step 16: Run Tekton Validation Pipeline

```bash
tkn pipeline start deployment-validation-pipeline --showlog
```

Validates coordination engine and model connectivity (26 validation checks).

#### Step 17: Check Model Training Pipeline Status

```bash
# ArgoCD automatically triggers initial training for both models on first deploy
tkn pipelinerun list -n self-healing-platform
```

**If training failed or was not triggered**, manually start the pipelines:

**Anomaly Detector (CPU-based)**:
```bash
tkn pipeline start model-training-pipeline \
  -p model-name=anomaly-detector \
  -p notebook-path=notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb \
  -p data-source=prometheus \
  -p training-hours=168 \
  -p inference-service-name=anomaly-detector \
  -p health-check-enabled=true \
  -p git-url=<your-repo-url> \
  -p git-ref=main \
  -n self-healing-platform --showlog
```

**Predictive Analytics (GPU-based)**:
```bash
tkn pipeline start model-training-pipeline-gpu \
  -p model-name=predictive-analytics \
  -p notebook-path=notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb \
  -p data-source=prometheus \
  -p training-hours=720 \
  -p inference-service-name=predictive-analytics \
  -p health-check-enabled=true \
  -p git-url=<your-repo-url> \
  -p git-ref=main \
  -n self-healing-platform --showlog
```

### Post-Deployment Access

**Access Jupyter notebooks**:
```bash
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
# Open http://localhost:8888
```

**Post-Deployment Cleanup (Optional)**:
```bash
# Clean up extra namespaces created by upstream Validated Patterns defaults
oc delete namespace self-healing-platform-example imperative --ignore-not-found=true
```

### 🎉 Done!

Your self-healing platform is now running.

---

## Section 4: SNO vs HA Differences

### Topology Detection Command

```bash
make show-cluster-info
```

**Output shows**:
- `Topology: sno` → Single Node OpenShift
- `Topology: ha` → HighlyAvailable (3+ nodes)

### Key Differences Table

| Feature | SNO | HA (HighlyAvailable) |
|---------|-----|----------------------|
| **Nodes** | 1 (all roles) | 3+ (separate control-plane/worker) |
| **ODF Storage** | ⚠️ MCG-only (S3) | ✅ Full ODF (Ceph + S3) |
| **Storage Classes** | CSI only (gp3-csi) | ODF + CSI (ocs-storagecluster-cephfs, gp3-csi) |
| **Replicas** | 1 (no HA) | 3+ (HA enabled) |
| **Resource Isolation** | ❌ Shared | ✅ Distributed |
| **High Availability** | ❌ No | ✅ Yes |
| **MachineSet Scaling** | ❌ No | ✅ Yes |
| **Production Ready** | ⚠️ Limited (edge/dev/test) | ✅ Yes (production) |
| **Use Case** | Edge, development, testing | Production, full features |
| **Cost** | 💰 Lower | 💰💰💰 Higher |

### SNO-Specific Configuration

When `make show-cluster-info` shows `topology: sno`, edit `values-hub.yaml` **before** step 12 (`make operator-deploy`):

```yaml
# Cluster configuration
cluster:
  topology: "sno"

# Storage classes (CSI for block/file - MCG provides S3)
storage:
  modelStorage:
    size: "10Gi"
    storageClass: "gp3-csi"  # Changed from ocs-storagecluster-cephfs

# Object store stays enabled -- MCG-only ODF provides NooBaa S3
objectStore:
  enabled: true
```

### SNO Deployment Behavior

**Step 8 (`make configure-cluster`)** on SNO:
- ✅ Skips MachineSet scaling (log: "Skipping Worker Node Scaling (SNO Cluster)")
- ✅ Installs ODF operator (MCG-only mode)
- ✅ Creates MCG-only StorageCluster (NooBaa S3 with gp3-csi backing)
- ✅ Waits for NooBaa to become Ready
- ❌ Does NOT install Ceph daemons (OSD, MON, MGR)

**Step 12 (`make operator-deploy`)** on SNO:
- Platform automatically detects SNO topology if `values-hub.yaml` is configured
- Reduces resource requests/limits for notebooks
- Uses CSI storage classes for PVCs
- Uses NooBaa S3 for object storage (model artifacts)

### Reference Documentation

- **[docs/how-to/deploy-on-sno.md](docs/how-to/deploy-on-sno.md)** - Complete SNO deployment guide
- **[ADR-055](docs/adrs/055-openshift-420-multi-cluster-topology-support.md)** - Multi-cluster topology support
- **[ADR-056](docs/adrs/056-standalone-mcg-on-sno.md)** - Standalone MCG on SNO
- **[ADR-057](docs/adrs/057-topology-aware-gpu-scheduling-and-storage.md)** - Topology-aware GPU scheduling

---

## Section 5: Common Troubleshooting

### Issue 1: Coordination Engine Not Responding

**Symptoms**:
- HTTP requests to coordination engine timeout
- Health endpoint returns 503 or connection refused
- Pods in CrashLoopBackOff or not ready

**Diagnosis**:

```bash
# Check pod status (Go-based coordination engine from external repo)
oc get pods -n self-healing-platform -l app.kubernetes.io/component=coordination-engine

# View logs
oc logs -n self-healing-platform -l app.kubernetes.io/component=coordination-engine --tail=100

# Test health endpoint
oc exec -n self-healing-platform deployment/self-healing-coordination-engine -- \
  curl -s http://localhost:8080/health

# Check service
oc get svc coordination-engine -n self-healing-platform
```

**Solution**:

```bash
# If pods are not running, check deployment
oc describe deployment coordination-engine -n self-healing-platform

# If missing RBAC, re-run prerequisites
make operator-deploy-prereqs

# If configuration is incorrect, check ConfigMap
oc get configmap coordination-engine-config -n self-healing-platform -o yaml

# Restart deployment
oc rollout restart deployment/coordination-engine -n self-healing-platform
```

**Related Documentation**:
- [ADR-038: Go Coordination Engine Migration](docs/adrs/038-go-coordination-engine-migration.md)
- External repo: https://github.com/KubeHeal/openshift-coordination-engine

### Issue 2: GPU Not Available in Notebooks

**Symptoms**:
- `nvidia-smi` command not found in notebook
- PyTorch/TensorFlow cannot detect GPU
- Notebook shows 0 GPUs available

**Diagnosis**:

```bash
# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Verify GPU operator
oc get csv -n openshift-operators | grep gpu-operator

# Check notebook GPU allocation
oc describe notebook self-healing-workbench -n self-healing-platform | grep -A 5 "nvidia.com/gpu"

# Check if GPU pods are running
oc get pods -n nvidia-gpu-operator
```

**Solution**:

```bash
# If no GPU nodes, label a node
oc label node <node-name> nvidia.com/gpu.present=true

# If GPU operator not installed, install it
# (Should be handled by platform deployment)
oc get subscription -n openshift-operators | grep gpu-operator

# If notebook doesn't request GPU, check values-hub.yaml
# Ensure notebook.resources includes nvidia.com/gpu: 1

# Restart notebook
oc delete notebook self-healing-workbench -n self-healing-platform
# ArgoCD will recreate it
```

**Related Documentation**:
- [ADR-006: NVIDIA GPU Operator for AI Workload Management](docs/adrs/006-nvidia-gpu-management.md)
- [ADR-057: Topology-Aware GPU Scheduling and Storage](docs/adrs/057-topology-aware-gpu-scheduling-and-storage.md)

### Issue 3: Operators Failing - TooManyOperatorGroups

**Symptoms**:
- Multiple operators failing in `openshift-operators` namespace
- Error message: `TooManyOperatorGroups: operatorgroup jupyter-validator-operatorgroup...`
- Operators stuck in "Failed" state
- CSV (ClusterServiceVersion) status shows conflict

**Diagnosis**:

```bash
# Check for multiple OperatorGroups
oc get operatorgroups -n openshift-operators

# Expected: Only "global-operators" should exist
# If you see "jupyter-validator-operatorgroup", that's the problem

# Check CSV status
oc get csv -n openshift-operators
```

**Solution**:

```bash
# Delete the conflicting OperatorGroup
oc delete operatorgroup jupyter-validator-operatorgroup -n openshift-operators

# Wait 30-60 seconds for operators to reconcile
oc get csv -n openshift-operators --watch

# Verify all CSVs are in "Succeeded" phase
oc get csv -n openshift-operators

# No pending InstallPlans
oc get installplans -n openshift-operators
```

**Related Documentation**:
- [docs/guides/TROUBLESHOOTING-GUIDE.md § Operator Failures](docs/guides/TROUBLESHOOTING-GUIDE.md#operator-failures)

### Issue 4: ArgoCD Application Not Syncing

**Symptoms**:
- Application shows `syncStatus: Unknown`
- Application health shows `healthStatus: Missing`
- Error: `Failed to load live state: Cluster level ClusterRoleBinding "..." can not be managed when in namespaced mode`
- No pods are created

**Diagnosis**:

```bash
# Check Pattern CR status
oc get pattern self-healing-platform -n openshift-operators -o yaml | grep -A 20 "status:"

# Check ArgoCD application details
oc describe application self-healing-platform -n self-healing-platform-hub

# Check if hub-gitops controller has cluster-admin permissions
oc get clusterrolebinding | grep hub-gitops-argocd-application-controller

# Check ArgoCD controller logs
oc logs -n self-healing-platform-hub deployment/hub-gitops-application-controller --tail=100
```

**Solution**:

```bash
# Re-run prerequisites (grants cluster-admin to ArgoCD controller)
make operator-deploy-prereqs

# Verify ClusterRoleBinding exists
oc get clusterrolebinding hub-gitops-argocd-application-controller-cluster-admin

# If missing, create manually:
oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: hub-gitops-argocd-application-controller-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: hub-gitops-argocd-application-controller
  namespace: self-healing-platform-hub
EOF

# Manually trigger ArgoCD sync
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite
```

**Related Documentation**:
- [ADR-030: Hybrid Management Model for Namespaced ArgoCD](docs/adrs/030-hybrid-management-model-namespaced-argocd.md)
- [ADR-042: ArgoCD Deployment Lessons Learned](docs/adrs/042-argocd-deployment-lessons-learned.md)

### Issue 5: Model Training Pipeline Fails

**Symptoms**:
- Tekton PipelineRun shows "Failed" status
- Notebook execution fails with errors
- Model artifacts not uploaded to S3
- InferenceService predictor pods fail with ModelMissingError

**Diagnosis**:

```bash
# Check PipelineRun status
tkn pipelinerun list -n self-healing-platform

# View logs
tkn pipelinerun logs <pipelinerun-name> -n self-healing-platform

# Check notebook validation job logs
oc logs -n self-healing-platform job/<notebook-job-name>

# Check S3 bucket for model artifacts
oc get objectbucketclaim -n self-healing-platform
oc describe objectbucketclaim model-storage -n self-healing-platform
```

**Solution**:

```bash
# If notebook execution fails, check notebook syntax
jupyter nbconvert --to notebook --execute \
  notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb

# If S3 upload fails, check ExternalSecret for bucket credentials
oc get externalsecret model-storage-secret -n self-healing-platform
oc describe externalsecret model-storage-secret -n self-healing-platform

# If credentials missing, re-run prerequisites
make operator-deploy-prereqs

# Manually restart training pipeline (see Section 3 Step 17)
tkn pipeline start model-training-pipeline \
  -p model-name=anomaly-detector \
  -p notebook-path=notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb \
  -p data-source=prometheus \
  -p training-hours=168 \
  -p inference-service-name=anomaly-detector \
  -p health-check-enabled=true \
  -p git-url=https://github.com/YOUR-USERNAME/openshift-aiops-platform.git \
  -p git-ref=main \
  -n self-healing-platform --showlog
```

**Related Documentation**:
- [ADR-029: Jupyter Notebook Validator Operator](docs/adrs/029-jupyter-notebook-validator-operator.md)
- [ADR-053: Tekton Pipelines for Model Training](docs/adrs/053-tekton-model-training-pipelines.md)
- [ADR-054: InferenceService Model Readiness Race Condition Fix](docs/adrs/054-inferenceservice-model-readiness-race-condition.md)

### Issue 6: Values Files Not Found

**Symptoms**:
- `make` commands fail with: `values-global.yaml: No such file or directory`
- Deployment fails before starting
- Error in Makefile parsing

**Diagnosis**:

```bash
# Check if values files exist
ls -l values-global.yaml values-hub.yaml

# Check for example files
ls -l values-global.yaml.example values-hub.yaml.example
```

**Solution**:

```bash
# Create values files from examples (Section 3 Step 5)
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml

# Update repoURL in both files (Section 3 Step 6)
vi values-global.yaml
# Change: repoURL: "https://github.com/KubeHeal/openshift-aiops-platform.git"
# To:     repoURL: "https://github.com/YOUR-USERNAME/openshift-aiops-platform.git"

vi values-hub.yaml
# Same repoURL change

# Verify files are correct
cat values-global.yaml | grep repoURL
cat values-hub.yaml | grep repoURL
```

**Related Documentation**:
- [README.md lines 134-148](README.md) - Values files configuration

---

## Section 6: Key Architecture Decisions

### Hybrid Self-Healing Approach (ADR-002)

**Decision**: Combine deterministic automation with AI-driven analysis

**Architecture**:
```
┌─────────────────────────────────────────────────────────────┐
│                 Self-Healing Platform                        │
├─────────────────────────────────────────────────────────────┤
│  Coordination Engine (Go-based)                             │
│  ├─ Conflict Resolution                                     │
│  ├─ Priority Management                                     │
│  └─ Action Orchestration                                    │
├─────────────────────────────────────────────────────────────┤
│  Deterministic Layer    │    AI-Driven Layer               │
│  ├─ Machine Config      │    ├─ Anomaly Detection          │
│  │  Operator            │    │  (Isolation Forest, LSTM)   │
│  ├─ Known Remediation   │    ├─ Root Cause Analysis        │
│  │  Procedures          │    ├─ Predictive Analytics       │
│  └─ Rule-Based Actions  │    └─ Adaptive Responses         │
├─────────────────────────────────────────────────────────────┤
│  Shared Observability Layer (Prometheus, AlertManager)     │
└─────────────────────────────────────────────────────────────┘
```

**Reference**: [ADR-002](docs/adrs/002-hybrid-self-healing-approach.md)

### Deployment Strategy (ADR-019, ADR-042, ADR-043)

**Decision**: Use Validated Patterns Framework with hybrid ArgoCD management

**Key Patterns**:
- **GitOps-driven**: All resources defined in Git, deployed via ArgoCD
- **Operator-based**: Validated Patterns Operator creates ArgoCD Application
- **Hybrid RBAC**: Namespaced ArgoCD with cluster-admin permissions
- **Health checks**: Init containers, startup probes, cross-namespace health checks
- **Sync waves**: Ordered deployment (operators → storage → notebooks → models)

**References**:
- [ADR-019: Validated Patterns Framework Adoption](docs/adrs/019-validated-patterns-framework-adoption.md)
- [ADR-042: ArgoCD Deployment Lessons Learned](docs/adrs/042-argocd-deployment-lessons-learned.md)
- [ADR-043: Deployment Stability and Health Checks](docs/adrs/043-deployment-stability-health-checks.md)

### Model Serving (ADR-004, ADR-039, ADR-040)

**Decision**: KServe for model serving infrastructure

**Architecture**:
- **KServe InferenceServices**: Deploy models as scalable HTTP/gRPC services
- **User-deployed models**: Platform users train and deploy their own ML models
- **Extensible registry**: Custom model registration via `values.yaml`
- **Platform-agnostic**: Works on vanilla Kubernetes and OpenShift

**References**:
- [ADR-004: KServe for Model Serving Infrastructure](docs/adrs/004-kserve-model-serving.md)
- [ADR-039: User-Deployed KServe Models](docs/adrs/039-user-deployed-kserve-models.md)
- [ADR-040: Extensible KServe Model Registry](docs/adrs/040-extensible-kserve-model-registry.md)

### Secrets Management (ADR-024, ADR-026)

**Decision**: External Secrets Operator for automated secrets management

**Approach**:
- **External Secrets Operator**: Syncs secrets from external sources (Vault, AWS Secrets Manager, Kubernetes)
- **ExternalSecret CRs**: Define secrets declaratively in Git
- **SecretStores**: Configure backends (Kubernetes backend for MVP)
- **Automation**: Secrets auto-sync on backend changes

**⚠️ MANDATORY**: ADR-026 is required for all deployments

**References**:
- [ADR-024: External Secrets for Model Storage](docs/adrs/024-external-secrets-model-storage.md)
- [ADR-026: Secrets Management Automation](docs/adrs/026-secrets-management-automation.md)

### Notebook Architecture (ADR-011, ADR-012, ADR-013)

**Decision**: Jupyter notebooks for end-to-end ML workflows

**Structure**:
- **Tier 1 notebooks**: Infrastructure validation (platform readiness)
- **Tier 2 notebooks**: Data collection and preprocessing
- **Tier 3 notebooks**: Model training and deployment
- **Validation operator**: Automated notebook execution and validation

**References**:
- [ADR-011: Self-Healing Workbench Base Image](docs/adrs/011-self-healing-workbench-base-image.md)
- [ADR-012: Notebook Architecture for End-to-End Workflows](docs/adrs/012-notebook-architecture-for-end-to-end-workflows.md)
- [ADR-013: Data Collection and Preprocessing Workflows](docs/adrs/013-data-collection-and-preprocessing-workflows.md)

### Storage Strategy (ADR-035, ADR-041, ADR-056)

**Decision**: ODF for object storage, CSI for block/file

**Storage Classes**:
- **HA clusters**: ODF (ocs-storagecluster-cephfs, ocs-storagecluster-ceph-rbd) + CSI (gp3-csi)
- **SNO clusters**: MCG-only ODF (NooBaa S3) + CSI only (gp3-csi)
- **Model artifacts**: NooBaa S3 (one directory per InferenceService)

**References**:
- [ADR-035: Storage Strategy](docs/adrs/035-storage-strategy.md)
- [ADR-041: Model Storage and Versioning Strategy](docs/adrs/041-model-storage-and-versioning-strategy.md)
- [ADR-056: Standalone MCG on SNO](docs/adrs/056-standalone-mcg-on-sno.md)

---

## Section 7: Quick Reference Commands

### Cluster Information

```bash
# Show cluster topology and version
make show-cluster-info

# Check cluster operators status
oc get clusteroperators

# List all namespaces
oc get namespaces

# Check node status
oc get nodes

# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true
```

### Deployment Status

```bash
# ArgoCD application health
make argo-healthcheck

# Check Pattern CR status
oc get pattern self-healing-platform -n openshift-operators -o yaml | grep -A 20 "status:"

# Check ArgoCD applications
oc get applications -n self-healing-platform-hub

# Check all pods in platform namespace
oc get pods -n self-healing-platform

# Check specific component
oc get pods -n self-healing-platform -l app.kubernetes.io/component=coordination-engine
```

### Model Serving

```bash
# List InferenceServices
oc get inferenceservices -n self-healing-platform

# Check InferenceService status
oc describe inferenceservice anomaly-detector -n self-healing-platform

# Check predictor pods
oc get pods -n self-healing-platform -l serving.kserve.io/inferenceservice=anomaly-detector

# Test model inference
INGRESS=$(oc get route anomaly-detector -n self-healing-platform -o jsonpath='{.spec.host}')
curl -X POST https://${INGRESS}/v1/models/anomaly-detector:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[1.0, 2.0, 3.0]]}'
```

### Tekton Pipelines

```bash
# List pipelines
tkn pipeline list -n self-healing-platform

# List pipeline runs
tkn pipelinerun list -n self-healing-platform

# View pipeline run logs
tkn pipelinerun logs <pipelinerun-name> -n self-healing-platform -f

# Start deployment validation pipeline
tkn pipeline start deployment-validation-pipeline --showlog

# Start model training pipeline (see Section 3 Step 17 for full command)
tkn pipeline start model-training-pipeline \
  -p model-name=anomaly-detector \
  -p notebook-path=notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb \
  -n self-healing-platform --showlog
```

### Logs and Debugging

```bash
# Coordination engine logs
oc logs -n self-healing-platform deployment/coordination-engine --tail=100 -f

# Workbench notebook logs
oc logs -n self-healing-platform self-healing-workbench-0 --tail=100 -f

# KServe predictor logs
oc logs -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=anomaly-detector \
  -c kserve-container --tail=100 -f

# ArgoCD controller logs
oc logs -n self-healing-platform-hub \
  deployment/hub-gitops-application-controller --tail=100 -f

# Check events
oc get events -n self-healing-platform --sort-by='.lastTimestamp' | tail -20
```

### Storage and PVCs

```bash
# List PVCs
oc get pvc -n self-healing-platform

# Check ODF status
oc get cephcluster -n openshift-storage
oc get storagecluster -n openshift-storage

# List storage classes
oc get storageclass

# Check ObjectBucketClaim for model storage
oc get objectbucketclaim -n self-healing-platform
oc describe objectbucketclaim model-storage -n self-healing-platform

# Get S3 bucket credentials
oc get secret model-storage -n self-healing-platform -o yaml
```

---

## Section 8: File Locations Reference

### Configuration Files

| File | Purpose |
|------|---------|
| `values-global.yaml` | Global pattern configuration (git repo, sync policy) |
| `values-hub.yaml` | Hub cluster configuration (storage, notebooks, operators) |
| `Makefile` | Main build/deploy/test targets |
| `.gitignore` | Git ignore patterns (includes my-pattern/, token, values files) |

### Key Scripts

| Script | Purpose |
|--------|---------|
| `scripts/install-prerequisites-rhel.sh` | RHEL 9/10 prerequisites installer |
| `scripts/configure-cluster-infrastructure.sh` | ODF deployment and MachineSet scaling |
| `scripts/post-deployment-validation.sh` | Post-deployment health checks |

### Documentation

| Document | Purpose |
|----------|---------|
| `README.md` | Quick start guide |
| `AGENTS.md` | Comprehensive AI agent development guide (1,800+ lines) |
| `CLAUDE.md` | AI agent quick reference (this file) |
| `DEPLOYMENT.md` | Step-by-step deployment guide |
| `docs/adrs/README.md` | ADR index (58+ ADRs) |
| `docs/guides/TROUBLESHOOTING-GUIDE.md` | Troubleshooting guide |
| `docs/guides/JUNIOR-DEVELOPER-DEPLOYMENT-GUIDE.md` | Junior developer guide |
| `docs/how-to/deploy-on-sno.md` | SNO deployment guide |

### Ansible

| Directory/File | Purpose |
|----------------|---------|
| `ansible/roles/` | 8 production-ready reusable roles |
| `ansible/playbooks/prerequisites.yml` | Creates namespaces, RBAC, secrets |
| `ansible/playbooks/validated_patterns_operator_deploy.yml` | Deploys Validated Patterns Operator |
| `ansible/playbooks/cleanup.yml` | Cleanup playbook |

### Helm Charts

| Directory/File | Purpose |
|----------------|---------|
| `charts/hub/` | Main pattern chart |
| `charts/hub/Chart.yaml` | Chart metadata |
| `charts/hub/values.yaml` | Default values |
| `charts/hub/templates/` | Kubernetes resource templates |

### Kubernetes Manifests

| Directory/File | Purpose |
|----------------|---------|
| `k8s/operators/` | Operator deployments (GPU, Pipelines, GitOps, etc.) |
| `k8s/mcp-server/` | MCP server manifests (deprecated, now standalone) |

### Notebooks

| Directory | Purpose |
|-----------|---------|
| `notebooks/00-setup/` | Platform validation (00-platform-readiness-validation.ipynb) |
| `notebooks/01-data-collection/` | Metrics, logs, events collection |
| `notebooks/02-anomaly-detection/` | ML models (Isolation Forest, LSTM, predictive analytics) |
| `notebooks/03-self-healing-logic/` | Integration notebooks |
| `notebooks/04-model-serving/` | KServe deployment notebooks |
| `notebooks/05-end-to-end-scenarios/` | Complete use cases |
| `notebooks/06-mcp-integration/` | MCP integration notebooks |
| `notebooks/07-advanced-topics/` | Advanced ML topics |

### Tekton Pipelines

| Directory/File | Purpose |
|----------------|---------|
| `tekton/pipelines/` | Pipeline definitions |
| `tekton/tasks/` | Reusable tasks |
| `tekton/triggers/` | Event-driven triggers |

---

## Section 9: Agent Response Patterns

### Pattern 1: User Says "Deploy the platform"

**Agent Response Template**:

```
I'll help you deploy the OpenShift AI Ops Self-Healing Platform. Let me first check
if you've completed the prerequisites.

**Before we begin**:

1. Have you forked the repository to YOUR GitHub account?
   - If NO: Go to https://github.com/KubeHeal/openshift-aiops-platform and click "Fork"

2. Are you running RHEL 9 or RHEL 10?
   - If YES: Run `./scripts/install-prerequisites-rhel.sh` first
   - If NO: Manually install oc, kubectl, helm, yq, ansible-navigator, podman

3. Are you logged into your OpenShift cluster?
   - If NO: Run `oc login <cluster-url>`

4. Have you created values files?
   - If NO: Run `cp values-global.yaml.example values-global.yaml` and
            `cp values-hub.yaml.example values-hub.yaml`

5. Have you updated repoURL in both values files to YOUR fork?
   - If NO: Edit both files and change the repoURL

**If all prerequisites are met**, here's the deployment workflow:

[Provide Section 3: Complete Deployment Workflow - 17 steps]

Let me know which step you're on, and I'll guide you through it!
```

### Pattern 2: User Says "Something isn't working"

**Agent Response Template**:

```
I'll help you troubleshoot. Let me gather some diagnostic information first.

**Please run these commands and share the output**:

1. Check cluster topology:
   ```bash
   make show-cluster-info
   ```

2. Check ArgoCD application status:
   ```bash
   oc get applications -n self-healing-platform-hub
   ```

3. Check pod status:
   ```bash
   oc get pods -n self-healing-platform
   ```

4. Check recent events:
   ```bash
   oc get events -n self-healing-platform --sort-by='.lastTimestamp' | tail -20
   ```

**Common issues and quick fixes**:

- **ArgoCD not syncing**: See [Section 5 Issue 4](#issue-4-argocd-application-not-syncing)
- **Operators failing**: See [Section 5 Issue 3](#issue-3-operators-failing---toomanyoperatorgroups)
- **Coordination engine not responding**: See [Section 5 Issue 1](#issue-1-coordination-engine-not-responding)
- **Values files not found**: See [Section 5 Issue 6](#issue-6-values-files-not-found)

Please share the output, and I'll help identify the specific issue.
```

### Pattern 3: User Asks "What's different for SNO?"

**Agent Response Template**:

```
Great question! Single Node OpenShift (SNO) deployments have some key differences:

**Detection**:
Run `make show-cluster-info`. If it shows `Topology: sno`, you have an SNO cluster.

**Key Differences** (see [Section 4](#section-4-sno-vs-ha-differences) for full table):

1. **Storage**: SNO uses MCG-only ODF (NooBaa S3 without Ceph)
   - Must use CSI storage classes (gp3-csi) instead of ODF storage classes
   - No CephFS or RBD available

2. **Resources**: All workloads compete for single node's resources
   - Reduced resource limits configured in values-hub.yaml

3. **No HA**: Single point of failure, no horizontal scaling

**Required Configuration Changes**:

Before deploying (Step 12 in Section 3), edit `values-hub.yaml`:

```yaml
cluster:
  topology: "sno"

storage:
  modelStorage:
    storageClass: "gp3-csi"  # Changed from ocs-storagecluster-cephfs

objectStore:
  enabled: true  # MCG-only ODF provides NooBaa S3
```

**Reference**: [docs/how-to/deploy-on-sno.md](docs/how-to/deploy-on-sno.md) for complete SNO guide.

Need help with SNO deployment? Let me know!
```

### Pattern 4: User Asks "How do I set up my workstation?"

**Agent Response Template**:

```
I'll help you set up your workstation for deploying the platform.

**Are you using RHEL 9 or RHEL 10?**

**If YES (RHEL 9/10)** - Use the automated installer:

1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
   cd openshift-aiops-platform
   ```

2. Run the prerequisites installer:
   ```bash
   ./scripts/install-prerequisites-rhel.sh
   source ~/.bashrc
   ```

3. Verify installation:
   ```bash
   oc version
   helm version
   ansible-navigator --version
   ```

See [Section 2](#section-2-rhel-910-workstation-setup) for detailed information.

**If NO (Other Linux, macOS)** - Manual installation:

Install these tools manually:
- podman (container runtime)
- oc and kubectl (OpenShift/Kubernetes CLI)
- helm 3.12+ (Kubernetes package manager)
- ansible-navigator (Ansible execution environment runner)
- ansible-builder (Build custom Ansible EEs)
- yq (YAML processor)
- tkn (Tekton CLI, optional)
- git, make, jq (standard development tools)

See [README.md lines 79-87](README.md) for the prerequisites list.

**Next Steps After Setup**:

1. Log into your OpenShift cluster: `oc login <cluster-url>`
2. Get your Ansible Hub token: https://console.redhat.com/ansible/automation-hub/token
3. Continue with deployment (Section 3)

Need help with a specific step? Let me know!
```

### Pattern 5: User Asks "Where can I find more details?"

**Agent Response Template**:

```
Great question! The platform has extensive documentation depending on what you need:

**For Deployment**:
- [CLAUDE.md](CLAUDE.md) (this file) - AI agent quick reference
- [README.md](README.md) - Quick start guide (lines 115-227: 17-step workflow)
- [DEPLOYMENT.md](DEPLOYMENT.md) - Step-by-step deployment guide
- [docs/how-to/deploy-on-sno.md](docs/how-to/deploy-on-sno.md) - SNO deployment guide

**For Development**:
- [AGENTS.md](AGENTS.md) - Comprehensive AI agent development guide (1,800+ lines)
- [docs/guides/JUNIOR-DEVELOPER-DEPLOYMENT-GUIDE.md](docs/guides/JUNIOR-DEVELOPER-DEPLOYMENT-GUIDE.md) - Junior developer guide

**For Troubleshooting**:
- [Section 5](#section-5-common-troubleshooting) in this file - Common issues
- [docs/guides/TROUBLESHOOTING-GUIDE.md](docs/guides/TROUBLESHOOTING-GUIDE.md) - Complete troubleshooting guide

**For Architecture**:
- [docs/adrs/README.md](docs/adrs/README.md) - ADR index (58+ ADRs)
- [Section 6](#section-6-key-architecture-decisions) in this file - Key decisions
- [ADR-002](docs/adrs/002-hybrid-self-healing-approach.md) - Core architecture

**For Specific Components**:
- **Coordination Engine**: [ADR-038](docs/adrs/038-go-coordination-engine-migration.md)
- **Model Serving**: [ADR-004](docs/adrs/004-kserve-model-serving.md), [ADR-039](docs/adrs/039-user-deployed-kserve-models.md)
- **Secrets Management**: [ADR-026](docs/adrs/026-secrets-management-automation.md) (**MANDATORY**)
- **Notebooks**: [ADR-012](docs/adrs/012-notebook-architecture-for-end-to-end-workflows.md)
- **Storage**: [ADR-035](docs/adrs/035-storage-strategy.md), [ADR-056](docs/adrs/056-standalone-mcg-on-sno.md)

What specific aspect are you interested in? I can point you to the right documentation.
```

---

## Section 10: Important Reminders + Glossary

### Critical Steps Users Often Miss

#### 1. Forking the Repository

**❌ Wrong**: Clone the upstream repository directly
```bash
git clone https://github.com/KubeHeal/openshift-aiops-platform.git
```

**✅ Correct**: Fork first, then clone YOUR fork
```bash
# 1. Click "Fork" at https://github.com/KubeHeal/openshift-aiops-platform
# 2. Clone YOUR fork
git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
```

**Why**: ArgoCD needs to read from YOUR repository to deploy customized values files.

#### 2. Creating Values Files

**❌ Wrong**: Run `make` commands without creating values files

**✅ Correct**: Create values files BEFORE any `make` target
```bash
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml
```

**Why**: Makefile reads `values-global.yaml` on startup and will fail if missing.

#### 3. Updating repoURL

**❌ Wrong**: Leave default repoURL pointing to upstream repository

**✅ Correct**: Update repoURL in BOTH files to YOUR fork
```bash
vi values-global.yaml
# Change: repoURL: "https://github.com/KubeHeal/openshift-aiops-platform.git"
# To:     repoURL: "https://github.com/YOUR-USERNAME/openshift-aiops-platform.git"

vi values-hub.yaml
# Same repoURL change
```

**Why**: ArgoCD syncs from the repository specified in repoURL.

#### 4. SNO Configuration

**❌ Wrong**: Deploy on SNO without updating `values-hub.yaml`

**✅ Correct**: Check topology and update values for SNO
```bash
# 1. Check topology
make show-cluster-info

# 2. If topology shows "sno", edit values-hub.yaml:
vi values-hub.yaml
# Set:
#   cluster.topology: "sno"
#   storage.modelStorage.storageClass: "gp3-csi"
```

**Why**: SNO requires different storage classes and resource configurations.

#### 5. ODF Installation Time

**⏱️ Reminder**: `make configure-cluster` takes 10-15 minutes on HA clusters

**What's happening**:
- Installing ODF operator
- Creating StorageCluster
- Waiting for Ceph daemons (OSD, MON, MGR) to become Ready
- Scaling MachineSets (if needed)

**Don't panic** if it seems slow - this is expected behavior.

#### 6. Execution Environment

**❌ Wrong**: Skip execution environment setup

**✅ Correct**: Pull or build execution environment before deployment
```bash
# Option A: Pull pre-built image (Recommended)
podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest openshift-aiops-platform-ee:latest

# Option B: Build locally (requires ANSIBLE_HUB_TOKEN)
export ANSIBLE_HUB_TOKEN='your-token-here'
make build-ee
```

**Why**: Ansible playbooks run inside the execution environment container.

### Version Compatibility

| Component | Supported Versions | Notes |
|-----------|-------------------|-------|
| **OpenShift** | 4.18, 4.19, 4.20 | Auto-detected during deployment |
| **Red Hat OpenShift AI** | 2.22.2 | Deployed by platform |
| **KServe** | 1.36.1 | Part of OpenShift AI |
| **GPU Operator** | 24.9.2 | For GPU workloads |
| **GitOps** | 1.15.4 | ArgoCD-based GitOps |
| **Pipelines** | 1.17.2 | Tekton CI/CD |
| **helm** | v3.16.4 | Kubernetes package manager |
| **yq** | v4.44.6 | YAML processor |
| **tkn** | 0.38.1 | Tekton CLI |

### External Dependencies

#### Coordination Engine

- **Repository**: https://github.com/KubeHeal/openshift-coordination-engine
- **Language**: Go 1.21+
- **Architecture**: Standalone (not embedded in this repository)
- **Integration**: Deployed via Kubernetes manifests in this repo

#### Pre-Built Execution Environment

- **Registry**: quay.io/takinosh/openshift-aiops-platform-ee:latest
- **Alternative**: Build locally with `make build-ee` (requires ANSIBLE_HUB_TOKEN)

#### Ansible Hub

- **Purpose**: Download Ansible collections and content
- **Token**: Required for building execution environment locally
- **Get Token**: https://console.redhat.com/ansible/automation-hub/token

### Glossary

| Term | Definition |
|------|------------|
| **ADR** | Architectural Decision Record - Documents key architectural decisions |
| **AIOps** | Artificial Intelligence for IT Operations |
| **EE** | Execution Environment - Container image with Ansible and dependencies |
| **HA** | HighlyAvailable - Cluster topology with 3+ nodes, separate control-plane/worker roles |
| **InferenceService** | KServe custom resource for deploying ML models |
| **MCG** | Multi-Cloud Gateway - NooBaa S3-compatible object storage |
| **MCP** | Model Context Protocol - Integration protocol for OpenShift Lightspeed |
| **ODF** | OpenShift Data Foundation - Storage solution (Ceph + NooBaa) |
| **SNO** | Single Node OpenShift - Cluster topology with 1 node, all roles on single node |
| **VP** | Validated Patterns - Red Hat framework for GitOps-based deployments |

### Changelog

| Date | Change | Author |
|------|--------|--------|
| 2026-03-06 | Initial creation of CLAUDE.md | AI Agent |
| | Added 10 sections: Overview, RHEL setup, deployment, SNO, troubleshooting, architecture, commands, files, patterns, reminders | |
| | Content based on README.md, AGENTS.md, ADRs, and troubleshooting guides | |

---

**Last Updated**: 2026-03-06
**Maintained By**: Architecture Team
**Review Frequency**: Monthly or when major platform changes occur

**Questions or Issues?**
- GitHub Issues: https://github.com/KubeHeal/openshift-aiops-platform/issues
- Documentation: [AGENTS.md](AGENTS.md), [docs/adrs/](docs/adrs/)
