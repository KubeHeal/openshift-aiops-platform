# OpenShift AI Ops Platform - Deployment Guide

## 📋 Complete Deployment Workflow

This guide provides the **complete, step-by-step deployment process** for the OpenShift AI Ops Self-Healing Platform.

---

## 🎯 Prerequisites

Before starting deployment, ensure you have:

### Cluster Requirements
- ✅ OpenShift 4.18.21+ cluster with admin access
- ✅ 6+ nodes (3 control-plane, 3 workers, 1 GPU-enabled)
- ✅ 24+ CPU cores, 96+ GB RAM, 500+ GB storage
- ✅ OpenShift Data Foundation (ODF) deployed

### Local Tools
- ✅ `oc` CLI (OpenShift client)
- ✅ `podman` or `docker` (container runtime)
- ✅ `ansible-navigator` (for Ansible execution)
- ✅ `git` (version control)
- ✅ `make` (build automation)
- ✅ `yq` (YAML processor)

### Credentials
- ✅ `ANSIBLE_HUB_TOKEN` (from https://console.redhat.com/ansible/automation-hub/token)
- ✅ OpenShift cluster kubeconfig (logged in via `oc login`)

---

## 🚀 Deployment Steps

### Step 1: Build Execution Environment (EE)

The Execution Environment contains all dependencies needed for Ansible playbooks.

```bash
# Clone repository (if not already cloned)
git clone https://github.com/openshift-aiops/openshift-aiops-platform.git
cd openshift-aiops-platform

# Set Ansible Hub token (required for building EE)
export ANSIBLE_HUB_TOKEN='your-token-here'

# Or create a token file
echo 'your-token-here' > token

# Build the execution environment image
make build-ee
```

**What this does**:
- Builds containerized Ansible execution environment
- Installs all required Ansible collections and Python dependencies
- Creates image: `localhost/openshift-aiops-platform-ee:latest`
- Takes ~10-15 minutes on first build

**Verify**:
```bash
# List the built image
make list-ee

# Test the execution environment
make test-ee
```

---

### Step 2: Install Jupyter Notebook Validator Operator

The Notebook Validator Operator enables automated notebook validation via NotebookValidationJob CRDs.

```bash
# Install the operator using kustomize
make install-jupyter-validator
```

**What this does**:
- Deploys Jupyter Notebook Validator CRDs
- Installs operator in `jupyter-notebook-validator-system` namespace
- Creates RBAC for validation jobs
- Takes ~3-5 minutes

**Verify**:
```bash
# Check operator installation
make validate-jupyter-validator

# Should show:
# ✅ CRD installed: notebookvalidationjobs.mlops.mlops.dev
# ✅ Operator pod running: jupyter-notebook-validator-controller-manager
# ✅ Webhook service ready
```

---

### Step 3: Deploy Prerequisites (CRITICAL)

**⚠️ MANDATORY STEP** - Creates ServiceAccounts and RBAC before ArgoCD sync.

```bash
# Run Ansible prerequisites
make deploy-prereqs-only
```

**What this does**:
- ✅ Creates ServiceAccounts (`self-healing-operator`, `external-secrets-sa`)
- ✅ Creates cluster-scoped RBAC (ClusterRoles, ClusterRoleBindings)
- ✅ Creates namespaced RBAC (Roles, RoleBindings)
- ✅ Loads secrets from `.env` file (if exists)
- ✅ Breaks ArgoCD circular dependency (hooks need SA before creation)
- Takes ~5-10 minutes

**Why this is critical**:
- ArgoCD sync hooks (e.g., `noobaa-credentials-init`) need ServiceAccounts
- Without pre-created ServiceAccounts, hooks fail → ArgoCD can't sync
- This fixes the "serviceaccount not found" circular dependency

**Verify**:
```bash
# Check ServiceAccounts created
oc get sa -n self-healing-platform | grep -E "self-healing-operator|external-secrets"

# Check RBAC created
oc get clusterrole | grep self-healing
oc get role -n self-healing-platform

# Expected output:
# self-healing-operator ServiceAccount exists
# external-secrets-sa ServiceAccount exists
# ClusterRole: self-healing-operator
# Role: external-secrets-self-healing-platform
```

---

### Step 4: Deploy Pattern (Primary Deployment)

Deploy the pattern using the Validated Patterns Operator (recommended end-user workflow).

```bash
# Deploy using common Makefile (VP Operator)
make -f common/Makefile operator-deploy
```

**What this does**:
- ✅ Validates cluster prerequisites
- ✅ Deploys Pattern CR via Validated Patterns Operator
- ✅ Operator creates ArgoCD applications automatically
- ✅ ArgoCD syncs all platform components with sync waves
- ✅ Deploys (in order):
  - Wave -6: External Secrets Operator, SecretStore
  - Wave -5: Model storage PVC, init-models-job
  - Wave -4: ExternalSecrets (git-credentials, model-storage-config)
  - Wave -3: Workbench, RBAC
  - Wave -2: Model serving InferenceServices
  - Wave -1: Coordination engine
  - Wave 0: MCP server
  - Wave 1+: Notebook validation jobs
- Takes ~20-30 minutes for full deployment

**Alternative (Development Workflow)**:
```bash
# Deploy with Ansible roles (granular control)
make deploy-with-prereqs
```

**Verify**:
```bash
# Check Pattern CR created
oc get pattern self-healing-platform -n openshift-operators

# Check ArgoCD applications
make -f common/Makefile argo-healthcheck

# Should show all applications "Synced" and "Healthy"
```

---

### Step 5: Validate Deployment

Run comprehensive validation checks to ensure platform is operational.

```bash
# Run Tekton post-deployment validation pipeline
make validate-deployment

# Alternative: Run validation pipeline manually
tkn pipeline start deployment-validation-pipeline \
  --param namespace=self-healing-platform \
  --param cluster-version=4.18 \
  --showlog
```

**What this validates** (26 checks):
- ✅ Prerequisites: Cluster, tools, RBAC, namespace
- ✅ Operators: GitOps, AI, KServe, GPU, ODF
- ✅ Storage: Classes, PVCs, ODF, S3
- ✅ Model Serving: InferenceServices, endpoints, pods, metrics
- ✅ Coordination Engine: Deployment, health, API, DB
- ✅ Monitoring: Prometheus, alerts, Grafana, logging
- ✅ **NEW**: Inference endpoint testing (POST requests)

**Verify model storage structure**:
```bash
# Check that init-models-job created all subdirectories
oc exec -it self-healing-workbench-0 -n self-healing-platform -- \
  ls -la /mnt/models/

# Expected output:
# drwxr-xr-x. predictive-analytics/
# drwxr-xr-x. arima-predictor/
# drwxr-xr-x. prophet-predictor/
# drwxr-xr-x. lstm-predictor/
# drwxr-xr-x. ensemble-predictor/
# drwxr-xr-x. anomaly-detector/
# -rw-r--r--. .initialized
```

---

## 📊 Post-Deployment Verification

### Check Platform Components

```bash
# 1. Check all pods are running
oc get pods -n self-healing-platform

# Should show:
# - self-healing-workbench-0 (Running)
# - coordination-engine-* (Running) # Go-based from https://github.com/KubeHeal/openshift-coordination-engine
# - cluster-health-mcp-server-* (Running)
# - predictive-analytics-predictor-* (Running/PodInitializing)
# - *-validation (Completed/Running)

# 2. Check NotebookValidationJobs
oc get notebookvalidationjob -n self-healing-platform

# Should show validation jobs for each tier (tier0, tier1, tier2, tier3)

# 3. Check InferenceServices (may be NotReady until models loaded)
oc get inferenceservices -n self-healing-platform

# 4. Check ExternalSecrets synced
oc get externalsecrets -n self-healing-platform
oc get secrets -n self-healing-platform | grep -E "git-credentials|model-storage"

# 5. Check ArgoCD application health
oc get applications -n openshift-gitops

# All should be "Synced" and "Healthy"
```

### Access Platform Components

```bash
# 1. Access Jupyter Workbench
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
# Open: http://localhost:8888

# 2. Access ArgoCD UI
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
# Username: admin
# Password: oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-

# 3. Test Coordination Engine API (Go-based engine)
oc port-forward svc/coordination-engine 8080:8080 -n self-healing-platform
curl http://localhost:8080/health
# For Go engine source: https://github.com/KubeHeal/openshift-coordination-engine

# 4. Check MCP Server (stdio transport - no external endpoint)
oc logs deployment/cluster-health-mcp-server -n self-healing-platform
```

---

## 🚀 Optional: Deploy MCP Server and OpenShift Lightspeed

The MCP Server is deployed automatically via ArgoCD, but you may want to configure OpenShift Lightspeed integration for conversational AI capabilities.

### Quick Deployment

```bash
# 1. View deployment documentation
make show-mcp-docs

# 2. Verify MCP Server is running (deployed via ArgoCD)
oc get deployment cluster-health-mcp-server -n self-healing-platform

# 3. Create OpenAI API key secret (if using OpenShift Lightspeed)
oc create secret generic openai-api-key \
  -n openshift-lightspeed \
  --from-literal=apiKey='YOUR_OPENAI_API_KEY'

# 4. Configure OpenShift Lightspeed
make configure-lightspeed

# 5. Test MCP Server integration
make test-mcp-server
```

### Available MCP Targets

```bash
# Deploy MCP Server (development overlay) - if not already deployed
make deploy-mcp-server

# Deploy production configuration
make deploy-mcp-server-production

# Configure OpenShift Lightspeed
make configure-lightspeed

# Test MCP Server health and integration
make test-mcp-server

# Remove MCP Server deployment
make uninstall-mcp-server

# Show all documentation links
make show-mcp-docs
```

### Documentation

- **📄 ADR-014**: [MCP Server Architecture](docs/adrs/014-openshift-aiops-platform-mcp-server.md)
- **📖 Deployment Guide**: [How-To: Deploy MCP Server](docs/how-to/deploy-mcp-server-lightspeed.md)
- **🔧 Kustomize Manifests**: `k8s/mcp-server/` (see [README](k8s/mcp-server/README.md))
- **📓 Notebook**: `notebooks/06-mcp-lightspeed-integration/openshift-lightspeed-integration.ipynb`

**Note**: The MCP Server is automatically deployed via ArgoCD as part of the pattern. The targets above are primarily for:
- Manual deployment (if ArgoCD deployment is disabled)
- OpenShift Lightspeed configuration (requires separate setup)
- Testing and validation
- Development and debugging

---

## 🔄 Cleanup and Rebuild

### Clean Deployment (Retains Shared Infrastructure)

```bash
# Run Ansible cleanup playbook
ansible-navigator run ansible/playbooks/cleanup_pattern.yml \
  --container-engine podman \
  --execution-environment-image openshift-aiops-platform-ee:latest \
  --mode stdout
```

**What this removes**:
- ✅ Pattern CR
- ✅ ArgoCD applications
- ✅ Application namespaces (`self-healing-platform`)
- ✅ PVCs and ConfigMaps

**What this retains** (for faster rebuild):
- ✅ OpenShift GitOps (ArgoCD)
- ✅ Gitea (local git repository)
- ✅ Validated Patterns Operator
- ✅ Jupyter Notebook Validator Operator

### Complete Teardown (Remove Everything)

```bash
# Delete Pattern CR
oc delete pattern self-healing-platform -n openshift-operators

# Delete ArgoCD applications
oc delete applications --all -n openshift-gitops

# Delete application namespaces
oc delete namespace self-healing-platform

# Uninstall Jupyter Notebook Validator
make uninstall-jupyter-validator

# Optional: Remove GitOps (rarely needed)
oc delete namespace openshift-gitops

# Optional: Uninstall VP Operator (rarely needed)
oc delete subscription patterns-operator -n openshift-operators
oc delete csv -n openshift-operators $(oc get csv -n openshift-operators | grep patterns-operator | awk '{print $1}')
```

---

## 🐛 Troubleshooting

### Build Issues

**Problem**: `make build-ee` fails with "ANSIBLE_HUB_TOKEN not set"

```bash
# Solution: Set token
export ANSIBLE_HUB_TOKEN='your-token-here'
# Or create token file
echo 'your-token-here' > token
```

**Problem**: EE build fails with "permission denied"

```bash
# Solution: Check container runtime
podman info  # or docker info
# Ensure you have permissions to run containers
```

### Prerequisite Issues

**Problem**: `make deploy-prereqs-only` fails with "cluster not accessible"

```bash
# Solution: Verify cluster login
oc whoami
oc cluster-info

# Re-login if needed
oc login --server=https://api.your-cluster.com:6443
```

**Problem**: ServiceAccounts not created

```bash
# Solution: Check Ansible execution
ansible-navigator run ansible/playbooks/operator_deploy_prereqs.yml --mode stdout

# Check for errors in output
# Verify you have cluster-admin permissions
```

### Deployment Issues

**Problem**: ArgoCD applications stuck "OutOfSync"

```bash
# Solution: Force sync
argocd app sync self-healing-platform --force

# Or delete and let operator recreate
oc delete application self-healing-platform -n openshift-gitops
# Wait for operator to recreate
```

**Problem**: Pods stuck in "Init:Error" or "CrashLoopBackOff"

```bash
# Solution: Check events
oc get events -n self-healing-platform --sort-by='.lastTimestamp'

# Check pod logs
oc logs <pod-name> -n self-healing-platform

# Common issues:
# - Missing ServiceAccount: Run deploy-prereqs-only again
# - PVC not bound: Check storage class and ODF
# - Image pull error: Check BuildConfigs completed
```

**Problem**: NotebookValidationJobs fail with "multiple files detected"

```bash
# Solution: This should be fixed by our model storage isolation changes
# Verify init-models-job created subdirectories
oc get job init-model-storage -n self-healing-platform
oc logs job/init-model-storage -n self-healing-platform

# Manually create if needed
oc exec -it self-healing-workbench-0 -n self-healing-platform -- \
  mkdir -p /mnt/models/{predictive-analytics,arima-predictor,prophet-predictor,lstm-predictor,ensemble-predictor}
```

---

## 📚 Additional Resources

- **Architecture**: [AGENTS.md](AGENTS.md) - Complete platform architecture and agent guidance
- **ADRs**: [docs/adrs/](docs/adrs/) - Architectural Decision Records
- **Notebooks**: [notebooks/](notebooks/) - Jupyter notebooks for ML workflows
- **Ansible Roles**: [ansible/roles/](ansible/roles/) - Reusable deployment roles

---

## 🆘 Support

For issues or questions:
1. Check [AGENTS.md](AGENTS.md) for detailed platform documentation
2. Review relevant ADRs in `docs/adrs/`
3. Check Tekton validation pipeline logs
4. Review ArgoCD application status

---

**Last Updated**: 2025-12-09
**Platform Version**: 1.0
**OpenShift Version**: 4.18.21+
