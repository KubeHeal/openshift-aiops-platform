# Scenario: Handling Memory Exhaustion and OOM Kills

*Part 11 of the OpenShift AI Ops Learning Series*

---

## Introduction

Memory exhaustion is a critical issue in Kubernetes. When pods exceed their memory limits, they're killed by the OOM (Out Of Memory) killer, causing service disruptions. Detecting memory pressure early and proactively scaling or optimizing resources prevents these failures.

This hands-on scenario demonstrates how the platform detects memory exhaustion trends, predicts OOM conditions, and triggers automated remediation before services are impacted.

---

## What You'll Learn

- How to monitor memory usage trends
- Predicting when memory will be exhausted
- Triggering proactive scaling before OOM
- Optimizing resource requests and limits
- Tracking scaling effectiveness

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 1: Setting Up Your AI-Powered Cluster](01-setting-up-ai-powered-cluster.md)
- [ ] Completed [Blog 10: Pod Crash Loops](10-scenario-pod-crash-loops.md)
- [ ] Prometheus metrics available
- [ ] Predictive analytics model deployed

---

## Step 1: Deploy a Memory-Intensive Application

Let's deploy an application that gradually consumes memory to simulate a memory leak.

### Create Memory-Leaking Deployment

```bash
oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-leak-app
  namespace: self-healing-platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app: memory-leak
  template:
    metadata:
      labels:
        app: memory-leak
    spec:
      containers:
      - name: web
        image: registry.access.redhat.com/ubi9/python-311:latest
        command: ["/bin/bash", "-c"]
        args:
        - |
          # Gradually consume memory
          import time
          memory = []
          while True:
              memory.append('x' * 10 * 1024 * 1024)  # 10MB chunks
              time.sleep(5)
        resources:
          limits:
            memory: "256Mi"  # Will be exceeded
          requests:
            memory: "128Mi"
EOF
```

### Monitor Memory Usage

```bash
# Watch memory usage
watch -n 2 'oc adm top pods -n self-healing-platform | grep memory-leak'

# You'll see memory gradually increase:
# memory-leak-app-xxx   100Mi   256Mi
# memory-leak-app-xxx   150Mi   256Mi
# memory-leak-app-xxx   200Mi   256Mi
# memory-leak-app-xxx   OOMKilled
```

---

## Step 2: Open the Resource Exhaustion Notebook

1. Navigate to `notebooks/05-end-to-end-scenarios/`
2. Open `resource-exhaustion-detection.ipynb`

### Understanding Resource Monitoring

The notebook implements comprehensive resource tracking:

```python
def collect_resource_metrics(namespace, hours=24):
    """
    Collect resource metrics from Prometheus.

    Args:
        namespace: Kubernetes namespace
        hours: Historical data window

    Returns:
        Resource metrics dataframe with CPU, memory, disk usage
    """
    import requests
    import pandas as pd

    # Query Prometheus for memory usage
    query = f'''
        sum(container_memory_working_set_bytes{{namespace="{namespace}"}})
        by (pod)
        /
        sum(container_spec_memory_limit_bytes{{namespace="{namespace}"}})
        by (pod)
        * 100
    '''

    # Execute Prometheus query
    response = requests.get(
        'https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091/api/v1/query',
        params={'query': query},
        verify=False
    )

    # Parse and return metrics
    data = response.json()
    # ... process into DataFrame

    return metrics_df
```

---

## Step 3: Detect Memory Trends

### Analyze Memory Usage Patterns

```python
import pandas as pd
import numpy as np
from scipy import stats

def detect_memory_trend(metrics_df, threshold=85):
    """
    Detect if memory usage is trending toward exhaustion.

    Args:
        metrics_df: DataFrame with memory_usage column
        threshold: Memory threshold percentage

    Returns:
        Trend analysis with prediction
    """
    # Calculate trend using linear regression
    x = np.arange(len(metrics_df))
    y = metrics_df['memory_usage'].values

    slope, intercept, r_value, p_value, std_err = stats.linregress(x, y)

    # Predict when threshold will be reached
    if slope > 0:  # Increasing trend
        hours_to_threshold = (threshold - intercept) / slope
    else:
        hours_to_threshold = float('inf')

    return {
        'trend': 'increasing' if slope > 0 else 'stable',
        'slope': slope,
        'current_usage': y[-1],
        'hours_to_threshold': hours_to_threshold,
        'confidence': r_value ** 2  # R-squared
    }
```

### Run Trend Analysis

```python
# Collect metrics
metrics = collect_resource_metrics('self-healing-platform', hours=24)

# Analyze memory trend
memory_trend = detect_memory_trend(metrics, threshold=85)

print(f"📊 Memory Trend Analysis:")
print(f"   Current usage: {memory_trend['current_usage']:.1f}%")
print(f"   Trend: {memory_trend['trend']}")
print(f"   Hours until 85% threshold: {memory_trend['hours_to_threshold']:.1f}")
print(f"   Confidence: {memory_trend['confidence']:.2f}")
```

---

## Step 4: Predict Memory Exhaustion

Use the predictive analytics model to forecast future memory usage.

> **💡 Architecture Note**: Your Python notebooks call the **Go-based Coordination Engine** via REST API. The Coordination Engine orchestrates predictions and remediation. You don't need to write Go code!

### Call Predictive Model

```python
from coordination_engine_client import get_client

client = get_client()  # Python client → Go Coordination Engine → KServe models

# Get current memory baseline
current_memory = metrics['memory_usage'].iloc[-1]

# Predict memory usage 6 hours ahead
prediction = client.predict_resource_usage(
    scope='namespace',
    namespace='self-healing-platform',
    target_time='18:00',  # 6 hours from now
    metric='memory_usage'
)

print(f"🔮 Memory Prediction:")
print(f"   Current: {current_memory:.1f}%")
print(f"   Predicted (6h): {prediction.predicted_memory_percent:.1f}%")
print(f"   Confidence: {prediction.confidence:.2f}")

if prediction.predicted_memory_percent > 90:
    print("⚠️ WARNING: Memory exhaustion predicted!")
```

### Expected Output

```
🔮 Memory Prediction:
   Current: 78.5%
   Predicted (6h): 92.3%
   Confidence: 0.85
⚠️ WARNING: Memory exhaustion predicted!
```

---

## Step 5: Trigger Proactive Scaling

Before memory is exhausted, scale the deployment to distribute load.

### Scale Deployment

```python
from kubernetes import client, config

def scale_deployment_proactively(deployment_name, namespace, target_replicas):
    """
    Scale deployment to prevent memory exhaustion.

    Args:
        deployment_name: Deployment name
        namespace: Kubernetes namespace
        target_replicas: Target number of replicas
    """
    config.load_incluster_config()
    apps_v1 = client.AppsV1Api()

    # Get current deployment
    deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
    current_replicas = deployment.spec.replicas

    if target_replicas > current_replicas:
        # Scale up
        deployment.spec.replicas = target_replicas
        apps_v1.patch_namespaced_deployment(deployment_name, namespace, deployment)

        print(f"✅ Scaled {deployment_name} from {current_replicas} to {target_replicas} replicas")
        return True
    else:
        print(f"ℹ️ No scaling needed (current: {current_replicas}, target: {target_replicas})")
        return False
```

### Calculate Required Replicas

```python
def calculate_required_replicas(current_usage, target_usage=70):
    """
    Calculate how many replicas needed to bring usage below target.

    Args:
        current_usage: Current memory usage percentage
        target_usage: Target usage after scaling

    Returns:
        Required number of replicas
    """
    current_replicas = 2  # Get from deployment

    # Simple calculation: scale proportionally
    required_replicas = int(np.ceil(current_replicas * (current_usage / target_usage)))

    return max(required_replicas, current_replicas + 1)  # At least scale up by 1
```

### Execute Scaling

```python
# Calculate required replicas
current_usage = prediction.predicted_memory_percent
required_replicas = calculate_required_replicas(current_usage, target_usage=70)

print(f"📈 Scaling recommendation:")
print(f"   Current replicas: 2")
print(f"   Required replicas: {required_replicas}")
print(f"   Reason: Memory predicted to reach {current_usage:.1f}%")

# Scale via Coordination Engine
remediation_request = {
    'incident_id': f"memory-exhaustion-{datetime.now().isoformat()}",
    'action': 'scale_deployment',
    'target': 'memory-leak-app',
    'namespace': 'self-healing-platform',
    'parameters': {
        'replicas': required_replicas,
        'reason': 'Proactive scaling to prevent memory exhaustion',
        'predicted_usage': current_usage
    }
}

result = client.trigger_remediation(remediation_request)
print(f"✅ Remediation triggered: {result.action_id}")
```

---

## Step 6: Optimize Resource Limits

If scaling isn't sufficient, optimize resource requests and limits.

### Analyze Resource Allocation

```python
def analyze_resource_allocation(namespace):
    """
    Analyze if resource requests/limits are optimal.

    Args:
        namespace: Kubernetes namespace

    Returns:
        Optimization recommendations
    """
    from kubernetes import client, config

    config.load_incluster_config()
    v1 = client.CoreV1Api()
    apps_v1 = client.AppsV1Api()

    # Get deployments
    deployments = apps_v1.list_namespaced_deployment(namespace)

    recommendations = []

    for deployment in deployments.items:
        # Get pod template
        containers = deployment.spec.template.spec.containers

        for container in containers:
            limits = container.resources.limits
            requests = container.resources.requests

            # Check if limits are too tight
            if limits and 'memory' in limits:
                limit_mb = parse_memory(limits['memory'])

                # If pods are hitting limits frequently, recommend increase
                if limit_mb < 512:  # Less than 512Mi
                    recommendations.append({
                        'deployment': deployment.metadata.name,
                        'container': container.name,
                        'current_limit': limits['memory'],
                        'recommended_limit': '512Mi',
                        'reason': 'Frequent OOM kills detected'
                    })

    return recommendations
```

### Apply Optimizations

```python
def update_resource_limits(deployment_name, namespace, container_name, new_limit):
    """
    Update resource limits for a container.

    Args:
        deployment_name: Deployment name
        namespace: Kubernetes namespace
        container_name: Container name
        new_limit: New memory limit (e.g., '512Mi')
    """
    from kubernetes import client, config

    config.load_incluster_config()
    apps_v1 = client.AppsV1Api()

    # Get deployment
    deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)

    # Update container limits
    for container in deployment.spec.template.spec.containers:
        if container.name == container_name:
            if not container.resources:
                container.resources = client.V1ResourceRequirements()
            if not container.resources.limits:
                container.resources.limits = {}

            container.resources.limits['memory'] = new_limit
            break

    # Apply update
    apps_v1.patch_namespaced_deployment(deployment_name, namespace, deployment)

    print(f"✅ Updated {container_name} memory limit to {new_limit}")
```

---

## Step 7: Verify Remediation

Monitor memory usage after remediation to verify effectiveness.

### Track Memory After Scaling

```python
import time

def verify_memory_reduction(namespace, deployment_name, timeout=600):
    """
    Monitor memory usage after scaling to verify reduction.

    Args:
        namespace: Kubernetes namespace
        deployment_name: Deployment name
        timeout: Maximum time to wait (seconds)

    Returns:
        True if memory reduced, False otherwise
    """
    start_time = time.time()
    baseline_memory = collect_resource_metrics(namespace, hours=1)['memory_usage'].iloc[-1]

    while time.time() - start_time < timeout:
        current_metrics = collect_resource_metrics(namespace, hours=1)
        current_memory = current_metrics['memory_usage'].iloc[-1]

        # Check if memory reduced by at least 10%
        if current_memory < baseline_memory * 0.9:
            print(f"✅ Memory reduced from {baseline_memory:.1f}% to {current_memory:.1f}%")
            return True

        time.sleep(30)  # Check every 30 seconds

    print(f"⚠️ Memory did not reduce significantly (current: {current_memory:.1f}%)")
    return False
```

### Calculate Success Metrics

```python
# Track remediation success
remediation_results = []

for deployment in ['memory-leak-app']:
    # Execute remediation
    scale_deployment_proactively(deployment, 'self-healing-platform', 4)

    # Verify
    success = verify_memory_reduction('self-healing-platform', deployment)

    remediation_results.append({
        'deployment': deployment,
        'remediated': success,
        'timestamp': datetime.now().isoformat()
    })

# Calculate success rate
success_rate = sum(1 for r in remediation_results if r['remediated']) / len(remediation_results)
print(f"📊 Remediation success rate: {success_rate * 100:.1f}%")
```

---

## What Just Happened?

You've implemented proactive memory exhaustion prevention:

### 1. Trend Detection

- **Linear regression**: Identifies increasing memory trends
- **Threshold prediction**: Forecasts when limits will be hit
- **Confidence scoring**: R-squared indicates prediction reliability

### 2. Predictive Analytics

- **ML forecasting**: Uses predictive-analytics model for future usage
- **Time-based prediction**: Forecasts specific time windows
- **Confidence intervals**: Model provides uncertainty estimates

### 3. Proactive Scaling

- **Pre-emptive action**: Scales before exhaustion occurs
- **Replica calculation**: Determines optimal replica count
- **Load distribution**: Spreads memory usage across more pods

### 4. Resource Optimization

- **Limit analysis**: Identifies containers with tight limits
- **Recommendations**: Suggests optimal resource allocations
- **Automated updates**: Applies optimizations via API

---

## Advanced: Integration with HPA

For production, integrate with Horizontal Pod Autoscaler (HPA):

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: memory-leak-app-hpa
  namespace: self-healing-platform
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: memory-leak-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70  # Scale when memory > 70%
```

---

## Next Steps

Explore more scenarios:

1. **Crash Loops**: [Blog 10: Pod Crash Loop Healing](10-scenario-pod-crash-loops.md) for restart scenarios
2. **Predictive Scaling**: [Blog 14: Predictive Scaling](14-predictive-scaling-cost-optimization.md) for capacity planning
3. **Cost Optimization**: [Blog 14: Cost Optimization](14-predictive-scaling-cost-optimization.md) for FinOps integration

---

## Related Resources

- **Notebook**: `notebooks/05-end-to-end-scenarios/resource-exhaustion-detection.ipynb`
- **ADRs**:
  - [ADR-002: Hybrid Self-Healing Approach](docs/adrs/002-hybrid-self-healing-approach.md)
  - [ADR-010: OpenShift Data Foundation](docs/adrs/010-openshift-data-foundation-requirement.md)
- **Kubernetes Docs**: [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/tosin2013/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/11-scenario-memory-exhaustion.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 11 of 15 in the OpenShift AI Ops Learning Series*
