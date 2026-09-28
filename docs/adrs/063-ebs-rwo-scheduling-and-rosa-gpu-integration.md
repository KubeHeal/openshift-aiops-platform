# ADR-063: EBS RWO Shared-Volume Scheduling and ROSA GPU Integration

## Status

Accepted

## Date

2026-09-28

## Context

During the first end-to-end deployment on ROSA Classic HA (OCP 4.21, us-east-1), the platform encountered 10 distinct deployment issues. This ADR documents the two most architecturally significant patterns discovered: **EBS ReadWriteOnce shared-volume scheduling** and **NVIDIA GPU Operator integration via Helm/ArgoCD**.

### Problem 1: EBS Volume Multi-Attach Failures

On ROSA with `objectStore.backend: aws-s3`, the platform uses native AWS S3 for model artifact storage instead of ODF/NooBaa. The `model-storage-pvc` PersistentVolumeClaim uses gp3-csi (EBS), which only supports `ReadWriteOnce` (RWO) — the volume attaches to a single node at a time.

Multiple pods share this PVC:
- `self-healing-workbench-0` (StatefulSet) — Jupyter notebook workbench
- `anomaly-detector-predictor-*` — KServe InferenceService predictor
- `predictive-analytics-predictor-*` — KServe InferenceService predictor
- `restart-predictors-after-models-ready` (Job) — post-training restart
- `model-restart-after-training` (Job) — model reinitialization
- `initial-model-training` (Job) — first-time model setup

When these pods schedule to different nodes, the EBS volume cannot multi-attach and pods fail with:
```
Multi-Attach error for volume "pvc-xxx": Volume is already exclusively attached to one node
and can't be attached to another
```

**Key insight**: EBS PersistentVolume `nodeAffinity` is zone-level (`topology.ebs.csi.aws.com/zone=us-east-1a`), not node-level. The Kubernetes scheduler sees that the volume is in `us-east-1a` but cannot determine which specific node within that zone the volume is attached to. Multiple worker nodes exist in the same zone, so pods land on the wrong node.

### Problem 2: GPU Operator Not Deployed

The platform documentation listed NVIDIA GPU Operator as a component, but no Helm template or VP subscription existed to deploy it. GPU nodes (g5.2xlarge) had hardware but no NVIDIA drivers, device plugin, or DCGM — the `nvidia.com/gpu` resource was never advertised by the node.

Additionally, GPU validation pods requested `nvidia.com/gpu: 1` in their resource limits and had `nodeSelector: nvidia.com/gpu.present=true`, but lacked the toleration for the `nvidia.com/gpu=True:NoSchedule` taint that the GPU Operator places on GPU nodes.

## Decision

### Decision 1: PodAffinity for EBS RWO Co-Scheduling

All pods that mount the shared `model-storage-pvc` use `requiredDuringSchedulingIgnoredDuringExecution` podAffinity to anchor to the workbench StatefulSet pod:

```yaml
affinity:
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          notebook-name: self-healing-workbench
      topologyKey: kubernetes.io/hostname
```

**Why the workbench as the anchor?**
- It is a StatefulSet — stable, long-lived, and (once scheduled) pinned to a node with a stable PVC binding.
- The workbench is the first pod to bind the PVC, so the EBS volume attaches to whatever node the workbench lands on.
- All other pods follow the workbench by affinity, ensuring they land on the same node.

**Label choice**: The label `notebook-name: self-healing-workbench` (not `opendatahub.io/notebook-name`) is what the OpenShift AI workbench controller applies to pods. An initial attempt used the wrong label prefix and had to be corrected.

**Conditional rendering**: The affinity block is only rendered when `objectStore.backend == "aws-s3"`, since ODF-backed deployments use CephFS (RWX) which supports multi-node attachment.

### Decision 2: GPU PVC Gating Pattern

The platform defines two PVCs:
- `model-storage-pvc` — general model storage (always created)
- `model-storage-gpu-pvc` — GPU-specific model storage (only on ODF HA clusters)

The `model-storage-gpu-pvc` is gated on `NOT sno AND NOT aws-s3`:

```yaml
{{- if and (ne ((.Values.cluster).topology | default "ha") "sno")
           (ne (default "aws-s3" ((.Values.objectStore).backend)) "aws-s3") }}
```

**Every template referencing `model-storage-gpu-pvc` must use the same gate.** This was violated in 4 locations within `tekton-model-training-pipeline.yaml` which only checked `sno` topology. The fix adds the `aws-s3` backend check everywhere:

| File | Locations Fixed |
|------|----------------|
| `tekton-model-training-pipeline.yaml` | Lines 309 (GPU task volume), 712 (GPU pipeline gate), 1012 (copy task), 1032 (runAfter) |
| `model-restart-job.yaml` | GPU PVC volumeMount |
| `restart-predictors-job.yaml` | GPU PVC volumeMount |

### Decision 3: GPU Operator + NFD via Helm/ArgoCD

Deploy NVIDIA GPU Operator and Node Feature Discovery as first-class platform components:

**VP Subscriptions** (in `values-hub.yaml`):
- NFD: `channel: stable`, `source: redhat-operators`, namespace `openshift-nfd`
- GPU Operator: `channel: v26.7`, `source: certified-operators`, namespace `nvidia-gpu-operator`
- Both use `OwnNamespace` install mode (not `AllNamespaces`)

**Helm Template** (`charts/hub/templates/operators/nvidia-gpu-operator.yaml`):
- `NodeFeatureDiscovery` CR at sync-wave **-10** (hardware discovery first)
- `ClusterPolicy` CR at sync-wave **-9** (driver + device plugin deployment)
- Both gated on `nodeConfig.gpu.enabled`

**ArgoCD Sync Wave Ordering**:
| Wave | Resource | Purpose |
|------|----------|---------|
| -10 | NodeFeatureDiscovery | Label GPU nodes with hardware features |
| -9 | ClusterPolicy | Install NVIDIA driver, device plugin, DCGM |
| -6 | Storage PVCs | Create model storage volumes |
| -5 to -3 | RBAC, Secrets | Platform infrastructure |
| 0 to 6 | Validation Jobs | Notebook validation (GPU pods need device plugin) |
| 2 | InferenceServices | Model serving |
| 3 | Tekton Pipelines | Model training |

**GPU Toleration for Validation Pods**: When `gpuRequired: true` AND `gpu.enabled: true`, the `notebook-validation-jobs.yaml` template renders:
```yaml
tolerations:
- key: nvidia.com/gpu
  operator: Exists
  effect: NoSchedule
nodeSelector:
  nvidia.com/gpu.present: "true"
```

### Decision 4: S3 IAM Credential Provisioning

Added Step 7 to `create-rosa-cluster.sh` that:
- Creates IAM user `<cluster-name>-s3-access` with a scoped S3 policy (limited to the model storage bucket)
- Generates an access key and outputs credentials for `values-hub.yaml`
- Is idempotent (reuses existing user/keys)

## Consequences

### Positive

1. **EBS RWO works reliably** — all pods sharing a PVC land on the same node via podAffinity
2. **GPU stack is fully automated** — NFD + GPU Operator deploy via ArgoCD, no manual intervention
3. **Sync wave ordering** prevents race conditions — GPU hardware discovery completes before workloads deploy
4. **Template consistency** — GPU PVC gating pattern is documented and applied uniformly
5. **S3 credentials are automated** — no manual `oc patch` required

### Negative

1. **Single-node bottleneck** — podAffinity pins all model pods to one worker node, concentrating load
2. **GPU driver build time** — NVIDIA driver compilation takes 5-10 minutes after ClusterPolicy creation; sync waves ensure creation order but cannot wait for readiness
3. **GPU pod queuing** — with 1 GPU, validation pods run sequentially; multiple GPU nodes would allow parallelism but increase cost
4. **Schema coupling** — ClusterPolicy CRD schema changes between GPU Operator versions (v26.7 requires `spec.dcgm`, deprecated `driver.use_ocp_driver_toolkit`)

### Neutral

1. **ODF deployments unaffected** — all EBS-specific fixes are conditional on `objectStore.backend == "aws-s3"`
2. **SNO deployments unaffected** — GPU PVC and GPU operator are both gated off for SNO topology

## Related Issues

- [#135](https://github.com/KubeHeal/openshift-aiops-platform/issues/135) — GPU PVC gating in Tekton pipeline
- [#136](https://github.com/KubeHeal/openshift-aiops-platform/issues/136) — GPU toleration for validation pods
- [#137](https://github.com/KubeHeal/openshift-aiops-platform/issues/137) — S3 IAM credential provisioning

## Related ADRs

- [ADR-006](006-nvidia-gpu-management.md) — NVIDIA GPU Operator for AI Workload Management
- [ADR-035](035-storage-strategy.md) — Storage Strategy
- [ADR-041](041-model-storage-and-versioning-strategy.md) — Model Storage and Versioning Strategy
- [ADR-056](056-standalone-mcg-on-sno.md) — Standalone MCG on SNO
- [ADR-057](057-topology-aware-gpu-scheduling-and-storage.md) — Topology-Aware GPU Scheduling and Storage
- [ADR-062](062-rosa-primary-deployment-target.md) — ROSA as Primary Deployment Target

## Commits

| Commit | Description |
|--------|-------------|
| `9571d794` | ReadWriteOnce for model storage on aws-s3 backend |
| `f42a9119` | Skip s3-bucket-setup job for aws-s3 backend |
| `2e664e93` | PodAffinity on model restart jobs |
| `8b61242b` | PodAffinity on InferenceService predictors |
| `be321fbe` | Correct podAffinity label selector |
| `fa532b24` | Skip GPU PVC mount in model-restart-job |
| `751e620b` | Gate GPU PVC in Tekton pipeline (#135) |
| `efa000e3` | GPU toleration for validation pods (#136) |
| `e58339a2` | S3 IAM credential provisioning (#137) |
| `122863ce` | GPU Operator + NFD via Helm/ArgoCD |
| `dc424c46` | OwnNamespace install mode for NFD/GPU |
| `09db90da` | ClusterPolicy schema fix for v26.7 |
