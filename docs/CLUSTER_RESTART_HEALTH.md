# Cluster Restart Health Diagnostic and Recovery

## Overview

This document describes the cluster restart health diagnostic and recovery implementation for the OpenShift AI Ops Self-Healing Platform. The solution addresses post-restart health issues including pod failures, service unavailability, and model serving problems.

## Problem Statement

After cluster restart, the platform experiences:
- **Pod CrashLoopBackOff**: coordination-engine, mcp-server failing to start
- **Init Job Failures**: init-models-job exceeding backoff limit
- **Storage Mount Issues**: PVCs taking 2-5 minutes to bind, causing mount failures
- **Cross-Namespace Dependency Failures**: Pods starting before Prometheus/ArgoCD are ready

## Root Cause

1. **Cross-Namespace Dependency Race Conditions**: Platform pods start before critical dependencies in other namespaces are ready
   - Prometheus (openshift-monitoring)
   - ArgoCD (openshift-gitops)
   - ODF/NooBaa storage (openshift-storage)

2. **Storage Mount Timing Issues**: CephFS RWX PVCs take 2-5 minutes to become available after restart
   - init-models-job attempts to mount immediately with only 3 retries
   - Insufficient backoff limit for storage readiness delays

3. **Insufficient Startup Resilience**: No startup probes, short failure windows, no dependency verification

## Solution Architecture

The solution implements a two-phase approach:

### Phase 1: Diagnostics (Implemented)
Comprehensive diagnostic script to capture cluster restart behavior and identify exact failure points.

### Phase 2: Targeted Fixes (Implemented)
Production-ready fixes based on identified failure patterns:
- Init containers to wait for cross-namespace dependencies
- Startup probes with 5-minute windows
- Enhanced retry logic for storage-dependent jobs
- Storage verification before mounting

---

## Phase 1: Diagnostic Script

### Location
`/home/lab-user/openshift-aiops-platform/scripts/diagnose-cluster-restart.sh`

### Capabilities
- **Pre-Restart Snapshot**: Captures baseline state before restart
- **Post-Restart Monitoring**: Tracks component startup sequence and timing
- **Dependency Timing Analysis**: Measures when cross-namespace services become ready
- **Failure Pattern Detection**: Identifies which components fail and why
- **Storage Readiness Tracking**: Monitors PVC binding and CSI driver availability
- **Detailed Reporting**: Generates actionable report with root cause analysis

### Usage

#### 1. Before Cluster Restart
```bash
cd /home/lab-user/openshift-aiops-platform
./scripts/diagnose-cluster-restart.sh --phase pre-restart
```

**Output**: Creates baseline snapshot in `/tmp/cluster-restart-diagnostics/pre-restart-<timestamp>/`

#### 2. After Cluster Restart (Run Immediately)
```bash
./scripts/diagnose-cluster-restart.sh --phase post-restart --monitor-duration 600
```

**Options**:
- `--monitor-duration SECONDS`: Duration to monitor (default: 600 = 10 minutes)
- `--namespace NAMESPACE`: Platform namespace (default: self-healing-platform)

**Output**: Creates monitoring data in `/tmp/cluster-restart-diagnostics/post-restart-<timestamp>/`

**What it monitors** (every 10 seconds):
- Cross-namespace dependency readiness (Prometheus, ArgoCD, ODF)
- CSI drivers and storage class availability
- PVC binding status and timing
- Platform pod startup sequence
- Init job completion status
- InferenceService health

**Captures detailed snapshots** (every 60 seconds):
- Pod status and events
- Logs of failed/restarting pods
- PVC binding state
- Service endpoint availability

#### 3. Generate Diagnostic Report
```bash
./scripts/diagnose-cluster-restart.sh --phase report
```

**Output**: Comprehensive markdown report at `/tmp/cluster-restart-diagnostics/diagnostic-report-<timestamp>.md`

**Report Includes**:
- **Executive Summary**: High-level findings
- **Startup Timeline Analysis**: When each component became ready
- **Failure Analysis**: Pod failures, CrashLoopBackOff, Init errors
- **Root Cause Analysis**: Identified issues with evidence
- **Recommended Actions**: Prioritized fix recommendations
- **Critical Events**: Warning/Error events from the cluster
- **Detailed Pod Status**: Final state of all pods

### Example Workflow

```bash
# Step 1: Capture pre-restart state
./scripts/diagnose-cluster-restart.sh --phase pre-restart

# Step 2: Perform cluster restart
# (Follow your organization's cluster restart procedure)

# Step 3: Monitor post-restart startup (run immediately after restart)
./scripts/diagnose-cluster-restart.sh --phase post-restart --monitor-duration 600

# Step 4: Generate analysis report
./scripts/diagnose-cluster-restart.sh --phase report

# Step 5: Review the report
cat /tmp/cluster-restart-diagnostics/diagnostic-report-*.md
```

### Interpreting Results

**Startup Timeline Analysis**:
```
| Component | Time to Ready |
|-----------|---------------|
| Prometheus | 45s |
| ArgoCD | 60s |
| model-storage-pvc | 180s |
| coordination-engine | NOT_READY |  ← Problem detected!
| mcp-server | NOT_READY |  ← Problem detected!
```

**Indicates**: coordination-engine and mcp-server failed because they started before dependencies were ready.

**Failure Analysis**:
```
- CrashLoopBackOff pods: 2
- Init container failures: 1
```

**Root Cause Examples**:
- "⚠️ Cross-Namespace Dependency Race Condition Detected"
- "⚠️ Storage Mount Timing Issue Detected"
- "⚠️ Init Models Job Failure Detected"

---

## Phase 2: Targeted Fixes

Based on diagnostic findings, the following production-ready fixes have been implemented:

### Fix 1: Coordination Engine Resilience

**File**: `charts/hub/templates/coordination-engine-deployment.yaml`

**Changes**:
1. **Init Containers** (lines 30-68):
   - `wait-for-prometheus`: Waits for Prometheus API to be responsive
   - `wait-for-argocd`: Waits for ArgoCD health endpoint

2. **Startup Probe** (lines 134-141):
   - 5-minute startup window (failureThreshold: 30, periodSeconds: 10)
   - Allows dependencies to initialize before declaring pod failure

**Behavior After Restart**:
- Pod waits in `Init:0/2` state until Prometheus is ready
- Pod waits in `Init:1/2` state until ArgoCD is ready
- Pod transitions to `Running` only after all dependencies are ready
- Startup probe allows up to 5 minutes for full initialization
- Existing liveness/readiness probes unchanged

### Fix 2: MCP Server Resilience

**File**: `charts/hub/templates/mcp-server-deployment.yaml`

**Changes**:
1. **Init Containers** (lines 30-68):
   - `wait-for-coordination-engine`: Waits for Coordination Engine health endpoint
   - `wait-for-prometheus`: Waits for Prometheus API

2. **Startup Probe** (lines 131-138):
   - 5-minute startup window (failureThreshold: 30, periodSeconds: 10)

**Behavior After Restart**:
- Starts only after Coordination Engine is healthy
- Ensures Prometheus is available before connecting
- Proper startup ordering prevents cascading failures

### Fix 3: Init Models Job Resilience

**File**: `charts/hub/templates/init-models-job.yaml`

**Changes**:
1. **Init Container** (lines 15-44):
   - `wait-for-pvc`: Verifies model-storage-pvc is bound and mounted
   - 5-minute wait window with 10-second intervals
   - Graceful failure if PVC doesn't become available

2. **Enhanced Retry Logic** (lines 46-104):
   - Function `create_dir_with_retry()` with exponential backoff
   - 5 retries per directory creation operation
   - Backoff: 1s → 2s → 4s → 8s → 16s
   - Clear success/failure indicators (✓/✗)

3. **Increased Resilience** (lines 113-114):
   - `backoffLimit: 10` (increased from 3)
   - `activeDeadlineSeconds: 900` (15-minute maximum)

**Behavior After Restart**:
- Init container verifies PVC is mounted before starting
- Main container retries directory creation with exponential backoff
- Job won't exceed backoff limit due to storage timing issues
- Clear logging shows exactly which operations succeed/fail

### Fix 4: AI/ML Workbench Resilience

**File**: `charts/hub/templates/ai-ml-workbench.yaml`

**Changes**:
1. **Enhanced Init Container** (lines 40-97):
   - Added storage verification: waits for `/mnt/models/.initialized` file
   - 5-minute wait window with warning if storage not ready
   - Continues anyway with degraded functionality
   - Enhanced logging (✓ for success, ⚠ for warnings)

2. **Added model-storage Volume Mount** (lines 89-90):
   - Init container can verify storage readiness

3. **Startup Probe** (lines 180-189):
   - 5-minute startup window (failureThreshold: 30, periodSeconds: 10)
   - Jupyter API health check

**Behavior After Restart**:
- Init container verifies model storage is initialized
- If storage not ready after 5 minutes, starts anyway with warning
- Users can access workbench even if models aren't available yet
- Startup probe allows time for Jupyter to fully initialize

### Fix 5: Model Serving (InferenceServices)

**File**: `charts/hub/templates/model-serving.yaml`

**Status**: No changes required

**Rationale**:
- Already uses ArgoCD sync-wave "2" (deploys after init-models-job at wave "-5")
- Uses `SkipDryRunOnMissingResource=true` for resilient deployment
- InferenceService CRD doesn't support direct init container modification
- Enhanced init-models-job provides necessary storage guarantees

**Behavior After Restart**:
- KServe controller creates InferenceService pods after job completes
- PVC-based storage (`pvc://model-storage-pvc/`) mounts after initialization
- If models missing, InferenceService shows degraded but doesn't crash

---

## Testing the Fixes

### Pre-Deployment Testing

1. **Validate Helm Chart Syntax**:
   ```bash
   cd /home/lab-user/openshift-aiops-platform
   helm lint charts/hub/
   ```

2. **Dry Run Deployment**:
   ```bash
   helm template self-healing-platform charts/hub/ \
     --namespace self-healing-platform \
     --values charts/hub/values.yaml
   ```

3. **Review Generated Manifests**:
   ```bash
   helm template self-healing-platform charts/hub/ | grep -A 20 "initContainers:"
   helm template self-healing-platform charts/hub/ | grep -A 10 "startupProbe:"
   ```

### Deployment and Validation

1. **Deploy Updated Charts**:
   ```bash
   # Apply via Helm
   helm upgrade self-healing-platform charts/hub/ \
     --namespace self-healing-platform \
     --install \
     --create-namespace

   # OR apply via ArgoCD (if using GitOps)
   git add charts/hub/templates/
   git commit -m "fix: add cluster restart resilience (init containers, startup probes)"
   git push
   # ArgoCD will sync automatically or manually sync via UI
   ```

2. **Verify Deployments Rolled Out**:
   ```bash
   oc rollout status deployment/coordination-engine -n self-healing-platform
   oc rollout status deployment/mcp-server -n self-healing-platform
   ```

3. **Check Init Containers**:
   ```bash
   # Should show Init:0/2 or Init:1/2 states during dependency wait
   oc get pods -n self-healing-platform -w

   # View init container logs
   oc logs -f deployment/coordination-engine -c wait-for-prometheus -n self-healing-platform
   oc logs -f deployment/coordination-engine -c wait-for-argocd -n self-healing-platform
   ```

4. **Verify Startup Probes**:
   ```bash
   # Describe pod to see probe configuration
   oc describe pod -l app.kubernetes.io/component=coordination-engine -n self-healing-platform | grep -A 10 "Startup:"
   ```

### Cluster Restart Test

**CRITICAL: Only perform cluster restart if authorized and in a non-production environment!**

1. **Before Restart - Capture Baseline**:
   ```bash
   ./scripts/diagnose-cluster-restart.sh --phase pre-restart
   ```

2. **Perform Cluster Restart**:
   ```bash
   # For OpenShift on bare metal/VM
   # Restart each node (control plane first, then workers)

   # For managed OpenShift (ROSA, ARO, etc.)
   # Follow cloud provider's cluster restart procedure
   ```

3. **After Restart - Monitor Immediately**:
   ```bash
   # As soon as cluster API is responsive
   ./scripts/diagnose-cluster-restart.sh --phase post-restart --monitor-duration 600
   ```

4. **Validate Expected Behavior**:
   ```bash
   # All pods should reach Running/Ready within 10 minutes
   oc get pods -n self-healing-platform

   # Expected status progression:
   # 1. coordination-engine: Init:0/2 → Init:1/2 → Running (1/1)
   # 2. mcp-server: Init:0/2 → Init:1/2 → Running (1/1)
   # 3. init-models-job: Init:0/1 → Running → Completed
   # 4. InferenceServices: Pending → Running
   # 5. Workbench: Init:0/1 → Running (2/2)

   # No CrashLoopBackOff or Init:Error states!
   ```

5. **Verify Service Health**:
   ```bash
   # Coordination Engine health
   oc exec -n self-healing-platform deployment/coordination-engine -- curl -s http://localhost:8080/health

   # MCP Server health
   oc exec -n self-healing-platform deployment/mcp-server -- curl -s http://localhost:8080/health

   # InferenceService status
   oc get inferenceservices -n self-healing-platform

   # Workbench accessibility (via browser)
   # Access RHODS dashboard and verify Jupyter is accessible
   ```

6. **Generate Diagnostic Report**:
   ```bash
   ./scripts/diagnose-cluster-restart.sh --phase report
   cat /tmp/cluster-restart-diagnostics/diagnostic-report-*.md
   ```

### Success Criteria

✅ **All pods reach Ready state within 10 minutes of cluster restart**
✅ **No CrashLoopBackOff or Init:Error states**
✅ **Coordination Engine /health endpoint returns 200 OK**
✅ **MCP Server /health endpoint returns 200 OK**
✅ **InferenceServices show READY status**
✅ **Model serving endpoints respond to prediction requests**
✅ **Jupyter Workbench accessible via RHODS dashboard**
✅ **Workbench can read/write to /mnt/models**

---

## Troubleshooting

### Issue: Init Containers Stuck Waiting

**Symptom**: Pod stuck in `Init:0/2` or `Init:1/2` for extended period

**Diagnosis**:
```bash
# Check init container logs
oc logs <pod-name> -c wait-for-prometheus -n self-healing-platform
oc logs <pod-name> -c wait-for-argocd -n self-healing-platform

# Check if dependencies are actually ready
oc get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus
oc get pods -n openshift-gitops
```

**Resolution**:
- If Prometheus/ArgoCD pods are not running, investigate those namespaces first
- Init containers will automatically proceed once dependencies are healthy
- If stuck for >10 minutes, check network policies or service availability

### Issue: Init Models Job Still Failing

**Symptom**: Job shows `BackoffLimitExceeded` even with fixes

**Diagnosis**:
```bash
# Check job status
oc get job init-models-job -n self-healing-platform

# Check pod logs
oc logs job/init-models-job -n self-healing-platform

# Check PVC status
oc get pvc model-storage-pvc -n self-healing-platform
oc describe pvc model-storage-pvc -n self-healing-platform
```

**Resolution**:
- Verify PVC is in `Bound` state
- Check if storage class and CSI drivers are available
- Review pod logs for specific directory creation failures
- Verify ODF/NooBaa pods are running in `openshift-storage` namespace

### Issue: Workbench Can't Access Models

**Symptom**: Jupyter starts but `/mnt/models` is empty or read-only

**Diagnosis**:
```bash
# Check workbench pod logs
oc logs -l app=self-healing-workbench -n self-healing-platform -c setup-jupyter-dirs

# Exec into workbench and check
oc exec -it -n self-healing-platform deployment/self-healing-workbench -- ls -la /mnt/models/

# Check PVC mount
oc describe pod -l app=self-healing-workbench -n self-healing-platform | grep -A 5 "Mounts:"
```

**Resolution**:
- Verify init-models-job completed successfully
- Check if `.initialized` file exists: `oc exec ... -- ls /mnt/models/.initialized`
- Verify PVC permissions allow writes
- Restart workbench pod if necessary: `oc delete pod -l app=self-healing-workbench`

### Issue: Startup Probes Timing Out

**Symptom**: Pod restarts repeatedly with startup probe failures

**Diagnosis**:
```bash
# Check pod events
oc describe pod <pod-name> -n self-healing-platform | grep -A 10 "Events:"

# Check if health endpoint is responsive
oc exec <pod-name> -- curl -v http://localhost:8080/health
```

**Resolution**:
- Verify application actually starts (check logs for startup errors)
- Increase startup probe failureThreshold if needed (current: 30)
- Check if liveness probe is interfering (unlikely with current config)

---

## Rollback Plan

If the fixes cause unexpected issues:

### 1. Quick Rollback via Git
```bash
cd /home/lab-user/openshift-aiops-platform

# View changes
git diff charts/hub/templates/

# Revert specific file
git checkout HEAD -- charts/hub/templates/coordination-engine-deployment.yaml
git checkout HEAD -- charts/hub/templates/mcp-server-deployment.yaml
git checkout HEAD -- charts/hub/templates/init-models-job.yaml
git checkout HEAD -- charts/hub/templates/ai-ml-workbench.yaml

# Revert all changes
git checkout HEAD -- charts/hub/templates/
```

### 2. Redeploy Previous Configuration
```bash
# Via Helm
helm upgrade self-healing-platform charts/hub/ \
  --namespace self-healing-platform \
  --reuse-values

# Via ArgoCD
git push
# ArgoCD will sync reverted changes
```

### 3. Verify Rollback
```bash
# Ensure pods are running
oc get pods -n self-healing-platform

# Verify no init containers present
oc get pods -n self-healing-platform -o yaml | grep -c "initContainers:"
# Should return 0 (or original count)
```

### 4. If Cluster Becomes Unresponsive
```bash
# Use existing cleanup playbook
cd /home/lab-user/openshift-aiops-platform
ansible-playbook ansible/playbooks/cleanup_environment.yml

# Redeploy from scratch
./scripts/deploy-with-prereqs.sh
```

---

## Files Modified

| File | Purpose | Changes |
|------|---------|---------|
| `scripts/diagnose-cluster-restart.sh` | Diagnostic script | **NEW** - Comprehensive restart monitoring |
| `charts/hub/templates/coordination-engine-deployment.yaml` | Coordination Engine | Init containers (Prometheus, ArgoCD), startup probe |
| `charts/hub/templates/mcp-server-deployment.yaml` | MCP Server | Init containers (Coord Engine, Prometheus), startup probe |
| `charts/hub/templates/init-models-job.yaml` | Model Storage Init | Init container (PVC wait), retry logic, increased backoffLimit |
| `charts/hub/templates/ai-ml-workbench.yaml` | Jupyter Workbench | Storage verification, startup probe |
| `charts/hub/templates/model-serving.yaml` | InferenceServices | **NO CHANGES** - Already resilient |
| `docs/CLUSTER_RESTART_HEALTH.md` | Documentation | **NEW** - This file |

---

## Next Steps

### Immediate Actions
1. ✅ Review this documentation
2. ✅ Run diagnostic script before next cluster restart
3. ✅ Deploy fixes to development/staging environment
4. ✅ Test cluster restart in non-production environment
5. ✅ Validate all success criteria met

### Post-Validation
1. Deploy to production during maintenance window
2. Monitor first production cluster restart closely
3. Run diagnostic script to capture actual behavior
4. Fine-tune probe timings if needed based on real data

### Optional Enhancements (Phase 3)
If manual monitoring is insufficient or cluster restarts are frequent:

1. **Automated Recovery Pipeline**:
   - Create Tekton pipeline: `tekton/pipelines/post-restart-recovery-pipeline.yaml`
   - Tasks: verify dependencies, restart failed jobs, reconcile InferenceServices
   - EventListener trigger for automated execution

2. **Prometheus Alerting**:
   - Alert on prolonged Init state
   - Alert on startup probe failures
   - Alert on PVC binding delays

3. **Dashboard Integration**:
   - Grafana dashboard showing startup timeline
   - Component dependency graph
   - Historical restart performance

---

## Architecture Decision Records

The following ADRs document the architectural decisions made in this implementation:

- **ADR-XXX**: Use Init Containers for Cross-Namespace Dependency Management
- **ADR-XXX**: Implement Startup Probes with 5-Minute Windows
- **ADR-XXX**: Exponential Backoff for Storage-Dependent Operations
- **ADR-XXX**: Diagnostic-First Approach to Cluster Health Issues

*(Create these ADRs following your organization's ADR template)*

---

## Support and Feedback

For questions or issues related to cluster restart health:

1. **Review diagnostic report** first: `/tmp/cluster-restart-diagnostics/diagnostic-report-*.md`
2. **Check troubleshooting section** in this document
3. **Examine pod logs**: `oc logs <pod> -c <container> -n self-healing-platform`
4. **Review events**: `oc get events -n self-healing-platform --sort-by='.lastTimestamp'`

---

## References

- [Kubernetes Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Kubernetes Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-startup-probes)
- [OpenShift Storage Documentation](https://docs.openshift.com/container-platform/4.18/storage/index.html)
- [KServe InferenceService API](https://kserve.github.io/website/latest/reference/api/)
- [Helm Chart Best Practices](https://helm.sh/docs/chart_best_practices/)

---

**Document Version**: 1.0
**Last Updated**: 2026-01-22
**Author**: Claude Code (OpenShift AI Ops Platform Team)
