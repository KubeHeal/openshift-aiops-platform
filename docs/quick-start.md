# Quick Start

Get the OpenShift AI Ops Self-Healing Platform running in 5 minutes.

---

## Supported Cluster Topologies

This platform supports both HighlyAvailable (HA) and Single Node OpenShift (SNO) deployments:

| Topology | Nodes | Storage | ODF | Use Case |
|----------|-------|---------|-----|----------|
| **HA (HighlyAvailable)** | 3+ (separate control-plane/worker) | ODF + CSI | ✅ Yes | Production, full features |
| **SNO SingleReplica** | 1 (all roles on single node) | CSI only | ❌ No | Edge, development, testing |

**Supported OpenShift Versions:**
- OpenShift 4.19, 4.20, 4.21 (active support window; 4.18 maintenance)
- Auto-detected during deployment
- Version-specific operator overlays

**Auto-Detection:**

The platform automatically detects your cluster topology and version. After installing prerequisites and logging into your cluster, verify with `make show-cluster-info`.

📖 **See also:** [SNO Deployment Guide](how-to/deploy-on-sno.md)

---

## RHPDS Deployment Options

You can deploy this platform on **Red Hat Product Demo System (RHPDS)** clusters. Two catalog items are available:

### Option 1: SNO with OpenShift AI 3 (Recommended for Quick Start)

**Catalog Item:** [Red Hat OpenShift AI 3](https://catalog.demo.redhat.com/catalog?item=babylon-catalog-prod/published.openshift-ai-v3.prod&utm_source=webapp&utm_medium=share-link)

**What's Included:**
- Single-Node OpenShift (SNO) with GPU instance
- OpenShift AI 3 (latest, generally available)
- Pre-configured and ready for platform deployment
- Ideal for demos, POCs, and exploration

**Deployment Time:** ~1 hour  
**Topology:** SNO (Single Node OpenShift)

### Option 2: HA Cluster with NVIDIA GPUs on AWS

**Catalog Item:** [RHOAI on OCP on AWS with NVIDIA GPUs](https://catalog.demo.redhat.com/catalog?item=babylon-catalog-prod/sandboxes-gpte.ocp4-demo-rhods-nvidia-gpu-aws.prod&utm_source=webapp&utm_medium=share-link)

**What's Included:**
- OpenShift Container Platform 4.18 (HA cluster)
- Red Hat OpenShift AI 2.25
- NVIDIA L4 Tensor Core GPUs
- Full HA deployment with multiple nodes

**Deployment Time:** ~1 hour, 40 minutes  
**Topology:** HA (HighlyAvailable)  
**Note:** OCP 4.21 is the current recommended version. Upgrade from 4.18 to 4.19+ recommended — 4.18 is maintenance-only.

**Auto-Stop:** 6 hours | **Auto-Destroy:** 48 hours

**Deployment Notes:**
- Both RHPDS options come with OpenShift AI pre-installed, reducing deployment time
- Follow the standard deployment workflow (see Installation section below)
- For SNO clusters (Option 1), ensure you update `values-hub.yaml` with SNO-specific configuration
- For HA clusters (Option 2), standard HA configuration applies

---

## Prerequisites

**HA Cluster Requirements:**
- OpenShift 4.19+ cluster recommended (4.21 current; admin access)
- 6+ nodes (3 control-plane, 3+ workers, 1 GPU-enabled recommended)
- 24+ CPU cores, 96+ GB RAM, 500+ GB storage

**SNO Cluster Requirements:**
- OpenShift 4.19+ cluster recommended (4.21 current; admin access)
- 1 node (all roles: control-plane, master, worker)
- 8+ CPU cores (16+ recommended), 32+ GB RAM (64+ recommended), 120+ GB storage

**Local Workstation Tools:**
- `podman` - Container runtime for building execution environments
- `oc` and `kubectl` - OpenShift/Kubernetes CLI
- `helm` 3.12+ - Kubernetes package manager
- `ansible-navigator` - Ansible execution environment runner
- `ansible-builder` - Build custom Ansible execution environments
- `yq` - YAML processor
- `tkn` - Tekton CLI (optional, for pipeline management)
- `git`, `make`, `jq` - Standard development tools

**Credentials:**
- Red Hat Ansible Automation Hub token ([get one here](https://console.redhat.com/ansible/automation-hub/token))

---

## RHEL 9/10 Workstation Setup (One-Time)

If you're running **RHEL 9** or **RHEL 10**, run the prerequisites installer script (from the cloned repository) to set up all required tools:

```bash
# Run from the cloned repository directory (see Installation steps below)
./scripts/install-prerequisites-rhel.sh

# Start a new terminal or source your shell config
source ~/.bashrc
```

**What the script installs:**
- System packages via `dnf` (podman, git, make, jq, python3-pip, development headers)
- Python virtual environment at `~/.venv/aiops-platform` with ansible-navigator, ansible-builder
- CLI tools: `oc`, `kubectl`, `helm`, `yq`, `tkn` (installed to `/usr/local/bin/`)

> **💡 Note**: The script is idempotent - safe to run multiple times. It will prompt before reinstalling existing tools.

> **💡 Fedora/CentOS Stream**: The script may work on Fedora and CentOS Stream 9+ but is tested on RHEL.

---

## Installation

### Option 1: Validated Patterns Operator (Recommended)

This pattern is installed via the [Validated Patterns Operator](https://validatedpatterns.io/). The operator manages the full GitOps lifecycle — no `make load-secrets` step is required for the default public-GitHub configuration.

```bash
# 1. Fork the repository on GitHub
# Click "Fork" at https://github.com/KubeHeal/openshift-aiops-platform

# 2. Clone YOUR fork
git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
cd openshift-aiops-platform

# 3. Log into your OpenShift cluster
oc login <cluster-api-url>

# 4. Update git.repoURL in values-global.yaml to point to YOUR fork
vi values-global.yaml
# Set: git.repoURL: "https://github.com/<your-github-user>/openshift-aiops-platform.git"

# 5. Commit and push the values change to your fork
git add values-global.yaml && git commit -m "chore: point repoURL to my fork" && git push

# 6. Install via the VP CLI
./pattern.sh make install
```

The VP Operator creates an ArgoCD instance (`self-healing-platform-hub` namespace) and syncs all operators and workloads. Wait for the pattern to converge:

```bash
oc get applications.argoproj.io -n self-healing-platform-hub
# Target state: SYNC STATUS=Synced, HEALTH STATUS=Healthy
```

**Secrets — only required for optional features:**

The default deployment uses public GitHub and requires no source secrets. Create source secrets only if you enable optional features:

| Feature | Enable flag | Source secret to create |
|---|---|---|
| Self-hosted Gitea mirror | `gitea.enabled: true` | `gitea-credentials-source` |
| Private notebook repos | `notebookValidation.requiresAuth: true` | `github-pat-credentials-source` |
| External container registry | `registry.credentials` set | `registry-credentials-source` |
| External database | `database.credentials` set | `database-credentials-source` |

```bash
# Example — only if using Gitea (gitea.enabled: true):
oc create secret generic gitea-credentials-source \
  --from-literal=username=<gitea-user> \
  --from-literal=password=<gitea-token> \
  -n self-healing-platform

# Example — only if using private notebooks (notebookValidation.requiresAuth: true):
oc create secret generic github-pat-credentials-source \
  --from-literal=username=<github-user> \
  --from-literal=password=<github-pat> \
  -n self-healing-platform
```

See `values-secret.yaml.template` at the repository root for the full decision matrix.

> **SNO Deployment**: Set `cluster.topology: "sno"` and `storage.modelStorage.storageClass: "gp3-csi"` in `values-hub.yaml` before running `./pattern.sh make install`. Object storage (NooBaa) is automatically provided by MCG-only ODF. See [SNO Deployment Guide](how-to/deploy-on-sno.md) for details.

---

### Option 2: Fork and Deploy with Validated Patterns Operator

```bash
# 1. Clone the repository
git clone https://github.com/KubeHeal/openshift-aiops-platform.git
cd openshift-aiops-platform

# 2. Install workstation prerequisites (RHEL 9/10 only - skip if tools already installed)
./scripts/install-prerequisites-rhel.sh
source ~/.bashrc

# 3. Log into your OpenShift cluster
oc login <cluster-api-url>

# 4. Create values files from examples (REQUIRED before any make target)
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml  # if not already present

# 5. Verify cluster topology and version
make show-cluster-info
# Output shows: Topology (ha or sno), OpenShift Version, Platform, ODF Channel

# 6. Configure cluster infrastructure (ODF, node scaling)
# HA clusters: installs full ODF (Ceph + NooBaa), scales MachineSets (takes 10-15 min)
# SNO clusters: installs MCG-only ODF (NooBaa S3 without Ceph)
make configure-cluster
# Skip ODF on HA clusters with existing storage: ./scripts/configure-cluster-infrastructure.sh --skip-odf

# 7. Update values files to point to YOUR fork
vi values-global.yaml
# Set: repoURL: "https://github.com/<your-github-user>/openshift-aiops-platform.git"

vi values-hub.yaml
# Set: repoURL: "https://github.com/<your-github-user>/openshift-aiops-platform.git"
#
# IMPORTANT: If step 5 showed topology "sno", also update values-hub.yaml:
#   cluster.topology: "sno"
#   storage.modelStorage.storageClass: "gp3-csi"

# 8. Get the Execution Environment
# Option A: Pull pre-built image (Recommended)
podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest \
  openshift-aiops-platform-ee:latest
# Option B: Build locally
# export ANSIBLE_HUB_TOKEN='your-token-here'
# podman login registry.redhat.io
# make build-ee

# 9. Validate cluster prerequisites
make check-prerequisites

# 10. Run Ansible prerequisites (creates secrets, RBAC, namespaces)
make operator-deploy-prereqs

# 11. Deploy the platform via Validated Patterns Operator
make operator-deploy

# 12. Wait for the ArgoCD Application to be created by the operator
oc wait --for=jsonpath='{.kind}'=Application \
  application/self-healing-platform -n self-healing-platform-hub --timeout=120s

# 13. Sync ArgoCD (if needed)
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite

# 14. Validate deployment
make argo-healthcheck

# 15. Run Tekton validation pipeline (validates coordination engine + model connectivity)
tkn pipeline start deployment-validation-pipeline --showlog
```

> **🖥️ SNO Deployment**: If step 5 (`make show-cluster-info`) shows topology `sno`, edit `values-hub.yaml` before step 11: set `cluster.topology: "sno"` and change `storage.modelStorage.storageClass` to `"gp3-csi"`. Object storage (NooBaa) is automatically provided by MCG-only ODF. See [SNO Deployment Guide](how-to/deploy-on-sno.md) for details.

---

### Option 3: Deploy with Local Gitea (Air-Gapped/Development)

For air-gapped environments or local development, you can deploy Gitea on your OpenShift cluster and fork the repository there. Set `gitea.enabled: true` in `values-hub.yaml` and create the `gitea-credentials-source` secret.

```bash
# Follow steps 1-6 from Option 2 above, then:

# 7. Deploy Gitea on OpenShift
make deploy-gitea
# This deploys Gitea operator and creates a Gitea instance

# 8. Get Gitea URL
GITEA_URL=$(oc get route gitea -n gitea -o jsonpath='{.spec.host}')
echo "Gitea URL: https://${GITEA_URL}"

# 9. Fork repository in Gitea
# - Log into Gitea UI (default: admin / see giteuserpass.md for password)
# - Create new repository or import from GitHub
# - Repository name: openshift-aiops-platform

# 10. Update values files to point to Gitea
vi values-global.yaml
# Set: repoURL: "https://gitea-with-admin-gitea.apps.<cluster-domain>/<username>/openshift-aiops-platform.git"

vi values-hub.yaml
# Set: repoURL: "https://gitea-with-admin-gitea.apps.<cluster-domain>/<username>/openshift-aiops-platform.git"
#
# IMPORTANT: If step 5 showed topology "sno", also update values-hub.yaml:
#   cluster.topology: "sno"
#   storage.modelStorage.storageClass: "gp3-csi"

# 11. Continue with steps 8-15 from Option 2 above
```

> **📖 More info**: See [Gitea Integration Guide](guides/GITEA-INTEGRATION-GUIDE.md) for detailed setup

---

## Post-Deployment

### Access Jupyter Notebooks

```bash
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
# Open http://localhost:8888
```

### Post-Deployment Cleanup (Optional)

```bash
# Clean up extra namespaces created by upstream Validated Patterns defaults
# These are safe to delete and don't affect your deployment
oc delete namespace self-healing-platform-example imperative --ignore-not-found=true
```

> **ℹ️ Note**: The `self-healing-platform-example` and `imperative` namespaces are created by the upstream `clustergroup:0.9.*` chart's default values. See [Issue #5 in the Junior Developer Guide](guides/JUNIOR-DEVELOPER-DEPLOYMENT-GUIDE.md#issue-5-extra-namespaces-created-upstream-behavior---expected) for details.

---

## Next Steps

- 📖 **[Tutorials](tutorials/index.md)** - Learn by doing with guided exercises
- 🔧 **[How-To Guides](how-to/index.md)** - Task-oriented guides for specific goals
- 📚 **[Reference](reference/index.md)** - Technical reference and API documentation
- 🎓 **[Explanation](explanation/index.md)** - Understand the architecture and design decisions
- 🤝 **[Contributing](../CONTRIBUTING.md)** - Join the community and contribute

**🎉 Done!** Your self-healing platform is now running.
