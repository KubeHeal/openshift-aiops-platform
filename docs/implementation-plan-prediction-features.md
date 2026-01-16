# Implementation Plan: Prediction & Capacity Planning Features

**Context**: Blog Part 3 promises natural language predictions that current MCP tools don't fully support.

**Goal**: Enable Lightspeed to answer:
- "What will CPU be at 3 PM today?"
- "If I scale sample-flask-app to 5 replicas, what happens?"
- "How many more pods can I run?"

---

## Current State Analysis

### What We Have

**MCP Server Tools** (`openshift-cluster-health-mcp`):
- ✅ `get-cluster-health` - Basic health checks
- ✅ `list-pods` - Pod discovery
- ✅ `analyze-anomalies` - Historical anomaly detection over time ranges
  - Accepts: `metric`, `namespace`, `time_range` ("1h", "6h", "24h", "7d")
  - Returns: Anomaly scores for past events

**Coordination Engine** (`openshift-coordination-engine`):
- ✅ REST API integration
- ✅ KServe model client
- ✅ Remediation engine

**KServe Models**:
- ✅ `anomaly-detector` - Detects anomalies in metrics
- ✅ `predictive-analytics` - Expects `[hour, day_of_week, cpu_rolling_mean, memory_rolling_mean]`

**Prometheus Integration**:
- ✅ Coordination engine queries Prometheus for metrics
- ✅ 5-minute caching

### What's Missing

1. ❌ **Time-specific predictions** - No "predict at 3 PM" capability
2. ❌ **Scaling impact analysis** - No "what if I scale to N replicas" tool
3. ❌ **Capacity planning** - No "how many pods can I run" calculator
4. ❌ **Pod-specific predictions** - Can't target "sample-flask-app" specifically

---

## Implementation Plan

### Phase 1: Enhanced Prediction Tool (MCP Server)

**New Tool**: `predict-resource-usage`

**Location**: `/home/lab-user/openshift-cluster-health-mcp/internal/tools/predict_resource_usage.go`

**Functionality**:
```go
// Input schema
{
  "target_time": "15:00",           // Optional: specific time (HH:MM) - defaults to current time
  "target_date": "2026-01-12",      // Optional: specific date - defaults to today
  "namespace": "self-healing-platform",
  "deployment": "sample-flask-app", // Optional: specific deployment
  "metric": "cpu_usage",            // cpu_usage, memory_usage, both
}

// Output
{
  "status": "success",
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
  "recommendation": "Memory approaching 85% threshold...",
  "model_used": "predictive-analytics"
}
```

**Implementation**:
1. Parse target time (default to current hour + 1)
2. Extract hour and day_of_week from target_time
3. Query Prometheus for cpu_rolling_mean and memory_rolling_mean
4. Call coordination engine `/api/v1/predict` endpoint
5. Format natural language response

**Files to Create**:
```
/home/lab-user/openshift-cluster-health-mcp/internal/tools/predict_resource_usage.go
/home/lab-user/openshift-cluster-health-mcp/internal/tools/predict_resource_usage_test.go
```

---

### Phase 2: Scaling Impact Analysis Tool (MCP Server)

**New Tool**: `analyze-scaling-impact`

**Location**: `/home/lab-user/openshift-cluster-health-mcp/internal/tools/analyze_scaling_impact.go`

**Functionality**:
```go
// Input schema
{
  "deployment": "sample-flask-app",
  "namespace": "self-healing-platform",
  "current_replicas": 2,           // Optional: auto-detected if not provided
  "target_replicas": 5,
  "predict_at": "17:00"            // Optional: specific time for prediction
}

// Output
{
  "status": "success",
  "current_state": {
    "replicas": 2,
    "cpu_per_pod": 45,
    "memory_per_pod": 82,
    "total_cpu": 90,
    "total_memory": 164
  },
  "projected_state": {
    "replicas": 5,
    "cpu_per_pod": 47,              // Slight increase due to overhead
    "memory_per_pod": 84,
    "total_cpu": 235,
    "total_memory": 420
  },
  "namespace_impact": {
    "current_usage": 74.5,
    "projected_usage": 92.3,
    "threshold_exceeded": false,
    "headroom_remaining": 7.7
  },
  "recommendation": "WARNING: Memory usage will approach critical threshold...",
  "alternative_scenarios": [
    {"replicas": 4, "projected_usage": 86.7},
    {"replicas": 3, "projected_usage": 80.1}
  ]
}
```

**Implementation**:
1. Query current deployment state via Kubernetes API
2. Get current pod resource usage from Prometheus
3. Calculate linear scaling impact (replicas * avg_per_pod)
4. Query namespace resource quotas/limits
5. Calculate projected namespace usage percentage
6. Generate warnings if approaching thresholds
7. Optionally call prediction model for time-specific forecast

**Files to Create**:
```
/home/lab-user/openshift-cluster-health-mcp/internal/tools/analyze_scaling_impact.go
/home/lab-user/openshift-cluster-health-mcp/internal/tools/analyze_scaling_impact_test.go
```

---

### Phase 3: Capacity Planning Tool (MCP Server)

**New Tool**: `calculate-pod-capacity`

**Location**: `/home/lab-user/openshift-cluster-health-mcp/internal/tools/calculate_pod_capacity.go`

**Functionality**:
```go
// Input schema
{
  "namespace": "self-healing-platform",
  "pod_profile": "medium",         // small, medium, large, custom
  "custom_resources": {            // Only if pod_profile = "custom"
    "cpu": "200m",
    "memory": "128Mi"
  },
  "safety_margin": 15              // Percentage of headroom to preserve (default: 15)
}

// Output
{
  "status": "success",
  "namespace_quota": {
    "cpu_limit": "10000m",
    "memory_limit": "10Gi"
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
    "memory": "2720Mi"
  },
  "pod_estimates": {
    "small": {"cpu": "100m", "memory": "64Mi", "max_pods": 12},
    "medium": {"cpu": "200m", "memory": "128Mi", "max_pods": 6},
    "large": {"cpu": "400m", "memory": "256Mi", "max_pods": 2}
  },
  "recommended_limit": {
    "pod_profile": "medium",
    "safe_pod_count": 5,
    "max_pod_count": 6,
    "limiting_factor": "memory"
  },
  "trending": {
    "daily_growth": 2.0,
    "days_until_85_percent": 5
  },
  "recommendation": "Can safely run 5 more medium-sized pods. Keep <85% memory for stability."
}
```

**Implementation**:
1. Query namespace ResourceQuota via Kubernetes API
2. Sum current pod resource usage from Prometheus
3. Calculate available headroom
4. For each pod profile, calculate: `floor(available_resources / pod_resources)`
5. Apply safety margin (default 85% max usage)
6. Query Prometheus for usage trend (last 7 days)
7. Calculate time-to-capacity

**Files to Create**:
```
/home/lab-user/openshift-cluster-health-mcp/internal/tools/calculate_pod_capacity.go
/home/lab-user/openshift-cluster-health-mcp/internal/tools/calculate_pod_capacity_test.go
/home/lab-user/openshift-cluster-health-mcp/pkg/capacity/calculator.go
/home/lab-user/openshift-cluster-health-mcp/pkg/capacity/calculator_test.go
```

---

### Phase 4: Coordination Engine API Extensions

**Location**: `https://github.com/tosin2013/openshift-coordination-engine`

**New Endpoints**:

#### 1. `/api/v1/predict` - Time-specific prediction

```go
// Request
{
  "hour": 15,                    // 0-23
  "day_of_week": 3,              // 0=Mon, 6=Sun
  "namespace": "self-healing-platform",
  "model": "predictive-analytics"
}

// Response
{
  "predictions": {
    "cpu_percent": 74.5,
    "memory_percent": 81.2
  },
  "current_metrics": {
    "cpu_rolling_mean": 68.2,
    "memory_rolling_mean": 74.5
  },
  "confidence": 0.92,
  "model_version": "v1"
}
```

#### 2. `/api/v1/capacity/namespace` - Namespace capacity info

```go
// Request
{
  "namespace": "self-healing-platform"
}

// Response
{
  "quota": {
    "cpu": "10000m",
    "memory": "10Gi"
  },
  "current_usage": {
    "cpu": "6820m",
    "memory": "7648Mi"
  },
  "available": {
    "cpu": "3180m",
    "memory": "2720Mi"
  },
  "pod_count": 8,
  "trend": {
    "cpu_daily_change_percent": 1.5,
    "memory_daily_change_percent": 2.0
  }
}
```

**Files to Modify**:
```
pkg/api/routes.go - Add new endpoints
pkg/handlers/prediction.go - Time-specific prediction handler
pkg/handlers/capacity.go - Capacity analysis handler
pkg/clients/prometheus.go - Add trend calculation methods
```

---

### Phase 5: Pod-Specific Query Enhancements

**Enhance Existing Tools**:

#### `analyze-anomalies` Enhancement
Add optional `deployment` parameter:

```go
// Enhanced input schema
{
  "metric": "cpu_usage",
  "namespace": "self-healing-platform",
  "deployment": "sample-flask-app",  // NEW: filter to specific deployment
  "time_range": "24h"
}

// Prometheus query changes from:
// avg(rate(container_cpu_usage_seconds_total{namespace="X"}[24h]))

// To:
// avg(rate(container_cpu_usage_seconds_total{
//   namespace="X",
//   pod=~"sample-flask-app-.*"
// }[24h]))
```

#### `list-pods` Enhancement
Already supports label selectors, document it better for deployment filtering.

**Files to Modify**:
```
/home/lab-user/openshift-cluster-health-mcp/internal/tools/analyze_anomalies.go
/home/lab-user/openshift-cluster-health-mcp/pkg/clients/kserve.go
```

---

## Implementation Priority

### Phase 1: Quick Wins (1-2 days)
1. ✅ **Enhance `analyze-anomalies`** with deployment filtering
2. ✅ **Create `predict-resource-usage`** tool
   - Reuse existing Prometheus integration
   - Call coordination engine with time parameters

### Phase 2: Moderate Complexity (3-4 days)
3. ✅ **Create `calculate-pod-capacity`** tool
   - Query namespace quotas
   - Calculate pod capacity estimates
   - Add trending analysis

### Phase 3: Advanced Features (5-7 days)
4. ✅ **Create `analyze-scaling-impact`** tool
   - Deployment state detection
   - Impact calculation
   - Alternative scenario generation

5. ✅ **Coordination Engine Extensions**
   - Add `/api/v1/predict` endpoint
   - Add `/api/v1/capacity/namespace` endpoint
   - Enhance Prometheus client with trending

---

## Testing Strategy

### Unit Tests
```go
// Example test structure
func TestPredictResourceUsage(t *testing.T) {
  tests := []struct {
    name           string
    input          map[string]interface{}
    mockPrometheus map[string]float64
    mockKServe     []float64
    want           interface{}
    wantErr        bool
  }{
    {
      name: "predict at 3 PM today",
      input: map[string]interface{}{
        "target_time": "15:00",
        "namespace":   "self-healing-platform",
        "metric":      "cpu_usage",
      },
      mockPrometheus: map[string]float64{
        "cpu_rolling_mean":    68.2,
        "memory_rolling_mean": 74.5,
      },
      mockKServe: []float64{0.745, 0.812},
      want: map[string]interface{}{
        "predicted_metrics": map[string]interface{}{
          "cpu_percent":    74.5,
          "memory_percent": 81.2,
        },
      },
    },
  }
}
```

### Integration Tests
```bash
# Test predict-resource-usage tool
curl -X POST http://mcp-server:8080/mcp \
  -d '{
    "tool": "predict-resource-usage",
    "arguments": {
      "target_time": "15:00",
      "namespace": "self-healing-platform"
    }
  }'

# Test scaling impact analysis
curl -X POST http://mcp-server:8080/mcp \
  -d '{
    "tool": "analyze-scaling-impact",
    "arguments": {
      "deployment": "sample-flask-app",
      "target_replicas": 5
    }
  }'

# Test capacity calculation
curl -X POST http://mcp-server:8080/mcp \
  -d '{
    "tool": "calculate-pod-capacity",
    "arguments": {
      "namespace": "self-healing-platform",
      "pod_profile": "medium"
    }
  }'
```

### End-to-End Tests with Lightspeed
```
User: "What will CPU be at 3 PM today?"
Expected: Lightspeed calls predict-resource-usage, returns forecast

User: "If I scale sample-flask-app to 5 replicas, what happens?"
Expected: Lightspeed calls analyze-scaling-impact, returns impact analysis

User: "How many more pods can I run?"
Expected: Lightspeed calls calculate-pod-capacity, returns capacity estimate
```

---

## Rollout Plan

### Step 1: MCP Server Changes
1. Create new tool files in `openshift-cluster-health-mcp`
2. Add unit tests
3. Update tool registration in server initialization
4. Build and test locally
5. Create PR, merge

### Step 2: Coordination Engine Changes
1. Clone `openshift-coordination-engine` repo
2. Add new API endpoints
3. Enhance Prometheus client
4. Add unit/integration tests
5. Build container image
6. Push to quay.io
7. Create PR, merge

### Step 3: Deployment
1. Update MCP server Helm chart with new tools
2. Update coordination engine image tag
3. Deploy to dev cluster
4. Test with Lightspeed
5. Deploy to production

### Step 4: Documentation
1. Update blog with accurate examples
2. Document new MCP tools in README
3. Add API documentation for coordination engine
4. Create troubleshooting guide

---

## Alternative: Interim Solution (Low Code)

If we want the blog to work **immediately** without waiting for full implementation:

### Option A: Simplify Blog Part 3

Update blog to show what **currently works**:

```markdown
## Part 3: Analyzing Historical Metrics

**You type:**
```
Analyze CPU usage in self-healing-platform over the last 24 hours
```

**Lightspeed responds:**
```
ML Analysis (anomaly-detector):
- Time range: Last 24 hours
- Average CPU: 68.2%
- Peak CPU: 87.3% (at 15:23 UTC)
- Anomalies detected: 2 (scores: 0.82, 0.91)
- Recommendation: Monitor during afternoon peak hours
```

### Option B: Rely on Lightspeed's Intelligence

Add a note that Lightspeed **translates** natural language to tool calls:

```markdown
**Note**: When you ask "What will CPU be at 3 PM?", Lightspeed's AI
understands your intent and translates it to the appropriate tool
calls (analyze-anomalies, list-pods, etc.) to provide the best
possible answer based on historical patterns.
```

This is **partially true** - Lightspeed will try to answer, but won't have time-specific predictions without the tools.

---

## Recommendation

**Short-term** (this week):
- Update blog Part 3 to show **historical analysis** (what works now)
- Add note about future prediction capabilities
- Keep the "vision" examples in a "Coming Soon" section

**Medium-term** (2-3 weeks):
- Implement Phase 1 (predict-resource-usage tool)
- Implement Phase 2 (calculate-pod-capacity tool)
- Update blog to reflect new capabilities

**Long-term** (1-2 months):
- Implement Phase 3 (analyze-scaling-impact tool)
- Full coordination engine integration
- Production-ready prediction features

---

## Files to Create/Modify Summary

### MCP Server Repository (`openshift-cluster-health-mcp`)
**New files**:
- `internal/tools/predict_resource_usage.go`
- `internal/tools/predict_resource_usage_test.go`
- `internal/tools/analyze_scaling_impact.go`
- `internal/tools/analyze_scaling_impact_test.go`
- `internal/tools/calculate_pod_capacity.go`
- `internal/tools/calculate_pod_capacity_test.go`
- `pkg/capacity/calculator.go`
- `pkg/capacity/calculator_test.go`

**Modified files**:
- `internal/tools/analyze_anomalies.go` (add deployment filter)
- `internal/server/server.go` (register new tools)
- `README.md` (document new tools)

### Coordination Engine Repository (`openshift-coordination-engine`)
**New files**:
- `pkg/handlers/prediction.go`
- `pkg/handlers/capacity.go`
- `pkg/capacity/analyzer.go`

**Modified files**:
- `pkg/api/routes.go` (add new endpoints)
- `pkg/clients/prometheus.go` (add trending methods)
- `README.md` (document new APIs)

### Platform Repository (`openshift-aiops-platform`)
**Modified files**:
- `docs/blog/16-end-to-end-self-healing-with-lightspeed.md` (update Part 3)
- `charts/hub/values.yaml` (new MCP server image tag)
- `charts/hub/templates/coordination-engine-deployment.yaml` (new image tag)

---

**Next Steps**: Which approach do you prefer?
1. Implement the full solution (2-3 weeks)
2. Update blog to reflect current capabilities
3. Hybrid: Implement Phase 1 quickly (predict-resource-usage) + update blog
