# Configuration Reference

Complete reference for all configuration options in the OpenShift AI Ops Self-Healing Platform.

## Overview

The platform uses two primary configuration files:

- **values-global.yaml** - Global pattern configuration (git repository, sync policy, global resources)
- **values-hub.yaml** - Hub cluster configuration (storage, applications, operators, deployment-specific settings)

Both files must be created from their `.example` templates before deployment:

```bash
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml
```

---

## values-global.yaml Configuration

### Global Pattern Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `global.pattern` | string | `self-healing-platform` | Pattern name (must match directory name) |
| `global.version` | string | `1.0.0` | Pattern version |
| `global.clusterDomain` | string | `""` (auto-detected) | OpenShift baseDomain (e.g., "ocp.example.com"). Auto-populated by VP operator. Get via: `oc get dns cluster -o jsonpath='{.spec.baseDomain}'` |
| `global.analyticsUUID` | string | `""` | Optional analytics UUID for tracking |

**Example**:
```yaml
global:
  pattern: self-healing-platform
  version: "1.0.0"
  clusterDomain: ""  # Auto-detected
```

### Main Pattern Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `main.multiSourceConfig.enabled` | boolean | `true` | Enable multisource configuration (uses external Helm charts) |
| `main.multiSourceConfig.clusterGroupChartVersion` | string | `0.9.*` | Cluster group chart version (0.9.* for multisource) |
| `main.clusterGroupName` | string | `hub` | Cluster group name (hub cluster) |
| `main.targetSite` | string | `hub` | Target site for multi-cluster deployments |
| `main.gitOpsOperator` | string | `openshift-gitops` | OpenShift GitOps (ArgoCD) operator namespace |
| `main.namespace` | string | `self-healing-platform` | Namespace for pattern deployment |
| `main.components.openshift-ai` | boolean | `true` | Enable OpenShift AI (RHODS) |
| `main.components.gpu-operator` | boolean | `true` | Enable GPU Operator |
| `main.components.serverless` | boolean | `true` | Enable OpenShift Serverless |
| `main.components.service-mesh` | boolean | `false` | Enable Service Mesh |
| `main.components.pipelines` | boolean | `true` | Enable OpenShift Pipelines |
| `main.components.acm` | boolean | `false` | Enable Advanced Cluster Management |

### Git Repository Configuration

**⚠️ CRITICAL**: Update `git.repoURL` to YOUR fork's URL before deployment.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `git.repoURL` | string | `https://github.com/KubeHeal/openshift-aiops-platform.git` | **MUST UPDATE** - Git repository URL (GitHub, Gitea, GitLab). Single source of truth for ArgoCD sync. |
| `git.revision` | string | `main` | Git branch/revision to deploy from |
| `git.credentials.username` | string | `""` | Gitea/GitHub username (overridden by values-secret.yaml) |
| `git.credentials.password` | string | `""` | Gitea/GitHub password or token (overridden by values-secret.yaml) |
| `git.credentials.secretName` | string | `git-credentials` | Secret name for credentials (created by ESO or manually) |

**Example**:
```yaml
git:
  repoURL: "https://github.com/YOUR-USERNAME/openshift-aiops-platform.git"
  revision: "main"
  credentials:
    secretName: "git-credentials"
```

### Secret Management Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `secrets.backend` | string | `external-secrets` | Secret backend: `vault`, `sealed-secrets`, or `external-secrets` |
| `secrets.externalSecrets.enabled` | boolean | `true` | Enable External Secrets Operator |
| `secrets.externalSecrets.serviceAccount.name` | string | `external-secrets-sa` | Service account for ESO |
| `secrets.externalSecrets.secretStore.name` | string | `kubernetes-secret-store` | SecretStore name |
| `secrets.externalSecrets.secretStore.kind` | string | `SecretStore` | SecretStore kind |
| `secrets.externalSecrets.caProvider.enabled` | boolean | `true` | Enable CA provider for secure Kubernetes API communication |
| `secrets.externalSecrets.caProvider.type` | string | `ConfigMap` | CA provider type |
| `secrets.externalSecrets.caProvider.name` | string | `kube-root-ca.crt` | CA ConfigMap name |
| `secrets.externalSecrets.caProvider.key` | string | `ca.crt` | CA key in ConfigMap |
| `secrets.externalSecrets.refreshInterval` | string | `1h` | Refresh interval for syncing secrets |

### Object Store Configuration (Global)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `objectStore.enabled` | boolean | `true` | Enable object store integration (ODF/NooBaa) |
| `objectStore.endpoint` | string | `https://s3.openshift-storage.svc:443` | S3 endpoint URL (auto-detected from NooBaa if not provided) |
| `objectStore.accessKey` | string | `admin` | S3 access key (overridden by values-secret.yaml) |
| `objectStore.secretKey` | string | `changeme` | S3 secret key (overridden by values-secret.yaml) |
| `objectStore.buckets.models` | string | `model-storage` | Model storage bucket name |
| `objectStore.buckets.trainingData` | string | `training-data` | Training data bucket name |
| `objectStore.buckets.inferenceResults` | string | `inference-results` | Inference results bucket name |
| `objectStore.region` | string | `us-east-1` | AWS region |
| `objectStore.sslVerify` | boolean | `false` | SSL verification |
| `objectStore.vault.address` | string | `""` | Vault server address (fallback) |
| `objectStore.vault.namespace` | string | `""` | Vault namespace (for Vault Enterprise) |
| `objectStore.vault.authMethod` | string | `kubernetes` | Vault auth method: `kubernetes`, `jwt`, or `userpass` |
| `objectStore.vault.role` | string | `self-healing-platform` | Vault role for Kubernetes auth |
| `objectStore.vault.secretPath` | string | `secret/data/self-healing-platform` | Vault path for secrets |

### Storage Configuration (Global)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `storage.storageClass` | string | `""` (cluster default) | Storage class for persistent volumes |
| `storage.dataVolumeSize` | string | `5Gi` | Data volume size |
| `storage.modelsVolumeSize` | string | `10Gi` | Models volume size |
| `storage.logsVolumeSize` | string | `5Gi` | Logs volume size |

### Networking Configuration (Global)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `networking.networkPolicies` | boolean | `true` | Enable network policies |
| `networking.ingress.enabled` | boolean | `true` | Enable ingress |
| `networking.ingress.className` | string | `openshift` | Ingress class name |
| `networking.ingress.domain` | string | `""` (auto-detected) | Ingress domain |
| `networking.ingress.tls.enabled` | boolean | `true` | Enable TLS |
| `networking.ingress.tls.issuer` | string | `letsencrypt-prod` | TLS issuer |

### Monitoring and Observability (Global)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `monitoring.prometheus` | boolean | `true` | Enable Prometheus monitoring |
| `monitoring.grafana` | boolean | `true` | Enable Grafana dashboards |
| `monitoring.retention` | string | `15d` | Retention period for metrics |
| `monitoring.scrapeInterval` | string | `30s` | Scrape interval |

### Logging Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `logging.enabled` | boolean | `true` | Enable centralized logging |
| `logging.level` | string | `info` | Log level: `debug`, `info`, `warn`, `error` |
| `logging.retention` | string | `7d` | Log retention period |

### Application Configuration (Global)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `application.coordinationEngine.replicas` | integer | `1` | Coordination engine replicas |
| `application.coordinationEngine.resources.requests.memory` | string | `512Mi` | Memory request |
| `application.coordinationEngine.resources.requests.cpu` | string | `250m` | CPU request |
| `application.coordinationEngine.resources.limits.memory` | string | `1Gi` | Memory limit |
| `application.coordinationEngine.resources.limits.cpu` | string | `500m` | CPU limit |
| `application.workbench.replicas` | integer | `1` | Workbench replicas |
| `application.workbench.resources.requests.memory` | string | `1Gi` | Memory request |
| `application.workbench.resources.requests.cpu` | string | `500m` | CPU request |
| `application.workbench.resources.limits.memory` | string | `2Gi` | Memory limit |
| `application.workbench.resources.limits.cpu` | string | `1000m` | CPU limit |
| `application.modelServing.enabled` | boolean | `true` | Enable model serving |
| `application.modelServing.replicas` | integer | `1` | Model serving replicas |
| `application.modelServing.sklearn.image` | string | `kserve/sklearnserver:latest` | Sklearn serving image |
| `application.modelServing.tensorflow.image` | string | `kserve/tfserving:latest` | TensorFlow serving image |

### Environment-Specific Settings

#### Development Environment

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `development.debug` | boolean | `false` | Enable debug logging |
| `development.devFeatures` | boolean | `true` | Enable development features |
| `development.imagePullPolicy` | string | `IfNotPresent` | Image pull policy |
| `development.replicas` | integer | `1` | Default replicas for development |

#### Production Environment

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `production.debug` | boolean | `false` | Enable debug logging |
| `production.prodFeatures` | boolean | `true` | Enable production features |
| `production.imagePullPolicy` | string | `Always` | Image pull policy |
| `production.replicas` | integer | `3` | Default replicas for production |
| `production.ha` | boolean | `true` | Enable high availability |
| `production.podDisruptionBudgets` | boolean | `true` | Enable pod disruption budgets |

### Tekton Pipelines Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `tekton.enabled` | boolean | `true` | Enable Tekton pipelines |
| `tekton.namespace` | string | `openshift-pipelines` | Tekton namespace |
| `tekton.s3ConfigurationPipeline.enabled` | boolean | `true` | Enable S3 configuration pipeline |
| `tekton.s3ConfigurationPipeline.timeout` | string | `300` | Pipeline timeout (seconds) |

### GitOps Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `gitOps.namespace` | string | `openshift-gitops` | ArgoCD namespace |
| `gitOps.serverUrl` | string | `""` (auto-detected) | ArgoCD server URL |
| `gitOps.syncPolicy.automated.prune` | boolean | `true` | Auto-prune resources |
| `gitOps.syncPolicy.automated.selfHeal` | boolean | `true` | Auto-heal resources |
| `gitOps.syncPolicy.syncOptions` | array | See example | Sync options |
| `gitOps.retry.limit` | integer | `5` | Retry limit |
| `gitOps.retry.backoff.duration` | string | `5s` | Initial backoff duration |
| `gitOps.retry.backoff.factor` | integer | `2` | Backoff multiplier |
| `gitOps.retry.backoff.maxDuration` | string | `3m` | Max backoff duration |

**Example**:
```yaml
gitOps:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

### Compliance and Security

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `compliance.rbac` | boolean | `true` | Enable RBAC |
| `compliance.networkPolicies` | boolean | `true` | Enable network policies |
| `compliance.podSecurityPolicies` | boolean | `true` | Enable pod security policies |
| `compliance.auditLogging` | boolean | `true` | Enable audit logging |
| `compliance.securityContext.runAsNonRoot` | boolean | `true` | Run as non-root |
| `compliance.securityContext.runAsUser` | integer | `1000` | User ID |
| `compliance.securityContext.fsGroup` | integer | `1000` | Filesystem group ID |

### Feature Flags (Global)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `features.experimental` | boolean | `false` | Enable experimental features |
| `features.beta` | boolean | `false` | Enable beta features |
| `features.aiml` | boolean | `true` | Enable AI/ML features |
| `features.edge` | boolean | `false` | Enable edge deployment |

### Metadata (Global)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `metadata.owner` | string | `platform-team` | Owner/team |
| `metadata.environment` | string | `development` | Environment |
| `metadata.costCenter` | string | `""` | Cost center (for billing) |
| `metadata.tags.project` | string | `self-healing-platform` | Project tag |
| `metadata.tags.managed-by` | string | `validated-patterns` | Managed-by tag |
| `metadata.tags.version` | string | `1.0.0` | Version tag |

---

## values-hub.yaml Configuration

### Cluster Topology Configuration

**⚠️ CRITICAL for SNO deployments**: Update `cluster.topology` to `sno` and change storage classes to `gp3-csi`.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `cluster.topology` | string | `ha` | Cluster topology: `ha` (HighlyAvailable multi-node) or `sno` (Single Node OpenShift). **Must match actual cluster**. Verify with: `make show-cluster-info` |
| `cluster.version` | string | `4.18` (auto-detected) | OpenShift version (auto-detected during deployment) |

**SNO Configuration Example**:
```yaml
cluster:
  topology: "sno"

storage:
  modelStorage:
    storageClass: "gp3-csi"  # Changed from ocs-storagecluster-cephfs
```

### Main Cluster Group Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `main.clusterGroupName` | string | `hub` | Cluster group name |
| `main.targetSite` | string | `hub` | Target site for this deployment |
| `main.gitOpsOperator` | string | `openshift-gitops` | OpenShift GitOps operator namespace |
| `main.namespace` | string | `self-healing-platform` | Namespace for pattern deployment |

### Namespace Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `namespace.create` | boolean | `false` | **MUST BE FALSE** - Namespace already exists with OpenShift-specific annotations, don't recreate it |
| `namespace.name` | string | `self-healing-platform` | Namespace name |
| `namespace.git.repoURL` | string | `""` (overridden) | Repository URL (will be overridden - see values-global.yaml) |
| `namespace.git.revision` | string | `""` (overridden) | Branch to deploy from (will be overridden - see values-global.yaml) |
| `namespace.helm.clusterGroupChartVersion` | string | `0.9.*` | Helm chart repository version |
| `namespace.helm.extraValues` | array | `[]` | Additional Helm options |

### ClusterGroup Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `clusterGroup.name` | string | `hub` | ClusterGroup name |
| `clusterGroup.isHubCluster` | boolean | `true` | Is this a hub cluster? |
| `clusterGroup.namespaces.self-healing-platform.labels."openshift.io/cluster-monitoring"` | string | `"true"` | Enable cluster monitoring |
| `clusterGroup.namespaces.self-healing-platform.annotations."openshift.io/description"` | string | Descriptive text | Namespace description |

### ArgoCD Application Configuration

**⚠️ CRITICAL**: Update `clusterGroup.applications.self-healing-platform.repoURL` to YOUR fork's URL.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `clusterGroup.applications.self-healing-platform.name` | string | `self-healing-platform` | Application name |
| `clusterGroup.applications.self-healing-platform.namespace` | string | `self-healing-platform` | Target namespace |
| `clusterGroup.applications.self-healing-platform.project` | string | `default` | ArgoCD project |
| `clusterGroup.applications.self-healing-platform.path` | string | `charts/hub` | Helm chart path in repository |
| `clusterGroup.applications.self-healing-platform.repoURL` | string | `https://github.com/YOUR-USERNAME/...` | **MUST UPDATE** - Your forked repository URL |
| `clusterGroup.applications.self-healing-platform.targetRevision` | string | `main` | Git branch |
| `clusterGroup.applications.self-healing-platform.helm.valueFiles` | array | See example | Values files to use |
| `clusterGroup.applications.self-healing-platform.syncPolicy.automated.prune` | boolean | `true` | Auto-prune resources |
| `clusterGroup.applications.self-healing-platform.syncPolicy.automated.selfHeal` | boolean | `true` | Auto-heal resources |
| `clusterGroup.applications.self-healing-platform.syncPolicy.retry.limit` | integer | `5` | Retry limit |

**Example**:
```yaml
clusterGroup:
  applications:
    self-healing-platform:
      repoURL: "https://github.com/YOUR-USERNAME/openshift-aiops-platform.git"
      helm:
        valueFiles:
          - /values-global.yaml
          - /values-hub.yaml
          - charts/hub/values-notebooks-validation.yaml
```

### Workbench Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `workbench.enabled` | boolean | `true` | Enable workbench |
| `workbench.gpu.enabled` | boolean | `true` | Enable GPU support for AI/ML model training and inference |

### Storage Configuration

#### Basic Storage

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `storage.storageClass` | string | `""` (cluster default) | Storage class for persistent volumes |
| `storage.dataVolumeSize` | string | `5Gi` | Data volume size |
| `storage.modelsVolumeSize` | string | `10Gi` | Models volume size |
| `storage.logsVolumeSize` | string | `5Gi` | Logs volume size |

#### Self-Healing Data Storage

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `storage.selfHealingData.size` | string | `10Gi` | Self-healing data storage size |
| `storage.selfHealingData.storageClass` | string | `gp3-csi` | Storage class |

#### Model Artifacts Storage

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `storage.modelArtifacts.size` | string | `50Gi` | Model artifacts storage size |
| `storage.modelArtifacts.storageClass` | string | `ocs-storagecluster-cephfs` (HA) / `gp3-csi` (SNO) | Storage class (RWX for HA, RWO for SNO) |

#### Model Storage PVC

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `storage.modelStorage.size` | string | `10Gi` | Model storage PVC size (shared between notebooks and KServe) |
| `storage.modelStorage.storageClass` | string | `ocs-storagecluster-cephfs` (HA) / `gp3-csi` (SNO) | **CRITICAL**: Use `ocs-storagecluster-cephfs` (RWX) on HA clusters, `gp3-csi` (RWO) on SNO |

#### Workbench Data Storage

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `storage.workbenchData.size` | string | `20Gi` | Workbench data storage size |
| `storage.workbenchData.storageClass` | string | `gp3-csi` | Storage class |

### Object Store Configuration (Hub)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `objectStore.enabled` | boolean | `true` | **Always enabled** - Provides S3 storage. HA: full ODF (Ceph + NooBaa), SNO: MCG-only ODF (NooBaa without Ceph) |
| `objectStore.endpoint` | string | `https://s3.openshift-storage.svc:443` | S3 endpoint URL |
| `objectStore.region` | string | `us-east-1` | AWS region |
| `objectStore.sslVerify` | boolean | `false` | SSL verification |
| `objectStore.buckets.models` | string | `model-storage` | Model storage bucket |
| `objectStore.buckets.trainingData` | string | `training-data` | Training data bucket |
| `objectStore.buckets.inferenceResults` | string | `inference-results` | Inference results bucket |

### Networking Configuration (Hub)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `networking.networkPolicies` | boolean | `true` | Enable network policies |
| `networking.serviceMesh` | boolean | `false` | Enable service mesh |
| `networking.ingress.enabled` | boolean | `true` | Enable ingress |
| `networking.ingress.className` | string | `openshift` | Ingress class name |

### Security Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `security.rbac` | boolean | `true` | Enable RBAC |
| `security.podSecurityPolicies` | boolean | `true` | Enable pod security policies |
| `security.securityContext.runAsNonRoot` | boolean | `true` | Run as non-root |
| `security.securityContext.runAsUser` | integer | `1000` | User ID |
| `security.securityContext.fsGroup` | integer | `1000` | Filesystem group ID |
| `security.networkPolicies` | boolean | `true` | Enable network policies |

### Secrets Management (Hub)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `secrets.backend` | string | `external-secrets` | Secret backend: `vault`, `sealed-secrets`, or `external-secrets` |
| `secrets.vault.address` | string | `""` | Vault server address (set during deployment) |
| `secrets.vault.namespace` | string | `""` | Vault namespace (for Vault Enterprise) |
| `secrets.vault.authMethod` | string | `kubernetes` | Vault auth method: `kubernetes`, `jwt`, or `userpass` |
| `secrets.vault.role` | string | `self-healing-platform` | Vault role for Kubernetes auth |
| `secrets.vault.secretPath` | string | `secret/data/self-healing-platform` | Vault path for secrets |

### Model Serving Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `modelServing.enabled` | boolean | `true` | Enable model serving |
| `modelServing.sklearn.image` | string | `kserve/sklearnserver:latest` | Sklearn runtime image |
| `modelServing.sklearn.resources.requests.memory` | string | `256Mi` | Memory request |
| `modelServing.sklearn.resources.requests.cpu` | string | `100m` | CPU request |
| `modelServing.sklearn.resources.limits.memory` | string | `512Mi` | Memory limit |
| `modelServing.sklearn.resources.limits.cpu` | string | `500m` | CPU limit |
| `modelServing.tensorflow.image` | string | `kserve/tfserving:latest` | TensorFlow runtime image |
| `modelServing.tensorflow.resources.requests.memory` | string | `512Mi` | Memory request |
| `modelServing.tensorflow.resources.requests.cpu` | string | `200m` | CPU request |
| `modelServing.tensorflow.resources.limits.memory` | string | `1Gi` | Memory limit |
| `modelServing.tensorflow.resources.limits.cpu` | string | `1000m` | CPU limit |

### Monitoring and Observability (Hub)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `monitoring.prometheus.enabled` | boolean | `true` | Enable Prometheus |
| `monitoring.prometheus.retention` | string | `30d` | Retention period |
| `monitoring.grafana.enabled` | boolean | `true` | Enable Grafana |
| `monitoring.grafana.adminPassword` | string | `""` (from secrets) | Grafana admin password |
| `monitoring.alerting.enabled` | boolean | `true` | Enable alerting |
| `monitoring.serviceMonitors` | array | See example | Service monitors list |

**Example**:
```yaml
monitoring:
  serviceMonitors:
    - coordination-engine
    - mcp-server
    - self-healing-platform
```

### Notebook Validation Configuration

**References**: ADR-029, ADR-030  
**Documentation**: [docs/NOTEBOOK-VALIDATION-ARGOCD.md](../NOTEBOOK-VALIDATION-ARGOCD.md)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `notebooks.validation.enabled` | boolean | `true` | Enable ArgoCD-based notebook validation |
| `notebooks.validation.git.url` | string | `""` (from values-global.yaml) | Git repository URL (falls back to values-global.yaml git.repoURL) |
| `notebooks.validation.git.ref` | string | `main` | Git branch |
| `notebooks.validation.git.credentialsSecret` | string | `github-pat-credentials` | GitHub PAT secret (must be created before deployment). See: /tmp/github-pat-quick-start.md or docs/NOTEBOOK-VALIDATION-ARGOCD.md |
| `notebooks.validation.containerImage` | string | `image-registry.openshift-image-registry.svc:5000/self-healing-platform/notebook-validator:latest` | Default container image for notebook execution (HYBRID APPROACH: RHOAI base + validation tools via BuildConfig) |
| `notebooks.validation.tierImages.tier1` | string | `...s2i-minimal-notebook:2025.1` | Tier 1 image override (fast startup) |
| `notebooks.validation.tierImages.tier2` | string | `...pytorch:2025.1` | Tier 2 image override (ML workloads) |
| `notebooks.validation.tierImages.tier3` | string | `...pytorch:2025.1` | Tier 3 image override (GPU-enabled) |
| `notebooks.validation.fallbackImage` | string | `quay.io/jupyter/scipy-notebook:latest` | Fallback public image (only if RHOAI images unavailable) |
| `notebooks.validation.buildConfig.enabled` | boolean | `true` | Enable BuildConfig (HYBRID: RHOAI base + validation tools) |
| `notebooks.validation.buildConfig.baseImage` | string | `...pytorch:2025.1` | Base image for BuildConfig |
| `notebooks.validation.buildConfig.noCache` | boolean | `false` | Disable build cache |
| `notebooks.validation.buildConfig.imageChangeTrigger` | boolean | `true` | Enable image change triggers |
| `notebooks.validation.buildConfig.pullSecret` | string | `""` | Pull secret for base image |
| `notebooks.validation.timeout` | string | `30m` | Default timeout for notebook validation |
| `notebooks.validation.resources.requests.memory` | string | `2Gi` | Default memory request (tier1) |
| `notebooks.validation.resources.requests.cpu` | string | `1000m` | Default CPU request (tier1) |
| `notebooks.validation.resources.limits.memory` | string | `4Gi` | Default memory limit (tier1) |
| `notebooks.validation.resources.limits.cpu` | string | `2000m` | Default CPU limit (tier1) |
| `notebooks.validation.operatorImage` | string | `quay.io/takinosh/jupyter-notebook-validator-operator:release-4.20-f655671` | Operator image |

#### Tier-Specific Configuration

**Tier 1: Simple notebooks (ArgoCD Sync Wave 10)**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `notebooks.validation.tiers.tier1.enabled` | boolean | `true` | Enable tier 1 validation |
| `notebooks.validation.tiers.tier1.notebooks` | array | See values file | Notebooks to validate (prerequisites, data collection) |

**Tier 2: Intermediate notebooks (ArgoCD Sync Wave 20)**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `notebooks.validation.tiers.tier2.enabled` | boolean | `true` | Enable tier 2 validation (ML training) |
| `notebooks.validation.tiers.tier2.notebooks` | array | See values file | Notebooks to validate (ML model training, integration) |
| `notebooks.validation.tiers.tier2.resources.requests.memory` | string | `4Gi` | Memory request |
| `notebooks.validation.tiers.tier2.resources.requests.cpu` | string | `2000m` | CPU request |
| `notebooks.validation.tiers.tier2.resources.limits.memory` | string | `8Gi` | Memory limit |
| `notebooks.validation.tiers.tier2.resources.limits.cpu` | string | `4000m` | CPU limit |
| `notebooks.validation.tiers.tier2.timeout` | string | `30m` | Timeout |

**Tier 3: Advanced notebooks (ArgoCD Sync Wave 30)**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `notebooks.validation.tiers.tier3.enabled` | boolean | `false` | Enable tier 3 validation (enable after tier1+tier2 pass) |
| `notebooks.validation.tiers.tier3.notebooks` | array | See values file | Notebooks to validate (model serving, end-to-end scenarios) |
| `notebooks.validation.tiers.tier3.resources.requests.memory` | string | `6Gi` | Memory request |
| `notebooks.validation.tiers.tier3.resources.requests.cpu` | string | `3000m` | CPU request |
| `notebooks.validation.tiers.tier3.resources.limits.memory` | string | `12Gi` | Memory limit |
| `notebooks.validation.tiers.tier3.resources.limits.cpu` | string | `6000m` | CPU limit |
| `notebooks.validation.tiers.tier3.timeout` | string | `45m` | Timeout |
| `notebooks.validation.tiers.tier3.gpu.enabled` | boolean | `false` | Enable GPU (set to true for GPU-enabled notebooks) |
| `notebooks.validation.tiers.tier3.gpu.count` | string | `"1"` | GPU count |

### Feature Flags (Hub)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `features.experimental` | boolean | `false` | Enable experimental features |
| `features.beta` | boolean | `false` | Enable beta features |
| `features.aiml` | boolean | `true` | Enable AI/ML features |
| `features.edge` | boolean | `false` | Enable edge deployment |

### Metadata (Hub)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `metadata.owner` | string | `platform-team` | Owner/team |
| `metadata.environment` | string | `development` | Environment |
| `metadata.costCenter` | string | `""` | Cost center (for billing) |
| `metadata.tags.project` | string | `self-healing-platform` | Project tag |
| `metadata.tags.managed-by` | string | `validated-patterns` | Managed-by tag |
| `metadata.tags.version` | string | `1.0.0` | Version tag |
| `metadata.tags.framework` | string | `openshift-gitops` | Framework tag |

---

## Environment Variables

### Ansible Execution Environment

| Variable | Description | Example |
|----------|-------------|---------|
| `ANSIBLE_HUB_TOKEN` | Red Hat Ansible Automation Hub token (for building execution environment locally) | `eyJhbGc...` |
| `KUBECONFIG` | Kubernetes/OpenShift configuration file path | `~/.kube/config` |
| `OC_LOGIN_TOKEN` | OpenShift login token (alternative to password) | `sha256~abc...` |

### Build Environment

| Variable | Description | Example |
|----------|-------------|---------|
| `CONTAINER_RUNTIME` | Container runtime to use | `podman` (default) or `docker` |
| `EE_IMAGE_NAME` | Execution environment image name | `openshift-aiops-platform-ee` |
| `EE_IMAGE_TAG` | Execution environment image tag | `latest` |

---

## Quick Reference

### Critical Configuration Steps

1. **Create values files**:
   ```bash
   cp values-global.yaml.example values-global.yaml
   cp values-hub.yaml.example values-hub.yaml
   ```

2. **Update repoURL in BOTH files**:
   ```bash
   vi values-global.yaml  # Change git.repoURL
   vi values-hub.yaml     # Change clusterGroup.applications.self-healing-platform.repoURL
   ```

3. **For SNO deployments**, update `values-hub.yaml`:
   ```yaml
   cluster:
     topology: "sno"
   storage:
     modelStorage:
       storageClass: "gp3-csi"
   ```

4. **Verify configuration**:
   ```bash
   make show-cluster-info
   cat values-global.yaml | grep repoURL
   cat values-hub.yaml | grep repoURL
   ```

### Related Documentation

- [DEPLOYMENT.md](../../DEPLOYMENT.md) - Complete deployment guide
- [docs/how-to/deploy-on-sno.md](../how-to/deploy-on-sno.md) - SNO deployment guide
- [docs/NOTEBOOK-VALIDATION-ARGOCD.md](../NOTEBOOK-VALIDATION-ARGOCD.md) - Notebook validation configuration
- [ADR-026: Secrets Management Automation](../adrs/026-secrets-management-automation.md) - Secrets configuration
- [ADR-035: Storage Strategy](../adrs/035-storage-strategy.md) - Storage configuration
- [ADR-056: Standalone MCG on SNO](../adrs/056-standalone-mcg-on-sno.md) - SNO storage configuration
