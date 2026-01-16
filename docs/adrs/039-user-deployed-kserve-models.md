# ADR-039: User-Deployed KServe Models (Platform-Agnostic ML Integration)

**Status:** ACCEPTED
**Date:** 2026-01-07
**Decision Makers:** Architecture Team
**Consulted:** ML Engineering, DevOps Team
**Informed:** Development Team, Operations Team

## Context

Following the Go coordination engine migration (ADR-038), we needed to decide how ML models integrate with the platform. The initial configuration assumed a standalone `aiops-ml-service` at `http://aiops-ml-service:8080`, but this service was never deployed.

### Current State Analysis

**What Exists:**
- ✅ **KServe InferenceServices**: `anomaly-detector` and `predictive-analytics` deployed via KServe (ADR-004)
- ✅ **User MLOps Workflow**: Users train models in notebooks and deploy via KServe (ADR-037)
- ✅ **Go Coordination Engine**: Ready for ML integration (ADR-038)
- ✅ **Platform Multi-Cluster Support**: Hub-spoke topology via ACM (ADR-022)

**What Doesn't Exist:**
- ❌ **Standalone ML Service**: `aiops-ml-service` was never deployed (only BuildConfig exists in `src/models/`)
- ❌ **Centralized Model Registry**: Using simple PVC-based storage (ADR-037)
- ❌ **Platform-Managed Models**: No pre-trained models provided by platform

### Key Requirements

1. **Platform Agnostic**: Support both **vanilla Kubernetes** and **OpenShift** environments
2. **User Responsibility**: Users train and deploy their own models
3. **Separation of Concerns**: Platform provides infrastructure, users provide models
4. **Flexibility**: Support any KServe-compatible model
5. **Multi-Cluster Ready**: Work with ACM spoke clusters (ADR-022)

## Decision

We will adopt a **User-Deployed KServe Model Architecture** where:

1. **Users are responsible** for training and deploying models via KServe InferenceServices
2. **Coordination engine calls KServe InferenceServices directly** (no intermediate ML service)
3. **Platform provides** KServe infrastructure and integration points
4. **Works on both** vanilla Kubernetes (with KServe operator) and OpenShift (with OpenShift AI)

### Architecture

```
┌──────────────────────────────────────────────────────┐
│ USER RESPONSIBILITY: Model Training & Deployment    │
│                                                       │
│  1. Train models in OpenShift AI workbenches/locally │
│  2. Save models to PVC or S3 storage                 │
│  3. Deploy as KServe InferenceServices               │
│  4. Maintain model versions and updates              │
└──────────────────────────────────────────────────────┘
                          ▲
                          │ Calls KServe v1 API:
                          │ /v1/models/<model>:predict
                          │
┌──────────────────────────────────────────────────────┐
│ PLATFORM RESPONSIBILITY: Infrastructure              │
│                                                       │
│  - Go Coordination Engine (anomaly processing)       │
│  - KServe Infrastructure (model serving)             │
│  - Monitoring & Observability (Prometheus/Grafana)   │
│  - Storage (PVC/S3 for models)                       │
└──────────────────────────────────────────────────────┘
```

### Configuration Changes

**Before (ADR-038 Initial)**:
```yaml
coordinationEngine:
  mlService:
    enabled: true
    url: http://aiops-ml-service:8080  # Service never deployed
```

**After (This ADR)**:
```yaml
coordinationEngine:
  kserve:
    enabled: true
    namespace: self-healing-platform
    services:
      anomaly_detector: "anomaly-detector-predictor"
      predictive_analytics: "predictive-analytics-predictor"
```

**Environment Variables**:
```yaml
env:
  - name: ENABLE_KSERVE_INTEGRATION
    value: "true"
  - name: KSERVE_NAMESPACE
    value: "self-healing-platform"
  - name: KSERVE_ANOMALY_DETECTOR_SERVICE
    value: "anomaly-detector-predictor"
  - name: KSERVE_PREDICTIVE_ANALYTICS_SERVICE
    value: "predictive-analytics-predictor"
```

## Rationale

### Why User-Deployed Models?

1. **✅ Platform Agnostic**: KServe works on vanilla Kubernetes and OpenShift
2. **✅ User Control**: Users maintain full control over model lifecycle
3. **✅ Flexibility**: Users can deploy any sklearn, TensorFlow, PyTorch, or custom model
4. **✅ Aligns with ADR-037**: Already documented MLOps workflow
5. **✅ No Vendor Lock-in**: Not tied to OpenShift-specific services
6. **✅ Multi-Cluster Ready**: KServe InferenceServices work in ACM spoke clusters

### Why Direct KServe Integration (No aiops-ml-service)?

| Criterion | aiops-ml-service Wrapper | Direct KServe Integration | Winner |
|-----------|--------------------------|---------------------------|--------|
| **Simplicity** | Extra service to maintain | Direct KServe API calls | ✅ Direct |
| **Platform Support** | Custom service deployment | Native KServe (K8s + OpenShift) | ✅ Direct |
| **User Responsibility** | Who maintains wrapper? | Users deploy their own models | ✅ Direct |
| **Flexibility** | Wrapper limits model types | Any KServe-compatible model | ✅ Direct |
| **Operational Overhead** | Service + BuildConfig + Deployment | Just InferenceService | ✅ Direct |
| **Alignment with ADR-037** | Conflicts with user workflow | Matches perfectly | ✅ Direct |

### When aiops-ml-service Would Make Sense

Consider deploying a wrapper ML service if:
- ❌ **We want to hide KServe details** from users (not a goal - users need KServe knowledge anyway)
- ❌ **We need unified API** across multiple models (KServe already provides this)
- ❌ **Complex aggregation logic** needed (can be done in coordination engine)
- ❌ **Platform provides pre-trained models** (we don't - users train their own)

**Verdict**: None of these apply to our architecture → Direct KServe integration is the right choice.

## Consequences

### Positive

1. **✅ Platform Agnostic**
   - Works on vanilla Kubernetes with KServe operator
   - Works on OpenShift with OpenShift AI
   - No OpenShift-specific dependencies

2. **✅ User Empowerment**
   - Users have full control over model training and deployment
   - Can use any KServe-compatible framework (sklearn, TensorFlow, PyTorch)
   - Flexible model versioning and rollback strategies

3. **✅ Simpler Architecture**
   - No extra service to maintain (`aiops-ml-service` eliminated)
   - Fewer moving parts = less operational overhead
   - Direct API calls to KServe (no wrapper layer)

4. **✅ Alignment with Industry Practices**
   - KServe is the de facto standard for Kubernetes ML serving
   - Follows cloud-native principles
   - Compatible with Kubeflow ecosystem

5. **✅ Multi-Cluster Ready**
   - KServe InferenceServices can be deployed to ACM spoke clusters
   - Coordination engine configuration supports multi-namespace/multi-cluster

### Negative

1. **⚠️ User Responsibility**
   - Users must learn KServe concepts and API
   - Platform doesn't provide pre-trained models
   - **Mitigation**: Comprehensive user deployment guide (docs/guides/USER-MODEL-DEPLOYMENT-GUIDE.md)

2. **⚠️ No Centralized Model Catalog**
   - No single place to discover available models
   - Users manage their own model versions
   - **Mitigation**: Documentation and notebook examples show best practices

3. **⚠️ Coordination Engine Must Discover Models**
   - Coordination engine needs to know which KServe services exist
   - Configuration required for each model
   - **Mitigation**: Configuration via values.yaml with sensible defaults

### Neutral

1. **📊 Documentation Burden**
   - Need comprehensive guides for users
   - **Impact**: Created USER-MODEL-DEPLOYMENT-GUIDE.md with platform-specific examples

2. **📊 KServe Dependency**
   - Platform tied to KServe ecosystem
   - **Impact**: Acceptable - KServe is industry standard and works everywhere

## Implementation

### Phase 1: Configuration ✅ COMPLETED

**Files Modified**:
- `charts/hub/templates/coordination-engine.yaml` - Removed `ML_SERVICE_URL`, added `KSERVE_*` env vars
- `values-hub.yaml` - Replaced `mlService` with `kserve` section

**Environment Variables**:
```yaml
- name: ENABLE_KSERVE_INTEGRATION
  value: "true"
- name: KSERVE_NAMESPACE
  value: "self-healing-platform"
- name: KSERVE_ANOMALY_DETECTOR_SERVICE
  value: "anomaly-detector-predictor"
- name: KSERVE_PREDICTIVE_ANALYTICS_SERVICE
  value: "predictive-analytics-predictor"
```

### Phase 2: Documentation ✅ COMPLETED

**Files Created**:
- `docs/guides/USER-MODEL-DEPLOYMENT-GUIDE.md` - Comprehensive guide for deploying models
  - Platform compatibility matrix (vanilla K8s vs OpenShift)
  - KServe API contract requirements
  - Step-by-step deployment workflow
  - PVC-based storage (OpenShift) vs S3 storage (cloud)
  - Troubleshooting section

**Files Updated**:
- `README.md` - Added "Deploying Your Own ML Models" section with link to guide

### Phase 3: Notebook Updates ✅ COMPLETED

**Files Modified**:
- `notebooks/03-self-healing-logic/rule-based-remediation.ipynb` - Fixed endpoint `/incidents` → `/api/v1/incidents`

### Phase 4: Coordination Engine Integration (Pending)

**Upstream Repository**: `tosin2013/openshift-coordination-engine`

**Required Changes** (GitHub issue to be created):
1. Remove `ML_SERVICE_URL` support
2. Add `ENABLE_KSERVE_INTEGRATION` flag
3. Add KServe service discovery via environment variables
4. Implement KServe v1 API client (`/v1/models/<model>:predict`)
5. Update API contract documentation

## Platform Compatibility

| Platform | KServe Installation | OpenShift AI | Notes |
|----------|---------------------|--------------|-------|
| **OpenShift 4.18+** | ✅ Via OpenShift Serverless | ✅ Native | Recommended platform |
| **Vanilla Kubernetes 1.28+** | ✅ Via KServe Operator | ❌ N/A | Install Knative + KServe manually |
| **ACM Spoke Clusters** | ✅ Deploy via ApplicationSet | ✅ If OpenShift | Multi-cluster support |

**Installation Guides**:
- **OpenShift**: KServe included with OpenShift AI operator
- **Vanilla Kubernetes**: [KServe Quick Start](https://kserve.github.io/website/latest/get_started/)

## Model API Contract

Users deploying models MUST implement the KServe v1 prediction API:

### Required Endpoints

```
GET  /v1/models/<model>           # Model metadata
POST /v1/models/<model>:predict   # Inference
GET  /v1/models                   # List models
```

### Request Format

```json
POST /v1/models/anomaly-detector:predict

{
  "instances": [
    [0.5, 1.2, 0.8],
    [0.3, 0.9, 1.1]
  ]
}
```

### Response Format

```json
{
  "predictions": [-1, 1],  # -1=anomaly, 1=normal
  "model_name": "anomaly-detector",
  "model_version": "v2"
}
```

## Migration Path

### From ADR-038 (Initial Go Migration)

**No Breaking Changes** - Existing KServe InferenceServices continue to work:
- `anomaly-detector` InferenceService remains deployed
- `predictive-analytics` InferenceService remains deployed

**Configuration Update Required**:
```yaml
# Update values-hub.yaml
coordinationEngine:
  # OLD (remove):
  # mlService:
  #   enabled: true
  #   url: http://aiops-ml-service:8080

  # NEW (add):
  kserve:
    enabled: true
    namespace: self-healing-platform
    services:
      anomaly_detector: "anomaly-detector-predictor"
      predictive_analytics: "predictive-analytics-predictor"
```

**Coordination Engine Update**: Once upstream coordination engine adds KServe support, update to new version.

## Related ADRs

- **ADR-002**: [Hybrid Deterministic-AI Self-Healing Approach](002-hybrid-self-healing-approach.md) - Defines ML integration architecture
- **ADR-004**: [KServe for Model Serving Infrastructure](004-kserve-model-serving.md) - KServe as the serving platform
- **ADR-022**: [Multi-Cluster Support via ACM](022-multi-cluster-support-acm-integration.md) - Multi-cluster deployment patterns
- **ADR-037**: [MLOps Workflow for Model Training, Versioning, and Deployment](037-mlops-workflow-strategy.md) - User-centric MLOps workflow
- **ADR-038**: [Go Coordination Engine Migration](038-go-coordination-engine-migration.md) - Coordination engine architecture

## References

### External

- [KServe Documentation](https://kserve.github.io/website/)
- [KServe v1 Prediction Protocol](https://kserve.github.io/website/latest/modelserving/data_plane/v1_protocol/)
- [OpenShift AI Model Serving](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2-latest/html/serving_models/index)
- [Validated Patterns Multi-Cluster](https://validatedpatterns.io/learn/vp_openshift_framework/)

### Internal

- **User Guide**: [USER-MODEL-DEPLOYMENT-GUIDE.md](../guides/USER-MODEL-DEPLOYMENT-GUIDE.md)
- **MLOps Examples**: `notebooks/04-model-serving/kserve-model-deployment.ipynb`
- **Helm Configuration**: `charts/hub/templates/coordination-engine.yaml`, `values-hub.yaml`

## Success Criteria

- [x] Configuration updated (coordination-engine.yaml, values-hub.yaml)
- [x] User deployment guide created
- [x] README updated with model deployment section
- [x] Notebook endpoint fixed (rule-based-remediation.ipynb)
- [ ] GitHub issue created for coordination engine KServe support
- [ ] Coordination engine implements KServe integration
- [ ] Integration tested on both OpenShift and vanilla Kubernetes

## Next Steps

1. **✅ COMPLETED**: Update platform configuration to use KServe directly
2. **✅ COMPLETED**: Create comprehensive user deployment guide
3. **✅ COMPLETED**: Fix notebook endpoints for Go coordination engine
4. **PENDING**: Create GitHub issue for coordination engine KServe support
5. **FUTURE**: Test KServe integration on vanilla Kubernetes cluster
6. **FUTURE**: Add multi-cluster model deployment examples (ACM spoke clusters)

---

**Approved by**: Architecture Team
**Date**: 2026-01-07
