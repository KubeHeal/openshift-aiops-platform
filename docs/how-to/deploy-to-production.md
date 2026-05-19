# Deploy to Production

This guide provides production-specific deployment procedures for the OpenShift AIOps Self-Healing Platform.

## Prerequisites

Before deploying to production, ensure you've:

✅ **Tested on non-production environments** (development, staging)
✅ **Reviewed all ADRs** in [docs/adrs/](../adrs/README.md)
✅ **Completed deployment readiness checklist** (see below)
✅ **Obtained necessary approvals** from security, operations, and stakeholders

## Production Readiness Checklist

### Infrastructure

- [ ] **High Availability (HA) cluster topology**
  - 3+ control plane nodes
  - 3+ worker nodes
  - GPU nodes for ML workloads (optional but recommended)
  - Verified with: `make show-cluster-info`

- [ ] **OpenShift Data Foundation (ODF) deployed**
  - Full ODF (Ceph + NooBaa), not MCG-only
  - Storage classes available: `ocs-storagecluster-cephfs`, `ocs-storagecluster-ceph-rbd`
  - Verified with: `oc get storagecluster -n openshift-storage`

- [ ] **Network configuration validated**
  - DNS resolution for all services
  - Ingress routes accessible
  - Firewall rules configured for external access (if needed)

- [ ] **Resource quotas and limits defined**
  - Namespace resource quotas
  - Pod resource requests/limits
  - Cluster autoscaling configured (if using cloud provider)

### Security

- [ ] **Secrets management configured**
  - External Secrets Operator deployed (ADR-026 - **MANDATORY**)
  - Secrets stored in external vault (not in Git)
  - Service account permissions reviewed

- [ ] **RBAC policies reviewed**
  - Principle of least privilege applied
  - Role bindings audited
  - Cluster admin permissions limited

- [ ] **Network policies enforced**
  - Namespace isolation configured
  - Ingress/egress rules defined
  - Pod-to-pod communication restricted

- [ ] **Image security**
  - Container images from trusted registries
  - Image vulnerability scanning enabled
  - Image pull policies configured (`Always` or `IfNotPresent`)

### Configuration

- [ ] **Values files customized for production**
  - `values-global.yaml` updated with production Git repository
  - `values-hub.yaml` configured with production settings
  - Resource limits appropriate for production workloads
  - Replica counts set for high availability

- [ ] **GitOps repository configured**
  - Fork created at your organization's GitHub/GitLab
  - `repoURL` updated in both values files
  - Branch protection rules enabled on main branch
  - PR approval workflow configured

- [ ] **Monitoring and observability**
  - Prometheus deployed and configured
  - Alertmanager rules defined
  - Grafana dashboards imported
  - Log aggregation configured (optional: OpenShift Logging)

### ML/AI Components

- [ ] **Model storage configured**
  - S3-compatible object storage (NooBaa) available
  - Model versioning strategy defined
  - Backup policy for trained models

- [ ] **GPU resources allocated** (if using GPU)
  - NVIDIA GPU Operator deployed
  - GPU node affinity/tolerations configured
  - GPU resource limits defined in workloads

- [ ] **Model serving validated**
  - KServe InferenceServices tested
  - Model endpoints accessible
  - Inference performance acceptable

### Validation and Testing

- [ ] **Deployment validation pipeline passed**
  - Tekton validation pipeline: `tkn pipeline start deployment-validation-pipeline --showlog`
  - All 26 validation checks passed
  - No errors in ArgoCD applications

- [ ] **Model training pipelines tested**
  - Anomaly detector training successful
  - Predictive analytics training successful (if using GPU)
  - Models deployed to KServe

- [ ] **Self-healing workflows verified**
  - Coordination engine responding
  - Health endpoints accessible
  - Integration with Prometheus/AlertManager working

---

## Production Deployment Steps

### Step 1: Prepare Production Environment

```bash
# Clone your organization's fork
git clone https://github.com/YOUR-ORG/openshift-aiops-platform.git
cd openshift-aiops-platform

# Create production branch (optional but recommended)
git checkout -b production
```

### Step 2: Configure Production Values

```bash
# Create production values files
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml

# Update repoURL to your organization's fork
vi values-global.yaml
# Change: repoURL: "https://github.com/YOUR-ORG/openshift-aiops-platform.git"

vi values-hub.yaml
# Change: repoURL: "https://github.com/YOUR-ORG/openshift-aiops-platform.git"
```

**Production-specific values.yaml settings**:

```yaml
# values-hub.yaml - Production settings
cluster:
  topology: "ha"  # High Availability

workbench:
  replicas: 2  # HA for workbench (optional)
  resources:
    requests:
      cpu: "4"
      memory: "16Gi"
    limits:
      cpu: "8"
      memory: "32Gi"

coordinationEngine:
  replicas: 3  # HA for coordination engine
  resources:
    requests:
      cpu: "2"
      memory: "4Gi"
    limits:
      cpu: "4"
      memory: "8Gi"

storage:
  modelStorage:
    size: "100Gi"  # Larger for production models
    storageClass: "ocs-storagecluster-cephfs"

objectStore:
  enabled: true  # Required for model artifacts
```

### Step 3: Verify Cluster Configuration

```bash
# Login to production cluster
oc login <production-cluster-api-url>

# Verify cluster topology
make show-cluster-info

# Expected output:
# Cluster Topology Information:
#   Type: HA (HighlyAvailable)
#   Control Plane: HighlyAvailable
#   Infrastructure: HighlyAvailable
```

### Step 4: Configure Infrastructure

```bash
# Install ODF and scale MachineSets (if needed)
make configure-cluster

# This command will:
# - Install OpenShift Data Foundation (full ODF)
# - Scale MachineSets to ensure sufficient workers
# - Wait for storage cluster to be ready
```

**Note**: This step takes 10-15 minutes on HA clusters.

### Step 5: Deploy Execution Environment

**Option A: Use Pre-Built Image** (Recommended)

```bash
podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest \
  openshift-aiops-platform-ee:latest
```

**Option B: Build Locally** (if customized)

```bash
export ANSIBLE_HUB_TOKEN='your-token-here'
podman login registry.redhat.io
make token
make build-ee
```

### Step 6: Run Pre-Deployment Validation

```bash
# Validate cluster prerequisites
make check-prerequisites

# Expected output:
# ✅ OpenShift version: 4.18+
# ✅ Cluster admin access: confirmed
# ✅ ODF deployed: yes
# ✅ Storage classes: available
```

### Step 7: Deploy Platform

```bash
# Run Ansible prerequisites
make operator-deploy-prereqs

# Deploy via Validated Patterns Operator
make operator-deploy
```

**What happens**:
1. Creates namespaces (`self-healing-platform`, `self-healing-platform-hub`)
2. Deploys RBAC resources (ServiceAccounts, Roles, ClusterRoles)
3. Creates External Secrets configuration
4. Deploys Validated Patterns Operator
5. Creates Pattern CR
6. Operator creates ArgoCD Application
7. ArgoCD deploys all platform components

### Step 8: Monitor Deployment Progress

```bash
# Watch ArgoCD application sync
watch oc get application -n self-healing-platform-hub

# Check pod status
watch oc get pods -n self-healing-platform

# View ArgoCD logs
oc logs -n self-healing-platform-hub \
  deployment/hub-gitops-application-controller -f
```

### Step 9: Validate Deployment

```bash
# Run ArgoCD health check
make argo-healthcheck

# Expected output:
# ✅ self-healing-platform: Healthy, Synced
# ✅ All applications: Healthy

# Run Tekton validation pipeline
tkn pipeline start deployment-validation-pipeline --showlog

# Expected: All 26 checks pass
```

### Step 10: Verify Model Training Pipelines

```bash
# Check initial model training status
tkn pipelinerun list -n self-healing-platform

# If training failed or wasn't triggered, manually start:

# Anomaly Detector (CPU-based)
tkn pipeline start model-training-pipeline \
  -p model-name=anomaly-detector \
  -p notebook-path=notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb \
  -p data-source=prometheus \
  -p training-hours=168 \
  -p inference-service-name=anomaly-detector \
  -p health-check-enabled=true \
  -p git-url=https://github.com/YOUR-ORG/openshift-aiops-platform.git \
  -p git-ref=main \
  -n self-healing-platform --showlog

# Predictive Analytics (GPU-based, if GPU available)
tkn pipeline start model-training-pipeline-gpu \
  -p model-name=predictive-analytics \
  -p notebook-path=notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb \
  -p data-source=prometheus \
  -p training-hours=720 \
  -p inference-service-name=predictive-analytics \
  -p health-check-enabled=true \
  -p git-url=https://github.com/YOUR-ORG/openshift-aiops-platform.git \
  -p git-ref=main \
  -n self-healing-platform --showlog
```

### Step 11: Configure Monitoring and Alerting

```bash
# Verify Prometheus is scraping platform metrics
oc get servicemonitor -n self-healing-platform

# Check Grafana dashboards (if installed)
# Import dashboards from: docs/monitoring/grafana-dashboards/

# Configure Alertmanager for production alerts
# Edit AlertManager configuration:
oc edit secret alertmanager-main -n openshift-monitoring
```

**Recommended alerts**:
- Coordination engine unhealthy
- Model inference errors
- KServe predictor pods failing
- High anomaly detection rate
- Workbench pod failures

### Step 12: Post-Deployment Verification

```bash
# Access workbench
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
# Open http://localhost:8888

# Test coordination engine
oc exec -n self-healing-platform \
  deployment/self-healing-coordination-engine -- \
  curl -s http://localhost:8080/health

# Test model endpoints
oc get inferenceservices -n self-healing-platform
```

### Step 13: Clean Up Extra Namespaces (Optional)

```bash
# Remove example namespaces created by Validated Patterns defaults
oc delete namespace self-healing-platform-example imperative --ignore-not-found=true
```

---

## Post-Deployment Configuration

### Enable External Access (if needed)

If users need to access services from outside the cluster:

```bash
# Create routes for coordination engine (example)
oc create route edge coordination-engine \
  --service=coordination-engine \
  --port=8080 \
  -n self-healing-platform

# Get route URL
oc get route coordination-engine -n self-healing-platform \
  -o jsonpath='{.spec.host}'
```

### Configure Backup and Recovery

**Backup strategy**:

1. **Etcd backups** (cluster-level) - configure via OpenShift
2. **Model artifacts** - stored in S3 (NooBaa) with versioning enabled
3. **Configuration** - stored in Git (GitOps principle)

```bash
# Verify ODF/NooBaa backup configuration
oc get objectbucketclaim model-storage -n self-healing-platform -o yaml

# Enable versioning on S3 bucket (via NooBaa UI or AWS S3 API)
```

### Configure Log Aggregation (Optional)

If using OpenShift Logging:

```bash
# Create ClusterLogForwarder to send platform logs to central location
cat <<EOF | oc apply -f -
apiVersion: logging.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  pipelines:
  - name: self-healing-platform-logs
    inputRefs:
    - application
    outputRefs:
    - default
    parse: json
    labels:
      platform: "aiops"
EOF
```

### Performance Tuning

**Coordination Engine**:

```yaml
# Increase replicas for higher load
coordinationEngine:
  replicas: 5
  resources:
    requests:
      cpu: "4"
      memory: "8Gi"
```

**KServe Predictors**:

```yaml
# Auto-scaling configuration
inferenceService:
  scaleTarget: 70  # CPU utilization target
  scaleMetric: cpu
  minReplicas: 2
  maxReplicas: 10
```

---

## Production Maintenance

### Rolling Updates

```bash
# Update values in Git repository
git add values-hub.yaml
git commit -s -m "feat: Increase coordination engine replicas"
git push origin production

# ArgoCD will automatically sync changes
# Monitor sync progress:
watch oc get application self-healing-platform -n self-healing-platform-hub
```

### Model Retraining

```bash
# Schedule periodic model retraining (example: weekly)
# Create CronJob for model training pipeline
cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: model-retraining-weekly
  namespace: self-healing-platform
spec:
  schedule: "0 2 * * 0"  # Every Sunday at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: tekton-triggers-sa
          containers:
          - name: trigger-training
            image: quay.io/openshift/origin-cli:latest
            command:
            - /bin/bash
            - -c
            - |
              tkn pipeline start model-training-pipeline \
                -p model-name=anomaly-detector \
                -p notebook-path=notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb \
                -n self-healing-platform
          restartPolicy: OnFailure
EOF
```

### Monitoring Health

```bash
# Create monitoring dashboard
# Check platform health daily:
make argo-healthcheck

# Review model inference metrics:
oc exec -n self-healing-platform \
  deployment/self-healing-coordination-engine -- \
  curl -s http://localhost:8090/metrics | grep inference
```

---

## Rollback Procedures

### Rollback ArgoCD Application

```bash
# Rollback to previous sync
oc patch application self-healing-platform \
  -n self-healing-platform-hub \
  --type merge \
  -p '{"operation":{"initiatedBy":{"automated":false}}}'

# Revert Git commit
git revert HEAD
git push origin production
```

### Rollback Model Deployment

```bash
# Redeploy previous model version
# Models are versioned in S3 storage
# Update InferenceService to point to previous model path
oc edit inferenceservice anomaly-detector -n self-healing-platform
```

---

## Troubleshooting

### ArgoCD Application Not Syncing

**Symptom**: Application shows "Unknown" or "Missing" health status

**Solution**:

```bash
# Check Pattern CR status
oc get pattern self-healing-platform -n openshift-operators -o yaml

# Verify ArgoCD controller has cluster-admin
oc get clusterrolebinding | grep hub-gitops-argocd-application-controller

# Re-run prerequisites if missing
make operator-deploy-prereqs

# Manually trigger sync
oc annotate application self-healing-platform \
  -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite
```

### Coordination Engine Not Responding

**Symptom**: Health endpoint returns 503 or connection refused

**Solution**:

```bash
# Check pod status
oc get pods -n self-healing-platform -l app.kubernetes.io/component=coordination-engine

# View logs
oc logs -n self-healing-platform \
  -l app.kubernetes.io/component=coordination-engine --tail=100

# Restart deployment
oc rollout restart deployment/coordination-engine -n self-healing-platform
```

### Model Training Pipeline Fails

**Symptom**: PipelineRun shows "Failed" status

**Solution**:

```bash
# View pipeline logs
tkn pipelinerun logs <pipelinerun-name> -n self-healing-platform

# Check S3 bucket credentials
oc get externalsecret model-storage-secret -n self-healing-platform

# Re-run prerequisites
make operator-deploy-prereqs

# Manually restart training pipeline (see Step 10)
```

---

## Production Best Practices

1. **Use GitOps** - All configuration in Git, deployed via ArgoCD
2. **Immutable infrastructure** - Rebuild, don't patch in place
3. **Test first** - Validate in dev/staging before production
4. **Monitor continuously** - Set up alerts for critical components
5. **Document changes** - Update ADRs for architectural decisions
6. **Regular backups** - Verify backup and restore procedures
7. **Security scanning** - Scan images and dependencies regularly
8. **Resource limits** - Always set requests and limits
9. **High availability** - Run multiple replicas of critical services
10. **Disaster recovery** - Have a tested recovery plan

---

## Next Steps

After successful production deployment:

- 📊 **Configure dashboards** - Import Grafana dashboards for monitoring
- 🔔 **Set up alerts** - Configure Alertmanager rules for critical events
- 📝 **Document runbooks** - Create operational procedures for your team
- 🧪 **Test recovery** - Practice backup and restore procedures
- 📈 **Monitor performance** - Establish baseline metrics and SLOs
- 🔄 **Plan updates** - Schedule regular platform updates and model retraining

---

## Related Documentation

- [Deployment Guide](../../DEPLOYMENT.md) - Complete step-by-step deployment
- [Fresh Cluster Deployment](../guides/FRESH-CLUSTER-DEPLOYMENT.md) - First-time deployment
- [Troubleshooting Guide](../guides/TROUBLESHOOTING-GUIDE.md) - Common issues and solutions
- [ADRs](../adrs/README.md) - Architectural decisions
- [Pattern CR Best Practices](../guides/PATTERN-CR-BEST-PRACTICES.md) - Advanced configuration

---

## Support

For issues or questions:

- 🐛 **Report bugs**: https://github.com/KubeHeal/openshift-aiops-platform/issues
- 📖 **Read documentation**: https://kubeheal.github.io/openshift-aiops-platform/
- 💬 **Ask questions**: Open a GitHub Discussion
