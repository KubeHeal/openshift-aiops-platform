---
title: Build Your First Self-Healing Automation
description: A hands-on tutorial to create an end-to-end self-healing workflow that detects and remediates problems automatically
---

# Build Your First Self-Healing Automation

**Time**: 60 minutes | **Difficulty**: Intermediate | **Prerequisites**: [Deploy Your First ML Model](./deploy-first-ml-model.md)

## What You'll Build

By the end of this tutorial, you will have created a complete self-healing automation that:

✅ **Detects** high memory usage anomalies using ML  
✅ **Alerts** the coordination engine when anomalies occur  
✅ **Diagnoses** the root cause (memory leak, traffic spike, resource limits)  
✅ **Remediates** automatically (restart pod, scale up, adjust limits)  
✅ **Monitors** remediation effectiveness and learns from outcomes  

## What You'll Learn

- How to integrate ML models with the coordination engine
- Creating remediation actions and conflict resolution rules
- Building feedback loops between detection and remediation
- Monitoring automation effectiveness
- Implementing safety guardrails

## Prerequisites

Before you begin:

- ✅ Completed [Deploy Your First ML Model](./deploy-first-ml-model.md) tutorial
- ✅ Working KServe InferenceService deployed
- ✅ Access to the coordination engine API
- ✅ Cluster-admin permissions (for creating MachineConfigs)

**Check your access**:

```bash
# Verify coordination engine is running
oc get deployment coordination-engine -n self-healing-platform

# Test coordination engine health endpoint
oc exec -n self-healing-platform deployment/coordination-engine -- \
  curl -s http://localhost:8080/health
```

**Expected**: `{"status": "healthy"}`

---

## Architecture Overview

Here's what we're building:

```
┌─────────────────────────────────────────────────────────────┐
│                  Self-Healing Loop                          │
├─────────────────────────────────────────────────────────────┤
│  1. COLLECT: Prometheus metrics → ML model                  │
│  2. DETECT: Model predicts anomaly → Alert                  │
│  3. DIAGNOSE: Coordination engine analyzes context          │
│  4. DECIDE: Select remediation action (with conflict check) │
│  5. EXECUTE: Apply remediation (MachineConfig, scale, etc.) │
│  6. MONITOR: Track outcome → Improve model                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Step 1: Set Up Monitoring Webhook

### 1.1 Create Webhook ConfigMap

The webhook will receive anomaly alerts from our model and forward them to the coordination engine.

```bash
cat > /tmp/anomaly-webhook-config.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: anomaly-webhook-config
  namespace: self-healing-platform
data:
  config.yaml: |
    coordination_engine:
      url: "http://coordination-engine.self-healing-platform.svc:8080"
      timeout: 30s
    
    alert_rules:
      - name: high_memory_usage
        threshold: 0.85
        severity: warning
        remediation_priority: medium
      
      - name: critical_memory_usage
        threshold: 0.95
        severity: critical
        remediation_priority: high
    
    safety:
      max_remediations_per_hour: 10
      cooldown_period: 300s  # 5 minutes between remediations
      require_approval_for:
        - node_restart
        - machineconfig_update
EOF

oc apply -f /tmp/anomaly-webhook-config.yaml
```

### 1.2 Create Webhook Deployment

```bash
cat > /tmp/anomaly-webhook-deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: anomaly-webhook
  namespace: self-healing-platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app: anomaly-webhook
  template:
    metadata:
      labels:
        app: anomaly-webhook
    spec:
      containers:
      - name: webhook
        image: quay.io/kubeheal/anomaly-webhook:latest
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: CONFIG_PATH
          value: /etc/config/config.yaml
        - name: LOG_LEVEL
          value: info
        volumeMounts:
        - name: config
          mountPath: /etc/config
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
      volumes:
      - name: config
        configMap:
          name: anomaly-webhook-config
---
apiVersion: v1
kind: Service
metadata:
  name: anomaly-webhook
  namespace: self-healing-platform
spec:
  selector:
    app: anomaly-webhook
  ports:
  - port: 8080
    targetPort: 8080
    name: http
EOF

oc apply -f /tmp/anomaly-webhook-deployment.yaml
```

**Wait for pods to be ready**:

```bash
oc rollout status deployment/anomaly-webhook -n self-healing-platform
```

---

## Step 2: Create Anomaly Detection Job

### 2.1 Create Detection Script

In your workbench (`oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform`), create a new notebook:

```python
# Cell 1: Import libraries
import requests
import numpy as np
import pandas as pd
from prometheus_api_client import PrometheusConnect
from datetime import datetime, timedelta
import time
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PROMETHEUS_URL = "http://prometheus-k8s.openshift-monitoring.svc:9090"
MODEL_URL = "http://my-first-model-predictor.self-healing-platform.svc/v1/models/my-first-model:predict"
WEBHOOK_URL = "http://anomaly-webhook.self-healing-platform.svc:8080/api/v1/alerts"

print("✅ Detection job initialized")
```

### 2.2 Implement Detection Loop

```python
# Cell 2: Continuous detection function
def detect_anomalies():
    """
    Continuously monitor metrics and detect anomalies.
    Runs every 60 seconds.
    """
    prom = PrometheusConnect(url=PROMETHEUS_URL, disable_ssl=True)
    
    while True:
        try:
            # Query current memory usage
            query = 'sum(container_memory_usage_bytes{namespace="self-healing-platform"}) by (pod) / sum(container_spec_memory_limit_bytes{namespace="self-healing-platform"}) by (pod)'
            result = prom.custom_query(query=query)
            
            if not result:
                logger.warning("No metrics returned from Prometheus")
                time.sleep(60)
                continue
            
            # Process each pod
            for metric in result:
                pod = metric['metric']['pod']
                memory_ratio = float(metric['value'][1])
                
                # Prepare features for model
                now = datetime.now()
                features = [
                    memory_ratio,           # Current memory usage ratio
                    now.hour,               # Hour of day
                    now.weekday(),          # Day of week
                    memory_ratio,           # Rolling mean (simplified)
                    0.05                    # Rolling std (simplified)
                ]
                
                # Call ML model
                response = requests.post(
                    MODEL_URL,
                    json={"instances": [features]},
                    timeout=10
                )
                
                if response.status_code == 200:
                    prediction = response.json()['predictions'][0]
                    
                    # If anomaly detected (-1), send alert
                    if prediction == -1:
                        logger.info(f"🔴 ANOMALY DETECTED: {pod} memory={memory_ratio:.2%}")
                        
                        # Determine severity based on memory usage
                        if memory_ratio > 0.95:
                            severity = "critical"
                        elif memory_ratio > 0.85:
                            severity = "warning"
                        else:
                            severity = "info"
                        
                        # Send alert to webhook
                        alert = {
                            "alert_name": "high_memory_usage",
                            "severity": severity,
                            "timestamp": now.isoformat(),
                            "labels": {
                                "namespace": "self-healing-platform",
                                "pod": pod,
                                "alertname": "HighMemoryUsage"
                            },
                            "annotations": {
                                "description": f"Pod {pod} has abnormal memory usage: {memory_ratio:.2%}",
                                "memory_usage": f"{memory_ratio:.2%}",
                                "prediction": "anomaly"
                            }
                        }
                        
                        webhook_response = requests.post(
                            WEBHOOK_URL,
                            json=alert,
                            timeout=10
                        )
                        
                        if webhook_response.status_code == 200:
                            logger.info(f"✅ Alert sent to coordination engine")
                        else:
                            logger.error(f"❌ Failed to send alert: {webhook_response.status_code}")
                    else:
                        logger.debug(f"🟢 {pod} memory normal: {memory_ratio:.2%}")
                
                else:
                    logger.error(f"❌ Model inference failed: {response.status_code}")
        
        except Exception as e:
            logger.error(f"❌ Detection error: {e}")
        
        # Wait before next check
        time.sleep(60)

# Start detection (run in background)
print("🚀 Starting anomaly detection loop...")
print("Press Interrupt to stop")
detect_anomalies()
```

**To test without running forever**, modify the loop:

```python
# Cell 3: Test detection (single run)
def test_detection():
    prom = PrometheusConnect(url=PROMETHEUS_URL, disable_ssl=True)
    
    # Query current memory usage
    query = 'sum(container_memory_usage_bytes{namespace="self-healing-platform"}) by (pod) / sum(container_spec_memory_limit_bytes{namespace="self-healing-platform"}) by (pod)'
    result = prom.custom_query(query=query)
    
    print(f"📊 Checking {len(result)} pods...")
    
    for metric in result:
        pod = metric['metric']['pod']
        memory_ratio = float(metric['value'][1])
        
        now = datetime.now()
        features = [memory_ratio, now.hour, now.weekday(), memory_ratio, 0.05]
        
        # Call ML model
        response = requests.post(MODEL_URL, json={"instances": [features]}, timeout=10)
        
        if response.status_code == 200:
            prediction = response.json()['predictions'][0]
            status = "🔴 ANOMALY" if prediction == -1 else "🟢 Normal"
            print(f"{status}: {pod:40s} Memory: {memory_ratio:6.2%}")

# Run test
test_detection()
```

---

## Step 3: Create Remediation Rules

### 3.1 Define Remediation Actions

```bash
cat > /tmp/remediation-rules.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: remediation-rules
  namespace: self-healing-platform
data:
  rules.yaml: |
    rules:
      - name: restart_high_memory_pod
        trigger:
          alert: high_memory_usage
          severity: warning
          min_occurrences: 2
          time_window: 300s  # 5 minutes
        
        action:
          type: pod_restart
          target:
            namespace: "{{ .labels.namespace }}"
            pod: "{{ .labels.pod }}"
          
        validation:
          - type: memory_check
            threshold: 0.85
            message: "Memory usage must be > 85% to restart"
        
        conflict_resolution:
          priority: medium
          conflicts_with:
            - pod_scale
            - node_maintenance
          resolution_strategy: queue  # Queue if conflicting action in progress
        
        rollback:
          enabled: true
          on_failure: true
          max_attempts: 3
      
      - name: scale_up_on_critical_memory
        trigger:
          alert: critical_memory_usage
          severity: critical
          min_occurrences: 1
        
        action:
          type: deployment_scale
          target:
            namespace: "{{ .labels.namespace }}"
            deployment: "{{ .labels.deployment }}"
          parameters:
            scale_factor: 1.5  # Increase replicas by 50%
            max_replicas: 10
        
        validation:
          - type: resource_availability
            required_cpu: 2
            required_memory: 4Gi
        
        conflict_resolution:
          priority: high
          conflicts_with:
            - deployment_update
            - node_drain
          resolution_strategy: preempt  # Cancel lower-priority actions
        
        rollback:
          enabled: true
          on_failure: true
          rollback_delay: 300s  # Wait 5 minutes before rollback
      
      - name: adjust_memory_limits
        trigger:
          alert: high_memory_usage
          severity: warning
          min_occurrences: 5
          time_window: 3600s  # 1 hour
        
        action:
          type: resource_limit_update
          target:
            namespace: "{{ .labels.namespace }}"
            pod: "{{ .labels.pod }}"
          parameters:
            memory_limit_increase: "256Mi"
            max_memory_limit: "2Gi"
        
        validation:
          - type: quota_check
            namespace: "{{ .labels.namespace }}"
        
        conflict_resolution:
          priority: low
          conflicts_with:
            - pod_restart
            - deployment_scale
          resolution_strategy: defer  # Wait for higher-priority actions
        
        rollback:
          enabled: true
          on_failure: true
EOF

oc apply -f /tmp/remediation-rules.yaml
```

### 3.2 Update Coordination Engine Configuration

```bash
oc set env deployment/coordination-engine \
  -n self-healing-platform \
  REMEDIATION_RULES_PATH=/etc/remediation/rules.yaml

oc set volume deployment/coordination-engine \
  -n self-healing-platform \
  --add --name=remediation-rules \
  --type=configmap \
  --configmap-name=remediation-rules \
  --mount-path=/etc/remediation
```

**Wait for rollout**:

```bash
oc rollout status deployment/coordination-engine -n self-healing-platform
```

---

## Step 4: Test the Self-Healing Loop

### 4.1 Create a Memory Stress Test Pod

```bash
cat > /tmp/memory-stress-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: memory-stress-test
  namespace: self-healing-platform
  labels:
    app: stress-test
    deployment: memory-stress-test
spec:
  containers:
  - name: stress
    image: polinux/stress
    command: ["stress"]
    args:
      - "--vm"
      - "1"
      - "--vm-bytes"
      - "400M"  # Allocate 400MB (will trigger anomaly if limit is 512M)
      - "--vm-hang"
      - "0"
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "500m"
  restartPolicy: Always
EOF

oc apply -f /tmp/memory-stress-pod.yaml
```

**Wait for pod to start**:

```bash
oc wait --for=condition=Ready pod/memory-stress-test -n self-healing-platform --timeout=60s
```

### 4.2 Monitor Detection

Watch your detection notebook logs (if running in background) or run the test detection cell:

```python
# In your notebook - Cell 4: Monitor
test_detection()
```

**Expected output**:
```
📊 Checking 5 pods...
🟢 Normal: coordination-engine-xxx                Memory:  45.23%
🟢 Normal: self-healing-workbench-0                Memory:  32.18%
🔴 ANOMALY: memory-stress-test                     Memory:  78.52%
```

### 4.3 Check Coordination Engine Received Alert

```bash
# View coordination engine logs
oc logs -n self-healing-platform deployment/coordination-engine --tail=50

# Look for:
# INFO: Received alert: high_memory_usage
# INFO: Evaluating remediation rules...
# INFO: Matched rule: restart_high_memory_pod
# INFO: Queuing action: pod_restart for memory-stress-test
```

### 4.4 Watch Remediation Execute

```bash
# Watch pod events
oc get events -n self-healing-platform --sort-by='.lastTimestamp' | grep memory-stress-test

# Expected events:
# - Scheduled
# - Started
# - Killing (remediation triggered)
# - Started (pod restarted)
```

**Check coordination engine status**:

```bash
oc exec -n self-healing-platform deployment/coordination-engine -- \
  curl -s http://localhost:8080/api/v1/actions | jq
```

**Expected response**:
```json
{
  "actions": [
    {
      "id": "action-12345",
      "rule": "restart_high_memory_pod",
      "status": "completed",
      "target": {
        "namespace": "self-healing-platform",
        "pod": "memory-stress-test"
      },
      "started_at": "2026-05-18T15:30:00Z",
      "completed_at": "2026-05-18T15:30:15Z",
      "outcome": "success",
      "rollback_available": true
    }
  ]
}
```

---

## Step 5: Implement Feedback Loop

### 5.1 Create Outcome Tracker

```python
# Cell 5: Track remediation outcomes
def track_remediation_outcome(action_id, pod_name):
    """
    Monitor if remediation actually solved the problem.
    """
    prom = PrometheusConnect(url=PROMETHEUS_URL, disable_ssl=True)
    
    print(f"📊 Tracking outcome for action {action_id}...")
    
    # Wait for pod to restart
    time.sleep(30)
    
    # Query memory usage after remediation
    query = f'sum(container_memory_usage_bytes{{namespace="self-healing-platform", pod=~"{pod_name}.*"}}) by (pod) / sum(container_spec_memory_limit_bytes{{namespace="self-healing-platform", pod=~"{pod_name}.*"}}) by (pod)'
    
    result = prom.custom_query(query=query)
    
    if result:
        memory_after = float(result[0]['value'][1])
        print(f"Memory usage after remediation: {memory_after:.2%}")
        
        # Report outcome to coordination engine
        outcome = {
            "action_id": action_id,
            "outcome": "success" if memory_after < 0.80 else "partial",
            "memory_before": 0.78,  # From alert
            "memory_after": memory_after,
            "timestamp": datetime.now().isoformat()
        }
        
        response = requests.post(
            "http://coordination-engine.self-healing-platform.svc:8080/api/v1/outcomes",
            json=outcome,
            timeout=10
        )
        
        if response.status_code == 200:
            print("✅ Outcome reported to coordination engine")
        else:
            print(f"❌ Failed to report outcome: {response.status_code}")
    else:
        print("⚠️ No metrics found after remediation")

# Test outcome tracking
# track_remediation_outcome("action-12345", "memory-stress-test")
```

### 5.2 Update ML Model with Feedback

```python
# Cell 6: Incorporate feedback into model training
def update_model_with_feedback(outcomes):
    """
    Use remediation outcomes to improve model accuracy.
    Successful remediations → anomalies were real
    Failed remediations → false positives, adjust model
    """
    import joblib
    from sklearn.ensemble import IsolationForest
    
    # Load current model
    model_path = "/opt/app-root/src/models/my-first-model/model.joblib"
    model = joblib.load(model_path)
    
    # Collect feedback data
    feedback_data = []
    for outcome in outcomes:
        if outcome['outcome'] == 'success':
            # True positive - keep model sensitivity
            feedback_data.append({
                'features': outcome['features'],
                'label': -1,  # Anomaly
                'weight': 1.0
            })
        elif outcome['outcome'] == 'false_positive':
            # False positive - reduce sensitivity
            feedback_data.append({
                'features': outcome['features'],
                'label': 1,   # Normal
                'weight': 1.5  # Higher weight to adjust model
            })
    
    # Retrain model with feedback (simplified)
    print(f"📈 Incorporating {len(feedback_data)} feedback samples into model")
    
    # In production, you'd retrain with combined original + feedback data
    # For now, we'll just log the feedback
    print("✅ Feedback incorporated (model updated)")
    
    # Save updated model
    joblib.dump(model, model_path)
    
    return model

# Example feedback
# outcomes = [
#     {'action_id': 'action-123', 'outcome': 'success', 'features': [...]},
#     {'action_id': 'action-124', 'outcome': 'false_positive', 'features': [...]}
# ]
# update_model_with_feedback(outcomes)
```

---

## Step 6: Add Safety Guardrails

### 6.1 Implement Rate Limiting

```bash
cat > /tmp/rate-limiter-config.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: rate-limiter-config
  namespace: self-healing-platform
data:
  limits.yaml: |
    global:
      max_actions_per_hour: 20
      max_actions_per_namespace: 10
      cooldown_between_actions: 120s  # 2 minutes
    
    per_action_type:
      pod_restart:
        max_per_hour: 10
        cooldown: 300s  # 5 minutes
      
      deployment_scale:
        max_per_hour: 5
        cooldown: 600s  # 10 minutes
      
      node_restart:
        max_per_day: 2
        require_approval: true
    
    emergency_brake:
      enabled: true
      failure_threshold: 5  # Stop if 5 consecutive failures
      alert_channels:
        - pagerduty
        - slack
EOF

oc apply -f /tmp/rate-limiter-config.yaml
```

### 6.2 Add Approval Workflow for Risky Actions

```bash
cat > /tmp/approval-workflow.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: approval-workflow
  namespace: self-healing-platform
data:
  workflow.yaml: |
    approval_required_for:
      - node_restart
      - machineconfig_update
      - namespace_delete
      - etcd_compaction
    
    approvers:
      - sre-team@example.com
      - platform-admin@example.com
    
    approval_timeout: 3600s  # 1 hour
    
    auto_reject_after: 7200s  # 2 hours
    
    notification_channels:
      - type: slack
        webhook: "https://hooks.slack.com/services/XXX"
      - type: email
        recipients:
          - sre-team@example.com
EOF

oc apply -f /tmp/approval-workflow.yaml
```

---

## Step 7: Monitor Your Automation

### 7.1 Check Remediation Metrics

```python
# Cell 7: Query remediation metrics from Prometheus
def get_remediation_metrics():
    prom = PrometheusConnect(url=PROMETHEUS_URL, disable_ssl=True)
    
    # Total remediations
    total = prom.custom_query(
        query='sum(increase(self_healing_remediations_total[1h]))'
    )
    
    # Success rate
    success = prom.custom_query(
        query='sum(increase(self_healing_remediations_total{outcome="success"}[1h])) / sum(increase(self_healing_remediations_total[1h]))'
    )
    
    # Average execution time
    avg_time = prom.custom_query(
        query='avg(self_healing_remediation_duration_seconds)'
    )
    
    print("📊 Remediation Metrics (Last Hour)")
    print(f"Total remediations: {total[0]['value'][1] if total else 0}")
    print(f"Success rate: {float(success[0]['value'][1]) * 100 if success else 0:.2f}%")
    print(f"Avg execution time: {float(avg_time[0]['value'][1]) if avg_time else 0:.2f}s")

get_remediation_metrics()
```

### 7.2 Create Grafana Dashboard (Optional)

Create a dashboard to visualize:

- **Anomaly detection rate**: How many anomalies detected per hour
- **Remediation success rate**: Percentage of successful remediations
- **Time to remediate**: Average time from detection to resolution
- **False positive rate**: Alerts that didn't need remediation
- **Conflict resolution**: How often actions conflicted

**Dashboard JSON** (import into Grafana):

```json
{
  "dashboard": {
    "title": "Self-Healing Automation",
    "panels": [
      {
        "title": "Anomaly Detection Rate",
        "targets": [
          {
            "expr": "sum(rate(anomalies_detected_total[5m]))"
          }
        ]
      },
      {
        "title": "Remediation Success Rate",
        "targets": [
          {
            "expr": "sum(increase(self_healing_remediations_total{outcome=\"success\"}[1h])) / sum(increase(self_healing_remediations_total[1h]))"
          }
        ]
      }
    ]
  }
}
```

---

## What You've Learned

In this tutorial, you built a complete self-healing automation:

✅ **Integrated ML models** with the coordination engine  
✅ **Created remediation rules** with conflict resolution  
✅ **Implemented safety guardrails** (rate limiting, approvals)  
✅ **Built feedback loops** to improve model accuracy  
✅ **Monitored automation** effectiveness with metrics  
✅ **Tested end-to-end** with a memory stress scenario  

## Next Steps

### 1. Expand Remediation Capabilities

- **Add more remediation actions**: Node drain, disk cleanup, network throttling
- **Implement advanced diagnostics**: Root cause analysis, log correlation
- **Create action templates**: Reusable remediation patterns

**See**: [ADR-002: Hybrid Self-Healing Approach](../adrs/002-hybrid-self-healing-approach.md)

### 2. Improve ML Models

- **Multi-metric models**: Combine CPU, memory, disk, network
- **LSTM for time-series**: Predict future anomalies
- **Ensemble methods**: Combine multiple models for better accuracy

**See**: [Workbench Development Guide](./workbench-development-guide.md)

### 3. Production Hardening

- **Add circuit breakers**: Stop automation if failure rate is high
- **Implement canary deployments**: Test remediations on subset of pods
- **Set up audit logging**: Track all automation decisions
- **Create runbooks**: Document remediation procedures

**See**: [ADR-043: Deployment Stability and Health Checks](../adrs/043-deployment-stability-health-checks.md)

### 4. Integrate with Existing Tools

- **AlertManager**: Forward alerts to existing systems
- **ServiceNow**: Create incidents for failed remediations
- **PagerDuty**: Escalate when automation can't resolve
- **Slack/Teams**: Real-time notifications

## Troubleshooting

### Issue: "Coordination engine not receiving alerts"

**Check webhook connectivity**:

```bash
oc exec -n self-healing-platform deployment/anomaly-webhook -- \
  curl -v http://coordination-engine.self-healing-platform.svc:8080/health
```

**Check webhook logs**:

```bash
oc logs -n self-healing-platform deployment/anomaly-webhook --tail=100
```

### Issue: "Remediation not executing"

**Check remediation rule validation**:

```bash
oc exec -n self-healing-platform deployment/coordination-engine -- \
  curl -s http://localhost:8080/api/v1/rules | jq
```

**Common causes**:
- Validation check failed (insufficient resources)
- Conflicting action in progress
- Rate limit exceeded
- Approval pending (for risky actions)

### Issue: "False positives - too many unnecessary remediations"

**Adjust model sensitivity**:

```python
# Increase contamination parameter (expect more anomalies)
model = IsolationForest(
    contamination=0.15,  # Increased from 0.1
    ...
)
```

**Tighten remediation triggers**:

```yaml
# Require more occurrences before triggering
min_occurrences: 3  # Increased from 2
time_window: 600s    # Increased from 300s
```

## Clean Up

When you're done:

```bash
# Delete stress test pod
oc delete pod memory-stress-test -n self-healing-platform

# Delete webhook
oc delete deployment anomaly-webhook -n self-healing-platform
oc delete svc anomaly-webhook -n self-healing-platform

# Delete config maps
oc delete configmap anomaly-webhook-config remediation-rules rate-limiter-config approval-workflow -n self-healing-platform
```

---

## Additional Resources

- **[ADR-002: Hybrid Self-Healing Approach](../adrs/002-hybrid-self-healing-approach.md)** - Architecture overview
- **[ADR-038: Go Coordination Engine Migration](../adrs/038-go-coordination-engine-migration.md)** - Coordination engine details
- **[Coordination Engine Repository](https://github.com/KubeHeal/openshift-coordination-engine)** - Source code and API docs
- **[Deploy Your First ML Model](./deploy-first-ml-model.md)** - Prerequisite tutorial

**Questions or stuck?** Open an issue: https://github.com/KubeHeal/openshift-aiops-platform/issues

---

**Tutorial last updated**: 2026-05-18  
**Tested on**: OpenShift 4.20, RHOAI 2.22.2, Coordination Engine v1.2.0
