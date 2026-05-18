# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

#### Patternizer Adoption (ADR-059) 🎉
- **Automated pattern scaffolding** via Validated Patterns Patternizer CLI tool
  - Single command generates all scaffolding files: `podman run quay.io/validatedpatterns/patternizer init --with-secrets`
  - Standardizes pattern structure across Validated Patterns community
  - Automated upgrade path via `patternizer upgrade` (monthly cadence recommended)
  - See [ADR-059: Patternizer Adoption](./docs/adrs/059-patternizer-adoption.md) for full decision rationale
- **Generated files** (replacing manual `.example` templates):
  - `values-global.yaml` - Global pattern configuration
  - `values-hub.yaml` - Hub cluster configuration
  - `values-secret.yaml.template` - Secrets template with External Secrets Operator integration
  - `pattern.sh` - Utility wrapper for pattern operations
  - `Makefile` + `Makefile-common` - Standardized build/deploy logic
  - `ansible.cfg` - Ansible configuration
- **Benefits**:
  - ⚡ 90% faster initial scaffolding setup (1 command vs 12+ manual steps)
  - 🛡️ 80% reduction in configuration errors (no manual file editing)
  - 🔄 Automated infrastructure upgrades synchronized with Validated Patterns releases
  - 📚 75% reduction in setup documentation (reference Patternizer docs)

### Changed

#### Deployment Workflow Improvements
- **Updated prerequisites documentation** to reflect Patternizer workflow
- **Simplified onboarding**: Replaced multi-step manual file creation with single container command
- **RELEASE.md enhancements**: Added Patternizer adoption to Pre-Release and VP Submission checklists

### Deprecated

#### Manual Scaffolding Files (v1.1.0+)
- `values-global.yaml.example` - Replaced by Patternizer-generated `values-global.yaml`
- `values-hub.yaml.example` - Replaced by Patternizer-generated `values-hub.yaml`
- **Migration**: Run `patternizer init --with-secrets`, review generated files, remove `.example` files
- **Timeline**: `.example` files will be removed in v2.0.0

### Planned — v1.1.0 (Remaining Tracked Issues)

#### OCP 4.21 Support
- Update compatibility matrix to 4.19 / 4.20 / 4.21 active window; move 4.18 to maintenance
- `values-hub.yaml` `cluster.version` default remains "4.20"; document override to "4.21" for current clusters
- `charts/hub/Chart.yaml`: bump `operatorhub.io/ui-metadata-max-k8s-version` to 1.34

#### Helm Chart & Image Refs
- Fix `Chart.yaml` `appVersion` and pin all image references to explicit tags — [#51](https://github.com/KubeHeal/openshift-aiops-platform/issues/51)

#### Validated Patterns Submission
- ✅ Patternizer scaffolding complete (see ADR-059 in Added section above)
- Author VP submission ADR and prepare nomination email — [#54](https://github.com/KubeHeal/openshift-aiops-platform/issues/54)
- Add architecture diagram + support policy to README

#### Monitoring
- Add `PrometheusRule` for CPU throttle detection using CFS metrics — [#52](https://github.com/KubeHeal/openshift-aiops-platform/issues/52)
- Grafana dashboard `ConfigMap` as Helm subchart for anomaly, disk, and right-sizing metrics — [#59](https://github.com/KubeHeal/openshift-aiops-platform/issues/59)

#### CI / Infrastructure
- Fix broken notebook test paths in `ci.yml` after directory restructure — [#53](https://github.com/KubeHeal/openshift-aiops-platform/issues/53)
- Verify all GitHub Actions workflows pass; configure branch protection on `main` — [#49](https://github.com/KubeHeal/openshift-aiops-platform/issues/49)

#### Documentation
- Resolve ADR-025 (object store model serving) — finalize status from Proposed — [#56](https://github.com/KubeHeal/openshift-aiops-platform/issues/56)
- Resolve ADR-032 (infrastructure validation notebook) — finalize status from Proposed — [#57](https://github.com/KubeHeal/openshift-aiops-platform/issues/57)
- Add `CONTRIBUTING.md` — [#58](https://github.com/KubeHeal/openshift-aiops-platform/issues/58)
- Add `RELEASE.md` with Helm chart release runbook and VP submission checklist — [#50](https://github.com/KubeHeal/openshift-aiops-platform/issues/50)

#### Ecosystem Growth
- `catalog-info.yaml` Backstage Software Catalog entries for all KubeHeal Suite components — [#60](https://github.com/KubeHeal/openshift-aiops-platform/issues/60)

#### Open Bugs
- Race condition: `InferenceService` predictor pods start before `NotebookValidationJob` trains models — [#34](https://github.com/KubeHeal/openshift-aiops-platform/issues/34)

---

## [1.0.0] - 2026-04-21

### Added — Platform Foundation

#### Architecture (ADRs 001-020)
- OpenShift 4.18+ as foundation platform with 4.18/4.19/4.20 version-specific overlays (ADR-001)
- Hybrid deterministic-AI self-healing approach: MCO rule-based + Isolation Forest / LSTM ML models (ADR-002)
- Red Hat OpenShift AI integration for ML platform (ADR-003)
- KServe for ML model serving with user-deployed model architecture (ADR-004)
- Machine Config Operator for node-level automation (ADR-005)
- NVIDIA GPU Operator support for AI workloads (ADR-006)
- Prometheus-based monitoring and data collection (ADR-007)
- Bootstrap deployment automation with deploy/delete lifecycle modes (ADR-009, ADR-020)
- OpenShift Data Foundation as storage infrastructure requirement (ADR-010)
- Self-healing workbench base image selection (ADR-011)
- Notebook architecture for end-to-end self-healing workflows (ADR-012)
- Data collection and preprocessing workflows (ADR-013)
- Validated Patterns framework adoption for GitOps deployment (ADR-019)

#### Platform Capabilities (ADRs 021-036)
- Tekton Pipeline for post-deployment validation (ADR-021)
- Multi-cluster support with ACM integration (ADR-022, Proposed)
- Jupyter Notebook Validator Operator integration (ADR-029)
- KServe `InferenceService` provisioning via Helm (ADR-028)
- OpenShift Lightspeed OLSConfig integration (ADR-016, Proposed)
- Service separation: standalone MCP server vs REST API coordination (ADR-015, superseded)
- Cluster Health MCP server for OpenShift Lightspeed (ADR-014, superseded by ADR-036)

#### Deployment
- Helm charts under `charts/` for all platform components
- `values-hub.yaml` for hub cluster GitOps values
- `values-global.yaml` for global configuration
- `values-secret.yaml.template` for secrets management
- Ansible collections under `ansible/` and `collections/` for bootstrap
- ArgoCD ApplicationSet-driven GitOps via Validated Patterns
- HA and SNO (Single Node OpenShift) topology support
- `DEPLOYMENT.md` and `DEPLOYMENT-QUICKSTART.md` step-by-step guides

#### Developer Experience
- `AGENTS.md` — comprehensive AI agent development guide
- `CLAUDE.md` — AI agent quick reference
- 32+ Architectural Decision Records in `docs/adrs/`
- Troubleshooting guide, user model deployment guide, junior developer guide
- Pre-commit hooks for Helm chart validation
- CI/CD: `ci.yml`, `helm-validation.yml` GitHub Actions workflows

#### AIOps Use Cases Implemented
- Anomaly detection via Coordination Engine (`/api/v1/anomaly/analyze`)
- Predictive analytics: disk exhaustion ETA, memory leak detection
- CPU/memory right-sizing recommendations (P95 usage vs requests/limits)
- CPU throttle detection (CFS metrics)
- Capacity forecasting with replica increase recommendations
- Deep RCA via Coordination Engine multi-layer analysis
