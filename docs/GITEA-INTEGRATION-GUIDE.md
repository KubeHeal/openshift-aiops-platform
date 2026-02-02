# Gitea Integration Guide
## Local Git Repository for OpenShift AIOps Platform

**Date:** 2025-11-02
**Status:** ✅ Deployed and Operational
**ADR:** [ADR-028: Gitea Local Git Repository](adrs/028-gitea-local-git-repository.md)

---

## Overview

Gitea is now deployed as a local Git repository for the OpenShift AIOps Platform, enabling GitOps workflows in air-gapped and disconnected environments. This guide provides complete instructions for accessing, configuring, and integrating Gitea with ArgoCD and Tekton pipelines.

---

## Deployment Summary

### ✅ Deployment Status

**Gitea Instance:** `gitea-with-admin`
**Namespace:** `gitea`
**Operator Namespace:** `gitea-operator`
**Deployment Date:** 2025-11-02
**Status:** Running and Operational

### 🌐 Access Information

**Gitea URL:** https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com

**Admin Credentials:**
- Username: `opentlc-mgr`
- Password: `pQF1QnP8pf3AzkoXY5wlm0C5XhzoHxaw`
- Email: `opentlc-mgr@redhat.com`

**User Credentials:**
- Username: `lab-user`
- Password: `VyyBum5vYrW95jgR`

**API Version:** Gitea 1.24.7

---

## Quick Start

### 1. Access Gitea Web UI

```bash
# Open Gitea in browser
open https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com

# Or get the URL from OpenShift
oc get route gitea-with-admin -n gitea -o jsonpath='{.spec.host}'
```

Login with admin credentials:
- Username: `opentlc-mgr`
- Password: `pQF1QnP8pf3AzkoXY5wlm0C5XhzoHxaw`

### 2. Verify Deployment

```bash
# Run validation script
./scripts/validate-gitea-deployment.sh --verbose

# Check Gitea API
curl -k https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/api/v1/version

# Check pods
oc get pods -n gitea

# Check route
oc get route -n gitea
```

### 3. Extract Credentials Programmatically

```bash
# Get admin password from Gitea CR status
oc get gitea gitea-with-admin -n gitea -o jsonpath='{.status.adminPassword}'

# Get user password from Gitea CR status
oc get gitea gitea-with-admin -n gitea -o jsonpath='{.status.userPassword}'

# Get Gitea URL
oc get gitea gitea-with-admin -n gitea -o jsonpath='{.status.giteaRoute}'
```

---

## Repository Management

### Create Organization

```bash
# Create organization via API
GITEA_URL="https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com"
ADMIN_USER="opentlc-mgr"
ADMIN_PASS="pQF1QnP8pf3AzkoXY5wlm0C5XhzoHxaw"

curl -k -X POST "$GITEA_URL/api/v1/orgs" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "validated-patterns",
    "full_name": "Validated Patterns",
    "description": "Validated Patterns Repositories"
  }'
```

### Mirror External Repository

```bash
# Mirror openshift-aiops-platform repository
curl -k -X POST "$GITEA_URL/api/v1/repos/migrate" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "clone_addr": "https://github.com/KubeHeal/openshift-aiops-platform.git",
    "repo_name": "openshift-aiops-platform",
    "mirror": true,
    "private": false,
    "uid": 1
  }'

# Mirror validated-patterns-ansible-toolkit
curl -k -X POST "$GITEA_URL/api/v1/repos/migrate" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "clone_addr": "https://github.com/tosin2013/validated-patterns-ansible-toolkit.git",
    "repo_name": "validated-patterns-ansible-toolkit",
    "mirror": true,
    "private": false,
    "uid": 1
  }'
```

### Create New Repository

```bash
# Create new repository via API
curl -k -X POST "$GITEA_URL/api/v1/user/repos" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-new-repo",
    "description": "My new repository",
    "private": false,
    "auto_init": true,
    "default_branch": "main"
  }'
```

### Clone Repository

```bash
# Clone via HTTPS (with credentials)
git clone https://opentlc-mgr:pQF1QnP8pf3AzkoXY5wlm0C5XhzoHxaw@gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/opentlc-mgr/openshift-aiops-platform.git

# Or configure Git credential helper
git config --global credential.helper store
git clone https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/opentlc-mgr/openshift-aiops-platform.git
# Enter credentials when prompted
```

---

## ArgoCD Integration

### Step 1: Create ArgoCD Repository Secret

```bash
# Create secret for Gitea repository
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: gitea-repo-secret
  namespace: openshift-gitops
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/opentlc-mgr/openshift-aiops-platform.git
  username: opentlc-mgr
  password: pQF1QnP8pf3AzkoXY5wlm0C5XhzoHxaw
  insecure: "true"
EOF
```

### Step 2: Update ArgoCD Application

```bash
# Update application to use Gitea
oc patch application coordination-engine -n openshift-gitops --type=merge -p '{
  "spec": {
    "source": {
      "repoURL": "https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/opentlc-mgr/openshift-aiops-platform.git"
    }
  }
}'
```

### Step 3: Verify ArgoCD Sync

```bash
# Check application status
oc get application coordination-engine -n openshift-gitops

# Trigger manual sync
argocd app sync coordination-engine --grpc-web

# Or via oc
oc patch application coordination-engine -n openshift-gitops --type=merge -p '{"operation":{"sync":{}}}'
```

---

## Tekton Integration

### Step 1: Create Gitea Webhook Secret

```bash
# Generate webhook secret
WEBHOOK_SECRET=$(openssl rand -hex 20)

# Create secret in OpenShift
oc create secret generic gitea-webhook-secret \
  -n openshift-pipelines \
  --from-literal=secretToken=$WEBHOOK_SECRET

echo "Webhook Secret: $WEBHOOK_SECRET"
```

### Step 2: Deploy Gitea EventListener

```bash
# Create EventListener for Gitea webhooks
cat <<EOF | oc apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: gitea-webhook-listener
  namespace: openshift-pipelines
spec:
  serviceAccountName: pipeline
  triggers:
    - name: gitea-push-trigger
      interceptors:
        - ref:
            name: gitea
          params:
            - name: eventTypes
              value: ["push"]
            - name: secretRef
              value:
                secretName: gitea-webhook-secret
                secretKey: secretToken
      bindings:
        - name: gitrevision
          value: \$(body.after)
        - name: gitrepositoryurl
          value: \$(body.repository.clone_url)
      template:
        spec:
          params:
            - name: gitrevision
            - name: gitrepositoryurl
          resourcetemplates:
            - apiVersion: tekton.dev/v1beta1
              kind: PipelineRun
              metadata:
                generateName: deployment-validation-
              spec:
                pipelineRef:
                  name: deployment-validation-pipeline
                params:
                  - name: namespace
                    value: self-healing-platform
EOF
```

### Step 3: Get EventListener URL

```bash
# Get EventListener route
EL_URL=$(oc get route el-gitea-webhook-listener -n openshift-pipelines -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "$EL_URL" ]; then
  # Create route if it doesn't exist
  oc expose service el-gitea-webhook-listener -n openshift-pipelines
  EL_URL=$(oc get route el-gitea-webhook-listener -n openshift-pipelines -o jsonpath='{.spec.host}')
fi

echo "EventListener URL: https://$EL_URL"
```

### Step 4: Configure Webhook in Gitea

```bash
# Configure webhook via API
REPO_OWNER="opentlc-mgr"
REPO_NAME="openshift-aiops-platform"
EL_URL=$(oc get route el-gitea-webhook-listener -n openshift-pipelines -o jsonpath='{.spec.host}')
WEBHOOK_SECRET=$(oc get secret gitea-webhook-secret -n openshift-pipelines -o jsonpath='{.data.secretToken}' | base64 -d)

curl -k -X POST "$GITEA_URL/api/v1/repos/$REPO_OWNER/$REPO_NAME/hooks" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"gitea\",
    \"config\": {
      \"url\": \"https://$EL_URL\",
      \"content_type\": \"json\",
      \"secret\": \"$WEBHOOK_SECRET\"
    },
    \"events\": [\"push\"],
    \"active\": true
  }"
```

### Step 5: Test Webhook

```bash
# Make a test commit
cd /tmp
git clone https://opentlc-mgr:pQF1QnP8pf3AzkoXY5wlm0C5XhzoHxaw@gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/opentlc-mgr/openshift-aiops-platform.git
cd openshift-aiops-platform
echo "Test webhook" >> README.md
git add README.md
git commit -m "Test webhook trigger"
git push

# Check pipeline runs
tkn pipelinerun list -n openshift-pipelines
```

---

## Ansible Automation

### Deploy Gitea via Ansible

```bash
# Using validated_patterns_gitea role
ansible-playbook ansible/playbooks/deploy_gitea.yml \
  -e gitea_namespace=gitea \
  -e gitea_admin_user=opentlc-mgr \
  -e gitea_ssl_enabled=true
```

### Mirror Repositories via Ansible

```bash
# Run repository mirroring playbook
ansible-playbook ansible/playbooks/mirror_repositories.yml \
  -e gitea_url=https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com \
  -e gitea_admin_user=opentlc-mgr
```

---

## Backup and Restore

### Backup Gitea Data

```bash
# Backup PostgreSQL database
oc exec -n gitea postgresql-gitea-with-admin-<pod-id> -- \
  pg_dump -U gitea gitea > gitea-backup-$(date +%Y%m%d).sql

# Backup Git repositories (via PVC)
oc rsync -n gitea gitea-with-admin-<pod-id>:/data ./gitea-data-backup/
```

### Restore Gitea Data

```bash
# Restore PostgreSQL database
cat gitea-backup-20251102.sql | \
  oc exec -i -n gitea postgresql-gitea-with-admin-<pod-id> -- \
  psql -U gitea gitea

# Restore Git repositories
oc rsync ./gitea-data-backup/ gitea-with-admin-<pod-id>:/data -n gitea
```

---

## Troubleshooting

### Gitea Not Accessible

```bash
# Check pod status
oc get pods -n gitea

# Check pod logs
oc logs -n gitea -l app=gitea

# Check route
oc get route -n gitea

# Test route
curl -k https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/api/v1/version
```

### ArgoCD Cannot Connect

```bash
# Verify repository secret
oc get secret gitea-repo-secret -n openshift-gitops -o yaml

# Test connectivity from ArgoCD pod
oc exec -n openshift-gitops argocd-server-<pod-id> -- \
  curl -k https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/api/v1/version

# Check ArgoCD logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=argocd-repo-server
```

### Webhook Not Triggering

```bash
# Check EventListener
oc get eventlistener -n openshift-pipelines

# Check EventListener logs
oc logs -n openshift-pipelines -l eventlistener=gitea-webhook-listener

# Test webhook manually
curl -k -X POST https://$EL_URL \
  -H "Content-Type: application/json" \
  -H "X-Gitea-Event: push" \
  -d '{"after":"test","repository":{"clone_url":"https://gitea/test.git"}}'
```

---

## Security Considerations

### 1. Change Default Passwords

```bash
# Change admin password via Gitea UI
# Settings > Account > Password

# Or via API
curl -k -X PATCH "$GITEA_URL/api/v1/admin/users/opentlc-mgr" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  -H "Content-Type: application/json" \
  -d '{"password": "new-secure-password"}'
```

### 2. Enable Two-Factor Authentication

```bash
# Enable 2FA via Gitea UI
# Settings > Security > Two-Factor Authentication
```

### 3. Restrict Access

```bash
# Create NetworkPolicy to restrict access
cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gitea-access-policy
  namespace: gitea
spec:
  podSelector:
    matchLabels:
      app: gitea
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: openshift-gitops
        - namespaceSelector:
            matchLabels:
              name: openshift-pipelines
      ports:
        - protocol: TCP
          port: 3000
EOF
```

---

## Next Steps

1. ✅ **Gitea Deployed** - Operational and accessible
2. **Mirror Repositories** - Mirror external repos to Gitea
3. **Configure ArgoCD** - Update applications to use Gitea
4. **Setup Webhooks** - Enable automated CI/CD triggers
5. **Backup Strategy** - Implement automated backups
6. **User Management** - Create additional users and teams

---

## Related Documentation

- [ADR-028: Gitea Local Git Repository](adrs/028-gitea-local-git-repository.md)
- [ADR-027: CI/CD Pipeline Automation](adrs/027-cicd-pipeline-automation.md)
- [ADR-026: Secrets Management Automation](adrs/026-secrets-management-automation.md)
- [Gitea Documentation](https://docs.gitea.io/)
- [Validated Patterns Gitea Role](https://github.com/tosin2013/validated-patterns-ansible-toolkit/tree/main/ansible/roles/validated_patterns_gitea)

---

**Last Updated:** 2025-11-02
**Status:** ✅ Deployed and Operational
**Maintained By:** Architecture Team
