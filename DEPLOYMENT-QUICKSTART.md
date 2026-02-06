# OpenShift AI Ops Platform - Deployment Quick Start

## Overview

The OpenShift AI Ops Self-Healing Platform uses a **Hybrid Management Model** (ADR-030) that requires deploying cluster-scoped resources via Ansible BEFORE Pattern CR deployment.

## Prerequisites

- OpenShift 4.18+ cluster with required operators
- Configuration files: `values-global.yaml`, `values-hub.yaml`, `values-secret.yaml`
- Git repository (Gitea or GitHub) with code pushed

## Quick Start

### Step 1: Get the Execution Environment

#### Option A: Pull Pre-Built Image (Recommended)

```bash
# Pull the latest pre-built image from Quay.io
podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest

# Tag for local use
podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest \
  openshift-aiops-platform-ee:latest
```

#### Option B: Build Locally

```bash
# Requires ANSIBLE_HUB_TOKEN (get from https://console.redhat.com/ansible/automation-hub/token)
export ANSIBLE_HUB_TOKEN='your-token-here'
make build-ee
```

This creates the `openshift-aiops-platform-ee:latest` container image with all required Ansible collections and dependencies.

**Note**: The wrapper script will automatically build the image if missing, but getting it explicitly first provides better visibility and faster subsequent runs.

### Step 2: Complete Deployment with Prerequisites (Recommended)

```bash
# Single command - handles everything
make deploy-with-prereqs
```

This runs the full deployment sequence:
1. Prerequisites validation
2. External Secrets Operator deployment
3. Secrets management setup
4. Notebook validation setup
5. **Cluster-scoped RBAC deployment** (ClusterRole/ClusterRoleBinding)
6. Pattern CR deployment (namespaced resources via ArgoCD)
7. Post-deployment validation

### Alternative: Manual Steps (Advanced)

```bash
# Step 1: Get execution environment (Option A: pull, or Option B: build)
podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest \
  openshift-aiops-platform-ee:latest
# Or: export ANSIBLE_HUB_TOKEN='your-token' && make build-ee

# Step 2: Deploy prerequisites only
make deploy-prereqs-only

# Step 3: Verify cluster resources
oc get clusterrole,clusterrolebinding | grep self-healing

# Step 4: Deploy pattern
make -f common/Makefile operator-deploy

# Step 5: Validate
make argo-healthcheck
```

### Alternative: Skip Prerequisites (If Already Run)

```bash
# Get EE first (if not already available) — pull or build
# podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest && \
#   podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest openshift-aiops-platform-ee:latest
# Or: make build-ee

# Use this if you've already run deploy-prereqs-only
make -f common/Makefile operator-deploy
```

## Verification

### Check Cluster-Scoped Resources

```bash
oc get clusterrole,clusterrolebinding | grep self-healing
```

Expected output:
```
clusterrole.rbac.authorization.k8s.io/self-healing-operator-cluster
clusterrole.rbac.authorization.k8s.io/self-healing-workbench-cluster
clusterrolebinding.rbac.authorization.k8s.io/external-secrets-self-healing-platform
clusterrolebinding.rbac.authorization.k8s.io/self-healing-operator-cluster
clusterrolebinding.rbac.authorization.k8s.io/self-healing-workbench-cluster
clusterrolebinding.rbac.authorization.k8s.io/self-healing-workbench-prometheus
```

### Check ArgoCD Applications

```bash
oc get applications.argoproj.io -A
make argo-healthcheck
```

### Check Pods

```bash
oc get pods -n self-healing-platform
```

## Why This Approach?

**Problem**: ArgoCD in namespaced mode cannot manage cluster-scoped resources (ClusterRole, ClusterRoleBinding).

**Solution**: Deploy cluster-scoped resources via Ansible BEFORE Pattern CR creation (Hybrid Management Model).

**Reference**: [ADR-030: Hybrid Management Model for Namespaced ArgoCD](docs/adrs/030-hybrid-management-model-namespaced-argocd.md)

## Troubleshooting

### "Cluster level ClusterRoleBinding can not be managed when in namespaced mode"

**Cause**: Cluster-scoped resources not deployed before Pattern CR.

**Fix**:
```bash
# Deploy cluster resources
make deploy-prereqs-only

# Verify deployment
oc get clusterrole,clusterrolebinding | grep self-healing

# Then deploy pattern
make -f common/Makefile operator-deploy
```

### ArgoCD Application Shows "Missing" or "Unknown"

```bash
# Check application details
oc get application self-healing-platform -n self-healing-platform-hub -o yaml

# Force refresh
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite

# Wait and check again
sleep 30
oc get applications.argoproj.io -A
```

### External Secrets Operator Not Found

```bash
# Check if ESO was deployed
oc get csv -n openshift-operators | grep external-secrets

# If not found, run prerequisites
make deploy-prereqs-only
```

## Next Steps

After successful deployment:

1. **Monitor ArgoCD Sync**:
   ```bash
   oc get applications.argoproj.io -A --watch
   ```

2. **Check Pod Status**:
   ```bash
   oc get pods -n self-healing-platform --watch
   ```

3. **View ArgoCD UI**:
   ```bash
   oc get route -n openshift-gitops
   ```

4. **Access Documentation**:
   - Complete guide: [docs/guides/NEW-CLUSTER-DEPLOYMENT.md](docs/guides/NEW-CLUSTER-DEPLOYMENT.md)
   - Architecture: [docs/adrs/030-hybrid-management-model-namespaced-argocd.md](docs/adrs/030-hybrid-management-model-namespaced-argocd.md)
   - Makefile targets: `make help`

## Available Makefile Targets

```bash
make build-ee                  # Build execution environment container (alternative to pulling pre-built image)
make deploy-with-prereqs       # Complete deployment with prerequisites (recommended)
make deploy-prereqs-only       # Deploy only prerequisites
make operator-deploy           # Deploy pattern via VP Operator (use after prereqs)
make argo-healthcheck          # Check ArgoCD application health
make uninstall                 # Remove pattern deployment
make help                      # Show all available targets
```

## References

- [ADR-030: Hybrid Management Model](docs/adrs/030-hybrid-management-model-namespaced-argocd.md)
- [ADR-019: Validated Patterns Framework](docs/adrs/019-validated-patterns-framework-adoption.md)
- [Complete Deployment Guide](docs/guides/NEW-CLUSTER-DEPLOYMENT.md)
- [Ansible Playbook](ansible/playbooks/deploy_complete_pattern.yml)
