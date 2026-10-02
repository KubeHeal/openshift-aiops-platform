# ADR-065: Baremetal and Agent-Based Install Compatibility

## Status

Accepted

## Date

2026-10-02

## Context

The Self-Healing Platform was developed and primarily tested on ROSA (Red Hat OpenShift Service on AWS). As the platform matures toward its [v1.0 release](../adrs/064-distribution-strategy-three-tier.md) and OperatorHub listing, we need to document whether baremetal, UPI, and Agent-Based Install (ABI) deployments are supported and what, if any, code changes are required.

Key questions:
1. Does the Helm chart render correctly on baremetal/ABI clusters?
2. Does the kubeheal-operator work on non-cloud platforms?
3. Are there storage or GPU differences that need accommodation?
4. What is the testing status for these environments?

## Decision

**Baremetal and Agent-Based Install require zero code changes.** The platform's existing topology detection (`ha` / `sno`), storage backend selection (`aws-s3` / `noobaa`), and GPU gating (`nodeConfig.gpu.enabled`) already handle all necessary differences.

### Architecture Analysis

Agent-Based Install creates a standard OpenShift cluster that is indistinguishable from IPI/UPI at the Kubernetes API level. The platform interacts only with standard APIs:
- `infrastructure.config.openshift.io` (topology detection)
- OLM Subscriptions (operator installation)
- Standard CRDs (KServe, External Secrets, GPU Operator, etc.)

None of these APIs differ between cloud-hosted and baremetal clusters.

### Storage Compatibility

| Backend | Baremetal Support | Configuration |
|---------|------------------|---------------|
| ODF/NooBaa | ✅ Full support | `objectStore.backend: "noobaa"` |
| External S3 (MinIO, Ceph RGW) | ⚠️ Community-tested | `objectStore.backend: "aws-s3"` + custom endpoint |
| Native AWS S3 | ❌ Not available | N/A (no AWS APIs on baremetal) |

The `objectStore.backend` value switch was designed in [ADR-062](062-rosa-primary-deployment-target.md) to support this exact scenario. Baremetal users set `backend: "noobaa"` and the chart automatically uses ODF-based S3.

For environments with external S3-compatible storage (MinIO, Ceph RADOS Gateway), the `aws-s3` backend works with a custom `objectStore.aws.endpoint` URL.

### GPU Compatibility

GPU support on baremetal works identically to cloud:
- NFD Operator discovers GPU hardware
- GPU Operator installs NVIDIA drivers
- `nodeConfig.gpu.enabled: true` triggers ClusterPolicy and NodeFeatureDiscovery CRs

The only difference is that baremetal GPU nodes must have physical NVIDIA GPUs, while cloud deployments use GPU instance types (e.g., `g5.2xlarge`).

### Operator Compatibility

The kubeheal-operator (Helm SDK) has been E2E tested on ROSA OCP 4.22.15. The operator interacts with the cluster only through standard Kubernetes and OpenShift APIs. A baremetal-specific sample CR is provided:

```yaml
# config/samples/aiops_v1alpha1_selfhealingplatform_baremetal.yaml
spec:
  objectStore:
    backend: "noobaa"
  storage:
    modelStorage:
      storageClass: "ocs-storagecluster-cephfs"
```

## Consequences

### Positive

- **Zero maintenance burden**: No platform-specific code paths to maintain
- **Broader adoption**: Users on baremetal, ABI, and VMware can deploy without waiting for dedicated testing
- **Validated Patterns compatibility**: The VP framework itself is platform-agnostic, and our chart inherits this property

### Negative

- **Testing gap**: Baremetal and external S3 paths are not yet covered by automated CI. Community testing is the primary validation mechanism.
- **Support expectations**: Users may expect Tier 1 support on untested platforms. The [platform support tiers](../how-to/deploy-on-other-platforms.md) documentation mitigates this.

### Risks

- **ODF version skew**: ODF behavior may vary across platform installers. Mitigated by testing on ROSA (which uses the same ODF operator).
- **External S3 endpoint compatibility**: Some S3-compatible services have API differences (e.g., path-style vs virtual-hosted-style). The chart uses the standard AWS SDK, which handles most variations.

## Alternatives Considered

### 1. Add platform-specific code paths

Rejected. Would increase maintenance burden without clear benefit, since the existing abstraction (`objectStore.backend`) already handles all known differences.

### 2. Block unsupported platforms

Rejected. The platform works on baremetal — blocking it would unnecessarily limit adoption. The tiered support model communicates expectations without blocking usage.

## References

- [ADR-062: ROSA as Primary Deployment Target](062-rosa-primary-deployment-target.md)
- [ADR-055: Multi-Cluster Topology Support](055-openshift-420-multi-cluster-topology-support.md)
- [Deploy on Other Platforms](../how-to/deploy-on-other-platforms.md)
- [kubeheal-operator E2E test results](https://github.com/KubeHeal/kubeheal-operator)
