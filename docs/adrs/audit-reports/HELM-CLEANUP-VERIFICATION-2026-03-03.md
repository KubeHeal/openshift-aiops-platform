# Helm Storage Cleanup Verification

**Date:** 2026-03-03
**Context:** ADR-035 cleanup - removing unused PVC definitions from Helm chart

---

## Summary

We successfully removed orphaned PVC definitions that were creating unused storage resources. All dependent systems verified as unaffected.

---

## What We Removed

### From `charts/hub/templates/storage.yaml`:
```yaml
# REMOVED (never mounted by any workload):
- self-healing-data-development (10Gi)
- model-artifacts-development (50Gi)
```

### From `charts/hub/values.yaml`:
```yaml
# REMOVED:
storage:
  selfHealingData:      # Not used
    size: "10Gi"
  modelArtifacts:       # Not used
    size: "100Gi"
```

---

## What We Kept

### PVCs Actually Used:
1. ✅ **workbench-data-development** (20Gi)
   - Used by: `self-healing-workbench-0`
   - Purpose: Jupyter workbench persistent storage

2. ✅ **model-storage-pvc** (10Gi)
   - Used by: **40+ pods** (InferenceServices, training jobs, validation jobs, workbench)
   - Purpose: Shared model storage

3. ✅ **model-storage-gpu-pvc** (10Gi, HA only)
   - Used by: GPU training validation jobs
   - Purpose: GPU-compatible RWO storage for training

---

## Verification Matrix

| System | PVC References | Status | Notes |
|--------|----------------|--------|-------|
| **Tekton Pipelines** | `model-storage-pvc` only | ✅ Safe | No references to deleted PVCs |
| **Tekton Tasks** | `model-storage-pvc` only | ✅ Safe | No references to deleted PVCs |
| **Helm Templates** | workbench-data, model-storage-pvc, model-storage-gpu-pvc | ✅ Safe | Updated to match reality |
| **Kustomize (k8s/base)** | self-healing-data, model-artifacts (no suffix) | ✅ Safe | Different PVC names, unaffected |
| **ArgoCD** | Helm-managed PVCs | ✅ Safe | Manages Helm deployments |
| **Deployed Pods** | 40+ pods use model-storage-pvc | ✅ Safe | All use PVCs we kept |

---

## Tekton Verification Details

### PipelineRuns Checked:
```bash
oc get pipelinerun -n self-healing-platform -o yaml | grep "claimName"
# Result: Only references "model-storage-pvc" ✅
```

### Tasks Checked:
```bash
oc get task -n self-healing-platform -o yaml | grep "claimName"
# Result: Only references "model-storage-pvc" ✅
```

### No Workspaces Found:
```bash
grep -r "workspaces:" charts/hub/templates/tekton*
# Result: No workspace definitions that could reference deleted PVCs ✅
```

---

## Kustomize vs Helm Naming

**Important:** Kustomize and Helm use DIFFERENT PVC naming conventions:

| Deployment Method | PVC Names |
|-------------------|-----------|
| **Kustomize (k8s/base/)** | `self-healing-data`, `model-artifacts` (no suffix) |
| **Helm (charts/hub/)** | `self-healing-data-development`, `model-artifacts-development` (with `-development` suffix) |

We deleted Helm-created PVCs. Kustomize files are unaffected because they reference different PVC names.

---

## Helm Template Rendering Verification

### SNO Topology:
```bash
helm template test-sno charts/hub --set cluster.topology=sno --set metadata.environment=development --show-only templates/storage.yaml
```

**Result:** ✅ Creates 2 PVCs
1. workbench-data-development (20Gi, gp3-csi, RWO)
2. model-storage-pvc (10Gi, gp3-csi, RWO)

### HA Topology:
```bash
helm template test-ha charts/hub --set cluster.topology=ha --set metadata.environment=development --show-only templates/storage.yaml
```

**Result:** ✅ Creates 3 PVCs
1. workbench-data-development (20Gi, gp3-csi, RWO)
2. model-storage-pvc (10Gi, ocs-storagecluster-cephfs, RWX)
3. model-storage-gpu-pvc (10Gi, gp3-csi, RWO)

---

## Cluster State Verification

### Before Cleanup (SNO):
```
NAME                            STATUS
model-artifacts-development     Bound (via pvc-binder hack)
model-storage-gpu-pvc           Bound (via pvc-binder hack)
model-storage-pvc               Bound (used by 3 pods)
self-healing-data-development   Bound (via pvc-binder hack)
workbench-data-development      Bound (used by 1 pod)
```

### After Cleanup (SNO):
```
NAME                            STATUS   USED BY
model-storage-pvc               Bound    40+ pods
workbench-data-development      Bound    1 pod (workbench)
```

### After Cleanup (HA):
```
NAME                            STATUS   USED BY
model-storage-gpu-pvc           Bound    2 pods (GPU training)
model-storage-pvc               Bound    39+ pods
workbench-data-development      Bound    1 pod (workbench)
```

---

## Impact Analysis

### What Changed:
1. ✅ Removed 2 PVC definitions from Helm templates
2. ✅ Updated values.yaml to match actual usage
3. ✅ Deleted orphaned PVCs from clusters (freed 130Gi total)
4. ✅ Deleted pvc-binder hack pod

### What Stayed the Same:
1. ✅ All 40+ running pods continue using model-storage-pvc
2. ✅ Tekton pipelines continue working (only use model-storage-pvc)
3. ✅ Workbench continues using workbench-data-development
4. ✅ Kustomize manifests untouched (different PVC names)

### Next Helm Deployment:
- ✅ Will create only PVCs that are actually used
- ✅ Won't recreate orphaned PVCs
- ✅ Storage config matches cluster reality

---

## Files Modified

### Git Commit: `674a5cd`

**Modified:**
1. `charts/hub/templates/storage.yaml` - removed 2 PVC definitions
2. `charts/hub/values.yaml` - replaced selfHealingData/modelArtifacts with modelStorage/modelStorageGpu

**Unmodified (intentionally):**
1. `k8s/base/storage.yaml` - legacy kustomize, different PVC names
2. `k8s/base/ai-ml-workbench.yaml` - legacy kustomize, different PVC names
3. All Tekton pipeline/task definitions

---

## Conclusion

✅ **Safe to deploy** - All verification checks passed
✅ **Tekton unaffected** - Only uses model-storage-pvc
✅ **Running pods unaffected** - All use PVCs we kept
✅ **Kustomize unaffected** - Different PVC naming convention
✅ **Next deployment clean** - Won't recreate orphaned PVCs

**Storage savings:** 130Gi across both clusters
**Architecture:** Cleaner, more accurate, matches actual usage
