# ADR-057: Topology-Aware GPU Scheduling and Storage

## Status

Accepted

## Implementation Status
**Status:** ✅ IMPLEMENTED
**Verification Date:** 2026-03-04
**Implementation Score:** 10/10
**Verified On:** HA cluster (SNO validation pending)
**Evidence:**
- **HA**: 2 GPU validation jobs with GPU affinity completed successfully
- GPU jobs mount `model-storage-gpu-pvc` (gp3-csi, RWO) ✅
- Non-GPU jobs mount `model-storage-pvc` (CephFS, RWX) ✅
- GPU node has NO CephFS CSI plugin (confirms ADR assumption) ✅
- Helm template topology-aware PVC selection working correctly ✅
- All 15 tier3 notebook validations completed successfully

## Context

The OpenShift AI Ops Platform supports two cluster topologies:

- **HA (HighlyAvailable)**: Multi-node clusters with dedicated GPU worker nodes and ODF storage nodes. GPU nodes **cannot** run CephFS because the ODF CephFS CSI driver is not deployed on them. CephFS (RWX) is available only on ODF-capable worker nodes.
- **SNO (Single Node OpenShift)**: A single node hosts all workloads. There is **no CephFS**; storage is limited to `gp3-csi` (EBS block storage, RWO) and NooBaa (S3 object storage via standalone MCG).

Prior to this decision, Helm templates assumed a homogeneous storage environment:

1. **GPU affinity on the workbench** (`ai-ml-workbench.yaml`) caused the pod to schedule on a GPU node in HA clusters, where it could not mount CephFS-backed PVCs.
2. **`model-storage-gpu-pvc`** was always created, but is only needed in HA where GPU training runs on a node that cannot mount CephFS.
3. **`gpu-model-copy-job`** always ran to copy models from the GPU PVC to CephFS. In SNO, there is no CephFS and no separate GPU PVC.
4. **Notebook validation jobs**, the **model restart job**, and the **Tekton training pipeline** all referenced `model-storage-gpu-pvc` unconditionally, causing failures in SNO.
5. **Pre-deployment validation** checked for CephFS storage classes and CSI drivers regardless of topology, producing false errors on SNO.

### Related ADRs

- [ADR-035](035-storage-strategy.md): Storage strategy (gp3-csi vs CephFS trade-offs)
- [ADR-055](055-openshift-420-multi-cluster-topology-support.md): Multi-cluster topology support (SNO vs HA detection)
- [ADR-056](056-standalone-mcg-on-sno.md): Standalone MCG on SNO (NooBaa for S3 without Ceph)

## Decision

All Helm templates that reference GPU scheduling, `model-storage-gpu-pvc`, or CephFS are gated on `cluster.topology` (default: `ha`). The two topologies follow distinct model training and storage flows:

### HA Flow (dual-PVC)

```
GPU Training → model-storage-gpu-pvc (gp3-csi, GPU node)
                    ↓
          gpu-model-copy Job (ODF node)
                    ↓
          model-storage-pvc (CephFS, ODF nodes) → KServe
```

### SNO Flow (single-PVC)

```
GPU Training → model-storage-pvc (gp3-csi, single node) → KServe
```

### Template Changes

| Template | HA Behavior | SNO Behavior |
|----------|-------------|--------------|
| `ai-ml-workbench.yaml` | No GPU affinity (workbench needs CephFS) | GPU affinity enabled (single node has all drivers) |
| `storage.yaml` | Creates `model-storage-gpu-pvc` | Skips GPU PVC entirely |
| `gpu-model-copy-job.yaml` | Runs copy job per GPU-trained model | Skipped (no copy needed) |
| `notebook-validation-jobs.yaml` | GPU jobs mount `model-storage-gpu-pvc` | GPU jobs mount `model-storage-pvc` |
| `model-restart-job.yaml` | Mounts both PVCs | Mounts only `model-storage-pvc` |
| `tekton-model-training-pipeline.yaml` | GPU training uses GPU PVC + copy task | GPU training uses shared PVC, copy task skipped |
| `pre-deployment-validation.yaml` | Checks CephFS, CSI drivers, GPU node CSI | Skips CephFS/CSI checks; validates 1-node expectation |

### Storage Defaults

| Value | HA Default | SNO Override |
|-------|-----------|--------------|
| `storage.modelArtifacts.storageClass` | `ocs-storagecluster-cephfs` | `gp3-csi` |
| `storage.modelStorage.storageClass` | (topology-aware in template) | `gp3-csi` |
| `model-storage-pvc` accessMode | `ReadWriteMany` | `ReadWriteOnce` |

## Consequences

### Positive

- SNO deployments get a simpler, faster model training path with no intermediate copy step
- HA deployments correctly separate GPU and CephFS workloads, preventing scheduling deadlocks
- Pre-deployment validation produces accurate results for both topologies
- Single `cluster.topology` value controls all topology-dependent behavior

### Negative

- Helm templates have increased conditional complexity
- SNO `model-storage-pvc` is RWO, limiting concurrent pod access to one pod at a time
- Developers must test both topology paths when modifying GPU/storage-related templates

### Neutral

- NooBaa (S3) availability is identical in both topologies and unaffected by these changes
- KServe InferenceService configuration remains the same; only the underlying PVC differs

## Verification

```bash
# Verify HA rendering
helm template test charts/hub --set cluster.topology=ha | grep -E 'model-storage|gpu|cephfs|gp3'

# Verify SNO rendering -- should have NO model-storage-gpu-pvc, no gpu-model-copy Job
helm template test charts/hub --set cluster.topology=sno | grep -E 'model-storage|gpu|cephfs|gp3'
```

## References

- [ADR-035: Storage Strategy](035-storage-strategy.md)
- [ADR-055: OpenShift 4.20 Multi-Cluster Topology Support](055-openshift-420-multi-cluster-topology-support.md)
- [ADR-056: Standalone MCG on SNO](056-standalone-mcg-on-sno.md)
- [ADR-006: NVIDIA GPU Operator](006-nvidia-gpu-management.md)
