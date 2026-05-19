---
title: API Documentation
---

# API Documentation

Complete reference documentation for all APIs in the OpenShift AI Ops Self-Healing Platform.

**Last Updated**: 2026-05-18

---

## Overview

The platform exposes several APIs for:
- **Coordination Engine**: Submit anomalies, trigger remediations, check status
- **KServe InferenceServices**: ML model inference endpoints
- **Tekton Pipelines**: Model training and validation
- **External Secrets**: Automated secrets management
- **ArgoCD**: GitOps deployment status

**Authentication**: Most internal APIs (Coordination Engine, KServe) use cluster-internal networking without authentication. External access via OpenShift Routes uses OAuth.

---

## Coordination Engine REST API

**Base URL**: `http://coordination-engine.self-healing-platform.svc.cluster.local:8080`

**Source**: Go-based standalone service ([GitHub](https://github.com/KubeHeal/openshift-coordination-engine))

**Reference**: [ADR-038: Go Coordination Engine Migration](../adrs/038-go-coordination-engine-migration.md)

### Health Endpoints

#### GET /health

**Purpose**: Health check endpoint for liveness/readiness probes

**Request**:
```bash
curl http://coordination-engine.self-healing-platform.svc.cluster.local:8080/health
```

**Response** (200 OK):
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2025-12-09T18:00:00.000Z"
}
```

**Use Cases**:
- Kubernetes liveness probe
- Kubernetes readiness probe
- Monitoring health checks

---

#### GET /metrics

**Purpose**: Prometheus metrics endpoint

**Request**:
```bash
curl http://coordination-engine.self-healing-platform.svc.cluster.local:8080/metrics
```

**Response**: Prometheus text format

**Metrics Exposed**:
- `coordination_engine_anomalies_total` - Total anomalies processed (counter)
- `coordination_engine_remediations_total` - Total remediations triggered (counter)
- `coordination_engine_response_time_seconds` - API response times (histogram)
- `coordination_engine_active_remediations` - Currently active remediations (gauge)

**Prometheus Configuration**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: coordination-engine
  namespace: self-healing-platform
  labels:
    app: coordination-engine
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

---

### Anomaly Management

#### POST /api/v1/anomalies

**Purpose**: Submit detected anomaly for analysis and remediation

**Authentication**: None (internal cluster traffic only)

**Request**:
```bash
curl -X POST http://coordination-engine:8080/api/v1/anomalies \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2025-12-09T18:00:00Z",
    "type": "cpu_spike",
    "severity": "high",
    "source": "prometheus",
    "details": {
      "namespace": "my-app",
      "pod": "my-app-7d8f9c5b-xkz9p",
      "metric": "cpu_usage_percent",
      "value": 95.5,
      "threshold": 80.0
    },
    "confidence_score": 0.87,
    "recommended_action": "scale_up"
  }'
```

**Request Body Schema**:
```json
{
  "timestamp": "string (ISO 8601, required)",
  "type": "cpu_spike|memory_leak|disk_full|pod_crash|custom (required)",
  "severity": "low|medium|high|critical (required)",
  "source": "prometheus|ai-model|custom (required)",
  "details": {
    "namespace": "string (optional)",
    "pod": "string (optional)",
    "metric": "string (required)",
    "value": "number (required)",
    "threshold": "number (optional)"
  },
  "confidence_score": "number 0.0-1.0 (required)",
  "recommended_action": "string (optional)"
}
```

**Response** (200 OK):
```json
{
  "anomaly_id": "anom-12345",
  "status": "accepted",
  "queued_at": "2025-12-09T18:00:01.234Z"
}
```

**Error Responses**:

| Status Code | Error | Resolution |
|-------------|-------|------------|
| 400 Bad Request | Invalid anomaly format | Check required fields, validate timestamp format |
| 500 Internal Server Error | Database connection failed | Check coordination engine logs, verify database connectivity |

**Example** (Python):
```python
import requests
from datetime import datetime

anomaly = {
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'type': 'memory_leak',
    'severity': 'high',
    'source': 'custom',
    'details': {
        'namespace': 'production',
        'pod': 'app-server-abc123',
        'metric': 'memory_usage_mb',
        'value': 3800,
        'threshold': 3200
    },
    'confidence_score': 0.92,
    'recommended_action': 'restart_pod'
}

response = requests.post(
    'http://coordination-engine.self-healing-platform.svc.cluster.local:8080/api/v1/anomalies',
    json=anomaly,
    timeout=10
)

if response.status_code == 200:
    print(f"Anomaly submitted: {response.json()['anomaly_id']}")
else:
    print(f"Failed: {response.status_code} - {response.text}")
```

---

#### GET /api/v1/anomalies/{id}

**Purpose**: Retrieve anomaly details and remediation status

**Request**:
```bash
curl http://coordination-engine:8080/api/v1/anomalies/anom-12345
```

**Response** (200 OK):
```json
{
  "anomaly_id": "anom-12345",
  "status": "resolved",
  "created_at": "2025-12-09T18:00:00.000Z",
  "updated_at": "2025-12-09T18:02:30.000Z",
  "anomaly": {
    "type": "cpu_spike",
    "severity": "high",
    "source": "prometheus",
    "details": {
      "namespace": "my-app",
      "pod": "my-app-7d8f9c5b-xkz9p",
      "metric": "cpu_usage_percent",
      "value": 95.5
    }
  },
  "remediation": {
    "action": "scale_up",
    "triggered_at": "2025-12-09T18:00:05.000Z",
    "completed_at": "2025-12-09T18:02:30.000Z",
    "status": "success",
    "result": {
      "replicas_before": 2,
      "replicas_after": 4
    }
  }
}
```

**Status Values**:
- `pending` - Anomaly queued for processing
- `processing` - Remediation in progress
- `resolved` - Successfully remediated
- `failed` - Remediation failed

**Error Responses**:

| Status Code | Error | Resolution |
|-------------|-------|------------|
| 404 Not Found | Anomaly ID not found | Verify anomaly ID is correct |

---

### Remediation Actions

#### POST /api/v1/remediations

**Purpose**: Manually trigger remediation (bypasses anomaly queue)

**Authentication**: None (internal cluster traffic only)

**Request**:
```bash
curl -X POST http://coordination-engine:8080/api/v1/remediations \
  -H "Content-Type: application/json" \
  -d '{
    "anomaly_id": "anom-12345",
    "action": "scale_up",
    "parameters": {
      "replicas": 4,
      "namespace": "my-app",
      "deployment": "my-app"
    }
  }'
```

**Request Body Schema**:
```json
{
  "anomaly_id": "string (optional, for tracking)",
  "action": "scale_up|scale_down|restart_pod|apply_config (required)",
  "parameters": {
    "replicas": "number (for scale actions)",
    "namespace": "string (required)",
    "deployment": "string (required for scale actions)",
    "pod": "string (required for restart_pod)"
  }
}
```

**Response** (200 OK):
```json
{
  "remediation_id": "rem-67890",
  "status": "triggered",
  "triggered_at": "2025-12-09T18:05:00.000Z"
}
```

**Supported Actions**:
- `scale_up`: Increase deployment replicas
- `scale_down`: Decrease deployment replicas
- `restart_pod`: Delete pod (Kubernetes recreates it)
- `apply_config`: Apply ConfigMap or Secret changes

---

## KServe InferenceService API

**Base URL**: `https://{inferenceservice-name}-{namespace}.apps.{cluster-domain}`

**Protocol**: KServe v2 Inference Protocol

**Reference**: [ADR-004: KServe for Model Serving Infrastructure](../adrs/004-kserve-model-serving.md)

### Model Inference

#### POST /v1/models/{model-name}:predict

**Purpose**: Get predictions from deployed ML model

**Authentication**: OpenShift OAuth (via Route)

**Deployed Models**:
- `anomaly-detector` - Isolation Forest anomaly detection
- `predictive-analytics` - LSTM predictive analytics

**Request**:
```bash
# Get route URL
ROUTE=$(oc get route anomaly-detector -n self-healing-platform -o jsonpath='{.spec.host}')

# Inference request
curl -X POST https://${ROUTE}/v1/models/anomaly-detector:predict \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [
      [1.0, 2.0, 3.0, 4.0, 5.0]
    ]
  }'
```

**Request Body Schema**:
```json
{
  "instances": [
    [feature1, feature2, ..., featureN]
  ]
}
```

**Response** (200 OK):
```json
{
  "predictions": [
    -1
  ]
}
```

**Prediction Values**:
- `-1` - Anomaly detected
- `1` - Normal behavior

**Example** (Python with scikit-learn features):
```python
import requests
import numpy as np
from sklearn.preprocessing import StandardScaler

# Prepare features (CPU, memory, disk, network, response_time)
features = np.array([[75.5, 82.3, 45.0, 120.5, 0.45]])

# Get InferenceService URL
route = "anomaly-detector-self-healing-platform.apps.cluster.example.com"

# Inference request
response = requests.post(
    f'https://{route}/v1/models/anomaly-detector:predict',
    json={'instances': features.tolist()},
    verify=False  # Or provide CA cert
)

prediction = response.json()['predictions'][0]
if prediction == -1:
    print("⚠️  Anomaly detected!")
else:
    print("✅ Normal behavior")
```

---

#### GET /v1/models/{model-name}

**Purpose**: Get model metadata and status

**Request**:
```bash
curl https://anomaly-detector-self-healing-platform.apps.cluster.example.com/v1/models/anomaly-detector
```

**Response** (200 OK):
```json
{
  "name": "anomaly-detector",
  "versions": ["1"],
  "platform": "sklearn",
  "inputs": [
    {
      "name": "input",
      "datatype": "FP32",
      "shape": [-1, 5]
    }
  ],
  "outputs": [
    {
      "name": "output",
      "datatype": "INT64",
      "shape": [-1]
    }
  ]
}
```

---

### InferenceService Status

#### Check via kubectl/oc

```bash
# Get InferenceService status
oc get inferenceservice anomaly-detector -n self-healing-platform

# Expected output:
# NAME                URL                                                  READY   PREV   LATEST
# anomaly-detector    https://anomaly-detector-...apps.cluster.com        True    100           

# Detailed status
oc describe inferenceservice anomaly-detector -n self-healing-platform
```

**Ready Conditions**:
- `True` - Model serving is ready
- `False` - Model deployment failed or in progress
- `Unknown` - Status unknown (check predictor pods)

---

## Tekton Pipelines API

**Interface**: Tekton CLI (`tkn`) or Kubernetes API

**Reference**: [ADR-053: Tekton Pipelines for Model Training](../adrs/053-tekton-model-training-pipelines.md)

### Trigger Pipeline Run

#### Using Tekton CLI

```bash
# Model training pipeline (CPU-based)
tkn pipeline start model-training-pipeline \
  -p model-name=anomaly-detector \
  -p notebook-path=notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb \
  -p data-source=prometheus \
  -p training-hours=168 \
  -p inference-service-name=anomaly-detector \
  -p health-check-enabled=true \
  -p git-url=https://github.com/YOUR-USERNAME/openshift-aiops-platform.git \
  -p git-ref=main \
  -n self-healing-platform \
  --showlog
```

**Parameters**:
- `model-name`: Model identifier (string, required)
- `notebook-path`: Path to training notebook (string, required)
- `data-source`: Data source (prometheus, s3, custom) (string, required)
- `training-hours`: Hours of historical data (number, default: 168)
- `inference-service-name`: InferenceService name (string, required)
- `health-check-enabled`: Enable health checks (boolean, default: true)
- `git-url`: Git repository URL (string, required)
- `git-ref`: Git branch/tag (string, default: main)

---

#### Using Kubernetes API

```bash
# Create PipelineRun resource
cat <<EOF | oc apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: train-anomaly-detector-
  namespace: self-healing-platform
spec:
  pipelineRef:
    name: model-training-pipeline
  params:
    - name: model-name
      value: anomaly-detector
    - name: notebook-path
      value: notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb
    - name: data-source
      value: prometheus
    - name: training-hours
      value: "168"
    - name: inference-service-name
      value: anomaly-detector
    - name: git-url
      value: https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
    - name: git-ref
      value: main
EOF
```

---

### Check Pipeline Run Status

```bash
# List all pipeline runs
tkn pipelinerun list -n self-healing-platform

# Example output:
# NAME                               STARTED          DURATION   STATUS
# train-anomaly-detector-abc123     5 minutes ago    3m20s      Succeeded
# train-predictive-analytics-xyz789 10 minutes ago   8m45s      Running

# Get detailed status
tkn pipelinerun describe train-anomaly-detector-abc123 -n self-healing-platform

# View logs
tkn pipelinerun logs train-anomaly-detector-abc123 -n self-healing-platform -f
```

**Status Values**:
- `Running` - Pipeline currently executing
- `Succeeded` - All tasks completed successfully
- `Failed` - One or more tasks failed
- `Cancelled` - Pipeline cancelled by user

---

## External Secrets Operator

**Interface**: Kubernetes Custom Resources (CRs)

**API Version**: `external-secrets.io/v1beta1`

**Reference**: [ADR-026: Secrets Management Automation](../adrs/026-secrets-management-automation.md) (**MANDATORY**)

### Key Custom Resources

#### SecretStore

**Purpose**: Configure backend secret store (Kubernetes, Vault, AWS Secrets Manager, etc.)

**Example** (Kubernetes backend):
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: kubernetes-backend
  namespace: self-healing-platform
spec:
  provider:
    kubernetes:
      server:
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
      auth:
        serviceAccount:
          name: external-secrets-sa
      remoteNamespace: openshift-storage
```

**Backends Supported**:
- Kubernetes (default for MVP)
- HashiCorp Vault
- AWS Secrets Manager
- Azure Key Vault
- GCP Secret Manager

---

#### ExternalSecret

**Purpose**: Sync secret from backend to local namespace

**Example** (Model storage credentials):
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
    creationPolicy: Owner
  data:
    - secretKey: BUCKET_NAME
      remoteRef:
        key: model-storage
        property: BUCKET_NAME
    - secretKey: BUCKET_ACCESS_KEY_ID
      remoteRef:
        key: model-storage
        property: BUCKET_ACCESS_KEY_ID
    - secretKey: BUCKET_SECRET_ACCESS_KEY
      remoteRef:
        key: model-storage
        property: BUCKET_SECRET_ACCESS_KEY
```

**Fields**:
- `refreshInterval`: How often to sync (default: 1h)
- `secretStoreRef`: Reference to SecretStore
- `target.name`: Name of created Secret
- `data[].secretKey`: Key in target Secret
- `data[].remoteRef`: Reference to backend secret

---

### Check ExternalSecret Status

```bash
# Get ExternalSecret status
oc get externalsecret model-storage-secret -n self-healing-platform

# Expected output:
# NAME                    STORE                REFRESH INTERVAL   STATUS    READY
# model-storage-secret    kubernetes-backend   1h                 SecretSynced   True

# Detailed status
oc describe externalsecret model-storage-secret -n self-healing-platform

# Verify synced Secret exists
oc get secret model-storage -n self-healing-platform
```

**Status Values**:
- `SecretSynced` - Secret successfully synced
- `SecretSyncedError` - Sync failed (check logs)

---

## ArgoCD Application API

**Interface**: Kubernetes Custom Resources (kubectl/oc) or ArgoCD CLI

**API Version**: `argoproj.io/v1alpha1`

**Reference**: [ADR-042: ArgoCD Deployment Lessons Learned](../adrs/042-argocd-deployment-lessons-learned.md)

### Get Application Status

```bash
# Get Application resource
oc get application self-healing-platform -n self-healing-platform-hub -o yaml

# Quick status check
oc get application self-healing-platform -n self-healing-platform-hub \
  -o jsonpath='{.status.sync.status} - {.status.health.status}'

# Expected: Synced - Healthy
```

**Sync Status Values**:
- `Synced` - Application matches Git repository
- `OutOfSync` - Cluster state differs from Git
- `Unknown` - Sync status unknown

**Health Status Values**:
- `Healthy` - All resources healthy
- `Progressing` - Resources deploying
- `Degraded` - Some resources unhealthy
- `Missing` - Resources not found

---

### Trigger Manual Sync

```bash
# Hard refresh (re-fetch from Git)
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite

# Wait for sync to complete
oc wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/self-healing-platform -n self-healing-platform-hub --timeout=300s
```

---

## Authentication and Authorization

### Internal APIs (Cluster-Internal)

**Coordination Engine**, **KServe Predictors** (cluster-internal access):
- **Authentication**: None
- **Authorization**: Kubernetes RBAC (ServiceAccount permissions)
- **Network**: ClusterIP Services (not exposed externally)

**Example RBAC** (access Coordination Engine):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: coordination-engine-client
  namespace: self-healing-platform
rules:
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["services/proxy"]
    resourceNames: ["coordination-engine"]
    verbs: ["get", "create"]
```

---

### External APIs (Public Routes)

**KServe InferenceServices** (HTTPS via OpenShift Route):
- **Authentication**: OpenShift OAuth
- **Authorization**: Kubernetes RBAC
- **TLS**: Automatic via OpenShift router

**Example** (authenticate via oc login):
```bash
# Login to cluster
oc login https://api.cluster.example.com:6443

# Get OAuth token
TOKEN=$(oc whoami -t)

# Inference with authentication
curl -X POST https://anomaly-detector-...apps.cluster.com/v1/models/anomaly-detector:predict \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"instances": [[1.0, 2.0, 3.0]]}'
```

---

## Rate Limiting and Quotas

### Coordination Engine

**Rate Limiting**: None (internal API)

**Resource Limits**:
```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

**Concurrency**: Go goroutines handle concurrent requests

---

### KServe InferenceServices

**Autoscaling**: Horizontal Pod Autoscaler (HPA)
```yaml
spec:
  predictor:
    minReplicas: 1
    maxReplicas: 5
    scaleTarget: 80  # CPU utilization target
```

**Request Timeout**: 60 seconds (default)

**Concurrency**: Configurable via `containerConcurrency`

---

## Monitoring and Observability

### Prometheus Metrics

**Coordination Engine**:
- Endpoint: `http://coordination-engine:8080/metrics`
- Scrape interval: 30s
- Retention: 15 days (Prometheus default)

**KServe**:
- Automatic via Service Mesh
- Metrics: request rate, latency, error rate

**Tekton**:
- Built-in Prometheus integration
- Metrics: pipeline duration, task success rate

---

### Logs

```bash
# Coordination Engine
oc logs -n self-healing-platform deployment/coordination-engine --tail=100 -f

# KServe Predictor
oc logs -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=anomaly-detector \
  -c kserve-container --tail=100 -f

# Tekton PipelineRun
tkn pipelinerun logs <pipelinerun-name> -n self-healing-platform -f

# ArgoCD Application Controller
oc logs -n self-healing-platform-hub \
  deployment/hub-gitops-application-controller --tail=100 -f
```

---

### Tracing

**OpenTelemetry**: Not currently implemented

**Future**: [ADR Proposed] Distributed tracing with Jaeger

---

## Error Codes Reference

### Coordination Engine

| Code | HTTP Status | Description | Resolution |
|------|-------------|-------------|------------|
| E001 | 400 | Invalid anomaly format | Check required fields (timestamp, type, severity, source, details, confidence_score) |
| E002 | 400 | Invalid timestamp format | Use ISO 8601 format: `2025-12-09T18:00:00Z` |
| E003 | 400 | Invalid severity value | Use: low, medium, high, critical |
| E004 | 404 | Anomaly not found | Verify anomaly ID is correct |
| E005 | 500 | Database connection failed | Check coordination engine logs, verify PostgreSQL connectivity |
| E006 | 500 | Remediation execution failed | Check Kubernetes API server logs, verify RBAC permissions |

---

### KServe

| Code | HTTP Status | Description | Resolution |
|------|-------------|-------------|------------|
| E101 | 400 | Invalid input shape | Check model input requirements (use GET /v1/models/{name}) |
| E102 | 404 | Model not found | Verify InferenceService exists and is ready |
| E103 | 503 | Model not ready | Wait for predictor pods to become ready |
| E104 | 500 | Model inference failed | Check predictor pod logs for errors |

---

### Tekton

| Code | HTTP Status | Description | Resolution |
|------|-------------|-------------|------------|
| E201 | 400 | Invalid pipeline parameters | Check required parameters for pipeline |
| E202 | 404 | Pipeline not found | Verify pipeline exists in namespace |
| E203 | 500 | Task execution failed | Check PipelineRun logs for task failures |

---

## SDK Examples

### Python Client (Coordination Engine)

```python
import requests
from datetime import datetime

class CoordinationEngineClient:
    def __init__(self, base_url='http://coordination-engine.self-healing-platform.svc.cluster.local:8080'):
        self.base_url = base_url
    
    def submit_anomaly(self, anomaly):
        """Submit anomaly for remediation."""
        response = requests.post(
            f'{self.base_url}/api/v1/anomalies',
            json=anomaly,
            timeout=10
        )
        response.raise_for_status()
        return response.json()
    
    def get_anomaly_status(self, anomaly_id):
        """Get anomaly status."""
        response = requests.get(
            f'{self.base_url}/api/v1/anomalies/{anomaly_id}',
            timeout=5
        )
        response.raise_for_status()
        return response.json()

# Usage
client = CoordinationEngineClient()

anomaly = {
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'type': 'cpu_spike',
    'severity': 'high',
    'source': 'custom',
    'details': {
        'namespace': 'production',
        'pod': 'app-server-abc123',
        'metric': 'cpu_percent',
        'value': 95.5
    },
    'confidence_score': 0.85
}

result = client.submit_anomaly(anomaly)
print(f"Submitted: {result['anomaly_id']}")

status = client.get_anomaly_status(result['anomaly_id'])
print(f"Status: {status['status']}")
```

---

## Related Documentation

- [How-To: Test Custom Applications with MCP](../how-to/test-custom-applications-with-mcp.md)
- [ADR-038: Go Coordination Engine Migration](../adrs/038-go-coordination-engine-migration.md)
- [ADR-004: KServe for Model Serving Infrastructure](../adrs/004-kserve-model-serving.md)
- [ADR-026: Secrets Management Automation](../adrs/026-secrets-management-automation.md)
- [ADR-053: Tekton Pipelines for Model Training](../adrs/053-tekton-model-training-pipelines.md)

---

**Questions or Issues?**

- GitHub Issues: https://github.com/KubeHeal/openshift-aiops-platform/issues
- Documentation: https://github.com/KubeHeal/openshift-aiops-platform/tree/main/docs
