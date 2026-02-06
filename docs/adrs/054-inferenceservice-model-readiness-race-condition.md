# ADR-054: InferenceService Model Readiness Race Condition Fix

## Status
**ACCEPTED** - 2026-02-06

## Context

### Problem Statement

InferenceService predictor pods deploy at ArgoCD sync-wave `"2"`, but the NotebookValidationJobs that train and write `model.pkl` files to the shared PVC run at wave `"3"`. The KServe sklearn server loads models only at startup and does not retry, so predictors run with **no loaded models** and return `ModelMissingError` on every inference request.

**Critical Issue**: InferenceServices falsely report `Ready: True` and `activeModelState: Loaded` in their status, even when models are missing. This creates a silent failure that students won't discover until Module 2/3 when Lightspeed tries to use the models.

### Observed Behavior

| Event                                                                               | Timestamp    |
| ----------------------------------------------------------------------------------- | ------------ |
| Predictor pods started (wave 2)                                                     | 14:05:07 UTC |
| Predictor failed to find model file                                                 | 14:05:23 UTC |
| isolation-forest-implementation-validation wrote anomaly-detector/model.pkl (1.5MB) | 14:06:57 UTC |
| predictive-scaling-validation wrote predictive-analytics/model.pkl (4.0MB)          | 14:09:00 UTC |

**Error on inference requests**:
```json
{"error":"Model with name anomaly-detector does not exist."}
```

The `model.pkl` files exist on the PVC — the predictor pods simply never reloaded after they were written.

### Root Cause

ADR-053 separated model training from ArgoCD sync waves (moved to Tekton Pipelines), and in doing so removed the `inferenceServiceTrigger` and `blockNextWave` annotations from wave 3 notebooks. The Tekton CronJobs handle steady-state retraining (weekly), but there is **no automatic initial training trigger** on first deployment. The wave 3 notebooks still train models as part of validation, but the predictors at wave 2 never reload after the models appear.

**Architecture Flow**:
```
Wave 2: InferenceServices deploy → Predictors start → Look for model.pkl → Not found → ModelMissingError (no retry)
Wave 3: NotebookValidationJobs run → Train models → Write model.pkl to PVC
Result: Predictors never reload, inference fails silently
```

### Related ADRs

- **ADR-053**: Tekton Pipelines for Model Training (Replaces ArgoCD Sync Wave Approach)
  - Established the separation of deployment (ArgoCD) from training (Tekton)
  - Removed `inferenceServiceTrigger` annotations from notebooks
  - Created the architectural gap that led to this race condition

- **ADR-043**: Deployment Stability and Cross-Namespace Health Check Patterns
  - Established init container patterns for waiting on dependencies
  - However, init containers would deadlock ArgoCD sync in this case

### Issue Reference

- **GitHub Issue**: [#34](https://github.com/KubeHeal/openshift-aiops-platform/issues/34)
- **Workshop Impact**: Module 0 tells students to verify that predictor pods are Running and InferenceServices are Ready. Both checks pass — but inference silently fails. Students won't discover the issue until Module 2/3 when Lightspeed tries to use the models.

## Decision

**Add a Kubernetes Job at sync-wave `"5"` that waits for model artifacts to exist on the PVC and then restarts predictor deployments.**

### Chosen Solution: Post-Deploy Restart Job

**File**: `charts/hub/templates/restart-predictors-job.yaml`

A Kubernetes Job that:
1. Waits for `model.pkl` to exist at `/mnt/models/{model-name}/model.pkl` for each model (polling with timeout)
2. Restarts the predictor deployment via `oc rollout restart deployment/{model-name}-predictor`
3. Validates pods reach Running state after restart
4. Uses `argocd.argoproj.io/hook: PostSync` so it runs after the main sync completes

**Sync Wave Strategy**:
- Wave 2: InferenceServices deploy (predictors start, models missing)
- Wave 3: NotebookValidationJobs train models (write model.pkl to PVC)
- Wave 5: **Restart job waits for models, restarts predictors**

### Why This Approach?

**Advantages**:
- ✅ **Least invasive**: Doesn't change existing sync-wave architecture
- ✅ **Aligns with ADR-053**: InferenceServices deploy early, models come later via Tekton/notebooks
- ✅ **Non-blocking**: Doesn't prevent ArgoCD sync from completing
- ✅ **Automatic**: No manual intervention required
- ✅ **Works with existing patterns**: Uses same PVC mount pattern as init-models-job

**Disadvantages**:
- ⚠️ **Temporary gap**: Predictors are "Ready" but non-functional until restart completes
- ⚠️ **Additional resource**: One-time Job consumes cluster resources during deployment

### Alternatives Considered

#### Option 1: Init Container in Predictor Deployment

**Approach**: Add an init container to each InferenceService predictor that waits for `model.pkl` before starting the kserve container.

**Rejected Because**:
- ❌ **Deadlocks ArgoCD sync**: Wave 2 InferenceServices would never become Healthy (blocked by init container waiting for models), preventing wave 3 notebooks from starting
- ❌ **Breaks ADR-053 intent**: InferenceServices should deploy early, models come later
- ❌ **Complex**: Requires modifying KServe-managed deployments

#### Option 2: Increase Sync-Wave on InferenceServices

**Approach**: Move InferenceServices to sync-wave `"5"` or later (after notebooks complete).

**Rejected Because**:
- ❌ **Changes deployment architecture**: Would require moving InferenceServices to wave 5+, changing the architecture established by ADR-053
- ❌ **Delays all model serving**: Other components that depend on InferenceServices would also be delayed
- ❌ **Doesn't solve steady-state**: Tekton CronJobs still need restart mechanism

#### Option 3: Post-Deploy Restart Job (CHOSEN)

**Approach**: Kubernetes Job at sync-wave 5 that waits for models and restarts predictors.

**Chosen Because**:
- ✅ **Minimal changes**: Only adds one new Job template
- ✅ **Preserves architecture**: Doesn't change existing sync-wave assignments
- ✅ **Works with Tekton**: Can be reused for Tekton-triggered retraining
- ✅ **Clear separation**: Deployment (ArgoCD) vs. operational fix (Job)

#### Option 4: Document Only

**Approach**: Document the manual restart step in Module 0 as a known post-deployment action.

**Rejected Because**:
- ❌ **Poor UX**: Students hit the issue silently in later modules
- ❌ **Doesn't fix the problem**: Just documents a workaround
- ❌ **Workshop friction**: Adds manual steps that break the automated flow

## Consequences

### Positive

1. **Automatic Fix**: No manual intervention required after deployment
2. **Early Detection**: Post-deployment validation script (Check 7) now tests inference endpoints, catching the issue in Module 0
3. **Works with Tekton**: The restart job pattern can be reused for Tekton-triggered retraining
4. **Preserves Architecture**: Doesn't change ADR-053's separation of concerns
5. **Clear Failure Mode**: If restart job fails, it's visible in ArgoCD UI and logs

### Negative

1. **Temporary Gap**: There's a window (wave 2 → wave 5) where predictors are "Ready" but non-functional
2. **Resource Overhead**: One-time Job consumes cluster resources during deployment
3. **Additional Complexity**: One more Helm template to maintain
4. **Not Perfect**: Still requires a restart job rather than native KServe retry mechanism

### Neutral

1. **Workshop Impact**: Students will see the restart job in ArgoCD UI, providing visibility into the fix
2. **Future Improvement**: Could be replaced by KServe-native model reload mechanism if one is added
3. **Pattern Reusability**: The restart job pattern can be applied to other model-serving scenarios

## Implementation

### Files Changed

1. **`charts/hub/templates/restart-predictors-job.yaml`** (NEW)
   - Kubernetes Job at sync-wave 5
   - Waits for model.pkl files, restarts predictor deployments
   - Uses PostSync hook for post-deployment execution

2. **`scripts/post-deployment-validation.sh`** (MODIFIED)
   - Added Check 7: InferenceService Model Health Check
   - Tests inference endpoints, verifies predictions (not ModelMissingError)
   - Catches the issue early in Module 0

3. **`docs/adrs/054-inferenceservice-model-readiness-race-condition.md`** (NEW)
   - This ADR documenting the fix

### Deployment Flow

```
Wave -5: init-models-job (creates directory structure)
Wave 2:   InferenceServices deploy (predictors start, models missing)
Wave 3:   NotebookValidationJobs train models (write model.pkl)
Wave 5:   restart-predictors-job (waits for models, restarts predictors)
PostSync: Validation script tests inference endpoints
```

### Testing

**Manual Test**:
```bash
# Deploy platform
make -f common/Makefile operator-deploy

# Wait for sync to complete
make -f common/Makefile argo-healthcheck

# Verify restart job completed
oc get job restart-predictors-after-models-ready -n self-healing-platform

# Test inference endpoint
oc get pods -n self-healing-platform -l serving.kserve.io/inferenceservice=anomaly-detector
POD_IP=$(oc get pod -n self-healing-platform -l serving.kserve.io/inferenceservice=anomaly-detector -o jsonpath='{.items[0].status.podIP}')
curl -X POST "http://${POD_IP}:8080/v1/models/anomaly-detector:predict" \
  -H "Content-Type: application/json" \
  -d '{"instances": [[0.1, 0.2, 0.3, ...]]}'
# Should return predictions, not ModelMissingError
```

**Automated Test**:
```bash
# Run post-deployment validation script
./scripts/post-deployment-validation.sh
# Check 7 should pass (InferenceService Model Health Check)
```

## References

- **GitHub Issue**: [#34](https://github.com/KubeHeal/openshift-aiops-platform/issues/34) - Race condition: InferenceService predictor pods start before NotebookValidationJobs train models
- **ADR-053**: Tekton Pipelines for Model Training (Replaces ArgoCD Sync Wave Approach)
- **ADR-043**: Deployment Stability and Cross-Namespace Health Check Patterns
- **KServe Documentation**: [Model Loading Behavior](https://kserve.github.io/website/modelserving/inference_service/model_loading/)

## Notes

- This fix addresses the **initial deployment** race condition. For **steady-state retraining** (Tekton CronJobs), the Tekton pipeline's `restart-inference-service` task handles predictor restarts after training completes.
- Future improvement: If KServe adds native model reload/retry mechanism, this restart job could be deprecated.
- The restart job uses `argocd.argoproj.io/hook-delete-policy: HookSucceeded` to clean up after successful completion.
