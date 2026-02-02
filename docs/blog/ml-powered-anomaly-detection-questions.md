# ML-Powered Anomaly Detection Questions for OpenShift Clusters

*Published: 2026-01-28*
*Author: OpenShift AI Ops Platform Team*

## Asking Your Cluster "Are You OK?" with AI

The OpenShift AI Ops Self-Healing Platform brings machine learning-powered anomaly detection directly into your operational workflow. Through OpenShift Lightspeed and the Coordination Engine, you can ask natural language questions about your cluster's health and get intelligent, data-driven answers.

---

## Cluster-Wide Anomaly Detection

### Basic Health Checks

```
"Are there any anomalies in the cluster?"
"Check for anomalies cluster-wide"
"Is my cluster healthy?"
```

These questions trigger cluster-wide analysis across **5 key metrics**:
- Node CPU utilization
- Node memory utilization
- Pod CPU usage
- Pod memory usage
- Container restart count

### Time-Based Analysis

```
"Check for anomalies in the last hour"
"Are there any anomalies in the past 6 hours?"
"Show me anomalies from the last 24 hours"
"Any anomalies this week?"
```

Supported time ranges: `1h`, `6h`, `24h`, `7d`

### Metric-Specific Questions

```
"Are there any CPU anomalies?"
"Check for memory anomalies"
"Are there unusual pod restarts?"
"Is CPU usage normal across the cluster?"
```

---

## Namespace-Scoped Analysis

### Production Namespace Monitoring

```
"Check for anomalies in the production namespace"
"Are there any issues in openshift-monitoring?"
"Analyze self-healing-platform namespace for anomalies"
```

### Critical Infrastructure

```
"Are there anomalies in openshift-etcd?"
"Check the openshift-kube-apiserver namespace"
"Any issues with openshift-ingress?"
```

---

## Application-Level Detection

### Deployment Analysis

```
"Check for anomalies in the sample-flask-app deployment"
"Is my coordination-engine deployment healthy?"
"Analyze anomalies for the anomaly-detector-predictor deployment"
```

### Pod-Specific Checks

```
"Check pod etcd-0 for anomalies"
"Are there issues with prometheus-k8s-0?"
"Analyze the mcp-server pod"
```

### Label-Based Filtering

```
"Check for anomalies in pods with label app=flask"
"Analyze pods matching component=etcd"
"Are there issues with app.kubernetes.io/name=coordination-engine?"
```

---

## Combined Queries

### Namespace + Metric

```
"Check CPU anomalies in the production namespace"
"Are there memory issues in openshift-monitoring?"
"Check for pod restarts in self-healing-platform"
```

### Deployment + Time Range

```
"Check my-app deployment for anomalies in the last 6 hours"
"Any issues with nginx deployment today?"
```

---

## Understanding the Results

When you ask about anomalies, the system returns:

| Field | Description |
|-------|-------------|
| `anomaly_score` | 0.0 to 1.0 (higher = more anomalous) |
| `severity` | low, medium, high, critical |
| `confidence` | Model's confidence in the detection |
| `explanation` | Human-readable description |
| `recommended_action` | Suggested remediation step |

### Example Response

```json
{
  "anomalies_detected": 1,
  "severity": "critical",
  "anomaly_score": 1.0,
  "confidence": 0.87,
  "explanation": "Container restarts detected (9)",
  "recommended_action": "restart_pod",
  "recommendation": "CRITICAL: Immediate investigation recommended."
}
```

---

## Proactive Workflows

### Using Prompts

OpenShift Lightspeed supports guided workflows:

| Prompt | Purpose |
|--------|---------|
| `/check-anomalies` | ML-powered anomaly detection workflow |
| `/diagnose-cluster-issues` | Systematic cluster health diagnosis |
| `/investigate-pods` | Pod failure investigation |
| `/predict-and-prevent` | Proactive remediation using ML predictions |
| `/correlate-incidents` | Find root causes across multiple incidents |

### Example Workflow

```
/check-anomalies
→ "Critical anomaly detected: 9 container restarts"
→ "Would you like me to list pods with restarts?"
→ "Yes"
→ Shows: aws-ebs-csi-driver-node (22 restarts), kube-apiserver (21 restarts)
→ "Would you like to open an incident to track this?"
```

---

## Direct API Access

For automation and scripting, use the Coordination Engine directly:

```bash
# Cluster-wide analysis
curl -X POST http://coordination-engine:8080/api/v1/anomalies/analyze \
  -H "Content-Type: application/json" \
  -d '{"scope": "cluster"}'

# Namespace-specific
curl -X POST http://coordination-engine:8080/api/v1/anomalies/analyze \
  -H "Content-Type: application/json" \
  -d '{"namespace": "production"}'

# Custom time range
curl -X POST http://coordination-engine:8080/api/v1/anomalies/analyze \
  -H "Content-Type: application/json" \
  -d '{"scope": "cluster", "time_range": "6h"}'
```

---

## The ML Model Behind the Scenes

The anomaly detection is powered by an **Isolation Forest** model trained on:

- **45 engineered features** (9 features × 5 base metrics)
- Features include: current value, 5-minute rolling mean/std/min/max, lag values, rate of change
- Trained on 7 days of historical data
- Deployed via KServe for real-time inference

### Feature Engineering

For each of the 5 base metrics, the model generates 9 features:

| Feature | Description |
|---------|-------------|
| `{metric}_value` | Current metric value |
| `{metric}_mean_5m` | 5-minute rolling mean |
| `{metric}_std_5m` | 5-minute rolling standard deviation |
| `{metric}_min_5m` | 5-minute rolling minimum |
| `{metric}_max_5m` | 5-minute rolling maximum |
| `{metric}_lag_1` | Previous value (1 sample lag) |
| `{metric}_lag_5` | 5 samples ago (5 sample lag) |
| `{metric}_diff` | Rate of change |
| `{metric}_pct_change` | Percentage change |

---

## Best Practices

### 1. Start Broad, Then Narrow Down

Begin with cluster-wide checks, then drill into specific namespaces or deployments:

```
"Are there any anomalies in the cluster?"
→ "Yes, critical anomaly in openshift-monitoring"
"Check for anomalies in openshift-monitoring"
→ "High memory usage in prometheus-k8s-0"
"Check pod prometheus-k8s-0 for anomalies"
```

### 2. Use Time Ranges Appropriately

| Time Range | Use Case |
|------------|----------|
| `1h` | Immediate issues, incident response |
| `6h` | Shift handoffs, recent changes |
| `24h` | Daily reviews, overnight issues |
| `7d` | Trend analysis, capacity planning |

### 3. Combine with Other Tools

After detecting anomalies, use Lightspeed to investigate further:

```
"Show me the logs for the failing pod"
"What events occurred in this namespace?"
"Describe the pod prometheus-k8s-0"
```

### 4. Set Up Continuous Monitoring

Integrate with alerting to catch anomalies proactively:

```yaml
# Example: Prometheus AlertRule
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: aiops-anomaly-alerts
spec:
  groups:
    - name: aiops.anomalies
      rules:
        - alert: HighAnomalyScore
          expr: aiops_anomaly_score > 0.8
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "High anomaly score detected"
```

---

## Real-World Examples

### Example 1: Investigating High CPU

**Question:** "Are there any CPU anomalies in the production namespace?"

**Response:**
```json
{
  "status": "success",
  "anomalies_detected": 1,
  "anomalies": [{
    "severity": "high",
    "anomaly_score": 0.85,
    "explanation": "CPU usage 3x normal baseline",
    "recommended_action": "scale_up"
  }],
  "recommendation": "WARNING: Monitor closely. Consider scaling resources."
}
```

**Follow-up:** "Which pods are using the most CPU?"

### Example 2: Container Restart Investigation

**Question:** "Check for pod restart anomalies cluster-wide"

**Response:**
```json
{
  "status": "success",
  "anomalies_detected": 1,
  "anomalies": [{
    "severity": "critical",
    "anomaly_score": 1.0,
    "metrics": {
      "container_restart_count": 22
    },
    "explanation": "Container restarts detected (22)",
    "recommended_action": "investigate_crashloop"
  }]
}
```

**Follow-up:** "List pods with restarts" → "Show logs for aws-ebs-csi-driver-node"

### Example 3: Memory Leak Detection

**Question:** "Check for memory anomalies in my-app deployment over the last 24 hours"

**Response:**
```json
{
  "status": "success",
  "anomalies_detected": 3,
  "anomalies": [{
    "severity": "high",
    "anomaly_score": 0.78,
    "explanation": "Memory usage trending upward, potential leak",
    "recommended_action": "investigate_memory_leak"
  }],
  "recommendation": "Memory growth pattern detected. Check for memory leaks in application code."
}
```

---

## Summary

With ML-powered anomaly detection integrated into OpenShift Lightspeed, you can:

- ✅ Ask natural language questions about cluster health
- ✅ Detect anomalies before they become incidents
- ✅ Get actionable recommendations
- ✅ Drill down from cluster → namespace → deployment → pod
- ✅ Combine AI insights with traditional debugging
- ✅ Automate anomaly detection via API

**The future of cluster operations is conversational.** Instead of writing PromQL queries and parsing JSON, just ask: *"Is my cluster healthy?"*

---

## Related Resources

- [ADR-002: Hybrid Deterministic-AI Self-Healing Approach](../adrs/002-hybrid-self-healing-approach.md)
- [ADR-050: Anomaly Detector Model Training and Data Strategy](../adrs/050-anomaly-detector-model-training-and-data-strategy.md)
- [Coordination Engine API Documentation](../reference/coordination-engine-api.md)
- [OpenShift Lightspeed MCP Integration](../adrs/036-go-based-standalone-mcp-server.md)

---

*Built with the OpenShift AI Ops Self-Healing Platform*
