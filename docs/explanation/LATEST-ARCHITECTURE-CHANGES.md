# Latest Architecture Changes - Post git pull (2026-03-03)

## Summary of Changes

**Commit Range:** 84c00d7..242de03
**Files Changed:** 12 files (+633 insertions, -216 deletions)

### 🚀 Major Architectural Improvement: Consolidated Model Training Workflow

The latest changes represent a significant architectural improvement to the model training and deployment workflow, moving from a **job-based copy approach** to a **Tekton pipeline-driven approach**.

---

## Key Changes

### 1. ❌ Removed: `gpu-model-copy-job.yaml` (168 lines deleted)

**Previous Approach:**
- Separate Job running at sync-wave 10
- Copied trained models from GPU PVC (gp3-csi, RWO) to CephFS PVC (RWX)
- Required for HA clusters where GPU nodes cannot mount CephFS
- Ran as standalone sync wave

**Why Deleted:**
- Functionality consolidated into `model-restart-job.yaml`
- Reduces job sprawl and improves maintainability
- Better error handling with optional GPU PVC access

---

### 2. ✅ Created: `initial-model-training-job.yaml` (141 lines added)

**New Approach:**
- Triggers Tekton training pipelines automatically on first deployment
- Runs at sync-wave 5 as PostSync hook
- Creates PipelineRun CRs for both models:
  - `anomaly-detector` → `model-training-pipeline` (CPU, 30 min timeout)
  - `predictive-analytics` → `model-training-pipeline-gpu` (GPU, 45 min timeout)
- Idempotent: Skips if PipelineRuns already exist
- Completes in seconds (just creates CRs, training runs asynchronously)

**Benefits:**
1. **Automatic Training on Deploy**: No manual pipeline trigger needed
2. **Consistent Behavior**: Same training workflow whether SNO or HA
3. **Better UX**: Users see trained models immediately after deployment
4. **GitOps-Friendly**: Declarative pipeline triggers via ArgoCD

**Key Logic:**
```yaml
# Check if training already ran
EXISTING=$(oc get pipelinerun -n {{ .Values.main.namespace }} --no-headers 2>/dev/null | wc -l)
if [ "$EXISTING" -gt 0 ]; then
  echo "PipelineRuns already exist ($EXISTING found) -- skipping initial trigger"
  exit 0
fi

# Trigger both pipelines
oc create -f - <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: train-anomaly-detector-
...
EOF
```

---

### 3. 📝 Modified: `model-restart-job.yaml` (consolidated functionality)

**New Responsibilities:**
- **Previous:** Wait for models, restart predictor pods (ADR-054 race condition fix)
- **Added:** GPU→CephFS model copy logic (from deleted gpu-model-copy-job.yaml)

**New Function: `copy_model_from_gpu()`** (lines 108-176):
- Checks if GPU PVC is mounted (best-effort, may not be available if RWO held by training pod)
- Compares GPU model timestamp and size with final PVC model
- Copies if GPU model is newer
- Gracefully handles GPU PVC unavailable (relies on Tekton pipeline to handle copy)
- Returns non-zero only if model is required from GPU but not found

**Topology-Aware Behavior:**
```bash
{{- if ne ((.Values.cluster).topology | default "ha") "sno" }}
- name: model-storage-gpu
  persistentVolumeClaim:
    claimName: model-storage-gpu-pvc
{{- end }}
```

**Benefits:**
1. **Consolidated Jobs**: One job handles wait + copy + restart (was 3 jobs)
2. **Better Error Handling**: GPU PVC mount failure is not fatal
3. **Simpler Workflow**: Fewer sync waves, clearer dependency graph
4. **Cost-Effective**: Runs only when needed (models changed)

---

### 4. ✅ Added: `charts/hub/values.yaml` (417 lines)

**Comprehensive Default Values File:**
- Previously only had `values-hub.yaml` (cluster-specific overrides)
- Now has full `values.yaml` with sensible defaults
- Extensive inline documentation explaining topology-aware settings
- Makes Helm chart more portable and self-documenting

**Key Sections:**
```yaml
# Cluster topology configuration
cluster:
  topology: "ha"  # or "sno"
  version: "4.20"

# Storage configuration (topology-aware)
storage:
  modelArtifacts:
    size: "100Gi"
    storageClass: "ocs-storagecluster-cephfs"  # HA default
    # SNO: override to "gp3-csi" in values-hub.yaml

# RBAC (ADR-030: Hybrid Management Model)
rbac:
  clusterScoped:
    enabled: false  # Managed by Ansible prereqs
  crossNamespaceEnabled: false  # Managed by Ansible prereqs

clusterRbacManagedExternally: true
```

**Benefits:**
1. **Self-Documenting**: Comments explain WHY settings exist
2. **Portable**: Can deploy without values-hub.yaml (uses defaults)
3. **Consistent**: Single source of truth for default values
4. **ADR-Aligned**: Comments reference ADR-030, ADR-054, ADR-055-057

---

### 5. 📝 Modified: Other Template Files

**Updated Files:**
- `ai-ml-workbench.yaml` - Minor adjustments
- `imagestreams-buildconfigs.yaml` - Image tag fixes
- `notebook-validation-jobs.yaml` - Topology conditionals refined
- `notebook-validator-tekton.yaml` - Pipeline references updated
- `restart-predictors-job.yaml` - Aligned with model-restart changes
- `tekton-model-training-cronjobs.yaml` - CronJob schedules updated
- `tekton-model-training-pipeline.yaml` - Pipeline parameters refined

**README.md Updated:**
- Added step 17: Check model training pipeline status
- Explains automatic training trigger on deployment
- Provides manual pipeline trigger commands for troubleshooting

---

## Architecture Comparison: Before vs After

### Before (84c00d7):

```
Deploy → (wave 2) InferenceServices
      → (wave 3-10) Notebooks train models → write to GPU PVC (if HA)
      → (wave 10) gpu-model-copy-job → copy GPU PVC → CephFS PVC
      → (wave 11) model-restart-job → wait for models → restart predictors
```

**Issues:**
- 3 separate jobs (training notebooks, copy, restart)
- GPU copy job always runs even if models unchanged
- Tight coupling between waves
- Harder to debug failures

### After (242de03):

```
Deploy → (wave 5, PostSync) initial-model-training-job → trigger Tekton pipelines
      → Tekton pipelines train models asynchronously
      → (wave 11) model-restart-job → optional GPU copy + restart
```

**Improvements:**
1. **Async Training**: Tekton pipelines run independently of ArgoCD sync
2. **Idempotent**: initial-model-training-job skips if pipelines already exist
3. **Consolidated**: model-restart-job handles copy + restart (was 2 jobs)
4. **Flexible**: GPU copy is best-effort (Tekton handles if restart job can't)
5. **Faster Syncs**: ArgoCD doesn't wait for training to complete

---

## ADR Validation Impact

### ADR-057: Topology-Aware GPU Scheduling and Storage

**Status:** ✅ Still fully implemented, architecture improved

**Changes:**
- GPU copy logic moved from dedicated job → consolidated into model-restart-job
- Storage.yaml unchanged (still creates model-storage-gpu-pvc for HA)
- Topology conditionals unchanged (SNO skips GPU PVC, HA creates both)

**New Validation Steps:**
1. ✅ Verify `initial-model-training-job` triggers pipelines on deployment
2. ✅ Verify `model-restart-job` includes GPU copy logic (HA only)
3. ✅ Verify GPU PVC copy is optional (not fatal if unavailable)
4. ❌ Remove validation for `gpu-model-copy-job` (deleted)

### ADR-054: InferenceService Model Readiness Race Condition

**Status:** ✅ Still addresses race condition, improved workflow

**Changes:**
- model-restart-job now runs at wave 11 (unchanged)
- Adds GPU copy capability (new)
- Still waits for models before restarting predictors

**Validation:**
- Same validation steps apply (wait for models, restart predictors)
- Additional check: GPU copy logs in model-restart-job

### ADR-019: Validated Patterns Framework Adoption

**Status:** ✅ Enhanced with better Helm chart structure

**Changes:**
- Added comprehensive values.yaml with defaults
- Improves portability and maintainability
- Follows Helm best practices

---

## Updated Validation Checklist

### SNO Deployment Validation

**What Changed:**
- ✅ No gpu-model-copy-job (was never created for SNO anyway)
- ✅ initial-model-training-job now triggers training automatically
- ✅ model-restart-job runs but skips GPU copy (GPU PVC not mounted)

**New Validation Steps:**
```bash
# 1. Verify initial-model-training-job triggered pipelines
oc get job initial-model-training -n self-healing-platform
oc logs job/initial-model-training -n self-healing-platform

# Expected: Job completed, shows "Both training pipelines triggered successfully"

# 2. Verify Tekton pipelines were created
tkn pipelinerun list -n self-healing-platform

# Expected:
# - train-anomaly-detector-xxxxx (Running or Succeeded)
# - train-predictive-analytics-xxxxx (Running or Succeeded)

# 3. Verify model-restart-job completed
oc get job model-restart-after-training -n self-healing-platform
oc logs job/model-restart-after-training -n self-healing-platform | grep -A5 "copy_model_from_gpu"

# Expected: "GPU PVC not mounted (RWO may still be held by training pod)" or
#           "GPU PVC not mounted but model $model_name requires GPU training" (non-fatal for SNO)

# 4. Verify predictors restarted successfully
oc get pods -n self-healing-platform -l serving.kserve.io/inferenceservice
```

### HA Deployment Validation

**What Changed:**
- ❌ gpu-model-copy-job DELETED (no longer created)
- ✅ initial-model-training-job now triggers training automatically
- ✅ model-restart-job now includes GPU copy logic

**New Validation Steps:**
```bash
# 1. Verify initial-model-training-job triggered pipelines
oc get job initial-model-training -n self-healing-platform
oc logs job/initial-model-training -n self-healing-platform

# Expected: Job completed, shows "Both training pipelines triggered successfully"

# 2. Verify Tekton pipelines running
tkn pipelinerun list -n self-healing-platform

# Expected:
# - train-anomaly-detector-xxxxx (Running or Succeeded)
# - train-predictive-analytics-xxxxx (Running or Succeeded, GPU training)

# 3. Verify both PVCs created (model-storage-pvc + model-storage-gpu-pvc)
oc get pvc -n self-healing-platform | grep model-storage

# Expected:
# - model-storage-pvc (CephFS, RWX)
# - model-storage-gpu-pvc (gp3-csi, RWO)

# 4. Verify model-restart-job includes GPU copy
oc logs job/model-restart-after-training -n self-healing-platform | grep -A10 "copy_model_from_gpu"

# Expected: Shows copy attempts from /mnt/models-gpu to /mnt/models
# Possible outcomes:
# - "Model copied successfully! (size: XXXXX bytes)" → GPU copy worked
# - "GPU PVC not mounted (RWO may still be held by training pod)" → Tekton handles copy
# - "Final PVC model is up-to-date" → No copy needed

# 5. Verify no gpu-model-copy-job exists (deleted in this version)
oc get jobs -n self-healing-platform | grep gpu-model-copy

# Expected: No output (job was deleted)
```

---

## Deployment Testing Strategy

### Phase 1: Fresh SNO Deployment

```bash
# Prerequisites: Blank SNO cluster with token ready

# 1. Clone latest code
cd /home/vpcuser/openshift-aiops-platform
git pull  # Already done

# 2. Authenticate to SNO cluster
oc login --server=<sno-api-url> --token=<sno-token>

# 3. Verify topology detection
make show-cluster-info
# Expected: CLUSTER_TOPOLOGY=sno

# 4. Deploy
make deploy-with-prereqs

# 5. Watch initial-model-training-job
oc logs -f job/initial-model-training -n self-healing-platform

# 6. Monitor Tekton pipelines
watch tkn pipelinerun list -n self-healing-platform

# 7. Validate deployment
./scripts/post-deployment-validation.sh

# 8. Test model endpoints
./scripts/test-model-endpoint.sh anomaly-detector self-healing-platform
./scripts/test-model-endpoint.sh predictive-analytics self-healing-platform
```

### Phase 2: Fresh HA Deployment

```bash
# Prerequisites: Blank HA cluster with token ready

# 1. Authenticate to HA cluster
oc login --server=<ha-api-url> --token=<ha-token>

# 2. Verify topology detection
make show-cluster-info
# Expected: CLUSTER_TOPOLOGY=ha

# 3. Deploy
make deploy-with-prereqs

# 4. Watch initial-model-training-job
oc logs -f job/initial-model-training -n self-healing-platform

# 5. Monitor Tekton pipelines (watch for GPU pipeline)
watch tkn pipelinerun list -n self-healing-platform
# Look for model-training-pipeline-gpu (predictive analytics)

# 6. Validate GPU copy in model-restart-job
oc logs job/model-restart-after-training -n self-healing-platform | grep "copy_model_from_gpu" -A20

# 7. Validate deployment
./scripts/post-deployment-validation.sh

# 8. Test model endpoints
./scripts/test-model-endpoint.sh anomaly-detector self-healing-platform
./scripts/test-model-endpoint.sh predictive-analytics self-healing-platform
```

---

## Breaking Changes

### None for End Users

The architecture changes are **backward compatible** from a deployment perspective:
- Same Makefile targets (`make deploy-with-prereqs`)
- Same validation scripts
- Same InferenceService endpoints
- Model training still happens automatically

### Internal Changes Only

Changes affect **implementation details**:
- Job names changed (gpu-model-copy-job deleted)
- Sync wave ordering improved
- Tekton pipelines triggered earlier in deployment

---

## Benefits of New Architecture

1. **Simpler**: Fewer jobs (3 → 2), clearer responsibilities
2. **Faster**: ArgoCD sync doesn't wait for training (async pipelines)
3. **More Reliable**: Better error handling, idempotent pipeline triggers
4. **More Maintainable**: Consolidated logic, better documentation
5. **More Portable**: Comprehensive values.yaml with defaults
6. **Better UX**: Training starts automatically on deployment

---

## Recommendations for Validation

### Focus Areas

1. **Initial Model Training Job**:
   - Verify it triggers both pipelines on first deploy
   - Verify it's idempotent (skips if pipelines exist)
   - Check logs for clear success/skip messages

2. **Model Restart Job**:
   - Verify GPU copy logic works on HA (when GPU PVC available)
   - Verify it gracefully handles GPU PVC unavailable
   - Verify predictor restarts happen regardless of copy success

3. **Tekton Pipeline Monitoring**:
   - Watch pipeline progress (`tkn pipelinerun list`)
   - Verify models written to correct PVCs
   - Verify InferenceServices pick up trained models

4. **ADR Compliance**:
   - ADR-054: Race condition still fixed
   - ADR-057: Topology-aware storage still works
   - ADR-019: Validated Patterns framework still used

### Expected Outcomes

**SNO:**
- ✅ initial-model-training-job succeeds
- ✅ 2 PipelineRuns created and complete
- ✅ model-restart-job succeeds (no GPU copy attempted)
- ✅ Predictors restart and serve models
- ✅ Health score: 100% (8/8 checks)

**HA:**
- ✅ initial-model-training-job succeeds
- ✅ 2 PipelineRuns created and complete (one uses GPU)
- ✅ model-restart-job succeeds (GPU copy attempted, may succeed or rely on pipeline)
- ✅ Predictors restart and serve models
- ✅ Health score: 100% (8/8 checks)

---

## Next Steps

1. **Review this document** with stakeholders
2. **Test on SNO cluster** with provided token
3. **Test on HA cluster** with provided token
4. **Document any issues** discovered during testing
5. **Update ADR-054 and ADR-057** to reflect architecture changes
6. **Create release notes** highlighting improvements

---

## Questions for Review

1. Should we create a new ADR for the Tekton-pipeline-triggered training approach?
2. Should we update ADR-054 to include the GPU copy consolidation?
3. Are there any edge cases with GPU PVC unavailability we should handle?
4. Should we add metrics/monitoring for initial-model-training-job success rate?

---

## References

- **Commit:** 242de03
- **Pull Request:** (if applicable)
- **Related ADRs:** ADR-019, ADR-054, ADR-057
- **Related Issues:** (if applicable)
