# Troubleshooting Guide

This guide documents common issues encountered during deployment and operation of the OpenShift AI Ops Self-Healing Platform, along with their solutions.

## Table of Contents

1. [Operator Failures](#operator-failures)
2. [ArgoCD Sync Issues](#argocd-sync-issues)
3. [Deployment Failures](#deployment-failures)
4. [Storage Issues](#storage-issues)
5. [Network and Connectivity](#network-and-connectivity)
6. [Getting Help](#getting-help)

---

## Operator Failures

### Issue: TooManyOperatorGroups

**Symptoms:**
- Multiple operators failing in `openshift-operators` namespace
- Error message: `TooManyOperatorGroups: operatorgroup jupyter-validator-operatorgroup...`
- Operators stuck in "Failed" state
- CSV (ClusterServiceVersion) status shows conflict

**Example Error:**
```
install strategy failed: InstallPlan approval needed: Waiting for install approval
status: InstallPlanFailed, reason: TooManyOperatorGroups, message:
operatorgroup jupyter-validator-operatorgroup is intersected by multiple operatorgroups
```

**Root Cause:**
The Jupyter Notebook Validator Operator creates an extra OperatorGroup (`jupyter-validator-operatorgroup`) that conflicts with the default `global-operators` OperatorGroup. OpenShift only allows one OperatorGroup per namespace.

**Diagnosis:**
```bash
# Check for multiple OperatorGroups
oc get operatorgroups -n openshift-operators

# Expected output should show ONLY:
# NAME              AGE
# global-operators  XXh

# If you see jupyter-validator-operatorgroup, that's the problem
```

**Fix:**
```bash
# Delete the conflicting OperatorGroup
oc delete operatorgroup jupyter-validator-operatorgroup -n openshift-operators

# Wait 30-60 seconds for operators to reconcile
oc get csv -n openshift-operators --watch
```

**Prevention:**
This issue should be fixed in future releases of the `validated_patterns_jupyter_validator` role. Track progress in the project issues.

**Verification:**
```bash
# All CSVs should be in "Succeeded" phase
oc get csv -n openshift-operators

# No pending InstallPlans
oc get installplans -n openshift-operators
```

---

## ArgoCD Sync Issues

### Issue: ClusterRoleBinding Cannot Be Managed in Namespaced Mode

**Symptoms:**
- ArgoCD application shows `ComparisonError`
- Error: `Failed to load live state: Cluster level ClusterRoleBinding "..." can not be managed when in namespaced mode`
- Application sync status shows "Unknown" or "OutOfSync"
- Retrying attempts fail with same error

**Example Error:**
```
ComparisonError: Failed to load live state: Cluster level ClusterRoleBinding
"self-healing-platform-mcp-prometheus" can not be managed when in namespaced mode.
Retrying attempt #2 at 2:55PM.
```

**Root Cause:**
The hub-gitops ArgoCD instance runs in **namespaced mode** (scoped to `self-healing-platform-hub` namespace) but the platform requires managing cluster-scoped resources (ClusterRole, ClusterRoleBinding). This is an architectural limitation documented in [ADR-030](../adrs/030-hybrid-management-model-namespaced-argocd.md).

**Diagnosis:**
```bash
# Check ArgoCD application status
oc get applications -n self-healing-platform-hub

# View detailed error
oc describe application self-healing-platform -n self-healing-platform-hub

# Check if hub-gitops controller has cluster-admin permissions
oc get clusterrolebinding | grep hub-gitops-argocd-application-controller
```

**Fix (Automated):**
This issue should be automatically fixed by the `operator-deploy-prereqs` playbook. If you're still seeing this error:

```bash
# Re-run prerequisites deployment
make operator-deploy-prereqs
```

**Fix (Manual - If Automated Fix Fails):**
```bash
# Grant cluster-admin to hub-gitops ArgoCD controller
oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: hub-gitops-argocd-application-controller-cluster-admin
  labels:
    app.kubernetes.io/component: application-controller
    app.kubernetes.io/instance: hub-gitops
    app.kubernetes.io/name: argocd-application-controller
    app.kubernetes.io/part-of: argocd
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

**Verification:**
```bash
# Check ClusterRoleBinding exists
oc get clusterrolebinding hub-gitops-argocd-application-controller-cluster-admin

# Watch ArgoCD application sync (should succeed within 1-2 minutes)
watch -n 5 'oc get applications -n self-healing-platform-hub'
```

**Related Documentation:**
- [ADR-030: Hybrid Management Model for Namespaced ArgoCD](../adrs/030-hybrid-management-model-namespaced-argocd.md)

### Issue: ArgoCD Application Stuck in "Unknown" Sync Status

**Symptoms:**
- Application shows `syncStatus: Unknown`
- Application health shows `healthStatus: Missing`
- No error messages visible in ArgoCD UI
- Pattern CR shows application but no pods are created

**Diagnosis:**
```bash
# Check Pattern CR status
oc get pattern self-healing-platform -n openshift-operators -o yaml | grep -A 20 "status:"

# Check ArgoCD application details
oc describe application self-healing-platform -n self-healing-platform-hub

# Check ArgoCD controller logs
oc logs -n self-healing-platform-hub deployment/hub-gitops-application-controller --tail=100
```

**Common Causes:**
1. **Git repository URL is incorrect** (most common)
   - Check `values-global.yaml` and `values-hub.yaml` for correct `repoURL`
   - Verify repository is accessible: `git ls-remote <repoURL>`

2. **ArgoCD doesn't have permissions to create namespace**
   - Check namespace exists: `oc get namespace self-healing-platform`
   - Check ArgoCD has RBAC: `oc get rolebinding -n self-healing-platform | grep argocd`

3. **Helm chart rendering fails**
   - Test locally: `helm template test charts/hub -f values-global.yaml -f values-hub.yaml`

**Fix:**
```bash
# For incorrect Git URL:
# 1. Update values-global.yaml and values-hub.yaml with correct repoURL
# 2. Re-deploy pattern
make operator-deploy

# For missing namespace:
oc create namespace self-healing-platform

# Manually trigger ArgoCD sync
oc patch application self-healing-platform -n self-healing-platform-hub \
  --type merge -p '{"operation":{"sync":{"revision":"main"}}}'
```

---

## Deployment Failures

### Issue: ServiceAccount Not Found During ArgoCD Sync

**Symptoms:**
- ArgoCD sync hook fails
- Error: `serviceaccount "self-healing-operator" not found`
- Deployment fails during post-sync or pre-sync hooks
- Pattern CR shows "Degraded" status

**Example Error:**
```
error syncing application: sync hook "noobaa-credentials-init" failed:
serviceaccount "self-healing-operator" not found
```

**Root Cause:**
ArgoCD sync hooks (like `noobaa-credentials-init`) require ServiceAccounts and RBAC that don't exist yet, creating a circular dependency. This is fixed by deploying namespaced RBAC resources **before** ArgoCD syncs (Hybrid Management Model - ADR-030).

**Fix:**
```bash
# Re-run prerequisites (includes namespaced RBAC deployment)
make operator-deploy-prereqs

# Verify ServiceAccounts exist
oc get sa -n self-healing-platform | grep self-healing-operator

# Retry ArgoCD sync
oc patch application self-healing-platform -n self-healing-platform-hub \
  --type merge -p '{"operation":{"sync":{"revision":"main"}}}'
```

**Prevention:**
Always run `make operator-deploy-prereqs` before `make operator-deploy`. The Makefile enforces this as a dependency, but if running Ansible playbooks directly, ensure proper order.

### Issue: External Secrets Not Syncing

**Symptoms:**
- ExternalSecret resource shows `SecretSyncedError`
- Kubernetes Secret is not created
- Pods fail to start with "secret not found" errors

**Diagnosis:**
```bash
# Check ExternalSecret status
oc get externalsecrets -n self-healing-platform

# View detailed error
oc describe externalsecret <name> -n self-healing-platform

# Check SecretStore
oc get secretstore -n self-healing-platform
oc describe secretstore <name> -n self-healing-platform

# Check External Secrets Operator logs
oc logs -n external-secrets-operator deployment/external-secrets-operator --tail=100
```

**Common Causes:**
1. **SecretStore not configured properly**
   - Backend credentials missing or incorrect
   - SecretStore pointing to wrong namespace

2. **Backend secret doesn't exist**
   - For Kubernetes backend: Check source secret exists
   - For Vault: Verify path and credentials

3. **RBAC permissions missing**
   - External Secrets Operator needs ClusterRole to read secrets

**Fix:**
```bash
# For Kubernetes backend:
# Ensure source secrets exist in the correct namespace
oc get secrets -n <source-namespace>

# Verify SecretStore configuration
oc get secretstore -n self-healing-platform -o yaml

# Check RBAC
oc get clusterrole | grep external-secrets
oc get clusterrolebinding | grep external-secrets

# If RBAC missing, re-run prerequisites
make operator-deploy-prereqs
```

---

## Storage Issues

### Issue: PVCs Stuck in "Pending" State

**Symptoms:**
- PersistentVolumeClaims show `Pending` status
- Pods fail to start with "PVC not bound" errors
- Workbench notebook fails to launch

**Diagnosis:**
```bash
# Check PVC status
oc get pvc -n self-healing-platform

# View detailed events
oc describe pvc <pvc-name> -n self-healing-platform

# Check available storage classes
oc get storageclass

# Check if ODF is installed
oc get csv -n openshift-storage | grep odf
```

**Common Causes:**
1. **No default StorageClass set**
2. **Insufficient storage capacity**
3. **ODF not installed or unhealthy**
4. **Node affinity/selector issues**

**Fix:**
```bash
# Check for default StorageClass
oc get storageclass
# One should show (default) next to it

# If no default, set one:
oc patch storageclass ocs-storagecluster-ceph-rbd \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Check ODF health
oc get cephcluster -n openshift-storage
oc get pods -n openshift-storage | grep -i osd

# For capacity issues, check ODF dashboard:
# OpenShift Console → Storage → Data Foundation
```

---

## Network and Connectivity

### Issue: Cannot Access Gitea Repository

**Symptoms:**
- `git clone` or `git push` fails with authentication error
- ArgoCD cannot sync from Gitea
- 403 Forbidden or 401 Unauthorized errors

**Diagnosis:**
```bash
# Check Gitea route
oc get route -n gitea

# Test Gitea connectivity
curl -I https://$(oc get route gitea -n gitea -o jsonpath='{.spec.host}')

# Check Gitea credentials secret
oc get secret gitea-credentials -n self-healing-platform -o yaml
```

**Fix:**
```bash
# Re-run secrets management configuration
make operator-deploy-prereqs

# Or manually create Gitea credentials:
# 1. Get Gitea admin password:
oc get secret gitea-admin-credentials -n gitea -o jsonpath='{.data.password}' | base64 -d

# 2. Test authentication:
GITEA_URL=$(oc get route gitea -n gitea -o jsonpath='{.spec.host}')
curl -u admin:<password> https://${GITEA_URL}/api/v1/user
```

### Issue: Cannot Access Prometheus Metrics

**Symptoms:**
- Notebooks fail with "Prometheus connection refused"
- Coordination engine cannot query metrics
- 403 Forbidden when accessing Prometheus

**Diagnosis:**
```bash
# Check Prometheus route
oc get route prometheus-k8s -n openshift-monitoring

# Check ServiceAccount has cluster-monitoring-view role
oc get clusterrolebinding | grep self-healing-workbench-prometheus

# Test from within cluster
oc exec -it self-healing-workbench-0 -n self-healing-platform -- \
  curl -k https://prometheus-k8s.openshift-monitoring.svc:9091/api/v1/query?query=up
```

**Fix:**
```bash
# Re-run prerequisites to create RBAC
make operator-deploy-prereqs

# Verify ClusterRoleBinding exists
oc get clusterrolebinding self-healing-workbench-prometheus

# If missing, create manually:
oc create clusterrolebinding self-healing-workbench-prometheus \
  --clusterrole=cluster-monitoring-view \
  --serviceaccount=self-healing-platform:self-healing-workbench
```

---

## Getting Help

### Diagnostic Data Collection

When reporting issues, collect the following:

```bash
# 1. Pattern CR status
oc get pattern self-healing-platform -n openshift-operators -o yaml > pattern-status.yaml

# 2. ArgoCD application status
oc get applications -A -o yaml > argocd-apps.yaml

# 3. Operator status
oc get csv -n openshift-operators > operators.txt

# 4. Pod status
oc get pods -n self-healing-platform > pods.txt
oc get pods -n self-healing-platform-hub > argocd-pods.txt

# 5. Events
oc get events -n self-healing-platform --sort-by='.lastTimestamp' > events.txt

# 6. ArgoCD controller logs
oc logs -n self-healing-platform-hub deployment/hub-gitops-application-controller \
  --tail=200 > argocd-controller.log
```

### Support Channels

- **GitHub Issues**: [openshift-aiops-platform/issues](https://github.com/KubeHeal/openshift-aiops-platform/issues)
- **Documentation**: [docs/adrs/](../adrs/) - Architectural Decision Records
- **Development Guide**: [AGENTS.md](../../AGENTS.md) - Comprehensive platform guide

### Related Documentation

- [Junior Developer Deployment Guide](JUNIOR-DEVELOPER-DEPLOYMENT-GUIDE.md)
- [ADR-030: Hybrid Management Model](../adrs/030-hybrid-management-model-namespaced-argocd.md)
- [ADR-031: Deployment Lessons Learned](../adrs/ADR-031-deployment-lessons-learned.md)
- [Deployment Guide](../../DEPLOYMENT.md)

---

**Last Updated**: 2025-12-10
**Version**: 1.0
