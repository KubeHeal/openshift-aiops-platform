# Feature: Implement Prometheus Metrics Endpoint per ADR-010

## Priority
**P1 (High)** - Essential for production operations and fleet management

## Summary
Implement the Prometheus metrics endpoint as specified in [ADR-010: Observability and Monitoring Strategy](https://github.com/tosin2013/jupyter-notebook-validator-operator/blob/main/docs/adrs/010-observability-and-monitoring-strategy.md). While ADR-010 has STATUS: Accepted and provides comprehensive metrics specifications, the implementation has not yet been completed.

## Problem Statement

Production operators running **fleets of NotebookValidationJobs** (5+ notebooks, potentially 30+ like openshift-aiops-platform) lack visibility into:

1. **Operational Health**
   - How many notebook validation jobs are running/pending/completed?
   - What is the success rate over time?
   - Are any notebooks consistently failing?

2. **Performance Metrics**
   - How long do notebooks take to execute?
   - Are execution times increasing (regression detection)?
   - What is the resource consumption pattern?

3. **Capacity Planning**
   - How many concurrent validation jobs can the cluster handle?
   - When should we scale up operator replicas?
   - What are peak usage times?

4. **SLO/SLA Monitoring**
   - Are we meeting notebook execution time SLOs?
   - What percentage of notebooks succeed within target time?
   - Can we alert on degraded performance?

### Current State

- **ADR-010** (Observability and Monitoring Strategy) is ACCEPTED
- **Metrics specification exists** with detailed counter, gauge, and histogram definitions
- **Implementation is missing** - no `/metrics` endpoint currently exposed
- **Users cannot monitor** operator health or notebook execution patterns

## Proposed Solution

Implement Prometheus metrics endpoint as specified in ADR-010 using `controller-runtime/pkg/metrics`.

### Metrics to Implement

Based on ADR-010 specification:

#### Controller Metrics

```go
// notebookvalidationjob_reconcile_total
// Counter: Total number of reconciliation loops
// Labels: result={success|error|requeue}
notebookvalidationjob_reconcile_total

// notebookvalidationjob_reconcile_duration_seconds
// Histogram: Time spent in reconciliation loop
notebookvalidationjob_reconcile_duration_seconds
```

#### Job Execution Metrics

```go
// notebookvalidationjob_execution_total
// Counter: Total number of notebook executions
// Labels: phase={Succeeded|Failed|Timeout}, tier={tier1|tier2|tier3|tier4|tier5}
notebookvalidationjob_execution_total

// notebookvalidationjob_execution_duration_seconds
// Histogram: Time from job creation to completion
// Labels: phase={Succeeded|Failed|Timeout}, tier={tier1|tier2|tier3|tier4|tier5}
notebookvalidationjob_execution_duration_seconds

// notebookvalidationjob_cell_execution_count
// Counter: Number of notebook cells executed
// Labels: status={passed|failed}
notebookvalidationjob_cell_execution_count
```

#### Resource Metrics

```go
// notebookvalidationjob_active_pods
// Gauge: Current number of active validation pods
notebookvalidationjob_active_pods

// notebookvalidationjob_pending_jobs
// Gauge: Current number of pending jobs (not yet started)
notebookvalidationjob_pending_jobs
```

## Use Cases

### General Use Cases (Any Organization)

1. **Platform Teams Running Notebook Fleets**
   - Monitor 10-100+ notebook validation jobs across multiple namespaces
   - Alert on degraded success rates (e.g., <95% success)
   - Track long-running notebooks that may indicate infrastructure issues

2. **MLOps Teams with CI/CD Pipelines**
   - Monitor model training notebook success rates
   - Track execution time regressions (model training taking longer than baseline)
   - Capacity planning: When to add more cluster resources?

3. **Data Science Teams with Scheduled Notebooks**
   - Monitor daily/hourly data processing notebooks
   - Alert on missed SLOs (e.g., data processing must complete within 2 hours)
   - Track resource consumption patterns for cost optimization

4. **Compliance and Audit Teams**
   - Historical record of notebook execution success/failure
   - Audit trail for regulatory requirements
   - Demonstrate uptime and reliability metrics

5. **Site Reliability Engineering (SRE)**
   - Define SLOs for notebook execution time (e.g., p95 < 5 minutes)
   - Alert on operator health issues (high reconciliation errors)
   - Capacity planning based on historical trends

### Specific Example: openshift-aiops-platform

The [openshift-aiops-platform](https://github.com/KubeHeal/openshift-aiops-platform) runs **32 NotebookValidationJobs** across 11 ArgoCD sync waves:

**Current Challenge**:
- No visibility into which notebooks are slow
- Cannot detect regressions in notebook execution time
- Manual monitoring of `kubectl get notebookvalidationjobs -A` is not scalable

**With Metrics Endpoint**:
- Grafana dashboard showing all 32 notebooks' status
- Alert when any notebook fails 3 times in a row
- Track p95 execution time per tier (tier1: <2min, tier3: <5min, tier5: <10min)
- Capacity planning: "We have 5 concurrent notebooks, need to scale?"

**Example Prometheus Queries**:
```promql
# Success rate by tier (last 24 hours)
sum(rate(notebookvalidationjob_execution_total{phase="Succeeded"}[24h])) by (tier)
/ sum(rate(notebookvalidationjob_execution_total[24h])) by (tier)

# P95 execution time by tier
histogram_quantile(0.95,
  sum(rate(notebookvalidationjob_execution_duration_seconds_bucket[24h])) by (le, tier)
)

# Failed notebooks in last hour
sum(increase(notebookvalidationjob_execution_total{phase="Failed"}[1h])) by (namespace, name)
```

## Technical Design

### Implementation Overview

**File**: `controllers/notebookvalidationjob_controller.go`

```go
package controllers

import (
    "github.com/prometheus/client_golang/prometheus"
    "sigs.k8s.io/controller-runtime/pkg/metrics"
)

var (
    // Reconcile metrics
    reconcileTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "notebookvalidationjob_reconcile_total",
            Help: "Total number of reconciliation loops",
        },
        []string{"result"}, // success, error, requeue
    )

    reconcileDuration = prometheus.NewHistogram(
        prometheus.HistogramOpts{
            Name:    "notebookvalidationjob_reconcile_duration_seconds",
            Help:    "Time spent in reconciliation loop",
            Buckets: prometheus.DefBuckets,
        },
    )

    // Execution metrics
    executionTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "notebookvalidationjob_execution_total",
            Help: "Total number of notebook executions",
        },
        []string{"phase", "tier"}, // Succeeded/Failed/Timeout, tier1-5
    )

    executionDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "notebookvalidationjob_execution_duration_seconds",
            Help:    "Time from job creation to completion",
            Buckets: []float64{30, 60, 120, 300, 600, 1200, 1800}, // 30s to 30min
        },
        []string{"phase", "tier"},
    )

    cellExecutionCount = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "notebookvalidationjob_cell_execution_count",
            Help: "Number of notebook cells executed",
        },
        []string{"status"}, // passed, failed
    )

    // Resource metrics
    activePods = prometheus.NewGauge(
        prometheus.GaugeOpts{
            Name: "notebookvalidationjob_active_pods",
            Help: "Current number of active validation pods",
        },
    )

    pendingJobs = prometheus.NewGauge(
        prometheus.GaugeOpts{
            Name: "notebookvalidationjob_pending_jobs",
            Help: "Current number of pending jobs",
        },
    )
)

func init() {
    // Register metrics with controller-runtime metrics registry
    metrics.Registry.MustRegister(
        reconcileTotal,
        reconcileDuration,
        executionTotal,
        executionDuration,
        cellExecutionCount,
        activePods,
        pendingJobs,
    )
}
```

### Reconcile Loop Integration

```go
func (r *NotebookValidationJobReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    startTime := time.Now()
    defer func() {
        reconcileDuration.Observe(time.Since(startTime).Seconds())
    }()

    job := &validationv1alpha1.NotebookValidationJob{}
    if err := r.Get(ctx, req.NamespacedName, job); err != nil {
        if errors.IsNotFound(err) {
            reconcileTotal.WithLabelValues("success").Inc()
            return ctrl.Result{}, nil
        }
        reconcileTotal.WithLabelValues("error").Inc()
        return ctrl.Result{}, err
    }

    // Update resource metrics
    r.updateResourceMetrics(ctx)

    // Handle job execution
    result, err := r.reconcileJob(ctx, job)
    if err != nil {
        reconcileTotal.WithLabelValues("error").Inc()
        return result, err
    }

    if result.Requeue {
        reconcileTotal.WithLabelValues("requeue").Inc()
    } else {
        reconcileTotal.WithLabelValues("success").Inc()
    }

    return result, nil
}
```

### Status Update Integration

```go
func (r *NotebookValidationJobReconciler) updateJobStatus(
    ctx context.Context,
    job *validationv1alpha1.NotebookValidationJob,
    phase string,
) error {
    // Record execution metrics when job completes
    if phase == "Succeeded" || phase == "Failed" || phase == "Timeout" {
        tier := job.Labels["tier"] // e.g., "tier1", "tier2"
        if tier == "" {
            tier = "unknown"
        }

        executionTotal.WithLabelValues(phase, tier).Inc()

        // Calculate execution duration
        if job.Status.StartTime != nil && job.Status.CompletionTime != nil {
            duration := job.Status.CompletionTime.Sub(job.Status.StartTime.Time).Seconds()
            executionDuration.WithLabelValues(phase, tier).Observe(duration)
        }

        // Record cell execution counts
        if job.Status.CellExecutionSummary != nil {
            cellExecutionCount.WithLabelValues("passed").Add(
                float64(job.Status.CellExecutionSummary.Passed),
            )
            cellExecutionCount.WithLabelValues("failed").Add(
                float64(job.Status.CellExecutionSummary.Failed),
            )
        }
    }

    // ... existing status update logic ...
    return nil
}
```

### Resource Metrics Update

```go
func (r *NotebookValidationJobReconciler) updateResourceMetrics(ctx context.Context) {
    // Count active pods
    podList := &corev1.PodList{}
    if err := r.List(ctx, podList, client.MatchingLabels{
        "app.kubernetes.io/managed-by": "notebook-validation-controller",
    }); err == nil {
        active := 0
        for _, pod := range podList.Items {
            if pod.Status.Phase == corev1.PodRunning {
                active++
            }
        }
        activePods.Set(float64(active))
    }

    // Count pending jobs
    jobList := &validationv1alpha1.NotebookValidationJobList{}
    if err := r.List(ctx, jobList); err == nil {
        pending := 0
        for _, job := range jobList.Items {
            if job.Status.Phase == "" || job.Status.Phase == "Pending" {
                pending++
            }
        }
        pendingJobs.Set(float64(pending))
    }
}
```

## Deliverables

### 1. Metrics Implementation

- [ ] Metrics defined and registered in `init()`
- [ ] Reconcile loop instrumented with timing and result counters
- [ ] Status updates record execution metrics
- [ ] Resource metrics updated periodically

### 2. Metrics Endpoint

- [ ] Metrics exposed on `:8080/metrics` (controller-runtime default)
- [ ] Endpoint accessible from within cluster
- [ ] Endpoint returns Prometheus-compatible format

### 3. Kubernetes Manifests

**ServiceMonitor CR** (for Prometheus Operator):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: notebook-validation-operator
  namespace: notebook-validation-system
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: notebook-validation-operator
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
```

**Service** (expose metrics port):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: notebook-validation-operator-metrics
  namespace: notebook-validation-system
  labels:
    app.kubernetes.io/name: notebook-validation-operator
spec:
  ports:
  - name: metrics
    port: 8080
    targetPort: 8080
    protocol: TCP
  selector:
    app.kubernetes.io/name: notebook-validation-operator
```

### 4. Sample Grafana Dashboard

Provide JSON dashboard with panels:

1. **Overview**
   - Success rate (last 24h) - Gauge
   - Total executions (last 24h) - Counter
   - Active pods - Gauge

2. **Execution Metrics**
   - Execution duration by tier (p50, p95, p99) - Graph
   - Success/Failure rate by tier - Graph
   - Failed notebooks (last 1h) - Table

3. **Performance**
   - Reconcile duration histogram - Heatmap
   - Cell execution counts - Counter

4. **Capacity**
   - Active vs pending jobs - Graph
   - Resource utilization trend - Graph

**File**: `config/grafana/notebook-validation-dashboard.json`

### 5. Documentation

**User Guide**: `docs/monitoring.md`

```markdown
# Monitoring NotebookValidationJobs with Prometheus

## Metrics Endpoint

The operator exposes Prometheus metrics at `:8080/metrics`.

## Available Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `notebookvalidationjob_reconcile_total` | Counter | Reconciliation loops by result |
| `notebookvalidationjob_execution_total` | Counter | Executions by phase and tier |
| `notebookvalidationjob_execution_duration_seconds` | Histogram | Execution time distribution |
| `notebookvalidationjob_active_pods` | Gauge | Current active validation pods |

## Installation

1. Apply ServiceMonitor: `kubectl apply -f config/prometheus/servicemonitor.yaml`
2. Import Grafana dashboard: `config/grafana/notebook-validation-dashboard.json`

## Example Queries

### Success Rate (Last 24h)
```promql
sum(rate(notebookvalidationjob_execution_total{phase="Succeeded"}[24h]))
/ sum(rate(notebookvalidationjob_execution_total[24h]))
```

### P95 Execution Time
```promql
histogram_quantile(0.95,
  sum(rate(notebookvalidationjob_execution_duration_seconds_bucket[24h])) by (le, tier)
)
```
```

## Testing Strategy

### Unit Tests

```go
func TestReconcileMetrics(t *testing.T) {
    // Reset metrics
    reconcileTotal.Reset()
    reconcileDuration.Reset()

    r := &NotebookValidationJobReconciler{}
    req := ctrl.Request{NamespacedName: types.NamespacedName{
        Namespace: "default",
        Name:      "test-job",
    }}

    _, err := r.Reconcile(context.TODO(), req)
    assert.NoError(t, err)

    // Verify metrics incremented
    metric := testutil.ToFloat64(reconcileTotal.WithLabelValues("success"))
    assert.Equal(t, 1.0, metric)
}
```

### E2E Tests

1. **Deploy operator with metrics enabled**
2. **Create NotebookValidationJob**
3. **Scrape metrics endpoint**: `curl http://operator:8080/metrics`
4. **Verify metrics present**:
   - `notebookvalidationjob_execution_total{phase="Succeeded",tier="tier1"} 1`
   - `notebookvalidationjob_active_pods 1`

### Integration with openshift-aiops-platform

**Test Scenario**: Deploy 32 NotebookValidationJobs, verify metrics

```bash
# Deploy platform
make deploy

# Wait for notebooks to complete
kubectl wait --for=condition=Complete notebookvalidationjob --all -n self-healing-platform --timeout=30m

# Scrape metrics
kubectl port-forward -n notebook-validation-system svc/notebook-validation-operator-metrics 8080:8080 &
curl http://localhost:8080/metrics | grep notebookvalidationjob

# Expected output:
# notebookvalidationjob_execution_total{phase="Succeeded",tier="tier1"} 12
# notebookvalidationjob_execution_total{phase="Succeeded",tier="tier2"} 8
# notebookvalidationjob_execution_total{phase="Succeeded",tier="tier3"} 7
# notebookvalidationjob_execution_total{phase="Succeeded",tier="tier4"} 3
# notebookvalidationjob_execution_total{phase="Succeeded",tier="tier5"} 2
```

## Benefits

### For Platform Teams
- **Fleet visibility**: Monitor dozens/hundreds of notebooks from single dashboard
- **Proactive alerting**: Detect issues before users report them
- **Capacity planning**: Historical data informs scaling decisions

### For MLOps Teams
- **SLO tracking**: Ensure model training notebooks meet performance targets
- **Regression detection**: Alert when execution times increase unexpectedly
- **Cost optimization**: Identify resource-heavy notebooks

### For Site Reliability Engineers
- **Operational visibility**: Operator health, reconciliation errors
- **Incident response**: Historical data aids troubleshooting
- **Compliance**: Audit trail for notebook execution patterns

### For Operator Maintainers
- **Debugging**: Reconciliation duration helps identify performance bottlenecks
- **Adoption metrics**: Understand how users deploy notebooks (tier distribution)
- **Error patterns**: Identify common failure modes

## Alternatives Considered

### Alternative 1: Custom Logging-Based Monitoring
Parse controller logs to extract metrics.

**Rejected**:
- Not scalable (log parsing is fragile)
- No standardized format for tools (Grafana, Prometheus)
- Missing historical data aggregation

### Alternative 2: External Monitoring Service
Use third-party APM (DataDog, New Relic, etc.).

**Rejected**:
- Additional cost and complexity
- Prometheus is already standard in Kubernetes
- Integration with existing monitoring stacks

### Alternative 3: Status-Only Metrics (No Prometheus)
Users query `kubectl get notebookvalidationjobs` for status.

**Rejected**:
- Not automated (requires manual checks)
- No historical trends or aggregation
- Cannot integrate with alerting systems

## Priority Justification

**Why P1 (High Priority)**:

1. **Production Requirement**: ADR-010 is ACCEPTED, indicating this was planned functionality
2. **Operational Necessity**: Fleet management impossible without metrics (30+ notebooks)
3. **Industry Standard**: Prometheus metrics are expected in production operators
4. **Low Implementation Cost**: `controller-runtime/pkg/metrics` makes this straightforward
5. **High User Value**: Enables SLOs, alerting, capacity planning, troubleshooting

## Related Work

### Existing ADRs in jupyter-notebook-validator-operator

- **ADR-010: Observability and Monitoring Strategy** - Specifies metrics (ACCEPTED but not implemented)
- **ADR-011: Error Handling and Retry Strategy** - Metrics help track retry patterns
- **ADR-045: Volume Support** - Execution duration metrics detect slow storage

### Reference Implementations

- **controller-runtime metrics**: https://pkg.go.dev/sigs.k8s.io/controller-runtime/pkg/metrics
- **Prometheus best practices**: https://prometheus.io/docs/practices/naming/
- **Kubebuilder metrics guide**: https://book.kubebuilder.io/reference/metrics.html

## Acceptance Criteria

- [ ] All ADR-010 specified metrics implemented
- [ ] Metrics registered with controller-runtime metrics registry
- [ ] Metrics endpoint accessible at `:8080/metrics`
- [ ] ServiceMonitor CR provided for Prometheus Operator
- [ ] Sample Grafana dashboard JSON provided
- [ ] Documentation updated with metrics guide
- [ ] Unit tests verify metrics increment correctly
- [ ] E2E tests validate metrics endpoint
- [ ] Tested with openshift-aiops-platform (32 notebooks)

## References

- **ADR-010**: https://github.com/tosin2013/jupyter-notebook-validator-operator/blob/main/docs/adrs/010-observability-and-monitoring-strategy.md
- **openshift-aiops-platform**: https://github.com/KubeHeal/openshift-aiops-platform (32 NotebookValidationJobs)
- **Prometheus Operator**: https://prometheus-operator.dev/
- **controller-runtime metrics**: https://pkg.go.dev/sigs.k8s.io/controller-runtime/pkg/metrics

---

**Labels**: `enhancement`, `high-priority`, `observability`, `metrics`, `prometheus`

**Estimated Effort**: 5-7 days (metrics implementation, ServiceMonitor, Grafana dashboard, tests, docs)
