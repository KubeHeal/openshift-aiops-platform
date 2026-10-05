# Runbook: Platform Deployment

**Owner**: Platform Engineering Team
**Risk Level**: High
**Last Updated**: 2026-09-29
**Last Tested**: 2026-09-29
**Approved By**: Platform Architect
**Version**: 1.0.0

---

## Quick Reference

| Attribute | Value |
|-----------|-------|
| **Execution Time** | ~25-45 minutes (varies by topology) |
| **Impact Window** | No downtime (new deployment) |
| **Rollback Time** | ~10 minutes |
| **Prerequisites** | Cluster-admin access, forked repository, values files |

---

## Scope and Use Case

### When to Use This Runbook

Deploy the OpenShift AI Ops Self-Healing Platform onto a fresh or existing OpenShift cluster. This runbook covers ROSA Classic, IPI HA, and SNO topologies.

**Triggers**:
- New cluster provisioning and platform bootstrap
- Platform redeployment after a full teardown
- Migration to a different cluster

### Expected Outcome

A fully operational self-healing platform with ArgoCD, coordination engine, model serving, Jupyter workbench, and Tekton pipelines deployed and validated.

### What This Does NOT Cover

- OpenShift cluster installation from scratch (use `scripts/create-rosa-cluster.sh` for ROSA)
- Individual operator upgrades (see [upgrade-and-maintenance.md](upgrade-and-maintenance.md))
- Incident response procedures (see [incident-response.md](incident-response.md))

---

## Prerequisites

### Required Access and Permissions

- [ ] OpenShift cluster with cluster-admin role
- [ ] GitHub account with a fork of the repository
- [ ] SSH or HTTPS access to the forked repository

### Required Tools

- [ ] `oc` CLI 4.20+ (OpenShift CLI)
- [ ] `kubectl` 1.31+ (installed with `oc`)
- [ ] `helm` 3.16.4+ (Kubernetes package manager)
- [ ] `yq` 4.44.6+ (YAML processor)
- [ ] `ansible-navigator` 24.11.0+ (Ansible execution)
- [ ] `podman` 4.9.4+ (container runtime)
- [ ] `git` 2.40+
- [ ] `make` 4.3+

**Verify tool installation**:

```bash
oc version --client
helm version --short
yq --version
ansible-navigator --version
podman --version
```

**Install all tools on RHEL 9/10**:

```bash
./scripts/install-prerequisites-rhel.sh
source ~/.bashrc
```

### Cluster Requirements

| Topology | Nodes | CPU | RAM | Storage |
|----------|-------|-----|-----|---------|
| **ROSA HA** | 2+ workers (m5.2xlarge minimum) | 16+ cores | Per instance type | AWS S3 (default) |
| **ROSA Single-Worker** | 1 worker (m5.2xlarge minimum) | 8+ cores | Per instance type | AWS S3 (default) |
| **IPI HA** | 6+ (3 control-plane, 3+ workers) | 24+ cores | 96+ GB | 500+ GB |
| **SNO** | 1 (all roles) | 8+ cores (16+ recommended) | 32+ GB (64+ recommended) | 120+ GB |

### Communication Requirements

- [ ] Notify the operations team before deployment
- [ ] Confirm no other deployments are in progress on the target cluster

---

## Pre-Flight Checks

**STOP**: Do NOT proceed unless ALL checks pass.

### Check 1: Verify Cluster Access

```bash
oc whoami
oc auth can-i create namespace --all-namespaces
```

Expected output: Your username and `yes`.

Pass criteria: Logged in with cluster-admin privileges.

Fail action: Run `oc login <cluster-api-url>` and verify your role bindings.

---

### Check 2: Detect Cluster Topology

```bash
make show-cluster-info
```

**Expected output** (HA example):

```
Cluster Information:
  Topology: ha
  OpenShift Version: 4.22
  Platform: AWS

Cluster Topology Information:
  Type: HA (HighlyAvailable)
  Control Plane: HighlyAvailable
  Infrastructure: HighlyAvailable
  Platform: AWS
```

Pass criteria: Topology is detected as `ha` or `sno`.

Fail action: Verify that `oc` is connected and that the cluster is healthy with `oc get nodes`.

---

### Check 3: Verify No Conflicting Deployments

```bash
oc get namespace self-healing-platform --ignore-not-found
oc get namespace self-healing-platform-hub --ignore-not-found
```

Pass criteria: Namespaces do not exist (fresh deployment) or are empty.

Fail action: Run cleanup before redeployment:

```bash
oc delete namespace self-healing-platform self-healing-platform-hub --ignore-not-found
```

---

### Check 4: Verify Values Files Exist

```bash
ls -l values-global.yaml values-hub.yaml values-secret.yaml
```

Pass criteria: All three files exist.

Fail action: Create them from examples:

```bash
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml
cp values-secret.yaml.example values-secret.yaml
```

The VP framework requires `values-secret.yaml` to exist, even if the file is empty. For public GitHub deployments the example file contents are sufficient.

---

## Alternative: KubeHeal Operator Install (Tier 1)

For a managed install without GitOps, install the kubeheal-operator from OperatorHub and create a single CR:

```yaml
apiVersion: aiops.kubeheal.io/v1alpha1
kind: SelfHealingPlatform
metadata:
  name: kubeheal
  namespace: self-healing-platform
spec:
  cluster:
    topology: "ha"
  coordinationEngine:
    enabled: true
  modelServing:
    enabled: true
  objectStore:
    enabled: true
    backend: "aws-s3"
```

The operator reconciles the Helm chart and manages the full lifecycle. Skip to the [Verification and Success Criteria](#verification-and-success-criteria) section after applying the CR.

See [ADR-064](../adrs/064-distribution-strategy-three-tier.md) for sample CRs for SNO and baremetal.

---

## Step-by-Step Procedure (Validated Patterns Path)

### Step 1: Fork and Clone Repository

**What this does**: Creates your own copy of the platform repository for customization.

**Commands**:

1. Fork the repository at `https://github.com/KubeHeal/openshift-aiops-platform` by clicking **Fork**.
2. Clone your fork:

```bash
git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
cd openshift-aiops-platform
```

**Verification**:

```bash
git remote -v
```

Confirm the origin URL points to YOUR fork.

> **WARNING**: Do NOT clone the upstream repository directly. ArgoCD reads from YOUR fork to deploy customized configurations.

---

### Step 2: Create and Configure Values Files

**What this does**: Configures deployment parameters for your cluster and fork.

**Commands**:

```bash
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml
cp values-secret.yaml.example values-secret.yaml
```

Update `repoURL` in **both** files to point to YOUR fork:

```bash
sed -i 's|https://github.com/KubeHeal/openshift-aiops-platform.git|https://github.com/YOUR-USERNAME/openshift-aiops-platform.git|g' values-global.yaml
sed -i 's|https://github.com/KubeHeal/openshift-aiops-platform.git|https://github.com/YOUR-USERNAME/openshift-aiops-platform.git|g' values-hub.yaml
```

**Verification**:

```bash
grep repoURL values-global.yaml
grep repoURL values-hub.yaml
```

Both should show YOUR fork URL.

---

### Step 3: Configure Topology-Specific Settings

**What this does**: Adjusts storage and GPU settings based on your cluster topology.

#### For SNO clusters:

Edit `values-hub.yaml`:

```yaml
cluster:
  topology: "sno"

storage:
  modelStorage:
    storageClass: "gp3-csi"

workbench:
  gpu:
    enabled: false
```

#### For HA clusters:

Default settings are correct. Optionally enable GPU if GPU nodes are available:

```yaml
cluster:
  topology: "ha"

workbench:
  gpu:
    enabled: true
```

**Verification**:

```bash
grep -A1 "topology:" values-hub.yaml
```

---

### Step 4: Get the Execution Environment

**What this does**: Provides the Ansible execution environment container with all required dependencies.

**Option A: Pull pre-built image (recommended)**:

```bash
podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest \
  openshift-aiops-platform-ee:latest
```

**Option B: Build locally**:

```bash
export ANSIBLE_HUB_TOKEN='your-token-here'
podman login registry.redhat.io
make token
make build-ee
```

**Verification**:

```bash
podman images | grep openshift-aiops-platform-ee
```

Expected: Image listed with `latest` tag.

---

### Step 5: Configure Cluster Infrastructure

**What this does**: Installs OpenShift Data Foundation and scales worker nodes (HA only).

```bash
make configure-cluster
```

**Expected duration**: 10-15 minutes (HA) or 5-7 minutes (SNO).

**Expected output** (HA):

```
[INFO] Installing ODF operator...
[INFO] Creating StorageCluster...
[OK] ODF StorageCluster is ready
[OK] Storage classes available
```

**Skip ODF** (for ROSA with native S3):

```bash
./scripts/configure-cluster-infrastructure.sh --skip-odf
```

**Skip GPU operators** (clusters without GPU nodes):

```bash
./scripts/configure-cluster-infrastructure.sh --skip-gpu
```

The script auto-detects GPU nodes by checking labels and instance types (g4dn, g5, p3, p4, p5). If no GPU nodes exist, GPU operator installation is skipped automatically.

**Verification**:

```bash
oc get storageclass
oc get csv -n openshift-storage | grep odf
```

---

### Step 6: Validate Prerequisites

**What this does**: Confirms all cluster-level requirements are met.

```bash
make check-prerequisites
```

**Expected output**: All checks pass with green checkmarks.

If failed: Address each failing check. Common issues include missing storage classes or insufficient node capacity.

---

### Step 7: Deploy Ansible Prerequisites

**What this does**: Creates namespaces, RBAC, ServiceAccounts, and grants ArgoCD cluster-admin permissions.

```bash
make operator-deploy-prereqs
```

**Expected duration**: 2-3 minutes.

**Expected output**:

```
PLAY [Deploy Prerequisites] ****************************************************
...
PLAY RECAP *********************************************************************
localhost : ok=XX changed=XX
```

**Verification**:

```bash
oc get namespace self-healing-platform
oc get namespace self-healing-platform-hub
oc get sa -n self-healing-platform | grep self-healing-operator
oc get clusterrolebinding hub-gitops-argocd-application-controller-cluster-admin
```

> **WARNING**: This step is MANDATORY. Without it, ArgoCD sync will fail with "serviceaccount not found" errors.

---

### Step 8: Deploy Platform via Validated Patterns Operator

**What this does**: Installs the VP Operator, creates the Pattern CR, and triggers ArgoCD deployment of all components.

```bash
make operator-deploy
```

**Expected duration**: 5-10 minutes for initial sync.

**Verification**:

```bash
oc wait --for=jsonpath='{.kind}'=Application \
  application/self-healing-platform -n self-healing-platform-hub --timeout=120s
```

---

### Step 9: Monitor ArgoCD Sync

**What this does**: Watches the ArgoCD application until it reaches a healthy state.

```bash
watch -n 5 'oc get application.argoproj.io self-healing-platform \
  -n self-healing-platform-hub \
  -o jsonpath="{.status.sync.status} - {.status.health.status}"'
```

**Expected progression**:

1. `Unknown - Unknown`
2. `OutOfSync - Missing`
3. `Synced - Progressing`
4. `Synced - Healthy`

Press `Ctrl+C` when you see `Synced - Healthy`.

**If stuck in OutOfSync**, trigger a manual sync:

```bash
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite
```

---

### Step 10: Validate Deployment

**What this does**: Runs automated health checks across all platform components.

```bash
make argo-healthcheck
```

**Expected output**:

```
ArgoCD Application Health Check
Application: self-healing-platform
Status: Healthy
Sync: Synced
```

---

## Verification and Success Criteria

### Post-Deployment Checks

#### Check 1: All Pods Running

```bash
oc get pods -n self-healing-platform
```

**Success criteria**: All pods show `Running` or `Completed` status. No `CrashLoopBackOff` or `Error` states.

---

#### Check 2: Coordination Engine Healthy

```bash
oc exec -n self-healing-platform deployment/self-healing-coordination-engine -- \
  curl -s http://localhost:8080/health
```

**Success criteria**: Returns `{"status":"healthy"}` or similar JSON response with healthy status.

---

#### Check 3: InferenceServices Ready

```bash
oc get inferenceservices -n self-healing-platform
```

**Success criteria**: All InferenceServices show `READY=True`. This may take 5-10 minutes after initial deployment.

---

#### Check 4: Jupyter Workbench Accessible

```bash
oc get pods -n self-healing-platform | grep workbench
```

**Success criteria**: Workbench pod is `Running` with `1/1` containers ready.

Access the workbench:

```bash
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
```

Open `http://localhost:8888` in a browser.

---

#### Check 5: Run Tekton Validation Pipeline (Optional)

```bash
tkn pipeline start deployment-validation-pipeline --showlog -n self-healing-platform
```

**Success criteria**: All 26 validation checks pass.

---

#### Check 6: Cleanup Extra Namespaces

```bash
oc delete namespace self-healing-platform-example imperative --ignore-not-found=true
```

---

## Rollback Procedure

### When to Rollback

Execute rollback if ANY of these occur:

- ArgoCD application remains in `Degraded` or `Unknown` state for more than 15 minutes after sync
- Multiple operators are in `Failed` state
- Critical pods (`coordination-engine`, `workbench`) are in `CrashLoopBackOff`

### Rollback Steps

#### Step 1: Delete Pattern CR

```bash
oc delete pattern self-healing-platform -n openshift-operators --ignore-not-found
```

#### Step 2: Delete ArgoCD Applications

```bash
oc delete applications --all -n self-healing-platform-hub
```

#### Step 3: Delete Platform Namespaces

> **WARNING**: This deletes all platform data including trained models and notebooks.

```bash
oc delete namespace self-healing-platform --ignore-not-found
oc delete namespace self-healing-platform-hub --ignore-not-found
```

#### Step 4: Clean Up Cluster-Scoped Resources

```bash
oc delete clusterrolebinding -l app.kubernetes.io/part-of=self-healing-platform
```

#### Step 5: Verify Removal

```bash
oc get namespace | grep self-healing
oc get applications -A | grep self-healing
```

Both commands should return no results.

---

## Troubleshooting

### Issue 1: Values Files Not Found

**Symptoms**: `make` commands fail with `values-global.yaml: No such file or directory`.

**Solution**:

```bash
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml
cp values-secret.yaml.example values-secret.yaml
```

Update `repoURL` in both files to point to YOUR fork.


---

### Issue 2: ArgoCD ClusterRoleBinding Error

**Symptoms**: Error about `ClusterRoleBinding cannot be managed when in namespaced mode`.

**Solution**:

```bash
make operator-deploy-prereqs
```

If the error persists, manually create the ClusterRoleBinding:

```bash
oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: hub-gitops-argocd-application-controller-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: hub-gitops-argocd-application-controller
  namespace: self-healing-platform-hub
EOF
```

---

### Issue 3: TooManyOperatorGroups

**Symptoms**: Operators stuck in `Failed` state with `TooManyOperatorGroups` error.

**Solution**:

```bash
oc get operatorgroups -n openshift-operators
oc delete operatorgroup jupyter-validator-operatorgroup -n openshift-operators
```

Wait 60 seconds for operators to reconcile:

```bash
oc get csv -n openshift-operators
```

---

### Issue 4: Workbench Pod Pending on SNO

**Symptoms**: `self-healing-workbench-0` stuck in `Pending` with `Insufficient nvidia.com/gpu`.

**Solution**:

1. Verify `values-hub.yaml` has `workbench.gpu.enabled: false` for SNO.
2. Commit and push the fix.
3. Trigger ArgoCD sync:

```bash
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite
```

---

### Escalation Path

| Severity | First Contact | Response Time | Next Escalation |
|----------|---------------|---------------|-----------------|
| **P1 (Critical)** | On-call engineer | Immediate | Engineering Manager (15 min) |
| **P2 (High)** | Team Slack #aiops-platform | 30 minutes | Team Lead (1 hour) |
| **P3 (Medium)** | Team Slack #aiops-platform | 2 hours | N/A |

---

## Post-Execution Tasks

### Immediate (Within 5 Minutes)

- [ ] Confirm all ArgoCD applications show `Synced - Healthy`
- [ ] Verify coordination engine health endpoint responds
- [ ] Notify operations team that deployment is complete

### Within 24 Hours

- [ ] Run the full Tekton validation pipeline
- [ ] Monitor model training pipeline runs (auto-triggered on first deploy)
- [ ] Verify InferenceServices reach `READY=True`
- [ ] Review platform logs for warnings

### Within 1 Week

- [ ] Run platform readiness validation notebook (`notebooks/00-setup/00-platform-readiness-validation.ipynb`)
- [ ] Verify model inference endpoints return predictions
- [ ] Document any deviations from this runbook
- [ ] Update this runbook if procedures changed

---

## Automation

### Automated Steps

- **Step 5 (Configure Infrastructure)**: `make configure-cluster`
- **Step 7 (Ansible Prerequisites)**: `make operator-deploy-prereqs`
- **Step 8 (Deploy Platform)**: `make operator-deploy`
- **Step 10 (Validate)**: `make argo-healthcheck`

### Script Locations

- Cluster provisioning: `scripts/create-rosa-cluster.sh`
- Infrastructure config: `scripts/configure-cluster-infrastructure.sh`
- Post-deployment validation: `scripts/post-deployment-validation.sh`
- Topology detection: `scripts/detect-cluster-topology.sh`

---

## Appendix

### Related Runbooks

- [Model Training Operations](model-training-operations.md)
- [Incident Response](incident-response.md)
- [Upgrade and Maintenance](upgrade-and-maintenance.md)

### Reference Documentation

- [CLAUDE.md](../../CLAUDE.md) - AI agent quick reference
- [Fresh Cluster Deployment Guide](../guides/FRESH-CLUSTER-DEPLOYMENT.md)
- [Troubleshooting Guide](../guides/TROUBLESHOOTING-GUIDE.md)
- [ADR-019: Validated Patterns Framework](../adrs/019-validated-patterns-framework-adoption.md)
- [ADR-030: Hybrid Management Model](../adrs/030-hybrid-management-model-namespaced-argocd.md)

### Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-29 | Platform Engineering | Initial version |

---

**Last Reviewed**: 2026-09-29
**Next Review**: 2026-12-29
**Feedback**: Report issues at https://github.com/KubeHeal/openshift-aiops-platform/issues
