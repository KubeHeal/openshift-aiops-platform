# ADR-062: ROSA as Primary Deployment Target

## Status

Accepted

## Date

2026-09-25

## Context

The OpenShift AI Ops Self-Healing Platform was originally built and documented for AWS IPI (Installer-Provisioned Infrastructure) clusters, with SNO support added later. The deployment scripts (`configure-cluster-infrastructure.sh`) directly manipulate MachineSets via the `openshift-machine-api` namespace, the storage chain assumes ODF/NooBaa for S3 object storage, and all documentation is framed around topology (HA vs SNO) rather than cluster provisioning method.

ROSA (Red Hat OpenShift Service on AWS) is Red Hat's managed OpenShift offering on AWS. It provides:

- Managed control plane and worker lifecycle
- Machine Pools instead of MachineSets for node scaling
- AWS STS (Secure Token Service) with IRSA (IAM Roles for Service Accounts) for credential management
- Native AWS service integration (S3, IAM, CloudWatch)
- Simplified cluster lifecycle management via `rosa` CLI

Users deploying this platform increasingly use ROSA as their cluster platform, but the existing scripts and documentation assume IPI infrastructure, causing deployment friction and failed MachineSet operations on ROSA clusters.

## Decision

Make **ROSA Classic** (both HA multi-node and single-worker-node configurations) the **primary deployment target** for the platform.

### Storage Backend

Introduce `objectStore.backend` with two supported values:

- **`aws-s3`** (default): Native AWS S3 buckets with IRSA or static IAM credentials. No ODF/NooBaa dependency. Recommended for ROSA and all AWS-based clusters.
- **`noobaa`**: OpenShift Data Foundation NooBaa S3. Required for baremetal, air-gapped, and non-AWS environments. All existing ODF/NooBaa templates, RBAC, and credential chains remain fully functional.

### Platform Detection

The infrastructure detection scripts (`detect-cluster-topology.sh`, `configure-cluster-infrastructure.sh`) are updated to:

- Auto-detect ROSA clusters via ClusterVersion channel, infrastructure annotations, and MachinePool API availability
- Skip MachineSet operations on ROSA (Machine Pools are managed externally via `rosa` CLI)
- Support a `--rosa` flag for explicit ROSA mode

### Documentation Structure

- **Primary path**: ROSA deployment guide (`docs/how-to/deploy-on-rosa.md`)
- **Community-supported**: Other platforms guide (`docs/how-to/deploy-on-other-platforms.md`) covering IPI, baremetal, SNO, VMware, Azure, GCP
- **CONTRIBUTING.md**: Platform support tiers (Tier 1: ROSA, Tier 2: Community)

## Consequences

### Positive

- **Simplified deployment**: ROSA users get a native, friction-free deployment path
- **Better security model**: Native AWS S3 with IRSA avoids the ODF/NooBaa credential chain and cross-namespace RBAC
- **Reduced dependencies**: No ODF operator required on ROSA, reducing resource consumption and complexity
- **Managed infrastructure**: ROSA handles control plane, updates, and node lifecycle
- **Clear documentation**: Users know which path to follow based on their platform

### Negative

- **ROSA cost**: ROSA has a per-cluster hourly cost on top of AWS infrastructure
- **Less cluster-admin control**: ROSA restricts some cluster-admin operations (mitigated by `dedicated-admin` group)
- **Machine Pool vs MachineSet**: GPU node scaling requires `rosa` CLI instead of `oc scale machineset`
- **Two storage paths**: Maintaining both `aws-s3` and `noobaa` backends adds template complexity
- **Community burden**: IPI and baremetal users rely on community contributions for ongoing support

### Neutral

- **ODF remains fully supported**: The `noobaa` backend preserves all existing ODF functionality for environments that need it
- **Backward compatible**: Existing deployments continue to work; `objectStore.backend` defaults to `aws-s3` but can be set to `noobaa` for current ODF users
- **Helm chart structure unchanged**: New templates are additive; no existing templates are removed

## Alternatives Considered

### Keep IPI as Primary

Rejected. IPI requires more manual infrastructure management and does not represent the growing ROSA user base.

### Support Both Equally

Rejected. Attempting to document and test all platforms equally dilutes focus and slows down feature development. A tiered model (primary + community) is more sustainable.

### Native S3 Only (Remove ODF Support)

Rejected. ODF is critical for baremetal, air-gapped, and multi-cloud environments. The dual-backend approach preserves flexibility.

## References

- [ADR-001: OpenShift 4.18+ as Foundation Platform](001-openshift-platform-selection.md)
- [ADR-024: External Secrets for Model Storage](024-external-secrets-model-storage.md)
- [ADR-035: Storage Strategy](035-storage-strategy.md)
- [ADR-055: OpenShift 4.20 Multi-Cluster Topology Support](055-openshift-420-multi-cluster-topology-support.md)
- [ADR-056: Standalone MCG on SNO](056-standalone-mcg-on-sno.md)
- [ROSA Documentation](https://docs.openshift.com/rosa/)
