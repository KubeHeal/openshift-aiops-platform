# Deploy on Other Platforms (Community-Supported)

This guide covers deploying the OpenShift AI Ops Self-Healing Platform on platforms other than ROSA. These environments are **community-supported** -- they work but are not the primary tested deployment target.

> **Primary deployment target**: [Deploy on ROSA](deploy-on-rosa.md) is the recommended path for new deployments.

## Platform Support Tiers

| Tier | Platform | Storage Backend | Support Level |
|------|----------|----------------|---------------|
| **Tier 1 (Primary)** | ROSA Classic (HA and single-worker) | Native AWS S3 | Fully tested, documented |
| **Tier 2 (Community)** | AWS IPI | AWS S3 or ODF/NooBaa | Community-maintained |
| **Tier 2 (Community)** | Baremetal / UPI | ODF/NooBaa | Community-maintained |
| **Tier 2 (Community)** | SNO (non-ROSA) | ODF MCG-only / CSI | Community-maintained |
| **Tier 2 (Community)** | VMware / Azure / GCP | ODF/NooBaa | Untested, contributions welcome |

## AWS IPI (Installer-Provisioned Infrastructure)

### Prerequisites

- OpenShift 4.19+ installed via IPI on AWS
- 6+ nodes (3 control-plane, 3+ workers)
- cluster-admin access

### Deployment

```bash
# 1. Fork and clone
git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
cd openshift-aiops-platform

# 2. Log into your cluster
oc login <cluster-api-url>

# 3. Verify topology
make show-cluster-info

# 4. Configure cluster infrastructure (scales MachineSets, installs ODF)
make configure-cluster

# 5. Configure values
vi values-global.yaml
# Set repoURL to YOUR fork

vi values-hub.yaml
# Set cluster.topology: "ha"
# Set objectStore.backend: "noobaa"  # ODF-based storage
# Set objectStore.enabled: true
# Set rbac.crossNamespaceEnabled: true

# 6. Deploy
./pattern.sh make install
```

### Storage Configuration

For IPI on AWS, you can use either storage backend:

- **`objectStore.backend: "aws-s3"`** -- Uses native AWS S3 (same as ROSA). Simpler, no ODF dependency.
- **`objectStore.backend: "noobaa"`** -- Uses ODF/NooBaa S3. Required if you need ODF for other purposes.

## Baremetal / UPI

### Prerequisites

- OpenShift 4.19+ installed on baremetal or UPI
- 3+ worker nodes with ODF-compatible storage (local disks or SAN)
- ODF is the **recommended and fully supported** storage backend for baremetal

### Installation Methods

#### Standard IPI / UPI Install

For baremetal clusters provisioned with the standard installer (IPI with `platform: baremetal` or UPI), no special platform changes are required. The chart and operator work identically to cloud-hosted deployments.

#### Agent-Based Install (ABI)

Agent-Based Install is fully compatible. ABI creates a standard OpenShift cluster that is indistinguishable from IPI/UPI at the API level. No code changes or extra configuration are needed beyond the standard baremetal settings below.

```bash
# After ABI completes and you have cluster-admin access:
oc login <cluster-api-url>
make show-cluster-info   # Verify topology: ha or sno
```

### Storage

Baremetal deployments **must** use ODF/NooBaa for S3 object storage, **unless** you have an external S3-compatible service (MinIO, Ceph RADOS Gateway, etc.).

#### Option A: ODF/NooBaa (Default for Baremetal)

```yaml
# values-hub.yaml
objectStore:
  enabled: true
  backend: "noobaa"

storage:
  modelStorage:
    storageClass: "ocs-storagecluster-cephfs"  # ODF CephFS
```

#### Option B: External S3-Compatible Storage

If you operate MinIO, Ceph RADOS Gateway, or another S3-compatible service, use the `aws-s3` backend with a custom endpoint:

```yaml
# values-hub.yaml
objectStore:
  enabled: true
  backend: "aws-s3"
  aws:
    endpoint: "https://minio.example.com:9000"   # Your S3-compatible endpoint
    bucketName: "model-storage"                   # Pre-created bucket
    region: "us-east-1"                           # Can be any value for non-AWS

# Supply credentials via values-secret.yaml:
#   AWS_ACCESS_KEY_ID: <your-access-key>
#   AWS_SECRET_ACCESS_KEY: <your-secret-key>
```

> **Note:** External S3 is community-tested. See [issue tracking](https://github.com/KubeHeal/openshift-aiops-platform/issues) for status.

### Deployment

```bash
# 1. Install ODF on baremetal
# See: https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/

# 2. Configure cluster (skip MachineSet scaling for baremetal)
./scripts/configure-cluster-infrastructure.sh --skip-odf  # If ODF already installed

# 3. Configure values
vi values-hub.yaml
# Set objectStore.backend: "noobaa"
# Set storage.modelStorage.storageClass: "ocs-storagecluster-cephfs"

# 4. Deploy
./pattern.sh make install
```

### Operator-Based Deployment

The [kubeheal-operator](https://github.com/KubeHeal/kubeheal-operator) also supports baremetal. A sample CR is included in the operator repository:

```bash
# Install kubeheal-operator, then apply the baremetal sample:
oc apply -f config/samples/aiops_v1alpha1_selfhealingplatform_baremetal.yaml
```

### Node Scaling

Baremetal clusters do not support automatic MachineSet scaling. The configure-cluster script will warn and continue. Add nodes manually using your infrastructure management tool.

### Testing Status

| Component | Status | Notes |
|-----------|--------|-------|
| Chart deployment (ArgoCD) | ✅ Supported | No changes needed vs cloud |
| Operator deployment (OLM) | ✅ Tested | E2E tested on ROSA, architecture-identical |
| ODF/NooBaa storage | ✅ Supported | Production-ready |
| External S3 (MinIO, etc.) | ⚠️ Community | Needs community testing |
| GPU (NVIDIA) | ✅ Supported | Requires GPU nodes with NVIDIA drivers |
| Agent-Based Install | ✅ Compatible | Zero code changes needed |

## SNO (Single Node OpenShift) -- Non-ROSA

### Prerequisites

- OpenShift 4.19+ SNO cluster
- 8+ CPU cores (16+ recommended), 32+ GB RAM, 120+ GB storage

### Deployment

See the dedicated [SNO Deployment Guide](deploy-on-sno.md) for step-by-step instructions.

Key differences from ROSA:
- Uses MCG-only ODF (NooBaa S3 without Ceph) by default
- Storage class: `gp3-csi` (AWS) or equivalent CSI class

```yaml
# values-hub.yaml for SNO
cluster:
  topology: "sno"

objectStore:
  enabled: true
  backend: "noobaa"  # MCG-only ODF

storage:
  modelStorage:
    storageClass: "gp3-csi"
```

## VMware / Azure / GCP

These platforms are untested but should work with ODF-based storage:

```yaml
# values-hub.yaml for non-AWS platforms
objectStore:
  enabled: true
  backend: "noobaa"

storage:
  modelStorage:
    # Use your platform's CSI storage class
    storageClass: "<your-csi-storage-class>"
```

**Contributions welcome!** If you successfully deploy on these platforms, please submit a PR with documentation updates.

## Contributing Platform Support

If you want to add or improve support for a platform:

1. Test the deployment end-to-end on your platform
2. Document any platform-specific configuration in this guide
3. Submit a PR with:
   - Updated `values-hub.yaml.example` with your platform's defaults
   - Any script changes needed (with appropriate gating)
   - Test evidence (deployment logs, validation pipeline output)

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for the full contribution process.

## Related Documentation

- [Deploy on ROSA](deploy-on-rosa.md) (primary deployment target)
- [Deploy on SNO](deploy-on-sno.md) (Single Node OpenShift)
- [Complete Deployment Guide](complete-deployment-guide.md) (generic reference)
- [Troubleshooting Guide](../guides/TROUBLESHOOTING-GUIDE.md)
