# ADR Cross-Reference Matrix

**Date**: 2025-12-01
**Purpose**: Document relationships and dependencies between all ADRs
**Status**: Initial Version

---

## How to Read This Matrix

- **→** : Depends on / References
- **←** : Referenced by / Depended upon by
- **↔** : Bidirectional relationship
- **⊗** : Supersedes / Superseded by
- **⚠️** : Conflict or inconsistency

---

## Platform Foundation (ADR-001 to ADR-010)

### ADR-001: OpenShift as Foundation Platform (originally 4.18+; now 4.19+ recommended)
**Dependencies**:
- → ADR-002 (Provides platform for hybrid architecture)
- → ADR-003 (Enables OpenShift AI deployment)
- → ADR-005 (Provides MCO capabilities)
- → ADR-006 (Supports GPU operator)
- → ADR-019 (Foundation for Validated Patterns)

**Referenced By**:
- ← All ADRs (foundational decision)

---

### ADR-002: Hybrid Deterministic-AI Self-Healing Approach
**Dependencies**:
- → ADR-001 (Requires OpenShift platform)
- → ADR-003 (Requires AI/ML platform)
- → ADR-005 (Uses MCO for deterministic layer)
- → ADR-007 (Requires monitoring for both layers)

**Referenced By**:
- ← ADR-014 (MCP server implements coordination)
- ← ADR-015 (Service separation for layers)

---

### ADR-003: Red Hat OpenShift AI for ML Platform
**Dependencies**:
- → ADR-001 (Requires OpenShift 4.19+; 4.18 maintenance-only)
- → ADR-006 (Requires GPU support)

**Referenced By**:
- ← ADR-004 (KServe part of OpenShift AI)
- ← ADR-008 (Kubeflow Pipelines - DEPRECATED)
- ← ADR-011 (Workbench images)
- ← ADR-012 (Notebook architecture)

---

### ADR-004: KServe for Model Serving Infrastructure
**Dependencies**:
- → ADR-001 (Requires OpenShift)
- → ADR-003 (Part of OpenShift AI)
- → ADR-024 (Requires secrets for S3)
- → ADR-025 (Requires object store)

**Referenced By**:
- ← ADR-029 (Models deployed to KServe)
- ← ADR-021 (Validates KServe deployments)

---

### ADR-005: Machine Config Operator for Node-Level Automation
**Dependencies**:
- → ADR-001 (MCO part of OpenShift)
- → ADR-002 (Implements deterministic layer)

---

### ADR-006: NVIDIA GPU Operator for AI Workload Management
**Dependencies**:
- → ADR-001 (Requires OpenShift)
- → ADR-003 (Enables AI workloads)

**Referenced By**:
- ← ADR-011 (GPU-enabled workbenches)
- ← ADR-029 (GPU support in notebooks)

---

### ADR-007: Prometheus-Based Monitoring and Data Collection
**Dependencies**:
- → ADR-001 (Prometheus on OpenShift)
- → ADR-002 (Monitors both layers)

**Referenced By**:
- ← ADR-008 (Data source for pipelines - DEPRECATED)
- ← ADR-013 (Data collection workflows)
- ← ADR-021 (Validates monitoring stack)

---

### ADR-008: Kubeflow Pipelines for MLOps Automation
**Status**: ⚠️ **SHOULD BE DEPRECATED**
**Dependencies**:
- → ADR-003 (Part of OpenShift AI)
- → ADR-007 (Data source)

**Conflicts**:
- ⊗ ADR-021 (Tekton used instead)
- ⊗ ADR-029 (Operator used instead)

**Recommendation**: Deprecate and create new ADR documenting actual MLOps approach

---

### ADR-009: Bootstrap Deployment Automation Architecture
**Status**: ⊗ **SUPERSEDED by ADR-019**
**Dependencies**:
- → ADR-001 (Deploys on OpenShift)

**Superseded By**:
- ⊗ ADR-019 (Validated Patterns framework)

---

### ADR-010: OpenShift Data Foundation as Storage Infrastructure Requirement
**Dependencies**:
- → ADR-001 (ODF on OpenShift)

**Referenced By**:
- ← ADR-024 (S3 via ODF)
- ← ADR-025 (Object store via ODF)
- ← ADR-035 (Storage strategy)

---

## ML/AI Workflows (ADR-011 to ADR-013)

### ADR-011: Self-Healing Workbench Base Image Selection
**Dependencies**:
- → ADR-003 (Workbench in OpenShift AI)
- → ADR-006 (GPU support)

**Referenced By**:
- ← ADR-012 (Notebook architecture)
- ← ADR-029 (Validation pods use same images)

---

### ADR-012: Notebook Architecture for End-to-End Self-Healing Workflows
**Dependencies**:
- → ADR-003 (OpenShift AI notebooks)
- → ADR-011 (Base images)

**Referenced By**:
- ← ADR-013 (Data workflows)
- ← ADR-029 (Notebook validation)
- ← ADR-032 (Platform readiness notebook)

---

### ADR-013: Data Collection and Preprocessing Workflows
**Dependencies**:
- → ADR-007 (Prometheus data source)
- → ADR-012 (Notebook architecture)

---

## Integration & Services (ADR-014 to ADR-018)

### ADR-014: Cluster Health MCP Server for OpenShift Lightspeed Integration
**Dependencies**:
- → ADR-002 (Implements coordination engine)
- → ADR-015 (Service separation)

**Referenced By**:
- ← ADR-016 (Lightspeed integration)
- ← ADR-021 (Validates MCP server)

---

### ADR-015: Service Separation - MCP Server vs REST API
**Dependencies**:
- → ADR-014 (MCP server architecture)

---

### ADR-016: OpenShift Lightspeed OLSConfig Integration
**Dependencies**:
- → ADR-014 (MCP server)
- → ADR-017 (Gemini integration)

---

### ADR-017: Gemini Integration with OpenShift Lightspeed
**Dependencies**:
- → ADR-016 (Lightspeed)

---

### ADR-018: LlamaStack Integration with OpenShift AI
**Dependencies**:
- → ADR-003 (OpenShift AI)

---

## Deployment & Operations (ADR-019 to ADR-030)

### ADR-019: Validated Patterns Framework Adoption
**Status**: ✅ **CURRENT DEPLOYMENT FRAMEWORK**
**Dependencies**:
- → ADR-001 (OpenShift platform)
- ⊗ ADR-009 (Supersedes bootstrap)

**Referenced By**:
- ← ADR-020 (Deploy/delete lifecycle)
- ← ADR-021 (Post-deployment validation)
- ← ADR-026 (Secrets management)
- ← ADR-027 (CI/CD integration)
- ← ADR-028 (Gitea integration)
- ← ADR-030 (Namespaced ArgoCD)
- ← ADR-DEVELOPMENT-RULES (Development guidelines)

---

### ADR-020: Bootstrap Deployment and Deletion Lifecycle
**Dependencies**:
- → ADR-019 (Validated Patterns framework)

---

### ADR-021: Tekton Pipeline for Post-Deployment Validation
**Status**: ✅ **ACTIVE** (Infrastructure) | ⊗ **SUPERSEDED** (Notebooks by ADR-029)
**Dependencies**:
- → ADR-019 (Post-deployment validation)
- → ADR-004 (Validates KServe)
- → ADR-007 (Validates Prometheus)
- → ADR-014 (Validates MCP server)

**Superseded By**:
- ⊗ ADR-029 (Notebook validation only)

**Referenced By**:
- ← ADR-027 (CI/CD pipelines)
- ← ADR-032 (Platform readiness)

---

### ADR-022: Multi-Cluster Support with ACM Integration
**Dependencies**:
- → ADR-019 (Validated Patterns multi-cluster)

---

### ADR-023: Tekton Configuration Pipeline
**Dependencies**:
- → ADR-021 (Tekton infrastructure)
- → ADR-027 (CI/CD automation)

---

### ADR-024: External Secrets for Model Storage
**Dependencies**:
- → ADR-026 (External Secrets Operator)
- → ADR-025 (S3 credentials)

**Referenced By**:
- ← ADR-004 (KServe S3 access)
- ← ADR-029 (Model storage integration)

---

### ADR-025: OpenShift Object Store for Model Serving
**Dependencies**:
- → ADR-010 (ODF/NooBaa)
- → ADR-024 (S3 credentials)

**Referenced By**:
- ← ADR-004 (KServe storage)
- ← ADR-029 (Model upload workflow)

---

### ADR-026: Secrets Management Automation with External Secrets Operator
**Status**: ✅ **MANDATORY**
**Dependencies**:
- → ADR-019 (Validated Patterns secrets)

**Referenced By**:
- ← ADR-024 (Model storage secrets)
- ← ADR-028 (Gitea credentials)
- ← ADR-029 (Git credentials)

---

### ADR-027: CI/CD Pipeline Automation with Tekton and ArgoCD
**Dependencies**:
- → ADR-019 (ArgoCD integration)
- → ADR-021 (Tekton pipelines)

---

### ADR-028: Gitea Local Git Repository for Air-Gapped Environments
**Dependencies**:
- → ADR-019 (Validated Patterns Gitea role)
- → ADR-026 (Gitea credentials)

---

### ADR-029: Jupyter Notebook Validator Operator for Notebook Validation
**Status**: ✅ **IMPLEMENTED** (Updated 2025-12-01)
**Dependencies**:
- → ADR-011 (Container images)
- → ADR-012 (Notebook architecture)
- → ADR-019 (Operator deployment)
- → ADR-024 (S3 credentials)
- → ADR-025 (Object store)
- → ADR-026 (Git credentials)
- → ADR-035 (Storage class)

**Supersedes**:
- ⊗ ADR-021 (Notebook validation only)

**Referenced By**:
- ← ADR-032 (Executes validation notebook)

---

### ADR-030: Hybrid Management Model for Namespaced ArgoCD Deployments
**Dependencies**:
- → ADR-019 (Validated Patterns ArgoCD)

---

## Validation & Testing (ADR-031, ADR-032)

### ADR-031: Dockerfile Strategy for Notebook Validation
**Dependencies**:
- → ADR-029 (Notebook operator)

---

### ADR-032: Infrastructure Validation Notebook for User Readiness
**Status**: ✅ **IMPLEMENTED**
**Dependencies**:
- → ADR-012 (Notebook architecture)
- → ADR-021 (Infrastructure validation)
- → ADR-029 (Executed via operator)

---

## Storage & Configuration (ADR-033 to ADR-035)

### ADR-033: Coordination Engine RBAC Permissions
**Dependencies**:
- → ADR-014 (Coordination engine)

---

### ADR-034: RHODS Notebook Routing Configuration
**Dependencies**:
- → ADR-011 (Workbench access)

---

### ADR-035: Storage Strategy for Self-Healing Platform
**Dependencies**:
- → ADR-010 (ODF)

**Referenced By**:
- ← ADR-029 (gp3-csi for PVCs)

---

## Summary Statistics

- **Total ADRs**: 35
- **Active**: 30
- **Deprecated**: 1 (ADR-009)
- **Should be Deprecated**: 1 (ADR-008)
- **Superseded**: 1 (ADR-021 notebooks only)
- **Missing Cross-References**: 12
- **Conflicts**: 1 (ADR-008 vs ADR-021/029)

---

**Next Steps**: Use this matrix to update individual ADRs with complete "Related ADRs" sections.
