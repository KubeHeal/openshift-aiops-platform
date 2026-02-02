# ADR-040: Extensible KServe Model Registry for User-Deployed Models

**Status:** ACCEPTED
**Date:** 2026-01-07
**Decision Makers:** Architecture Team
**Consulted:** ML Engineering, Platform Users
**Informed:** Development Team, Operations Team

## Context

Following ADR-039 (User-Deployed KServe Models), we established that users are responsible for training and deploying their own ML models via KServe InferenceServices. The platform provides coordination engine integration with two default models:

- `anomaly-detector-predictor` (Isolation Forest anomaly detection)
- `predictive-analytics-predictor` (LSTM-based predictive analytics)

However, users may want to add **domain-specific models** for their own use cases:
- Database-specific anomaly detection
- Network traffic prediction
- Disk failure prediction
- Application-specific performance models
- Security threat detection models

### Current Limitation

The coordination engine configuration is **hardcoded** for the two default models:

```yaml
# values-hub.yaml
coordinationEngine:
  kserve:
    enabled: true
    namespace: self-healing-platform
    services:
      anomaly_detector: "anomaly-detector-predictor"
      predictive_analytics: "predictive-analytics-predictor"
```

**Problem**: Users cannot easily add their own models without modifying platform configuration.

### User Requirements

1. **Easy Extension**: Users should be able to register custom models without forking the platform
2. **Multi-Namespace Support**: Models may be deployed in different namespaces
3. **Model Metadata**: Users need to specify model type, triggers, and purpose
4. **Platform Agnostic**: Must work on both vanilla Kubernetes and OpenShift
5. **GitOps Friendly**: Configuration should be manageable via GitOps workflows

## Decision

We will support an **extensible KServe model registry** via `values-hub.yaml` configuration, allowing users to register custom models that the coordination engine can discover and call.

### Architecture

```
┌───────────────────────────────────────────────────────────┐
│ User Configuration (values-hub.yaml)                      │
│                                                            │
│ coordinationEngine:                                        │
│   kserve:                                                  │
│     models:                                                │
│       - name: anomaly-detector                             │
│         service: anomaly-detector-predictor                │
│         type: anomaly                                      │
│       - name: disk-failure-predictor  ← USER ADDS THIS    │
│         service: disk-failure-predictor-predictor          │
│         namespace: storage-monitoring                      │
│         type: predictive                                   │
└───────────────────────────────────────────────────────────┘
                           ▼
                ┌──────────────────────┐
                │ Coordination Engine  │
                │ - Reads model list   │
                │ - Calls KServe APIs  │
                └──────────────────────┘
                           ▼
        ┌─────────────┬─────────────┬──────────────────┐
        │ Default     │ Default     │ User Custom      │
        │ Anomaly     │ Predictive  │ Disk Failure     │
        │ Detector    │ Analytics   │ Predictor        │
        └─────────────┴─────────────┴──────────────────┘
```

## Implementation

### Phase 1: Simple Extension via values.yaml (RECOMMENDED)

**Update `values-hub.yaml`** to support a model list:

```yaml
coordinationEngine:
  kserve:
    enabled: true
    namespace: self-healing-platform  # Default namespace
    models:
      - name: anomaly-detector
        service: anomaly-detector-predictor
        type: anomaly
        description: "Isolation Forest anomaly detection"

      - name: predictive-analytics
        service: predictive-analytics-predictor
        type: predictive
        description: "LSTM-based predictive analytics"

      # USERS CAN ADD MORE:
      - name: disk-failure-predictor
        service: disk-failure-predictor-predictor
        namespace: storage-monitoring  # Override default namespace
        type: predictive
        description: "Predicts disk failures 24h in advance"

      - name: postgres-query-anomaly
        service: postgres-anomaly-predictor
        namespace: database-monitoring
        type: anomaly
        description: "Detects abnormal database query patterns"
```

**Update `charts/hub/templates/coordination-engine.yaml`**:

```yaml
env:
  {{- if .Values.coordinationEngine.kserve.enabled }}
  - name: ENABLE_KSERVE_INTEGRATION
    value: "true"
  - name: KSERVE_NAMESPACE
    value: {{ .Values.coordinationEngine.kserve.namespace | default .Release.Namespace | quote }}
  - name: KSERVE_MODEL_REGISTRY
    value: {{ toJson .Values.coordinationEngine.kserve.models | quote }}
  {{- end }}
```

### Phase 2: ConfigMap-Based Registry (FUTURE)

For more dynamic updates without coordination engine restarts:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kserve-model-registry
  namespace: self-healing-platform
data:
  models.yaml: |
    models:
      - name: anomaly-detector
        service: anomaly-detector-predictor
        namespace: self-healing-platform
        type: anomaly
        triggers:
          - metric_anomaly
          - resource_spike
      - name: disk-failure-predictor
        service: disk-failure-predictor-predictor
        namespace: storage-monitoring
        type: predictive
        triggers:
          - disk_utilization_high
        inputFeatures:
          - disk_utilization
          - iops
          - disk_age_days
```

**Coordination Engine**: Watch ConfigMap for updates and reload model registry.

### Phase 3: CRD-Based Registry (ADVANCED)

For full Kubernetes-native integration:

```yaml
apiVersion: aiops.platform.io/v1alpha1
kind: ModelRegistration
metadata:
  name: disk-failure-predictor
spec:
  kserveInferenceService: "disk-failure-predictor"
  namespace: storage-monitoring
  modelType: predictive
  triggers:
    - type: metric-threshold
      metric: disk_utilization
      threshold: 85
  inputFeatures:
    - disk_utilization
    - iops
    - disk_age_days
  outputFormat:
    field: failure_probability
    threshold: 0.7
  remediationActions:
    - type: alert
      severity: warning
    - type: scale-storage
      target: increase-capacity
```

## User Guide: Registering Custom Models

### Step 1: Deploy Your Model via KServe

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: disk-failure-predictor
  namespace: storage-monitoring
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: "pvc://model-storage-pvc/disk-failure-predictor/v1"
```

### Step 2: Register Model in values-hub.yaml

```yaml
coordinationEngine:
  kserve:
    enabled: true
    models:
      # ... existing models ...
      - name: disk-failure-predictor
        service: disk-failure-predictor-predictor
        namespace: storage-monitoring
        type: predictive
        description: "Predicts disk failures using historical metrics"
```

### Step 3: Redeploy Coordination Engine

```bash
# Using Helm
helm upgrade self-healing-platform charts/hub -n self-healing-platform -f values-hub.yaml

# Or via GitOps (recommended)
git add values-hub.yaml
git commit -m "feat: register disk-failure-predictor model"
git push
# ArgoCD will sync automatically
```

### Step 4: Verify Integration

```bash
# Check coordination engine logs
oc logs -n self-healing-platform deployment/coordination-engine | grep "disk-failure-predictor"

# Expected: "Registered KServe model: disk-failure-predictor"

# Test model endpoint
oc exec -n self-healing-platform deployment/coordination-engine -- \
  curl -X POST http://disk-failure-predictor-predictor.storage-monitoring.svc.cluster.local/v1/models/disk-failure-predictor:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[85.5, 5000, 365]]}'
```

## Model Types and Use Cases

### Supported Model Types

| Type | Purpose | Example Models |
|------|---------|----------------|
| `anomaly` | Detect abnormal behavior | Isolation Forest, Autoencoders, One-Class SVM |
| `predictive` | Forecast future states | LSTM, Prophet, ARIMA |
| `classification` | Categorize incidents | Random Forest, XGBoost, Neural Networks |

### Example Custom Models

1. **Database Performance**
   - Model: `postgres-query-anomaly`
   - Input: Query execution time, CPU usage, connection count
   - Output: Anomaly score (0-1)
   - Remediation: Kill long-running queries, scale database

2. **Network Traffic**
   - Model: `network-traffic-predictor`
   - Input: Historical traffic patterns
   - Output: Predicted traffic in next hour
   - Remediation: Scale network pods, adjust QoS

3. **Disk Failure Prediction**
   - Model: `disk-failure-predictor`
   - Input: Disk age, SMART metrics, I/O patterns
   - Output: Failure probability
   - Remediation: Migrate workloads, alert operations

4. **Security Threat Detection**
   - Model: `security-threat-detector`
   - Input: Login attempts, API call patterns
   - Output: Threat classification (benign/suspicious/critical)
   - Remediation: Block IPs, trigger alerts

## Coordination Engine Requirements

### Current Implementation

**Upstream Repository**: `KubeHeal/openshift-coordination-engine`

**Required Changes** (GitHub issue to be created):

1. **Dynamic Model Loading**
   ```go
   type KServeModel struct {
       Name        string `json:"name"`
       Service     string `json:"service"`
       Namespace   string `json:"namespace,omitempty"`
       Type        string `json:"type"`
       Description string `json:"description,omitempty"`
   }

   func loadModels() ([]KServeModel, error) {
       registryJSON := os.Getenv("KSERVE_MODEL_REGISTRY")
       var models []KServeModel
       if err := json.Unmarshal([]byte(registryJSON), &models); err != nil {
           return nil, err
       }
       return models, nil
   }
   ```

2. **Model Discovery**
   - Read `KSERVE_MODEL_REGISTRY` environment variable (JSON array)
   - Validate model configurations
   - Build service URLs: `http://{service}.{namespace}.svc.cluster.local/v1/models/{name}:predict`

3. **API Endpoints**
   ```go
   GET /api/v1/models              // List registered models
   GET /api/v1/models/{name}       // Get model details
   POST /api/v1/models/{name}/predict  // Proxy to KServe
   ```

## Rationale

### Why Extensible Model Registry?

| Benefit | Impact |
|---------|--------|
| **User Empowerment** | Users can add domain-specific models without platform changes |
| **Multi-Tenant Support** | Different teams can deploy their own models |
| **Platform Agnostic** | Works on vanilla Kubernetes and OpenShift |
| **GitOps Friendly** | Configuration managed via Git |
| **Industry Alignment** | Matches Kubeflow/Seldon extensibility patterns |

### Why Start with values.yaml (Phase 1)?

| Criterion | values.yaml | ConfigMap | CRD |
|-----------|-------------|-----------|-----|
| **Simplicity** | ✅ Simple | Medium | Complex |
| **No Restart Required** | ❌ Needs restart | ✅ Hot reload | ✅ Hot reload |
| **GitOps Integration** | ✅ Native | ✅ Native | ✅ Native |
| **Validation** | ✅ Helm schema | ⚠️ Manual | ✅ OpenAPI schema |
| **Implementation Effort** | ✅ Low | Medium | High |

**Decision**: Start with Phase 1 (values.yaml), evolve to ConfigMap/CRD based on user feedback.

## Consequences

### Positive

1. **✅ Extensibility**
   - Users can add unlimited custom models
   - No platform code changes required

2. **✅ Multi-Namespace Support**
   - Models can be deployed in different namespaces
   - Supports organizational boundaries (team A, team B)

3. **✅ Platform Agnostic**
   - Works on vanilla Kubernetes (with KServe operator)
   - Works on OpenShift (with OpenShift AI)

4. **✅ GitOps Ready**
   - Configuration managed via Git
   - ArgoCD auto-sync support

5. **✅ Future-Proof**
   - Clear migration path: values.yaml → ConfigMap → CRD
   - Can add metadata without breaking changes

### Negative

1. **⚠️ Coordination Engine Dependency**
   - Requires upstream coordination engine to support dynamic model loading
   - **Mitigation**: Create GitHub issue with clear requirements

2. **⚠️ Restart Required (Phase 1)**
   - Model registry changes require coordination engine restart
   - **Mitigation**: Phase 2 (ConfigMap) enables hot reload

3. **⚠️ No Validation (Phase 1)**
   - Users might configure invalid model URLs
   - **Mitigation**: Add Helm schema validation for model list

### Neutral

1. **📊 Documentation Burden**
   - Need to document model registration process
   - **Impact**: Update USER-MODEL-DEPLOYMENT-GUIDE.md

2. **📊 Testing Complexity**
   - Need to test with multiple custom models
   - **Impact**: Add integration tests for model discovery

## Migration Path

### From ADR-039 (Current State)

**No Breaking Changes** - Existing configuration remains valid:

```yaml
# OLD (ADR-039) - Still works
coordinationEngine:
  kserve:
    enabled: true
    namespace: self-healing-platform
    services:
      anomaly_detector: "anomaly-detector-predictor"
      predictive_analytics: "predictive-analytics-predictor"
```

**NEW (ADR-040) - Recommended**:

```yaml
coordinationEngine:
  kserve:
    enabled: true
    namespace: self-healing-platform
    models:
      - name: anomaly-detector
        service: anomaly-detector-predictor
        type: anomaly
      - name: predictive-analytics
        service: predictive-analytics-predictor
        type: predictive
```

**Migration Strategy**:
- Coordination engine should support BOTH formats for backward compatibility
- Deprecate `services:` map in favor of `models:` list
- Document migration in upgrade guide

## Related ADRs

- **ADR-004**: [KServe for Model Serving Infrastructure](004-kserve-model-serving.md) - KServe as the serving platform
- **ADR-022**: [Multi-Cluster Support via ACM](022-multi-cluster-support-acm-integration.md) - Multi-cluster deployment patterns
- **ADR-037**: [MLOps Workflow for Model Training, Versioning, and Deployment](037-mlops-workflow-strategy.md) - User-centric MLOps workflow
- **ADR-038**: [Go Coordination Engine Migration](038-go-coordination-engine-migration.md) - Coordination engine architecture
- **ADR-039**: [User-Deployed KServe Models](039-user-deployed-kserve-models.md) - Platform-agnostic ML integration

## References

### External

- [Kubeflow Model Registry](https://www.kubeflow.org/docs/components/model-registry/)
- [Seldon Core Multi-Model Serving](https://docs.seldon.io/projects/seldon-core/en/latest/servers/overview.html)
- [KServe Multi-Model Serving](https://kserve.github.io/website/latest/modelserving/v1beta1/serving_runtime/)

### Internal

- **User Guide**: [USER-MODEL-DEPLOYMENT-GUIDE.md](../guides/USER-MODEL-DEPLOYMENT-GUIDE.md)
- **Coordination Engine**: GitHub issue (to be created)
- **Helm Configuration**: `charts/hub/templates/coordination-engine.yaml`, `values-hub.yaml`

## Implementation Status

- [x] ADR-040 created and documented
- [ ] Update USER-MODEL-DEPLOYMENT-GUIDE.md with custom model registration
- [ ] Update values-hub.yaml schema with model list format
- [ ] Create GitHub issue for coordination engine dynamic model loading
- [ ] Add Helm chart tests for model registry configuration
- [ ] Implement Phase 1 (values.yaml-based registry)
- [ ] Update coordination engine to support KSERVE_MODEL_REGISTRY
- [ ] Test with custom model on both OpenShift and vanilla Kubernetes

## Success Criteria

- [ ] Users can register custom models via values-hub.yaml
- [ ] Coordination engine loads models from KSERVE_MODEL_REGISTRY
- [ ] Custom models callable via coordination engine APIs
- [ ] Documentation shows complete example of custom model registration
- [ ] Works on both vanilla Kubernetes and OpenShift
- [ ] GitOps workflow tested (ArgoCD auto-sync)

## Next Steps

1. **✅ COMPLETED**: Document extensible model registry architecture (this ADR)
2. **PENDING**: Update USER-MODEL-DEPLOYMENT-GUIDE.md with custom model registration section
3. **PENDING**: Create GitHub issue for coordination engine dynamic model loading support
4. **FUTURE**: Implement Phase 1 (values.yaml-based registry)
5. **FUTURE**: Add integration tests for multi-model scenarios
6. **FUTURE**: Evaluate Phase 2 (ConfigMap hot reload) based on user feedback

---

**Approved by**: Architecture Team
**Date**: 2026-01-07
