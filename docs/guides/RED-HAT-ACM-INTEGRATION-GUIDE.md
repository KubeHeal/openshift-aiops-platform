# Red Hat Advanced Cluster Management (ACM) Integration Guide

**Version:** 1.0
**Date:** 2025-10-31
**Status:** PRODUCTION READY
**Related ADR:** ADR-022 - Multi-Cluster Support via Red Hat ACM

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Hub Cluster Installation](#hub-cluster-installation)
4. [Spoke Cluster Registration](#spoke-cluster-registration)
5. [GitOps Integration](#gitops-integration)
6. [Policy Management](#policy-management)
7. [Monitoring & Observability](#monitoring--observability)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

## Overview

Red Hat Advanced Cluster Management (ACM) provides enterprise-grade multi-cluster management for OpenShift. This guide covers ACM integration with the Self-Healing Platform for hub-spoke topology deployments.

### Key Capabilities

- **Cluster Lifecycle Management**: Register, monitor, and manage multiple clusters
- **Policy Engine**: Enforce consistent policies across clusters
- **Application Management**: Deploy applications via GitOps (ArgoCD)
- **Observability**: Centralized monitoring and logging
- **Security**: RBAC, network policies, and compliance management

## Prerequisites

### Hub Cluster Requirements

- OpenShift 4.19+ (4.21 recommended; 4.18 maintenance-only; originally tested on 4.18.21)
- 3+ control plane nodes
- 4+ worker nodes (minimum)
- 100GB+ available storage
- Network connectivity to all spoke clusters
- Operator Hub access (for operator installation)

### Spoke Cluster Requirements

- OpenShift 4.16+ (compatible with hub version)
- 1+ control plane node
- 2+ worker nodes (minimum)
- 20GB+ available storage
- Network connectivity to hub cluster (bidirectional)
- Outbound HTTPS access to hub cluster

### Required Tools

```bash
# On hub cluster
oc version          # OpenShift CLI
helm version        # Helm 3.x
kubectl version     # Kubernetes CLI
jq                  # JSON processor
yq                  # YAML processor

# For cluster registration
ansible --version   # Ansible 2.9+
```

## Hub Cluster Installation

### Step 1: Install ACM Operator

```bash
# Create namespace for ACM
oc create namespace open-cluster-management

# Create OperatorGroup
cat << 'EOF' | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: open-cluster-management
  namespace: open-cluster-management
spec:
  targetNamespaces:
  - open-cluster-management
EOF

# Subscribe to ACM operator
cat << 'EOF' | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: advanced-cluster-management
  namespace: open-cluster-management
spec:
  channel: release-2.9
  installPlanApproval: Automatic
  name: advanced-cluster-management
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Wait for operator to be ready
oc wait --for=condition=Installed \
  subscription/advanced-cluster-management \
  -n open-cluster-management \
  --timeout=300s
```

### Step 2: Create MultiClusterHub

```bash
# Create MultiClusterHub resource
cat << 'EOF' | oc apply -f -
apiVersion: operator.open-cluster-management.io/v1
kind: MultiClusterHub
metadata:
  name: multiclusterhub
  namespace: open-cluster-management
spec:
  imagePullSecret: multiclusterhub-operator-pull-secret
  availabilityConfig: High
  enableClusterBackup: true
  enableAnalytics: true

  # Resource requirements
  nodeSelector:
    node-role.kubernetes.io/worker: ""

  # Tolerations for worker nodes
  tolerations:
  - key: workload
    operator: Equal
    value: management
    effect: NoSchedule
EOF

# Wait for MultiClusterHub to be ready
oc wait --for=condition=Complete \
  multiclusterhub/multiclusterhub \
  -n open-cluster-management \
  --timeout=600s
```

### Step 3: Verify Hub Installation

```bash
# Check ACM operator status
oc get csv -n open-cluster-management

# Check MultiClusterHub status
oc get multiclusterhub -n open-cluster-management -o wide

# Check ACM pods
oc get pods -n open-cluster-management | grep -E "hub|manager|console"

# Access ACM Console
ACM_ROUTE=$(oc get route -n open-cluster-management-hub \
  multicloud-console -o jsonpath='{.spec.host}')
echo "ACM Console: https://$ACM_ROUTE"
```

## Spoke Cluster Registration

### Step 1: Generate Klusterlet Manifests

```bash
# From hub cluster, create cluster import
cat << 'EOF' | oc apply -f -
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: spoke-cluster-1
  labels:
    cloud: openstack
    region: us-west
    cluster-type: spoke
    workload: self-healing
spec:
  hubAcceptsClient: true
  leaseDurationSeconds: 60
EOF

# Get klusterlet manifests
oc get secret -n open-cluster-management \
  spoke-cluster-1-import \
  -o jsonpath='{.data.crds\.yaml}' | base64 -d > crds.yaml

oc get secret -n open-cluster-management \
  spoke-cluster-1-import \
  -o jsonpath='{.data.import\.yaml}' | base64 -d > import.yaml
```

### Step 2: Deploy Klusterlet on Spoke Cluster

```bash
# Switch to spoke cluster context
oc config use-context spoke-cluster-1

# Apply CRDs
oc apply -f crds.yaml

# Apply klusterlet manifests
oc apply -f import.yaml

# Wait for klusterlet to be ready
oc wait --for=condition=Ready \
  managedcluster/spoke-cluster-1 \
  -n open-cluster-management \
  --timeout=300s
```

### Step 3: Verify Spoke Registration

```bash
# From hub cluster
oc config use-context hub-cluster

# Check managed cluster status
oc get managedcluster spoke-cluster-1 -o wide

# Check klusterlet status on spoke
oc config use-context spoke-cluster-1
oc get pods -n open-cluster-management-agent

# Verify connectivity
oc logs -n open-cluster-management-agent \
  -l app=klusterlet-agent \
  --tail=50
```

## GitOps Integration

### Step 1: Create ApplicationSet for Hub

```bash
# Create ApplicationSet for hub deployment
cat << 'EOF' | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: self-healing-hub
  namespace: openshift-gitops
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          local-cluster: "true"
  template:
    metadata:
      name: self-healing-hub
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/self-healing-platform
        targetRevision: main
        path: charts/hub
        helm:
          values: |
            global:
              environment: hub
              cluster: local-cluster
      destination:
        server: https://kubernetes.default.svc
        namespace: self-healing-platform
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
EOF
```

### Step 2: Create ApplicationSet for Spokes

```bash
# Create ApplicationSet for spoke deployments
cat << 'EOF' | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: self-healing-spokes
  namespace: openshift-gitops
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          cluster-type: spoke
  template:
    metadata:
      name: self-healing-{{name}}
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/self-healing-platform
        targetRevision: main
        path: charts/spoke
        helm:
          values: |
            global:
              environment: spoke
              cluster: {{name}}
              hubCluster: hub-cluster
      destination:
        server: '{{server}}'
        namespace: self-healing-platform
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
EOF
```

## Policy Management

### Step 1: Create Cluster Policy

```bash
# Create policy for cluster configuration
cat << 'EOF' | oc apply -f -
apiVersion: policy.open-cluster-management.io/v1
kind: Policy
metadata:
  name: self-healing-platform-policy
  namespace: open-cluster-management-policies
spec:
  remediationAction: enforce
  disabled: false
  policy-templates:
  - objectDefinition:
      apiVersion: policy.open-cluster-management.io/v1
      kind: ConfigurationPolicy
      metadata:
        name: self-healing-namespace
      spec:
        remediationAction: enforce
        severity: high
        object-templates:
        - complianceType: musthave
          objectDefinition:
            apiVersion: v1
            kind: Namespace
            metadata:
              name: self-healing-platform
              labels:
                workload: self-healing
EOF
```

### Step 2: Bind Policy to Clusters

```bash
# Create PlacementBinding
cat << 'EOF' | oc apply -f -
apiVersion: policy.open-cluster-management.io/v1
kind: PlacementBinding
metadata:
  name: self-healing-platform-binding
  namespace: open-cluster-management-policies
placementRef:
  name: self-healing-clusters
  kind: Placement
  apiGroup: cluster.open-cluster-management.io
subjects:
- name: self-healing-platform-policy
  kind: Policy
  apiGroup: policy.open-cluster-management.io
EOF

# Create Placement for spoke clusters
cat << 'EOF' | oc apply -f -
apiVersion: cluster.open-cluster-management.io/v1beta1
kind: Placement
metadata:
  name: self-healing-clusters
  namespace: open-cluster-management-policies
spec:
  predicates:
  - requiredClusterSelector:
      labelSelector:
        matchLabels:
          cluster-type: spoke
EOF
```

## Monitoring & Observability

### Step 1: Enable Metrics Collection

```bash
# Enable observability addon on hub
cat << 'EOF' | oc apply -f -
apiVersion: observability.open-cluster-management.io/v1beta2
kind: MultiClusterObservability
metadata:
  name: observability
  namespace: open-cluster-management-observability
spec:
  enableDownsampling: true
  enableMetrics: true
  observabilityAddonSpec:
    interval: 300
    metrics:
      interval: 300
  storageConfig:
    metricObjectStorage:
      name: thanos-object-storage
      key: thanos.yaml
EOF
```

### Step 2: Configure Grafana Dashboards

```bash
# Create ConfigMap with Grafana dashboard
cat << 'EOF' | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: self-healing-dashboard
  namespace: open-cluster-management-observability
data:
  dashboard.json: |
    {
      "dashboard": {
        "title": "Self-Healing Platform - Multi-Cluster",
        "panels": [
          {
            "title": "Cluster Status",
            "targets": [
              {
                "expr": "count(up{job=\"kubernetes-apiservers\"}) by (cluster)"
              }
            ]
          }
        ]
      }
    }
EOF
```

## Troubleshooting

### Common Issues

**Issue: Klusterlet fails to connect to hub**

```bash
# Check klusterlet logs
oc logs -n open-cluster-management-agent \
  -l app=klusterlet-agent \
  --tail=100

# Verify network connectivity
oc exec -n open-cluster-management-agent \
  -it $(oc get pod -n open-cluster-management-agent \
    -l app=klusterlet-agent -o jsonpath='{.items[0].metadata.name}') \
  -- curl -v https://hub-cluster-api:6443
```

**Issue: ApplicationSet not propagating to spokes**

```bash
# Check ApplicationSet status
oc get applicationset -n openshift-gitops -o wide

# Check ArgoCD Application status
oc get application -n openshift-gitops -o wide

# Check cluster selector
oc get managedcluster -L cluster-type
```

## Best Practices

1. **Cluster Labeling**: Use consistent labels for cluster selection
2. **Policy Enforcement**: Start with audit mode before enforcement
3. **Network Security**: Use network policies to restrict cluster communication
4. **Resource Quotas**: Set resource quotas on spoke clusters
5. **Backup Strategy**: Enable cluster backup for disaster recovery
6. **Monitoring**: Monitor ACM components and cluster health
7. **Documentation**: Maintain runbooks for common operations
8. **Testing**: Test policies and applications in staging first

---

**For more information:**
- [Red Hat ACM Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/)
- [ADR-022: Multi-Cluster Support](./adrs/022-multi-cluster-support-acm-integration.md)
- [Validated Patterns Framework](https://validatedpatterns.io/)
