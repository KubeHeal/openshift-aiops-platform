# Documentation Automation and Expansion Plan

**Date**: 2026-05-18
**Status**: Proposed
**Related**: Documentation Audit Phases 4-5

---

## Executive Summary

This plan addresses three key areas:

1. **Phase 4**: Expand underpopulated documentation (API reference, architecture overview)
2. **Phase 5**: Reorganize root-level files into Diataxis framework
3. **Automation**: GitHub Actions workflows to keep documentation up-to-date

**Timeline**: 8-13 hours total (3-5 hours Phase 4, 3-5 hours Phase 5, 2-3 hours automation)

---

## Phase 4: Expand Underpopulated Documentation

### Current State

**Underpopulated Sections**:
- `docs/reference/api-documentation.md` - 824-byte stub
- `docs/explanation/architecture-overview.md` - 822-byte stub
- Reference section: Only 3 files total
- Explanation section: Only 2 files total

### 4.1: Expand API Documentation

**File**: `docs/reference/api-documentation.md`

**Content to Add**:

#### Coordination Engine API

```markdown
## Coordination Engine REST API

Base URL: `http://coordination-engine.self-healing-platform.svc.cluster.local:8080`

### Health Endpoints

**GET /health**
- **Purpose**: Health check endpoint
- **Response**: `{"status": "healthy", "version": "1.0.0", "timestamp": "2025-12-09T18:00:00.000Z"}`
- **Use Case**: Kubernetes liveness/readiness probes

**GET /metrics**
- **Purpose**: Prometheus metrics endpoint
- **Response**: Prometheus text format
- **Metrics Exposed**:
  - `coordination_engine_anomalies_total` - Total anomalies processed
  - `coordination_engine_remediations_total` - Total remediations triggered
  - `coordination_engine_response_time_seconds` - API response times

### Anomaly Management

**POST /api/v1/anomalies**
- **Purpose**: Submit detected anomaly for analysis
- **Authentication**: None (internal cluster traffic)
- **Request Body**:
  ```json
  {
    "timestamp": "2025-12-09T18:00:00Z",
    "type": "cpu_spike|memory_leak|disk_full|custom",
    "severity": "low|medium|high|critical",
    "source": "prometheus|custom|ai-model",
    "details": {
      "namespace": "string",
      "pod": "string",
      "metric": "string",
      "value": "number",
      "threshold": "number"
    },
    "confidence_score": 0.0-1.0,
    "recommended_action": "string (optional)"
  }
  ```
- **Response**: `{"anomaly_id": "anom-12345", "status": "accepted", "queued_at": "timestamp"}`
- **Error Codes**:
  - 400: Invalid anomaly format
  - 500: Internal server error

**GET /api/v1/anomalies/{id}**
- **Purpose**: Retrieve anomaly details and remediation status
- **Response**:
  ```json
  {
    "anomaly_id": "anom-12345",
    "status": "pending|processing|resolved|failed",
    "created_at": "timestamp",
    "remediation": {
      "action": "string",
      "triggered_at": "timestamp",
      "status": "string"
    }
  }
  ```

### Remediation Actions

**POST /api/v1/remediations**
- **Purpose**: Manually trigger remediation
- **Request Body**:
  ```json
  {
    "anomaly_id": "anom-12345",
    "action": "scale_up|restart_pod|apply_config",
    "parameters": {
      "replicas": 3,
      "namespace": "string"
    }
  }
  ```

## KServe InferenceService API

Base URL: `https://{inferenceservice-name}-{namespace}.apps.{cluster-domain}`

### Model Inference

**POST /v1/models/{model-name}:predict**
- **Purpose**: Get predictions from deployed ML model
- **Models**:
  - `anomaly-detector` - Isolation Forest anomaly detection
  - `predictive-analytics` - LSTM predictive analytics
- **Request Body**:
  ```json
  {
    "instances": [
      [1.0, 2.0, 3.0]  // Feature vector
    ]
  }
  ```
- **Response**:
  ```json
  {
    "predictions": [-1]  // -1 = anomaly, 1 = normal
  }
  ```

**GET /v1/models/{model-name}**
- **Purpose**: Get model metadata
- **Response**: Model version, ready status, runtime info

## External Secrets Operator API

Uses Kubernetes Custom Resources (CRs), not REST API.

### Key Custom Resources

**ExternalSecret**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: model-storage-secret
  namespace: self-healing-platform
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: kubernetes-backend
    kind: SecretStore
  target:
    name: model-storage
  data:
    - secretKey: ACCESS_KEY_ID
      remoteRef:
        key: model-storage
        property: BUCKET_ACCESS_KEY_ID
```

## Tekton Pipeline API

**Trigger Pipeline Run**:
```bash
tkn pipeline start model-training-pipeline \
  -p model-name=anomaly-detector \
  -p notebook-path=notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb \
  -n self-healing-platform --showlog
```

**Check Pipeline Run Status**:
```bash
tkn pipelinerun list -n self-healing-platform
tkn pipelinerun logs {pipelinerun-name} -n self-healing-platform
```

## ArgoCD Application API

**Get Application Status**:
```bash
oc get application self-healing-platform -n self-healing-platform-hub -o yaml
```

**Trigger Sync**:
```bash
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite
```

## Authentication

**Internal APIs** (Coordination Engine, KServe):
- No authentication required for cluster-internal traffic
- Network policies restrict access to same namespace

**External APIs** (InferenceService HTTPS):
- OpenShift OAuth authentication via Routes
- Service Mesh mTLS (if enabled)

## Rate Limiting

**Coordination Engine**:
- No built-in rate limiting
- Kubernetes resource limits apply (CPU/memory)

**KServe**:
- Horizontal Pod Autoscaler (HPA) scales based on load
- Default: min 1, max 5 replicas

## Monitoring and Observability

**Prometheus Metrics**:
- Coordination Engine: `http://coordination-engine:8080/metrics`
- KServe: Automatic via Service Mesh
- Tekton: Built-in Prometheus integration

**Logs**:
```bash
# Coordination Engine
oc logs -n self-healing-platform deployment/coordination-engine --tail=100 -f

# KServe Predictor
oc logs -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=anomaly-detector \
  -c kserve-container --tail=100 -f

# Tekton Pipeline Runs
tkn pipelinerun logs {pipelinerun-name} -n self-healing-platform -f
```

## Related Documentation

- [ADR-038: Go Coordination Engine Migration](../adrs/038-go-coordination-engine-migration.md)
- [ADR-004: KServe for Model Serving Infrastructure](../adrs/004-kserve-model-serving.md)
- [ADR-053: Tekton Pipelines for Model Training](../adrs/053-tekton-model-training-pipelines.md)
- [How-To: Test Custom Applications with MCP](../how-to/test-custom-applications-with-mcp.md)
```

**Sources**:
- Coordination Engine: External Go repo (https://github.com/KubeHeal/openshift-coordination-engine)
- KServe: Standard KServe v2 protocol
- ADR-038: Coordination Engine architecture
- How-to guides: Integration examples

**Effort**: 2-3 hours

---

### 4.2: Expand Architecture Overview

**File**: `docs/explanation/architecture-overview.md`

**Content to Add**:

```markdown
# Architecture Overview

This document explains the core concepts, design decisions, and architectural patterns of the OpenShift AI Ops Self-Healing Platform.

## Introduction

The platform implements a **hybrid self-healing approach** that combines:
- **Deterministic automation**: Rule-based remediation for known issues (Machine Config Operator)
- **AI-driven analysis**: ML models for anomaly detection and predictive analytics

This hybrid model provides:
- ✅ **Fast response** for known issues (deterministic layer)
- ✅ **Adaptive learning** for new patterns (AI layer)
- ✅ **Conflict resolution** when both layers disagree

## Core Concepts

### 1. Hybrid Self-Healing

**Problem**: Pure deterministic approaches can't handle novel issues. Pure AI approaches are slow and unpredictable.

**Solution**: Layered architecture with coordination engine:

```
┌─────────────────────────────────────────────────────────────┐
│                 Self-Healing Platform                        │
├─────────────────────────────────────────────────────────────┤
│  Coordination Engine (Go-based)                             │
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

**Data Flow**:
1. Prometheus collects metrics from cluster
2. Anomaly detection models analyze metrics
3. Anomalies submitted to coordination engine
4. Coordination engine decides: deterministic or AI-driven remediation
5. Remediation action executed (scale pods, restart services, apply configs)
6. Feedback loop: success/failure logged for model retraining

**Reference**: [ADR-002: Hybrid Deterministic-AI Self-Healing Approach](../adrs/002-hybrid-self-healing-approach.md)

### 2. GitOps-Driven Deployment

**Problem**: Manual deployments are error-prone and hard to reproduce.

**Solution**: Validated Patterns Framework with ArgoCD

```
┌──────────────────────────────────────────────────────────┐
│  Git Repository (Source of Truth)                        │
│  ├─ values-global.yaml                                   │
│  ├─ values-hub.yaml                                      │
│  ├─ charts/hub/ (Helm chart)                            │
│  └─ k8s/ (Kubernetes manifests)                         │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  Validated Patterns Operator                             │
│  Creates ArgoCD Application CR                           │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  ArgoCD (hub-gitops)                                     │
│  ├─ Syncs from Git repository                           │
│  ├─ Manages cluster-scoped resources (ClusterRole)      │
│  ├─ Deploys operators, workloads, notebooks             │
│  └─ Auto-heals drift (reconciliation loop)              │
└──────────────────────────────────────────────────────────┘
```

**Key Benefits**:
- **Declarative**: Infrastructure as code
- **Auditable**: Git history = deployment history
- **Reproducible**: Same Git commit = same cluster state
- **Self-healing**: ArgoCD auto-corrects drift

**Reference**: [ADR-019: Validated Patterns Framework Adoption](../adrs/019-validated-patterns-framework-adoption.md)

### 3. Model Serving with KServe

**Problem**: ML models need scalable, production-grade serving infrastructure.

**Solution**: KServe InferenceServices

```
Jupyter Notebook → Train Model → Upload to S3 (NooBaa) → InferenceService CR → KServe Predictor Pod
                                                                                      │
                                                                                      ▼
                                                                            HTTPS Endpoint
                                                                    (anomaly-detector.apps.cluster.com)
```

**User-Deployed Models**:
- Platform users train their own ML models in notebooks
- Models uploaded to S3 (NooBaa object storage)
- InferenceService CR created via Tekton pipeline
- KServe deploys model as scalable HTTP/gRPC service

**Extensible Registry**:
Users can register custom models in `values-hub.yaml`:
```yaml
inferenceServices:
  custom-models:
    - name: my-model
      storageUri: s3://model-storage/my-model
      runtime: sklearn
```

**References**:
- [ADR-004: KServe for Model Serving Infrastructure](../adrs/004-kserve-model-serving.md)
- [ADR-039: User-Deployed KServe Models](../adrs/039-user-deployed-kserve-models.md)
- [ADR-040: Extensible KServe Model Registry](../adrs/040-extensible-kserve-model-registry.md)

### 4. Secrets Management

**Problem**: Hardcoded secrets in Git are insecure. Manual secret creation is error-prone.

**Solution**: External Secrets Operator with Kubernetes backend

```
SecretStore CR → Kubernetes Backend (Secret in openshift-storage) → ExternalSecret CR → Synced Secret
```

**Example**:
1. ODF creates ObjectBucketClaim for model storage
2. Secret `model-storage` created in `openshift-storage` namespace
3. ExternalSecret CR references this secret
4. External Secrets Operator syncs to `self-healing-platform` namespace
5. Notebooks and pipelines use synced secret

**Benefits**:
- ✅ No secrets in Git
- ✅ Automated secret rotation
- ✅ Centralized secret management
- ✅ Declarative secret configuration

**Reference**: [ADR-026: Secrets Management Automation](../adrs/026-secrets-management-automation.md) (**MANDATORY**)

### 5. Notebook-Based Development

**Problem**: Data scientists need familiar tools, but production requires automation.

**Solution**: Jupyter notebooks + Jupyter Notebook Validator Operator

```
Jupyter Workbench (Development) → Notebook File (.ipynb) → Tekton Pipeline → Validator Operator → Production Job
```

**Notebook Tiers**:
- **Tier 1**: Infrastructure validation (platform readiness)
- **Tier 2**: Data collection and preprocessing
- **Tier 3**: Model training and deployment

**Automated Execution**:
- Tekton pipeline triggers notebook validation
- Validator Operator runs notebook as Kubernetes Job
- Results validated (cell outputs, no errors)
- Model artifacts uploaded to S3
- InferenceService created automatically

**References**:
- [ADR-012: Notebook Architecture for End-to-End Workflows](../adrs/012-notebook-architecture-for-end-to-end-workflows.md)
- [ADR-029: Jupyter Notebook Validator Operator](../adrs/029-jupyter-notebook-validator-operator.md)

## Design Decisions

### Why Hybrid Approach?

**Deterministic-Only Problems**:
- ❌ Can't handle novel issues
- ❌ Requires manual rule updates
- ❌ No learning from experience

**AI-Only Problems**:
- ❌ Slow cold-start (model training)
- ❌ Unpredictable behavior
- ❌ Hard to debug

**Hybrid Solution**:
- ✅ Fast response for known issues (deterministic)
- ✅ Adaptive learning for new patterns (AI)
- ✅ Coordination engine resolves conflicts
- ✅ Feedback loop improves both layers

### Why OpenShift AI?

**Alternatives Considered**:
- **Kubeflow**: More complex, not Red Hat supported
- **MLflow**: Tracking only, no serving
- **Custom solution**: Reinventing the wheel

**Why OpenShift AI**:
- ✅ Red Hat support and enterprise SLA
- ✅ Integrated with OpenShift (RBAC, networking, storage)
- ✅ KServe for model serving
- ✅ Jupyter notebooks for development
- ✅ GPU operator integration

**Reference**: [ADR-003: Red Hat OpenShift AI for ML Platform](../adrs/003-openshift-ai-ml-platform.md)

### Why Validated Patterns?

**Alternatives Considered**:
- **Helm-only**: No GitOps, manual management
- **Plain ArgoCD**: More setup, no patterns
- **Flux**: Similar to ArgoCD, less OpenShift integration

**Why Validated Patterns**:
- ✅ GitOps-driven (declarative)
- ✅ OpenShift-native
- ✅ Multi-cluster support (future)
- ✅ Proven deployment patterns
- ✅ Operator-based (easy to manage)

**Reference**: [ADR-019: Validated Patterns Framework Adoption](../adrs/019-validated-patterns-framework-adoption.md)

### Why Go for Coordination Engine?

**Previous**: Python/Flask (ADR-033, deprecated)

**Why Migrate to Go**:
- ✅ Better performance (compiled vs interpreted)
- ✅ Lower memory footprint
- ✅ Easier deployment (single binary)
- ✅ Better concurrency (goroutines)
- ✅ Stronger typing (compile-time safety)

**Reference**: [ADR-038: Go Coordination Engine Migration](../adrs/038-go-coordination-engine-migration.md)

## Trade-offs

### Complexity vs Flexibility

**Trade-off**: Hybrid architecture is more complex than pure deterministic or pure AI.

**Why Worth It**:
- Handles both known and unknown issues
- Better reliability than AI-only
- More adaptive than deterministic-only

### Platform Lock-in vs Integration

**Trade-off**: OpenShift AI ties us to Red Hat ecosystem.

**Why Worth It**:
- Enterprise support
- Deep OpenShift integration
- KServe is platform-agnostic (can migrate if needed)

**Mitigation**: User-deployed models (ADR-039) allow custom ML workflows outside OpenShift AI

### GitOps Strictness vs Development Speed

**Trade-off**: All changes require Git commits (slower than `kubectl apply`).

**Why Worth It**:
- Auditable deployments
- Reproducible environments
- Less configuration drift

**Mitigation**: Local Gitea option (ADR-028) for fast iteration in dev

## Comparison with Alternatives

| Approach | Pros | Cons |
|----------|------|------|
| **Our Hybrid Approach** | Fast + adaptive, handles known & unknown issues | More complex architecture |
| **Pure Deterministic** | Simple, predictable, fast | Can't handle novel issues, requires manual updates |
| **Pure AI** | Adaptive, learns new patterns | Slow cold-start, unpredictable, hard to debug |
| **Kubeflow-based** | Full ML platform | More complex than OpenShift AI, no Red Hat support |
| **Custom ML Platform** | Full control | Reinventing the wheel, maintenance burden |

## Integration Points

### External Systems

**Prometheus**:
- Metrics collection (cluster health, application metrics)
- Alert firing to AlertManager
- Query API for historical data

**ArgoCD**:
- Git repository sync
- Application deployment
- Health status reporting

**OpenShift AI**:
- Jupyter notebooks (development environment)
- KServe (model serving)
- GPU operator (accelerated training)

**MCP Server**:
- OpenShift Lightspeed integration
- Natural language cluster queries
- Tool exposure (cluster health, deployment status)

**Reference**: [ADR-036: Go-Based Standalone MCP Server](../adrs/036-go-based-standalone-mcp-server.md)

### Internal Services

**Coordination Engine** ↔ **KServe Predictors**:
- Anomaly detection results sent to coordination engine
- Remediation decisions trigger model inference

**Tekton Pipelines** ↔ **Jupyter Notebooks**:
- Pipelines trigger notebook execution
- Notebooks deploy models to KServe

**External Secrets Operator** ↔ **ODF**:
- Syncs S3 bucket credentials
- Provides model storage access

## Platform Agnosticism

**Goal**: Support both OpenShift and vanilla Kubernetes

**Current State**:
- ✅ KServe works on vanilla Kubernetes
- ✅ Tekton works on vanilla Kubernetes
- ⚠️ OpenShift AI is OpenShift-specific
- ⚠️ Machine Config Operator is OpenShift-specific

**User-Deployed Models** (ADR-039):
- Users bring their own ML models
- No dependency on OpenShift AI
- Works on any Kubernetes cluster

**Future**: Detect platform and adapt deployment (ADR-055)

## Further Reading

### Tutorials
- [Tutorial: Deploy on SNO](../tutorials/deploy-on-sno.md)
- [Tutorial: Train and Deploy Custom Models](../tutorials/custom-model-deployment.md)

### How-To Guides
- [How-To: Test Custom Applications with MCP](../how-to/test-custom-applications-with-mcp.md)
- [How-To: Deploy MCP Server for Lightspeed](../how-to/deploy-mcp-server-lightspeed.md)

### Reference
- [API Documentation](../reference/api-documentation.md)
- [Configuration Reference](../reference/configuration-reference.md)

### ADRs
- [ADR-002: Hybrid Deterministic-AI Self-Healing Approach](../adrs/002-hybrid-self-healing-approach.md)
- [ADR-019: Validated Patterns Framework Adoption](../adrs/019-validated-patterns-framework-adoption.md)
- [ADR-026: Secrets Management Automation](../adrs/026-secrets-management-automation.md)
- [ADR-038: Go Coordination Engine Migration](../adrs/038-go-coordination-engine-migration.md)
```

**Sources**:
- ADR-002: Hybrid approach
- ADR-019: Validated Patterns
- ADR-038: Go coordination engine
- README.md: Architecture diagram

**Effort**: 2-3 hours

---

### 4.3: Create New Reference Documents

**1. Configuration Reference**

**File**: `docs/reference/configuration-reference.md`

**Content**:
- Complete `values-hub.yaml` options with descriptions and defaults
- Complete `values-global.yaml` options
- Environment variables for all components
- Operator configuration (channel selection, install modes)
- Storage class configuration

**Effort**: 1-2 hours

**2. Troubleshooting Reference**

**File**: `docs/reference/troubleshooting-reference.md`

**Content**:
- Error code catalog (E001, E002, etc.)
- Common failure modes (quick lookup table)
- Symptoms → Solutions mapping
- Event message glossary
- Log message patterns

**Effort**: 1 hour

---

## Phase 5: Reorganize Root-Level Files

### Current State

**Root-Level Markdown Files** (11 total):
```
AGENTS.md                   # AI agent development guide (1,800+ lines)
CHANGELOG.md                # Release history
CLAUDE.md                   # AI agent quick reference (900+ lines)
CODE_OF_CONDUCT.md          # Community standards
CONTRIBUTING.md             # Contribution guidelines
DEPLOYMENT.md               # Complete deployment guide
DEPLOYMENT-QUICKSTART.md    # Quick deployment guide
OPERATOR_VERSIONS.md        # Version compatibility matrix
README.md                   # Quick start guide
RELEASE.md                  # Release process
VALUES-FILES-GUIDE.md       # Values files configuration
```

### 5.1: Categorization Strategy

**Keep at Root** (5 files):
- `README.md` - Entry point, must stay at root
- `CONTRIBUTING.md` - Standard GitHub location
- `CODE_OF_CONDUCT.md` - Standard GitHub location
- `CHANGELOG.md` - Standard location
- `CLAUDE.md` - AI agent instructions (referenced by .claude/CLAUDE.md)

**Move to docs/** (6 files):

#### Move to `docs/how-to/`
- `DEPLOYMENT.md` → `docs/how-to/complete-deployment-guide.md`
- `DEPLOYMENT-QUICKSTART.md` → `docs/how-to/quick-deployment.md`
- `VALUES-FILES-GUIDE.md` → `docs/how-to/configure-values-files.md`

#### Move to `docs/reference/`
- `OPERATOR_VERSIONS.md` → `docs/reference/operator-versions.md`

#### Move to `docs/explanation/`
- `AGENTS.md` → `docs/explanation/ai-agent-development-guide.md`

#### Move to `docs/` (general)
- `RELEASE.md` → `docs/RELEASE.md`

### 5.2: Migration Steps

**Step 1**: Create redirect files at old locations

```bash
# Example: DEPLOYMENT.md
cat > DEPLOYMENT.md <<'EOF'
# Deployment Guide

**⚠️ MOVED**: This documentation has been reorganized.

Please see: [Complete Deployment Guide](docs/how-to/complete-deployment-guide.md)

**Why moved?** Reorganization to follow [Diataxis documentation framework](https://diataxis.fr/).

**Quick links**:
- [Quick Deployment](docs/how-to/quick-deployment.md)
- [SNO Deployment](docs/how-to/deploy-on-sno.md)
- [Fresh Cluster Deployment](docs/guides/FRESH-CLUSTER-DEPLOYMENT.md)
EOF
```

**Step 2**: Move files with `git mv`

```bash
git mv DEPLOYMENT.md docs/how-to/complete-deployment-guide.md
git mv DEPLOYMENT-QUICKSTART.md docs/how-to/quick-deployment.md
git mv VALUES-FILES-GUIDE.md docs/how-to/configure-values-files.md
git mv OPERATOR_VERSIONS.md docs/reference/operator-versions.md
git mv AGENTS.md docs/explanation/ai-agent-development-guide.md
git mv RELEASE.md docs/RELEASE.md
```

**Step 3**: Update internal links

```bash
# Find all markdown files referencing moved files
grep -r "DEPLOYMENT.md" --include="*.md" docs/
grep -r "AGENTS.md" --include="*.md" docs/
grep -r "OPERATOR_VERSIONS.md" --include="*.md" docs/

# Update links in each file (automated with sed or manual editing)
```

**Step 4**: Update `mkdocs.yml` navigation

```yaml
nav:
  - Home: index.md
  - Quick Start: quick-start.md

  - How-To Guides:
      - Complete Deployment: how-to/complete-deployment-guide.md
      - Quick Deployment: how-to/quick-deployment.md
      - Configure Values Files: how-to/configure-values-files.md
      - Deploy on SNO: how-to/deploy-on-sno.md
      # ... existing how-to guides

  - Reference:
      - API Documentation: reference/api-documentation.md
      - Configuration Reference: reference/configuration-reference.md
      - Operator Versions: reference/operator-versions.md
      - Troubleshooting Reference: reference/troubleshooting-reference.md

  - Explanation:
      - Architecture Overview: explanation/architecture-overview.md
      - AI Agent Development: explanation/ai-agent-development-guide.md
      # ... existing explanation docs
```

**Step 5**: Update README.md links

```markdown
## 📚 Documentation

- **Getting Started**: [Quick Start](docs/quick-start.md)
- **Deployment**:
  - [Complete Deployment Guide](docs/how-to/complete-deployment-guide.md)
  - [Quick Deployment](docs/how-to/quick-deployment.md)
  - [SNO Deployment](docs/how-to/deploy-on-sno.md)
- **Reference**:
  - [API Documentation](docs/reference/api-documentation.md)
  - [Operator Versions](docs/reference/operator-versions.md)
- **For AI Agents**:
  - [CLAUDE.md](CLAUDE.md) - Quick reference
  - [AI Agent Development Guide](docs/explanation/ai-agent-development-guide.md) - Comprehensive guide
```

**Effort**: 3-5 hours

---

## GitHub Actions Automation

### 3.1: Link Checker Workflow

**File**: `.github/workflows/link-checker.yml`

**Purpose**: Detect broken internal and external links

```yaml
name: Documentation Link Checker

on:
  push:
    branches: [ main ]
    paths:
      - '**.md'
  pull_request:
    branches: [ main ]
    paths:
      - '**.md'
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday

jobs:
  link-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check internal links
        uses: gaurav-nelson/github-action-markdown-link-check@v1
        with:
          config-file: '.github/markdown-link-check-config.json'
          use-quiet-mode: 'yes'

      - name: Report broken links
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: '🔗 Broken documentation links detected',
              body: 'The link checker found broken links. See workflow run for details.',
              labels: ['documentation', 'broken-links']
            })
```

**Config**: `.github/markdown-link-check-config.json`

```json
{
  "ignorePatterns": [
    {
      "pattern": "^http://localhost"
    },
    {
      "pattern": "^https://cluster.*svc.cluster.local"
    }
  ],
  "timeout": "20s",
  "retryOn429": true,
  "retryCount": 3,
  "aliveStatusCodes": [200, 206]
}
```

**Effort**: 30 minutes

---

### 3.2: Version Consistency Checker

**File**: `.github/workflows/version-check.yml`

**Purpose**: Ensure OpenShift and operator versions are consistent across all docs

```yaml
name: Version Consistency Check

on:
  push:
    branches: [ main ]
    paths:
      - 'docs/**/*.md'
      - 'OPERATOR_VERSIONS.md'
      - 'README.md'
  pull_request:
    branches: [ main ]

jobs:
  version-consistency:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check OpenShift version consistency
        run: |
          # Extract version from OPERATOR_VERSIONS.md (source of truth)
          EXPECTED_VERSIONS=$(grep "| 4\." docs/reference/operator-versions.md | awk -F'|' '{print $2}' | tr -d ' ')

          # Check for outdated 4.18 references (should have maintenance-only note)
          OUTDATED=$(grep -rn "4\.18" docs/ README.md DEPLOYMENT*.md | grep -v "maintenance-only" | grep -v "4.19-4.21" || true)

          if [ ! -z "$OUTDATED" ]; then
            echo "❌ Found outdated 4.18 references without maintenance-only note:"
            echo "$OUTDATED"
            exit 1
          fi

          echo "✅ Version consistency check passed"

      - name: Check operator version consistency
        run: |
          # Extract operator versions from docs/reference/operator-versions.md
          GITOPS_VERSION=$(grep "GitOps" docs/reference/operator-versions.md | grep "4.20" | awk -F'|' '{print $7}' | tr -d ' ')
          PIPELINES_VERSION=$(grep "Pipelines" docs/reference/operator-versions.md | grep "4.20" | awk -F'|' '{print $6}' | tr -d ' ')

          # Check deployment guides for consistency
          GUIDE_GITOPS=$(grep "gitops" docs/guides/NEW-CLUSTER-DEPLOYMENT.md | grep -o "v[0-9]*\.[0-9]*\.[0-9]*" || echo "not-found")

          if [ "$GUIDE_GITOPS" != "$GITOPS_VERSION" ]; then
            echo "⚠️  GitOps version mismatch: Guide has $GUIDE_GITOPS, source of truth is $GITOPS_VERSION"
          fi
```

**Effort**: 1 hour

---

### 3.3: ADR Status Checker

**File**: `.github/workflows/adr-status-check.yml`

**Purpose**: Ensure ADR statuses are consistent (deprecated ADRs marked in index)

```yaml
name: ADR Status Consistency

on:
  push:
    branches: [ main ]
    paths:
      - 'docs/adrs/*.md'
  pull_request:
    branches: [ main ]

jobs:
  adr-status-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check deprecated ADRs
        run: |
          # Find ADRs with DEPRECATED status in frontmatter
          DEPRECATED_ADRS=$(grep -l "Status.*DEPRECATED" docs/adrs/*.md | xargs -I {} basename {})

          # Check if they're marked in README.md
          for adr in $DEPRECATED_ADRS; do
            if ! grep -q "$adr.*DEPRECATED" docs/adrs/README.md; then
              echo "❌ ADR $adr is deprecated but not marked in index"
              exit 1
            fi
          done

          echo "✅ All deprecated ADRs are properly marked in index"

      - name: Check superseded ADRs
        run: |
          # Find ADRs with SUPERSEDED status
          SUPERSEDED_ADRS=$(grep -l "Status.*SUPERSEDED" docs/adrs/*.md | xargs -I {} basename {})

          # Check if superseding ADR is referenced
          for adr in $SUPERSEDED_ADRS; do
            if ! grep -q "Superseded by" docs/adrs/$adr; then
              echo "⚠️  ADR $adr is superseded but doesn't reference superseding ADR"
            fi
          done
```

**Effort**: 30 minutes

---

### 3.4: Documentation Freshness Checker

**File**: `.github/workflows/doc-freshness.yml`

**Purpose**: Detect stale documentation (not updated in 6+ months)

```yaml
name: Documentation Freshness

on:
  schedule:
    - cron: '0 0 1 * *'  # Monthly on 1st

jobs:
  freshness-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full git history

      - name: Find stale docs
        run: |
          # Find markdown files not updated in 180 days
          STALE_DOCS=$(find docs -name "*.md" -type f -exec sh -c '
            LAST_COMMIT=$(git log -1 --format="%ct" -- "$1")
            NOW=$(date +%s)
            DAYS_OLD=$(( (NOW - LAST_COMMIT) / 86400 ))
            if [ $DAYS_OLD -gt 180 ]; then
              echo "$1 ($DAYS_OLD days old)"
            fi
          ' _ {} \;)

          if [ ! -z "$STALE_DOCS" ]; then
            echo "📅 Stale documentation (180+ days):"
            echo "$STALE_DOCS"

            # Create issue
            gh issue create \
              --title "📅 Stale documentation detected" \
              --body "The following documentation files haven't been updated in 180+ days:\n\n$STALE_DOCS" \
              --label documentation,stale
          fi
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Effort**: 30 minutes

---

### 3.5: Auto-Generate Documentation from Code

**File**: `.github/workflows/auto-docs.yml`

**Purpose**: Auto-generate parts of documentation from code comments and ADRs

```yaml
name: Auto-Generate Documentation

on:
  push:
    branches: [ main ]
    paths:
      - 'values-*.yaml.example'
      - 'docs/adrs/*.md'

jobs:
  generate-config-reference:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate configuration reference
        run: |
          # Extract comments from values-hub.yaml.example
          python3 scripts/generate-config-docs.py \
            --input values-hub.yaml.example \
            --output docs/reference/configuration-reference.md

      - name: Create pull request if changes
        uses: peter-evans/create-pull-request@v6
        with:
          commit-message: 'docs: Auto-update configuration reference'
          branch: auto-docs-update
          title: '📝 Auto-generated configuration reference updates'
          body: 'Automatically generated from values-hub.yaml.example comments'
          labels: documentation,automated
```

**Supporting Script**: `scripts/generate-config-docs.py`

```python
#!/usr/bin/env python3
"""Generate configuration reference from YAML comments."""

import argparse
import yaml
import re

def extract_comments(yaml_file):
    """Extract inline comments from YAML file."""
    with open(yaml_file, 'r') as f:
        lines = f.readlines()

    config_docs = []
    for line in lines:
        # Match: key: value  # Comment
        match = re.match(r'^\s*([\w.]+):\s*(.+?)\s*#\s*(.+)$', line)
        if match:
            key, default, comment = match.groups()
            config_docs.append({
                'key': key,
                'default': default,
                'description': comment.strip()
            })

    return config_docs

def generate_markdown(config_docs, output_file):
    """Generate markdown documentation."""
    with open(output_file, 'w') as f:
        f.write('# Configuration Reference\n\n')
        f.write('Auto-generated from `values-hub.yaml.example`.\n\n')
        f.write('| Configuration Key | Default Value | Description |\n')
        f.write('|-------------------|---------------|-------------|\n')

        for config in config_docs:
            f.write(f"| `{config['key']}` | `{config['default']}` | {config['description']} |\n")

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True, help='Input YAML file')
    parser.add_argument('--output', required=True, help='Output markdown file')
    args = parser.parse_args()

    config_docs = extract_comments(args.input)
    generate_markdown(config_docs, args.output)
    print(f'✅ Generated {args.output} with {len(config_docs)} configuration options')
```

**Effort**: 1-2 hours

---

## Implementation Timeline

### Week 1: Phase 4 Expansion

**Day 1-2**: Expand API documentation
- Document Coordination Engine API
- Document KServe API
- Document Tekton/ArgoCD interactions

**Day 3-4**: Expand architecture overview
- Core concepts section
- Design decisions section
- Integration points

**Day 5**: Create new reference documents
- Configuration reference
- Troubleshooting reference

**Deliverables**:
- ✅ `docs/reference/api-documentation.md` (expanded)
- ✅ `docs/explanation/architecture-overview.md` (expanded)
- ✅ `docs/reference/configuration-reference.md` (new)
- ✅ `docs/reference/troubleshooting-reference.md` (new)

### Week 2: Phase 5 Reorganization

**Day 1**: Plan and test migrations
- Create redirect files
- Test internal link updates

**Day 2**: Execute migrations
- `git mv` files to new locations
- Update internal links

**Day 3**: Update navigation
- Update `mkdocs.yml`
- Update README.md
- Test MkDocs build

**Day 4**: Validation
- Build documentation site
- Test all links
- Fix any broken references

**Day 5**: Buffer for issues

**Deliverables**:
- ✅ 6 files moved to `docs/` subdirectories
- ✅ 5 redirect files at old locations
- ✅ `mkdocs.yml` updated
- ✅ All internal links working

### Week 3: Automation Setup

**Day 1**: Link checker workflow
- Create `.github/workflows/link-checker.yml`
- Test on pull request

**Day 2**: Version consistency checker
- Create `.github/workflows/version-check.yml`
- Test with known inconsistencies

**Day 3**: ADR status checker
- Create `.github/workflows/adr-status-check.yml`
- Test with deprecated ADRs

**Day 4**: Documentation freshness checker
- Create `.github/workflows/doc-freshness.yml`
- Test with scheduled run

**Day 5**: Auto-documentation generation
- Create `.github/workflows/auto-docs.yml`
- Create `scripts/generate-config-docs.py`
- Test generation from values files

**Deliverables**:
- ✅ 5 GitHub Actions workflows
- ✅ 1 Python script for auto-generation
- ✅ All workflows tested and passing

---

## Success Criteria

### Phase 4
- ✅ API documentation >5 KB (vs 824-byte stub)
- ✅ Architecture overview >8 KB (vs 822-byte stub)
- ✅ 2 new reference documents created
- ✅ All documentation references current architecture (Go coordination engine, standalone MCP server)

### Phase 5
- ✅ 6 files moved to appropriate Diataxis categories
- ✅ 5 redirect files created for backward compatibility
- ✅ `mkdocs build --strict` passes with zero warnings
- ✅ All internal links working
- ✅ README.md updated with new documentation structure

### Automation
- ✅ 5 GitHub Actions workflows deployed and passing
- ✅ Link checker runs on every PR touching markdown
- ✅ Version consistency checker catches outdated references
- ✅ ADR status checker validates deprecated ADR markings
- ✅ Monthly freshness reports generated
- ✅ Configuration reference auto-updated from values files

---

## Risks and Mitigations

### Risk 1: Breaking Existing Links

**Mitigation**:
- Create redirect files at old locations
- Test all internal links before merging
- Use `mkdocs build --strict` to catch broken links

### Risk 2: Version Inconsistencies After Update

**Mitigation**:
- Version consistency checker workflow
- Update OPERATOR_VERSIONS.md as source of truth
- Automated checks on every PR

### Risk 3: Stale Auto-Generated Docs

**Mitigation**:
- Trigger auto-docs workflow on every values file change
- Monthly freshness checker
- Clear documentation in code comments

### Risk 4: Overwhelming Number of Issues

**Mitigation**:
- Start with warnings, not failures
- Gradually increase strictness
- Label automated issues clearly

---

## Next Steps

1. **Review this plan** with team
2. **Approve phases** to implement (4, 5, automation)
3. **Create tasks** in project board
4. **Assign owners** for each phase
5. **Set timeline** based on team capacity
6. **Execute incrementally** (one phase at a time)

---

## References

- [Diataxis Documentation Framework](https://diataxis.fr/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [MkDocs Documentation](https://www.mkdocs.org/)
- [Markdown Link Check Action](https://github.com/gaurav-nelson/github-action-markdown-link-check)
