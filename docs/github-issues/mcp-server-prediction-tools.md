# GitHub Issues for openshift-cluster-health-mcp

Repository: `https://github.com/tosin2013/openshift-cluster-health-mcp`

---

## Issue 1: Add `predict-resource-usage` MCP Tool for Time-Specific Forecasting

**Labels**: `enhancement`, `mcp-tool`, `prediction`, `ml-integration`

### Summary
Add a new MCP tool that enables time-specific resource usage predictions for any pod, deployment, namespace, or cluster-wide infrastructure using KServe ML models.

### Problem Statement
Currently, `analyze-anomalies` only provides historical anomaly detection over time ranges (1h, 6h, 24h, 7d). Users need to ask forward-looking questions like:
- "What will CPU usage be at 3 PM today?"
- "Predict memory usage tomorrow at 9 AM"
- "What will infrastructure pod resource usage be during peak hours?"

OpenShift Lightspeed cannot answer these questions without a time-specific prediction tool.

### Proposed Solution

**New Tool**: `predict-resource-usage`

**Input Schema**:
```json
{
  "target_time": "15:00",           // Optional: HH:MM format, defaults to current_hour + 1
  "target_date": "2026-01-12",      // Optional: YYYY-MM-DD, defaults to today
  "namespace": "openshift-*",       // Optional: namespace filter (supports wildcards)
  "deployment": "sample-app",       // Optional: specific deployment name
  "pod": "pod-name-123",            // Optional: specific pod name
  "metric": "cpu_usage",            // Required: cpu_usage, memory_usage, both
  "scope": "namespace"              // Optional: pod, deployment, namespace, cluster (default: namespace)
}
```

**Output Schema**:
```json
{
  "status": "success",
  "scope": "namespace",
  "target": "self-healing-platform",
  "current_metrics": {
    "cpu_percent": 68.2,
    "memory_percent": 74.5,
    "timestamp": "2026-01-12T14:30:00Z"
  },
  "predicted_metrics": {
    "cpu_percent": 74.5,
    "memory_percent": 81.2,
    "target_time": "2026-01-12T15:00:00Z",
    "confidence": 0.92
  },
  "trend": "upward",
  "recommendation": "Memory approaching 85% threshold. Consider monitoring or scaling.",
  "model_used": "predictive-analytics",
  "model_version": "v1"
}
```

### Implementation Details

**File Location**: `internal/tools/predict_resource_usage.go`

**Key Steps**:
1. Parse target_time and target_date (default to current time + 1 hour)
2. Extract hour (0-23) and day_of_week (0=Mon, 6=Sun) from target datetime
3. Query Prometheus for current cpu_rolling_mean and memory_rolling_mean
   - Support namespace, deployment, pod, and cluster-wide scoping
4. Call coordination engine `/api/v1/predict` endpoint with:
   ```json
   {
     "hour": 15,
     "day_of_week": 3,
     "cpu_rolling_mean": 68.2,
     "memory_rolling_mean": 74.5,
     "namespace": "self-healing-platform",
     "scope": "namespace"
   }
   ```
5. Format response with natural language recommendations

**Dependencies**:
- Requires coordination engine `/api/v1/predict` endpoint (see coordination-engine issue)
- Reuses existing Prometheus client
- Reuses existing KServe client

**Testing Requirements**:
- Unit tests with mocked Prometheus/KServe responses
- Integration tests with real coordination engine
- Test cases:
  - Specific time today (e.g., "15:00")
  - Tomorrow predictions (e.g., "2026-01-13 09:00")
  - Namespace-scoped predictions
  - Deployment-scoped predictions
  - Pod-scoped predictions
  - Cluster-wide predictions
  - Infrastructure pod predictions (openshift-*, kube-system)
  - Edge cases: invalid times, missing metrics

### Use Cases

1. **Application Pods**:
   ```
   User: "What will CPU be at 3 PM for my flask app?"
   Tool call: predict-resource-usage(target_time="15:00", deployment="flask-app")
   ```

2. **Infrastructure Monitoring**:
   ```
   User: "Predict memory usage for openshift-monitoring namespace at midnight"
   Tool call: predict-resource-usage(target_time="00:00", namespace="openshift-monitoring")
   ```

3. **Cluster-Wide Forecasting**:
   ```
   User: "What will overall cluster resource usage be tomorrow morning?"
   Tool call: predict-resource-usage(target_date="tomorrow", target_time="09:00", scope="cluster")
   ```

### Documentation Requirements
- Update README.md with tool description and examples
- Add inline code comments
- Update MCP server tool catalog

### Related Issues
- Coordination Engine: Add `/api/v1/predict` endpoint
- Blog: Update Part 3 with prediction examples

---

## Issue 2: Add `analyze-scaling-impact` MCP Tool for Replica Scaling Analysis

**Labels**: `enhancement`, `mcp-tool`, `capacity-planning`, `scaling`

### Summary
Add a new MCP tool that analyzes the impact of scaling deployments to different replica counts, including namespace resource impact, performance predictions, and infrastructure considerations.

### Problem Statement
Users need to understand "what if" scenarios before scaling:
- "If I scale my app to 5 replicas, what happens to cluster resources?"
- "Can the cluster handle 10 replicas of my deployment?"
- "What's the impact on infrastructure pods if I scale up?"

Without this tool, users must manually calculate resource impacts and risk exceeding namespace quotas or degrading infrastructure performance.

### Proposed Solution

**New Tool**: `analyze-scaling-impact`

**Input Schema**:
```json
{
  "deployment": "sample-flask-app",  // Required: deployment name
  "namespace": "my-namespace",       // Required: namespace
  "current_replicas": 2,             // Optional: auto-detected if not provided
  "target_replicas": 5,              // Required: desired replica count
  "predict_at": "17:00",             // Optional: specific time for prediction
  "include_infrastructure": true     // Optional: analyze impact on infra pods (default: true)
}
```

**Output Schema**:
```json
{
  "status": "success",
  "deployment": "sample-flask-app",
  "namespace": "my-namespace",
  "current_state": {
    "replicas": 2,
    "cpu_per_pod_avg": 45,
    "memory_per_pod_avg": 82,
    "total_cpu": 90,
    "total_memory": 164
  },
  "projected_state": {
    "replicas": 5,
    "cpu_per_pod_est": 47,
    "memory_per_pod_est": 84,
    "total_cpu": 235,
    "total_memory": 420
  },
  "namespace_impact": {
    "current_usage_percent": 74.5,
    "projected_usage_percent": 92.3,
    "quota_exceeded": false,
    "headroom_remaining_percent": 7.7,
    "limiting_factor": "memory"
  },
  "infrastructure_impact": {
    "etcd_impact": "low",
    "api_server_impact": "medium",
    "scheduler_impact": "low",
    "estimated_overhead": "5% increase in control plane CPU"
  },
  "warnings": [
    "Memory usage will approach 95% threshold",
    "Control plane load will increase moderately"
  ],
  "recommendation": "Scale to 4 replicas instead (projected: 86.7%). Or increase namespace memory quota by 20%.",
  "alternative_scenarios": [
    {"replicas": 4, "projected_usage": 86.7, "safe": true},
    {"replicas": 3, "projected_usage": 80.1, "safe": true}
  ]
}
```

### Implementation Details

**File Location**: `internal/tools/analyze_scaling_impact.go`

**Key Steps**:
1. Query current deployment state via Kubernetes API
   - Get current replica count if not provided
   - Get resource requests/limits
2. Query current pod resource usage from Prometheus
   - Calculate average CPU/memory per pod
   - Account for overhead (typically 2-5% per additional replica)
3. Calculate linear scaling projection
   - `projected_total = replicas * (avg_per_pod + overhead)`
4. Query namespace ResourceQuota
   - Get CPU/memory limits
   - Calculate current and projected usage percentages
5. Analyze infrastructure impact (optional):
   - Estimate etcd object count increase
   - Estimate API server request rate increase
   - Query control plane pod metrics
6. Generate warnings if:
   - Projected usage > 85% (warning)
   - Projected usage > 95% (critical)
   - Infrastructure metrics degraded
7. Generate alternative scenarios (e.g., target_replicas - 1, target_replicas - 2)

**Dependencies**:
- Kubernetes client (existing)
- Prometheus client (existing)
- Optional: Coordination engine for time-specific predictions

**Testing Requirements**:
- Unit tests with mocked K8s/Prometheus
- Test cases:
  - Scale up (2 → 5 replicas)
  - Scale down (5 → 2 replicas)
  - Scale up hitting quota limits
  - Scale up with infrastructure impact
  - Auto-detect current replica count
  - Time-specific predictions

### Use Cases

1. **Application Scaling**:
   ```
   User: "If I scale sample-flask-app to 5 replicas, what happens?"
   Tool call: analyze-scaling-impact(deployment="sample-flask-app", target_replicas=5)
   ```

2. **Infrastructure Safety Check**:
   ```
   User: "Can I scale my logging pods to 20 without impacting the cluster?"
   Tool call: analyze-scaling-impact(deployment="fluentd", target_replicas=20, include_infrastructure=true)
   ```

3. **Peak Hour Planning**:
   ```
   User: "Impact of scaling to 10 replicas at 5 PM?"
   Tool call: analyze-scaling-impact(deployment="api", target_replicas=10, predict_at="17:00")
   ```

### Documentation Requirements
- README.md with examples
- Document overhead calculation methodology
- Infrastructure impact analysis explanation

### Related Issues
- MCP Server: predict-resource-usage tool (optional integration)
- Coordination Engine: capacity analysis endpoints

---

## Issue 3: Add `calculate-pod-capacity` MCP Tool for Namespace/Cluster Capacity Planning

**Labels**: `enhancement`, `mcp-tool`, `capacity-planning`, `quota-management`

### Summary
Add a new MCP tool that calculates how many more pods can be deployed in a namespace or cluster based on resource quotas, current usage, and pod profiles.

### Problem Statement
Users frequently ask:
- "How many more pods can I run in my namespace?"
- "Do I have capacity for 10 medium-sized pods?"
- "What's my remaining cluster capacity?"
- "Can I deploy 50 more infrastructure monitoring agents?"

Without this tool, users must manually calculate available capacity, risking deployment failures or wasted capacity planning time.

### Proposed Solution

**New Tool**: `calculate-pod-capacity`

**Input Schema**:
```json
{
  "namespace": "my-namespace",     // Required: namespace name (or "cluster" for cluster-wide)
  "pod_profile": "medium",         // Optional: small, medium, large, custom (default: medium)
  "custom_resources": {            // Required if pod_profile="custom"
    "cpu": "200m",
    "memory": "128Mi"
  },
  "safety_margin": 15,             // Optional: percentage of headroom (default: 15)
  "include_trending": true         // Optional: include usage trends (default: true)
}
```

**Output Schema**:
```json
{
  "status": "success",
  "namespace": "my-namespace",
  "namespace_quota": {
    "cpu_limit": "10000m",
    "memory_limit": "10Gi",
    "pod_count_limit": 50
  },
  "current_usage": {
    "cpu": "6820m",
    "memory": "7648Mi",
    "cpu_percent": 68.2,
    "memory_percent": 74.5,
    "pod_count": 8
  },
  "available_capacity": {
    "cpu": "3180m",
    "memory": "2720Mi",
    "pod_slots": 42
  },
  "pod_estimates": {
    "small": {"cpu": "100m", "memory": "64Mi", "max_pods": 12, "safe_pods": 10},
    "medium": {"cpu": "200m", "memory": "128Mi", "max_pods": 6, "safe_pods": 5},
    "large": {"cpu": "400m", "memory": "256Mi", "max_pods": 2, "safe_pods": 2},
    "custom": {"cpu": "200m", "memory": "128Mi", "max_pods": 6, "safe_pods": 5}
  },
  "recommended_limit": {
    "pod_profile": "medium",
    "safe_pod_count": 5,
    "max_pod_count": 6,
    "limiting_factor": "memory",
    "explanation": "Memory constrains capacity. CPU could support 8 more pods."
  },
  "trending": {
    "daily_cpu_growth_percent": 1.5,
    "daily_memory_growth_percent": 2.0,
    "days_until_85_percent": 5,
    "projected_date": "2026-01-17"
  },
  "recommendation": "Can safely run 5 more medium-sized pods. Keep <85% memory for stability. Current trend suggests capacity exhaustion in 5 days."
}
```

### Implementation Details

**File Location**:
- `internal/tools/calculate_pod_capacity.go`
- `pkg/capacity/calculator.go` (reusable capacity logic)

**Key Steps**:
1. Query namespace ResourceQuota via Kubernetes API
   - CPU limits, memory limits, pod count limits
2. Query current resource usage from Prometheus
   - Sum all pod CPU/memory usage in namespace
   - Count running pods
3. Calculate available headroom:
   - `available = quota - current_usage`
4. For each pod profile (small/medium/large/custom):
   - `max_pods = floor(available_resources / pod_resources)`
   - `safe_pods = floor(available_resources * (1 - safety_margin) / pod_resources)`
   - Determine limiting factor (CPU, memory, or pod count)
5. Query Prometheus for usage trend (last 7 days):
   - Calculate daily growth percentage
   - Project days until 85% capacity threshold
6. Generate recommendations with safety margins

**Pod Profiles** (configurable defaults):
- **Small**: 100m CPU, 64Mi memory
- **Medium**: 200m CPU, 128Mi memory
- **Large**: 400m CPU, 256Mi memory
- **Custom**: User-defined resources

**Dependencies**:
- Kubernetes client (existing)
- Prometheus client (existing)
- New: `pkg/capacity/calculator.go` for capacity logic

**Testing Requirements**:
- Unit tests for capacity calculations
- Test cases:
  - Namespace with quota
  - Namespace without quota (unlimited)
  - Cluster-wide capacity (sum all namespaces)
  - Different pod profiles
  - Custom resource specifications
  - Trending calculations
  - Safety margin variations (0%, 15%, 25%)
  - Edge cases: already at/over quota

### Use Cases

1. **Basic Capacity Check**:
   ```
   User: "How many more pods can I run?"
   Tool call: calculate-pod-capacity(namespace="my-app")
   ```

2. **Infrastructure Planning**:
   ```
   User: "Can I deploy 50 monitoring agents in openshift-monitoring?"
   Tool call: calculate-pod-capacity(
     namespace="openshift-monitoring",
     custom_resources={"cpu": "50m", "memory": "128Mi"}
   )
   ```

3. **Multi-Size Analysis**:
   ```
   User: "Show me capacity for all pod sizes in my namespace"
   Tool call: calculate-pod-capacity(namespace="my-app", pod_profile="medium")
   // Returns estimates for small, medium, large, and custom
   ```

4. **Cluster-Wide Capacity**:
   ```
   User: "What's the total cluster capacity remaining?"
   Tool call: calculate-pod-capacity(namespace="cluster")
   ```

### Documentation Requirements
- README with examples for all pod profiles
- Explain capacity calculation methodology
- Document safety margin recommendations
- Trending analysis explanation

### Related Issues
- MCP Server: analyze-scaling-impact (can use capacity logic)

---

## Issue 4: Enhance `analyze-anomalies` Tool with Deployment and Pod Filtering

**Labels**: `enhancement`, `mcp-tool`, `filtering`, `existing-tool`

### Summary
Enhance the existing `analyze-anomalies` MCP tool to support filtering by specific deployments, pods, and infrastructure components.

### Problem Statement
Currently, `analyze-anomalies` only accepts:
- `metric` (required)
- `namespace` (optional)
- `time_range` (optional)

Users cannot ask deployment or pod-specific questions like:
- "Analyze anomalies in sample-flask-app deployment"
- "Check anomalies in etcd pods"
- "Analyze prometheus-k8s-0 pod metrics"

This forces users to analyze entire namespaces, making results less targeted.

### Proposed Solution

**Enhanced Input Schema**:
```json
{
  "metric": "cpu_usage",           // Required (existing)
  "namespace": "my-namespace",     // Optional (existing)
  "deployment": "sample-flask-app",// NEW: Optional deployment filter
  "pod": "pod-name-123",           // NEW: Optional specific pod filter
  "label_selector": "app=flask",   // NEW: Optional label selector
  "time_range": "24h",             // Optional (existing)
  "threshold": 0.7,                // Optional (existing)
  "model_name": "predictive-analytics" // Optional (existing)
}
```

**Implementation Changes**:

**File**: `internal/tools/analyze_anomalies.go`

**Prometheus Query Enhancement**:
```go
// Current query:
query := `avg(rate(container_cpu_usage_seconds_total{
  namespace="` + namespace + `"
}[24h]))`

// Enhanced query with deployment filter:
query := `avg(rate(container_cpu_usage_seconds_total{
  namespace="` + namespace + `",
  pod=~"` + deployment + `-.*"
}[24h]))`

// Enhanced query with specific pod filter:
query := `avg(rate(container_cpu_usage_seconds_total{
  namespace="` + namespace + `",
  pod="` + podName + `"
}[24h]))`

// Enhanced query with label selector:
query := `avg(rate(container_cpu_usage_seconds_total{
  namespace="` + namespace + `",
  ` + labelSelector + `
}[24h]))`
```

**Validation Logic**:
- `deployment` and `pod` are mutually exclusive
- `label_selector` can combine with namespace but not deployment/pod
- If `deployment` provided, automatically construct pod regex pattern

### Use Cases

1. **Deployment-Specific Analysis**:
   ```
   User: "Analyze CPU anomalies in my flask app"
   Tool call: analyze-anomalies(
     metric="cpu_usage",
     deployment="sample-flask-app",
     time_range="24h"
   )
   ```

2. **Infrastructure Pod Analysis**:
   ```
   User: "Check memory anomalies in etcd-0 pod"
   Tool call: analyze-anomalies(
     metric="memory_usage",
     pod="etcd-0",
     namespace="openshift-etcd"
   )
   ```

3. **Label-Based Filtering**:
   ```
   User: "Analyze all pods with label app=monitoring"
   Tool call: analyze-anomalies(
     metric="cpu_usage",
     label_selector="app=monitoring"
   )
   ```

### Testing Requirements
- Unit tests for all filter combinations
- Test cases:
  - Deployment filter
  - Pod filter
  - Label selector
  - Mutual exclusivity validation
  - Infrastructure pods (etcd, api-server, etc.)

### Documentation Requirements
- Update README with new parameters
- Add examples for each filter type
- Document validation rules

### Related Issues
- This enhancement complements predict-resource-usage and analyze-scaling-impact tools

---

## Additional Context

**Reference**: Implementation plan at `docs/implementation-plan-prediction-features.md` in `openshift-aiops-platform` repository.

**Use Case**: Enable OpenShift Lightspeed to answer natural language questions about:
- Future resource usage predictions
- Scaling impact analysis
- Capacity planning for application and infrastructure pods

**Repositories Involved**:
- `openshift-cluster-health-mcp` (MCP tools - these issues)
- `openshift-coordination-engine` (API endpoints - separate issues)
- `openshift-aiops-platform` (Blog documentation, deployment)

**Testing with OpenShift Lightspeed**:
All tools should be tested with OpenShift Lightspeed to ensure natural language queries work correctly for both application and infrastructure pods.
