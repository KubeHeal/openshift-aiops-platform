# OpenShift AI Ops Self-Healing Platform

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![OpenShift](https://img.shields.io/badge/OpenShift-4.18+-red.svg)](https://www.openshift.com/)
[![Python](https://img.shields.io/badge/Python-3.11-blue.svg)](https://www.python.org/)
[![CI/CD Pipeline](https://github.com/KubeHeal/openshift-aiops-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/KubeHeal/openshift-aiops-platform/actions/workflows/ci.yml)
[![Helm Chart Validation](https://github.com/KubeHeal/openshift-aiops-platform/actions/workflows/helm-validation.yml/badge.svg)](https://github.com/KubeHeal/openshift-aiops-platform/actions/workflows/helm-validation.yml)

> **AI-powered self-healing platform for OpenShift clusters combining deterministic automation with machine learning for intelligent incident response.**

## 🎯 What is This?

The **OpenShift AI Ops Self-Healing Platform** is a production-ready AIOps solution that:

- 🤖 **Hybrid Approach**: Combines deterministic automation (Machine Config Operator, rule-based) with AI-driven analysis (ML models, anomaly detection)
- 🔧 **Self-Healing**: Automatically detects and remediates common cluster issues
- 📊 **ML-Powered**: Uses Isolation Forest, LSTM models for anomaly detection
- 🚀 **OpenShift Native**: Built on Red Hat OpenShift AI, KServe, Tekton, ArgoCD
- 💬 **Natural Language Interface**: Integrates with OpenShift Lightspeed via MCP (Model Context Protocol)
- 🌐 **Platform Agnostic**: Supports both **vanilla Kubernetes** and **OpenShift** clusters

## 🧠 Deploying Your Own ML Models

This platform follows a **user-deployed model architecture**:

- **✅ You train and deploy** your own ML models via KServe InferenceServices
- **✅ Platform provides** coordination engine, infrastructure, and integration
- **✅ Works on both** vanilla Kubernetes (with KServe) and OpenShift (with OpenShift AI)
- **✅ Full control** over model versions, updates, and lifecycle

See the **[User Model Deployment Guide](docs/guides/USER-MODEL-DEPLOYMENT-GUIDE.md)** for complete instructions on deploying models to both vanilla Kubernetes and OpenShift.

## 📚 Documentation

| Document | Description |
|----------|-------------|
| **[AGENTS.md](AGENTS.md)** | 🤖 **AI Agent Development Guide** (comprehensive reference) |
| **[docs/adrs/](docs/adrs/)** | 🏛️ Architectural Decision Records (29+ ADRs) |
| **[DEPLOYMENT.md](DEPLOYMENT.md)** | 🚀 Step-by-step deployment guide |
| **[docs/guides/USER-MODEL-DEPLOYMENT-GUIDE.md](docs/guides/USER-MODEL-DEPLOYMENT-GUIDE.md)** | 🧠 **User Model Deployment Guide** (deploy your own ML models via KServe) |
| **[docs/guides/TROUBLESHOOTING-GUIDE.md](docs/guides/TROUBLESHOOTING-GUIDE.md)** | 🔧 **Troubleshooting Guide** (common issues and solutions) |
| **[docs/guides/JUNIOR-DEVELOPER-DEPLOYMENT-GUIDE.md](docs/guides/JUNIOR-DEVELOPER-DEPLOYMENT-GUIDE.md)** | 👨‍💻 **Junior Developer Guide** (deployment testing walkthrough) |
| **[notebooks/README.md](notebooks/README.md)** | 📓 Jupyter notebook workflows |

## 🚀 Quick Start (5 Minutes)

### Supported Cluster Topologies

This platform supports both standard HighlyAvailable and Single Node OpenShift (SNO) deployments:

| Topology | Nodes | Storage | ODF | Use Case |
|----------|-------|---------|-----|----------|
| **Standard HighlyAvailable** | 3+ (separate control-plane/worker) | ODF + CSI | ✅ Yes | Production, full features |
| **SNO SingleReplica** | 1 (all roles on single node) | CSI only | ❌ No | Edge, development, testing |

**Supported OpenShift Versions:**
- OpenShift 4.18, 4.19, 4.20
- Auto-detected during deployment
- Version-specific operator overlays

**Auto-Detection:**

The platform automatically detects your cluster topology and version. After installing prerequisites and logging into your cluster (see Installation steps below), verify with `make show-cluster-info`.

📖 **See also:** [SNO Deployment Guide](docs/how-to/deploy-on-sno.md)

### Prerequisites

**Standard Cluster Requirements:**
- OpenShift 4.18+ cluster (admin access)
- 6+ nodes (3 control-plane, 3+ workers, 1 GPU-enabled recommended)
- 24+ CPU cores, 96+ GB RAM, 500+ GB storage

**SNO Cluster Requirements:**
- OpenShift 4.18+ cluster (admin access)
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

### RHEL 9/10 Workstation Setup (One-Time)

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

### Installation

#### Option 1: Fork and Deploy (Recommended for Development)

**⚠️ IMPORTANT**: Always fork the repository first before deploying. This allows you to customize values files and maintain your own deployment configuration.

```bash
# 1. Fork the repository on GitHub
# Click "Fork" at https://github.com/KubeHeal/openshift-aiops-platform

# 2. Clone YOUR fork
git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
cd openshift-aiops-platform

# 3. Install workstation prerequisites (RHEL 9/10 only - skip if tools already installed)
./scripts/install-prerequisites-rhel.sh
source ~/.bashrc

# 4. Log into your OpenShift cluster
oc login <cluster-api-url>

# 5. Verify cluster topology and version
make show-cluster-info
# Output shows: Topology (standard or sno), OpenShift Version, Platform, ODF Channel

# 6. Configure cluster infrastructure (ODF, node scaling)
# Standard clusters: installs ODF, scales MachineSets (takes 10-15 min)
# SNO clusters: validates CSI storage classes, skips ODF
make configure-cluster
# Skip ODF on standard clusters with existing storage: ./scripts/configure-cluster-infrastructure.sh --skip-odf

# 7. Configure values files
# Edit values-global.yaml - Update git.repoURL to YOUR repository:
vi values-global.yaml
# Change: repoURL: "https://gitea-with-admin-gitea.apps.cluster-pvbs6..."
# To:     repoURL: "https://github.com/YOUR-USERNAME/openshift-aiops-platform.git"

# Edit values-hub.yaml - Update repoURL to YOUR repository:
vi values-hub.yaml
# Change: repoURL: "https://gitea-with-admin-gitea.apps.cluster-pvbs6..."
# To:     repoURL: "https://github.com/YOUR-USERNAME/openshift-aiops-platform.git"
#
# IMPORTANT: If step 5 showed topology "sno", also update values-hub.yaml:
#   cluster.topology: "sno"
#   storage.modelStorage.storageClass: "gp3-csi"
#   objectStore.enabled: false

# 8. Get the Execution Environment
#
# Option A: Pull pre-built image (Recommended)
podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest \
  openshift-aiops-platform-ee:latest
#
# Option B: Build locally (requires ANSIBLE_HUB_TOKEN)
# export ANSIBLE_HUB_TOKEN='your-token-here'
# podman login registry.redhat.io
# make token
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
# A manual sync or refresh may be required for the self-healing-platform-hub ArgoCD project
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite

# 14. Validate deployment
make argo-healthcheck

# 15. Run Tekton validation pipeline (validates coordination engine + model connectivity)
tkn pipeline start deployment-validation-pipeline --showlog
```

> **💡 Note**: Step 11 (`make operator-deploy`) automatically runs step 10 (`operator-deploy-prereqs`) as a dependency. However, running them separately helps with troubleshooting and understanding the deployment flow.

> **⚠️ Critical**: If you skip step 7 (updating repoURL in values files), ArgoCD will try to sync from the example Gitea URL which won't exist on your cluster, causing deployment failures. Always update both `values-global.yaml` and `values-hub.yaml` to point to YOUR fork's repository URL.

> **🖥️ SNO Deployment**: If step 5 (`make show-cluster-info`) shows topology `sno`, edit `values-hub.yaml` before step 11: set `cluster.topology: "sno"`, change `storage.modelStorage.storageClass` to `"gp3-csi"`, and set `objectStore.enabled: false`. See [SNO Deployment Guide](docs/how-to/deploy-on-sno.md) for details.

#### Option 2: Deploy with Local Gitea (Air-Gapped/Development)

For air-gapped environments or local development, you can deploy Gitea on your OpenShift cluster and fork the repository there:

```bash
# 1. Clone the repository
git clone https://github.com/KubeHeal/openshift-aiops-platform.git
cd openshift-aiops-platform

# 2. Install workstation prerequisites (RHEL 9/10 only - skip if tools already installed)
./scripts/install-prerequisites-rhel.sh
source ~/.bashrc

# 3. Log into your OpenShift cluster
oc login <cluster-api-url>

# 4. Verify cluster topology and version
make show-cluster-info
# Output shows: Topology (standard or sno), OpenShift Version, Platform, ODF Channel

# 5. Configure cluster infrastructure (ODF, node scaling)
# Standard clusters: installs ODF, scales MachineSets (takes 10-15 min)
# SNO clusters: validates CSI storage classes, skips ODF
make configure-cluster
# Skip ODF on standard clusters with existing storage: ./scripts/configure-cluster-infrastructure.sh --skip-odf

# 6. Deploy Gitea on OpenShift
make deploy-gitea
# This deploys Gitea operator and creates a Gitea instance

# 7. Get Gitea URL
GITEA_URL=$(oc get route gitea -n gitea -o jsonpath='{.spec.host}')
echo "Gitea URL: https://${GITEA_URL}"

# 8. Fork repository in Gitea
# - Log into Gitea UI (default: admin / see giteuserpass.md for password)
# - Create new repository or import from GitHub
# - Repository name: openshift-aiops-platform

# 9. Update values files to point to Gitea
vi values-global.yaml
# Set: repoURL: "https://gitea-with-admin-gitea.apps.<cluster-domain>/<username>/openshift-aiops-platform.git"

vi values-hub.yaml
# Set: repoURL: "https://gitea-with-admin-gitea.apps.<cluster-domain>/<username>/openshift-aiops-platform.git"
#
# IMPORTANT: If step 4 showed topology "sno", also update values-hub.yaml:
#   cluster.topology: "sno"
#   storage.modelStorage.storageClass: "gp3-csi"
#   objectStore.enabled: false

# 10. Get the Execution Environment
# Option A: Pull pre-built image (Recommended)
podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest \
  openshift-aiops-platform-ee:latest
# Option B: Build locally
# export ANSIBLE_HUB_TOKEN='your-token-here'
# podman login registry.redhat.io
# make build-ee

# 11. Validate cluster prerequisites
make check-prerequisites

# 12. Run Ansible prerequisites (creates secrets, RBAC, namespaces)
make operator-deploy-prereqs

# 13. Deploy the platform via Validated Patterns Operator
make operator-deploy

# 14. Wait for the ArgoCD Application to be created by the operator
oc wait --for=jsonpath='{.kind}'=Application \
  application/self-healing-platform -n self-healing-platform-hub --timeout=120s

# 15. Sync ArgoCD (if needed)
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite

# 16. Validate deployment
make argo-healthcheck

# 17. Run Tekton validation pipeline (validates coordination engine + model connectivity)
tkn pipeline start deployment-validation-pipeline --showlog
```

> **📖 More info**: See [Gitea Integration Guide](docs/GITEA-INTEGRATION-GUIDE.md) for detailed setup

> **🖥️ SNO Deployment**: If step 4 (`make show-cluster-info`) shows topology `sno`, edit `values-hub.yaml` before step 13: set `cluster.topology: "sno"`, change `storage.modelStorage.storageClass` to `"gp3-csi"`, and set `objectStore.enabled: false`. See [SNO Deployment Guide](docs/how-to/deploy-on-sno.md) for details.

**🎉 Done!** Your self-healing platform is now running.

**Access Jupyter notebooks:**
```bash
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
# Open http://localhost:8888
```

**Post-Deployment Cleanup (Optional):**
```bash
# Clean up extra namespaces created by upstream Validated Patterns defaults
# These are safe to delete and don't affect your deployment
oc delete namespace self-healing-platform-example imperative --ignore-not-found=true
```

> **ℹ️ Note**: The `self-healing-platform-example` and `imperative` namespaces are created by the upstream `clustergroup:0.9.*` chart's default values. See [Issue #5 in the Junior Developer Guide](docs/guides/JUNIOR-DEVELOPER-DEPLOYMENT-GUIDE.md#issue-5-extra-namespaces-created-upstream-behavior---expected) for details.

## 🛠️ Development Setup

### For Contributors

```bash
# 1. Fork and clone
git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
cd openshift-aiops-platform

# 2. Get the Execution Environment
#
# Option A: Pull pre-built image (Recommended)
podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest \
  openshift-aiops-platform-ee:latest
#
# Option B: Build locally (requires ANSIBLE_HUB_TOKEN)
# export ANSIBLE_HUB_TOKEN='your-token'
# make token
# make build-ee

# 3. Test execution environment
make test-ee

# 4. Run linting
make super-linter   # Or use pre-commit hooks

# 5. Install pre-commit hooks (optional but recommended)
pip install pre-commit
pre-commit install
```

### Testing

```bash
# Notebook validation
cd notebooks
jupyter nbconvert --to notebook --execute 00-setup/00-platform-readiness-validation.ipynb

# End-to-end deployment test
make test-deploy-complete-pattern

# Validate operators and services
make validate-deployment
```

### Development Workflow

1. **Read the Docs**: Start with [AGENTS.md](AGENTS.md) and [ADRs](docs/adrs/)
2. **Create Feature Branch**: `git checkout -b feature/your-feature-name`
3. **Make Changes**: Follow coding standards (YAML 2-space indent, yamllint compliant)
4. **Test Locally**: `make test-ee` (pull or build the EE first; see [DEPLOYMENT.md](DEPLOYMENT.md))
5. **Commit**: Use conventional commits (`feat:`, `fix:`, `docs:`, `chore:`)
6. **Push & PR**: Push to your fork, open pull request with description

## 📁 Project Structure

```
openshift-aiops-platform/
├── ansible/                    # Ansible roles and playbooks
│   ├── roles/                  # 8 production-ready reusable roles
│   └── playbooks/              # Deployment, validation, cleanup
├── charts/                     # Helm charts
│   └── hub/                    # Main pattern chart
├── docs/                       # Documentation
│   ├── adrs/                   # Architectural Decision Records
│   ├── guides/                 # How-to guides
│   └── tutorials/              # Learning-oriented guides
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
├── Makefile                    # Main build/deploy/test targets
├── AGENTS.md                   # 🤖 AI agent development guide
└── README.md                   # This file
```

## 🏗️ Architecture

### Hybrid Self-Healing Approach

```
┌─────────────────────────────────────────────────────────────┐
│                 Self-Healing Platform                        │
├─────────────────────────────────────────────────────────────┤
│  Coordination Engine (Python Flask API)                     │
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

**Key Components:**
- **Red Hat OpenShift AI 2.22.2**: ML platform for model training and serving
- **KServe 1.36.1**: Model serving infrastructure
- **Coordination Engine**: Orchestrates hybrid approach (Python/Flask)
- **Jupyter Notebooks**: Development environment for ML workflows
- **Tekton Pipelines**: CI/CD automation and validation
- **OpenShift GitOps (ArgoCD)**: GitOps deployment
- **MCP Server**: Model Context Protocol for OpenShift Lightspeed integration

**📖 Architecture Details**: [ADR-002: Hybrid Deterministic-AI Self-Healing Approach](docs/adrs/002-hybrid-self-healing-approach.md)

## 🤝 Contributing

We welcome contributions! Here's how you can help:

### Ways to Contribute

1. 🐛 **Report Bugs**: [Open an issue](https://github.com/KubeHeal/openshift-aiops-platform/issues/new)
2. 💡 **Suggest Features**: [Feature request](https://github.com/KubeHeal/openshift-aiops-platform/issues/new)
3. 📝 **Improve Docs**: Fix typos, add examples, clarify instructions
4. 🧪 **Add Tests**: Expand test coverage for notebooks and models
5. 🚀 **Submit PRs**: Fix bugs, add features, improve performance

### Contribution Guidelines

**Before Submitting a PR:**

1. ✅ **Read [AGENTS.md](AGENTS.md)**: Understand project architecture and conventions
2. ✅ **Check existing ADRs**: Review [docs/adrs/](docs/adrs/) for architectural decisions
3. ✅ **Run tests**: `make test-ee` (pull or build the EE first; see [DEPLOYMENT.md](DEPLOYMENT.md))
4. ✅ **Lint your code**: `make super-linter` or use pre-commit hooks
5. ✅ **Update docs**: If changing behavior, update relevant docs and ADRs
6. ✅ **Sign commits**: `git commit -s` (DCO required)

**PR Title Format:**
```
<type>(<scope>): <description>

Examples:
feat(notebooks): add LSTM autoencoder anomaly detection
fix(kserve): resolve model loading race condition
docs(adr): add ADR-038 for deployment validation strategy
chore(ci): update GitHub Actions to v4
```

**PR Description Template:**
```markdown
## Description
Brief description of changes

## Motivation
Why is this change needed?

## Related Issues
Closes #123

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manually tested in dev environment

## ADR Updates
- [ ] Created/updated relevant ADRs
- [ ] Updated docs/adrs/README.md

## Checklist
- [ ] Code follows project style guidelines
- [ ] Docs updated (if behavior changes)
- [ ] Tests added/updated
- [ ] All CI checks pass
```

### Good First Issues

Looking for a place to start? Check out issues tagged with:
- [`good first issue`](https://github.com/KubeHeal/openshift-aiops-platform/labels/good%20first%20issue)
- [`documentation`](https://github.com/KubeHeal/openshift-aiops-platform/labels/documentation)
- [`help wanted`](https://github.com/KubeHeal/openshift-aiops-platform/labels/help%20wanted)

### Code of Conduct

Be respectful, inclusive, and professional. We follow the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

## 🧪 Testing

### CI/CD Pipeline

We use GitHub Actions for continuous integration:

- **Helm Chart Validation**: Lints and validates all Helm charts
- **CI/CD Pipeline**: Python tests, notebook validation, security scans
- **Pre-commit Hooks**: YAML linting, trailing whitespace, secrets detection

### Running Tests Locally

```bash
# Pre-commit checks (runs all linters)
pre-commit run --all-files

# Notebook validation (executes notebooks)
cd notebooks
jupyter nbconvert --to notebook --execute \
  00-setup/00-platform-readiness-validation.ipynb

# End-to-end deployment test
make test-deploy-complete-pattern

# Tekton pipeline validation (post-deployment)
tkn pipeline start deployment-validation-pipeline --showlog
```

## 🔧 Troubleshooting

### Common Issues

**Issue: Operators failing with "TooManyOperatorGroups"**

```bash
# Check for multiple OperatorGroups
oc get operatorgroups -n openshift-operators

# Fix: Delete extra OperatorGroups (keep only global-operators)
oc delete operatorgroup <extra-operatorgroup-name> -n openshift-operators
```

**Issue: GPU not available in notebooks**

```bash
# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Verify GPU operator
oc get csv -n openshift-operators | grep gpu-operator

# Check notebook GPU allocation
oc describe notebook self-healing-workbench -n self-healing-platform
```

**Issue: Coordination engine not responding**

```bash
# Check pod status (Go-based coordination engine from external repo)
oc get pods -n self-healing-platform -l app.kubernetes.io/component=coordination-engine

# View logs
oc logs -n self-healing-platform -l app.kubernetes.io/component=coordination-engine --tail=100

# Test health endpoint
curl http://coordination-engine.self-healing-platform.svc.cluster.local:8080/health

# Note: Coordination engine is from https://github.com/KubeHeal/openshift-coordination-engine
```

**📖 Complete Troubleshooting Guide**: See [docs/guides/TROUBLESHOOTING-GUIDE.md](docs/guides/TROUBLESHOOTING-GUIDE.md) for comprehensive issue resolution

**Additional Resources**:
- [Junior Developer Deployment Guide](docs/guides/JUNIOR-DEVELOPER-DEPLOYMENT-GUIDE.md) - Step-by-step testing walkthrough
- [AGENTS.md § Common Pitfalls](AGENTS.md#common-pitfalls) - Development-specific issues

## 📊 Project Status

### Current Release

- **Version**: 1.0.0
- **OpenShift**: 4.18.21+
- **Red Hat OpenShift AI**: 2.22.2
- **Status**: Production-ready

### Features

- ✅ Hybrid deterministic-AI self-healing
- ✅ Jupyter notebook-based ML workflows
- ✅ Isolation Forest anomaly detection
- ✅ LSTM time-series anomaly detection
- ✅ KServe model serving
- ✅ Coordination engine with conflict resolution
- ✅ Tekton CI/CD pipelines (26 validation checks)
- ✅ GitOps deployment via ArgoCD
- ✅ External Secrets Operator integration
- ✅ OpenShift Lightspeed MCP integration
- 🚧 Multi-cluster support (in progress)
- 🚧 Advanced root cause analysis (planned)

### Roadmap

See [GitHub Projects](https://github.com/KubeHeal/openshift-aiops-platform/projects) for upcoming features and milestones.

## 📜 License

This project is licensed under the **GNU General Public License v3.0** - see the [LICENSE](LICENSE) file for details.

**What this means:**
- ✅ You can use, modify, and distribute this software
- ✅ You can use it for commercial purposes
- ⚠️ Modifications must also be licensed under GPL v3.0
- ⚠️ You must disclose source code of modified versions

## 🙏 Acknowledgments

### Built With

- [Red Hat OpenShift](https://www.openshift.com/)
- [Red Hat OpenShift AI](https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai)
- [Validated Patterns Framework](https://validatedpatterns.io/)
- [KServe](https://kserve.github.io/)
- [Kubeflow](https://www.kubeflow.org/)
- [Tekton](https://tekton.dev/)
- [ArgoCD](https://argo-cd.readthedocs.io/)

### References

- [ADR-001: OpenShift 4.18+ as Foundation Platform](docs/adrs/001-openshift-platform-selection.md)
- [ADR-002: Hybrid Deterministic-AI Self-Healing Approach](docs/adrs/002-hybrid-self-healing-approach.md)
- [ADR-003: Red Hat OpenShift AI for ML Platform](docs/adrs/003-openshift-ai-ml-platform.md)
- [ADR-019: Validated Patterns Framework Adoption](docs/adrs/019-validated-patterns-framework-adoption.md)

## 📞 Support & Community

### Getting Help

- 📖 **Documentation**: [docs/](docs/)
- 🐛 **Issues**: [GitHub Issues](https://github.com/KubeHeal/openshift-aiops-platform/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/KubeHeal/openshift-aiops-platform/discussions)

### Maintainers

- **Tosin Akinosho** ([@tosin2013](https://github.com/tosin2013)) - Project Lead

### Contributors

Thanks to all contributors who have helped improve this project!

<!-- ALL-CONTRIBUTORS-LIST:START -->
<!-- ALL-CONTRIBUTORS-LIST:END -->

---

**Made with ❤️ by the OpenShift AI Ops community**

**⭐ Star this repo** if you find it useful!

**🔗 Share** with your team and colleagues!
