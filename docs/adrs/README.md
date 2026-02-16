# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records for the Self-Healing Platform project.

## ADR Index

| ADR | Title | Status | Date | Notes |
|-----|-------|--------|------|-------|
| [ADR-001](001-openshift-platform-selection.md) | OpenShift 4.18+ as Foundation Platform | Accepted | 2025-10-09 | |
| [ADR-002](002-hybrid-self-healing-approach.md) | Hybrid Deterministic-AI Self-Healing Approach | Accepted | 2025-10-09 | Core architecture |
| [ADR-003](003-openshift-ai-ml-platform.md) | Red Hat OpenShift AI for ML Platform | Accepted | 2025-10-09 | |
| [ADR-004](004-kserve-model-serving.md) | KServe for Model Serving Infrastructure | Accepted | 2025-10-09 | |
| [ADR-005](005-machine-config-operator-automation.md) | Machine Config Operator for Node-Level Automation | Accepted | 2025-10-09 | |
| [ADR-006](006-nvidia-gpu-management.md) | NVIDIA GPU Operator for AI Workload Management | Accepted | 2025-10-09 | |
| [ADR-007](007-prometheus-monitoring-integration.md) | Prometheus-Based Monitoring and Data Collection | Accepted | 2025-10-09 | |
| [ADR-008](008-kubeflow-pipelines-mlops.md) | Kubeflow Pipelines for MLOps Automation | ⚠️ **DEPRECATED** | 2025-10-09 | Superseded by ADR-021 (Tekton) and ADR-029 (Notebook Operator) |
| [ADR-009](009-bootstrap-deployment-automation.md) | Bootstrap Deployment Automation Architecture | Accepted | 2025-01-09 | |
| [ADR-010](010-openshift-data-foundation-requirement.md) | OpenShift Data Foundation as Storage Infrastructure Requirement | Accepted | 2025-10-13 | |
| [ADR-011](011-self-healing-workbench-base-image.md) | Self-Healing Workbench Base Image Selection | Accepted | 2025-10-13 | |
| [ADR-012](012-notebook-architecture-for-end-to-end-workflows.md) | Notebook Architecture for End-to-End Self-Healing Workflows | **Implemented** | 2025-10-13 | Status updated 2026-01-15 |
| [ADR-013](013-data-collection-and-preprocessing-workflows.md) | Data Collection and Preprocessing Workflows for Self-Healing Platform | **Implemented** | 2025-10-13 | Status updated 2026-01-15 |
| [ADR-014](014-openshift-aiops-platform-mcp-server.md) | Cluster Health MCP Server for OpenShift Lightspeed Integration | ⚠️ **SUPERSEDED** | 2025-10-13 | Superseded by ADR-036 (Go-based standalone) |
| [ADR-015](015-service-separation-mcp-vs-rest-api.md) | Service Separation - MCP Server vs REST API | ⚠️ **SUPERSEDED** | 2025-10-15 | Superseded by ADR-036 (standalone architecture) |
| [ADR-016](016-openshift-lightspeed-olsconfig-integration.md) | OpenShift Lightspeed OLSConfig Integration | Proposed | 2025-10-15 | |
| [ADR-017](017-gemini-integration-openshift-lightspeed.md) | Gemini Integration with OpenShift Lightspeed | Proposed | 2025-10-15 | |
| [ADR-018](018-llamastack-integration-openshift-ai.md) | LlamaStack Integration with OpenShift AI | Proposed | 2025-10-15 | |
| [ADR-019](019-validated-patterns-framework-adoption.md) | Validated Patterns Framework Adoption | Accepted | 2025-10-18 | Deployment framework |
| [ADR-020](020-bootstrap-deployment-deletion-lifecycle.md) | Bootstrap Deployment and Deletion Lifecycle with Deploy/Delete Modes | Accepted | 2025-10-23 | |
| [ADR-021](021-tekton-pipeline-deployment-validation.md) | Tekton Pipeline for Post-Deployment Validation | Accepted (Infrastructure) / Superseded (Notebooks by ADR-029) | 2025-10-31 | Partial supersession |
| [ADR-022](022-multi-cluster-support-acm-integration.md) | Multi-Cluster Support with ACM Integration | Proposed | 2025-10-28 | |
| [ADR-023](023-tekton-configuration-pipeline.md) | Tekton Configuration Pipeline | Proposed | 2025-10-29 | |
| [ADR-024](024-external-secrets-model-storage.md) | External Secrets for Model Storage | Proposed | 2025-10-30 | |
| [ADR-025](025-openshift-object-store-model-serving.md) | OpenShift Object Store for Model Serving | Proposed | 2025-10-19 | Renumbered from 020 |
| [ADR-026](026-secrets-management-automation.md) | Secrets Management Automation with External Secrets Operator | Accepted | 2025-11-02 | **MANDATORY** |
| [ADR-027](027-cicd-pipeline-automation.md) | CI/CD Pipeline Automation with Tekton and ArgoCD | Accepted | 2025-11-02 | |
| [ADR-028](028-gitea-local-git-repository.md) | Gitea Local Git Repository for Air-Gapped Environments | Accepted | 2025-11-02 | |
| [ADR-029](029-jupyter-notebook-validator-operator.md) | Jupyter Notebook Validator Operator for Notebook Validation | Implemented | 2025-11-18 | Supersedes ADR-021 (notebooks only) |
| [ADR-030](030-hybrid-management-model-namespaced-argocd.md) | Hybrid Management Model for Namespaced ArgoCD Deployments | Accepted | 2025-11-06 | |
| [ADR-031](031-dockerfile-strategy-for-notebook-validation.md) | Dockerfile Strategy for Notebook Validation | Accepted | 2025-11-19 | Single shared Dockerfile |
| [ADR-032](032-infrastructure-validation-notebook.md) | Infrastructure Validation Notebook for User Readiness | Implemented | 2025-11-04 | Tier 1 validation |
| [ADR-033](033-coordination-engine-rbac-permissions.md) | Coordination Engine RBAC Permissions | ⚠️ **DEPRECATED** | 2025-10-17 | Superseded by ADR-038 (Go coordination engine) |
| [ADR-034](034-rhods-notebook-routing.md) | RHODS Notebook Routing Configuration | Accepted | 2025-10-17 | Direct hostname access |
| [ADR-035](035-storage-strategy.md) | Storage Strategy for Self-Healing Platform | Accepted | 2025-10-17 | gp3-csi selection |
| [ADR-036](036-go-based-standalone-mcp-server.md) | Go-Based Standalone MCP Server for OpenShift Cluster Health | **IN PROGRESS** (Phase 1.4) | 2025-12-09 | **Supersedes ADR-014 & ADR-015**, standalone repo, 2 tools operational |
|| [ADR-037](037-mlops-workflow-strategy.md) | MLOps Workflow for Model Training, Versioning, and Deployment | Accepted | 2025-12-10 | **Supersedes ADR-008**, clarifies actual MLOps architecture |
| [ADR-038](038-go-coordination-engine-migration.md) | Go Coordination Engine Migration | Accepted | 2026-01-07 | Python → Go migration, deployment-aware remediation |
| [ADR-039](039-user-deployed-kserve-models.md) | User-Deployed KServe Models | Accepted | 2026-01-07 | Platform-agnostic ML integration |
| [ADR-040](040-extensible-kserve-model-registry.md) | Extensible KServe Model Registry | Accepted | 2026-01-07 | Custom model registration via values.yaml |
| [ADR-041](041-model-storage-and-versioning-strategy.md) | Model Storage and Versioning Strategy | Accepted | 2025-12-09 | One directory per InferenceService |
| [ADR-042](042-argocd-deployment-lessons-learned.md) | ArgoCD Deployment Lessons Learned | Accepted | 2025-11-28 | Deployment patterns and best practices |
|| [ADR-043](043-deployment-stability-health-checks.md) | Deployment Stability and Cross-Namespace Health Check Patterns | Implemented | 2026-01-24 | Init containers, startup probes, health checks |
|| [ADR-053](053-tekton-model-training-pipelines.md) | Tekton Pipelines for Model Training | Proposed | 2026-01-27 | Replaces ArgoCD sync wave approach; amended #38 CPU/GPU split, #40 GPU PVC fix |
|| [ADR-054](054-inferenceservice-model-readiness-race-condition.md) | InferenceService Model Readiness Race Condition Fix | Accepted | 2026-02-06 | Post-deploy restart job for predictor pods |

### Meta-Documents

| Document | Purpose |
|----------|---------|
| [ADR-DEVELOPMENT-RULES.md](ADR-DEVELOPMENT-RULES.md) | Development rules and best practices for ADR management |

## ADR Status Definitions

- **Proposed**: The ADR is under consideration, not yet implemented
- **Accepted**: The ADR has been accepted and is being implemented
- **Implemented**: The ADR has been fully implemented and is in production
- **Deprecated**: The ADR is no longer valid but kept for historical reference
- **Superseded**: The ADR has been replaced by a newer decision (reference included)

## ADR Categories

### Platform Foundation (001-010)
Core platform decisions including OpenShift selection, hybrid architecture, AI/ML platform, and storage.

### ML/AI Workflows (011-013, 037-041)
Notebook architecture, workbench configuration, data workflows, MLOps, and model management.

### Integration & Services (014-018)
MCP server, OpenShift Lightspeed, and service integration patterns.

### Deployment & Operations (019-024, 026-028, 030)
Validated Patterns framework, deployment automation, CI/CD, secrets management, and GitOps.

### Validation & Testing (021, 029, 032)
Deployment validation (Tekton), notebook validation (Operator), and infrastructure validation.

### Storage & Configuration (025, 033-035, 041)
Object storage, RBAC, routing, storage strategies, and model versioning.

### Coordination & Integration (038-040)
Coordination engine architecture, KServe integration, and model registry.

### Deployment & Lessons (042-043, 053-054)
ArgoCD deployment patterns, health checks, Tekton pipelines, and race condition fixes.

### Advanced Features (031)
Custom image building strategies and Docker configuration.

## Recent Changes

### 2026-02-06: InferenceService Model Readiness Race Condition Fix

**Major Fix**:
- **ADR-054** created and accepted: InferenceService Model Readiness Race Condition Fix
- Fixes Issue #34: Predictor pods start before models are trained
- Solution: Post-deploy restart job at sync-wave 5 that waits for models and restarts predictors
- Added inference endpoint health check to post-deployment validation script

**Implementation**:
- New Helm template: `charts/hub/templates/restart-predictors-job.yaml`
- Updated validation script: `scripts/post-deployment-validation.sh` (Check 7)
- Prevents silent ModelMissingError failures in workshop scenarios

### 2026-01-07: Go Coordination Engine and KServe Integration

**Major Architectural Changes**:
- **ADR-038** created and accepted: Go Coordination Engine Migration (Python → Go)
- **ADR-039** created and accepted: User-Deployed KServe Models (Platform-agnostic ML integration)
- **ADR-040** created and accepted: Extensible KServe Model Registry (Custom model registration)

**Status Updates**:
- **ADR-012**: PROPOSED → **IMPLEMENTED** (notebooks complete, blog posts published)
- **ADR-013**: PROPOSED → **IMPLEMENTED** (data collection workflows operational)
- **ADR-033**: PROPOSED → **DEPRECATED** (superseded by ADR-038 Go coordination engine)

**Renumbering**:
- **ADR-031 (model-storage)** → **ADR-041** (resolved duplicate with dockerfile-strategy)
- **ADR-031 (deployment-lessons)** → **ADR-042** (resolved duplicate, standardized naming)

### 2025-12-10: MCP Server Migration to Standalone Go Project

**Major Architectural Change**:
- **ADR-036** created and accepted: Go-Based Standalone MCP Server
- **ADR-014** status changed: **Accepted** → **SUPERSEDED by ADR-036**
- **ADR-015** status changed: **Accepted** → **SUPERSEDED by ADR-036**

**Implementation Status** (ADR-036):
- ✅ Phase 1.4 completed: 2 MCP tools operational (`get-cluster-health`, `list-pods`)
- ✅ Deployed on OpenShift 4.18.21 with HTTP transport
- ✅ 10 ADRs in standalone repository documenting all decisions
- 🚧 Next: Phase 1.5 (Stateless Cache)

**Migration Details**:
- TypeScript MCP server removed from `src/mcp-server/` (commit: 9c2dc301)
- New standalone repository: `/home/lab-user/openshift-cluster-health-mcp`
- Language: TypeScript → Go 1.21+
- Architecture: Embedded → Standalone
- Integration: Direct coupling → HTTP REST APIs

### 2025-11-19: Renumbering for Consistency
- **ADR-020 (object-store)** → **ADR-025** (resolved duplicate with bootstrap-deployment)
- **ADR-029 (infrastructure-validation-notebook)** → **ADR-032** (resolved duplicate with jupyter-notebook-validator-operator)
- **ADR-025 (coordination-engine-rbac)** → **ADR-033** (standardized naming)
- **ADR-RHODS-NOTEBOOK-ROUTING** → **ADR-034** (standardized naming)
- **ADR-STORAGE-STRATEGY** → **ADR-035** (standardized naming)

### Status Updates (2025-11-19)
- **ADR-021**: Marked notebook validation as superseded by ADR-029 (infrastructure validation still active)
- **ADR-029**: Status changed from Proposed to Implemented
- **ADR-032**: Status changed from Proposed to Implemented (Tier 1 validation notebook)

## Current Platform State (2025-11-19)

The platform is deployed with:
- **OpenShift**: 4.18.21
- **Red Hat OpenShift AI**: 2.22.2
- **NVIDIA GPU Operator**: 24.9.2
- **Knative Serving**: 1.36.1
- **Istio Service Mesh**: 2.6.11
- **OpenShift GitOps**: 1.15.4
- **OpenShift Pipelines**: 1.17.2
- **Jupyter Notebook Validator Operator**: 0.1.0

## ADR Template

We use the [MADR (Markdown Architectural Decision Records)](https://adr.github.io/madr/) format for consistency.

### Template Structure

```markdown
# ADR-XXX: [Title]

**Status**: [Proposed | Accepted | Implemented | Deprecated | Superseded]
**Date**: YYYY-MM-DD
**Deciders**: [List of decision makers]

## Context

[Describe the issue/problem and forces at play]

## Decision

[The architectural decision made]

## Consequences

### Positive
- [Benefits]

### Negative
- [Drawbacks]

## Related ADRs

- [Links to related ADRs]

## References

- [External documentation, specifications, etc.]
```

## Contributing

When creating new ADRs:

1. **Use the next available number** in the sequence (currently: ADR-042, next: ADR-043)
2. **Follow the MADR template** format (see above)
3. **Include clear context**, decision, and consequences
4. **Update this README.md** index with your new ADR
5. **Link related ADRs** where appropriate (both in new ADR and existing ones)
6. **Use lowercase hyphenated filenames**: `036-your-decision-title.md`
7. **Mark superseded ADRs** if your decision replaces existing ones
8. **Add cross-references** in the "Related ADRs" section

## Quick Reference

### Most Important ADRs for New Contributors

1. **[ADR-002](002-hybrid-self-healing-approach.md)** - Core architecture pattern
2. **[ADR-019](019-validated-patterns-framework-adoption.md)** - Deployment framework
3. **[ADR-026](026-secrets-management-automation.md)** - **MANDATORY** secrets management
4. **[ADR-029](029-jupyter-notebook-validator-operator.md)** - Current notebook validation approach
5. **[ADR-031](031-dockerfile-strategy-for-notebook-validation.md)** - Image building strategy

### Superseded Decisions

- **ADR-021 (Notebook Validation only)** → **ADR-029** (Jupyter Notebook Validator Operator)
  - Infrastructure validation in ADR-021 remains ACTIVE

## Maintenance

This README is maintained by the Architecture Team and should be updated whenever:
- New ADRs are created
- ADR status changes (Proposed → Accepted → Implemented)
- ADRs are superseded or deprecated
- Major platform versions change

**Last Updated**: 2026-02-06
**Maintained By**: Architecture Team
**Review Frequency**: Monthly or when ADRs change
