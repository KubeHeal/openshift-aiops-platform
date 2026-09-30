# ADR-064: Three-Tier Distribution Strategy

## Status

Accepted

## Date

2026-09-30

## Context

The OpenShift AI Ops Self-Healing Platform currently requires an 18-step fork-and-deploy workflow (CLAUDE.md Section 3). While comprehensive, this is a distribution barrier for adoption. Different personas have different expectations for how they consume platform software:

- **Cluster administrators** expect to install operators from OperatorHub and create a single CR.
- **Platform architects** expect GitOps-managed deployment with ArgoCD for full control over configuration drift.
- **Power users and developers** expect to run `helm install` directly during evaluation or CI.

Research (September 2026) confirmed no AIOps self-healing operator exists on OperatorHub. The `KubeHeal/kubeheal-operator` repository was created (issue #103) as a Helm-based operator wrapping `charts/hub/` using `operator-sdk init --plugins helm`. The Validated Patterns Sandbox submission (ADR-060) addresses the GitOps consumption model. Neither path replaces the other; they serve different personas and deployment philosophies.

### Single Source of Truth

The canonical Helm chart lives at `charts/hub/` in the `openshift-aiops-platform` repository. The kubeheal-operator embeds a copy of this chart at `helm-charts/self-healing-platform/`. A sync script (`scripts/sync-operator-chart.sh`) keeps the operator's copy current. This avoids maintaining two divergent chart codebases.

### Current kubeheal-operator State

The `KubeHeal/kubeheal-operator` repository contains:

| Component | Description |
|-----------|-------------|
| `watches.yaml` | Maps `SelfHealingPlatform` CR (group `aiops.kubeheal.io/v1alpha1`) to the embedded chart |
| `Dockerfile` | Builds from `quay.io/operator-framework/helm-operator:v1.42.3` |
| `config/crd/` | CRD schema for `SelfHealingPlatform` (`x-kubernetes-preserve-unknown-fields: true`) |
| `bundle/` | OLM bundle with CSV, RBAC roles (admin, editor, viewer), scorecard config |
| `config/samples/` | Sample CRs for HA and SNO topologies |
| `.github/workflows/ci.yml` | Lint, build, bundle-validate; release pipeline triggered by `v*` tags |

Open issues: CI cleanup (#1), v0.1.0 Quay publish (#2), OperatorHub submission (#3).

## Decision

Adopt a **three-tier distribution strategy** where the same `charts/hub/` Helm chart powers all three consumption models.

### Tier 1: OperatorHub (kubeheal-operator)

**Target persona**: Cluster administrators who want a managed install.

**How it works**:

1. User installs the `kubeheal-operator` from OperatorHub (community-operators-prod catalog).
2. The operator deploys the `helm-operator` runtime which watches for `SelfHealingPlatform` CRs.
3. User creates a `SelfHealingPlatform` CR with desired configuration (topology, storage, models).
4. The Helm operator reconciles the CR by rendering `charts/hub/` templates with the CR's `.spec` as values.

**Deployment steps** (2 steps, down from 18):

```yaml
# Step 1: Install operator from OperatorHub (or CLI)
# Step 2: Create the CR
apiVersion: aiops.kubeheal.io/v1alpha1
kind: SelfHealingPlatform
metadata:
  name: kubeheal
  namespace: self-healing-platform
spec:
  cluster:
    topology: "ha"
  coordinationEngine:
    enabled: true
  modelServing:
    enabled: true
  objectStore:
    enabled: true
    backend: "aws-s3"
```

**Release pipeline**: Tag `v*` in `kubeheal-operator` triggers CI to build and push three images to Quay.io:

- `quay.io/takinosh/kubeheal-operator:vX.Y.Z` (operator image)
- `quay.io/takinosh/kubeheal-operator-bundle:vX.Y.Z` (OLM bundle)
- `quay.io/takinosh/kubeheal-operator-catalog:vX.Y.Z` (file-based catalog)

### Tier 2: Validated Patterns (ADR-060)

**Target persona**: Platform architects who want GitOps-managed deployment.

**How it works**:

1. User forks `openshift-aiops-platform`, customizes `values-hub.yaml`.
2. Validated Patterns Operator creates an ArgoCD Application pointing to the fork.
3. ArgoCD renders `charts/hub/` with the merged values and deploys all resources.
4. Ongoing drift detection and auto-sync via ArgoCD.

**Status**: Decision accepted (ADR-060); upstream VP catalog PR not yet submitted.

### Tier 3: Direct Helm Install

**Target persona**: Power users evaluating the platform, CI pipelines, and custom integrations.

**How it works**:

```bash
helm install self-healing-platform charts/hub/ \
  --namespace self-healing-platform \
  --create-namespace \
  -f values-hub.yaml
```

**Status**: Works today. Documented in README.md.

### Chart Sync Workflow

```
openshift-aiops-platform/charts/hub/  (canonical source)
        │
        │  scripts/sync-operator-chart.sh
        │  (or: make sync-operator-chart)
        ▼
kubeheal-operator/helm-charts/self-healing-platform/  (operator copy)
        │
        │  git tag v0.x.y → CI pipeline
        ▼
Quay.io images → OperatorHub catalog
```

The sync script:

1. Clones `KubeHeal/kubeheal-operator` to a temp directory
2. Replaces `helm-charts/self-healing-platform/` with current `charts/hub/` content
3. Excludes VP-specific files (`argocd-application.yaml`, `argocd-application-hub.yaml`)
4. Commits referencing the source repo SHA
5. Optionally pushes (`--push` flag)

### Future Evolution: Go-Based Operator

The Helm-based operator handles day-1 installation but cannot manage runtime state. Issue #116 proposes a Go-based operator (Operator SDK Go plugin) that introduces additional CRDs:

| CRD | Purpose |
|-----|---------|
| `SelfHealingPlatform` | Top-level desired state (same as Helm operator, but with structured status) |
| `HealingPolicy` | Remediation rules, escalation chains, conflict resolution priority |
| `ModelTrainingRun` | Wraps Tekton PipelineRun + model evaluation + canary deployment |

The Go operator depends on evaluation of:

- MCP Lifecycle Operator (#111)
- EvalHub (#112)
- Canary Rollout (#113)
- MLflow (#114)
- Model Catalog (#115)

The migration path is: Helm operator v0.x ships to OperatorHub first, Go operator replaces it at v1.0 when runtime CRDs are ready. The `SelfHealingPlatform` CRD API contract is preserved across both.

## Consequences

### Positive

- **Reduced adoption friction**: Cluster admins go from 18 steps to 2 via OperatorHub.
- **Single chart, three paths**: No code duplication; all tiers render the same templates.
- **Clear persona targeting**: Each tier has a defined audience and documentation path.
- **Progressive complexity**: Users start with Tier 1, graduate to Tier 2/3 as needs grow.
- **OperatorHub visibility**: First AIOps self-healing operator listed publicly.

### Negative

- **Sync overhead**: Chart changes in this repo must be synced to kubeheal-operator before release. Mitigated by the sync script and Makefile target.
- **Two repos to maintain**: kubeheal-operator has its own CI, issues, and release cycle. Mitigated by keeping the chart canonical in one place.
- **CRD schema is unstructured**: The Helm operator uses `x-kubernetes-preserve-unknown-fields: true`, meaning the CRD does not validate `.spec` fields. The Go operator (#116) will add typed validation.

### Neutral

- VP submission (ADR-060) and OperatorHub submission are independent workstreams. Neither blocks the other.
- Direct Helm install (Tier 3) requires no additional tooling or infrastructure.

## References

- Issue #103: Create kubeheal-operator repository (closed)
- Issue #104: Standalone Helm chart extraction (closed, superseded by kubeheal-operator)
- Issue #116: Go-based operator design (backlog)
- ADR-060: Validated Patterns Sandbox Submission
- ADR-019: Validated Patterns Framework Adoption
- `KubeHeal/kubeheal-operator`: https://github.com/KubeHeal/kubeheal-operator
- Operator SDK Helm tutorial: https://sdk.operatorframework.io/docs/building-operators/helm/tutorial/
- community-operators-prod: https://github.com/redhat-openshift-ecosystem/community-operators-prod
