# Fresh Cluster Deployment Guide

**Last Updated**: 2026-05-18

This guide walks you through deploying the OpenShift AIOps Self-Healing Platform on a fresh OpenShift cluster, consolidating best practices from DEPLOYMENT.md, DEPLOYMENT-QUICKSTART.md, and deploy-on-sno.md.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Topology Detection](#topology-detection)
3. [Fork and Clone Repository](#fork-and-clone-repository)
4. [Values Files Configuration](#values-files-configuration)
5. [Infrastructure Setup](#infrastructure-setup)
6. [Platform Deployment](#platform-deployment)
7. [Validation](#validation)
8. [Post-Deployment](#post-deployment)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

| Tool | Minimum Version | Purpose | Installation |
|------|-----------------|---------|--------------|
| **oc** | 4.18+ | OpenShift CLI | `./scripts/install-prerequisites-rhel.sh` (RHEL 9/10) |
| **kubectl** | 1.31+ | Kubernetes CLI | Installed with oc |
| **helm** | 3.16.4+ | Kubernetes package manager | Auto-installed by script |
| **yq** | 4.44.6+ | YAML processor | Auto-installed by script |
| **ansible-navigator** | 24.11.0+ | Ansible execution | Auto-installed by script |
| **podman** | 4.9.4+ | Container runtime | Auto-installed by script |
| **git** | 2.40+ | Version control | `dnf install git` |
| **make** | 4.3+ | Build automation | `dnf install make` |

### RHEL 9/10 One-Command Setup

```bash
# Run from the cloned repository
./scripts/install-prerequisites-rhel.sh
source ~/.bashrc
```

### Required Access

- ✅ **OpenShift cluster access** with cluster-admin permissions
- ✅ **GitHub account** to fork the repository
- ✅ **Ansible Hub token** (for building execution environment locally)
  - Get token: https://console.redhat.com/ansible/automation-hub/token
  - Only needed if building EE locally (can skip if using pre-built image)

---

## Topology Detection

**Critical First Step**: Detect your cluster topology to configure correctly for SNO or HA.

```bash
# Login to your cluster
oc login <cluster-api-url>

# Detect topology
make show-cluster-info
```

**Expected Output**:

```
Cluster Information:
  Topology: sno        # or "ha"
  OpenShift Version: 4.20
  Platform: AWS
  ODF Channel: stable-4.20

Cluster Topology Information:
  Type: SNO (Single Node OpenShift)  # or "HA (HighlyAvailable)"
  Control Plane: SingleReplica       # or "HighlyAvailable"
  Infrastructure: SingleReplica      # or "HighlyAvailable"
  Platform: AWS
```

**⚠️ IMPORTANT**: Note the topology - you'll configure values files differently for SNO vs. HA.

---

## Fork and Clone Repository

### Step 1: Fork on GitHub

**❌ DO NOT clone the upstream repository directly**

1. Go to https://github.com/KubeHeal/openshift-aiops-platform
2. Click **Fork** in the top-right corner
3. Create fork under YOUR account/organization

### Step 2: Clone YOUR Fork

```bash
git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
cd openshift-aiops-platform
```

**Why fork?** ArgoCD needs to read from YOUR repository to deploy your customized values files.

---

## Values Files Configuration

### Step 1: Create Values Files

```bash
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml
```

**⚠️ CRITICAL**: These files are **required before any `make` target**. The Makefile reads `values-global.yaml` on startup.

### Step 2: Update repoURL (REQUIRED)

Edit **BOTH** files and change the repoURL to YOUR fork:

**File**: `values-global.yaml`

```yaml
# BEFORE:
repoURL: "https://github.com/KubeHeal/openshift-aiops-platform.git"

# AFTER:
repoURL: "https://github.com/YOUR-USERNAME/openshift-aiops-platform.git"
```

**File**: `values-hub.yaml`

```yaml
# BEFORE:
      repoURL: https://github.com/KubeHeal/openshift-aiops-platform.git

# AFTER:
      repoURL: https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
```

### Step 3: Topology-Specific Configuration

#### If Topology is `sno`:

Edit `values-hub.yaml`:

```yaml
cluster:
  topology: "sno"

storage:
  modelStorage:
    storageClass: "gp3-csi"  # Changed from ocs-storagecluster-cephfs

workbench:
  enabled: true
  gpu:
    enabled: false  # GPU disabled per ADR-057 for SNO
```

#### If Topology is `ha`:

Default values are correct for HA. Optionally enable GPU:

```yaml
cluster:
  topology: "ha"

storage:
  modelStorage:
    storageClass: "ocs-storagecluster-cephfs"  # ODF storage

workbench:
  enabled: true
  gpu:
    enabled: true  # GPU enabled for HA (if GPU nodes available)
```

---

## Infrastructure Setup

### Step 1: Get Execution Environment

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

### Step 2: Configure Cluster Infrastructure (ODF)

```bash
make configure-cluster
```

**What this does**:

**On HA clusters**:
- Installs ODF operator
- Creates full ODF StorageCluster (Ceph + NooBaa)
- Scales MachineSets (if needed)
- **Duration**: 10-15 minutes

**On SNO clusters**:
- Installs ODF operator
- Creates MCG-only StorageCluster (NooBaa S3 without Ceph)
- Skips MachineSet scaling
- **Duration**: 5-7 minutes

**Skip ODF** (if you already have storage):

```bash
./scripts/configure-cluster-infrastructure.sh --skip-odf
```

---

## Platform Deployment

### Step 1: Validate Prerequisites

```bash
make check-prerequisites
```

Verifies:
- ✅ Cluster access
- ✅ Required operators available
- ✅ Storage classes exist
- ✅ Execution environment ready

### Step 2: Run Ansible Prerequisites

```bash
make operator-deploy-prereqs
```

**What this creates**:
- Namespaces: `self-healing-platform`, `self-healing-platform-hub`
- RBAC: ServiceAccounts, Roles, ClusterRoles, RoleBindings
- Secrets: External Secrets Operator configuration
- ArgoCD permissions: cluster-admin for hub-gitops

**Duration**: 2-3 minutes

### Step 3: Deploy Platform via Validated Patterns Operator

```bash
make operator-deploy
```

**What this does**:
1. Deploys Validated Patterns Operator
2. Creates Pattern CR pointing to YOUR fork
3. Operator creates ArgoCD application
4. ArgoCD deploys all platform components:
   - Red Hat OpenShift AI
   - OpenShift Pipelines
   - External Secrets Operator
   - Jupyter Notebook Validator Operator
   - Workbench notebooks
   - Model training pipelines
   - InferenceServices (KServe)

**Duration**: 5-10 minutes for initial sync

### Step 4: Wait for ArgoCD Application

```bash
oc wait --for=jsonpath='{.kind}'=Application \
  application/self-healing-platform -n self-healing-platform-hub --timeout=120s
```

### Step 5: Monitor ArgoCD Sync

```bash
watch -n 5 'oc get application.argoproj.io self-healing-platform \
  -n self-healing-platform-hub \
  -o jsonpath="{.status.sync.status} - {.status.health.status}"'
```

**Expected progression**:
1. `Unknown - Unknown`
2. `OutOfSync - Missing`
3. `Synced - Progressing`
4. `Synced - Healthy`

Press `Ctrl+C` when you see `Synced - Healthy`.

**If stuck in OutOfSync**, manually trigger sync:

```bash
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite
```

---

## Validation

### Step 1: ArgoCD Health Check

```bash
make argo-healthcheck
```

**Expected Output**:

```
✅ ArgoCD Application Health Check
Application: self-healing-platform
Status: Healthy
Sync: Synced
```

### Step 2: Verify Components

```bash
# Check all pods
oc get pods -n self-healing-platform

# Check operators
oc get csv -A | grep -E "jupyter|rhods|pipelines|external-secrets"

# Check InferenceServices
oc get inferenceservice -n self-healing-platform
```

**Expected**:
- ✅ All pods Running or Completed
- ✅ All CSVs in Succeeded phase
- ✅ InferenceServices Ready (may take 5-10 min)

### Step 3: Run Tekton Validation Pipeline

```bash
# Check if tkn is installed
which tkn || echo "tkn not found - validation optional"

# If tkn installed, run validation
tkn pipeline start deployment-validation-pipeline --showlog
```

Validates 26 checks including:
- Coordination engine connectivity
- Model serving endpoints
- Prometheus integration
- Storage configuration

---

## Post-Deployment

### Access Jupyter Workbench

```bash
# Port-forward to workbench
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform

# Open browser to http://localhost:8888
```

### Check Model Training Pipelines

```bash
# List pipeline runs
oc get pipelinerun -n self-healing-platform

# Expected: Two pipelines auto-started
# - train-anomaly-detector-XXXXX (CPU-based)
# - train-predictive-analytics-XXXXX (GPU-based, if GPU enabled)
```

**If pipelines not started**, manually trigger:

```bash
# Anomaly Detector (CPU)
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

### Cleanup Extra Namespaces (Optional)

```bash
# Remove upstream pattern examples
oc delete namespace self-healing-platform-example imperative --ignore-not-found=true
```

---

## Troubleshooting

### Issue 1: Operators Failing - TooManyOperatorGroups

**Symptoms**: CSV status shows `TooManyOperatorGroups` error

**Solution**:

```bash
# Check for multiple OperatorGroups
oc get operatorgroups -n <namespace>

# Delete extras (keep only one)
oc delete operatorgroup <extra-group> -n <namespace>
```

### Issue 2: ArgoCD Application Not Syncing

**Symptoms**: Application shows `syncStatus: Unknown`, error about ClusterRoleBinding in namespaced mode

**Solution**:

```bash
# Re-run prerequisites (grants cluster-admin to ArgoCD)
make operator-deploy-prereqs

# Verify ClusterRoleBinding exists
oc get clusterrolebinding hub-gitops-argocd-application-controller-cluster-admin

# Manually trigger sync
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite
```

### Issue 3: Workbench Pod Pending (GPU Conflict)

**Symptoms**: `self-healing-workbench-0` stuck in Pending state with "Insufficient nvidia.com/gpu" error

**Solution** (SNO only):

1. Verify topology:
   ```bash
   make show-cluster-info
   # Should show: Topology: sno
   ```

2. Check values-hub.yaml:
   ```bash
   grep -A 2 "workbench:" values-hub.yaml
   # Should show: gpu.enabled: false
   ```

3. If GPU enabled on SNO, fix it:
   ```bash
   # Edit values-hub.yaml
   vi values-hub.yaml
   # Set: workbench.gpu.enabled: false
   
   # Commit and push
   git add values-hub.yaml
   git commit -s -m "fix: Disable workbench GPU on SNO per ADR-057"
   git push origin main
   
   # Trigger ArgoCD sync
   oc annotate application self-healing-platform -n self-healing-platform-hub \
     argocd.argoproj.io/refresh=hard --overwrite
   ```

### Issue 4: Model Training Fails - S3 DNS Resolution Error

**Symptoms**: Notebook validation jobs fail with "Failed to resolve 's3.openshift-storage.svc'"

**Solution**: This is expected when `objectStore: false`. The platform uses PVCs for model storage instead. Validation jobs should show WARNING, not FAILED.

If jobs still fail, check:

```bash
# Verify S3 validation logic fix (should be in place)
grep -A 5 "EndpointConnectionError" notebooks/utils/validation_helpers.py

# Check ObjectStore configuration
grep "objectStore:" values-hub.yaml
```

### Issue 5: Values Files Not Found

**Symptoms**: `make` commands fail with `values-global.yaml: No such file or directory`

**Solution**:

```bash
# Create values files from examples
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml

# Update repoURL in both files (see Step 2 under Values Files Configuration)
```

---

## Quick Reference

### Essential Commands

```bash
# Show cluster info
make show-cluster-info

# Configure cluster (ODF)
make configure-cluster

# Deploy platform
make operator-deploy-prereqs
make operator-deploy

# Validate deployment
make argo-healthcheck

# Access workbench
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform

# Check logs
oc logs -n self-healing-platform deployment/coordination-engine --tail=100 -f

# Check events
oc get events -n self-healing-platform --sort-by='.lastTimestamp' | tail -20
```

### Topology-Specific Configurations

| Setting | SNO | HA |
|---------|-----|-----|
| `cluster.topology` | `"sno"` | `"ha"` |
| `storage.modelStorage.storageClass` | `"gp3-csi"` | `"ocs-storagecluster-cephfs"` |
| `workbench.gpu.enabled` | `false` | `true` (if GPU nodes available) |
| ODF Mode | MCG-only (NooBaa S3) | Full ODF (Ceph + NooBaa) |

---

## Related Documentation

- **[CLAUDE.md](../../CLAUDE.md)**: AI agent quick reference
- **[AGENTS.md](../../AGENTS.md)**: Comprehensive AI agent development guide
- **[TROUBLESHOOTING-GUIDE.md](TROUBLESHOOTING-GUIDE.md)**: Complete troubleshooting guide
- **[ADR-055](../adrs/055-openshift-420-multi-cluster-topology-support.md)**: Multi-cluster topology support
- **[ADR-056](../adrs/056-standalone-mcg-on-sno.md)**: Standalone MCG on SNO
- **[ADR-057](../adrs/057-topology-aware-gpu-scheduling-and-storage.md)**: Topology-aware GPU scheduling

---

**Deployment Timeline**:
- Prerequisites: 5-10 min (one-time setup)
- Infrastructure (ODF): 10-15 min (HA), 5-7 min (SNO)
- Platform Deployment: 5-10 min
- Validation: 2-3 min
- **Total**: ~25-40 minutes for complete deployment

**Next Steps After Successful Deployment**:
1. Access workbench and run sample notebooks
2. Monitor model training pipelines
3. Test InferenceService endpoints
4. Explore coordination engine functionality
5. Review ADRs to understand architectural decisions
