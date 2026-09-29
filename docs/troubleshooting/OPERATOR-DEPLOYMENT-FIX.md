# Pattern Operator Deployment Fix

## Issue

When deploying the `openshift-aiops-platform` pattern using the Validated Patterns Operator, the operator pod repeatedly crashes with Exit Code 137 (SIGKILL) during large repository clones.

### Symptoms
- Pattern operator pod shows multiple restarts (10+ restarts)
- Logs show successful git clone progress but pod terminates before completion
- Error message: `Liveness probe failed: context deadline exceeded`
- Pattern CR status stuck at "Updated status with start event sent"

### Root Cause
1. **Insufficient Memory**: The default 512Mi memory limit is too low for cloning large repositories (34,000+ objects)
2. **Aggressive Health Probes**: Default liveness probe timeout (15s initial delay, 1s timeout, 20s period) kills the pod during long git clone operations

## Solution

Patch the Pattern operator deployment to increase resources and extend health probe timeouts.

### Step 1: Apply Resource Patch

```bash
oc patch deployment patterns-operator-controller-manager \
  -n openshift-operators \
  --type='json' \
  -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value":"2Gi"},
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value":"256Mi"}
  ]'
```

### Step 2: Apply Health Probe Patch

```bash
oc patch deployment patterns-operator-controller-manager \
  -n openshift-operators \
  --type='json' \
  -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds", "value":60},
    {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/timeoutSeconds", "value":10},
    {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/periodSeconds", "value":60},
    {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds", "value":30},
    {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/timeoutSeconds", "value":10},
    {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/periodSeconds", "value":30}
  ]'
```

### Step 3: Verify Deployment

```bash
# Check pod is running without restarts
oc get pods -n openshift-operators | grep pattern

# Expected output: 0 restarts, Running status
# patterns-operator-controller-manager-XXXXX   1/1     Running   0          5m

# Check Pattern operator logs for successful clone
oc logs -n openshift-operators deployment/patterns-operator-controller-manager --tail=50

# Expected output: "Reconcile step 'create application' complete" and "Pattern completed"
```

### Step 4: Verify Pattern Deployment

```bash
# Check Pattern CR status
oc get pattern -n openshift-operators

# Check ArgoCD application
oc get applications.argoproj.io -n openshift-gitops

# Expected output:
# NAME                        SYNC STATUS   HEALTH STATUS
# self-healing-platform-hub   Synced        Healthy
```

## Permanent Fix

To make this fix permanent for new deployments, apply the patch configuration:

```bash
oc patch deployment patterns-operator-controller-manager \
  -n openshift-operators \
  --patch-file k8s/operator-patches/patterns-operator-resources.yaml
```

## Alternative: Apply During Operator Installation

If installing the operator for the first time, modify the operator subscription or deployment YAML to include these resource limits before deployment.

## Testing

Tested on:
- **OpenShift Version**: 4.18.21
- **Pattern Size**: 34,117 git objects, 19,583 compressed
- **Pattern Operator Version**: v0.0.63
- **Date**: 2025-12-04

## References

- **Related Issue**: Large repository clones timeout during Validated Patterns deployment
- **Pattern Repository**: https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/opentlc-mgr/openshift-aiops-platform.git
- **Deployment Plan**: docs/IMPLEMENTATION-PLAN.md

## Impact

After applying this fix:
- ✅ Pattern operator pod stable (0 restarts)
- ✅ Large repository clones complete successfully
- ✅ Pattern CR completes reconciliation
- ✅ ArgoCD application created and synced
- ✅ Deployment proceeds normally

## Notes

- This fix is specific to large patterns (30,000+ git objects)
- Smaller patterns may not require these increased limits
- Consider the tradeoff between resource usage and deployment reliability
- Monitor memory usage to adjust limits as needed
