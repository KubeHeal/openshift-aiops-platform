# Deploying on Single Node OpenShift (SNO)

This guide explains how to deploy the AI Ops Self-Healing Platform on Single Node OpenShift (SNO) clusters.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deployment Steps](#deployment-steps)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Prerequisites

### Hardware Requirements

**Minimum:**
- 8 vCPUs
- 32GB RAM
- 120GB disk

**Recommended:**
- 16 vCPUs
- 64GB RAM
- 500GB disk

### Software Requirements

- OpenShift 4.18, 4.19, or 4.20
- SingleReplica topology (controlPlaneTopology=SingleReplica, infrastructureTopology=SingleReplica)
- CSI storage classes available (gp2-csi, gp3-csi for AWS)

### Verify Cluster Topology

```bash
# Check control plane topology
oc get infrastructure cluster -o jsonpath='{.status.controlPlaneTopology}'
# Expected: SingleReplica

# Check infrastructure topology
oc get infrastructure cluster -o jsonpath='{.status.infrastructureTopology}'
# Expected: SingleReplica

# Check platform type
oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}'
# Example: AWS
```

### Check Storage Classes

```bash
# List available storage classes
oc get sc

# Ensure a default CSI storage class exists
oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'
# Expected: gp3-csi or equivalent
```

## Deployment Steps

### 1. Clone Repository

```bash
git clone https://github.com/KubeHeal/openshift-aiops-platform.git
cd openshift-aiops-platform
```

### 2. Login to OpenShift

```bash
oc login --token=<your-token> --server=https://api.<cluster-domain>:6443
```

### 3. Verify Cluster Detection

```bash
make show-cluster-info
```

**Expected Output:**
```
Cluster Information:
  Topology: sno
  OpenShift Version: 4.20
  Platform: AWS
  ODF Channel: stable-4.20

Cluster Topology Information:
  Type: SNO (Single Node OpenShift)
  Control Plane: SingleReplica
  Infrastructure: SingleReplica
  Platform: AWS
```

### 4. Configure Cluster Infrastructure

```bash
make configure-cluster
```

**Expected Behavior:**
- ✅ Skips MachineSet scaling (log message: "Skipping Worker Node Scaling (SNO Cluster)")
- ✅ Skips ODF installation (log message: "Skipping ODF Installation (SNO Cluster)")
- ✅ Validates CSI storage classes only

### 5. Build Execution Environment (First Time Only)

```bash
# Set your Ansible Hub token
export ANSIBLE_HUB_TOKEN=<your-token>
# Or create a token file
echo "<your-token>" > token

# Build the execution environment
make build-ee
```

### 6. Deploy Pattern

**Option 1: Auto-detection (Recommended)**

```bash
make operator-deploy
```

The platform will automatically detect SNO topology and adjust deployment accordingly.

**Option 2: Explicit SNO Configuration**

```bash
export CLUSTER_TOPOLOGY=sno
make operator-deploy EXTRA_HELM_OPTS="-f values-sno.yaml"
```

This explicitly uses SNO-specific resource limits and storage configuration.

### 7. Validate Deployment

```bash
# Check ArgoCD application health
make argo-healthcheck

# Verify pods are running
oc get pods -n self-healing-platform

# Check PVCs (should use CSI storage classes)
oc get pvc -n self-healing-platform
```

## Limitations

### Storage

❌ **No ODF support** (requires minimum 3 nodes)
- Only CSI storage classes available (gp2-csi, gp3-csi on AWS)
- No CephFS or RBD storage
- ReadWriteMany (RWX) support depends on CSI driver

### Resource Constraints

⚠️ **All workloads compete for single node's resources**
- Reduced resource limits applied automatically via `values-sno.yaml`
- GPU workloads may impact cluster stability
- Monitor resource usage closely

### High Availability

❌ **No HA capabilities**
- Single point of failure
- Node maintenance requires cluster downtime
- Not recommended for production workloads requiring HA

### Scaling

❌ **Cannot add worker nodes**
- No MachineSet scaling support
- Vertical scaling only (resize the node)
- Horizontal pod autoscaling limited by single node capacity

## Troubleshooting

### Issue: ODF Installation Attempted

**Symptom:** Script tries to install ODF, fails due to insufficient nodes

```
Error: ODF requires minimum 3 nodes
```

**Solution:**
```bash
export CLUSTER_TOPOLOGY=sno
make configure-cluster
```

### Issue: Pods Pending Due to Resources

**Symptom:** Pods stuck in Pending state with "Insufficient memory/cpu" errors

```
Warning  FailedScheduling  pod/my-pod  0/1 nodes available: insufficient memory
```

**Solution:** Apply SNO resource limits

```bash
make operator-deploy EXTRA_HELM_OPTS="-f values-sno.yaml"
```

Or manually adjust resource requests/limits in chart values.

### Issue: Storage Class Not Found (ocs-storagecluster-cephfs)

**Symptom:** PVCs pending, looking for ODF storage classes

```
Warning  ProvisioningFailed  persistentvolumeclaim/model-storage-pvc  storageclass.storage.k8s.io "ocs-storagecluster-cephfs" not found
```

**Solution:** Ensure CSI storage is default and update values

```bash
# Set gp3-csi as default storage class
oc patch storageclass gp3-csi -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Remove default from other storage classes
oc patch storageclass gp2-csi -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# Redeploy with SNO values
make operator-deploy EXTRA_HELM_OPTS="-f values-sno.yaml"
```

### Issue: Auto-Detection Not Working

**Symptom:** Platform detects "standard" topology on SNO cluster

**Solution:** Manually override

```bash
export CLUSTER_TOPOLOGY=sno
make show-cluster-info  # Verify detection
make operator-deploy EXTRA_HELM_OPTS="-f values-sno.yaml"
```

### Issue: Notebook Validation Jobs Failing

**Symptom:** NotebookValidationJob pods OOMKilled or CrashLoopBackOff

**Solution:** Reduce notebook resource limits in `values-sno.yaml`

```yaml
notebooks:
  validation:
    resources:
      tier1:
        limits:
          memory: "256Mi"  # Reduced from 512Mi
          cpu: "250m"      # Reduced from 500m
```

## Best Practices

### 1. Use CSI Storage

Always use CSI-based storage classes (gp3-csi recommended for AWS):

```yaml
storage:
  modelStorage:
    storageClass: "gp3-csi"
  modelStorageGpu:
    storageClass: "gp3-csi"
```

### 2. Monitor Resources

Single node means shared resources - monitor closely:

```bash
# Watch node resource usage
watch 'oc adm top node'

# Watch pod resource usage
watch 'oc adm top pods -n self-healing-platform'

# Check resource requests/limits
oc get pods -n self-healing-platform -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory,CPU_LIM:.spec.containers[*].resources.limits.cpu,MEM_LIM:.spec.containers[*].resources.limits.memory'
```

### 3. Limit Workloads

Deploy only essential workloads on SNO:

- ✅ Core coordination engine
- ✅ Essential notebooks (tier1, tier2)
- ⚠️ Advanced notebooks (tier3) - be cautious
- ❌ Large-scale model training - not recommended

### 4. Set Appropriate Resource Requests/Limits

Use the SNO values file and adjust as needed:

```bash
make operator-deploy EXTRA_HELM_OPTS="-f values-sno.yaml"
```

### 5. Regular Backups

**Critical for SNO:** Single node = single point of failure

```bash
# Backup etcd regularly
oc get nodes
oc debug node/<node-name>
# Follow OpenShift backup procedures
```

### 6. Plan Maintenance Windows

Node maintenance requires cluster downtime:

- Schedule maintenance during off-hours
- Notify users in advance
- Test upgrades in dev/test SNO first

### 7. Consider Upgrade Path

**For Production:** Plan migration to standard HighlyAvailable cluster:

1. Deploy standard cluster with 3+ nodes
2. Migrate workloads using GitOps (ArgoCD)
3. Update `values-hub.yaml` to use ODF storage classes
4. Redeploy with `make operator-deploy`

## Resource Configuration Reference

### SNO Values File (`values-sno.yaml`)

```yaml
# Cluster configuration
cluster:
  topology: "sno"

# Reduced resource requirements for single-node constraints
notebooks:
  validation:
    resources:
      tier1:
        limits:
          memory: "512Mi"
          cpu: "500m"
      tier2:
        limits:
          memory: "2Gi"
          cpu: "1000m"
      tier3:
        limits:
          memory: "8Gi"
          cpu: "2000m"

# Storage classes (CSI only - ODF not available)
storage:
  modelStorage:
    size: "10Gi"
    storageClass: "gp3-csi"
  modelStorageGpu:
    size: "10Gi"
    storageClass: "gp3-csi"

# Disable ODF-dependent features
odf:
  enabled: false
```

## Comparison: SNO vs Standard Cluster

| Feature | SNO | Standard (3+ nodes) |
|---------|-----|---------------------|
| **Resource Isolation** | ❌ Shared | ✅ Distributed |
| **High Availability** | ❌ No | ✅ Yes |
| **ODF Storage** | ❌ No | ✅ Yes |
| **MachineSet Scaling** | ❌ No | ✅ Yes |
| **Production Ready** | ⚠️ Limited | ✅ Yes |
| **Use Case** | Dev/Test, Edge | Production |
| **Cost** | 💰 Lower | 💰💰💰 Higher |

## Related Documentation

- [Main README](../../README.md)
- [ADR-055: OpenShift 4.20 Multi-Cluster Topology Support](../adrs/055-openshift-420-multi-cluster-topology-support.md)
- [OpenShift SNO Documentation](https://docs.openshift.com/container-platform/4.20/installing/installing_sno/install-sno-preparing-to-install-sno.html)

## Support

For issues or questions:
- 🐛 GitHub Issues: https://github.com/KubeHeal/openshift-aiops-platform/issues
- 📧 Email: support@example.com
- 💬 Slack: #openshift-aiops-platform

---

**Last Updated:** 2026-02-23
