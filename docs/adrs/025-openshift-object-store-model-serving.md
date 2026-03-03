# ADR-025: OpenShift Object Store for Model Serving

**Status**: PROPOSED
**Date**: 2025-10-19
**Renumbered From**: Originally ADR-020 (renumbered 2025-11-19 to resolve duplicate)
**Deciders**: Architecture Team
**Affects**: Model Serving, KServe, Storage, Helm Charts

## Implementation Status
**Status:** ✅ IMPLEMENTED
**Verification Date:** 2026-01-25
**Implementation Score:** 9.0/10
**Verified On:** SNO + HA clusters
**Evidence:** NooBaa S3 deployed (Ready), endpoints configured, 4 NooBaa pods running, ObjectBucketClaim created.

## Context

Phase 3 & 4 notebooks require object storage for model artifacts. Current implementation references S3 credentials that don't exist. We need to leverage OpenShift's built-in object storage capabilities following Validated Patterns framework.

### OpenShift Object Store Options

1. **OpenShift Data Foundation (ODF)** - Production-grade, S3-compatible
2. **NooBaa** - S3-compatible object storage (part of ODF)
3. **MinIO** - Lightweight S3-compatible alternative

### Validated Patterns Approach

From validated patterns research:
- **Medical Diagnosis Pattern**: Uses S3 storage with Ceph/NooBaa
- **Industrial Edge Pattern**: Uses OpenShift Data Foundation for object storage
- **Framework**: GitOps-driven deployment via Helm + ArgoCD

## Decision

We will **use OpenShift Data Foundation (ODF) with NooBaa** for model artifact storage, following the Validated Patterns framework structure:

1. **Storage Backend**: ODF/NooBaa (S3-compatible)
2. **Deployment Method**: Helm charts + ArgoCD (GitOps)
3. **Configuration**: values-hub.yaml for ODF operator subscription
4. **Secrets**: values-secret.yaml.template for S3 credentials
5. **Access**: KServe InferenceService via S3 endpoint

## Implementation

### 1. ODF Operator Subscription (values-hub.yaml)

```yaml
operators:
  - name: odf-operator
    namespace: openshift-storage
    channel: stable
    installPlanApproval: Automatic
```

### 2. NooBaa Object Store (k8s/base/object-store.yaml)

```yaml
apiVersion: noobaa.io/v1alpha1
kind: NooBaa
metadata:
  name: noobaa
  namespace: openshift-storage
spec:
  dbResources:
    requests:
      cpu: 500m
      memory: 1Gi
  coreResources:
    requests:
      cpu: 500m
      memory: 1Gi
```

### 3. S3 Bucket Configuration (k8s/base/s3-bucket.yaml)

```yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: model-storage
  namespace: self-healing-platform
spec:
  generateBucketName: model-storage
  storageClassName: openshift-storage.noobaa.io
```

### 4. Secret Management (values-secret.yaml.template)

```yaml
objectStore:
  endpoint: "https://s3.openshift-storage.svc.cluster.local"
  accessKey: "REDACTED"
  secretKey: "REDACTED"
  bucketName: "model-storage"
```

### 5. KServe Integration (charts/hub/templates/model-serving.yaml)

Update to use ODF endpoint:

```yaml
spec:
  predictor:
    sklearn:
      storageUri: "s3://model-storage/anomaly-detector/"
      env:
      - name: AWS_S3_ENDPOINT
        valueFrom:
          secretKeyRef:
            name: model-storage-config
            key: AWS_S3_ENDPOINT
```

## Consequences

### Positive
- ✅ No external S3 dependency
- ✅ Follows Validated Patterns framework
- ✅ GitOps-driven deployment
- ✅ S3-compatible API for KServe
- ✅ Integrated with OpenShift
- ✅ Automatic secret management via External Secrets Operator

### Negative
- ❌ Requires ODF operator installation
- ❌ Additional cluster resources needed
- ❌ Operational complexity for ODF management

### Mitigation
- Use ODF operator for lifecycle management
- Follow ODF best practices from validated patterns
- Monitor ODF health via Prometheus

## Validation

```bash
# Verify ODF installation
oc get storagecluster -n openshift-storage

# Verify NooBaa
oc get noobaa -n openshift-storage

# Verify bucket
oc get objectbucketclaim -n self-healing-platform

# Test S3 access
aws s3 ls s3://model-storage/ --endpoint-url $S3_ENDPOINT
```

## References

- ADR-010: OpenShift Data Foundation Requirement
- Validated Patterns: Medical Diagnosis Pattern
- Validated Patterns: Industrial Edge Pattern
- [OpenShift Data Foundation Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation/)
- [NooBaa Documentation](https://www.noobaa.io/)
