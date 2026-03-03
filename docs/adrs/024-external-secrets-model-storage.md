# ADR-024: External Secrets Operator for Model Storage Configuration

**Date:** 2025-10-31
**Status:** ✅ ACCEPTED
**Deciders:** Architecture Team
**Confidence:** 95%

---

## Implementation Status
**Status:** ✅ IMPLEMENTED
**Verification Date:** 2026-01-25
**Implementation Score:** 9.0/10
**Verified On:** SNO + HA clusters
**Evidence:** 4 ExternalSecrets deployed (model-storage-config, storage-config, git-credentials, gitea-credentials), all SecretSynced.

---

## Context

The OpenShift AIOps Self-Healing Platform uses ObjectBucketClaim to create S3 buckets and credentials. However, there's a critical GitOps conflict:

**Problem:** How to make ObjectBucketClaim credentials available to applications without conflicting with ArgoCD's GitOps principles?

**Current Issue:**
- Helm chart has hardcoded credentials (admin/changeme)
- ObjectBucketClaim creates real credentials
- Credential mismatch causes authentication failures
- Tekton patching conflicts with ArgoCD's selfHeal

---

## Decision

**Use External Secrets Operator to read ObjectBucketClaim credentials and manage the model-storage-config secret.**

This eliminates the need for Tekton to patch secrets and avoids ArgoCD conflicts.

---

## Rationale

### The GitOps Conflict

```
Git Repository (Source of Truth)
  └─ model-storage-config Secret
     ├─ AWS_ACCESS_KEY_ID: "admin"
     └─ AWS_SECRET_ACCESS_KEY: "changeme"

Cluster State (After Tekton Patch)
  └─ model-storage-config Secret
     ├─ AWS_ACCESS_KEY_ID: "real_key"
     └─ AWS_SECRET_ACCESS_KEY: "real_secret"

ArgoCD Comparison
  └─ Detects DRIFT
  └─ selfHeal: true
  └─ Reverts to Git state
  └─ ❌ Tekton changes lost
```

### The Solution

```
Git Repository
  └─ ExternalSecret (managed by ArgoCD)
     └─ Declarative: "Read from ObjectBucketClaim"

ObjectBucketClaim Secret (openshift-storage)
  └─ Real credentials (AWS_ACCESS_KEY_ID, etc.)

External Secrets Operator
  └─ Operational: Reads ObjectBucketClaim
  └─ Creates model-storage-config Secret
  └─ Refreshes every 1 hour

ArgoCD
  └─ Manages ExternalSecret
  └─ Does NOT manage Secret
  └─ No conflicts
```

### Why This Works

1. **Separation of Concerns**
   - ArgoCD manages ExternalSecret (declarative)
   - External Secrets Operator manages Secret (operational)
   - Clear responsibility boundaries

2. **No Drift Detection**
   - ArgoCD doesn't manage the Secret itself
   - External Secrets Operator manages the Secret
   - No conflicts between tools

3. **Automatic Sync**
   - Credentials refreshed every 1 hour
   - Always current
   - No manual intervention needed

4. **GitOps-Compliant**
   - ExternalSecret is declarative (in Git)
   - Secret is operational (managed by operator)
   - Follows GitOps principles

---

## Implementation

### Deployment via Validated Patterns Framework

**Location:** `ansible/roles/validated_patterns_common/tasks/deploy_external_secrets_operator.yml`

The External Secrets Operator is deployed as part of the `validated_patterns_common` role, following the Validated Patterns framework guidelines (AGENTS.md):

**Execution Flow:**
1. `validated_patterns_prerequisites` - Validate cluster readiness
2. `validated_patterns_common` - Deploy foundation (Helm, ArgoCD, **External Secrets Operator**)
3. `validated_patterns_secrets` - Configure secrets management
4. `validated_patterns_deploy` - Deploy application patterns

**Task Features:**
- ✅ Checks if operator already installed (idempotent)
- ✅ Deploys via Helm if missing
- ✅ Verifies CRDs available
- ✅ Waits for deployment ready
- ✅ Provides detailed status messages

**For Future Clusters:**
The task automatically handles operator deployment. No manual steps required.

---

### 1. Create ExternalSecret Template

**File:** `charts/hub/templates/externalsecrets-model-storage.yaml`

```yaml
{{- if eq .Values.secrets.backend "external-secrets" }}
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: model-storage-config
  namespace: {{ .Values.main.namespace }}
  labels:
    app.kubernetes.io/name: model-storage-config
    app.kubernetes.io/component: external-secret
spec:
  refreshInterval: {{ .Values.secrets.externalSecrets.refreshInterval | default "1h" }}
  secretStoreRef:
    name: kubernetes-secret-store
    kind: SecretStore
  target:
    name: model-storage-config
    creationPolicy: Owner
  data:
  - secretKey: AWS_ACCESS_KEY_ID
    remoteRef:
      key: model-storage-obc-secret
      property: AWS_ACCESS_KEY_ID
  - secretKey: AWS_SECRET_ACCESS_KEY
    remoteRef:
      key: model-storage-obc-secret
      property: AWS_SECRET_ACCESS_KEY
  - secretKey: AWS_S3_ENDPOINT
    remoteRef:
      key: model-storage-obc-secret
      property: AWS_S3_ENDPOINT
  - secretKey: AWS_DEFAULT_REGION
    secretValue: "us-east-1"
  - secretKey: AWS_S3_BUCKET
    secretValue: "model-storage"
{{- end }}
```

### 2. Create SecretStore Template

**File:** `charts/hub/templates/secretstore-kubernetes.yaml`

```yaml
{{- if eq .Values.secrets.backend "external-secrets" }}
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: kubernetes-secret-store
  namespace: {{ .Values.main.namespace }}
spec:
  provider:
    kubernetes:
      auth:
        serviceAccount:
          name: external-secrets-sa
      remoteNamespace: openshift-storage
{{- end }}
```

### 3. Create RBAC

**File:** `charts/hub/templates/externalsecrets-rbac.yaml`

```yaml
{{- if eq .Values.secrets.backend "external-secrets" }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-sa
  namespace: {{ .Values.main.namespace }}

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: external-secrets-reader
  namespace: openshift-storage
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]
  resourceNames: ["model-storage-obc-secret"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: external-secrets-reader
  namespace: openshift-storage
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: external-secrets-reader
subjects:
- kind: ServiceAccount
  name: external-secrets-sa
  namespace: {{ .Values.main.namespace }}
{{- end }}
```

### 4. Update values-global.yaml

```yaml
secrets:
  backend: external-secrets
  externalSecrets:
    enabled: true
    refreshInterval: 1h
    secretStore:
      name: kubernetes-secret-store
      kind: SecretStore
```

### 5. Remove Hardcoded Secret

**File:** `charts/hub/templates/01-secrets.yaml`

Remove the model-storage-config Secret section (keep other secrets).

### 6. Update Ansible Playbook

**File:** `ansible/playbooks/deploy_and_cleanup_e2e.yml`

Remove the task that creates the hardcoded secret.

---

## Deployment Prerequisites

### External Secrets Operator Must Be Installed

```bash
# Check if installed
oc get deployment -n external-secrets-system

# If not installed, install it:
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace
```

---

## Verification

### Check ExternalSecret Status
```bash
oc get externalsecrets -n self-healing-platform
oc describe externalsecret model-storage-config -n self-healing-platform
```

### Check Secret Contents
```bash
oc get secret model-storage-config -n self-healing-platform -o yaml
```

### Check Refresh Logs
```bash
oc logs -f deployment/external-secrets -n external-secrets-system
```

---

## Consequences

### Positive
- ✅ GitOps-compliant
- ✅ No ArgoCD conflicts
- ✅ Automatic credential sync
- ✅ Secure credential management
- ✅ Scalable to multiple environments
- ✅ Follows enterprise best practices

### Negative
- ⚠️ Requires External Secrets Operator
- ⚠️ Additional RBAC configuration
- ⚠️ Slightly more complex setup

### Mitigations
- External Secrets Operator is standard in enterprise Kubernetes
- RBAC templates provided
- Clear documentation provided

---

## Related ADRs

- **ADR-023:** Tekton Configuration Pipeline
- **ADR-021:** Tekton Pipeline Deployment Validation
- **ADR-019:** Validated Patterns Framework Adoption

---

## References

- [External Secrets Operator](https://external-secrets.io/)
- [Kubernetes Secrets Management](https://kubernetes.io/docs/concepts/configuration/secret/)
- [GitOps Best Practices](https://opengitops.dev/)

---

## Implementation Status

- [ ] Install External Secrets Operator
- [ ] Create ExternalSecret template
- [ ] Create SecretStore template
- [ ] Create RBAC template
- [ ] Remove hardcoded secret from Helm
- [ ] Update values-global.yaml
- [ ] Update Ansible playbook
- [ ] Test External Secrets deployment
- [ ] Verify credential sync
- [ ] Document troubleshooting procedures
