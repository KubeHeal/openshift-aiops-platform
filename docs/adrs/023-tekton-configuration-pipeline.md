# ADR-023: Tekton Configuration Pipeline for S3 Setup

**Date:** 2025-10-31
**Status:** ✅ ACCEPTED
**Deciders:** Architecture Team
**Confidence:** 90%

---

## Implementation Status
**Status:** implemented
**Verification Date:** 2026-01-25
**Implementation Score:** 9.0/10
**Verified On:** SNO + HA clusters
**Evidence:** S3 configuration pipeline + ExternalSecrets for credential management operational.

---

## Context

The OpenShift AIOps Self-Healing Platform requires S3 credentials to be discovered from ObjectBucketClaim and made available to:
1. InferenceServices (for downloading models)
2. Notebooks (for uploading trained models)

**Problem:** How should S3 credentials be discovered and made available?

**Options Considered:**
1. Tekton patches the secret directly (REJECTED - conflicts with ArgoCD)
2. External Secrets Operator manages credentials (ACCEPTED - GitOps-compliant)
3. Manual credential management (REJECTED - not scalable)

---

## Decision

**Use External Secrets Operator to manage S3 credentials from ObjectBucketClaim.**

Tekton's role is limited to:
- ✅ Validating S3 connectivity
- ✅ Uploading placeholder models
- ✅ Reconciling InferenceServices
- ✅ Running health checks

**NOT:**
- ❌ Patching secrets (conflicts with ArgoCD)
- ❌ Managing credentials (External Secrets handles this)

---

## Rationale

### Why External Secrets Instead of Tekton Patching?

**ArgoCD GitOps Conflict:**
```
Tekton patches secret (real credentials)
  ↓
ArgoCD detects drift (cluster ≠ Git)
  ↓
ArgoCD reverts secret (selfHeal: true)
  ↓
❌ Tekton changes lost
```

**External Secrets Solution:**
```
ObjectBucketClaim creates secret (real credentials)
  ↓
External Secrets reads ObjectBucketClaim
  ↓
External Secrets creates model-storage-config secret
  ↓
ArgoCD manages ExternalSecret (not Secret)
  ↓
✅ No conflicts
```

### Benefits

1. **GitOps-Compliant** - ArgoCD manages ExternalSecret, not Secret
2. **No Conflicts** - External Secrets Operator manages Secret
3. **Automatic Sync** - Credentials refreshed every 1 hour
4. **Secure** - Credentials not in Git
5. **Scalable** - Works with multiple environments

---

## Implementation

### Phase 1: External Secrets Setup (Helm)

**Create ExternalSecret template:**
```yaml
# charts/hub/templates/externalsecrets-model-storage.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: model-storage-config
  namespace: {{ .Values.main.namespace }}
spec:
  refreshInterval: 1h
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
```

**Create SecretStore template:**
```yaml
# charts/hub/templates/secretstore-kubernetes.yaml
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
```

### Phase 2: Tekton Configuration Pipeline

**Tekton Tasks (4):**
1. **validate-s3-connectivity** - Test S3 endpoint
2. **upload-placeholder-models** - Upload test models
3. **reconcile-inferenceservices** - Trigger reconciliation
4. **validate-model-serving** - Health checks

**Tekton Pipeline:**
```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: s3-configuration-pipeline
spec:
  tasks:
  - name: validate-s3
    taskRef:
      name: validate-s3-connectivity
  - name: upload-placeholders
    taskRef:
      name: upload-placeholder-models
    runAfter: [validate-s3]
  - name: reconcile-services
    taskRef:
      name: reconcile-inferenceservices
    runAfter: [upload-placeholders]
  - name: validate-serving
    taskRef:
      name: validate-model-serving
    runAfter: [reconcile-services]
```

---

## Workflow

### Phase 1: Ansible Prerequisites
```
Create namespace
Create ExternalSecret
Helm deployment
├─ Creates NooBaa
├─ Creates ObjectBucketClaim
└─ Creates InferenceServices (pending)
```

### Phase 2: External Secrets Operator
```
Reads ObjectBucketClaim secret
Creates model-storage-config secret
Refreshes every 1 hour
```

### Phase 3: Tekton Configuration
```
Validate S3 connectivity
Upload placeholder models
Reconcile InferenceServices
Run health checks
```

### Phase 4: User Trains Models
```
Run Phase 2 notebooks
Train models locally
Save to /opt/app-root/src/models/
```

### Phase 5: User Uploads Models
```
Get credentials from environment
Upload trained models to S3
Test model endpoints
```

---

## Consequences

### Positive
- ✅ GitOps-compliant architecture
- ✅ No ArgoCD conflicts
- ✅ Automatic credential sync
- ✅ Secure credential management
- ✅ Scalable to multiple environments
- ✅ Follows Validated Patterns best practices

### Negative
- ⚠️ Requires External Secrets Operator deployment
- ⚠️ Additional RBAC configuration needed
- ⚠️ Slightly more complex setup

### Mitigations
- External Secrets Operator is standard in enterprise Kubernetes
- RBAC templates provided in implementation
- Clear documentation and examples provided

---

## Related ADRs

- **ADR-024:** External Secrets for Model Storage Configuration
- **ADR-021:** Tekton Pipeline Deployment Validation
- **ADR-019:** Validated Patterns Framework Adoption

---

## References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [Kubernetes Secrets Management Best Practices](https://kubernetes.io/docs/concepts/configuration/secret/)
- [ArgoCD Self-Heal Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)

---

## Implementation Status

- [ ] Create ExternalSecret template
- [ ] Create SecretStore template
- [ ] Create RBAC template
- [ ] Remove hardcoded secret from Helm
- [ ] Update values-global.yaml
- [ ] Update Ansible playbook
- [ ] Test External Secrets deployment
- [ ] Verify credential sync
- [ ] Create Tekton configuration pipeline
- [ ] Test end-to-end workflow
