# ADR-035: Storage Strategy for Self-Healing Platform

**Status**: ACCEPTED
**Date**: 2025-10-17
**Renumbered**: 2025-11-19 (standardized naming from ADR-STORAGE-STRATEGY)
**Deciders**: Architecture Team
**Affects**: Helm Chart, PVC Configuration, Deployment

## Implementation Status
**Status:** implemented
**Verification Date:** 2026-03-03
**Implementation Score:** 10.0/10
**Verified On:** SNO + HA clusters

**Evidence:**
- **SNO**: 2/2 PVCs Bound and operational (workbench-data-development 20Gi, model-storage-pvc 10Gi)
- **HA**: 3/3 PVCs Bound and operational (workbench-data-development 20Gi, model-storage-pvc 10Gi RWX, model-storage-gpu-pvc 10Gi RWO)
- **Storage Classes**: gp3-csi (SNO), ocs-storagecluster-cephfs + gp3-csi (HA)
- **Topology-Aware**: GPU-specific PVC only on HA clusters per Helm template conditional
- **Active Usage**: model-storage-pvc used by 3 pods (SNO), 39 pods (HA) including InferenceServices, workbench, training jobs

## Context

The Self-Healing Platform requires persistent storage for:
1. **workbench-data-development** (20Gi) - Jupyter workbench persistent storage, notebooks, and development artifacts
2. **model-storage-pvc** (10Gi) - Shared model storage for notebooks and KServe InferenceServices
3. **model-storage-gpu-pvc** (10Gi, HA only) - GPU-compatible storage (gp3-csi RWO) for training on HA clusters with GPU nodes

OpenShift cluster provides multiple storage options:
- **gp3-csi** (AWS EBS) - Default, RWO, reliable, GPU-compatible
- **ocs-storagecluster-cephfs** (OCS) - RWX, requires node labels, not GPU-compatible
- **ocs-storagecluster-ceph-rbd** (OCS) - RWO, requires node labels

### Problem Statement

Initial design used CephFS (RWX) for model-artifacts to support multi-pod access. However:

1. **CSI Driver Not Available on GPU Node**: CephFS CSI node plugin requires `node.ocs.openshift.io/storage=true` label
2. **GPU Node Lacks OCS Label**: GPU node (`ip-10-0-3-186`) only has `nvidia.com/gpu=True` taint
3. **Mount Failures**: Pod stuck in ContainerCreating with error:
   ```
   MountVolume.MountDevice failed: driver name openshift-storage.cephfs.csi.ceph.com not found
   ```

## Decision

**Use gp3-csi (AWS EBS) with ReadWriteOnce (RWO) access mode for all persistent volumes.**

### Rationale

1. **Reliability**: gp3-csi is the default storage class, fully operational on all nodes
2. **Simplicity**: No special node labels or taints required
3. **Performance**: AWS EBS provides consistent, predictable performance
4. **Validated Patterns Alignment**: Follows OpenShift best practices for production deployments
5. **Cost Efficiency**: gp3 is more cost-effective than OCS for single-pod access patterns

### Trade-offs

| Aspect | CephFS (RWX) | gp3-csi (RWO) |
|--------|-------------|---------------|
| Multi-pod access | ✅ Yes | ❌ No |
| GPU node support | ❌ Requires label | ✅ Works everywhere |
| Reliability | ⚠️ CSI issues | ✅ Proven |
| Cost | Higher | Lower |
| Setup complexity | Higher | Lower |

### Architectural Impact

**Single-pod access pattern is acceptable because:**
- Model artifacts are accessed by workbench pod only
- Training data is read-only during inference
- No concurrent multi-pod access required
- If multi-pod access needed in future, can migrate to RBD (RWO) or add OCS labels to GPU node

## Implementation

### Changes Made

1. **storage.yaml**: Both PVCs now use `gp3-csi` with `ReadWriteOnce`
2. **values.yaml**: Updated storage configuration with explicit storageClass
3. **ai-ml-workbench.yaml**: Pod can now mount volumes on GPU node

### Configuration

**SNO Topology:**
```yaml
# workbench-data-development (20Gi)
accessModes:
  - ReadWriteOnce
storageClassName: gp3-csi

# model-storage-pvc (10Gi)
accessModes:
  - ReadWriteOnce
storageClassName: gp3-csi
```

**HA Topology:**
```yaml
# workbench-data-development (20Gi)
accessModes:
  - ReadWriteOnce
storageClassName: ocs-storagecluster-cephfs

# model-storage-pvc (10Gi)
accessModes:
  - ReadWriteMany
storageClassName: ocs-storagecluster-cephfs

# model-storage-gpu-pvc (10Gi) - GPU training only
accessModes:
  - ReadWriteOnce
storageClassName: gp3-csi
```

## Consequences

### Positive
- ✅ Pod scheduling succeeds on GPU node
- ✅ Workbench pod reaches Running state
- ✅ No CSI driver issues
- ✅ Simpler, more maintainable configuration
- ✅ Aligns with Validated Patterns best practices

### Negative
- ❌ Cannot share model-artifacts between multiple pods simultaneously
- ❌ Requires pod restart to switch between pods accessing same volume

### Mitigation
If multi-pod access becomes required:
1. Use OCS RBD (RWO) - requires OCS node labels
2. Add `node.ocs.openshift.io/storage=true` label to GPU node
3. Use separate PVCs per pod with shared ConfigMaps for read-only data

## Validation

```bash
# Verify storage classes
oc get storageclass

# Check PVCs
oc get pvc -n self-healing-platform

# Monitor pod status
oc get pods -n self-healing-platform self-healing-workbench-dev-0 -o wide

# Verify volume mounts
oc describe pod -n self-healing-platform self-healing-workbench-dev-0 | grep -A 10 "Mounts:"
```

## Related Decisions

- **ADR-GPU-TOLERATION**: GPU node scheduling configuration
- **ADR-HELM-CHART-STRUCTURE**: Helm chart organization
- **ADR-DEVELOPMENT-RULES**: Validated Patterns alignment

## References

- [OpenShift Storage Documentation](https://docs.openshift.com/container-platform/4.18/storage/index.html)
- [AWS EBS CSI Driver](https://docs.openshift.com/container-platform/4.18/storage/container_storage_interface/persistent-storage-csi-ebs.html)
- [OCS CephFS CSI](https://docs.openshift.com/container-platform/4.18/storage/persistent_storage/persistent_storage_local/persistent-storage-ocs.html)
- [Validated Patterns - Storage](https://validatedpatterns.io/learn/vp_openshift_framework/)
