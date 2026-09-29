# OpenShift Object Store Setup for Model Serving

This guide explains how to set up OpenShift Data Foundation (ODF) with NooBaa for model artifact storage, following the Validated Patterns framework.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│         OpenShift Cluster                               │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  OpenShift Data Foundation (ODF)                 │  │
│  │  ├─ Ceph (distributed storage)                   │  │
│  │  ├─ NooBaa (S3-compatible object store)          │  │
│  │  └─ Rook (storage orchestration)                 │  │
│  └──────────────────────────────────────────────────┘  │
│                      ↓                                  │
│  ┌──────────────────────────────────────────────────┐  │
│  │  S3 Buckets (via NooBaa)                         │  │
│  │  ├─ model-storage (trained models)               │  │
│  │  ├─ training-data (datasets)                     │  │
│  │  └─ inference-results (predictions)              │  │
│  └──────────────────────────────────────────────────┘  │
│                      ↓                                  │
│  ┌──────────────────────────────────────────────────┐  │
│  │  KServe InferenceService                         │  │
│  │  (accesses models via S3 endpoint)               │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **OpenShift Cluster**: 4.16+ with ODF operator available
2. **Storage Nodes**: At least 3 nodes with 100GB+ available storage
3. **Cluster Admin Access**: Required for ODF installation
4. **Helm 3.x**: For deploying charts

## Step 1: Verify ODF Installation

Check if ODF is already installed:

```bash
# Check for ODF operator
oc get operators | grep odf

# Check for storage cluster
oc get storagecluster -n openshift-storage

# Check for NooBaa
oc get noobaa -n openshift-storage
```

If ODF is not installed, install it via OperatorHub:

```bash
# Create openshift-storage namespace
oc create namespace openshift-storage

# Install ODF operator (via OperatorHub UI or CLI)
# The operator will automatically create storage cluster
```

## Step 2: Deploy Object Store Infrastructure

Apply the object store manifests:

```bash
# Deploy NooBaa and ObjectBucketClaims
oc apply -f k8s/base/object-store.yaml

# Verify deployment
oc get noobaa -n openshift-storage
oc get objectbucketclaim -n self-healing-platform
```

Wait for ObjectBucketClaims to be bound:

```bash
# Watch status
oc get objectbucketclaim -n self-healing-platform -w

# Should show: STATUS = Bound
```

## Step 3: Extract S3 Credentials

Once buckets are created, extract credentials:

```bash
# Get S3 endpoint
S3_ENDPOINT=$(oc get route s3 -n openshift-storage -o jsonpath='{.spec.host}')
echo "S3 Endpoint: https://$S3_ENDPOINT"

# Get access key
ACCESS_KEY=$(oc get secret model-storage -n self-healing-platform -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
echo "Access Key: $ACCESS_KEY"

# Get secret key
SECRET_KEY=$(oc get secret model-storage -n self-healing-platform -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
echo "Secret Key: $SECRET_KEY"

# Get bucket name
BUCKET_NAME=$(oc get objectbucketclaim model-storage -n self-healing-platform -o jsonpath='{.spec.generateBucketName}')
echo "Bucket Name: $BUCKET_NAME"
```

## Step 4: Configure Secrets

Update `values-secret.yaml.template`:

```yaml
objectStore:
  endpoint: "https://s3.openshift-storage.svc.cluster.local"
  accessKey: "<ACCESS_KEY_FROM_STEP_3>"
  secretKey: "<SECRET_KEY_FROM_STEP_3>"
  buckets:
    models: "model-storage"
    trainingData: "training-data"
    inferenceResults: "inference-results"
  region: "us-east-1"
  sslVerify: false
```

Copy to secure location:

```bash
# Create config directory
mkdir -p ~/.config/validatedpatterns

# Copy template
cp values-secret.yaml.template ~/.config/validatedpatterns/values-secret-openshift-aiops-platform.yaml

# Edit with actual values
vi ~/.config/validatedpatterns/values-secret-openshift-aiops-platform.yaml

# Encrypt with ansible-vault (optional but recommended)
ansible-vault encrypt ~/.config/validatedpatterns/values-secret-openshift-aiops-platform.yaml
```

## Step 5: Deploy with Helm

Deploy the platform with object store configuration:

```bash
# Using make (Validated Patterns way)
make install

# Or using helm directly
helm install self-healing-platform ./charts/hub \
  -f values-global.yaml \
  -f values-hub.yaml \
  -f ~/.config/validatedpatterns/values-secret-openshift-aiops-platform.yaml \
  -n self-healing-platform \
  --create-namespace
```

## Step 6: Verify Model Serving

Test KServe access to S3:

```bash
# Check InferenceService
oc get inferenceservice -n self-healing-platform

# Check model serving pod logs
oc logs -n self-healing-platform -l app=anomaly-detector -f

# Test S3 access
aws s3 ls s3://model-storage/ \
  --endpoint-url https://s3.openshift-storage.svc.cluster.local \
  --access-key $ACCESS_KEY \
  --secret-key $SECRET_KEY
```

## Troubleshooting

### ObjectBucketClaim stuck in Pending

```bash
# Check ODF status
oc get storagecluster -n openshift-storage

# Check NooBaa status
oc describe noobaa -n openshift-storage

# Check events
oc describe objectbucketclaim model-storage -n self-healing-platform
```

### KServe can't access S3

```bash
# Verify secret exists
oc get secret model-storage-config -n self-healing-platform

# Check InferenceService events
oc describe inferenceservice anomaly-detector -n self-healing-platform

# Check model serving pod logs
oc logs -n self-healing-platform -l app=anomaly-detector --tail=50
```

### S3 endpoint not accessible

```bash
# Verify NooBaa S3 service
oc get svc -n openshift-storage | grep s3

# Test connectivity from pod
oc run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -k https://s3.openshift-storage.svc.cluster.local
```

## References

- [ADR-020: OpenShift Object Store for Model Serving](docs/adrs/020-openshift-object-store-model-serving.md)
- [ADR-010: OpenShift Data Foundation Requirement](docs/adrs/010-openshift-data-foundation-requirement.md)
- [Validated Patterns: Medical Diagnosis](https://validatedpatterns.io/patterns/medical-diagnosis/)
- [OpenShift Data Foundation Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation/)
- [NooBaa Documentation](https://www.noobaa.io/)
