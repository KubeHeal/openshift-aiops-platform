---
title: Architecture Overview
---

# Architecture Overview

This document explains the core concepts, design decisions, and architectural patterns of the OpenShift AI Ops Self-Healing Platform.

**Last Updated**: 2026-05-18

---

## Introduction

The OpenShift AI Ops Self-Healing Platform implements a **hybrid self-healing approach** that combines:

- **Deterministic automation**: Rule-based remediation for known issues (Machine Config Operator, known procedures)
- **AI-driven analysis**: ML models for anomaly detection, root cause analysis, and predictive analytics

### Why Hybrid?

**Problem with Pure Deterministic Approaches**:
- ❌ Cannot handle novel or unfamiliar issues
- ❌ Require manual rule updates for every new scenario
- ❌ No learning from experience
- ❌ Brittle in dynamic environments

**Problem with Pure AI Approaches**:
- ❌ Slow cold-start (model training required)
- ❌ Unpredictable behavior
- ❌ Hard to debug and explain decisions
- ❌ Requires large training datasets

**Hybrid Solution Benefits**:
- ✅ Fast response for known issues (deterministic layer)
- ✅ Adaptive learning for new patterns (AI layer)
- ✅ Coordination engine resolves conflicts when both layers disagree
- ✅ Feedback loop improves both layers over time
- ✅ Explainable decisions (deterministic) + adaptive intelligence (AI)

---

## Core Concepts

### 1. Hybrid Self-Healing Architecture

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

#### Data Flow

1. **Metrics Collection**: Prometheus scrapes cluster metrics (CPU, memory, disk, network, application metrics)
2. **Anomaly Detection**: ML models (Isolation Forest, LSTM) analyze metrics and detect anomalies
3. **Anomaly Submission**: Detected anomalies submitted to Coordination Engine via REST API
4. **Decision Making**: Coordination Engine decides: deterministic remediation or AI-driven analysis?
   - If known issue → Deterministic layer (fast, predictable)
   - If unknown issue → AI-driven layer (adaptive, learning)
   - If conflict → Coordination engine resolves based on priority and confidence
5. **Remediation Execution**: Chosen action executed (scale pods, restart services, apply configs, trigger Machine Config Operator)
6. **Feedback Loop**: Success/failure logged for model retraining and rule refinement

#### Conflict Resolution Strategy

When both deterministic and AI layers suggest different actions:

```python
def resolve_conflict(deterministic_action, ai_action, ai_confidence):
    if ai_confidence < 0.7:
        # Low AI confidence → trust deterministic
        return deterministic_action
    elif ai_confidence > 0.9 and deterministic_action.severity < "high":
        # High AI confidence + low severity → try AI approach
        return ai_action
    else:
        # Default: deterministic for safety
        return deterministic_action
```

**Reference**: [ADR-002: Hybrid Deterministic-AI Self-Healing Approach](../adrs/002-hybrid-self-healing-approach.md)

---

### 2. GitOps-Driven Deployment

**Problem**: Manual deployments are error-prone, hard to reproduce, and difficult to audit.

**Solution**: Validated Patterns Framework with ArgoCD for declarative, Git-based deployments.

```
┌──────────────────────────────────────────────────────────┐
│  Git Repository (Source of Truth)                        │
│  ├─ values-global.yaml    (Global pattern config)       │
│  ├─ values-hub.yaml        (Hub cluster config)         │
│  ├─ charts/hub/            (Helm chart)                 │
│  └─ k8s/                   (Kubernetes manifests)       │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  Validated Patterns Operator                             │
│  ├─ Watches Pattern CR                                   │
│  ├─ Creates ArgoCD Application CR                        │
│  └─ Monitors deployment health                           │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  ArgoCD (hub-gitops namespace)                           │
│  ├─ Syncs from Git repository                           │
│  ├─ Manages cluster-scoped resources (ClusterRole)      │
│  ├─ Deploys operators, workloads, notebooks             │
│  ├─ Auto-heals configuration drift                      │
│  └─ Provides deployment health status                   │
└──────────────────────────────────────────────────────────┘
```

#### Why GitOps?

**Benefits**:
- **Declarative**: Infrastructure as code
- **Auditable**: Git history = deployment history (who, what, when, why)
- **Reproducible**: Same Git commit = same cluster state
- **Self-healing**: ArgoCD auto-corrects drift (reconciliation loop every 3 minutes)
- **Multi-cluster**: Pattern CR can target multiple clusters (future)

**Example Workflow**:
1. Developer updates `values-hub.yaml` (e.g., increase workbench replicas)
2. Commit and push to Git
3. ArgoCD detects change (polling or webhook)
4. ArgoCD syncs cluster state to match Git
5. Kubernetes applies changes (rolling update)
6. ArgoCD reports sync status (Healthy/Progressing/Degraded)

**Reference**: [ADR-019: Validated Patterns Framework Adoption](../adrs/019-validated-patterns-framework-adoption.md)

---

### 3. Model Serving with KServe

**Problem**: ML models need production-grade serving infrastructure with autoscaling, versioning, and monitoring.

**Solution**: KServe InferenceServices for scalable, HTTP/gRPC model endpoints.

```
┌──────────────────────────────────────────────────────────┐
│  Jupyter Notebook (Development)                          │
│  ├─ Data collection and preprocessing                   │
│  ├─ Model training (scikit-learn, TensorFlow, PyTorch)  │
│  └─ Model export (pickle, SavedModel, ONNX)             │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  Model Storage (NooBaa S3)                               │
│  ├─ s3://model-storage/anomaly-detector/model.pkl       │
│  └─ s3://model-storage/predictive-analytics/model.h5    │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  InferenceService CR (Kubernetes resource)               │
│  ├─ spec.predictor.storageUri: s3://model-storage/...  │
│  ├─ spec.predictor.runtime: sklearn / tensorflow       │
│  └─ spec.autoscaling: min=1, max=5                      │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  KServe Predictor Pod                                    │
│  ├─ Downloads model from S3                             │
│  ├─ Loads model into memory                             │
│  ├─ Exposes HTTP endpoint: /v1/models/{name}:predict    │
│  └─ Autoscales based on traffic (HPA)                   │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  HTTPS Endpoint (OpenShift Route)                        │
│  https://anomaly-detector-{namespace}.apps.cluster.com  │
└──────────────────────────────────────────────────────────┘
```

#### User-Deployed Models

Platform users are not limited to pre-deployed models. They can:

1. **Train custom models** in Jupyter notebooks
2. **Upload to S3** (NooBaa object storage)
3. **Register in values-hub.yaml**:
   ```yaml
   inferenceServices:
     custom-models:
       - name: my-fraud-detector
         storageUri: s3://model-storage/fraud-detector
         runtime: sklearn
   ```
4. **Deploy via ArgoCD** (automatic)
5. **Access via HTTPS** (OpenShift Route)

**Platform Agnostic**: KServe works on vanilla Kubernetes, not just OpenShift.

**References**:
- [ADR-004: KServe for Model Serving Infrastructure](../adrs/004-kserve-model-serving.md)
- [ADR-039: User-Deployed KServe Models](../adrs/039-user-deployed-kserve-models.md)
- [ADR-040: Extensible KServe Model Registry](../adrs/040-extensible-kserve-model-registry.md)

---

### 4. Secrets Management with External Secrets Operator

**Problem**: 
- Hardcoded secrets in Git are insecure
- Manual secret creation is error-prone and not reproducible
- Secret rotation requires manual intervention

**Solution**: External Secrets Operator with Kubernetes backend (MVP) for automated secret synchronization.

```
┌──────────────────────────────────────────────────────────┐
│  Backend Secret (openshift-storage namespace)            │
│  ├─ Created by: ODF ObjectBucketClaim                    │
│  ├─ Contains: BUCKET_NAME, ACCESS_KEY_ID, SECRET_KEY    │
│  └─ Managed by: ODF operator                             │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  SecretStore CR (self-healing-platform namespace)        │
│  ├─ Points to: openshift-storage namespace              │
│  ├─ Auth: ServiceAccount token                          │
│  └─ Provider: Kubernetes                                 │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  ExternalSecret CR (self-healing-platform namespace)     │
│  ├─ RefreshInterval: 1h                                  │
│  ├─ SecretStoreRef: kubernetes-backend                   │
│  └─ Data mappings: BUCKET_NAME, ACCESS_KEY_ID, etc.     │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  External Secrets Operator                               │
│  ├─ Watches ExternalSecret CRs                           │
│  ├─ Fetches from backend (openshift-storage)            │
│  ├─ Creates/updates local Secret                        │
│  └─ Refreshes every 1 hour                              │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  Synced Secret (self-healing-platform namespace)         │
│  ├─ Name: model-storage                                 │
│  ├─ Used by: Notebooks, Tekton pipelines, KServe        │
│  └─ Auto-updated on backend change                      │
└──────────────────────────────────────────────────────────┘
```

#### Benefits

✅ **No secrets in Git**: ExternalSecret CRs only contain references, not actual secrets  
✅ **Automated rotation**: Secrets auto-update when backend changes  
✅ **Centralized management**: One secret in backend, synced to multiple namespaces  
✅ **Declarative**: Secret configuration as code (GitOps-compatible)  
✅ **Extensible**: Supports Vault, AWS Secrets Manager, Azure Key Vault, etc.

**⚠️ MANDATORY**: All deployments must use External Secrets Operator (ADR-026).

**Reference**: [ADR-026: Secrets Management Automation](../adrs/026-secrets-management-automation.md)

---

### 5. Notebook-Based Development Workflow

**Problem**: 
- Data scientists need familiar tools (Jupyter notebooks)
- Production requires automation and validation
- Gap between development and deployment

**Solution**: Jupyter notebooks + Jupyter Notebook Validator Operator for dev-to-prod pipeline.

```
┌──────────────────────────────────────────────────────────┐
│  Development (Jupyter Workbench)                         │
│  ├─ Interactive exploration                              │
│  ├─ Model prototyping                                    │
│  ├─ Data visualization                                   │
│  └─ Save notebook to Git                                 │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  Git Repository                                           │
│  ├─ notebooks/02-anomaly-detection/                      │
│  │   01-isolation-forest-implementation.ipynb            │
│  └─ Commit + Push                                        │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  Tekton Pipeline (Triggered by Git commit or manual)     │
│  ├─ Clone repository                                     │
│  ├─ Trigger Jupyter Notebook Validator Operator         │
│  └─ Wait for validation result                          │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  Jupyter Notebook Validator Operator                     │
│  ├─ Creates Kubernetes Job                               │
│  ├─ Runs notebook non-interactively                     │
│  ├─ Validates cell outputs                              │
│  ├─ Checks for errors                                    │
│  └─ Returns validation result                           │
└──────────────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│  Model Artifacts                                          │
│  ├─ Model uploaded to S3 (NooBaa)                       │
│  ├─ InferenceService CR created                         │
│  └─ KServe deploys model                                │
└──────────────────────────────────────────────────────────┘
```

#### Notebook Tiers

**Tier 1: Infrastructure Validation**
- Purpose: Validate platform readiness before model training
- Example: `notebooks/00-setup/00-platform-readiness-validation.ipynb`
- Checks: Cluster access, operators installed, storage available, secrets configured

**Tier 2: Data Collection and Preprocessing**
- Purpose: Collect metrics, preprocess data, feature engineering
- Example: `notebooks/01-data-collection/01-prometheus-metrics-collection.ipynb`
- Outputs: Cleaned datasets ready for model training

**Tier 3: Model Training and Deployment**
- Purpose: Train ML models, validate, deploy to KServe
- Example: `notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb`
- Outputs: Trained model artifacts, InferenceService endpoint

#### Automated Execution

1. **Manual trigger**: `tkn pipeline start model-training-pipeline --showlog`
2. **Automated trigger**: Git commit webhook → Tekton EventListener → Pipeline
3. **Scheduled trigger**: Tekton CronJob → retrain models weekly

**References**:
- [ADR-012: Notebook Architecture for End-to-End Workflows](../adrs/012-notebook-architecture-for-end-to-end-workflows.md)
- [ADR-029: Jupyter Notebook Validator Operator](../adrs/029-jupyter-notebook-validator-operator.md)

---

## Design Decisions

### Why Hybrid Approach over Pure Deterministic or Pure AI?

**Deterministic-Only Limitations**:
- Cannot handle novel scenarios (requires predefined rules)
- Manual updates for every new issue type
- No learning from experience
- Brittle in dynamic cloud-native environments

**AI-Only Limitations**:
- Slow cold-start (model training required before first remediation)
- Unpredictable behavior (black-box decisions)
- Hard to debug when wrong
- Requires large training datasets

**Hybrid Benefits**:
- ✅ Best of both worlds: fast + adaptive
- ✅ Known issues → deterministic (predictable, fast)
- ✅ Unknown issues → AI (learning, adaptive)
- ✅ Coordination engine prevents conflicts
- ✅ Feedback loop improves both layers

**Trade-off**: More complex architecture, but handles both known and unknown issues effectively.

---

### Why OpenShift AI over Kubeflow or Custom ML Platform?

**Alternatives Considered**:

| Option | Pros | Cons |
|--------|------|------|
| **Kubeflow** | Full-featured ML platform, large community | More complex to deploy, no Red Hat support, heavy resource requirements |
| **MLflow** | Good for experiment tracking | Limited to tracking/registry, no serving infrastructure |
| **Custom Solution** | Full control | Reinventing the wheel, high maintenance burden, no enterprise support |
| **OpenShift AI** | Red Hat support, integrated with OpenShift, KServe included, enterprise SLA | OpenShift-specific (less portable) |

**Why OpenShift AI**:
- ✅ Red Hat enterprise support and SLA
- ✅ Tight OpenShift integration (RBAC, networking, storage, monitoring)
- ✅ KServe built-in (model serving)
- ✅ Jupyter notebooks for development
- ✅ GPU operator integration (NVIDIA drivers)
- ✅ Less operational overhead than Kubeflow

**Mitigation for Lock-in**: User-deployed models (ADR-039) allow custom ML workflows outside OpenShift AI. KServe is platform-agnostic (works on vanilla Kubernetes).

**Reference**: [ADR-003: Red Hat OpenShift AI for ML Platform](../adrs/003-openshift-ai-ml-platform.md)

---

### Why Validated Patterns over Helm-Only or Plain ArgoCD?

**Alternatives Considered**:

| Option | Pros | Cons |
|--------|------|------|
| **Helm-only** | Simple, widely used | No GitOps, manual `helm upgrade` required, no drift detection |
| **Plain ArgoCD** | GitOps-driven | More initial setup, no proven patterns for multi-cluster |
| **Flux CD** | Similar to ArgoCD | Less OpenShift integration, smaller community |
| **Validated Patterns** | GitOps + proven patterns, multi-cluster support, operator-based | Red Hat ecosystem-specific |

**Why Validated Patterns**:
- ✅ GitOps-driven (declarative, auditable)
- ✅ Proven deployment patterns (reference architectures)
- ✅ Operator-based (easy cluster-admin → namespace management)
- ✅ Multi-cluster support (hub-spoke model, future)
- ✅ OpenShift-native (tight integration)

**Trade-off**: Tied to Red Hat ecosystem, but benefits outweigh portability concerns for OpenShift deployments.

**Reference**: [ADR-019: Validated Patterns Framework Adoption](../adrs/019-validated-patterns-framework-adoption.md)

---

### Why Go for Coordination Engine (Migrated from Python)?

**Previous Implementation**: Python/Flask REST API (ADR-033, deprecated)

**Why Migrate to Go**:

| Metric | Python/Flask | Go |
|--------|--------------|-----|
| **Performance** | ~500 req/sec | ~5000 req/sec (10x) |
| **Memory** | 150-200 MB | 30-50 MB (4x less) |
| **Startup** | 2-3 seconds | <100ms (20x faster) |
| **Concurrency** | Threading (GIL limits) | Goroutines (native) |
| **Deployment** | Multiple dependencies | Single binary |
| **Type Safety** | Runtime (optional typing) | Compile-time |

**Migration Benefits**:
- ✅ Better performance (10x higher throughput)
- ✅ Lower resource footprint (4x less memory)
- ✅ Easier deployment (single binary, no dependencies)
- ✅ Better concurrency (goroutines vs threads)
- ✅ Stronger typing (compile-time safety)

**Trade-off**: Go has steeper learning curve than Python, but team already familiar with Go.

**Reference**: [ADR-038: Go Coordination Engine Migration](../adrs/038-go-coordination-engine-migration.md)

---

## Integration Points

### External Systems

#### Prometheus (Metrics Collection)

**Purpose**: Cluster and application metrics collection

**Integration**:
- Prometheus scrapes metrics from cluster components (kubelet, cAdvisor, API server)
- Custom ServiceMonitor CRs for application metrics
- Coordination Engine exports metrics at `/metrics` endpoint
- KServe predictors export metrics via Service Mesh

**Query API**:
```python
import requests

# Query CPU usage
response = requests.get(
    'http://prometheus-k8s.openshift-monitoring.svc:9090/api/v1/query',
    params={'query': 'container_cpu_usage_seconds_total'}
)
metrics = response.json()['data']['result']
```

---

#### ArgoCD (GitOps Deployment)

**Purpose**: Declarative deployment from Git

**Integration**:
- Validated Patterns Operator creates ArgoCD Application CR
- ArgoCD syncs from Git repository (your fork)
- Helm charts rendered with `values-hub.yaml`
- Auto-sync every 3 minutes (configurable)

**Check Status**:
```bash
oc get application self-healing-platform -n self-healing-platform-hub \
  -o jsonpath='{.status.sync.status} - {.status.health.status}'
# Expected: Synced - Healthy
```

---

#### OpenShift AI (ML Platform)

**Purpose**: Notebook development and model training

**Integration**:
- Jupyter notebooks deployed as StatefulSets
- PVCs for persistent notebook storage
- GPU tolerations for accelerated training (HA clusters)
- KServe integration for model serving

**Access**:
```bash
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
# Open http://localhost:8888
```

---

#### MCP Server (OpenShift Lightspeed Integration)

**Purpose**: Natural language cluster queries via OpenShift Lightspeed

**Integration**:
- Standalone Go service ([GitHub](https://github.com/KubeHeal/openshift-cluster-health-mcp))
- Exposes MCP tools (cluster health, deployment status, troubleshooting)
- Lightspeed queries → MCP server → Coordination Engine / Kubernetes API
- Responses in natural language

**Example Query**:
```
User: "What is the health status of the self-healing platform?"
Lightspeed → MCP Server → Coordination Engine → "Platform is healthy. All components running."
```

**Reference**: [ADR-036: Go-Based Standalone MCP Server](../adrs/036-go-based-standalone-mcp-server.md)

---

### Internal Services

#### Coordination Engine ↔ KServe Predictors

**Data Flow**:
1. Prometheus metrics → Anomaly detection model (KServe)
2. Anomaly detected → POST to Coordination Engine `/api/v1/anomalies`
3. Coordination Engine decides remediation
4. Remediation executed (scale, restart, config apply)

**Example**:
```python
# Anomaly detection model inference
response = requests.post(
    'https://anomaly-detector.apps.cluster.com/v1/models/anomaly-detector:predict',
    json={'instances': [[cpu, memory, disk, network, latency]]}
)

if response.json()['predictions'][0] == -1:
    # Anomaly detected → submit to coordination engine
    coordination_engine.submit_anomaly({
        'type': 'resource_spike',
        'severity': 'high',
        'confidence_score': 0.85
    })
```

---

#### Tekton Pipelines ↔ Jupyter Notebooks

**Data Flow**:
1. Developer commits notebook to Git
2. Tekton pipeline triggered (manual or automated)
3. Pipeline triggers Jupyter Notebook Validator Operator
4. Operator runs notebook as Kubernetes Job
5. Notebook uploads model to S3 (NooBaa)
6. Pipeline creates InferenceService CR
7. KServe deploys model

**Example**:
```bash
tkn pipeline start model-training-pipeline \
  -p notebook-path=notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb \
  --showlog
```

---

#### External Secrets Operator ↔ ODF

**Data Flow**:
1. ODF creates ObjectBucketClaim for model storage
2. Secret `model-storage` created in `openshift-storage` namespace (BUCKET_NAME, ACCESS_KEY_ID, SECRET_ACCESS_KEY)
3. ExternalSecret CR references this secret
4. External Secrets Operator syncs to `self-healing-platform` namespace
5. Notebooks and pipelines use synced secret to access S3

**Example**:
```yaml
# ExternalSecret watches backend secret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: model-storage-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: kubernetes-backend
  target:
    name: model-storage
  data:
    - secretKey: BUCKET_NAME
      remoteRef:
        key: model-storage
        property: BUCKET_NAME
```

---

## Platform Agnosticism

**Goal**: Support both OpenShift and vanilla Kubernetes where possible.

**Current State**:

| Component | OpenShift | Vanilla Kubernetes |
|-----------|-----------|-------------------|
| **KServe** | ✅ Works | ✅ Works |
| **Tekton** | ✅ Works | ✅ Works |
| **ArgoCD** | ✅ Works | ✅ Works |
| **OpenShift AI** | ✅ OpenShift-only | ❌ Not available |
| **Machine Config Operator** | ✅ OpenShift-only | ❌ Not available |
| **Validated Patterns** | ✅ OpenShift-native | ⚠️  Limited support |

**User-Deployed Models Strategy** (ADR-039):
- Users bring their own ML models (trained anywhere)
- Upload to S3-compatible storage (NooBaa, MinIO, AWS S3)
- Deploy via KServe (platform-agnostic)
- **No dependency on OpenShift AI**

**Future**: Detect platform and adapt deployment (OpenShift vs Kubernetes)

**Reference**: [ADR-055: OpenShift 4.20+ Multi-Cluster Topology Support](../adrs/055-openshift-420-multi-cluster-topology-support.md)

---

## Security Considerations

### Secrets Management

**✅ Enforced**:
- No hardcoded secrets in Git (External Secrets Operator)
- Secrets auto-rotated when backend changes
- Least-privilege RBAC (ServiceAccounts with minimal permissions)

**⚠️ TODO**:
- Vault integration (currently Kubernetes backend only)
- Secret encryption at rest (OpenShift default: etcd encryption)

---

### Network Policies

**✅ Enforced**:
- Internal APIs (Coordination Engine) not exposed externally
- KServe predictors use OpenShift OAuth for external access
- Network policies restrict cross-namespace traffic

**Example**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: coordination-engine-policy
  namespace: self-healing-platform
spec:
  podSelector:
    matchLabels:
      app: coordination-engine
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: self-healing-platform
      ports:
        - protocol: TCP
          port: 8080
```

---

### RBAC

**Principle**: Least privilege for all ServiceAccounts

**Example** (Coordination Engine):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: coordination-engine-role
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "deployments/scale"]
    verbs: ["get", "list", "patch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "delete"]
```

---

## Observability and Monitoring

### Metrics (Prometheus)

**Collected Metrics**:
- **Coordination Engine**: `coordination_engine_anomalies_total`, `coordination_engine_remediations_total`, `coordination_engine_response_time_seconds`
- **KServe**: Request rate, latency, error rate (via Service Mesh)
- **Tekton**: Pipeline duration, task success rate
- **Cluster**: CPU, memory, disk, network (standard Kubernetes metrics)

**Retention**: 15 days (Prometheus default)

---

### Logs (Aggregated)

**Log Aggregation**: OpenShift Logging (EFK stack) or Loki (future)

**Key Logs**:
```bash
# Coordination Engine
oc logs -n self-healing-platform deployment/coordination-engine --tail=100 -f

# KServe Predictor
oc logs -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=anomaly-detector \
  -c kserve-container --tail=100 -f

# Tekton Pipeline
tkn pipelinerun logs {pipelinerun-name} -n self-healing-platform -f
```

---

### Tracing (Future)

**Proposed**: OpenTelemetry + Jaeger for distributed tracing

**Use Cases**:
- Trace anomaly submission → remediation execution
- Trace model inference requests
- Trace pipeline execution flow

**Status**: Not yet implemented (ADR proposed)

---

## Scalability and Performance

### Horizontal Scaling

**Autoscaling Components**:
- **KServe Predictors**: HPA (min=1, max=5 replicas, CPU target=80%)
- **Coordination Engine**: Manual scaling (future: HPA based on request rate)

**Example**:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: anomaly-detector-predictor
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: anomaly-detector-predictor
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 80
```

---

### Resource Limits

**Default Limits**:
```yaml
# Coordination Engine
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

# KServe Predictor (anomaly-detector)
resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 100m
    memory: 512Mi
```

**Topology-Aware** (SNO vs HA):
- SNO: Lower resource limits (shared single node)
- HA: Higher limits (distributed across workers)

**Reference**: [ADR-057: Topology-Aware GPU Scheduling and Storage](../adrs/057-topology-aware-gpu-scheduling-and-storage.md)

---

## Further Reading

### Tutorials
- [Tutorial: Deploy on SNO](../tutorials/deploy-on-sno.md)
- [Tutorial: Train and Deploy Custom Models](../tutorials/custom-model-deployment.md)

### How-To Guides
- [How-To: Complete Deployment Guide](../how-to/complete-deployment-guide.md)
- [How-To: Test Custom Applications with MCP](../how-to/test-custom-applications-with-mcp.md)
- [How-To: Deploy MCP Server for Lightspeed](../how-to/deploy-mcp-server-lightspeed.md)

### Reference
- [API Documentation](../reference/api-documentation.md)
- [Configuration Reference](../reference/configuration-reference.md)
- [Operator Versions](../reference/operator-versions.md)

### Key ADRs
- [ADR-002: Hybrid Deterministic-AI Self-Healing Approach](../adrs/002-hybrid-self-healing-approach.md) - Core architecture
- [ADR-019: Validated Patterns Framework Adoption](../adrs/019-validated-patterns-framework-adoption.md) - Deployment strategy
- [ADR-026: Secrets Management Automation](../adrs/026-secrets-management-automation.md) - Secrets (**MANDATORY**)
- [ADR-038: Go Coordination Engine Migration](../adrs/038-go-coordination-engine-migration.md) - Coordination engine
- [ADR-039: User-Deployed KServe Models](../adrs/039-user-deployed-kserve-models.md) - Platform agnosticism

---

**Questions or Issues?**

- GitHub Issues: https://github.com/KubeHeal/openshift-aiops-platform/issues
- Documentation: https://github.com/KubeHeal/openshift-aiops-platform/tree/main/docs
