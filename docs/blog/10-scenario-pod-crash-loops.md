# Scenario: Detecting and Healing Pod Crash Loops

*Part 10 of the OpenShift AI Ops Learning Series*

---

## Introduction

Pod crash loops are one of the most common issues in Kubernetes. A pod repeatedly crashes and restarts, consuming resources and potentially impacting service availability. Manual intervention is time-consuming and error-prone.

This hands-on scenario demonstrates how the self-healing platform automatically detects, analyzes, and remediates pod crash loops using ML-powered anomaly detection and automated remediation workflows.

---

## What You'll Learn

- How to detect pod crash loops automatically
- Analyzing container logs to identify root causes
- Executing targeted remediation actions
- Tracking healing success rates
- Implementing recovery workflows

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 1: Setting Up Your AI-Powered Cluster](01-setting-up-ai-powered-cluster.md)
- [ ] Completed [Blog 3: Your First Anomaly Detector](03-isolation-forest-anomaly-detection.md)
- [ ] Coordination Engine running and accessible
- [ ] Anomaly detection models deployed to KServe

---

## Step 1: Deploy a Deliberately Broken Application

To demonstrate crash loop detection, let's deploy an application that will crash.

### Create a Crashy Deployment

```bash
oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crashy-app
  namespace: self-healing-platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app: crashy
  template:
    metadata:
      labels:
        app: crashy
    spec:
      containers:
      - name: web
        image: registry.access.redhat.com/ubi9/python-311:latest
        command: ["/bin/bash", "-c"]
        args:
        - |
          # This will crash after 30 seconds
          sleep 30
          exit 1
        resources:
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF
```

### Watch the Crash Loop

```bash
# Watch pod status
watch -n 2 'oc get pods -n self-healing-platform | grep crashy'

# You'll see:
# crashy-app-xxx   0/1   CrashLoopBackOff   3   2m
# crashy-app-yyy   0/1   CrashLoopBackOff   2   1m
```

---

## Step 2: Open the Crash Loop Healing Notebook

1. Navigate to `notebooks/05-end-to-end-scenarios/`
2. Open `pod-crash-loop-healing.ipynb`

### Understanding Crash Loop Detection

The notebook implements automatic detection:

```python
def detect_crash_loops(namespace, restart_threshold=3):
    """
    Detect pods in crash loop by checking restart count.
    
    Args:
        namespace: Kubernetes namespace
        restart_threshold: Restart count threshold (default: 3)
    
    Returns:
        List of pods in crash loop
    """
    from kubernetes import client, config
    
    config.load_incluster_config()
    v1 = client.CoreV1Api()
    
    crash_loop_pods = []
    
    # Get all pods in namespace
    pods = v1.list_namespaced_pod(namespace)
    
    for pod in pods.items:
        # Check restart count
        if pod.status.container_statuses:
            restart_count = pod.status.container_statuses[0].restart_count
            
            # Check if in CrashLoopBackOff
            if (restart_count >= restart_threshold or 
                pod.status.phase == 'Failed' or
                any(condition.reason == 'CrashLoopBackOff' 
                    for condition in pod.status.conditions)):
                
                crash_loop_pods.append({
                    'name': pod.metadata.name,
                    'namespace': pod.metadata.namespace,
                    'restart_count': restart_count,
                    'status': pod.status.phase
                })
    
    return crash_loop_pods
```

### Run Detection

```python
crash_loop_pods = detect_crash_loops('self-healing-platform', restart_threshold=3)

print(f"🔍 Found {len(crash_loop_pods)} pods in crash loop:")
for pod in crash_loop_pods:
    print(f"  - {pod['name']}: {pod['restart_count']} restarts")
```

---

## Step 3: Analyze Pod Logs

Once a crash loop is detected, analyze logs to identify the root cause.

### Extract Logs

```python
def analyze_pod_logs(pod_name, namespace, lines=50):
    """
    Analyze pod logs to identify root cause.
    
    Args:
        pod_name: Pod name
        namespace: Kubernetes namespace
        lines: Number of log lines to analyze
    
    Returns:
        Log analysis result with detected error patterns
    """
    from kubernetes import client, config
    
    config.load_incluster_config()
    v1 = client.CoreV1Api()
    
    # Get pod logs
    logs = v1.read_namespaced_pod_log(
        pod_name, 
        namespace,
        tail_lines=lines
    )
    
    # Error patterns to detect
    error_patterns = {
        'OOMKilled': r'(OOMKilled|Out of memory|MemoryError)',
        'ImagePullBackOff': r'(ImagePullBackOff|Failed to pull image)',
        'ConfigError': r'(ConfigError|configuration error|ConfigMap.*not found)',
        'HealthCheckFailed': r'(HealthCheckFailed|liveness probe failed)',
        'DatabaseError': r'(Connection refused|database.*error|DB.*unavailable)',
        'PermissionError': r'(Permission denied|Access denied|Forbidden)',
    }
    
    detected_errors = []
    for error_type, pattern in error_patterns.items():
        if re.search(pattern, logs, re.IGNORECASE):
            detected_errors.append(error_type)
    
    return {
        'pod_name': pod_name,
        'detected_errors': detected_errors if detected_errors else ['Unknown'],
        'log_sample': logs.split('\n')[-5:],  # Last 5 lines
        'analysis': f"Detected {len(detected_errors)} error types"
    }
```

### Analyze Each Pod

```python
for pod in crash_loop_pods:
    analysis = analyze_pod_logs(pod['name'], pod['namespace'])
    print(f"\n📋 Analysis for {pod['name']}:")
    print(f"   Errors: {', '.join(analysis['detected_errors'])}")
    print(f"   Log sample: {analysis['log_sample'][-1]}")
```

---

## Step 4: Use ML Anomaly Detection

The platform's anomaly detector can identify crash loops before they become critical.

> **💡 Architecture Note**: Your Python notebooks call the **Go-based Coordination Engine** via REST API. The Coordination Engine then proxies to KServe models. You don't need to write Go code!

### Call Anomaly Detection API

```python
from coordination_engine_client import get_client

client = get_client()  # Python client → Go Coordination Engine → KServe models

# Collect metrics for the crashing pod
pod_metrics = {
    'pod_cpu_usage': 0.0,  # Pod is crashing, no CPU usage
    'pod_memory_usage': 0.0,
    'container_restart_count': pod['restart_count'],  # High restart count
    'node_cpu_utilization': 0.3,  # Normal node CPU
    'node_memory_utilization': 0.4  # Normal node memory
}

# Detect anomaly
response = client.detect_anomaly(metrics=pod_metrics)

if response.is_anomaly:
    print(f"⚠️ Anomaly detected: {response.severity}")
    print(f"   Confidence: {response.confidence}")
    print(f"   Recommended action: {response.recommended_action}")
```

### Expected Output

```
⚠️ Anomaly detected: high
   Confidence: 0.92
   Recommended action: restart_pod
   Explanation: High restart count (8) indicates crash loop
```

---

## Step 5: Execute Remediation

Once the root cause is identified, execute targeted remediation.

### Remediation Strategies

The notebook demonstrates different remediation actions:

#### Strategy 1: Restart Pod

```python
def restart_pod(pod_name, namespace):
    """Delete pod to trigger restart"""
    from kubernetes import client, config
    
    config.load_incluster_config()
    v1 = client.CoreV1Api()
    
    v1.delete_namespaced_pod(pod_name, namespace)
    print(f"✅ Restarted pod: {pod_name}")
```

#### Strategy 2: Scale Deployment

```python
def scale_deployment(deployment_name, namespace, replicas):
    """Scale deployment to replace failing pods"""
    from kubernetes import client, config
    
    config.load_incluster_config()
    apps_v1 = client.AppsV1Api()
    
    # Get current deployment
    deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
    
    # Scale down then up to force pod recreation
    deployment.spec.replicas = replicas
    apps_v1.patch_namespaced_deployment(deployment_name, namespace, deployment)
    
    print(f"✅ Scaled {deployment_name} to {replicas} replicas")
```

#### Strategy 3: Update Configuration

```python
def update_configmap(configmap_name, namespace, updates):
    """Update ConfigMap if configuration error detected"""
    from kubernetes import client, config
    
    config.load_incluster_config()
    v1 = client.CoreV1Api()
    
    # Get ConfigMap
    cm = v1.read_namespaced_config_map(configmap_name, namespace)
    
    # Update data
    cm.data.update(updates)
    
    # Apply update
    v1.patch_namespaced_config_map(configmap_name, namespace, cm)
    
    print(f"✅ Updated ConfigMap: {configmap_name}")
```

### Trigger Remediation via Coordination Engine

```python
# Use Coordination Engine for orchestrated remediation
remediation_request = {
    'incident_id': f"crash-loop-{pod['name']}",
    'action': 'restart_pod',
    'target': pod['name'],
    'namespace': pod['namespace'],
    'confidence': response.confidence,
    'parameters': {
        'reason': 'CrashLoopBackOff detected',
        'restart_count': pod['restart_count']
    }
}

result = client.trigger_remediation(remediation_request)
print(f"✅ Remediation triggered: {result.action_id}")
```

---

## Step 6: Verify Healing

After remediation, verify the pod recovers.

### Monitor Pod Status

```python
import time

def verify_healing(pod_name, namespace, timeout=300):
    """Monitor pod until it's healthy or timeout"""
    from kubernetes import client, config
    
    config.load_incluster_config()
    v1 = client.CoreV1Api()
    
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        pod = v1.read_namespaced_pod(pod_name, namespace)
        
        if pod.status.phase == 'Running':
            # Check if container is ready
            if pod.status.container_statuses:
                if pod.status.container_statuses[0].ready:
                    print(f"✅ Pod {pod_name} is healthy!")
                    return True
        
        time.sleep(5)
    
    print(f"⚠️ Pod {pod_name} did not recover within {timeout}s")
    return False
```

### Track Success Rate

```python
healing_results = []

for pod in crash_loop_pods:
    # Execute remediation
    restart_pod(pod['name'], pod['namespace'])
    
    # Wait and verify
    recovered = verify_healing(pod['name'], pod['namespace'])
    
    healing_results.append({
        'pod': pod['name'],
        'recovered': recovered,
        'timestamp': datetime.now().isoformat()
    })

# Calculate success rate
success_rate = sum(1 for r in healing_results if r['recovered']) / len(healing_results)
print(f"📊 Healing success rate: {success_rate * 100:.1f}%")
```

---

## What Just Happened?

You've implemented a complete crash loop healing workflow:

### 1. Detection

- **Restart count monitoring**: Tracks pod restart frequency
- **Status checking**: Identifies CrashLoopBackOff state
- **Threshold-based**: Configurable sensitivity (default: 3 restarts)

### 2. Analysis

- **Log parsing**: Extracts error patterns from container logs
- **Root cause identification**: Categorizes errors (OOM, config, health check)
- **ML validation**: Uses anomaly detector to confirm severity

### 3. Remediation

- **Targeted actions**: Restart, scale, or update based on root cause
- **Orchestrated execution**: Via Coordination Engine for conflict prevention
- **Audit logging**: All actions tracked for compliance

### 4. Verification

- **Health monitoring**: Tracks pod recovery status
- **Success tracking**: Measures healing effectiveness
- **Continuous improvement**: Data feeds back into model training

---

## Advanced: Integration with Lightspeed

You can also trigger healing via OpenShift Lightspeed:

**You type:**
```
The crashy-app pods are in crash loop. Fix them automatically.
```

**Lightspeed responds:**
```
I detected 2 pods in crash loop:
- crashy-app-xxx: 5 restarts
- crashy-app-yyy: 3 restarts

Analyzing logs... Found: ConfigError

Executing remediation: Restarting pods with updated configuration.

✅ Remediation complete. Monitoring recovery...
✅ Both pods recovered successfully.
```

---

## Next Steps

Explore more scenarios:

1. **Memory Exhaustion**: [Blog 11: Handling Memory Exhaustion](11-scenario-memory-exhaustion.md) for OOM scenarios
2. **Rule-Based Remediation**: [Blog 7: Rule-Based Remediation](07-rule-based-remediation.md) for deterministic workflows
3. **AI Decision Making**: [Blog 8: AI-Driven Decision Making](08-ai-driven-decision-making.md) for complex incidents

---

## Related Resources

- **Notebook**: `notebooks/05-end-to-end-scenarios/pod-crash-loop-healing.ipynb`
- **ADRs**:
  - [ADR-002: Hybrid Self-Healing Approach](docs/adrs/002-hybrid-self-healing-approach.md)
  - [ADR-012: Notebook Architecture](docs/adrs/012-notebook-architecture-for-end-to-end-workflows.md)
- **Kubernetes Docs**: [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/tosin2013/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/10-scenario-pod-crash-loops.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 10 of 15 in the OpenShift AI Ops Learning Series*
