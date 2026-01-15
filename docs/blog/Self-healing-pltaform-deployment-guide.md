# Building and Deploying an AI-Powered Self-Healing Platform on OpenShift

## A Complete Guide to Kubernetes-Native Autonomous Operations

---

## Executive Summary

This guide walks you through deploying an **AI-powered Self-Healing Platform** on Red Hat OpenShift. The platform combines **machine learning anomaly detection** with **rule-based remediation** to automatically detect, diagnose, and heal infrastructure issues—reducing Mean Time To Resolution (MTTR) from hours to minutes.

**What You'll Learn:**
- Why we built a custom Kubernetes Operator for self-healing
- The GitOps deployment pattern and why it matters
- How to deploy ML models alongside operational automation
- Production-ready patterns for enterprise environments

**Technologies Used:**
- Red Hat OpenShift 4.18+
- OpenShift AI (RHOAI) / Open Data Hub
- Prometheus & Alertmanager
- Helm, ArgoCD, Ansible
- Python, Scikit-learn, KServe

---

## Table of Contents

1. [The Problem: Why Self-Healing?](#1-the-problem-why-self-healing)
2. [Architecture Overview](#2-architecture-overview)
3. [Why We Built a Kubernetes Operator](#3-why-we-built-a-kubernetes-operator)
4. [Deployment Patterns & GitOps](#4-deployment-patterns--gitops)
5. [Prerequisites](#5-prerequisites)
6. [Step-by-Step Deployment](#6-step-by-step-deployment)
7. [ML Model Training & Deployment](#7-ml-model-training--deployment)
8. [Testing & Validation](#8-testing--validation)
9. [Production Considerations](#9-production-considerations)
10. [Conclusion](#10-conclusion)

---

## 1. The Problem: Why Self-Healing?

### The Reality of Modern Operations

In enterprise Kubernetes environments, operations teams face:

| Challenge | Impact |
|-----------|--------|
| **Alert Fatigue** | 500+ alerts/day, 80% are noise |
| **Mean Time To Detect (MTTD)** | 15-30 minutes average |
| **Mean Time To Resolve (MTTR)** | 2-4 hours for common issues |
| **Repetitive Tasks** | 60% of incidents are recurring patterns |
| **Skill Gap** | Not every engineer knows every system |

### The Solution: Autonomous Operations

Our Self-Healing Platform addresses these challenges by:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     TRADITIONAL vs SELF-HEALING                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  TRADITIONAL:                                                           │
│  Alert → PagerDuty → Human wakes up → SSH → Diagnose → Fix → Document  │
│  Time: 2-4 hours                                                        │
│                                                                         │
│  SELF-HEALING:                                                          │
│  Anomaly Detected → AI Diagnosis → Automated Remediation → Notify      │
│  Time: 2-5 minutes                                                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### What Problems Does It Solve?

1. **CrashLoopBackOff Pods** → Automatic log analysis, rollback, or resource adjustment
2. **Memory Leaks** → Detect trend, restart pod before OOM
3. **Resource Exhaustion** → Auto-scale or increase limits
4. **Failed Deployments** → Automatic rollback to last known good
5. **Storage Issues** → PVC cleanup, expansion recommendations

---

## 2. Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SELF-HEALING PLATFORM ARCHITECTURE                   │
└─────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────────┐
                              │   Prometheus    │
                              │   (Metrics)     │
                              └────────┬────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        DATA COLLECTION LAYER                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │ CPU Metrics │  │Memory Metrics│  │Pod Status   │  │API Server   │    │
│  │ 5,000+ pts  │  │ 5,000+ pts  │  │ 962 pts     │  │ Metrics     │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        ANOMALY DETECTION LAYER                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │ Isolation   │  │   ARIMA     │  │  Prophet    │  │    LSTM     │    │
│  │   Forest    │  │  Analysis   │  │  Forecast   │  │  Autoencoder│    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
│                              │                                          │
│                              ▼                                          │
│                    ┌─────────────────┐                                  │
│                    │ Ensemble Voting │                                  │
│                    │   (F1: 0.85+)   │                                  │
│                    └─────────────────┘                                  │
└─────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     SELF-HEALING OPERATOR (CRD)                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  SelfHealingPolicy CRD                                          │   │
│  │  ─────────────────────────────────────────────────────────────  │   │
│  │  - anomalyType: CrashLoopBackOff                                │   │
│  │  - action: restart | rollback | scale | adjust-resources        │   │
│  │  - confidence: 0.8                                              │   │
│  │  - cooldown: 5m                                                 │   │
│  │  - maxRetries: 3                                                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐            │
│  │ Rule Engine    │  │ AI Decision    │  │ Action         │            │
│  │ (Deterministic)│  │ (ML-based)     │  │ Executor       │            │
│  └────────────────┘  └────────────────┘  └────────────────┘            │
└─────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        REMEDIATION ACTIONS                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │ Pod Restart │  │  Rollback   │  │ Scale Up    │  │ Adjust      │    │
│  │             │  │  Deployment │  │             │  │ Resources   │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Breakdown

| Component | Purpose | Technology |
|-----------|---------|------------|
| **Metrics Collection** | Gather real-time cluster metrics | Prometheus, kube-state-metrics |
| **Anomaly Detection** | ML-based pattern recognition | Isolation Forest, ARIMA, Prophet, LSTM |
| **Self-Healing Operator** | Kubernetes-native automation | Go, Operator SDK, Custom CRDs |
| **Model Serving** | Real-time inference | KServe, OpenShift AI |
| **GitOps Deployment** | Declarative, auditable deployments | ArgoCD, Helm |

---

## 3. Why We Built a Kubernetes Operator

### The Operator Pattern

A Kubernetes Operator extends the Kubernetes API to manage complex applications. But why did we choose this pattern for self-healing?

### Why Not Just Use Scripts or CronJobs?

| Approach | Problems |
|----------|----------|
| **Bash Scripts** | No state management, no retry logic, no audit trail |
| **CronJobs** | Time-based, not event-driven; misses real-time issues |
| **External Tools** | Outside the cluster, network latency, authentication complexity |
| **Ansible Playbooks** | Great for provisioning, not for continuous reconciliation |

### Why an Operator?

```yaml
# The Operator Pattern gives us:

1. KUBERNETES-NATIVE:
   - Lives inside the cluster
   - Uses service accounts (no external credentials)
   - Leverages RBAC for security
   - Watches resources in real-time

2. DECLARATIVE:
   - Define WHAT you want, not HOW
   - Self-healing policies as Custom Resources
   - Version controlled, auditable

3. RECONCILIATION LOOP:
   - Continuously ensures desired state
   - Automatic retry on failure
   - Handles edge cases gracefully

4. EVENT-DRIVEN:
   - Reacts to changes immediately
   - No polling delays
   - Efficient resource usage
```

### Custom Resource Definition (CRD)

```yaml
# selfhealingpolicy-crd.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: selfhealingpolicies.aiops.example.com
spec:
  group: aiops.example.com
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                targetNamespace:
                  type: string
                anomalyType:
                  type: string
                  enum: [CrashLoopBackOff, MemoryLeak, CPUThrottling, StorageExhaustion]
                action:
                  type: string
                  enum: [restart, rollback, scale, adjust-resources, notify-only]
                confidenceThreshold:
                  type: number
                  minimum: 0.0
                  maximum: 1.0
                cooldownPeriod:
                  type: string
                maxRetries:
                  type: integer
                enabled:
                  type: boolean
  scope: Namespaced
  names:
    plural: selfhealingpolicies
    singular: selfhealingpolicy
    kind: SelfHealingPolicy
    shortNames:
      - shp
```

### Example Policy

```yaml
# crashloop-healing-policy.yaml
apiVersion: aiops.example.com/v1alpha1
kind: SelfHealingPolicy
metadata:
  name: crashloop-healing
  namespace: production
spec:
  targetNamespace: production
  anomalyType: CrashLoopBackOff
  action: rollback
  confidenceThreshold: 0.85
  cooldownPeriod: 5m
  maxRetries: 3
  enabled: true
  
  # Advanced options
  preChecks:
    - checkDeploymentHistory
    - checkResourceQuota
  postActions:
    - notifySlack
    - createIncidentTicket
```

---

## 4. Deployment Patterns & GitOps

### Why GitOps?

Traditional deployment:
```
Developer → kubectl apply → Cluster (hope it works!)
```

GitOps deployment:
```
Developer → Git PR → Review → Merge → ArgoCD → Cluster (audited, reversible)
```

### Our Deployment Pattern

We use a **layered deployment approach**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        DEPLOYMENT LAYERS                                │
└─────────────────────────────────────────────────────────────────────────┘

Layer 1: INFRASTRUCTURE (Ansible Automation Platform)
├── OpenShift cluster provisioning
├── Storage configuration
├── Network policies
└── Base RBAC setup

Layer 2: PLATFORM SERVICES (Helm + ArgoCD)
├── Prometheus/Alertmanager
├── OpenShift AI (RHOAI)
├── Kafka/AMQ Streams (optional)
└── Model storage (S3/MinIO)

Layer 3: APPLICATION (Helm + ArgoCD)
├── Self-Healing Operator
├── ML Model deployments (KServe)
├── Coordination Engine
└── Dashboard/UI

Layer 4: CONFIGURATION (Kustomize overlays)
├── Environment-specific values
├── SelfHealingPolicy CRs
├── AlertManager routes
└── Grafana dashboards
```

### Why This Pattern?

| Layer | Tool | Why |
|-------|------|-----|
| **Infrastructure** | Ansible | Idempotent, handles cloud APIs, inventory management |
| **Platform** | Helm + ArgoCD | Package management + GitOps for operators |
| **Application** | Helm + ArgoCD | Same tooling, consistent patterns |
| **Configuration** | Kustomize | Environment overlays without chart duplication |

### Repository Structure

```
openshift-aiops-platform/
├── ansible/
│   ├── playbooks/
│   │   ├── deploy-cluster.yml
│   │   ├── configure-storage.yml
│   │   └── setup-rbac.yml
│   ├── inventory/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── production/
│   └── execution-environment/
│       └── execution-environment.yml
│
├── charts/
│   ├── self-healing-operator/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── values-dev.yaml
│   │   ├── values-prod.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── rbac.yaml
│   │       ├── serviceaccount.yaml
│   │       └── crd.yaml
│   │
│   ├── anomaly-detector/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       └── inferenceservice.yaml
│   │
│   └── coordination-engine/
│       └── ...
│
├── argocd/
│   ├── applications/
│   │   ├── self-healing-operator.yaml
│   │   ├── anomaly-detector.yaml
│   │   └── coordination-engine.yaml
│   └── projects/
│       └── aiops-project.yaml
│
├── notebooks/
│   ├── 01-data-collection/
│   ├── 02-anomaly-detection/
│   ├── 03-self-healing-logic/
│   └── ...
│
└── docs/
    └── deployment-guide.md
```

---

## 5. Prerequisites

### Cluster Requirements

```yaml
OpenShift Version: 4.18+
Nodes:
  - Control Plane: 3x (m5.xlarge or equivalent)
  - Workers: 3x (m5.2xlarge or equivalent)
  - GPU (optional): 1x (g4dn.xlarge for LSTM training)

Storage:
  - Default StorageClass configured
  - 100GB+ for model storage PVC

Operators:
  - OpenShift AI (or Open Data Hub)
  - OpenShift GitOps (ArgoCD)
  - OpenShift Pipelines (optional)
```

### Required Permissions

```yaml
# Cluster-admin for initial setup, then:
ClusterRoles needed:
  - View pods/deployments/replicasets across namespaces
  - Create/delete pods (for restart actions)
  - Patch deployments (for rollback, scale)
  - Read Prometheus metrics
  - Create InferenceServices (KServe)
```

### Tools

```bash
# Local machine
oc version    # 4.18+
helm version  # 3.12+
ansible --version  # 2.14+
python --version   # 3.11+
```

---

## 6. Step-by-Step Deployment

### Step 1: Clone the Repository

```bash
git clone https://github.com/your-org/openshift-aiops-platform.git
cd openshift-aiops-platform
```

### Step 2: Build Ansible Execution Environment

```bash
# Build custom EE with required collections
cd ansible/execution-environment

cat > execution-environment.yml << 'EOF'
version: 3
images:
  base_image:
    name: registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel9:latest

dependencies:
  galaxy:
    collections:
      - kubernetes.core
      - redhat.openshift
      - community.general
  python:
    - kubernetes
    - openshift
  system:
    - python3-pip

additional_build_steps:
  append_final:
    - RUN pip3 install --upgrade openshift kubernetes
EOF

ansible-builder build -t aiops-ee:latest -f execution-environment.yml
```

### Step 3: Deploy RBAC

```bash
# Create namespace and RBAC
oc new-project self-healing

# Apply RBAC
cat > rbac.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: self-healing-operator
  namespace: self-healing
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: self-healing-operator
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "events"]
    verbs: ["get", "list", "watch", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch", "patch", "update"]
  - apiGroups: ["aiops.example.com"]
    resources: ["selfhealingpolicies"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: self-healing-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: self-healing-operator
subjects:
  - kind: ServiceAccount
    name: self-healing-operator
    namespace: self-healing
EOF

oc apply -f rbac.yaml
```

### Step 4: Deploy with Helm (Fix SCC)

```bash
# Important: OpenShift requires SCC configuration
cd charts/self-healing-operator

# Create values-openshift.yaml with SCC fix
cat > values-openshift.yaml << 'EOF'
# OpenShift-specific values
serviceAccount:
  create: true
  name: self-healing-operator

securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true

# Use anyuid SCC if needed (apply separately)
podAnnotations:
  openshift.io/scc: restricted-v2

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

prometheus:
  url: https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091
  
modelServing:
  enabled: true
  endpoint: http://anomaly-detector.self-healing.svc.cluster.local:8080
EOF

# Install the chart
helm upgrade --install self-healing-operator . \
  -f values.yaml \
  -f values-openshift.yaml \
  -n self-healing \
  --create-namespace
```

### Step 5: Configure ArgoCD Application

```bash
# Login to ArgoCD
ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')
ARGOCD_PASSWORD=$(oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d)

argocd login $ARGOCD_ROUTE --username admin --password $ARGOCD_PASSWORD --insecure

# Create the ArgoCD Application
cat > argocd/applications/self-healing-operator.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: self-healing-operator
  namespace: openshift-gitops
  labels:
    app.kubernetes.io/part-of: aiops-platform
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/openshift-aiops-platform.git
    targetRevision: main
    path: charts/self-healing-operator
    helm:
      valueFiles:
        - values.yaml
        - values-openshift.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: self-healing
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
EOF

oc apply -f argocd/applications/self-healing-operator.yaml
```

### Step 6: Deploy Model Storage

```bash
# Create PVC for models
cat > model-storage-pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-storage-pvc
  namespace: self-healing
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: gp3-csi  # Adjust for your cluster
EOF

oc apply -f model-storage-pvc.yaml
```

### Step 7: Deploy KServe InferenceService

```bash
# Deploy the anomaly detection model
cat > anomaly-detector-isvc.yaml << 'EOF'
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: anomaly-detector
  namespace: self-healing
  annotations:
    sidecar.istio.io/inject: "false"
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: pvc://model-storage-pvc/anomaly-detector
      resources:
        limits:
          cpu: "1"
          memory: 2Gi
        requests:
          cpu: 100m
          memory: 512Mi
EOF

oc apply -f anomaly-detector-isvc.yaml
```

---

## 7. ML Model Training & Deployment

### Training Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      ML MODEL TRAINING PIPELINE                         │
└─────────────────────────────────────────────────────────────────────────┘

    ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
    │  Prometheus  │────▶│   Jupyter    │────▶│   Model      │
    │   Metrics    │     │   Notebook   │     │   (.pkl)     │
    └──────────────┘     └──────────────┘     └──────────────┘
                                                     │
                                                     ▼
    ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
    │   KServe     │◀────│  Model PVC   │◀────│   S3/MinIO   │
    │  Inference   │     │   Storage    │     │   (backup)   │
    └──────────────┘     └──────────────┘     └──────────────┘
```

### 16 Working Prometheus Metrics

Our models are trained on these verified working metrics:

```python
TARGET_METRICS = [
    # Resource Metrics (5)
    'node_memory_utilization',      # Node memory usage %
    'pod_cpu_usage',                # Pod CPU cores
    'pod_memory_usage',             # Pod memory bytes
    'alt_cpu_usage',                # Container CPU rate
    'alt_memory_usage',             # Container memory RSS
    
    # Stability Metrics (3)
    'container_restart_count',      # Total restarts
    'container_restart_rate_1h',    # Restarts per hour
    'deployment_unavailable',       # Unavailable replicas
    
    # Pod Status Metrics (4)
    'namespace_pod_count',          # Pods per namespace
    'pods_pending',                 # Pending pods
    'pods_running',                 # Running pods
    'pods_failed',                  # Failed pods
    
    # Storage Metrics (2)
    'persistent_volume_usage',      # PVC usage %
    'cluster_resource_quota',       # Resource quotas
    
    # Control Plane Metrics (2)
    'apiserver_request_total',      # API request rate
    'apiserver_error_rate',         # API error rate %
]
```

### Training the Models

```bash
# Access Jupyter in OpenShift AI
oc get route -n redhat-ods-applications

# Run notebooks in order:
# 1. prometheus-metrics-collection.ipynb
# 2. isolation-forest-implementation.ipynb
# 3. time-series-anomaly-detection.ipynb
# 4. lstm-based-prediction.ipynb
# 5. ensemble-anomaly-methods.ipynb
```

### Model Performance

| Model | Precision | Recall | F1-Score |
|-------|-----------|--------|----------|
| Isolation Forest | 0.84 | 0.84 | 0.84 |
| ARIMA | 0.75 | 0.48 | 0.59 |
| Prophet | 0.79 | 0.44 | 0.56 |
| LSTM | 0.80 | 0.80 | 0.80 |
| **Ensemble (Hard Voting)** | **0.89** | **0.80** | **0.84** |

---

## 8. Testing & Validation

### Create a Test Scenario

```bash
# Deploy a crash-loop test pod
cat > crashloop-test.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crashloop-test
  namespace: self-healing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crashloop-test
  template:
    metadata:
      labels:
        app: crashloop-test
    spec:
      containers:
        - name: crash
          image: busybox
          command: ["/bin/sh", "-c", "echo 'Starting...'; sleep 5; exit 1"]
EOF

oc apply -f crashloop-test.yaml
```

### Apply Self-Healing Policy

```bash
cat > crashloop-policy.yaml << 'EOF'
apiVersion: aiops.example.com/v1alpha1
kind: SelfHealingPolicy
metadata:
  name: test-crashloop-healing
  namespace: self-healing
spec:
  targetNamespace: self-healing
  anomalyType: CrashLoopBackOff
  action: notify-only  # Safe for testing
  confidenceThreshold: 0.80
  cooldownPeriod: 2m
  maxRetries: 3
  enabled: true
EOF

oc apply -f crashloop-policy.yaml
```

### Verify Detection

```bash
# Watch the operator logs
oc logs -f deployment/self-healing-operator -n self-healing

# Expected output:
# INFO: Anomaly detected - Pod crashloop-test-xxx in CrashLoopBackOff
# INFO: Confidence: 0.92 (threshold: 0.80)
# INFO: Action: notify-only
# INFO: Notification sent to configured channel
```

### Validate Model Inference

```bash
# Test KServe endpoint
ISVC_URL=$(oc get inferenceservice anomaly-detector -n self-healing -o jsonpath='{.status.url}')

curl -X POST "$ISVC_URL/v1/models/anomaly-detector:predict" \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [[30.5, 65.2, 0.15, 0.12, 3, 0.5, 0, 45, 2, 42, 1, 0.25, 0, 150, 0.01]]
  }'

# Expected response:
# {"predictions": [1]}  # 1 = anomaly detected
```

---

## 9. Production Considerations

### Security

```yaml
# 1. Use least-privilege RBAC
# 2. Enable audit logging
# 3. Encrypt model storage
# 4. Use network policies

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: self-healing-operator-netpol
  namespace: self-healing
spec:
  podSelector:
    matchLabels:
      app: self-healing-operator
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: openshift-monitoring
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: openshift-monitoring
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: self-healing
```

### High Availability

```yaml
# Deploy operator with multiple replicas
replicaCount: 3

# Use pod anti-affinity
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: self-healing-operator
          topologyKey: kubernetes.io/hostname

# Configure leader election
leaderElection:
  enabled: true
  leaseDuration: 15s
  renewDeadline: 10s
  retryPeriod: 2s
```

### Monitoring the Self-Healer

```yaml
# Prometheus ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: self-healing-operator
  namespace: self-healing
spec:
  selector:
    matchLabels:
      app: self-healing-operator
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

### Key Metrics to Watch

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `selfhealing_anomalies_detected_total` | Total anomalies found | > 100/hour |
| `selfhealing_actions_executed_total` | Remediation actions taken | > 50/hour |
| `selfhealing_action_success_rate` | % of successful healings | < 80% |
| `selfhealing_model_inference_latency` | ML model response time | > 500ms |

---

## 10. Conclusion

### What We Built

An **AI-powered Self-Healing Platform** that:

✅ **Detects** anomalies using ensemble ML (F1: 0.84+)
✅ **Diagnoses** root causes using trained models
✅ **Heals** automatically via Kubernetes Operator
✅ **Deploys** via GitOps for auditability
✅ **Scales** for enterprise production use

### Key Design Decisions

| Decision | Why |
|----------|-----|
| **Kubernetes Operator** | Native integration, event-driven, reconciliation loop |
| **Custom CRD** | Declarative policies, version controlled |
| **GitOps (ArgoCD)** | Auditable, reversible, automated sync |
| **Helm Charts** | Parameterized, reusable, environment-specific |
| **Ensemble ML** | Multiple models reduce false positives |
| **KServe** | Standard model serving, auto-scaling |

### Next Steps

1. **Extend policies** for more anomaly types
2. **Add more ML models** (transformers, graph neural networks)
3. **Integrate with ITSM** (ServiceNow, Jira)
4. **Build dashboards** (Grafana, custom UI)
5. **Implement feedback loop** to improve models over time

### Resources

- [GitHub Repository](https://github.com/your-org/openshift-aiops-platform)
- [Operator SDK Documentation](https://sdk.operatorframework.io/)
- [KServe Documentation](https://kserve.github.io/website/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

---

## Appendix: Quick Reference Commands

```bash
# Deploy everything
./deploy.sh --env production

# Check operator status
oc get pods -n self-healing
oc logs -f deployment/self-healing-operator -n self-healing

# View policies
oc get selfhealingpolicies -A

# Test model endpoint
curl -X POST "$ISVC_URL/v1/models/anomaly-detector:predict" -d '...'

# Sync ArgoCD
argocd app sync self-healing-operator

# Rollback
argocd app rollback self-healing-operator
```

---

*Last Updated: January 2026*
*Author: Sangeetha Bhaskaran , OpenShift Specialist Architect*
