# Building Rule-Based Remediation Workflows

*Part 7 of the OpenShift AI Ops Learning Series*

---

## Introduction

Rule-based remediation provides deterministic, predictable responses to known failure patterns. When CPU exceeds 90%, scale up. When a pod crashes 5 times, restart it. These rules are fast, reliable, and auditable—perfect for common scenarios.

This guide shows you how to define remediation rules, map anomalies to actions, and execute them through the Coordination Engine with proper validation and tracking.

---

## What You'll Learn

- Defining remediation rules (if-then logic)
- Safe automation patterns (circuit breakers, rate limiting)
- Integrating with Kubernetes API
- Audit logging and compliance
- Validating remediation success

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 3: Isolation Forest](03-isolation-forest-anomaly-detection.md)
- [ ] Completed [Blog 6: Ensemble Methods](06-ensemble-anomaly-methods.md)
- [ ] Coordination Engine running and accessible
- [ ] Kubernetes API access from workbench

---

## Understanding Rule-Based Remediation

### When to Use Rules

Rules are ideal for:
- ✅ **Known patterns**: CPU spikes, memory exhaustion, crash loops
- ✅ **Deterministic actions**: Scale up, restart pod, clear cache
- ✅ **Fast response**: No ML inference delay
- ✅ **Audit requirements**: Clear, traceable decisions

### Rule Structure

```
IF (condition) THEN (action)
  - Condition: Anomaly type + severity + context
  - Action: Kubernetes operation (scale, restart, update)
  - Validation: Verify action succeeded
  - Tracking: Log outcome for learning
```

---

## Step 1: Define Remediation Rules

### Open the Rule-Based Remediation Notebook

1. Navigate to `notebooks/03-self-healing-logic/`
2. Open `rule-based-remediation.ipynb`

### Define Rule Set

```python
REMEDIATION_RULES = [
    {
        'name': 'cpu_high_scale_up',
        'condition': {
            'metric': 'cpu_usage',
            'operator': '>',
            'threshold': 0.90,
            'duration': '5m'  # Sustained for 5 minutes
        },
        'action': {
            'type': 'scale_deployment',
            'direction': 'up',
            'factor': 1.5  # Scale by 50%
        },
        'priority': 1,  # High priority
        'max_actions_per_hour': 3  # Rate limiting
    },
    {
        'name': 'memory_high_scale_up',
        'condition': {
            'metric': 'memory_usage',
            'operator': '>',
            'threshold': 0.85,
            'duration': '5m'
        },
        'action': {
            'type': 'scale_deployment',
            'direction': 'up',
            'factor': 1.5
        },
        'priority': 1,
        'max_actions_per_hour': 3
    },
    {
        'name': 'crash_loop_restart',
        'condition': {
            'metric': 'restart_count',
            'operator': '>=',
            'threshold': 5,
            'duration': '10m'
        },
        'action': {
            'type': 'restart_pod'
        },
        'priority': 2,  # Critical
        'max_actions_per_hour': 10
    },
    {
        'name': 'image_pull_error_update',
        'condition': {
            'event_type': 'ImagePullBackOff',
            'operator': '==',
            'value': True
        },
        'action': {
            'type': 'update_image',
            'fallback_image': 'registry.access.redhat.com/ubi9/python-311:latest'
        },
        'priority': 2
    }
]
```

---

## Step 2: Evaluate Rules Against Anomalies

### Match Anomalies to Rules

```python
def evaluate_rules(anomaly, rules):
    """
    Evaluate which rules match an anomaly.
    
    Args:
        anomaly: Detected anomaly with metrics
        rules: List of remediation rules
    
    Returns:
        List of matching rules sorted by priority
    """
    matching_rules = []
    
    for rule in rules:
        condition = rule['condition']
        
        # Check if condition matches
        if condition['metric'] in anomaly['metrics']:
            value = anomaly['metrics'][condition['metric']]
            threshold = condition['threshold']
            operator = condition['operator']
            
            # Evaluate condition
            if operator == '>':
                matches = value > threshold
            elif operator == '>=':
                matches = value >= threshold
            elif operator == '<':
                matches = value < threshold
            elif operator == '==':
                matches = value == threshold
            else:
                matches = False
            
            if matches:
                matching_rules.append(rule)
    
    # Sort by priority (lower number = higher priority)
    matching_rules.sort(key=lambda r: r['priority'])
    
    return matching_rules
```

### Check Rate Limits

```python
def check_rate_limit(rule, action_history):
    """
    Check if rule has exceeded rate limit.
    
    Args:
        rule: Remediation rule
        action_history: List of past actions
    
    Returns:
        True if action allowed, False if rate limited
    """
    if 'max_actions_per_hour' not in rule:
        return True  # No rate limit
    
    # Count actions in last hour
    one_hour_ago = datetime.now() - timedelta(hours=1)
    recent_actions = [
        a for a in action_history
        if a['rule'] == rule['name'] and a['timestamp'] > one_hour_ago
    ]
    
    return len(recent_actions) < rule['max_actions_per_hour']
```

---

## Step 3: Execute Remediation Actions

### Scale Deployment

```python
from kubernetes import client, config

def scale_deployment(deployment_name, namespace, factor, direction='up'):
    """
    Scale deployment up or down.
    
    Args:
        deployment_name: Deployment name
        namespace: Kubernetes namespace
        factor: Scaling factor (e.g., 1.5 = 50% increase)
        direction: 'up' or 'down'
    """
    config.load_incluster_config()
    apps_v1 = client.AppsV1Api()
    
    # Get current deployment
    deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
    current_replicas = deployment.spec.replicas
    
    # Calculate new replica count
    if direction == 'up':
        new_replicas = int(np.ceil(current_replicas * factor))
    else:
        new_replicas = int(np.floor(current_replicas / factor))
    
    # Update deployment
    deployment.spec.replicas = new_replicas
    apps_v1.patch_namespaced_deployment(deployment_name, namespace, deployment)
    
    print(f"✅ Scaled {deployment_name} from {current_replicas} to {new_replicas} replicas")
    return new_replicas
```

### Restart Pod

```python
def restart_pod(pod_name, namespace):
    """Delete pod to trigger restart"""
    config.load_incluster_config()
    v1 = client.CoreV1Api()
    
    v1.delete_namespaced_pod(pod_name, namespace)
    print(f"✅ Restarted pod: {pod_name}")
```

### Update Image

```python
def update_image(deployment_name, namespace, new_image):
    """Update container image in deployment"""
    config.load_incluster_config()
    apps_v1 = client.AppsV1Api()
    
    deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
    
    # Update image
    for container in deployment.spec.template.spec.containers:
        container.image = new_image
    
    apps_v1.patch_namespaced_deployment(deployment_name, namespace, deployment)
    print(f"✅ Updated image for {deployment_name}")
```

---

## Step 4: Execute via Coordination Engine

> **💡 Architecture Note**: The Coordination Engine is a **Go service** that orchestrates remediation. Your Python notebooks call it via REST API—you don't need to write Go code!

### Trigger Remediation

```python
from coordination_engine_client import get_client

client = get_client()  # Python client calling Go service at http://coordination-engine:8080

def execute_remediation(anomaly, rule):
    """
    Execute remediation action via Coordination Engine.
    
    Args:
        anomaly: Detected anomaly
        rule: Matching remediation rule
    """
    # Create incident
    incident = client.create_incident({
        'title': f"Anomaly: {anomaly['type']}",
        'description': f"Detected {anomaly['type']} in {anomaly['target']}",
        'severity': anomaly['severity'],
        'source': 'rule-based',
        'labels': {
            'rule': rule['name'],
            'metric': rule['condition']['metric']
        }
    })
    
    # Trigger remediation
    remediation = client.trigger_remediation({
        'incident_id': incident.incident_id,
        'action': rule['action']['type'],
        'target': anomaly['target'],
        'namespace': anomaly['namespace'],
        'parameters': rule['action'],
        'priority': rule['priority']
    })
    
    return remediation
```

---

## Step 5: Validate Remediation Success

### Monitor Action Results

```python
def validate_remediation(anomaly, rule, action_id, timeout=300):
    """
    Validate that remediation was successful.
    
    Args:
        anomaly: Original anomaly
        rule: Remediation rule
        action_id: Action ID from Coordination Engine
        timeout: Maximum time to wait (seconds)
    
    Returns:
        True if remediation successful, False otherwise
    """
    import time
    
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        # Check if metric improved
        current_metrics = get_current_metrics(anomaly['target'], anomaly['namespace'])
        
        metric_name = rule['condition']['metric']
        current_value = current_metrics[metric_name]
        threshold = rule['condition']['threshold']
        
        # Check if condition resolved
        if rule['condition']['operator'] == '>':
            resolved = current_value < threshold * 0.9  # 10% below threshold
        elif rule['condition']['operator'] == '>=':
            resolved = current_value < threshold
        else:
            resolved = False
        
        if resolved:
            print(f"✅ Remediation successful: {metric_name} reduced to {current_value:.2f}")
            return True
        
        time.sleep(10)  # Check every 10 seconds
    
    print(f"⚠️ Remediation did not resolve within {timeout}s")
    return False
```

---

## Step 6: Track Remediation Outcomes

### Log Actions

```python
def track_remediation(anomaly, rule, action_id, success):
    """
    Track remediation outcome for learning.
    
    Args:
        anomaly: Original anomaly
        rule: Remediation rule
        action_id: Action ID
        success: Whether remediation succeeded
    """
    outcome = {
        'timestamp': datetime.now().isoformat(),
        'anomaly_id': anomaly.get('id'),
        'rule': rule['name'],
        'action_id': action_id,
        'action_type': rule['action']['type'],
        'target': anomaly['target'],
        'success': success,
        'metrics_before': anomaly['metrics'],
        'metrics_after': get_current_metrics(anomaly['target'], anomaly['namespace'])
    }
    
    # Save to persistent storage
    outcomes_file = '/opt/app-root/src/data/processed/remediation_outcomes.jsonl'
    with open(outcomes_file, 'a') as f:
        f.write(json.dumps(outcome) + '\n')
    
    print(f"📊 Remediation tracked: {rule['name']} - {'Success' if success else 'Failed'}")
```

---

## What Just Happened?

You've implemented rule-based remediation:

### 1. Rule Definition

- **Conditions**: Metric thresholds, operators, durations
- **Actions**: Kubernetes operations (scale, restart, update)
- **Priorities**: Order of execution
- **Rate limits**: Prevent action storms

### 2. Rule Evaluation

- **Matching**: Anomalies matched to rules
- **Priority sorting**: Higher priority rules first
- **Rate limiting**: Prevents excessive actions

### 3. Action Execution

- **Kubernetes API**: Direct cluster operations
- **Coordination Engine**: Centralized orchestration
- **Audit logging**: All actions tracked

### 4. Validation

- **Success monitoring**: Verify metrics improved
- **Timeout handling**: Detect failed remediations
- **Outcome tracking**: Learn from successes/failures

---

## Best Practices

### Circuit Breakers

Prevent cascading failures:

```python
CIRCUIT_BREAKER = {
    'max_failures': 3,
    'reset_timeout': 300,  # 5 minutes
    'state': 'closed'  # closed, open, half-open
}
```

### Rate Limiting

Prevent action storms:

```python
# Per-rule rate limits
'max_actions_per_hour': 3

# Global rate limits
'max_total_actions_per_hour': 20
```

### Dry Run Mode

Test rules without executing:

```python
DRY_RUN = True  # Set to False for production

if not DRY_RUN:
    execute_remediation(anomaly, rule)
else:
    print(f"[DRY RUN] Would execute: {rule['action']['type']}")
```

---

## Next Steps

Explore AI-driven remediation:

1. **AI Decision Making**: [Blog 8: AI-Driven Decision Making](08-ai-driven-decision-making.md) for complex scenarios
2. **Hybrid Approach**: Combine rules + AI (see hybrid-healing-workflows notebook)
3. **Model Deployment**: [Blog 9: Deploying Models with KServe](09-deploying-models-kserve.md)

---

## Related Resources

- **Notebook**: `notebooks/03-self-healing-logic/rule-based-remediation.ipynb`
- **ADRs**:
  - [ADR-002: Hybrid Self-Healing Approach](docs/adrs/002-hybrid-self-healing-approach.md)
- **Kubernetes Docs**: [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/tosin2013/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/07-rule-based-remediation.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 7 of 15 in the OpenShift AI Ops Learning Series*
