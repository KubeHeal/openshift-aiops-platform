# Deploy on ROSA (Red Hat OpenShift Service on AWS)

ROSA is the **primary deployment target** for the OpenShift AI Ops Self-Healing Platform. This guide covers deploying on ROSA Classic in both HA (multi-node) and single-worker-node configurations.

## Prerequisites

### ROSA Cluster

- **ROSA Classic** cluster (HA or single-worker-node)
- OpenShift 4.19+ (4.22 recommended)
- `dedicated-admin` or `cluster-admin` access
- AWS account with appropriate IAM permissions

### CLI Tools

| Tool | Purpose |
|------|---------|
| `rosa` | ROSA cluster and machine pool management |
| `oc` | OpenShift CLI |
| `aws` | AWS CLI for S3 bucket creation |
| `helm` | Kubernetes package manager (3.12+) |
| `git` | Version control |

Install workstation prerequisites:

```bash
# RHEL 9/10 automated installer
./scripts/install-prerequisites-rhel.sh
source ~/.bashrc

# Install rosa CLI (if not included)
curl -o rosa https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz
tar xzf rosa-linux.tar.gz && sudo mv rosa /usr/local/bin/
rosa login --token=<your-ocm-token>
```

## Step 1: Create or Access Your ROSA Cluster

### Option A: Create a New ROSA Classic Cluster (HA)

```bash
rosa create cluster --cluster-name=aiops-platform \
  --sts --mode=auto \
  --region=us-east-1 \
  --compute-machine-type=m5.2xlarge \
  --replicas=3

# Wait for cluster to be ready (~40 minutes)
rosa describe cluster --cluster=aiops-platform
```

### Option B: Create a Single-Worker ROSA Cluster

```bash
rosa create cluster --cluster-name=aiops-sno \
  --sts --mode=auto \
  --region=us-east-1 \
  --compute-machine-type=m5.2xlarge \
  --replicas=1
```

### Option C: Use an Existing ROSA Cluster

```bash
rosa list clusters
oc login --token=<token> --server=<api-url>
```

## Step 2: (Optional) Add GPU Machine Pool

If you need GPU support for accelerated model training:

```bash
# Create GPU machine pool with NVIDIA A10G GPUs
rosa create machinepool --cluster=aiops-platform \
  --name=gpu-workers \
  --instance-type=g5.2xlarge \
  --replicas=1 \
  --labels="nvidia.com/gpu.present=true" \
  --taints="nvidia.com/gpu=True:NoSchedule"
```

**Recommended GPU Instance Types:**

| Instance | GPU | GPU Memory | vCPU | RAM | Use Case |
|----------|-----|------------|------|-----|----------|
| `g5.xlarge` | 1x A10G | 24 GB | 4 | 16 GB | Development, small models |
| `g5.2xlarge` | 1x A10G | 24 GB | 8 | 32 GB | Production training (recommended) |
| `p3.2xlarge` | 1x V100 | 16 GB | 8 | 61 GB | Heavy training workloads |
| `g5.4xlarge` | 1x A10G | 24 GB | 16 | 64 GB | Large model training |

After creating the GPU machine pool, install the NVIDIA GPU Operator:

```bash
# Install Node Feature Discovery (NFD) Operator first
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd
  namespace: openshift-operators
spec:
  channel: stable
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Install NVIDIA GPU Operator
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gpu-operator-certified
  namespace: openshift-operators
spec:
  channel: v24.9
  name: gpu-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
EOF
```

## Step 3: Create S3 Bucket for Model Storage

The platform uses native AWS S3 for model artifact storage by default on ROSA.

### Option A: Using AWS CLI (Recommended)

```bash
# Create S3 bucket for model storage
aws s3 mb s3://aiops-model-storage-$(rosa describe cluster -c aiops-platform -o json | jq -r '.id' | cut -c1-8) \
  --region us-east-1

# Create additional buckets
aws s3 mb s3://aiops-training-data-$(rosa describe cluster -c aiops-platform -o json | jq -r '.id' | cut -c1-8) \
  --region us-east-1
```

### Option B: Using IRSA (IAM Roles for Service Accounts)

For production deployments, use IRSA instead of static credentials:

```bash
# Create IAM policy for S3 access
cat > /tmp/s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:CreateBucket"
      ],
      "Resource": [
        "arn:aws:s3:::aiops-model-storage-*",
        "arn:aws:s3:::aiops-model-storage-*/*",
        "arn:aws:s3:::aiops-training-data-*",
        "arn:aws:s3:::aiops-training-data-*/*"
      ]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name AIOpsS3Access \
  --policy-document file:///tmp/s3-policy.json

# Create OIDC-based IAM role for the service account
# (Replace ACCOUNT_ID and OIDC_PROVIDER with your values)
```

### Option C: Using ODF Add-on (Alternative)

If you prefer ODF/NooBaa for S3 storage (consistent with baremetal deployments):

```bash
# Enable ODF add-on on ROSA
rosa install addon --cluster=aiops-platform managed-odh

# Set backend to noobaa in values-hub.yaml
# objectStore.backend: "noobaa"
```

## Step 4: Fork and Configure the Repository

```bash
# 1. Fork on GitHub
# Click "Fork" at https://github.com/KubeHeal/openshift-aiops-platform

# 2. Clone YOUR fork
git clone https://github.com/YOUR-USERNAME/openshift-aiops-platform.git
cd openshift-aiops-platform

# 3. Log into your ROSA cluster
oc login --token=<token> --server=<api-url>

# 4. Update git.repoURL in values-global.yaml
vi values-global.yaml
# Set: git.repoURL: "https://github.com/YOUR-USERNAME/openshift-aiops-platform.git"
```

## Step 5: Configure values-hub.yaml for ROSA

```yaml
# Cluster configuration
cluster:
  topology: "ha"  # or "sno" for single-worker

# Object store -- native AWS S3 (default for ROSA)
objectStore:
  enabled: true
  backend: "aws-s3"
  aws:
    region: "us-east-1"
    bucketName: "aiops-model-storage-XXXXXXXX"
    # irsaRoleArn: "arn:aws:iam::ACCOUNT_ID:role/AIOpsS3Role"  # For IRSA
  buckets:
    models: "aiops-model-storage-XXXXXXXX"
    trainingData: "aiops-training-data-XXXXXXXX"

# Storage classes (ROSA uses gp3-csi by default)
storage:
  modelStorage:
    storageClass: "gp3-csi"

# RBAC
rbac:
  crossNamespaceEnabled: true
```

For single-worker ROSA:

```yaml
cluster:
  topology: "sno"

storage:
  modelStorage:
    storageClass: "gp3-csi"
```

## Step 6: Deploy the Platform

```bash
# Verify cluster topology
make show-cluster-info

# Configure cluster infrastructure (skips MachineSet scaling on ROSA)
make configure-cluster

# Deploy via Validated Patterns Operator
./pattern.sh make install
```

The VP Operator creates an ArgoCD instance and syncs all platform components:

```bash
# Wait for ArgoCD applications to sync
oc get applications.argoproj.io -n self-healing-platform-hub
# Target: SYNC STATUS=Synced, HEALTH STATUS=Healthy
```

## Step 7: Validate Deployment

```bash
# Check ArgoCD health
make argo-healthcheck

# Run Tekton validation pipeline
tkn pipeline start deployment-validation-pipeline --showlog -n self-healing-platform
```

## Storage Backend Decision Tree

```
Is your cluster on AWS (ROSA or IPI)?
├── YES: Do you need air-gapped / disconnected support?
│   ├── YES → Use objectStore.backend: "noobaa" (ODF add-on)
│   └── NO → Use objectStore.backend: "aws-s3" (recommended)
└── NO: (baremetal, Azure, GCP, VMware)
    └── Use objectStore.backend: "noobaa" (requires ODF)
```

## ROSA-Specific Troubleshooting

### Machine Pool Not Scaling

```bash
# Check machine pool status
rosa list machinepools --cluster=aiops-platform

# Check machine pool logs
rosa logs install --cluster=aiops-platform --watch
```

### S3 Access Denied

```bash
# Verify IAM credentials
aws s3 ls s3://aiops-model-storage-XXXXXXXX

# Check if model-storage-config secret has correct values
oc get secret model-storage-config -n self-healing-platform -o yaml

# For IRSA: verify service account annotation
oc get sa self-healing-s3-access -n self-healing-platform -o yaml
```

### GPU Operator Not Installing

```bash
# Check NFD is installed first
oc get csv -n openshift-operators | grep nfd

# Check GPU operator status
oc get csv -n openshift-operators | grep gpu-operator

# Verify GPU node is labeled
oc get nodes -l nvidia.com/gpu.present=true
```

### ArgoCD Sync Issues on ROSA

ROSA uses `dedicated-admin` by default. The platform requires cluster-admin for ArgoCD:

```bash
# Grant cluster-admin to ArgoCD controller
make operator-deploy-prereqs

# Verify ClusterRoleBinding
oc get clusterrolebinding hub-gitops-argocd-application-controller-cluster-admin
```

## Related Documentation

- [ADR-062: ROSA as Primary Deployment Target](../adrs/062-rosa-primary-deployment-target.md)
- [ADR-006: NVIDIA GPU Operator for AI Workload Management](../adrs/006-nvidia-gpu-management.md)
- [ADR-057: Topology-Aware GPU Scheduling and Storage](../adrs/057-topology-aware-gpu-scheduling-and-storage.md)
- [Deploy on Other Platforms](deploy-on-other-platforms.md) (IPI, baremetal, community-supported)
- [Deploy on SNO](deploy-on-sno.md) (Single Node OpenShift)
