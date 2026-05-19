# How-To: Test Your Custom Application with the MCP Server

## Overview

This guide explains how to integrate and test your own custom applications with the OpenShift AI Ops Platform's MCP server. Whether you're building a new self-healing workflow, custom monitoring tool, or ML pipeline, this guide will help you integrate with the platform.

## Prerequisites

- OpenShift 4.18+ cluster with MCP server deployed
- Basic understanding of Kubernetes/OpenShift
- Familiarity with Python or TypeScript (depending on your integration approach)
- Access to self-healing-platform namespace

## Integration Patterns

### Pattern 1: Direct API Integration (Recommended)

Your application can directly call the MCP server's internal services:

```python
import requests

# Health Service
health_response = requests.get(
    'http://cluster-health-mcp-server.self-healing-platform.svc.cluster.local:9090/health'
)

# Coordination Engine
anomaly_data = {
    'timestamp': '2025-12-09T18:00:00Z',
    'type': 'custom_anomaly',
    'severity': 'high',
    'details': {
        'application': 'my-custom-app',
        'metric': 'response_time',
        'threshold': 500,
        'current_value': 1200
    },
    'confidence_score': 0.85
}

response = requests.post(
    'http://coordination-engine.self-healing-platform.svc.cluster.local:8080/api/v1/anomalies',
    json=anomaly_data
)

print(f"Anomaly submitted: {response.json()['anomaly_id']}")
```

### Pattern 2: OpenShift Lightspeed Integration

Use natural language queries through OpenShift Lightspeed:

```bash
# Ask about your custom application
oc lightspeed query "What is the health status of my custom application?"

# Trigger custom remediation
oc lightspeed query "Trigger remediation for my-custom-app memory leak"
```

### Pattern 3: Jupyter Notebook Integration

Create custom notebooks that integrate with the platform:

```python
# In your custom notebook
import sys
sys.path.append('../utils')

from common_functions import setup_environment, query_prometheus
from mcp_client import CoordinationEngineClient

# Setup
env = setup_environment()
client = CoordinationEngineClient(base_url='http://coordination-engine:8080')

# Query your custom metrics
metrics = query_prometheus(
    query='my_custom_app_response_time_seconds',
    start_time='1h',
    step='30s'
)

# Analyze and submit anomalies
anomalies = detect_anomalies(metrics)  # Your custom logic
for anomaly in anomalies:
    client.submit_anomaly(anomaly)
```

## Testing Workflow

### Step 1: Deploy Your Custom Application

```bash
# Deploy your application to a test namespace
oc new-project my-custom-app-test

# Deploy your app (example with a simple deployment)
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-custom-app
  namespace: my-custom-app-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-custom-app
  template:
    metadata:
      labels:
        app: my-custom-app
    spec:
      serviceAccountName: my-custom-app-sa
      containers:
        - name: app
          image: quay.io/myorg/my-custom-app:latest
          ports:
            - containerPort: 8080
          env:
            - name: MCP_SERVER_URL
              value: "http://cluster-health-mcp-server.self-healing-platform.svc.cluster.local:9090"
            - name: COORDINATION_ENGINE_URL
              value: "http://coordination-engine.self-healing-platform.svc.cluster.local:8080"
EOF
```

### Step 2: Configure RBAC for MCP Server Access

```bash
# Create ServiceAccount
oc create serviceaccount my-custom-app-sa -n my-custom-app-test

# Grant access to MCP server services
oc create role mcp-client \
  --verb=get,list,watch,create \
  --resource=services,endpoints \
  -n self-healing-platform

oc create rolebinding my-custom-app-mcp-access \
  --role=mcp-client \
  --serviceaccount=my-custom-app-test:my-custom-app-sa \
  -n self-healing-platform
```

### Step 3: Test Basic Connectivity

```bash
# Test from your application pod
POD=$(oc get pods -n my-custom-app-test -l app=my-custom-app -o jsonpath='{.items[0].metadata.name}')

# Test MCP server health endpoint
oc exec -n my-custom-app-test $POD -- \
  curl -s http://cluster-health-mcp-server.self-healing-platform.svc.cluster.local:9090/health

# Expected output:
# {"status":"healthy","timestamp":"2025-12-09T18:00:00.000Z"}

# Test coordination engine
oc exec -n my-custom-app-test $POD -- \
  curl -s http://coordination-engine.self-healing-platform.svc.cluster.local:8080/health

# Expected output:
# {"status":"healthy","version":"1.0.0","timestamp":"2025-12-09T18:00:00.000Z"}
```

### Step 4: Submit Test Anomalies

**Python Example**:

```python
import requests
import json
from datetime import datetime

# Test anomaly submission
test_anomaly = {
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'type': 'test_anomaly',
    'severity': 'low',
    'source': 'my-custom-app',
    'details': {
        'application': 'my-custom-app',
        'namespace': 'my-custom-app-test',
        'metric': 'test_metric',
        'value': 100,
        'threshold': 80
    },
    'confidence_score': 0.90,
    'recommended_action': 'log_only'
}

response = requests.post(
    'http://coordination-engine.self-healing-platform.svc.cluster.local:8080/api/v1/anomalies',
    json=test_anomaly,
    timeout=10
)

if response.status_code == 200:
    print(f"✅ Test anomaly submitted: {response.json()['anomaly_id']}")
else:
    print(f"❌ Failed to submit anomaly: {response.status_code} - {response.text}")
```

**Bash Example**:

```bash
curl -X POST \
  http://coordination-engine.self-healing-platform.svc.cluster.local:8080/api/v1/anomalies \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "type": "test_anomaly",
    "severity": "low",
    "source": "my-custom-app",
    "details": {
      "application": "my-custom-app",
      "metric": "test_metric",
      "value": 100
    },
    "confidence_score": 0.90
  }'
```

### Step 5: Verify Anomaly Processing

```bash
# Check coordination engine logs
oc logs -n self-healing-platform deployment/coordination-engine --tail=50 | grep test_anomaly

# Expected output:
# {"level":"info","message":"Anomaly received","anomaly_id":"anom-12345","type":"test_anomaly"}
# {"level":"info","message":"Anomaly processed successfully","anomaly_id":"anom-12345"}

# Query anomaly status (if database is enabled)
curl -s http://coordination-engine.self-healing-platform.svc.cluster.local:8080/api/v1/anomalies/anom-12345
```

### Step 6: Test with OpenShift Lightspeed

```bash
# Query your custom application via Lightspeed
oc lightspeed query "What is the status of my-custom-app?"

# Expected: Lightspeed queries MCP server resources and responds with your app's status

# Trigger custom remediation
oc lightspeed query "Trigger remediation for my-custom-app-test namespace"

# Expected: MCP server processes remediation request
```

## Creating Custom Notebooks for Your Application

### Directory Structure

> **Note**: The `09-custom-applications/` directory structure shown below is recommended for organizing your custom notebooks. You can create this directory structure in your fork, or use the existing `notebooks/08-advanced-scenarios/` directory for custom integrations.

```
notebooks/
└── 09-custom-applications/        # Create this directory for your custom notebooks
    ├── my-app-monitoring.ipynb
    ├── my-app-anomaly-detection.ipynb
    └── my-app-self-healing.ipynb
```

### Notebook Template

```python
# ============================================================
# HEADER SECTION
# ============================================================
# Title: My Custom App Monitoring
# Purpose: Monitor custom application metrics and detect anomalies
# Prerequisites:
#   - my-custom-app deployed in my-custom-app-test namespace
#   - MCP server and coordination engine running
# Expected Outcomes:
#   - Real-time monitoring dashboard
#   - Automated anomaly detection
#   - Self-healing triggers
# ============================================================

# ============================================================
# SETUP SECTION
# ============================================================
import sys
sys.path.append('../utils')

from common_functions import setup_environment, query_prometheus
from mcp_client import CoordinationEngineClient

# Validate environment
env_info = setup_environment()
client = CoordinationEngineClient(base_url='http://coordination-engine:8080')

# ============================================================
# DATA COLLECTION
# ============================================================
# Query custom metrics
metrics = query_prometheus(
    query='my_custom_app_response_time_seconds{namespace="my-custom-app-test"}',
    start_time='1h',
    step='30s'
)

# Display metrics
import pandas as pd
df = pd.DataFrame(metrics)
print(f"Collected {len(df)} data points")
df.head()

# ============================================================
# ANOMALY DETECTION
# ============================================================
# Use your custom anomaly detection logic
from sklearn.ensemble import IsolationForest

model = IsolationForest(contamination=0.1, random_state=42)
anomalies = model.fit_predict(df[['response_time']])

# Submit anomalies to coordination engine
for idx, is_anomaly in enumerate(anomalies):
    if is_anomaly == -1:  # Anomaly detected
        client.submit_anomaly({
            'timestamp': df.iloc[idx]['timestamp'],
            'type': 'response_time_anomaly',
            'severity': 'medium',
            'details': {
                'application': 'my-custom-app',
                'metric': 'response_time',
                'value': df.iloc[idx]['response_time']
            },
            'confidence_score': 0.85
        })

# ============================================================
# VALIDATION
# ============================================================
print(f"✅ Detected {(anomalies == -1).sum()} anomalies")
print(f"✅ Submitted to coordination engine")
```

## Testing Checklist

- [ ] **Connectivity Tests**
  - [ ] MCP server health endpoint accessible
  - [ ] Coordination engine health endpoint accessible
  - [ ] Network policies allow traffic from your namespace

- [ ] **RBAC Configuration**
  - [ ] ServiceAccount created
  - [ ] RoleBinding configured for MCP server access
  - [ ] Tested with `oc auth can-i` commands

- [ ] **Anomaly Submission**
  - [ ] Test anomaly successfully submitted
  - [ ] Anomaly appears in coordination engine logs
  - [ ] Anomaly ID returned in response

- [ ] **OpenShift Lightspeed Integration**
  - [ ] Lightspeed can query your application status
  - [ ] Natural language queries return expected results
  - [ ] MCP tools work with your custom data

- [ ] **Notebook Integration**
  - [ ] Custom notebooks can import platform utilities
  - [ ] Notebooks can submit anomalies via MCP client
  - [ ] Data collection from Prometheus works
  - [ ] Models can be deployed via KServe (if applicable)

- [ ] **Performance Tests**
  - [ ] Response times < 500ms for API calls
  - [ ] No timeout errors under load
  - [ ] MCP server logs show successful processing

## Troubleshooting

### Issue: Cannot Connect to MCP Server

**Symptoms**:
```
curl: (7) Failed to connect to cluster-health-mcp-server port 9090: Connection refused
```

**Solutions**:
```bash
# 1. Verify MCP server is running
oc get pods -n self-healing-platform -l app=cluster-health-mcp-server

# 2. Check service endpoints
oc get endpoints -n self-healing-platform cluster-health-mcp-server

# 3. Test from a pod in self-healing-platform namespace (known working)
oc run test-curl --image=curlimages/curl:latest --rm -i --restart=Never \
  -n self-healing-platform -- \
  curl http://cluster-health-mcp-server:9090/health

# 4. Check network policies
oc get networkpolicies -n self-healing-platform
oc get networkpolicies -n my-custom-app-test
```

### Issue: Anomaly Submission Fails

**Symptoms**:
```
{"error": "Invalid anomaly format", "status": 400}
```

**Solutions**:
```python
# Ensure required fields are present
required_fields = ['timestamp', 'type', 'severity', 'source', 'details', 'confidence_score']

# Validate timestamp format (ISO 8601)
from datetime import datetime
timestamp = datetime.utcnow().isoformat() + 'Z'  # Must end with 'Z'

# Validate severity values
valid_severities = ['low', 'medium', 'high', 'critical']

# Validate confidence_score range
confidence_score = 0.85  # Must be between 0.0 and 1.0
```

### Issue: RBAC Permission Denied

**Symptoms**:
```
Error from server (Forbidden): services "cluster-health-mcp-server" is forbidden
```

**Solutions**:
```bash
# Check current permissions
oc auth can-i get services \
  --as=system:serviceaccount:my-custom-app-test:my-custom-app-sa \
  -n self-healing-platform

# Create necessary RoleBinding
oc create rolebinding my-custom-app-mcp-access \
  --role=mcp-client \
  --serviceaccount=my-custom-app-test:my-custom-app-sa \
  -n self-healing-platform

# Verify permissions granted
oc describe rolebinding my-custom-app-mcp-access -n self-healing-platform
```

## Example: Complete Custom Application Integration

**Reference Implementations**:
- Use the patterns shown in this guide as templates for your own integration
- Refer to existing notebooks in `notebooks/06-mcp-lightspeed-integration/` for MCP integration examples
- See `notebooks/08-advanced-scenarios/` for advanced use cases you can adapt

> **Note**: You can create your own `notebooks/09-custom-applications/` directory for custom notebooks, or add them to the appropriate existing section

## Advanced Topics

### Using MCP Server with Database (Stateful Mode)

If you deployed the MCP server with PostgreSQL:

```python
# Query incident history
response = requests.get(
    'http://coordination-engine:8080/api/v1/incidents',
    params={'severity': 'high', 'time_range': '24h'}
)

incidents = response.json()
print(f"Found {len(incidents)} high-severity incidents")
```

### Custom Prometheus Metrics

Export custom metrics for monitoring:

```python
from prometheus_client import Counter, Gauge, push_to_gateway

# Define custom metrics
custom_anomalies = Counter(
    'my_app_anomalies_total',
    'Total anomalies detected by my application'
)

custom_response_time = Gauge(
    'my_app_response_time_seconds',
    'Response time of my application'
)

# Update metrics
custom_anomalies.inc()
custom_response_time.set(0.45)

# Push to Prometheus Pushgateway
push_to_gateway(
    'pushgateway.self-healing-platform.svc.cluster.local:9091',
    job='my-custom-app',
    registry=registry
)
```

### Extending MCP Server Tools

To add custom tools to the MCP server (requires TypeScript development):

1. Add tool definition in `src/mcp-server/src/index.ts`
2. Implement tool handler
3. Rebuild and redeploy MCP server

See [ADR-014: MCP Server Architecture](../../docs/adrs/014-openshift-aiops-platform-mcp-server.md) for details.

## Related Documentation

- **[Lightspeed-Notebook Feedback Loop](lightspeed-notebook-feedback-loop.md)** - Using interactions to improve notebooks
- **[Deploy MCP Server Guide](deploy-mcp-server-lightspeed.md)** - Deployment and configuration
- **[ADR-014: MCP Server Architecture](../../docs/adrs/014-openshift-aiops-platform-mcp-server.md)** - Technical architecture
- **[Notebook Development Guide](../../notebooks/README.md)** - Creating custom notebooks
- **[Coordination Engine API](../../docs/adrs/002-hybrid-self-healing-approach.md)** - API reference

## Questions or Issues?

- **GitHub Issues**: https://github.com/openshift-aiops/openshift-aiops-platform/issues
- **Documentation**: https://github.com/openshift-aiops/openshift-aiops-platform/tree/main/docs
