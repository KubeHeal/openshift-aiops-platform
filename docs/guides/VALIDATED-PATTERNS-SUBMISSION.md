# Validated Patterns Upstream Submission Guide

**Last Updated**: 2026-05-18

This guide walks you through preparing and submitting the OpenShift AIOps Self-Healing Platform to the upstream Validated Patterns repository at https://github.com/validatedpatterns/patterns.

---

## Table of Contents

1. [Prerequisites for Submission](#prerequisites-for-submission)
2. [Pattern Metadata Validation](#pattern-metadata-validation)
3. [Required Files Checklist](#required-files-checklist)
4. [Framework Compliance](#framework-compliance)
5. [Documentation Requirements](#documentation-requirements)
6. [Testing Checklist](#testing-checklist)
7. [Submission Process](#submission-process)
8. [Upstream Maintenance](#upstream-maintenance)

---

## Prerequisites for Submission

Before submitting to https://github.com/validatedpatterns/patterns:

- ✅ **Fresh cluster testing**: Pattern deploys successfully on clean SNO and HA clusters
- ✅ **Documentation complete**: Deployment guide, architecture docs, troubleshooting
- ✅ **No hard-coded secrets**: All secrets use External Secrets Operator or placeholders
- ✅ **Helm chart validated**: `helm lint` passes without errors
- ✅ **ADRs documented**: Architectural decisions recorded and linked
- ✅ **GitHub Pages live**: Documentation published at https://kubeheal.github.io/openshift-aiops-platform/

---

## Pattern Metadata Validation

**File**: `pattern-metadata.yaml`

### Required Fields

```yaml
tier: sandbox  # Start with sandbox for initial submission
supportedPlatforms:
  - AWS
  - Azure
  - GCP
  - BareMetal
supportedTopologies:
  - SNO  # Single Node OpenShift
  - HA   # HighlyAvailable (3+ nodes)
minOpenShiftVersion: "4.18"
maxOpenShiftVersion: "4.20"  # Update as tested
resourceRequirements:
  sno:
    cpu: "8"      # Minimum 8 cores
    memory: "32Gi" # Minimum 32 GB RAM
    storage: "120Gi"
  ha:
    cpu: "24"      # Minimum 24 cores
    memory: "96Gi" # Minimum 96 GB RAM
    storage: "500Gi"
```

### Validation Checklist

- [ ] `tier: sandbox` for initial submission (graduates to `tested`/`maintained` later)
- [ ] `supportedPlatforms` includes all tested cloud providers
- [ ] `supportedTopologies` lists SNO and/or HA based on testing
- [ ] `minOpenShiftVersion` matches lowest tested version
- [ ] `resourceRequirements` accurately reflects cluster sizing
- [ ] `description` explains pattern purpose and use case
- [ ] `maintainers` lists contact information

---

## Required Files Checklist

### Core Files

- [ ] `pattern-metadata.yaml` - Pattern metadata and requirements
- [ ] `values-hub.yaml.example` - Example hub values (no secrets)
- [ ] `values-global.yaml.example` - Example global values (no secrets)
- [ ] `README.md` - Quick start guide with deployment steps
- [ ] `CONTRIBUTING.md` - Contributor guidelines with DCO requirements
- [ ] `CODE_OF_CONDUCT.md` - Community code of conduct
- [ ] `CHANGELOG.md` - Release history and versioning
- [ ] `LICENSE` - GPL v3 license (or compatible)

### Deployment Files

- [ ] `charts/hub/Chart.yaml` - Helm chart metadata
- [ ] `charts/hub/values.yaml` - Default Helm values
- [ ] `charts/hub/templates/` - Kubernetes resource templates
- [ ] `ansible/playbooks/operator_deploy_prereqs.yml` - Prerequisites playbook
- [ ] `ansible/roles/` - Reusable Ansible roles
- [ ] `Makefile` - Standard deployment targets
- [ ] `Makefile-common` - Common pattern framework targets

### Documentation Files

- [ ] `docs/` - Documentation following Diataxis structure
  - [ ] `docs/tutorials/` - Learning-oriented content
  - [ ] `docs/how-to/` - Problem-solving guides
  - [ ] `docs/reference/` - Information-oriented content
  - [ ] `docs/explanation/` - Understanding-oriented content
- [ ] `docs/adrs/` - Architectural Decision Records
- [ ] `docs/guides/TROUBLESHOOTING-GUIDE.md` - Troubleshooting guide
- [ ] `docs/guides/FRESH-CLUSTER-DEPLOYMENT.md` - Fresh cluster deployment

### CI/CD Files

- [ ] `.github/workflows/` - GitHub Actions workflows
  - [ ] `ci.yml` - Continuous integration
  - [ ] `deploy-docs.yml` - Documentation deployment
  - [ ] `validate-docs.yml` - Documentation validation
- [ ] `.github/ISSUE_TEMPLATE/` - Issue templates
- [ ] `.github/pull_request_template.md` - PR template

---

## Framework Compliance

### Validated Patterns Framework Requirements

#### Makefile Targets

Ensure these standard targets exist:

```bash
# Display cluster information
make show-cluster-info

# Validate prerequisites
make check-prerequisites

# Deploy infrastructure (ODF, storage)
make configure-cluster

# Deploy pattern
make operator-deploy

# Validate deployment
make argo-healthcheck

# Cleanup
make uninstall
```

#### Pattern CR

**File**: `deploy_pattern_cr.yml`

```yaml
apiVersion: gitops.hybrid-cloud-patterns.io/v1alpha1
kind: Pattern
metadata:
  name: self-healing-platform
  namespace: openshift-operators
spec:
  clusterGroupName: hub
  gitSpec:
    targetRepo: https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
    targetRevision: main
```

#### ArgoCD Applications

- [ ] Applications deploy via Pattern CR
- [ ] ArgoCD application created automatically
- [ ] Sync waves configured for ordered deployment
- [ ] Health checks implemented
- [ ] `ignoreDifferences` configured for managed fields

#### Secrets Management

- [ ] No hard-coded secrets in any values files
- [ ] External Secrets Operator used for secret management
- [ ] Example values use placeholders (e.g., `<INSERT_TOKEN_HERE>`)
- [ ] Secret backend documented (Vault, AWS Secrets Manager, Kubernetes)

---

## Documentation Requirements

### Minimum Documentation

- [ ] **Deployment guide** (SNO + HA) with step-by-step instructions
- [ ] **Architecture documentation** with diagrams and ADRs
- [ ] **Prerequisites** list (tools, access, tokens, cluster requirements)
- [ ] **Troubleshooting guide** with common issues and solutions
- [ ] **Known limitations** documented (e.g., GPU requirements, ODF dependencies)
- [ ] **Contributing guidelines** with DCO and PR process

### Recommended Documentation

- [ ] **GitHub Pages site** with Diataxis structure
- [ ] **API documentation** for custom resources and APIs
- [ ] **Video walkthrough** or demo (YouTube link)
- [ ] **Screenshots** showing deployed platform
- [ ] **Blog post** explaining pattern use case and architecture

---

## Testing Checklist

Test the pattern on **fresh clusters** (no pre-existing operators or configuration):

### SNO Testing

Test on:
- [ ] SNO cluster on AWS (t3.2xlarge or larger)
- [ ] SNO cluster on Azure (Standard_D8s_v3 or larger)
- [ ] SNO cluster on GCP (n2-standard-8 or larger)

**Validation**:
- [ ] `make configure-cluster` completes (MCG-only ODF)
- [ ] `make operator-deploy` completes
- [ ] All ArgoCD applications Healthy
- [ ] Workbench pods Running (without GPU)
- [ ] Model training pipelines succeed
- [ ] InferenceServices Ready

### HA Testing

Test on:
- [ ] HA cluster on AWS (3+ m5.2xlarge or larger)
- [ ] HA cluster on Azure (3+ Standard_D8s_v3 or larger)
- [ ] HA cluster on GCP (3+ n2-standard-8 or larger)

**Validation**:
- [ ] `make configure-cluster` completes (full ODF with Ceph)
- [ ] `make operator-deploy` completes
- [ ] All ArgoCD applications Healthy
- [ ] Workbench pods Running (with GPU if enabled)
- [ ] Model training pipelines succeed
- [ ] InferenceServices Ready

### OpenShift Version Testing

Test on all supported OpenShift versions:
- [ ] OpenShift 4.18
- [ ] OpenShift 4.19
- [ ] OpenShift 4.20

---

## Submission Process

### Step 1: Pre-Submission Validation

Run the validation script:

```bash
./scripts/validate-pattern-submission.sh
```

Expected output:

```
✅ All required files present
✅ Pattern submission validation complete

Next steps:
1. Test deployment on fresh SNO and HA clusters
2. Review docs/guides/VALIDATED-PATTERNS-SUBMISSION.md
3. Fork https://github.com/validatedpatterns/patterns
4. Create PR with your pattern
```

### Step 2: Fork Validated Patterns Repository

1. Go to https://github.com/validatedpatterns/patterns
2. Click **Fork** in the top-right corner
3. Create fork under your account

### Step 3: Create Pattern Directory

```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/patterns.git
cd patterns

# Create pattern directory
mkdir -p patterns/openshift-aiops-platform

# Copy files from this repository
rsync -av --exclude='.git' \
  /path/to/openshift-aiops-platform/ \
  patterns/openshift-aiops-platform/
```

### Step 4: Update Pattern Index

**File**: `patterns/README.md`

Add entry to pattern index:

```markdown
## Sandbox Patterns

- [OpenShift AIOps Self-Healing Platform](openshift-aiops-platform/README.md) - Production-ready AIOps platform with ML-powered anomaly detection and self-healing automation
```

### Step 5: Create Pull Request

Create PR with:

**Title**: `[New Pattern] OpenShift AIOps Self-Healing Platform`

**Description**:

```markdown
## Pattern Description

The OpenShift AIOps Self-Healing Platform is a production-ready AIOps solution that combines deterministic automation with AI-driven analysis for automated anomaly detection and self-healing in OpenShift clusters.

## Key Features

- 🤖 Hybrid approach: Deterministic automation + AI-driven analysis
- 📊 ML-powered anomaly detection (Isolation Forest, LSTM models)
- 🔧 Self-healing automation with conflict resolution
- 🚀 OpenShift native (Red Hat OpenShift AI, KServe, Tekton, ArgoCD)
- 💬 Natural language interface via MCP (Model Context Protocol)
- 🌐 Platform agnostic (Kubernetes + OpenShift)

## Tested Environments

- ✅ OpenShift 4.18, 4.19, 4.20
- ✅ SNO clusters (AWS, Azure, GCP)
- ✅ HA clusters (AWS, Azure, GCP)
- ✅ With and without GPU acceleration

## Documentation

- **GitHub Pages**: https://kubeheal.github.io/openshift-aiops-platform/
- **Deployment Guide**: [docs/guides/FRESH-CLUSTER-DEPLOYMENT.md](openshift-aiops-platform/docs/guides/FRESH-CLUSTER-DEPLOYMENT.md)
- **Architecture**: [docs/adrs/](openshift-aiops-platform/docs/adrs/) (59 ADRs)
- **Troubleshooting**: [docs/guides/TROUBLESHOOTING-GUIDE.md](openshift-aiops-platform/docs/guides/TROUBLESHOOTING-GUIDE.md)

## Screenshots

![Workbench Notebooks](screenshots/workbench.png)
![Model Training Pipeline](screenshots/pipelines.png)
![InferenceServices](screenshots/kserve.png)

## Demo

📹 [Video Walkthrough](https://youtube.com/link-to-demo)

## Contact

- **Maintainers**: KubeHeal Team
- **Repository**: https://github.com/KubeHeal/openshift-aiops-platform
- **Issues**: https://github.com/KubeHeal/openshift-aiops-platform/issues
```

### Step 6: Respond to Review Feedback

Validated Patterns team will review:
- [ ] Pattern metadata completeness
- [ ] Framework compliance (Makefile targets, Pattern CR)
- [ ] Documentation quality
- [ ] Testing coverage
- [ ] Security (no hard-coded secrets)

**Be prepared to**:
- Answer questions about architecture decisions
- Provide additional test results
- Fix any compliance issues
- Update documentation based on feedback

### Step 7: Iterate Until Approved

- Monitor PR comments
- Address feedback promptly
- Update pattern based on review
- Request re-review when ready

---

## Upstream Maintenance

### After Acceptance

Once your pattern is accepted into the Validated Patterns repository:

#### Monitor Issues

- Watch validated-patterns repository for issues
- Respond to user questions about your pattern
- Triage bug reports and feature requests

#### Update for New OpenShift Versions

- Test pattern on new OpenShift releases (quarterly)
- Update `maxOpenShiftVersion` in pattern-metadata.yaml
- Document any compatibility issues or required changes

#### Address Community Feedback

- Review user-reported issues
- Incorporate community improvements
- Share learnings with upstream community

#### Contribute Improvements Back Upstream

- Submit PRs to `common/` framework for general improvements
- Share reusable Ansible roles and Helm charts
- Contribute to pattern best practices documentation

### Graduation Path

**Sandbox → Tested → Maintained**

- **Sandbox**: Initial submission, actively tested by community
- **Tested**: Proven in production by multiple users, documented use cases
- **Maintained**: Actively maintained, regular updates, enterprise support

**To graduate from Sandbox to Tested**:
- [ ] Deployed in 3+ production environments
- [ ] Documented use cases and success stories
- [ ] Active community engagement (issues, PRs, documentation)
- [ ] Regular updates for new OpenShift versions
- [ ] Enterprise support available (optional)

---

## Validation Script

Use the provided script to validate submission readiness:

```bash
./scripts/validate-pattern-submission.sh
```

**What it checks**:
- ✅ All required files present
- ✅ No secrets in example values files
- ✅ `pattern-metadata.yaml` structure valid
- ✅ Helm chart lints successfully
- ⚠️ Warnings for potential issues

---

## Additional Resources

- **Validated Patterns Documentation**: https://validatedpatterns.io
- **Framework Repository**: https://github.com/validatedpatterns/common
- **Pattern Examples**: https://github.com/validatedpatterns/patterns
- **Community Slack**: https://hybridcloudpatterns.slack.com

---

## FAQ

### Q: Can I submit a pattern that requires GPU?

**A**: Yes, but document GPU as optional for broader adoption. Support both GPU and non-GPU deployments.

### Q: What tier should I use for initial submission?

**A**: Start with `tier: sandbox`. Graduate to `tested` after community validation.

### Q: How long does the review process take?

**A**: Typically 1-2 weeks, depending on PR complexity and reviewer availability.

### Q: Can I update the pattern after submission?

**A**: Yes! Submit PRs to update your pattern in the validated-patterns repository.

### Q: What if my pattern fails validation?

**A**: Address the feedback and re-submit. The validation script helps catch issues early.

---

**Next Steps**:

1. Run `./scripts/validate-pattern-submission.sh`
2. Test on fresh SNO and HA clusters
3. Fork https://github.com/validatedpatterns/patterns
4. Create PR with your pattern
5. Engage with community feedback

Good luck with your submission! 🚀
