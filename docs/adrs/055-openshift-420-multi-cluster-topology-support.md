# ADR-055: OpenShift 4.20 Multi-Cluster Topology Support

## Status
ACCEPTED

## Context

The AI Ops Self-Healing Platform needs to support OpenShift 4.20 across two distinct cluster topology types:

1. **Standard HighlyAvailable clusters** (3+ nodes, separate control-plane/worker nodes)
2. **SNO (Single Node OpenShift)** clusters (1 node with all roles)

### Cluster Topologies

| Aspect | Standard (HighlyAvailable) | SNO (SingleReplica) |
|--------|---------------------------|---------------------|
| **Nodes** | 3+ nodes (separate control-plane/worker) | 1 node (all roles) |
| **Topology** | controlPlaneTopology=HighlyAvailable, infrastructureTopology=HighlyAvailable | controlPlaneTopology=SingleReplica, infrastructureTopology=SingleReplica |
| **MachineSet** | AWS IPI MachineSets available | Not applicable |
| **ODF Storage** | Full ODF (Ceph + NooBaa) | MCG-only ODF (NooBaa S3, no Ceph) |
| **Storage Classes** | ODF (CephFS/RBD/NooBaa) + CSI (gp2/gp3) | NooBaa + CSI (gp2/gp3) |
| **Resource Distribution** | Distributed across nodes | Single node constraints |
| **Use Cases** | Production, full features | Edge, development, testing |

### Challenges

1. **Infrastructure Requirements**: Different infrastructure setup requirements (MachineSet scaling, ODF availability)
2. **Version-Specific Manifests**: Operator manifests vary across OpenShift versions (4.18, 4.19, 4.20)
3. **Resource Constraints**: SNO clusters have tighter resource constraints than HA clusters
4. **Storage Class Availability**: ODF storage classes not available on SNO

### Current State

The platform currently:
- Assumes multi-node clusters for infrastructure configuration
- Attempts ODF installation without topology checks
- Lacks version-specific deployment parameters
- Does not handle SNO resource constraints

## Decision

Implement **auto-detection of cluster topology and OpenShift version** with environment variable overrides for flexibility.

### Key Components

1. **Detection Scripts**
   - `scripts/detect-cluster-topology.sh`: Queries OpenShift API for topology
   - `scripts/detect-ocp-version.sh`: Extracts OpenShift version for overlay selection

2. **Makefile Integration**
   - Auto-detect topology and version at build time
   - Export variables to scripts and Ansible
   - Provide manual override mechanism

3. **Ansible Roles**
   - Topology-aware resource validation
   - Dynamic minimum requirements based on cluster type
   - Storage class validation adapted to topology

4. **Deployment Logic**
   - Conditional infrastructure setup (skip MachineSet scaling for SNO)
   - Topology-aware ODF: full StorageCluster for HA, MCG-only StorageCluster for SNO (see [ADR-056](056-standalone-mcg-on-sno.md))
   - Version-based operator overlay selection

### Detection Logic

```bash
# Cluster Topology Detection
controlPlaneTopology=$(oc get infrastructure cluster -o jsonpath='{.status.controlPlaneTopology}')
infrastructureTopology=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureTopology}')

if [[ "$controlPlaneTopology" == "SingleReplica" ]] && [[ "$infrastructureTopology" == "SingleReplica" ]]; then
    CLUSTER_TOPOLOGY="sno"
else
    CLUSTER_TOPOLOGY="ha"
fi

# Version Detection
OCP_VERSION=$(oc version -o json | jq -r '.openshiftVersion' | cut -d. -f1-2)
```

### Override Mechanism

Users can override auto-detection:

```bash
export CLUSTER_TOPOLOGY=sno
export OCP_VERSION=4.20
make operator-deploy
```

### SNO-Specific Configuration

For SNO clusters, edit `values-hub.yaml` with SNO overrides before deploying:

- Set `cluster.topology: "sno"`
- Change `storage.modelStorage.storageClass` to `"gp3-csi"`
- `objectStore.enabled` stays `true` -- MCG-only ODF provides NooBaa S3 on SNO (see [ADR-056](056-standalone-mcg-on-sno.md))

Then deploy normally:

```bash
make operator-deploy
```

The chart templates use topology-aware conditionals (e.g., RWO vs RWX access modes) based on `cluster.topology`.

## Rationale

### Why Auto-Detection?

1. **Zero Configuration**: Works out of the box for 90% of deployments
2. **Fail-Fast Validation**: Prevents incompatible configurations early
3. **Single Codebase**: One codebase adapts to all cluster types
4. **User Experience**: No manual topology specification required

### Why Support SNO?

1. **Edge Computing**: SNO is designed for edge deployments
2. **Development/Testing**: Lower resource requirements for development
3. **OpenShift Strategy**: Red Hat promotes SNO for edge use cases
4. **Market Demand**: Increasing adoption of edge AI/ML workloads

### Why Environment Override?

1. **Testing Flexibility**: Test different topologies on same cluster
2. **CI/CD Integration**: Explicit topology for automated pipelines
3. **Troubleshooting**: Force specific configuration for debugging

## Consequences

### Positive

1. **Simplified Deployment**: No manual topology configuration needed
2. **Prevents Misconfiguration**: Automatic checks adapt ODF to topology (MCG-only on SNO, full on HA)
3. **Version Agnostic**: Works across OpenShift 4.18, 4.19, 4.20
4. **Reduced Documentation**: Users don't need to know topology details
5. **Better User Experience**: Platform adapts automatically

### Negative

1. **Additional Complexity**: More conditional logic in scripts and Ansible
2. **Test Matrix Expansion**: 2 topologies × 3 versions = 6 combinations to test
3. **Detection Overhead**: One-time API calls to detect topology (negligible)
4. **Maintenance Burden**: Must maintain topology-specific configurations

### Risks and Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Detection failure | Deployment fails | Fallback to "ha", allow manual override |
| Version mismatch | Wrong overlay used | Version detection from cluster, not user input |
| Resource exhaustion on SNO | Pods crash | Reduced resource limits in values-hub.yaml |
| Missing storage on SNO | PVCs pending | MCG-only ODF provides S3; CSI validated for block/file |

## Implementation

### Files Created

1. `scripts/detect-cluster-topology.sh` - Topology detection script
2. `scripts/detect-ocp-version.sh` - Version detection script
3. `ansible/roles/validated_patterns_prerequisites/tasks/check_cluster_topology.yml` - Ansible topology detection
4. `ansible/roles/validated_patterns_prerequisites/tasks/install_gitops_operator.yml` - Auto-installs OpenShift GitOps if missing
5. `docs/how-to/deploy-on-sno.md` - SNO deployment guide

### Files Modified

1. `Makefile` - Added topology/version detection variables
2. `scripts/configure-cluster-infrastructure.sh` - Topology-aware infrastructure setup: MCG-only StorageCluster for SNO, full ODF for HA
3. `scripts/post-deployment-validation.sh` - Topology-aware validation
4. `ansible/roles/validated_patterns_prerequisites/defaults/main.yml` - SNO resource minimums, GitOps auto-install settings
5. `ansible/roles/validated_patterns_prerequisites/tasks/check_operators.yml` - Auto-installs GitOps if missing
6. `ansible/roles/validated_patterns_prerequisites/tasks/check_cluster_resources.yml` - Topology-aware validation
7. `ansible/roles/validated_patterns_prerequisites/tasks/check_required_storage_classes.yml` - Topology-aware storage validation
8. `ansible/roles/validated_patterns_jupyter_validator/defaults/main.yml` - Version detection
9. `ansible/roles/validated_patterns_jupyter_validator/tasks/deploy_operator.yml` - Version-based overlay selection
10. `ansible/roles/validated_patterns_deploy_cluster_resources/tasks/deploy_cross_namespace_rbac.yml` - Values-driven NooBaa RBAC (reads objectStore.enabled + checks namespace)
11. `values-hub.yaml` - Added cluster topology configuration, objectStore.enabled=true for all topologies
12. `README.md` - Documented topology support

## Verification

### HA Cluster Verification

```bash
# Detect cluster
make show-cluster-info
# Expected: Topology=ha, Version=4.20

# Configure infrastructure
make configure-cluster
# Expected: MachineSet scaling, ODF installation

# Deploy pattern
make operator-deploy

# Validate
make argo-healthcheck
```

### SNO Cluster Verification

```bash
# Detect cluster
make show-cluster-info
# Expected: Topology=sno, Version=4.20

# Configure infrastructure
make configure-cluster
# Expected: Skip MachineSet, install ODF operator, create MCG-only StorageCluster, NooBaa Ready

# Edit values-hub.yaml with SNO overrides (cluster.topology, storage.modelStorage.storageClass)
# objectStore.enabled stays true (MCG provides S3)
# Then deploy
make operator-deploy

# Validate
make argo-healthcheck
```

## Related

- [ADR-029: Jupyter Notebook Validator Operator](029-jupyter-notebook-validator-operator.md)
- [ADR-030: Hybrid Management Model](030-hybrid-management-model.md)
- [ADR-043: GitOps-based Deployment Architecture](043-gitops-based-deployment-architecture.md)
- [ADR-056: Standalone MCG on SNO for Consistent S3 Storage](056-standalone-mcg-on-sno.md)

## References

- [OpenShift SNO Documentation](https://docs.openshift.com/container-platform/4.20/installing/installing_sno/install-sno-preparing-to-install-sno.html)
- [OpenShift Infrastructure API](https://docs.openshift.com/container-platform/4.20/rest_api/config_apis/infrastructure-config-openshift-io-v1.html)
- [OpenShift Data Foundation Requirements](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation/4.20/html/planning_your_deployment/infrastructure-requirements_rhodf)

## Decision Date

2026-02-23

## Decision Makers

- Platform Team
- Architecture Review Board
