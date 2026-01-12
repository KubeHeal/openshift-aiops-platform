# GitHub Issues for openshift-coordination-engine

Repository: `https://github.com/tosin2013/openshift-coordination-engine`

---

## Issue 1: Add `/api/v1/predict` Endpoint for Time-Specific Resource Predictions

**Labels**: `enhancement`, `api`, `ml-integration`, `prediction`

### Summary
Add a new REST API endpoint that provides time-specific resource usage predictions using KServe ML models and Prometheus metrics. Supports predictions for any pod, deployment, namespace, or cluster-wide infrastructure.

### Problem Statement
The MCP server needs a coordination engine endpoint to:
- Accept time-based prediction requests (hour, day_of_week)
- Query Prometheus for current rolling metrics
- Call KServe predictive-analytics model
- Return formatted predictions with confidence scores

This enables natural language queries via OpenShift Lightspeed like:
- "What will CPU be at 3 PM today?"
- "Predict memory usage for infrastructure pods tomorrow at 9 AM"
- "What will cluster resources look like at midnight?"

### Proposed Solution

**Endpoint**: `POST /api/v1/predict`

**Request Schema**:
```json
{
  "hour": 15,                        // Required: 0-23 (hour of day)
  "day_of_week": 3,                  // Required: 0=Monday, 6=Sunday
  "namespace": "my-namespace",       // Optional: namespace filter
  "deployment": "my-app",            // Optional: deployment filter
  "pod": "pod-name",                 // Optional: specific pod filter
  "scope": "namespace",              // Optional: pod, deployment, namespace, cluster (default: namespace)
  "model": "predictive-analytics"    // Optional: KServe model name (default: predictive-analytics)
}
```

**Response Schema**:
```json
{
  "status": "success",
  "scope": "namespace",
  "target": "my-namespace",
  "predictions": {
    "cpu_percent": 74.5,
    "memory_percent": 81.2
  },
  "current_metrics": {
    "cpu_rolling_mean": 68.2,
    "memory_rolling_mean": 74.5,
    "timestamp": "2026-01-12T14:30:00Z",
    "time_range": "24h"
  },
  "model_info": {
    "name": "predictive-analytics",
    "version": "v1",
    "confidence": 0.92
  },
  "target_time": {
    "hour": 15,
    "day_of_week": 3,
    "iso_timestamp": "2026-01-12T15:00:00Z"
  }
}
```

**Error Response**:
```json
{
  "status": "error",
  "error": "Failed to query Prometheus metrics",
  "details": "Connection timeout after 30s",
  "code": "PROMETHEUS_UNAVAILABLE"
}
```

### Implementation Details

**File Location**: `pkg/handlers/prediction.go`

**Key Steps**:

1. **Validate Request**:
   ```go
   func (h *PredictionHandler) Validate(req *PredictRequest) error {
       if req.Hour < 0 || req.Hour > 23 {
           return fmt.Errorf("hour must be between 0-23")
       }
       if req.DayOfWeek < 0 || req.DayOfWeek > 6 {
           return fmt.Errorf("day_of_week must be between 0-6")
       }
       return nil
   }
   ```

2. **Query Prometheus for Rolling Metrics**:
   ```go
   // Query CPU rolling mean (24h window)
   cpuQuery := `avg(rate(container_cpu_usage_seconds_total{
       container!="",pod!="",namespace="` + namespace + `"
   }[24h]))`

   // Query Memory rolling mean (24h window)
   memoryQuery := `avg(container_memory_usage_bytes{
       container!="",pod!="",namespace="` + namespace + `"
   } / container_spec_memory_limit_bytes > 0)`

   // Apply filters based on scope:
   // - deployment: add pod=~"deployment-.*"
   // - pod: add pod="pod-name"
   // - cluster: remove namespace filter
   ```

3. **Call KServe Predictive Analytics Model**:
   ```go
   instances := [][]float64{{
       float64(req.Hour),
       float64(req.DayOfWeek),
       cpuRollingMean,
       memoryRollingMean,
   }}

   prediction, err := h.kserveClient.Predict(
       req.Model,
       instances,
   )
   ```

4. **Format Response**:
   ```go
   // Extract predictions [cpu_forecast, memory_forecast]
   cpuPercent := prediction.Predictions[0][0] * 100
   memoryPercent := prediction.Predictions[0][1] * 100

   // Build response with current + predicted metrics
   ```

5. **Cache Results** (optional):
   ```go
   // Cache predictions for 5 minutes (same time/scope combinations)
   cacheKey := fmt.Sprintf("predict:%d:%d:%s", req.Hour, req.DayOfWeek, req.Namespace)
   h.cache.Set(cacheKey, response, 5*time.Minute)
   ```

**Dependencies**:
- Existing Prometheus client (`pkg/clients/prometheus.go`)
- Existing KServe client (`pkg/clients/kserve.go`)
- New: `pkg/handlers/prediction.go`

**Files to Modify**:
- `pkg/api/routes.go` - Add route: `router.POST("/api/v1/predict", handlers.PredictHandler)`
- `pkg/clients/prometheus.go` - Add scoped query methods:
  - `GetCPURollingMean(namespace, deployment, pod string) (float64, error)`
  - `GetMemoryRollingMean(namespace, deployment, pod string) (float64, error)`

**Files to Create**:
- `pkg/handlers/prediction.go` - Prediction handler logic
- `pkg/handlers/prediction_test.go` - Unit tests

### Scoping Logic

**Namespace Scope** (default):
```promql
avg(rate(container_cpu_usage_seconds_total{
  namespace="my-namespace",
  container!="",pod!=""
}[24h]))
```

**Deployment Scope**:
```promql
avg(rate(container_cpu_usage_seconds_total{
  namespace="my-namespace",
  pod=~"my-deployment-.*",
  container!=""
}[24h]))
```

**Pod Scope**:
```promql
avg(rate(container_cpu_usage_seconds_total{
  namespace="my-namespace",
  pod="specific-pod-name",
  container!=""
}[24h]))
```

**Cluster Scope**:
```promql
avg(rate(container_cpu_usage_seconds_total{
  container!="",pod!=""
}[24h]))
```

### Testing Requirements

**Unit Tests** (`pkg/handlers/prediction_test.go`):
```go
func TestPredictHandler_Success(t *testing.T)
func TestPredictHandler_InvalidHour(t *testing.T)
func TestPredictHandler_InvalidDayOfWeek(t *testing.T)
func TestPredictHandler_PrometheusUnavailable(t *testing.T)
func TestPredictHandler_KServeUnavailable(t *testing.T)
func TestPredictHandler_NamespaceScope(t *testing.T)
func TestPredictHandler_DeploymentScope(t *testing.T)
func TestPredictHandler_PodScope(t *testing.T)
func TestPredictHandler_ClusterScope(t *testing.T)
```

**Integration Tests**:
```bash
# Test basic prediction
curl -X POST http://coordination-engine:8080/api/v1/predict \
  -H "Content-Type: application/json" \
  -d '{
    "hour": 15,
    "day_of_week": 3,
    "namespace": "self-healing-platform"
  }'

# Test infrastructure pod prediction
curl -X POST http://coordination-engine:8080/api/v1/predict \
  -d '{
    "hour": 0,
    "day_of_week": 1,
    "namespace": "openshift-monitoring",
    "deployment": "prometheus-k8s"
  }'

# Test cluster-wide prediction
curl -X POST http://coordination-engine:8080/api/v1/predict \
  -d '{
    "hour": 12,
    "day_of_week": 5,
    "scope": "cluster"
  }'
```

### Use Cases

1. **Application Prediction**:
   ```json
   POST /api/v1/predict
   {
     "hour": 15,
     "day_of_week": 3,
     "deployment": "sample-flask-app",
     "namespace": "my-app"
   }
   ```

2. **Infrastructure Prediction**:
   ```json
   POST /api/v1/predict
   {
     "hour": 0,
     "day_of_week": 1,
     "namespace": "openshift-etcd"
   }
   ```

3. **Cluster-Wide Prediction**:
   ```json
   POST /api/v1/predict
   {
     "hour": 12,
     "day_of_week": 5,
     "scope": "cluster"
   }
   ```

### Performance Considerations

- **Prometheus Query Cache**: 5-minute TTL to reduce query load
- **Response Time Target**: < 500ms end-to-end
- **Concurrent Requests**: Support 100+ requests/second
- **Graceful Degradation**: Return cached data if Prometheus temporarily unavailable

### Documentation Requirements

- Update API documentation with `/api/v1/predict` endpoint
- Add examples for all scopes (pod, deployment, namespace, cluster)
- Document Prometheus query patterns
- Add troubleshooting guide for prediction failures

### Related Issues
- MCP Server: `predict-resource-usage` tool (depends on this endpoint)
- Blog: Update Part 3 with prediction examples

---

## Issue 2: Add `/api/v1/capacity/namespace` Endpoint for Capacity Analysis

**Labels**: `enhancement`, `api`, `capacity-planning`, `quota-management`

### Summary
Add a new REST API endpoint that provides namespace (and cluster) capacity analysis including current usage, available resources, trending data, and infrastructure impact.

### Problem Statement
The MCP server needs capacity planning data to answer questions like:
- "How many more pods can I run?"
- "What's my remaining cluster capacity?"
- "How is resource usage trending over time?"
- "What's the impact on infrastructure if I add more pods?"

This data is currently scattered across Prometheus queries and requires manual aggregation.

### Proposed Solution

**Endpoint**: `GET /api/v1/capacity/namespace/{namespace}`

Alternative: `GET /api/v1/capacity/cluster` for cluster-wide analysis

**Request Parameters**:
```
GET /api/v1/capacity/namespace/my-namespace?include_trending=true&include_infrastructure=true
```

Query Parameters:
- `include_trending` (bool): Include 7-day usage trends (default: true)
- `include_infrastructure` (bool): Analyze infrastructure impact (default: false)
- `window` (string): Trending window - "7d", "30d" (default: "7d")

**Response Schema**:
```json
{
  "status": "success",
  "namespace": "my-namespace",
  "timestamp": "2026-01-12T14:30:00Z",
  "quota": {
    "cpu": {
      "limit": "10000m",
      "limit_numeric": 10.0
    },
    "memory": {
      "limit": "10Gi",
      "limit_bytes": 10737418240
    },
    "pod_count_limit": 50,
    "has_quota": true
  },
  "current_usage": {
    "cpu": {
      "used": "6820m",
      "used_numeric": 6.82,
      "percent": 68.2
    },
    "memory": {
      "used": "7648Mi",
      "used_bytes": 8020377600,
      "percent": 74.5
    },
    "pod_count": 8
  },
  "available": {
    "cpu": {
      "available": "3180m",
      "available_numeric": 3.18,
      "percent": 31.8
    },
    "memory": {
      "available": "2720Mi",
      "available_bytes": 2852126720,
      "percent": 25.5
    },
    "pod_slots": 42
  },
  "trending": {
    "cpu": {
      "daily_change_percent": 1.5,
      "weekly_change_percent": 10.5,
      "direction": "increasing"
    },
    "memory": {
      "daily_change_percent": 2.0,
      "weekly_change_percent": 14.0,
      "direction": "increasing"
    },
    "days_until_85_percent": 5,
    "projected_exhaustion_date": "2026-01-17",
    "confidence": 0.87
  },
  "infrastructure_impact": {
    "etcd_object_count": 1247,
    "etcd_capacity_percent": 12.47,
    "api_server_qps": 234,
    "scheduler_queue_length": 12,
    "control_plane_health": "healthy"
  }
}
```

**Cluster-Wide Response** (`GET /api/v1/capacity/cluster`):
```json
{
  "status": "success",
  "scope": "cluster",
  "timestamp": "2026-01-12T14:30:00Z",
  "cluster_capacity": {
    "total_cpu": "48000m",
    "total_memory": "128Gi",
    "allocatable_cpu": "45000m",
    "allocatable_memory": "120Gi"
  },
  "cluster_usage": {
    "cpu": {
      "used": "32400m",
      "percent": 72.0
    },
    "memory": {
      "used": "89600Mi",
      "percent": 74.7
    },
    "pod_count": 342
  },
  "namespaces": [
    {
      "name": "self-healing-platform",
      "cpu_percent": 68.2,
      "memory_percent": 74.5,
      "pod_count": 8
    },
    {
      "name": "openshift-monitoring",
      "cpu_percent": 45.3,
      "memory_percent": 62.1,
      "pod_count": 24
    }
  ],
  "infrastructure": {
    "control_plane_cpu_percent": 23.4,
    "control_plane_memory_percent": 45.2,
    "etcd_health": "healthy"
  }
}
```

### Implementation Details

**File Location**: `pkg/handlers/capacity.go`

**Key Steps**:

1. **Query Namespace ResourceQuota**:
   ```go
   quota, err := h.k8sClient.CoreV1().ResourceQuotas(namespace).Get(ctx, "default", metav1.GetOptions{})

   cpuLimit := quota.Status.Hard[corev1.ResourceCPU]
   memoryLimit := quota.Status.Hard[corev1.ResourceMemory]
   podCountLimit := quota.Status.Hard[corev1.ResourcePods]
   ```

2. **Query Current Usage from Prometheus**:
   ```go
   // CPU usage
   cpuQuery := `sum(rate(container_cpu_usage_seconds_total{
       namespace="` + namespace + `",container!=""
   }[5m]))`

   // Memory usage
   memoryQuery := `sum(container_memory_usage_bytes{
       namespace="` + namespace + `",container!=""
   })`

   // Pod count
   podCountQuery := `count(kube_pod_info{namespace="` + namespace + `"})`
   ```

3. **Calculate Available Capacity**:
   ```go
   availableCPU := cpuLimit - cpuUsed
   availableMemory := memoryLimit - memoryUsed
   availablePodSlots := podCountLimit - podCount
   ```

4. **Calculate Trending Data** (if requested):
   ```go
   // Query 7-day historical data
   cpuTrend := `avg_over_time(sum(rate(container_cpu_usage_seconds_total{
       namespace="` + namespace + `"
   }[5m]))[7d:1h])`

   // Linear regression to calculate daily change %
   dailyCPUChange := calculateTrend(cpuTrendData)

   // Project days until 85% threshold
   daysUntil85 := (0.85*cpuLimit - cpuUsed) / (dailyCPUChange * cpuLimit)
   ```

5. **Infrastructure Impact Analysis** (if requested):
   ```go
   // Query etcd metrics
   etcdObjects := queryPrometheus(`etcd_object_counts`)

   // Query API server metrics
   apiServerQPS := queryPrometheus(`apiserver_request_total:rate5m`)

   // Query scheduler metrics
   schedulerQueue := queryPrometheus(`scheduler_queue_incoming_pods`)
   ```

**Dependencies**:
- Kubernetes client (existing)
- Prometheus client (existing)
- New: `pkg/capacity/analyzer.go` - Capacity calculation logic
- New: `pkg/capacity/trending.go` - Trend analysis logic

**Files to Modify**:
- `pkg/api/routes.go` - Add routes:
  - `router.GET("/api/v1/capacity/namespace/:namespace", handlers.NamespaceCapacityHandler)`
  - `router.GET("/api/v1/capacity/cluster", handlers.ClusterCapacityHandler)`
- `pkg/clients/prometheus.go` - Add trend query methods

**Files to Create**:
- `pkg/handlers/capacity.go` - Capacity handler logic
- `pkg/handlers/capacity_test.go` - Unit tests
- `pkg/capacity/analyzer.go` - Capacity calculation utilities
- `pkg/capacity/trending.go` - Trend analysis algorithms

### Trending Analysis Algorithm

**Linear Regression for Trend Calculation**:
```go
func CalculateDailyChangePercent(dataPoints []float64, timestamps []time.Time) float64 {
    // Convert timestamps to days from start
    x := make([]float64, len(timestamps))
    for i, ts := range timestamps {
        x[i] = ts.Sub(timestamps[0]).Hours() / 24
    }

    // Linear regression: y = mx + b
    slope, _ := linearRegression(x, dataPoints)

    // Convert slope to daily change percentage
    dailyChange := slope / dataPoints[0] * 100
    return dailyChange
}
```

**Projection to Threshold**:
```go
func DaysUntilThreshold(current, limit, dailyChange, threshold float64) int {
    if dailyChange <= 0 {
        return -1 // Usage decreasing or stable
    }

    targetUsage := limit * threshold // e.g., 85% of limit
    delta := targetUsage - current
    days := delta / (dailyChange * limit / 100)

    return int(math.Ceil(days))
}
```

### Testing Requirements

**Unit Tests**:
```go
func TestCapacityHandler_NamespaceWithQuota(t *testing.T)
func TestCapacityHandler_NamespaceWithoutQuota(t *testing.T)
func TestCapacityHandler_ClusterWide(t *testing.T)
func TestCapacityHandler_Trending(t *testing.T)
func TestCapacityHandler_InfrastructureImpact(t *testing.T)
func TestTrendingAnalysis_LinearRegression(t *testing.T)
func TestTrendingAnalysis_DaysUntilThreshold(t *testing.T)
```

**Integration Tests**:
```bash
# Test namespace capacity
curl http://coordination-engine:8080/api/v1/capacity/namespace/my-namespace

# Test with trending
curl "http://coordination-engine:8080/api/v1/capacity/namespace/my-namespace?include_trending=true"

# Test infrastructure impact
curl "http://coordination-engine:8080/api/v1/capacity/namespace/openshift-monitoring?include_infrastructure=true"

# Test cluster-wide capacity
curl http://coordination-engine:8080/api/v1/capacity/cluster
```

### Use Cases

1. **Basic Capacity Check**:
   ```
   GET /api/v1/capacity/namespace/my-app
   ```

2. **Capacity Planning with Trends**:
   ```
   GET /api/v1/capacity/namespace/my-app?include_trending=true&window=30d
   ```

3. **Infrastructure Impact Analysis**:
   ```
   GET /api/v1/capacity/namespace/openshift-monitoring?include_infrastructure=true
   ```

4. **Cluster-Wide Capacity**:
   ```
   GET /api/v1/capacity/cluster
   ```

### Performance Considerations

- **Cache Duration**: 1 minute for capacity data (changes slowly)
- **Prometheus Query Optimization**: Use recording rules for frequently queried metrics
- **Response Time Target**: < 300ms for namespace, < 1s for cluster-wide
- **Trending Calculation**: Pre-compute or cache for 5 minutes

### Documentation Requirements

- API documentation for both endpoints
- Explain trending analysis methodology
- Document infrastructure impact metrics
- Add troubleshooting guide

### Related Issues
- MCP Server: `calculate-pod-capacity` tool (depends on this endpoint)
- MCP Server: `analyze-scaling-impact` tool (can use this data)

---

## Issue 3: Enhance Prometheus Client with Scoped Queries and Trending Analysis

**Labels**: `enhancement`, `prometheus`, `metrics`, `infrastructure`

### Summary
Enhance the existing Prometheus client to support scoped queries (pod, deployment, namespace, cluster) and trending analysis calculations used by the prediction and capacity endpoints.

### Problem Statement
Current Prometheus client methods are basic and don't support:
- Scoped queries (deployment-specific, pod-specific, cluster-wide)
- Trending analysis (daily change %, days until threshold)
- Infrastructure metric queries (etcd, API server, scheduler)
- Efficient query result caching

### Proposed Solution

**File**: `pkg/clients/prometheus.go`

**New Methods**:

```go
// Scoped CPU queries
func (c *PrometheusClient) GetCPUUsage(ctx context.Context, opts QueryOptions) (float64, error)
func (c *PrometheusClient) GetCPURollingMean(ctx context.Context, opts QueryOptions) (float64, error)

// Scoped Memory queries
func (c *PrometheusClient) GetMemoryUsage(ctx context.Context, opts QueryOptions) (float64, error)
func (c *PrometheusClient) GetMemoryRollingMean(ctx context.Context, opts QueryOptions) (float64, error)

// Trending analysis
func (c *PrometheusClient) GetCPUTrend(ctx context.Context, opts QueryOptions, window time.Duration) (*TrendData, error)
func (c *PrometheusClient) GetMemoryTrend(ctx context.Context, opts QueryOptions, window time.Duration) (*TrendData, error)

// Infrastructure metrics
func (c *PrometheusClient) GetETCDObjectCount(ctx context.Context) (int, error)
func (c *PrometheusClient) GetAPIServerQPS(ctx context.Context) (float64, error)
func (c *PrometheusClient) GetSchedulerQueueLength(ctx context.Context) (int, error)

// Helper methods
func (c *PrometheusClient) buildQueryWithScope(baseQuery string, opts QueryOptions) string
func (c *PrometheusClient) calculateTrend(data []TrendPoint) *TrendAnalysis
```

**Query Options Struct**:
```go
type QueryOptions struct {
    Namespace  string
    Deployment string
    Pod        string
    Scope      ScopeType
    TimeRange  time.Duration
}

type ScopeType string

const (
    ScopePod        ScopeType = "pod"
    ScopeDeployment ScopeType = "deployment"
    ScopeNamespace  ScopeType = "namespace"
    ScopeCluster    ScopeType = "cluster"
)
```

**Trend Data Structs**:
```go
type TrendPoint struct {
    Timestamp time.Time
    Value     float64
}

type TrendData struct {
    Points        []TrendPoint
    Current       float64
    Average       float64
    Min           float64
    Max           float64
}

type TrendAnalysis struct {
    DailyChangePercent   float64
    WeeklyChangePercent  float64
    Direction            string  // "increasing", "decreasing", "stable"
    DaysUntilThreshold   int     // -1 if not applicable
    ProjectedDate        time.Time
    Confidence           float64
}
```

### Implementation Examples

**Scoped Query Builder**:
```go
func (c *PrometheusClient) buildQueryWithScope(baseQuery string, opts QueryOptions) string {
    filters := []string{`container!=""`}

    if opts.Scope == ScopePod {
        filters = append(filters, fmt.Sprintf(`pod="%s"`, opts.Pod))
        filters = append(filters, fmt.Sprintf(`namespace="%s"`, opts.Namespace))
    } else if opts.Scope == ScopeDeployment {
        filters = append(filters, fmt.Sprintf(`pod=~"%s-.*"`, opts.Deployment))
        filters = append(filters, fmt.Sprintf(`namespace="%s"`, opts.Namespace))
    } else if opts.Scope == ScopeNamespace {
        filters = append(filters, fmt.Sprintf(`namespace="%s"`, opts.Namespace))
    }
    // ScopeCluster: no namespace filter

    filterStr := strings.Join(filters, ",")
    return fmt.Sprintf(baseQuery, filterStr)
}
```

**Trending Analysis**:
```go
func (c *PrometheusClient) GetCPUTrend(ctx context.Context, opts QueryOptions, window time.Duration) (*TrendData, error) {
    query := c.buildQueryWithScope(
        `avg_over_time(sum(rate(container_cpu_usage_seconds_total{%s}[5m]))[` + window.String() + `:1h])`,
        opts,
    )

    result, err := c.queryRange(ctx, query, time.Now().Add(-window), time.Now(), time.Hour)
    if err != nil {
        return nil, err
    }

    return c.parseTrendData(result), nil
}

func (c *PrometheusClient) calculateTrend(data []TrendPoint) *TrendAnalysis {
    if len(data) < 2 {
        return &TrendAnalysis{Direction: "insufficient_data"}
    }

    // Linear regression
    slope, _ := linearRegression(data)

    // Calculate daily change %
    dailyChange := (slope / data[0].Value) * 100

    // Determine direction
    direction := "stable"
    if dailyChange > 0.5 {
        direction = "increasing"
    } else if dailyChange < -0.5 {
        direction = "decreasing"
    }

    return &TrendAnalysis{
        DailyChangePercent:  dailyChange,
        WeeklyChangePercent: dailyChange * 7,
        Direction:           direction,
        Confidence:          calculateConfidence(data),
    }
}
```

**Infrastructure Metrics**:
```go
func (c *PrometheusClient) GetETCDObjectCount(ctx context.Context) (int, error) {
    query := `sum(etcd_object_counts)`
    result, err := c.queryInstant(ctx, query)
    if err != nil {
        return 0, err
    }
    return int(result.Value), nil
}

func (c *PrometheusClient) GetAPIServerQPS(ctx context.Context) (float64, error) {
    query := `sum(rate(apiserver_request_total[5m]))`
    result, err := c.queryInstant(ctx, query)
    return result.Value, err
}
```

### Testing Requirements

**Unit Tests**:
```go
func TestPrometheusClient_BuildQueryWithScope_Pod(t *testing.T)
func TestPrometheusClient_BuildQueryWithScope_Deployment(t *testing.T)
func TestPrometheusClient_BuildQueryWithScope_Namespace(t *testing.T)
func TestPrometheusClient_BuildQueryWithScope_Cluster(t *testing.T)
func TestPrometheusClient_GetCPUTrend(t *testing.T)
func TestPrometheusClient_CalculateTrend(t *testing.T)
func TestPrometheusClient_LinearRegression(t *testing.T)
func TestPrometheusClient_InfrastructureMetrics(t *testing.T)
```

### Documentation Requirements
- Document all new methods
- Add examples for scoped queries
- Explain trending analysis algorithms
- Document infrastructure metric sources

### Related Issues
- Coordination Engine: `/api/v1/predict` endpoint (uses scoped queries)
- Coordination Engine: `/api/v1/capacity/namespace` endpoint (uses trending)

---

## Additional Context

**Reference**: Implementation plan at `docs/implementation-plan-prediction-features.md` in `openshift-aiops-platform` repository.

**Dependencies**:
- These endpoints support MCP server tools in `openshift-cluster-health-mcp`
- Enable OpenShift Lightspeed natural language queries
- Support both application and infrastructure pod analysis

**Testing with Real Data**:
All endpoints should be tested with:
- Application workloads (user deployments)
- Infrastructure pods (openshift-*, kube-system)
- Different time ranges and scopes
- Edge cases (no quota, empty namespace, etc.)
