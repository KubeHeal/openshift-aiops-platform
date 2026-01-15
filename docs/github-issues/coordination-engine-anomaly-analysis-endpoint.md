# Feature: Add Anomaly Analysis Endpoint with Feature Engineering

## Repository

`openshift-aiops-platform` - Coordination Engine (`src/coordination-engine/`)

## Summary

The coordination engine should expose an `/api/v1/anomalies/analyze` endpoint that:
1. Queries Prometheus for required metrics
2. Performs feature engineering (45 features)
3. Calls the KServe anomaly-detector model
4. Returns human-readable anomaly results

This centralizes ML integration logic in the coordination engine rather than distributing it across MCP server and other clients.

## Current Architecture (Problem)

```
MCP Server ──────────────────────► KServe Model
            (sends metadata,        (expects 45 numeric
             not features)           features)
                    ❌ MISMATCH
```

## Proposed Architecture (Solution)

```
MCP Server ──► Coordination Engine ──► Prometheus (query metrics)
                       │
                       ├──► Feature Engineering (45 features)
                       │
                       └──► KServe Model ──► Response
                                   │
                       ◄───────────┘
                       │
              Format response with explanations
                       │
               ◄───────┘
```

## API Specification

### Request

```http
POST /api/v1/anomalies/analyze
Content-Type: application/json

{
  "time_range": "1h",           // Options: 1h, 6h, 24h, 7d
  "namespace": "self-healing-platform",  // Optional: scope to namespace
  "deployment": "broken-app",   // Optional: scope to deployment
  "pod": "",                    // Optional: scope to specific pod
  "label_selector": "",         // Optional: label selector
  "threshold": 0.7,             // Anomaly score threshold (0.0-1.0)
  "model_name": "anomaly-detector"  // KServe model to use
}
```

### Response

```json
{
  "status": "success",
  "time_range": "1h",
  "scope": {
    "namespace": "self-healing-platform",
    "deployment": "broken-app",
    "target_description": "deployment 'broken-app' in namespace 'self-healing-platform'"
  },
  "model_used": "anomaly-detector",
  "anomalies_detected": 3,
  "anomalies": [
    {
      "timestamp": "2026-01-14T16:30:00Z",
      "severity": "critical",
      "anomaly_score": 0.92,
      "confidence": 0.87,
      "metrics": {
        "pod_memory_usage": 0.95,
        "pod_cpu_usage": 0.78,
        "container_restart_count": 5
      },
      "explanation": "Memory usage critically high (95%) with elevated CPU and multiple restarts",
      "recommended_action": "restart_pod"
    }
  ],
  "summary": {
    "max_score": 0.92,
    "average_score": 0.85,
    "metrics_analyzed": 5,
    "features_generated": 45
  },
  "recommendation": "CRITICAL: Immediate investigation recommended. Consider scaling resources or triggering remediation."
}
```

## Implementation Details

### Feature Engineering Function

```python
def build_feature_vector(self, namespace: str, pod: str = None, deployment: str = None) -> List[float]:
    """
    Build 45-feature vector from Prometheus metrics.
    
    Features per metric (9 each):
    - value: current value
    - mean_5m: 5-minute rolling mean
    - std_5m: 5-minute rolling stddev
    - min_5m: 5-minute rolling min
    - max_5m: 5-minute rolling max
    - lag_1: 1-minute lag
    - lag_5: 5-minute lag  
    - diff: value - lag_1
    - pct_change: (value - lag_1) / lag_1
    """
    BASE_METRICS = [
        'node_cpu_utilization',
        'node_memory_utilization',
        'pod_cpu_usage', 
        'pod_memory_usage',
        'container_restart_count'
    ]
    
    features = []
    for metric in BASE_METRICS:
        # Query current value
        current = self.query_prometheus(metric, namespace, pod)
        
        # Query rolling statistics
        mean_5m = self.query_prometheus(f'avg_over_time({metric}[5m])', namespace, pod)
        std_5m = self.query_prometheus(f'stddev_over_time({metric}[5m])', namespace, pod)
        min_5m = self.query_prometheus(f'min_over_time({metric}[5m])', namespace, pod)
        max_5m = self.query_prometheus(f'max_over_time({metric}[5m])', namespace, pod)
        
        # Query lag values
        lag_1 = self.query_prometheus(f'{metric} offset 1m', namespace, pod)
        lag_5 = self.query_prometheus(f'{metric} offset 5m', namespace, pod)
        
        # Calculate derived features
        diff = current - lag_1
        pct_change = (current - lag_1) / lag_1 if lag_1 != 0 else 0
        
        features.extend([current, mean_5m, std_5m, min_5m, max_5m, lag_1, lag_5, diff, pct_change])
    
    return features  # 45 features total
```

### Prometheus Queries

```python
PROMETHEUS_QUERIES = {
    'node_cpu_utilization': '''
        avg(1 - rate(node_cpu_seconds_total{mode="idle"}[5m]))
    ''',
    'node_memory_utilization': '''
        1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
    ''',
    'pod_cpu_usage': '''
        sum(rate(container_cpu_usage_seconds_total{namespace="{namespace}"}[5m])) by (pod)
    ''',
    'pod_memory_usage': '''
        sum(container_memory_working_set_bytes{namespace="{namespace}"}) by (pod) 
        / sum(kube_pod_container_resource_limits{resource="memory",namespace="{namespace}"}) by (pod)
    ''',
    'container_restart_count': '''
        sum(kube_pod_container_status_restarts_total{namespace="{namespace}"}) by (pod)
    '''
}
```

### KServe Model Call

```python
def call_anomaly_model(self, features: List[float], model_name: str = "anomaly-detector") -> dict:
    """Call KServe model with feature vector."""
    url = f"http://{model_name}-predictor:8080/v1/models/model:predict"
    
    response = requests.post(url, json={
        "instances": [features]  # Single 45-feature vector
    })
    
    result = response.json()
    # predictions: [-1] = anomaly, [1] = normal
    prediction = result.get("predictions", [1])[0]
    
    return {
        "is_anomaly": prediction == -1,
        "raw_prediction": prediction
    }
```

## Files to Modify

- `src/coordination-engine/app.py` or equivalent - Add new endpoint
- `src/coordination-engine/prometheus_client.py` - Add feature query methods
- `src/coordination-engine/kserve_client.py` - Update model calling (use correct URL)

## Testing

```bash
# Test the new endpoint
curl -X POST http://coordination-engine:8080/api/v1/anomalies/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "time_range": "1h",
    "namespace": "self-healing-platform",
    "deployment": "broken-app"
  }'

# Expected: JSON with anomaly analysis results
```

## MCP Server Update

Once the coordination engine has this endpoint, update the MCP server's `analyze-anomalies` tool to call:

```go
// Instead of calling KServe directly
response, err := c.coordinationEngine.AnalyzeAnomalies(ctx, req)
```

## Related Issues

- `mcp-server-anomaly-detection-feature-engineering.md` - MCP server side of this issue
- `mcp-server-kserve-url-bug.md` - KServe URL pattern bug
- `coordination-engine-prediction-type-mismatch.md` - Response parsing bug

## Priority

**High** - Required for end-to-end self-healing demo with Lightspeed

## Labels

`enhancement`, `coordination-engine`, `ml-integration`, `feature-engineering`, `api`
