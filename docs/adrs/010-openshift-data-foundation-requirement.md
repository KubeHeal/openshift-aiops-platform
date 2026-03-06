# ADR-010: OpenShift Data Foundation as Storage Infrastructure Requirement

**Status:** ACCEPTED

## Status

accepted - 2025-10-13

## Implementation Status
**Status:** implemented
**Verification Date:** 2026-01-25
**Implementation Score:** 10.0/10
**Verified On:** SNO + HA clusters
**Evidence:** ODF 4.18.14-rhodf deployed, 10 components operational. Topology-aware storage configuration validated.

## Context

The Self-Healing Platform requires sophisticated storage capabilities to support its AI/ML workloads and distributed architecture. During implementation, we discovered that the platform has specific storage access mode requirements that cannot be satisfied by standard cloud storage classes alone.

### Storage Requirements Analysis

The platform requires two distinct types of storage access:

1. **ReadWriteOnce (RWO)**: For individual pod data, logs, and configurations
2. **ReadWriteMany (RWX)**: For shared model artifacts, datasets, and multi-pod AI/ML workloads

### Current Storage Landscape

**Available Storage Classes**:
- **AWS EBS (`gp3-csi`, `gp2-csi`)**: Provides RWO access only
- **OpenShift Data Foundation**: Provides both RWO and RWX access modes

### Critical Implementation Discovery

During deployment, the `model-artifacts` PVC failed to provision because:
- **Required Access Mode**: ReadWriteMany (RWX) for shared model storage
- **Attempted Storage Class**: `gp3-csi` (AWS EBS) - RWO only
- **Result**: PVC stuck in Pending state, blocking AI/ML workbench deployment

### Architecture Dependencies Requiring RWX Storage

1. **AI/ML Workbench (Jupyter Notebooks)**
   - Multiple notebook instances need shared access to model artifacts
   - Data scientists collaborate on shared datasets and models

2. **KServe Model Serving**
   - InferenceServices need access to trained model files
   - Model artifacts must be accessible across multiple serving pods

3. **Kubeflow Pipelines (MLOps)**
   - Pipeline steps need shared access to intermediate artifacts
   - Model training and validation require shared storage

4. **Coordination Engine**
   - Needs access to shared configuration and model metadata
   - Coordinates between different platform components

## Decision

We will **mandate OpenShift Data Foundation (ODF) as a required infrastructure component** for the Self-Healing Platform.

### Storage Architecture

| Storage Type | Access Mode | Storage Class | Use Case |
|--------------|-------------|---------------|----------|
| **Individual Pod Data** | RWO | `gp3-csi` (AWS EBS) | Logs, configs, temporary data |
| **Shared Model Artifacts** | RWX | `ocs-storagecluster-cephfs` | Models, datasets, shared files |
| **High-Performance Block** | RWO | `ocs-storagecluster-ceph-rbd` | Database storage, high-IOPS workloads |

### ODF Components Required

- **Ceph RBD**: High-performance block storage (RWO)
- **CephFS**: Shared filesystem storage (RWX)
- **NooBaa**: S3-compatible object storage (optional for model registry)

## Alternatives Considered

### 1. **AWS EFS with CSI Driver**
- **Pros**: Native AWS service, managed
- **Cons**: Additional AWS dependency, performance limitations, cost complexity
- **Verdict**: Rejected - adds cloud vendor lock-in

### 2. **NFS Server Deployment**
- **Pros**: Simple, well-understood
- **Cons**: Single point of failure, manual management, no enterprise features
- **Verdict**: Rejected - not enterprise-grade

### 3. **Rook-Ceph Manual Deployment**
- **Pros**: More control over configuration
- **Cons**: Complex management, no Red Hat support, operational overhead
- **Verdict**: Rejected - ODF provides supported Rook-Ceph

### 4. **Redesign to RWO-Only**
- **Pros**: Works with existing EBS storage
- **Cons**: Breaks AI/ML collaboration model, limits scalability, architectural compromise
- **Verdict**: Rejected - compromises core platform capabilities

## Consequences

### Positive Consequences

1. **Complete Storage Solution**
   - RWX support enables true AI/ML collaboration
   - High-performance storage for demanding workloads
   - Enterprise-grade data protection and backup

2. **Architectural Consistency**
   - All ADRs can be implemented as designed
   - No compromises to the self-healing platform vision
   - Supports distributed AI/ML workflows

3. **Operational Excellence**
   - Red Hat supported storage solution
   - Integrated monitoring and management
   - Automatic data replication and healing

4. **Future-Proof Architecture**
   - Supports advanced features like snapshots, cloning
   - S3-compatible object storage for model registry
   - Scales with platform growth

### Negative Consequences

1. **Infrastructure Complexity**
   - Additional operator to manage (ODF Operator)
   - More complex storage architecture
   - Requires understanding of Ceph concepts

2. **Resource Requirements**
   - Additional storage overhead for Ceph metadata
   - Requires dedicated storage nodes or sufficient node storage
   - Higher memory and CPU usage for storage services

3. **Cost Implications**
   - Additional licensing costs for ODF
   - Higher storage overhead compared to simple EBS
   - Requires proper capacity planning

4. **Deployment Dependencies**
   - ODF must be installed before platform deployment
   - Adds prerequisite to installation process
   - Requires cluster admin privileges for ODF installation

## Implementation Requirements

### Prerequisites

1. **ODF Installation**
   ```bash
   # Install ODF Operator
   oc create -f - <<EOF
   apiVersion: operators.coreos.com/v1alpha1
   kind: Subscription
   metadata:
     name: odf-operator
     namespace: openshift-storage
   spec:
     channel: stable-4.18
     name: odf-operator
     source: redhat-operators
     sourceNamespace: openshift-marketplace
   EOF
   ```

2. **Storage Cluster Configuration**
   - Minimum 3 worker nodes with local storage
   - At least 100GB available storage per node
   - Proper node labeling for storage nodes

### Updated Kustomize Configuration

**Base Storage Configuration** (`k8s/base/storage.yaml`):
```yaml
# Individual pod data - RWO
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: self-healing-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3-csi
  resources:
    requests:
      storage: 10Gi
---
# Shared model artifacts - RWX
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-artifacts
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ocs-storagecluster-cephfs
  resources:
    requests:
      storage: 50Gi
```

**Development Overlay** (`k8s/overlays/development/kustomization.yaml`):
- `model-artifacts`: 10Gi with `ocs-storagecluster-cephfs`
- `self-healing-data`: 5Gi with `gp3-csi`

**Production Overlay** (`k8s/overlays/production/kustomization.yaml`):
- `model-artifacts`: 200Gi with `ocs-storagecluster-cephfs`
- `self-healing-data`: 50Gi with `ocs-storagecluster-ceph-rbd`

## Validation and Testing

### Storage Validation Commands

```bash
# Verify ODF installation
oc get storagecluster -n openshift-storage

# Verify storage classes
oc get storageclass | grep ocs

# Test RWX functionality
oc run test-rwx-1 --image=busybox --restart=Never -- sleep 3600
oc run test-rwx-2 --image=busybox --restart=Never -- sleep 3600
# Mount same PVC to both pods and verify shared access
```

### Performance Benchmarking

- **RWO Performance**: Compare `ocs-storagecluster-ceph-rbd` vs `gp3-csi`
- **RWX Performance**: Benchmark `ocs-storagecluster-cephfs` for ML workloads
- **Concurrent Access**: Test multiple pods accessing shared storage

## Monitoring and Alerting

### ODF-Specific Monitoring

- **Ceph Cluster Health**: Monitor cluster status and data replication
- **Storage Utilization**: Track usage across all storage classes
- **Performance Metrics**: Monitor IOPS, latency, and throughput
- **Capacity Planning**: Alert on storage capacity thresholds

### Integration with Platform Monitoring

- Add ODF metrics to existing Prometheus configuration
- Create alerts for storage-related issues
- Dashboard integration for storage health visibility

## Related ADRs

- **ADR-001**: OpenShift Platform Selection - ODF is part of OpenShift ecosystem
- **ADR-003**: OpenShift AI ML Platform - Requires RWX storage for shared notebooks
- **ADR-004**: KServe Model Serving - Needs shared access to model artifacts
- **ADR-008**: Kubeflow Pipelines MLOps - Requires shared storage for pipeline artifacts
- **ADR-009**: Bootstrap Deployment Automation - Must validate ODF prerequisites

## References

- [OpenShift Data Foundation Documentation](https://docs.openshift.com/container-platform/4.18/storage/persistent_storage/persistent-storage-ocs.html)
- [Ceph Storage Architecture](https://docs.ceph.com/en/latest/architecture/)
- [Self-Healing Platform PRD](../../PRD.md)
- [Storage Requirements Analysis](../../IMPLEMENTATION_TASKS.md)

## Implementation Status

- ✅ **ODF Installed**: Cluster has ODF 4.18.11 operational
- ✅ **Storage Classes Available**: All required storage classes present
- ✅ **Kustomize Updated**: Development and production overlays configured
- ✅ **PVC Validation**: Both RWO and RWX PVCs working correctly
- ⏳ **Platform Deployment**: Pods starting with correct storage configuration
