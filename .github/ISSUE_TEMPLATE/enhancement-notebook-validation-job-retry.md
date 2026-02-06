# Enhancement: NotebookValidationJob Operator Should Auto-Retry Failed Jobs

## Problem Statement

The `NotebookValidationJob` operator currently requires manual intervention when a job fails. After a job enters `Failed` state (e.g., due to `OOMKilled`), the operator does not automatically retry or recreate the job, even when:

1. **Resource configuration changes** (e.g., GPU enabled, memory increased)
2. **Underlying infrastructure improves** (e.g., GPU nodes become available, storage issues resolved)
3. **Transient failures occur** (e.g., network timeouts, temporary resource constraints)

### Current Behavior

```bash
# Job fails with OOMKilled
oc get notebookvalidationjob predictive-analytics-kserve-validation -n self-healing-platform
# STATUS: Failed
# PHASE: Failed
# MESSAGE: Validation failed after 3 retries: OOMKilled

# Even after fixing the issue (enabling GPU, increasing memory), the job remains Failed
# Manual deletion required:
oc delete notebookvalidationjob predictive-analytics-kserve-validation -n self-healing-platform
```

### Expected Behavior

The operator should intelligently handle failed jobs by:
1. **Detecting spec changes** and automatically recreating the job
2. **Configurable retry policies** with exponential backoff
3. **Auto-cleanup** of failed jobs after a grace period
4. **Status reconciliation** to detect when underlying issues are resolved

## Use Case

**Scenario**: Model training job fails due to `OOMKilled` error.

1. **Initial State**: Job configured with 8Gi memory, no GPU
2. **Failure**: Job fails with `OOMKilled` after 3 retries
3. **Fix Applied**: 
   - GPU enabled in `values-hub.yaml`
   - ArgoCD syncs changes
   - Job spec updated with `nvidia.com/gpu: "1"`
4. **Current Behavior**: Job remains in `Failed` state, requires manual deletion
5. **Expected Behavior**: Operator detects spec change and automatically recreates job

## Proposed Solution

### Option 1: Spec Change Detection (Recommended)

The operator should watch for changes to the `NotebookValidationJob` spec and automatically recreate failed jobs when:
- Resource limits/requests change
- GPU configuration changes
- Image or notebook path changes
- Any other spec field that affects job execution

**Implementation**:
```go
// Pseudo-code
func (r *NotebookValidationJobReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    job := &mlopsv1alpha1.NotebookValidationJob{}
    if err := r.Get(ctx, req.NamespacedName, job); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }
    
    // If job failed and spec changed, recreate
    if job.Status.Phase == "Failed" {
        if r.hasSpecChanged(job) {
            // Delete existing job and let reconciliation recreate it
            return r.recreateJob(ctx, job)
        }
    }
    
    // ... existing reconciliation logic
}
```

### Option 2: Configurable Retry Policy

Add a `retryPolicy` field to the `NotebookValidationJob` spec:

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: predictive-analytics-kserve-validation
spec:
  # ... existing spec ...
  retryPolicy:
    enabled: true
    maxRetries: 5  # Total retries (not just per-pod)
    backoffPolicy: exponential
    backoffBaseSeconds: 60
    maxBackoffSeconds: 3600
    retryOnSpecChange: true  # Retry when spec changes
    autoCleanupAfterHours: 24  # Delete failed job after 24h
```

### Option 3: Status Reconciliation

Periodically check if conditions that caused failure have been resolved:
- Resource availability (GPU nodes, storage)
- Network connectivity
- Image pullability
- Storage mountability

## Benefits

1. **Reduced Manual Intervention**: No need to manually delete failed jobs
2. **Faster Recovery**: Automatic retry when issues are resolved
3. **Better GitOps Experience**: Changes in Git automatically trigger job recreation
4. **Self-Healing**: Platform automatically recovers from transient failures

## Implementation Details

### Files to Modify

- `notebook-validation-job-controller.go`: Add spec change detection logic
- `notebook-validation-job_types.go`: Add `retryPolicy` field (if Option 2)
- `notebook-validation-job_controller_test.go`: Add test cases

### Breaking Changes

None - this is a backward-compatible enhancement.

### Migration Path

Existing failed jobs will remain in `Failed` state until manually deleted or until the operator is upgraded and detects spec changes.

## Related Issues

- Issue #34: Model training OOMKilled errors
- ADR-029: Infrastructure Validation Notebook
- ADR-030: Advanced Comparison for ML Metric Variations

## Acceptance Criteria

- [ ] Operator detects spec changes in failed jobs
- [ ] Operator automatically recreates failed jobs when spec changes
- [ ] Configurable retry policy (optional, if Option 2 implemented)
- [ ] Unit tests for spec change detection
- [ ] Integration tests for auto-retry behavior
- [ ] Documentation updated with new behavior

## Additional Context

**Operator**: `jupyter-notebook-validator-operator`  
**Version**: v1.0.5+  
**Repository**: https://github.com/takinosh/jupyter-notebook-validator-operator  
**Current Behavior**: Jobs remain in `Failed` state after retries exhausted  
**Desired Behavior**: Jobs auto-retry when spec changes or conditions improve

---

**Labels**: `enhancement`, `operator`, `notebook-validation`, `good-first-issue`  
**Priority**: Medium  
**Estimated Effort**: 2-3 days
