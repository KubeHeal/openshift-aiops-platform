# Self-Healing Sequence Diagrams

## Overview

These sequence diagrams show the time-ordered interactions between components during the platform's core workflows: anomaly detection and remediation, model training, and incident response.

**Audience**: Developers, SREs, and ML engineers who need to understand the runtime behavior of the self-healing system.

## Sequence 1: Anomaly Detection and Remediation

This sequence shows what happens when the platform detects an anomaly and automatically remediates it.

```mermaid
sequenceDiagram
    participant PROM as Prometheus
    participant AM as AlertManager
    participant CE as Coordination Engine
    participant AD as anomaly-detector<br>(KServe)
    participant PA as predictive-analytics<br>(KServe)
    participant K8S as OpenShift API
    participant LS as Lightspeed<br>(via MCP)

    Note over PROM,AM: Phase 1: Detection
    PROM->>PROM: Scrape cluster metrics (30s interval)
    PROM->>AM: Alert fires (memory > 90%)
    AM->>CE: Webhook: critical alert payload

    Note over CE,PA: Phase 2: Analysis
    CE->>CE: Check known patterns database
    CE->>AD: POST /v1/models/anomaly-detector:predict<br>{"instances": [[cpu, mem, disk, net_in, net_out]]}
    AD-->>CE: {"predictions": [1]}<br>anomaly_score: 0.92

    CE->>PA: POST /v1/models/predictive-analytics:predict<br>{"instances": [[feature_vector]]}
    PA-->>CE: {"predictions": [0.87]}<br>failure_probability: high, horizon: 15min

    Note over CE,K8S: Phase 3: Decision
    CE->>CE: Evaluate confidence scores
    alt Known pattern (deterministic)
        CE->>CE: Match rule: memory_exhaustion -> restart_pod
        CE->>K8S: DELETE pod/app-server-xyz (graceful)
        K8S-->>CE: Pod deleted, replacement scheduled
    else Novel anomaly (AI-driven, confidence > 80%)
        CE->>CE: AI recommends: scale deployment + adjust limits
        CE->>K8S: PATCH deployment/app-server replicas=3
        K8S-->>CE: Deployment scaled
        CE->>K8S: PATCH deployment/app-server memory_limit=2Gi
        K8S-->>CE: Limits adjusted
    end

    Note over CE,PROM: Phase 4: Verification
    CE->>CE: Wait 60s for metrics stabilization
    CE->>PROM: Query: memory_usage{pod=~"app-server.*"}
    PROM-->>CE: Memory normalized to 65%

    alt Resolved
        CE->>CE: Log incident as resolved
        CE->>CE: Update training dataset
    else Not resolved
        CE->>LS: Escalate via MCP: "Automated remediation<br>did not resolve memory issue on app-server"
        LS-->>CE: Human operator notified
    end
```

## Sequence 2: Model Training Pipeline

This sequence shows the end-to-end model training flow triggered by a Tekton CronJob.

```mermaid
sequenceDiagram
    participant CRON as CronJob<br>(weekly trigger)
    participant TEK as Tekton Pipeline
    participant NVJ as NotebookValidation<br>Job (Operator)
    participant NB as Training Notebook
    participant PROM2 as Prometheus
    participant PVC as Model PVC
    participant S3 as S3 Bucket
    participant KS as KServe<br>InferenceService

    Note over CRON,TEK: Trigger
    CRON->>TEK: Create PipelineRun<br>(model: anomaly-detector)

    Note over TEK,S3: Task 1: Train Model
    TEK->>NVJ: Create NotebookValidationJob CR
    NVJ->>NVJ: Pull notebook from Git
    NVJ->>NB: Execute notebook in container

    NB->>PROM2: Query: 7 days of cluster metrics
    PROM2-->>NB: Time series data (CPU, mem, disk, network)
    NB->>NB: Feature engineering<br>(rolling stats, rate of change)
    NB->>NB: Train Isolation Forest model
    NB->>NB: Evaluate: accuracy, precision, recall
    NB->>PVC: Save model.pkl to /mnt/models/anomaly-detector/

    NVJ-->>TEK: NotebookValidationJob: status=Succeeded

    Note over TEK,PVC: Task 2: Health Check
    TEK->>PVC: Check model file exists (> 1KB)
    TEK->>TEK: Load model with joblib
    TEK->>TEK: Run predictions on test data
    TEK-->>TEK: All health checks passed

    Note over TEK,S3: Task 3: Upload and Deploy
    TEK->>S3: Upload model.pkl to s3://model-storage/anomaly-detector/
    TEK->>KS: Restart predictor pods<br>(oc rollout restart)
    KS->>S3: Load new model from S3
    KS-->>TEK: Predictor pods ready

    Note over TEK,KS: Task 4: Post-Deployment Validation
    TEK->>KS: POST /v1/models/anomaly-detector:predict<br>(test data)
    KS-->>TEK: Predictions returned successfully
    TEK-->>CRON: PipelineRun: status=Succeeded
```

## Sequence 3: Incident Response with Lightspeed

This sequence shows how a human operator interacts with the platform through OpenShift Lightspeed using the MCP protocol.

```mermaid
sequenceDiagram
    actor OP as Platform Engineer
    participant LS2 as OpenShift Lightspeed
    participant MCP as MCP Server
    participant CE2 as Coordination Engine
    participant PROM3 as Prometheus
    participant K8S2 as OpenShift API

    Note over OP,MCP: Natural Language Query
    OP->>LS2: "What anomalies were detected<br>in the last hour?"
    LS2->>MCP: MCP tool call: list_incidents(timeframe=1h)
    MCP->>CE2: GET /api/v1/incidents?since=1h
    CE2-->>MCP: [{id: "inc-42", type: "memory_exhaustion",<br>severity: "critical", status: "auto-remediated"}]
    MCP-->>LS2: Structured incident list
    LS2-->>OP: "One critical incident detected:<br>Memory exhaustion on worker-2,<br>auto-remediated by pod restart."

    Note over OP,K8S2: Drill-Down Query
    OP->>LS2: "Show me the cluster health metrics"
    LS2->>MCP: MCP tool call: get_cluster_health()
    MCP->>PROM3: Query: cluster CPU, memory, disk usage
    PROM3-->>MCP: Current metrics snapshot
    MCP->>K8S2: GET /api/v1/nodes (status)
    K8S2-->>MCP: Node conditions
    MCP-->>LS2: Health summary with metrics
    LS2-->>OP: "Cluster health: 3/3 nodes ready.<br>CPU: 42%, Memory: 68%, Disk: 31%.<br>No active alerts."

    Note over OP,CE2: Manual Override
    OP->>LS2: "Scale the app-server deployment to 5 replicas"
    LS2->>MCP: MCP tool call: trigger_remediation(<br>action=scale, target=app-server, replicas=5)
    MCP->>CE2: POST /api/v1/remediation/trigger
    CE2->>K8S2: PATCH deployment/app-server replicas=5
    K8S2-->>CE2: Deployment scaled
    CE2-->>MCP: Remediation executed
    MCP-->>LS2: Action confirmed
    LS2-->>OP: "Scaled app-server to 5 replicas.<br>All pods running and ready."
```

## Sequence 4: OOM Kill Detection and Auto-Remediation

This sequence shows the coordination engine's OOM remediation feature (v1.2.0), which automatically adjusts memory limits for pods that are repeatedly OOM-killed.

```mermaid
sequenceDiagram
    participant K8S3 as OpenShift API
    participant CE3 as Coordination Engine
    participant AD2 as anomaly-detector<br>(KServe)

    Note over K8S3,CE3: OOM Event Detection
    K8S3->>CE3: Watch event: Pod OOMKilled<br>(namespace: production, pod: api-server-abc)
    CE3->>CE3: Check OOM history for pod
    CE3->>CE3: Current limit: 512Mi,<br>multiplier: 2.5x,<br>max: 2Gi

    Note over CE3,AD2: Anomaly Correlation
    CE3->>AD2: POST predict: Is this a systemic issue?
    AD2-->>CE3: anomaly_score: 0.45 (isolated event)

    Note over CE3,K8S3: Remediation
    CE3->>CE3: Calculate new limit:<br>512Mi x 2.5 = 1280Mi
    CE3->>CE3: Check against max (2Gi): OK
    CE3->>K8S3: PATCH deployment/api-server<br>memory_limit: 1280Mi
    K8S3-->>CE3: Deployment patched
    K8S3->>K8S3: Rolling restart with new limits

    Note over CE3: Notification
    CE3->>CE3: Log incident: OOM remediation applied
    alt Slack webhook configured
        CE3->>CE3: POST to Slack webhook
    end
    alt PagerDuty configured
        CE3->>CE3: POST to PagerDuty routing key
    end
```

## Notes

- **Confidence threshold**: The coordination engine requires a minimum 80% confidence score before executing AI-driven remediation. Below this threshold, the issue is escalated to a human operator.
- **Deterministic rules take priority**: Known failure patterns (OOM kills, CrashLoopBackOff, resource exhaustion) are handled by deterministic rules before querying AI models.
- **Conflict resolution**: The coordination engine prevents simultaneous contradictory actions (for example, scaling up and scaling down the same deployment).
- **MCP integration is bidirectional**: Lightspeed can query the platform for status and can trigger remediation actions through the MCP protocol.
- **OOM remediation** uses a configurable multiplier (default 2.5x) with a configurable ceiling (default 2Gi) to prevent runaway memory allocation.
- **Alert webhooks** (Slack, PagerDuty, AlertManager) are optional and configured via `coordinationEngine.alertWebhooks` in `values-hub.yaml`.
