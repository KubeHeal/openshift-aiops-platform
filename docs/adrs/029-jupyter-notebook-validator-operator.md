# ADR-029: Jupyter Notebook Validator Operator for Notebook Validation

**Status:** IMPLEMENTED
**Date:** 2025-11-18
**Updated:** 2026-01-26 (Upgraded to v1.0.5 with ArgoCD integration, model validation, and exit code validation)
**Decision Makers:** Architecture Team, ML Engineering
**Consulted:** DevOps Team, Platform Engineering
**Informed:** Operations Team, Data Science Team

## Context

The OpenShift AIOps Self-Healing Platform includes 30+ Jupyter notebooks across 8 directories that require automated validation and execution tracking. The notebooks implement critical ML workflows including data collection, anomaly detection, model training, and deployment to KServe.

### Current State (ADR-021 Implementation)

The current implementation uses **Tekton pipelines** for notebook validation:
- Notebooks executed directly in Tekton tasks via `jupyter nbconvert --execute`
- Validation mixed with infrastructure health checks
- No declarative notebook job management
- Limited resource isolation per notebook
- Difficult to track individual notebook execution history

### Problems with Current Approach

1. **Tight Coupling**: Notebook execution tightly coupled to Tekton pipeline infrastructure
2. **Resource Management**: No per-notebook resource requests/limits configuration
3. **Execution Tracking**: Difficult to track individual notebook runs and artifacts
4. **Git Integration**: Manual git clone in Tekton tasks, no credential management
5. **Validation Reporting**: No standardized notebook validation results format
6. **Scalability**: All notebooks share same pipeline execution context
7. **Model Storage**: No persistent storage for trained models across validation runs

### New Requirements

Based on [Jupyter Notebook Validator Operator](https://raw.githubusercontent.com/tosin2013/jupyter-notebook-validator-operator/refs/heads/release-4.18/helm/jupyter-notebook-validator-operator/INSTALLATION.md) capabilities:

1. **CRD-Based Validation**: Declarative NotebookValidationJob resources
2. **Git Integration**: Native support for public and private Git repositories
3. **Resource Isolation**: Per-notebook resource requests and limits
4. **Artifact Collection**: Automatic validation pod log collection
5. **Credential Management**: Kubernetes secret integration for private repos
6. **Webhook Support**: Validation via cert-manager webhooks
7. **Volume Support**: PVC mounting for persistent model storage (NEW - 2025-12-01)

## Decision

**Adopt the Jupyter Notebook Validator Operator** as the primary notebook validation mechanism, superseding Tekton-based notebook execution from ADR-021.

### Architecture

```
Notebook Validation Architecture:
┌─────────────────────────────────────────────────────────────┐
│              Jupyter Notebook Validator Operator            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  NotebookValidationJob CRDs                         │    │
│  │  (mlops.mlops.dev/v1alpha1)                         │    │
│  └─────────────────────────────────────────────────────┘    │
│           │                                                  │
│           ▼                                                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Validation Controller                              │    │
│  │  - Watches NotebookValidationJob CRDs               │    │
│  │  - Creates validation pods                          │    │
│  │  - Collects execution logs                          │    │
│  │  - Updates CRD status                               │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              Validation Pods (per notebook)                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  1. Git Clone (from spec.notebook.git.url)          │    │
│  │  2. Install Dependencies (requirements.txt)         │    │
│  │  3. Execute Notebook (jupyter nbconvert --execute)  │    │
│  │  4. Collect Artifacts (logs, outputs)               │    │
│  │  5. Update CRD Status (Success/Failed)              │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              Git Repository Integration                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Public Repos: Direct HTTPS clone                   │    │
│  │  Private Repos: Kubernetes secret credentials       │    │
│  │    - username/password (PAT tokens)                 │    │
│  │    - SSH keys                                       │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### NotebookValidationJob CRD Example

#### Basic Notebook Validation (Without Volumes)

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: anomaly-detection-isolation-forest
  namespace: self-healing-platform
spec:
  notebook:
    git:
      url: "https://github.com/openshift-aiops/openshift-aiops-platform.git"
      ref: "main"
      credentialsSecret: "github-credentials"  # For private repos
    path: "notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb"

  podConfig:
    containerImage: "quay.io/jupyter/minimal-notebook:latest"
    resources:
      requests:
        memory: "2Gi"
        cpu: "1000m"
      limits:
        memory: "4Gi"
        cpu: "2000m"

  timeout: "30m"
```

#### Advanced Notebook Validation (With Model Storage Volumes)

**NEW (2025-12-01)**: The Jupyter Notebook Validator Operator now supports volume mounting, enabling persistent model storage across validation runs.

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: model-training-with-storage
  namespace: self-healing-platform
spec:
  notebook:
    git:
      url: "https://github.com/openshift-aiops/openshift-aiops-platform.git"
      ref: "main"
      credentialsSecret: "github-credentials"
    path: "notebooks/03-model-training/ensemble-model-training.ipynb"

  podConfig:
    containerImage: "quay.io/modh/runtime-images:jupyter-datascience-ubi9-python-3.11-2025.1"
    resources:
      requests:
        memory: "4Gi"
        cpu: "2000m"
        nvidia.com/gpu: "1"  # GPU support for model training
      limits:
        memory: "8Gi"
        cpu: "4000m"
        nvidia.com/gpu: "1"

    # Volume mounts for persistent model storage
    volumes:
      - name: model-storage
        persistentVolumeClaim:
          claimName: model-storage-pvc
      - name: data-storage
        persistentVolumeClaim:
          claimName: data-storage-pvc

    volumeMounts:
      - name: model-storage
        mountPath: /opt/app-root/src/models
      - name: data-storage
        mountPath: /opt/app-root/src/data

  timeout: "60m"
```

**Use Cases for Volume Support**:
1. **Model Training Notebooks**: Store trained models in PVCs for later deployment
2. **Data Preprocessing**: Cache preprocessed datasets across validation runs
3. **Artifact Persistence**: Maintain validation artifacts and logs
4. **Model Versioning**: Track model versions across multiple training runs
5. **Shared Storage**: Enable multiple notebooks to access common model repository

### v1.0.5 Enhancements (2026-01-26)

**Operator Version**: v1.0.5 (universal release for OpenShift 4.18/4.19/4.20)

The v1.0.5 release introduces significant new features that improve notebook validation and deployment workflows:

#### 1. ArgoCD Integration (ADR-049)

All 5 ArgoCD integration features are fully implemented:

**ArgoCD Health Assessment**: Notebook validation status visible in ArgoCD UI
- Installation: `kubectl apply -f k8s/operators/jupyter-notebook-validator/argocd/health-check-configmap.yaml`
- Status mapping: Succeeded → Healthy, Failed → Degraded, Running → Progressing
- Real-time validation progress visible in ArgoCD dashboard

**Post-Success Resource Hooks**: Auto-restart InferenceServices when notebooks succeed
```yaml
annotations:
  mlops.dev/on-success-trigger: |
    - apiVersion: serving.kserve.io/v1beta1
      kind: InferenceService
      name: predictive-analytics
      namespace: self-healing-platform
      action: restart
```

**CRITICAL ISSUE SOLVED**: This feature eliminates the manual pod deletion requirement for InferenceServices. Previously, when notebooks trained models and stored them in PVCs, the InferenceService predictor pods remained at 1/2 ready state until manually deleted. The `mlops.dev/on-success-trigger` annotation automatically triggers pod restart, bringing InferenceServices to 2/2 ready state without manual intervention.

**Sync Wave Awareness**: Coordinate notebook execution with ArgoCD deployment waves
```yaml
annotations:
  argocd.argoproj.io/sync-wave: "3"     # Run notebook in wave 3
  mlops.dev/block-wave: "4"              # Block wave 4 until success
```

This enables precise orchestration of notebook execution in relation to other resources:
- Wave 1: Infrastructure (PVCs, ConfigMaps)
- Wave 2: Dependencies (databases, services)
- Wave 3: Notebook validation (model training)
- Wave 4: Model deployment (InferenceServices)

**Application Status Integration**: Aggregated notebook status in ArgoCD Applications
- Auto-updates `mlops.dev/notebook-status` annotation with success/failure counts
- Application-level health reflects notebook validation state
- Rollback policies can trigger on notebook failures

**Notification Events**: Kubernetes Events for ArgoCD notifications
- Integrates with ArgoCD notification controller
- Supports Slack, email, PagerDuty, webhook notifications
- Events created for: validation started, succeeded, failed, timeout

**RBAC Requirements**: Updated ClusterRole permissions required
```yaml
# Required for auto-restart InferenceServices
- apiGroups: ["serving.kserve.io"]
  resources: ["inferenceservices"]
  verbs: ["get", "list", "patch"]

- apiGroups: [""]
  resources: ["pods"]
  verbs: ["list", "delete"]

# Required for ArgoCD Application status updates
- apiGroups: ["argoproj.io"]
  resources: ["applications"]
  verbs: ["get", "list", "patch"]

# Required for notification events
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "patch"]
```

#### 2. Model-Aware Validation (ADR-020)

Fully implemented multi-platform model validation:

**Supported Platforms**: KServe, OpenShift AI, vLLM, TorchServe, Triton, Ray Serve, Seldon Core, BentoML

**Two-Phase Validation Strategy**:
- **Phase 1 (Clean Environment)**: Validate notebook in isolated environment before deployment
- **Phase 2 (Existing Environment)**: Validate against deployed models after deployment
- **Both**: Run both phases for comprehensive testing

**Prediction Validation**: Test deployed models with sample data
```yaml
modelValidation:
  enabled: true
  platform: kserve
  phase: both
  targetModels:
    - predictive-analytics
  predictionValidation:
    enabled: true
    testData: |
      {"instances": [[1.0, 2.0, 3.0, 4.0, 5.0]]}
    expectedOutput: |
      {"predictions": [[0.8, 0.2]]}
    tolerance: "0.1"
  timeout: "5m"
```

**Platform Auto-Detection**: Automatically detects serving platform from deployed models
- Scans namespace for InferenceServices (KServe)
- Detects Ray Serve deployments
- Identifies Seldon Core models
- No manual platform configuration required

**Benefits**:
- ✅ Catch model integration issues before deployment
- ✅ Validate notebook works with actual serving infrastructure
- ✅ Prevent version mismatches between training and serving
- ✅ Ensure model API compatibility

#### 3. Exit Code Validation (ADR-041)

Developer safety framework to catch silent failures:

**Validation Levels**:
- `learning`: Minimal checks, maximum flexibility (for experimentation)
- `development`: Basic checks, allow warnings
- `staging`: Strict checks, catch most issues
- `production`: Full checks, zero tolerance for errors

**Silent Failure Detection**: Catches common issues
- None returns from cells
- NaN values in outputs
- Missing exit codes
- Empty results when output expected
- Type mismatches

**Configuration Example**:
```yaml
validationConfig:
  level: "production"
  strictMode: true
  failOnStderr: false  # Allow warnings but not errors
  detectSilentFailures: true
  checkOutputTypes: true
  expectedOutputs:
    - cell: 10  # Cell that trains model
      type: "object"
      notEmpty: true
    - cell: 15  # Cell that evaluates model
      type: "float"
      range: [0.7, 1.0]  # Accuracy 70-100%
```

**Use Cases**:
- Prevent broken notebooks from passing validation
- Catch logical errors that don't raise exceptions
- Enforce output type contracts
- Validate metric ranges (accuracy, loss, etc.)

#### 4. Advanced Comparison (ADR-030)

Smart error messages and comparison strategies for ML workflows:

**Comparison Strategies**:
- `exact`: Byte-for-byte comparison (for deterministic notebooks)
- `normalized`: Floating-point tolerant comparison (for ML notebooks)

**Floating-Point Tolerance**: Handle non-deterministic ML outputs
```yaml
comparisonConfig:
  strategy: "normalized"
  floatingPointTolerance: "0.01"  # 1% tolerance
  ignoreTimestamps: true
  ignoreExecutionCount: true
```

**Custom Timestamp Patterns**: Ignore ML training logs
```yaml
comparisonConfig:
  customTimestampPatterns:
    - "Training time: \\d+\\.\\d+s"
    - "Epoch \\d+/\\d+ - \\d+\\.\\d+s"
    - "Accuracy: 0\\.\\d+"  # Tolerate accuracy variations
```

**Benefits**:
- ✅ Handle non-deterministic model training outputs
- ✅ Tolerate timing variations across runs
- ✅ Focus on meaningful differences, not noise
- ✅ Reduce false positive validation failures

#### Integration Benefits

The v1.0.5 features solve critical pain points in the platform:

**Before v1.0.5**:
- Manual pod deletion required for InferenceServices after model training
- No visibility of notebook validation in ArgoCD UI
- Model integration issues discovered in production
- Silent notebook failures could pass validation
- ML metric variations caused false positive failures

**After v1.0.5**:
- ✅ Automatic InferenceService reload when notebooks succeed (no manual intervention)
- ✅ Full GitOps compliance with ArgoCD health checks and sync waves
- ✅ Model validation gates prevent broken deployments
- ✅ Silent failure detection catches logical errors
- ✅ Smart comparison strategies handle ML non-determinism
- ✅ Comprehensive notification integration (Slack, email, PagerDuty)

**Cross-Reference**:
- See ADR-043 (Deployment Stability & Health Checks) for init container patterns
- See operator ADR-020, ADR-030, ADR-041, ADR-049 for detailed feature specifications
- See `k8s/operators/jupyter-notebook-validator/samples/` for example manifests

### Operator Deployment

The operator requires:

1. **cert-manager v1.13+**: For webhook certificate management
2. **Helm 3.8+**: Operator deployment via Helm chart
3. **Kubernetes 1.31+ / OpenShift 4.18+**: Platform requirements

**Helm Installation**:
```bash
helm install jupyter-validator \
  https://github.com/tosin2013/jupyter-notebook-validator-operator/releases/download/release-4.18/jupyter-notebook-validator-operator-0.1.0.tgz \
  --namespace jupyter-validator-system \
  --create-namespace \
  --set openshift.enabled=true \
  --set prometheus.enabled=true
```

### Deployment via Validated Patterns (2025-12-04 Update)

**Status**: Operator NOT yet in OperatorHub/marketplace (submission in progress)

**Deployment Method**: Self-contained kustomize deployment following ADR-030 Hybrid Management Pattern

**Architecture**:
```
k8s/operators/jupyter-notebook-validator/
├── base/                           # Base manifests
│   ├── crd/                        # NotebookValidationJob CRD
│   ├── rbac/                       # ClusterRole, ClusterRoleBinding, ServiceAccount
│   ├── manager/                    # Operator Deployment
│   ├── certmanager/                # Certificates (optional - webhooks)
│   └── webhook/                    # Webhook configuration (optional)
├── argocd/                         # ArgoCD integration (NEW v1.0.5)
│   ├── health-check-configmap.yaml # Health assessment for NotebookValidationJob
│   └── README.md                   # ArgoCD integration guide
├── samples/                        # Example validation jobs (NEW v1.0.5)
│   ├── predictive-analytics-validation-job.yaml
│   └── README.md                   # Usage examples
└── overlays/
    ├── dev-ocp4.18/                # OCP 4.18 (image: 1.0.5 - universal release)
    ├── dev-ocp4.19/                # OCP 4.19 (image: 1.0.5 - universal release)
    └── dev-ocp4.20/                # OCP 4.20 (image: 1.0.5 - universal release)
```

**Installation**:
```bash
# Build execution environment (first time)
make build-ee

# Install operator
make install-jupyter-validator

# Verify installation
make validate-jupyter-validator

# Test with sample notebook
make test-jupyter-validator
```

**Uninstallation**:
```bash
make uninstall-jupyter-validator
```

**Deployment Flow**:
1. Kustomize builds overlay: `k8s/operators/jupyter-notebook-validator/overlays/dev-ocp4.18`
2. Ansible applies manifests: `kubernetes.core.k8s` with kustomize lookup
3. Operator deployed to: `jupyter-notebook-validator-operator` namespace
4. CRD registered: `notebookvalidationjobs.mlops.mlops.dev`
5. Validation jobs created in: `self-healing-platform` namespace

**Key Features**:
- ✅ **Self-contained**: All manifests in project (no external dependencies)
- ✅ **Version controlled**: Operator manifests tracked in git
- ✅ **ADR-030 compliant**: Cluster-scoped resources via Ansible
- ✅ **Multi-version support**: Overlays for OCP 4.18, 4.19, 4.20
- ✅ **Optional webhooks**: Auto-enabled if cert-manager present

**Comparison with OLM Deployment** (when available):
| Aspect | Current (Kustomize) | Future (OLM) |
|--------|---------------------|--------------|
| Method | Direct manifest deployment | OperatorHub subscription |
| Namespace | `jupyter-notebook-validator-operator` | `openshift-operators` |
| Updates | Manual (update manifests) | Automatic (OLM) |
| Dependencies | None | OLM, CatalogSource |
| Flexibility | Full control | Limited to operator package |

**Ansible Role**: `validated_patterns_jupyter_validator`

**Role Tasks**:
- `tasks/main.yml` - Orchestration and cert-manager detection
- `tasks/deploy_operator.yml` - Kustomize deployment
- `tasks/verify_operator.yml` - Health checks and validation
- `tasks/cleanup_operator.yml` - Uninstallation and cleanup

**Playbooks**:
- `ansible/playbooks/install_jupyter_validator_operator.yml` - Installation playbook
- `ansible/playbooks/uninstall_jupyter_validator_operator.yml` - Cleanup playbook

### Integration with Existing Infrastructure

**Storage Integration** (Updated 2025-12-01):
- Validation pods use same storage classes as workbenches (gp3-csi)
- **NEW**: PVC mounting enables persistent model storage across validation runs
- **NEW**: Models can be stored in PVCs and accessed by multiple notebooks
- **NEW**: Integration with ADR-024 (External Secrets for Model Storage) and ADR-025 (Object Store)
- Notebook artifacts stored in persistent volumes
- Integration with existing ODF/NooBaa for model artifacts
- **Workflow**: Train models in notebooks → Store in PVCs → Deploy to KServe from PVCs

**RBAC Integration**:
- NotebookValidationJob CRDs use existing service accounts
- Validation pods inherit workbench security context
- Integration with OpenShift RBAC policies
- **NEW**: PVC access requires appropriate RBAC permissions for validation pods

**Monitoring Integration**:
- Operator exposes Prometheus metrics
- Validation job status tracked via CRD conditions
- Integration with existing Grafana dashboards
- **NEW**: Volume usage metrics tracked for model storage PVCs

## Consequences

### Positive Consequences

- ✅ **Declarative Management**: NotebookValidationJob CRDs provide declarative notebook validation
- ✅ **Resource Isolation**: Per-notebook resource requests/limits prevent resource contention
- ✅ **Git Integration**: Native support for public and private Git repositories
- ✅ **Credential Management**: Kubernetes secret integration for secure credential handling
- ✅ **Execution Tracking**: CRD status provides clear notebook execution history
- ✅ **Scalability**: Independent validation pods scale horizontally
- ✅ **Artifact Collection**: Automatic log collection and status reporting
- ✅ **Webhook Validation**: cert-manager integration for secure webhooks
- ✅ **NEW (2025-12-01) - Persistent Model Storage**: PVC mounting enables models to persist across validation runs
- ✅ **NEW (2025-12-01) - Model Sharing**: Multiple notebooks can access shared model repository via PVCs
- ✅ **NEW (2025-12-01) - Training-to-Deployment Pipeline**: Seamless workflow from training to KServe deployment
- ✅ **NEW (2025-12-01) - GPU Support**: Full GPU support for model training notebooks with persistent storage

### Negative Consequences

- ⚠️ **New Operator Dependency**: Additional operator to manage and maintain
- ⚠️ **cert-manager Requirement**: Requires cert-manager v1.13+ installation
- ⚠️ **Migration Effort**: Migrate 30+ notebooks from Tekton to CRDs
- ⚠️ **Learning Curve**: Team needs to learn NotebookValidationJob CRD spec
- ⚠️ **Operator Maintenance**: Custom operator requires version upgrades
- ⚠️ **NEW (2025-12-01) - Storage Management**: Additional PVC management and capacity planning required
- ⚠️ **NEW (2025-12-01) - RBAC Complexity**: Volume access requires additional RBAC configuration

### Migration Strategy

**Phase 1: Operator Deployment (Week 1)**
1. Install cert-manager (if not present)
2. Deploy Jupyter Notebook Validator Operator via Helm
3. Verify operator installation and CRD registration
4. Create test NotebookValidationJob for tier1-simple notebooks

**Phase 2: Tier Migration (Week 2-3)**
1. Migrate tier1-simple notebooks (hello-world, basic operations)
2. Migrate tier2-intermediate notebooks (data collection, preprocessing)
3. Migrate tier3-advanced notebooks (anomaly detection, model training)
4. Keep Tekton infrastructure validation tasks (prerequisites, operators, storage)

**Phase 3: Full Integration (Week 4)**
1. Update Ansible roles (create `validated_patterns_notebooks`)
2. Update documentation (notebooks/README.md, migration guide)
3. Remove Tekton notebook execution tasks (retain infrastructure validation)
4. Deploy production NotebookValidationJobs for all 30 notebooks

## Implementation Tasks

1. ✅ Create ADR-029 (this document)
2. [ ] Update ADR-021 to mark notebook validation as superseded
3. [ ] Create `validated_patterns_notebooks` Ansible role
   - Tasks: Install operator, verify cert-manager, create CRDs
4. [ ] Update `validated_patterns_validate` role
   - Add NotebookValidationJob status checks
   - Remove Tekton notebook execution tasks
5. [ ] Create migration guide (docs/NOTEBOOK-VALIDATION-MIGRATION.md)
6. [ ] Update notebooks/README.md with CRD workflow
7. [ ] Update tekton/README.md to clarify infrastructure-only scope
8. [ ] Create NotebookValidationJob manifests for all 30 notebooks
9. [ ] Test operator deployment on development cluster
10. [ ] Migrate tier1-simple notebooks first (hello-world)
11. [ ] Document rollback procedures

## Related ADRs

### Direct Dependencies
- **ADR-021**: Tekton Pipeline for Post-Deployment Validation (SUPERSEDED for notebook validation)
  - Tekton retains infrastructure validation responsibilities
  - Notebook execution moved to operator-based approach
  - **Relationship**: ADR-029 supersedes notebook validation from ADR-021
- **ADR-019**: Validated Patterns Framework Adoption
  - Operator deployment via Helm and ArgoCD
  - Integration with existing deployment workflows
  - **Relationship**: Operator deployed as part of Validated Patterns framework
- **ADR-026**: Secrets Management Automation
  - Integration with External Secrets Operator for Git credentials
  - **Relationship**: Git credentials managed via External Secrets
- **ADR-011**: Self-Healing Workbench Base Image
  - Validation pods use same container images as workbenches
  - **Relationship**: Shared container image strategy

### Storage and Model Management (NEW - 2025-12-01)
- **ADR-024**: External Secrets for Model Storage
  - **Relationship**: PVC-based model storage complements S3-based storage
  - **Integration**: Models can be stored in PVCs during training, then uploaded to S3 for serving
- **ADR-025**: OpenShift Object Store for Model Serving
  - **Relationship**: PVCs provide local storage, S3 provides serving storage
  - **Workflow**: Train in PVC → Upload to S3 → Serve via KServe
- **ADR-035**: Storage Strategy for Self-Healing Platform
  - **Relationship**: Uses gp3-csi storage class for model PVCs
  - **Integration**: Consistent storage strategy across platform
- **ADR-004**: KServe for Model Serving Infrastructure
  - **Relationship**: Models trained in notebooks with PVCs deployed to KServe
  - **Workflow**: Notebook validation → Model storage → KServe deployment

### Validation and Testing
- **ADR-032**: Infrastructure Validation Notebook for User Readiness
  - **Relationship**: Tier 1 validation notebook executed via this operator
  - **Integration**: Platform readiness validation before notebook execution

## References

- [Jupyter Notebook Validator Operator - Installation Guide](https://raw.githubusercontent.com/tosin2013/jupyter-notebook-validator-operator/refs/heads/release-4.18/helm/jupyter-notebook-validator-operator/INSTALLATION.md)
- [Jupyter Notebook Validator Operator - GitHub Repository](https://github.com/tosin2013/jupyter-notebook-validator-operator)
- [OpenShift cert-manager Documentation](https://docs.openshift.com/container-platform/latest/security/cert_manager_operator/index.html)
- [Validated Patterns Framework](https://validatedpatterns.io/)

## Approval

- **Architecture Team**: Proposed
- **ML Engineering**: Pending Review
- **DevOps Team**: Pending Review
- **Date**: 2025-11-18
