# Deploying Self-Healing Platform to a New OpenShift Cluster

## Overview

This guide provides step-by-step instructions for deploying the OpenShift AI Ops Self-Healing Platform to a fresh OpenShift 4.19+ cluster using the Validated Patterns framework.

**Target Audience**: Advanced SREs and Platform Engineers with OpenShift experience

**Estimated Time**: 30-45 minutes

**Prerequisites**: OpenShift 4.19+ cluster (4.21 recommended; 4.18 maintenance-only) with required operators installed

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Configuration Steps](#configuration-steps)
4. [Deployment Process](#deployment-process)
5. [Validation](#validation)
6. [Troubleshooting](#troubleshooting)
7. [Next Steps](#next-steps)

---

## Prerequisites

### Cluster Requirements

**Minimum Configuration**:
- ✅ OpenShift Container Platform **4.19+** (4.21 recommended; 4.18 maintenance-only)
- ✅ **6+ nodes**: 3 control-plane, 3+ workers
- ✅ **1+ GPU node**: NVIDIA GPU for AI/ML workloads
- ✅ **24+ CPU cores** across cluster
- ✅ **96+ GB RAM** across cluster
- ✅ **500+ GB storage** with dynamic provisioning

**Verify Cluster Version**:
```bash
oc version
# openshiftVersion: 4.19+ (4.21 recommended)
```

### Required Operators

The following operators **must be pre-installed**:

| Operator | Version | Purpose |
|----------|---------|---------|
| **Red Hat OpenShift AI** | 2.22.2+ | ML platform |
| **NVIDIA GPU Operator** | 24.9.2+ | GPU management |
| **OpenShift GitOps** | 1.20.3+ | ArgoCD/GitOps |
| **OpenShift Pipelines** | 1.22.0+ | Tekton CI/CD |
| **OpenShift Serverless** | Latest | Knative/Istio |
| **OpenShift Data Foundation** | 4.20+ (matches cluster version) | Storage (ODF) |
| **External Secrets Operator** | 1.1.0+ | Secrets management |

> **📖 Reference**: See [OPERATOR_VERSIONS.md](../../OPERATOR_VERSIONS.md) for complete version compatibility matrix

**Verify Operators**:
```bash
oc get csv -n openshift-operators | grep -E 'rhods|gpu|gitops|pipelines|serverless|odf|external-secrets'
```

Expected output (versions may be newer):
```
rhods-operator.2.22.2
gpu-operator-certified.v24.9.2
openshift-gitops-operator.v1.20.3
openshift-pipelines-operator-rh.v1.22.0
serverless-operator.v1.36.1
odf-operator.v4.20.0
external-secrets-operator.v1.1.0
```

> **Note**: Versions shown are minimum requirements. Newer versions are generally compatible. Check [OPERATOR_VERSIONS.md](../../OPERATOR_VERSIONS.md) for latest tested versions.

### Storage Classes

**Required storage classes**:
- `gp3-csi` (AWS EBS) - RWO volumes
- `ocs-storagecluster-cephfs` (ODF CephFS) - RWX volumes

**Verify Storage**:
```bash
oc get storageclass | grep -E 'gp3-csi|ocs-storagecluster-cephfs'
```

### GPU Availability

**Verify GPU Nodes**:
```bash
oc get nodes -l nvidia.com/gpu.present=true
```

Expected: At least 1 node with GPU

### Local Tools

Install these tools on your workstation:

- ✅ `oc` CLI (OpenShift client)
- ✅ `kubectl` CLI (Kubernetes client)
- ✅ `helm` 3.12+ (Helm package manager)
- ✅ `yq` (YAML processor)
- ✅ `git` (Version control)
- ✅ `python-kubernetes` (Python Kubernetes client)
- ✅ `kubernetes.core` (Ansible collection)

**Install Tools** (if missing):
```bash
# Install yq
curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /tmp/yq
chmod +x /tmp/yq
sudo mv /tmp/yq /usr/local/bin/yq

# Install Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Python Kubernetes client
pip3 install --user --upgrade oauthlib kubernetes

# Install Ansible kubernetes.core collection
ansible-galaxy collection install kubernetes.core
```

**Verify Tools**:
```bash
oc version --client
kubectl version --client
helm version --short
yq --version
git --version
python3 -c "import kubernetes; print('kubernetes: OK')"
ansible-galaxy collection list | grep kubernetes.core
```

---

## Pre-Deployment Checklist

### 1. Clone Repository

```bash
git clone https://github.com/openshift-aiops/openshift-aiops-platform.git
cd openshift-aiops-platform
```

### 2. Authenticate to OpenShift

```bash
# Login as cluster-admin
oc login --server=https://api.cluster-abc123.example.com:6443 --username=admin

# Verify permissions
oc auth can-i create namespace
# yes
```

### 3. Verify Cluster Readiness

Run automated validation:
```bash
ansible-playbook ansible/playbooks/validate_new_cluster.yml
```

This checks:
- OpenShift version
- Required operators
- GPU nodes
- Storage classes
- Cluster resources
- Network connectivity

**Expected Output**:
```
TASK [Display validation summary]
============================================================
Validation Summary
============================================================
Checks Passed:   8
Checks Failed:   0
Checks Warnings: 1

✅ Cluster validation PASSED
Ready to deploy Self-Healing Platform
```

**If validation fails**: Review errors and fix issues before proceeding.

---

## Configuration Steps

### Step 1: Configure Git Repository

**Choose Your Git Backend**:

**Option A: Gitea (Development/Air-gapped)**
- Local git server on cluster
- Fast iteration
- No internet dependency
- Install Gitea:
  ```bash
  ansible-playbook ansible/playbooks/deploy_gitea.yml
  ```

**Option B: GitHub (Production)**
- Public/private repositories
- CI/CD integration
- Team collaboration
- Fork repository: https://github.com/openshift-aiops/openshift-aiops-platform

### Step 2: Install Local Prerequisites

**⚠️ CRITICAL**: Install all required tools BEFORE attempting deployment.

```bash
# Check if tools are installed
./scripts/check-local-prerequisites.sh

# Or manually verify each tool
yq --version || echo "❌ yq not found"
helm version || echo "❌ helm not found"
python3 -c "import kubernetes" || echo "❌ python-kubernetes not found"
ansible-galaxy collection list | grep kubernetes.core || echo "❌ kubernetes.core not found"
```

**If any tools are missing**, install them using the commands in the [Local Tools](#local-tools) section above.

### Step 3: Generate Customized Values Files

Run the interactive configuration helper:

```bash
./scripts/configure-cluster-values.sh
```

**Interactive Prompts**:
```
Enter cluster domain [apps.cluster-abc123.example.com]: <press Enter to accept>
Enter git type (gitea/github) [gitea]: gitea
Enter Git organization/username [my-org]: openshift-aiops
Enter Git repository name [openshift-aiops-platform]: openshift-aiops-platform
Enter Git branch [main]: main
Enter Git username [admin]: admin
```

**What This Does**:
- ✅ Auto-detects cluster domain from OpenShift API
- ✅ Generates `values-global.yaml` from template
- ✅ Generates `values-hub.yaml` from template
- ✅ Creates `values-secret.yaml` for credentials

**Output Files**:
```
✅ Created values-global.yaml
✅ Created values-hub.yaml
✅ Created values-secret.yaml - EDIT IT WITH YOUR ACTUAL SECRETS
```

### Step 4: Configure Secrets

Edit `values-secret.yaml` with actual credentials:

```bash
vi values-secret.yaml
```

**Required Secrets**:

```yaml
# Git Credentials
git:
  credentials:
    username: "admin"
    password: "r8sA8CPHD9"  # Get from: oc get secret gitea-admin-secret -n gitea -o jsonpath='{.data.password}' | base64 -d

# S3/NooBaa Credentials (for model storage)
objectStore:
  accessKey: "AKIAIOSFODNN7EXAMPLE"
  secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

# Grafana Admin Password
grafana:
  adminPassword: "secure-password-here"
```

**Get NooBaa Credentials** (if using ODF):
```bash
# Get NooBaa credentials
oc get secret noobaa-admin -n openshift-storage -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d
oc get secret noobaa-admin -n openshift-storage -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d
```

⚠️ **IMPORTANT**: Ensure `values-secret.yaml` is in `.gitignore` - **NEVER commit secrets to git!**

### Step 5: Push Code to Git Repository

**For Gitea**:
```bash
# Get Gitea URL
GITEA_URL=$(oc get route gitea-with-admin -n gitea -o jsonpath='{.spec.host}')
echo "Gitea URL: https://${GITEA_URL}"

# Create repository in Gitea (via UI or API)
# Then push code
git remote add gitea https://${GITEA_URL}/openshift-aiops/openshift-aiops-platform.git
git push gitea main
```

**For GitHub**:
```bash
# Fork the repository on GitHub
# Clone your fork and push changes
git remote add github https://github.com/YOUR_ORG/openshift-aiops-platform.git
git push github main
```

---

## Deployment Process

### Step 1: Build Execution Environment

Before deploying, build the Ansible execution environment container:

```bash
make build-ee
```

This creates the `openshift-aiops-platform-ee:latest` container image that includes:
- Ansible Core and Navigator
- Required Ansible collections (kubernetes.core, community.general, etc.)
- Python dependencies (kubernetes client, openshift client)
- OpenShift CLI tools

**Expected Duration**: 5-10 minutes (first build)

**Verification**:
```bash
# Verify image exists
podman images | grep openshift-aiops-platform-ee

# Test the image
make test-ee
```

**Note**: The `deploy-with-prereqs` script will automatically build the image if it doesn't exist, but building it explicitly first provides better visibility and error detection.

### Step 1.5: Preview Pattern CR (Optional but Recommended)

Before deploying, preview what will be created:

```bash
./scripts/preview-pattern-cr.sh
```

**What This Shows**:
- Complete Pattern CR YAML
- Git configuration
- ArgoCD applications
- Resource counts
- Deployment readiness status

**Example Output**:
```
============================================================
Pattern CR Preview
============================================================

# Generated Pattern CR for: self-healing-platform
# Git URL: https://gitea-with-admin-gitea.apps.cluster-abc123.example.com/openshift-aiops/openshift-aiops-platform.git
# Git Revision: main

apiVersion: gitops.hybrid-cloud-patterns.io/v1alpha1
kind: Pattern
metadata:
  name: self-healing-platform
  namespace: openshift-operators
spec:
  gitConfig:
    targetRepo: https://gitea-with-admin-gitea.apps.cluster-abc123.example.com/openshift-aiops/openshift-aiops-platform.git
    targetRevision: main
  ...
```

**Save Preview** (optional):
```bash
./scripts/preview-pattern-cr.sh --save /tmp/pattern-cr-preview.yaml
```

### Step 2: Deploy Pattern with Prerequisites

**RECOMMENDED**: Use the wrapper script that handles all prerequisites and deployment:

```bash
make deploy-with-prereqs
```

This script implements the complete deployment sequence from [ADR-030: Hybrid Management Model](../adrs/030-hybrid-management-model-namespaced-argocd.md):

**Deployment Flow**:
1. ✅ Prerequisites validation (cluster, operators, storage)
2. ✅ Common infrastructure (External Secrets Operator, Helm, GitOps)
3. ✅ Secrets management (SecretStore, credentials)
4. ✅ Notebook validation setup (GitHub PAT, Tekton RBAC, build PVCs)
5. ✅ **Cluster-scoped RBAC** (ClusterRole/ClusterRoleBinding for ESO, operator, workbench)
6. ✅ Pattern deployment (Pattern CR → ArgoCD sync with namespaced resources only)
7. ✅ Post-deployment validation

**Why This is Required**:
- ArgoCD runs in **namespaced mode** and cannot manage cluster-scoped resources
- Cluster-scoped resources (ClusterRole, ClusterRoleBinding) must be deployed BEFORE Pattern CR
- Without this, ArgoCD fails with: `Cluster level ClusterRoleBinding can not be managed when in namespaced mode`

**Alternative: Manual Steps** (for advanced users who prefer granular control):

```bash
# Step 2a: Deploy prerequisites only
make deploy-prereqs-only

# Step 2b: Verify cluster resources deployed
oc get clusterrole,clusterrolebinding | grep self-healing

# Expected output:
# clusterrole.rbac.authorization.k8s.io/self-healing-operator-cluster
# clusterrole.rbac.authorization.k8s.io/self-healing-workbench-cluster
# clusterrolebinding.rbac.authorization.k8s.io/external-secrets-self-healing-platform
# clusterrolebinding.rbac.authorization.k8s.io/self-healing-operator-cluster
# clusterrolebinding.rbac.authorization.k8s.io/self-healing-workbench-cluster
# clusterrolebinding.rbac.authorization.k8s.io/self-healing-workbench-prometheus

# Step 2c: Deploy pattern
make -f common/Makefile operator-deploy
```

**Expected Duration**: 20-30 minutes (includes Ansible prerequisite deployment)

**Monitor Progress**:
```bash
# Watch Pattern CR status
oc get pattern -n openshift-operators --watch

# Check operator logs
oc logs -n openshift-operators -l control-plane=patterns-operator -f

# Watch ArgoCD applications
make -f common/Makefile argo-healthcheck
```

### Step 3: Monitor Deployment

**Pattern CR Status**:
```bash
oc get pattern self-healing-platform -n openshift-operators

# NAME                    CLUSTER           PLATFORM   VERSION
# self-healing-platform   cluster-abc123    AWS        4.21.0
```

**ArgoCD Application Health**:
```bash
# Login to ArgoCD
argocd login $(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}') --insecure

# Check application status
argocd app list

# NAME                            CLUSTER                         NAMESPACE                    PROJECT  STATUS  HEALTH   SYNCPOLICY  CONDITIONS
# self-healing-platform-hub       https://kubernetes.default.svc  openshift-gitops             default  Synced  Healthy  Auto        <none>
# self-healing-platform           https://kubernetes.default.svc  self-healing-platform        default  Synced  Healthy  Auto        <none>
```

**Expected Timeline**:
- **0-5 min**: Operator installs, GitOps deployed
- **5-10 min**: Clustergroup app syncs, namespaces created
- **10-15 min**: Platform components deploy (coordination engine, notebooks)
- **15-20 min**: Model serving and validation jobs start
- **20-25 min**: All applications reach "Healthy" status

---

## Validation

### Step 1: Run Post-Deployment Validation

Execute comprehensive validation:

```bash
# Using Tekton pipeline (26 validation checks)
tkn pipeline start deployment-validation-pipeline \
  --param namespace=self-healing-platform \
  --param cluster-version=4.19 \
  --showlog
```

**Validation Checks**:
- ✅ Prerequisites (cluster, tools, RBAC, namespace)
- ✅ Operators (GitOps, AI, KServe, GPU, ODF)
- ✅ Storage (classes, PVCs, ODF, S3)
- ✅ Model Serving (InferenceServices, endpoints, pods)
- ✅ Coordination Engine (deployment, health, API, DB)
- ✅ Monitoring (Prometheus, alerts, Grafana)

**Expected Result**:
```
✅ DEPLOYMENT READY: All checks passed
Validation Summary: 26/26 checks passed
```

### Step 2: Verify Key Components

**Check All Pods Running**:
```bash
oc get pods -n self-healing-platform

# NAME                                    READY   STATUS
# coordination-engine-xxx                 1/1     Running
# self-healing-workbench-0                1/1     Running
# cluster-health-mcp-server-xxx           1/1     Running
```

**Test Coordination Engine**:
```bash
POD=$(oc get pod -n self-healing-platform -l app=coordination-engine -o jsonpath='{.items[0].metadata.name}')
oc exec -n self-healing-platform $POD -- curl -s http://localhost:8080/health
# {"status": "healthy"}
```

**Verify Jupyter Workbench**:
```bash
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
# Access http://localhost:8888
```

**Check Model Serving**:
```bash
oc get inferenceservices -n self-healing-platform

# NAME                READY   URL
# anomaly-detector    True    http://anomaly-detector...
```

### Step 3: Run Infrastructure Validation Notebook

Execute the platform readiness validation notebook:

```bash
# Access Jupyter and run: notebooks/00-setup/00-platform-readiness-validation.ipynb
# Or check validation job status:
oc get notebookvalidationjobs -n self-healing-platform
```

---

## Troubleshooting

### Pattern CR Not Syncing

**Symptoms**:
- Pattern CR shows `lastStep: Installing GitOps` for >10 minutes
- No ArgoCD applications created

**Debug Steps**:
```bash
# Check Pattern CR status
oc describe pattern self-healing-platform -n openshift-operators

# Check operator logs
oc logs -n openshift-operators -l control-plane=patterns-operator --tail=100

# Verify Git repository accessibility
curl -I $(yq eval '.git.repoURL' values-global.yaml)
```

**Common Causes**:
- ❌ Git repository not accessible
- ❌ Invalid Git credentials
- ❌ Helm chart errors in repository
- ❌ Missing CRDs

**Resolution**:
```bash
# Recreate Pattern CR
oc delete pattern self-healing-platform -n openshift-operators
make -f common/Makefile operator-deploy
```

### ArgoCD Application OutOfSync

**Symptoms**:
- Application shows "OutOfSync" status
- Resources not deploying

**Debug Steps**:
```bash
# Check application details
argocd app get self-healing-platform

# View sync diff
argocd app diff self-healing-platform

# Check application events
oc get events -n openshift-gitops --sort-by='.lastTimestamp' | grep self-healing
```

**Resolution**:
```bash
# Force sync with prune
argocd app sync self-healing-platform --prune --force

# Or via OpenShift GitOps UI
# Navigate to Applications → self-healing-platform → Sync → Force
```

### Missing GPU Nodes

**Symptoms**:
- GPU-enabled workloads stuck in "Pending"
- Notebook validator jobs fail

**Debug Steps**:
```bash
# Check GPU node labels
oc get nodes -l nvidia.com/gpu.present=true

# Check GPU operator pods
oc get pods -n gpu-operator-resources

# View pod events
oc describe pod <gpu-pod-name> -n self-healing-platform
```

**Resolution**:
- Ensure GPU nodes are properly labeled
- Verify NVIDIA GPU Operator is healthy
- Check node taints/tolerations

### Storage Class Issues

**Symptoms**:
- PVCs stuck in "Pending"
- No dynamic provisioning

**Debug Steps**:
```bash
# Check PVC status
oc get pvc -n self-healing-platform

# Check storage classes
oc get storageclass

# Describe pending PVC
oc describe pvc <pvc-name> -n self-healing-platform
```

**Resolution**:
- Verify ODF is deployed: `oc get pods -n openshift-storage`
- Check storage class configuration
- Ensure sufficient storage capacity

### Secrets Not Syncing

**Symptoms**:
- External Secrets show "SecretSyncedError"
- Applications fail to start due to missing secrets

**Debug Steps**:
```bash
# Check External Secrets status
oc get externalsecrets -n self-healing-platform

# Check SecretStore
oc get secretstore -n self-healing-platform

# View External Secrets Operator logs
oc logs -n openshift-operators -l app.kubernetes.io/name=external-secrets
```

**Resolution**:
- Verify secrets backend (Vault, AWS Secrets Manager) is accessible
- Check SecretStore configuration
- Validate backend credentials

---

## Next Steps

### 1. Configure Monitoring

Set up Grafana dashboards and Prometheus alerts:

```bash
# Access Grafana
oc get route grafana -n self-healing-platform

# Import pre-configured dashboards
oc apply -f charts/hub/templates/monitoring/
```

### 2. Run Notebook Workflows

Execute the self-healing workflows:

1. **Data Collection**: `notebooks/01-data-collection/`
2. **Anomaly Detection**: `notebooks/02-anomaly-detection/`
3. **Self-Healing Logic**: `notebooks/03-self-healing-logic/`
4. **Model Serving**: `notebooks/04-model-serving/`
5. **End-to-End Scenarios**: `notebooks/05-end-to-end-scenarios/`

### 3. Integrate with OpenShift Lightspeed

Configure MCP server for natural language interface:

```bash
# Deploy MCP server
oc apply -f k8s/base/mcp-server/

# Configure OLSConfig (if using Gemini)
# See: docs/adrs/017-gemini-integration-openshift-lightspeed.md
```

### 4. Set Up Multi-Cluster Management (Optional)

If using Advanced Cluster Management:

```bash
# Install ACM operator on hub
# See: docs/RED-HAT-ACM-INTEGRATION-GUIDE.md
```

### 5. Enable CI/CD Webhooks

Configure GitHub webhooks for automated deployments:

```bash
# Get EventListener route
oc get route deployment-validation-trigger -n openshift-pipelines

# Add webhook to GitHub repository
# Settings → Webhooks → Add webhook
# URL: <route-url>
# Events: push
```

---

## Additional Resources

### Documentation
- [AGENTS.md](../../AGENTS.md) - Complete platform architecture and development guide
- [Pattern CR Best Practices](PATTERN-CR-BEST-PRACTICES.md) - Advanced configuration patterns
- [Example Deployment Walkthrough](EXAMPLE-DEPLOYMENT-WALKTHROUGH.md) - Real-world deployment example
- [ADR Index](../adrs/README.md) - Architectural Decision Records

### Validated Patterns
- [Validated Patterns Framework](https://validatedpatterns.io/)
- [Pattern Installation Chart](https://github.com/validatedpatterns/pattern-install)
- [Common Subtree](https://github.com/validatedpatterns/common)

### OpenShift Documentation
- [OpenShift GitOps](https://docs.openshift.com/gitops/latest/)
- [OpenShift AI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
- [External Secrets Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/security_and_compliance/external-secrets-operator-for-red-hat-openshift)

---

## Support and Contributions

### Getting Help
- Open an issue: https://github.com/openshift-aiops/openshift-aiops-platform/issues
- Check existing issues and discussions
- Review troubleshooting section above

### Contributing
- Fork the repository
- Create a feature branch
- Submit a pull request
- Follow ADR process for architectural changes

---

**Document Version**: 1.0
**Last Updated**: 2025-12-05
**Tested With**: OpenShift 4.19-4.21, RHOAI 2.22.2, ODF 4.20, GitOps 1.20.3, Pipelines 1.22.0
**Authors**: Platform Team
**License**: GPL v3.0
