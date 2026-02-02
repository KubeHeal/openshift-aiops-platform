# Junior Developer Deployment Testing Guide

This guide provides step-by-step instructions for deploying the OpenShift AI Ops Self-Healing Platform for testing purposes. It documents expected issues and their solutions, making it suitable for junior developers learning the platform.

## 📋 Prerequisites

Before starting, ensure you have:

- ✅ Access to an OpenShift 4.18+ cluster with admin permissions
- ✅ `oc` CLI installed and configured
- ✅ Git installed
- ✅ Red Hat Ansible Automation Hub token ([get one here](https://console.redhat.com/ansible/automation-hub/token))
- ✅ Cluster meets minimum requirements:
  - 6+ nodes (3 control-plane, 3+ workers)
  - 24+ CPU cores total
  - 96+ GB RAM total
  - OpenShift Data Foundation (ODF) installed

### Verify Cluster Access

```bash
# Check you're logged into OpenShift
oc whoami
oc cluster-info

# Verify you have admin permissions
oc auth can-i '*' '*' --all-namespaces
# Should output: yes

# Check OpenShift version (should be 4.18+)
oc version
```

---

## 🚀 Deployment Steps

### Step 1: Fork and Clone the Repository

**⚠️ CRITICAL**: Always fork the repository first before testing deployment. This allows you to customize values files and maintain your own test configuration.

#### Option A: Fork from GitHub (Recommended)

```bash
# 1. Fork the repository on GitHub
# Visit: https://github.com/KubeHeal/openshift-aiops-platform
# Click the "Fork" button in the top-right corner

# 2. Clone YOUR fork to a new directory
cd ~/
git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git openshift-aiops-platform-deployment-testing
cd openshift-aiops-platform-deployment-testing
```

#### Option B: Fork in Gitea (For Air-Gapped/Local Testing)

```bash
# 1. Access Gitea UI
GITEA_URL=$(oc get route gitea -n gitea -o jsonpath='{.spec.host}' 2>/dev/null)
echo "Gitea URL: https://${GITEA_URL}"

# 2. Log into Gitea (get credentials from giteuserpass.md or ask instructor)

# 3. Fork the repository in Gitea UI
# - Navigate to: https://gitea-with-admin-gitea.apps.<cluster-domain>/takinosh/openshift-aiops-platform
# - Click "Fork" button
# - Create fork under your username

# 4. Clone YOUR Gitea fork
cd ~/
git clone https://gitea-with-admin-gitea.apps.cluster-pvbs6.pvbs6.sandbox3005.opentlc.com/YOUR-USERNAME/openshift-aiops-platform.git openshift-aiops-platform-deployment-testing
cd openshift-aiops-platform-deployment-testing
```

**⚠️ Important**: Use a new directory (`openshift-aiops-platform-deployment-testing`) to avoid conflicts with any existing clones.

### Step 2: Configure Values Files

The platform requires you to configure Git repository URLs. The repository includes template files that you need to copy and customize:

```bash
# Copy template files
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml
```

**Edit `values-global.yaml`** (line 98 - update `git.repoURL`):
```bash
vi values-global.yaml
```

Change:
```yaml
git:
  repoURL: "https://gitea-with-admin-gitea.apps.cluster-pvbs6..."
```

To (use the Gitea URL you cloned from):
```yaml
git:
  repoURL: "https://gitea-with-admin-gitea.apps.cluster-pvbs6.pvbs6.sandbox3005.opentlc.com/takinosh/openshift-aiops-platform.git"
```

**Edit `values-hub.yaml`** (line 57 - update `applications.self-healing-platform.repoURL`):
```bash
vi values-hub.yaml
```

Change the `repoURL` to match the same Gitea URL.

**💡 Why is this needed?**
ArgoCD uses these URLs to sync the application. If they're incorrect, ArgoCD won't be able to pull the Helm charts and deployment will fail with `syncStatus: Unknown`.

### Step 3: Set Your Ansible Hub Token

Get your token from [console.redhat.com](https://console.redhat.com/ansible/automation-hub/token), then:

```bash
# Option 1: Export as environment variable
export ANSIBLE_HUB_TOKEN='your-token-here'

# Option 2: Create a token file
echo 'your-token-here' > token
```

**Verify token is set:**
```bash
# If using environment variable:
echo $ANSIBLE_HUB_TOKEN

# If using token file:
cat token
```

### Step 4: Build the Execution Environment

This builds a containerized environment with all Ansible dependencies:

```bash
make build-ee
```

**Expected output:**
```
Building execution environment...
STEP 1/8: FROM quay.io/ansible/creator-ee:latest
...
Successfully tagged openshift-aiops-platform-ee:latest
```

**Time**: ~5-10 minutes (depending on network speed)

**Troubleshooting:**
- If it fails with "token not found", verify Step 3
- If it fails with "permission denied", ensure Docker/Podman is running

### Step 5: Validate Cluster Prerequisites

This checks if your cluster meets all requirements:

```bash
make check-prerequisites
```

**Expected checks:**
- ✅ OpenShift version 4.18+
- ✅ Required operators installed (OpenShift AI, GPU Operator, etc.)
- ✅ Sufficient cluster resources
- ✅ Storage classes available
- ✅ Network connectivity

**If any check fails**, review the error message and fix before proceeding.

### Step 6: Run Ansible Prerequisites (CRITICAL)

This step creates ServiceAccounts, RBAC, secrets, and cluster-scoped resources **before** ArgoCD deploys applications:

```bash
make operator-deploy-prereqs
```

**What this does:**
1. Validates prerequisites
2. Deploys common infrastructure (Helm, External Secrets Operator)
3. Configures secrets management
4. Deploys Jupyter Notebook Validator Operator
5. **Deploys cluster-scoped RBAC resources** (fixes ArgoCD namespaced mode issues)

**Expected output:**
```
✅ Ansible Prerequisites Complete
✅ Prerequisites validated
✅ Common infrastructure deployed
✅ Secrets management configured
✅ Cluster-scoped resources deployed (RBAC, KServe)
```

**Time**: ~3-5 minutes

**⚠️ CRITICAL**: Do NOT skip this step! It creates resources that ArgoCD sync hooks require, preventing circular dependency errors.

### Step 7: Deploy the Platform

This deploys the pattern using the Validated Patterns Operator:

```bash
make operator-deploy
```

**What this does:**
1. Runs `operator-deploy-prereqs` automatically (if not already run)
2. Deploys the pattern-install Helm chart
3. Creates the Pattern CR
4. ArgoCD syncs all applications

**Expected output:**
```
Pattern self-healing-platform deployed successfully
Check status: make argo-healthcheck
```

**Time**: ~10-15 minutes for full deployment

**⚠️ Note**: This step automatically runs Step 6 as a dependency. However, running them separately (Steps 6 then 7) helps with troubleshooting.

### Step 8: Validate Deployment

Check if all ArgoCD applications are synced and healthy:

```bash
make argo-healthcheck
```

**Expected output:**
```
openshift-gitops self-healing-platform-hub -> Sync: Synced - Health: Healthy
self-healing-platform-hub self-healing-platform -> Sync: Synced - Health: Healthy
```

**Alternative validation:**
```bash
# Check Pattern CR status
oc get pattern self-healing-platform -n openshift-operators

# Check all ArgoCD applications
oc get applications -A

# Check all pods are running
oc get pods -n self-healing-platform
oc get pods -n self-healing-platform-hub
```

### Step 9: Monitor Deployment Progress

If applications are still syncing, watch their progress:

```bash
# Watch ArgoCD applications (Ctrl+C to exit)
watch -n 5 'oc get applications -A'

# Watch pods in self-healing-platform namespace
watch -n 5 'oc get pods -n self-healing-platform'

# View ArgoCD controller logs (if troubleshooting)
oc logs -n self-healing-platform-hub deployment/hub-gitops-application-controller --tail=50 -f
```

---

## 🎉 Success Criteria

Your deployment is successful when:

- ✅ All ArgoCD applications show `Synced` and `Healthy`
- ✅ Pattern CR shows healthy applications
- ✅ All operators in `openshift-operators` are in "Succeeded" state
- ✅ All pods in `self-healing-platform` namespace are `Running`
- ✅ No errors in ArgoCD application status

**Verify:**
```bash
# Check Pattern CR
oc get pattern self-healing-platform -n openshift-operators -o jsonpath='{.status.applications}' | jq '.'

# Check operators
oc get csv -n openshift-operators

# Check pods
oc get pods -n self-healing-platform
```

---

## 🔧 Expected Issues and Solutions

During deployment, you may encounter these **expected** issues. Don't panic! Each has a documented solution.

### Issue 1: TooManyOperatorGroups

**When**: After Step 6 (operator-deploy-prereqs)
**Symptoms**: 8 operators failing with "TooManyOperatorGroups" error

**Diagnosis:**
```bash
oc get csv -n openshift-operators | grep -i fail

# Check for extra OperatorGroup
oc get operatorgroups -n openshift-operators
```

**Solution:**
```bash
oc delete operatorgroup jupyter-validator-operatorgroup -n openshift-operators

# Wait 30-60 seconds, then verify
oc get csv -n openshift-operators
```

**Why this happens**: The Jupyter Notebook Validator Operator creates an extra OperatorGroup that conflicts with `global-operators`.

**Reference**: [Troubleshooting Guide - OperatorGroups](TROUBLESHOOTING-GUIDE.md#issue-toomanyoperatorgroups)

### Issue 2: ArgoCD "ClusterRoleBinding Cannot Be Managed"

**When**: After Step 7 (operator-deploy)
**Symptoms**: ArgoCD application shows `ComparisonError`, error about "namespaced mode"

**Diagnosis:**
```bash
oc get applications -n self-healing-platform-hub
oc describe application self-healing-platform -n self-healing-platform-hub
```

**Solution (Automated):**
This should be automatically fixed by Step 6. If you still see the error:

```bash
# Re-run prerequisites
make operator-deploy-prereqs

# Check ClusterRoleBinding was created
oc get clusterrolebinding hub-gitops-argocd-application-controller-cluster-admin
```

**Solution (Manual - If Automated Fix Fails):**
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

**Why this happens**: The hub-gitops ArgoCD instance runs in namespaced mode but needs to manage cluster-scoped resources.

**Reference**: [Troubleshooting Guide - ArgoCD Sync Issues](TROUBLESHOOTING-GUIDE.md#issue-clusterrolebinding-cannot-be-managed-in-namespaced-mode)

### Issue 3: ArgoCD Application Stuck in "Unknown" Status

**When**: After Step 7, application never transitions to "Synced"
**Symptoms**: Application shows `syncStatus: Unknown`, `healthStatus: Missing`

**Most Common Cause**: Incorrect Git repository URL in values files

**Diagnosis:**
```bash
# Check what URL ArgoCD is using
oc get application self-healing-platform -n self-healing-platform-hub -o yaml | grep repoURL

# Test if repository is accessible
git ls-remote https://gitea-with-admin-gitea.apps.cluster-pvbs6.pvbs6.sandbox3005.opentlc.com/takinosh/openshift-aiops-platform.git
```

**Solution:**
1. Verify Step 2 was completed correctly
2. Check `values-global.yaml` (line 98) has correct `repoURL`
3. Check `values-hub.yaml` (line 57) has correct `repoURL`
4. Re-deploy if URLs were wrong:
   ```bash
   make operator-deploy
   ```

**Reference**: [Troubleshooting Guide - ArgoCD Unknown Status](TROUBLESHOOTING-GUIDE.md#issue-argocd-application-stuck-in-unknown-sync-status)

### Issue 4: ServiceAccount Not Found During Sync

**When**: ArgoCD sync hooks fail
**Symptoms**: Error "serviceaccount '...' not found"

**Solution:**
```bash
# Re-run prerequisites
make operator-deploy-prereqs

# Verify ServiceAccounts exist
oc get sa -n self-healing-platform | grep self-healing-operator
```

**Why this happens**: ArgoCD sync hooks require ServiceAccounts created in Step 6. If you skipped Step 6 or it failed partially, this error occurs.

**Reference**: [Troubleshooting Guide - ServiceAccount Not Found](TROUBLESHOOTING-GUIDE.md#issue-serviceaccount-not-found-during-argocd-sync)

### Issue 5: Extra Namespaces Created (UPSTREAM BEHAVIOR - EXPECTED)

**When**: After deployment completes
**Symptoms**:
- Extra namespace `self-healing-platform-example` exists with `example-gitops` ArgoCD instance
- Extra namespace `imperative` exists with Vault unsealing cronjob
- These are NOT part of your intended deployment

**Root Cause (IMPORTANT - READ THIS):**

This is **EXPECTED BEHAVIOR** from the upstream Validated Patterns framework (`oci://quay.io/validatedpatterns/clustergroup:0.9.38`).

The upstream chart has these **default values**:
```yaml
# From quay.io/validatedpatterns/clustergroup:0.9.38 values.yaml
clusterGroup:
  name: example  # <-- Default value creates "example" resources
```

When the Pattern CR renders, it creates resources for BOTH:
1. **Your configured values** (`clusterGroup.name: hub`) → `self-healing-platform-hub` ✅
2. **Upstream defaults** (`clusterGroup.name: example`) → `self-healing-platform-example` ⚠️

The `imperative` namespace contains Vault-related unsealing jobs and is also part of the upstream chart's default behavior.

**Diagnosis:**
```bash
# Check all self-healing namespaces
oc get namespaces | grep -E "self-healing|imperative"

# Expected output:
# imperative                      Active   <time>
# self-healing-platform           Active   <time>
# self-healing-platform-example   Active   <time>
# self-healing-platform-hub       Active   <time>
```

**Solution: Safe Cleanup (Post-Deployment)**
```bash
# These extra namespaces DO NOT affect deployment functionality
# Safe to delete after deployment completes:

oc delete namespace self-healing-platform-example imperative

# OR if you prefer to keep them (they're harmless):
# Do nothing - they consume minimal resources
```

**Correct Namespaces for Your Deployment:**
- ✅ `self-healing-platform` (application resources)
- ✅ `self-healing-platform-hub` (hub-gitops ArgoCD instance)
- ⚠️ `self-healing-platform-example` (upstream default - safe to delete)
- ⚠️ `imperative` (upstream default - safe to delete)

**Why We Don't "Fix" This in Code:**

This is **upstream Validated Patterns framework behavior**, not a bug in this repository. The issue is in:
- `oci://quay.io/validatedpatterns/clustergroup` (external OCI chart)
- `oci://quay.io/hybridcloudpatterns/pattern-install` (external OCI chart)

Attempting to override these defaults in our values files has proven unreliable due to the chart rendering logic.

**Best Practice:**
Include the cleanup commands in your post-deployment automation:
```bash
# In your deployment script, after 'make operator-deploy' completes:
sleep 30  # Wait for all resources to be created
oc delete namespace self-healing-platform-example imperative --ignore-not-found=true
```

**Verification:**
```bash
# Verify only your intended namespaces remain
oc get namespaces | grep self-healing

# Should see only:
# self-healing-platform           Active   <time>
# self-healing-platform-hub       Active   <time>
```

**Additional Context:**
- This behavior affects ALL Validated Patterns deployments using `clustergroup:0.9.*`
- The extra namespaces may recreate on subsequent deployments
- They do **NOT** interfere with your application functionality
- This is documented upstream: https://github.com/validatedpatterns/common

---

## 📊 Validation Checklist

Use this checklist to verify successful deployment:

### Operators
- [ ] All CSVs in `openshift-operators` are "Succeeded"
- [ ] No "TooManyOperatorGroups" errors
- [ ] External Secrets Operator is running
- [ ] OpenShift AI operator is healthy

```bash
oc get csv -n openshift-operators
oc get pods -n openshift-operators | grep -E "external-secrets|rhods"
```

### Pattern Deployment
- [ ] Pattern CR exists and shows healthy applications
- [ ] No errors in Pattern CR status

```bash
oc get pattern self-healing-platform -n openshift-operators
oc get pattern self-healing-platform -n openshift-operators -o yaml | grep -A 20 "status:"
```

### ArgoCD Applications
- [ ] `self-healing-platform-hub` application is Synced and Healthy
- [ ] `self-healing-platform` application is Synced and Healthy
- [ ] hub-gitops ArgoCD controller has cluster-admin ClusterRoleBinding

```bash
oc get applications -A
oc get clusterrolebinding | grep hub-gitops-argocd-application-controller
```

### Platform Namespace
- [ ] `self-healing-platform` namespace exists
- [ ] All pods are Running or Completed
- [ ] ServiceAccounts exist (self-healing-operator, self-healing-workbench, etc.)
- [ ] Secrets are synced (ExternalSecrets showing SecretSynced)
- [ ] **No extra namespaces** (e.g., `self-healing-platform-example`)

```bash
oc get namespace self-healing-platform
oc get pods -n self-healing-platform
oc get sa -n self-healing-platform
oc get externalsecrets -n self-healing-platform

# Check for extra namespaces (should only see self-healing-platform and self-healing-platform-hub)
oc get namespaces | grep self-healing

# If self-healing-platform-example exists, delete it:
# oc delete namespace self-healing-platform-example
```

### RBAC and Permissions
- [ ] ClusterRoles exist for workbench, operator
- [ ] ClusterRoleBindings grant necessary permissions
- [ ] Workbench has cluster-monitoring-view role

```bash
oc get clusterrole | grep self-healing
oc get clusterrolebinding | grep self-healing
```

---

## 🧪 Access and Testing

After successful deployment, you can access the platform components:

### Jupyter Notebooks

```bash
# Port-forward to workbench
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform

# Open in browser: http://localhost:8888
```

### ArgoCD UI

```bash
# Get ArgoCD URL
oc get route -n self-healing-platform-hub

# Get admin password
oc get secret hub-gitops-cluster -n self-healing-platform-hub \
  -o jsonpath='{.data.admin\.password}' | base64 -d
```

### Prometheus Metrics

```bash
# Test Prometheus access from workbench
oc exec -it self-healing-workbench-0 -n self-healing-platform -- \
  curl -k https://prometheus-k8s.openshift-monitoring.svc:9091/api/v1/query?query=up
```

---

## 🗑️ Cleanup (After Testing)

To remove the deployment and start fresh:

```bash
# Full cleanup (removes everything including GitOps)
make end2end-cleanup

# Or step-by-step:
# 1. Delete Pattern CR
oc delete pattern self-healing-platform -n openshift-operators

# 2. Delete ArgoCD applications
oc delete applications --all -n openshift-gitops
oc delete applications --all -n self-healing-platform-hub

# 3. Delete namespaces
oc delete namespace self-healing-platform
oc delete namespace self-healing-platform-hub

# 4. Verify cleanup
oc get pattern -A
oc get applications -A
```

---

## 📚 Additional Resources

- **[Troubleshooting Guide](TROUBLESHOOTING-GUIDE.md)** - Comprehensive problem-solving reference
- **[AGENTS.md](../../AGENTS.md)** - Complete platform architecture and development guide
- **[ADR-030](../adrs/030-hybrid-management-model-namespaced-argocd.md)** - Hybrid Management Model (why cluster RBAC is needed)
- **[Deployment Guide](../../DEPLOYMENT.md)** - Production deployment documentation
- **[README.md](../../README.md)** - Project overview and quick start

---

## 🆘 Getting Help

If you encounter issues not covered in this guide:

1. **Check the Troubleshooting Guide**: Most common issues are documented there
2. **Review ArgoCD logs**: `oc logs -n self-healing-platform-hub deployment/hub-gitops-application-controller`
3. **Collect diagnostic data**: See [Troubleshooting Guide - Diagnostic Data Collection](TROUBLESHOOTING-GUIDE.md#diagnostic-data-collection)
4. **Open a GitHub issue**: Include diagnostic data and error messages

---

## 📝 Reporting Results

After completing your testing, please report:

### Success Report
- ✅ Deployment completed successfully
- ✅ All validation checks passed
- ✅ Time taken for each step
- ✅ Any issues encountered and how you resolved them

### Failure Report
- ❌ Step where deployment failed
- ❌ Error messages (copy-paste full output)
- ❌ Diagnostic data:
  ```bash
  oc get pattern self-healing-platform -n openshift-operators -o yaml > pattern-status.yaml
  oc get applications -A > argocd-apps.txt
  oc get csv -n openshift-operators > operators.txt
  oc get pods -n self-healing-platform > pods.txt
  ```
- ❌ What you tried to fix the issue

---

**Good luck with your deployment testing! 🚀**

**Last Updated**: 2025-12-10
**Version**: 1.0
**Tested on**: OpenShift 4.18.21
self-healing-platform-example
