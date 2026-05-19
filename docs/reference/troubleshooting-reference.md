# Troubleshooting Reference

Quick reference guide for diagnosing and resolving common issues in the OpenShift AI Ops Self-Healing Platform.

## Error Code Catalog

### Coordination Engine Errors (E001-E006)

| Code | Severity | Description | Causes | Solutions |
|------|----------|-------------|---------|-----------|
| **E001** | Critical | Connection Error | Coordination engine cannot connect to Prometheus, KServe, or Tekton | 1. Check service endpoints<br>2. Verify network policies<br>3. Check RBAC permissions<br>4. Test connectivity: `curl http://coordination-engine:8080/health` |
| **E002** | High | Validation Error | Input validation failed (invalid JSON, missing required fields) | 1. Check request payload schema<br>2. Verify required fields are present<br>3. Check data types match API spec<br>4. Review API documentation: [docs/reference/api-documentation.md](api-documentation.md) |
| **E003** | High | Remediation Error | Remediation action failed to execute | 1. Check Tekton pipeline status<br>2. Verify RBAC permissions for remediation<br>3. Check ArgoCD sync status<br>4. Review logs: `oc logs deployment/coordination-engine -n self-healing-platform` |
| **E004** | Medium | Timeout Error | Request timeout (default 30s) | 1. Increase timeout in coordination engine config<br>2. Check if backend services are slow<br>3. Review resource limits<br>4. Check pod CPU/memory usage |
| **E005** | Medium | Rate Limit Exceeded | Too many requests in time window | 1. Implement request throttling<br>2. Increase rate limit in config<br>3. Batch requests<br>4. Check for infinite loops or retry storms |
| **E006** | Low | Not Found Error | Requested resource not found | 1. Verify resource exists in cluster<br>2. Check namespace and name<br>3. Verify RBAC permissions<br>4. Use `oc get <resource> -n <namespace>` |

### KServe Model Serving Errors (E101-E104)

| Code | Severity | Description | Causes | Solutions |
|------|----------|-------------|---------|-----------|
| **E101** | Critical | Model Loading Error | Model artifacts not found or corrupted | 1. Check ObjectBucketClaim: `oc get objectbucketclaim model-storage -n self-healing-platform`<br>2. Verify S3 bucket credentials: `oc get secret model-storage -n self-healing-platform -o yaml`<br>3. Check model artifact path in InferenceService<br>4. Re-run training pipeline: [Section 3 Step 17](../../CLAUDE.md#step-17-check-model-training-pipeline-status) |
| **E102** | Critical | Inference Error | Model inference request failed | 1. Check predictor pod logs: `oc logs -l serving.kserve.io/inferenceservice=anomaly-detector -c kserve-container`<br>2. Verify input data format matches model schema<br>3. Check model compatibility (sklearn/tensorflow version)<br>4. Test with sample data: [API docs](api-documentation.md#kserve-inferenceservice-api) |
| **E103** | High | Timeout Error | Inference request timeout | 1. Increase predictor timeout in InferenceService spec<br>2. Scale predictor replicas for load balancing<br>3. Check predictor resource limits<br>4. Optimize model (reduce size, quantization) |
| **E104** | Medium | Service Unavailable (503) | Predictor pods not ready | 1. Check predictor pod status: `oc get pods -l serving.kserve.io/inferenceservice=anomaly-detector`<br>2. Check InferenceService status: `oc describe inferenceservice anomaly-detector -n self-healing-platform`<br>3. Verify model loading didn't fail (check logs)<br>4. Check readiness probe configuration |

### Tekton Pipeline Errors (E201-E203)

| Code | Severity | Description | Causes | Solutions |
|------|----------|-------------|---------|-----------|
| **E201** | High | Pipeline Execution Error | Tekton pipeline failed | 1. View logs: `tkn pipelinerun logs <pipelinerun-name> -n self-healing-platform`<br>2. Check TaskRun status: `tkn taskrun list -n self-healing-platform`<br>3. Verify pipeline parameters<br>4. Check for missing secrets or ConfigMaps |
| **E202** | High | Task Execution Error | Specific task in pipeline failed | 1. View task logs: `tkn taskrun logs <taskrun-name> -n self-healing-platform`<br>2. Check task container logs<br>3. Verify task inputs/outputs<br>4. Check for syntax errors in task definition |
| **E203** | Medium | Resource Error | Pipeline resource not found | 1. Verify PipelineResource exists: `oc get pipelineresource -n self-healing-platform`<br>2. Check workspace PVC: `oc get pvc -n self-healing-platform`<br>3. Verify service account permissions<br>4. Check for typos in resource names |

### ArgoCD Errors (E301-E305)

| Code | Severity | Description | Causes | Solutions |
|------|----------|-------------|---------|-----------|
| **E301** | Critical | Sync Error | Application sync failed | 1. Check application status: `oc describe application self-healing-platform -n self-healing-platform-hub`<br>2. View sync errors in ArgoCD UI<br>3. Verify git repository is accessible<br>4. Check RBAC permissions: [Issue 4 in CLAUDE.md](../../CLAUDE.md#issue-4-argocd-application-not-syncing) |
| **E302** | Critical | Cluster-Level Resource Error | ArgoCD cannot manage cluster-level resources | 1. Grant cluster-admin to ArgoCD controller: `make operator-deploy-prereqs`<br>2. Verify ClusterRoleBinding exists: `oc get clusterrolebinding | grep hub-gitops`<br>3. Check ArgoCD controller logs<br>4. See [ADR-030](../adrs/030-hybrid-management-model-namespaced-argocd.md) |
| **E303** | High | Health Check Failed | Application health status degraded | 1. Check pod status in target namespace<br>2. Review resource events: `oc get events -n self-healing-platform --sort-by='.lastTimestamp'`<br>3. Verify resource quotas not exceeded<br>4. Check for missing dependencies |
| **E304** | Medium | OutOfSync | Application detected drift | 1. Review diff in ArgoCD UI<br>2. Manual sync: `oc annotate application self-healing-platform argocd.argoproj.io/refresh=hard -n self-healing-platform-hub`<br>3. If expected, configure ignoreDifferences<br>4. Check for manual edits to resources |
| **E305** | Low | Missing Application | ArgoCD Application CR not created | 1. Wait for operator to create application (up to 120s)<br>2. Check Pattern CR status: `oc get pattern self-healing-platform -n openshift-operators -o yaml`<br>3. Verify operator is running: `oc get pods -n openshift-operators | grep validated-patterns`<br>4. Check operator logs |

### Operator Errors (E401-E405)

| Code | Severity | Description | Causes | Solutions |
|------|----------|-------------|---------|-----------|
| **E401** | Critical | TooManyOperatorGroups | Multiple OperatorGroups in namespace | 1. Delete extra OperatorGroup: `oc delete operatorgroup jupyter-validator-operatorgroup -n openshift-operators`<br>2. Wait 30-60s for operators to reconcile<br>3. Verify CSVs succeed: `oc get csv -n openshift-operators`<br>4. See [Issue 3 in CLAUDE.md](../../CLAUDE.md#issue-3-operators-failing---toomanyoperatorgroups) |
| **E402** | Critical | CSV Failed | ClusterServiceVersion in failed state | 1. View CSV status: `oc describe csv <csv-name> -n openshift-operators`<br>2. Check InstallPlan: `oc get installplan -n openshift-operators`<br>3. Review operator pod logs<br>4. Verify subscription channel and version |
| **E403** | High | Subscription Failed | Operator subscription failing | 1. View subscription status: `oc describe subscription <subscription-name> -n openshift-operators`<br>2. Check CatalogSource: `oc get catalogsource -n openshift-marketplace`<br>3. Verify operator is in catalog: `oc get packagemanifest | grep <operator>`<br>4. Check for version conflicts |
| **E404** | Medium | InstallPlan Pending | InstallPlan not approved or failing | 1. List InstallPlans: `oc get installplan -n openshift-operators`<br>2. Approve if needed: `oc patch installplan <plan> -n openshift-operators --type merge -p '{"spec":{"approved":true}}'`<br>3. Check for missing prerequisites<br>4. Review InstallPlan status |
| **E405** | Low | CatalogSource Unhealthy | Operator catalog source not ready | 1. Check CatalogSource: `oc get catalogsource -n openshift-marketplace`<br>2. View CatalogSource pod logs<br>3. Restart catalog pod if needed<br>4. Verify image pull succeeds |

### Storage Errors (E501-E505)

| Code | Severity | Description | Causes | Solutions |
|------|----------|-------------|---------|-----------|
| **E501** | Critical | PVC Pending | PersistentVolumeClaim stuck in Pending | 1. Check PVC events: `oc describe pvc <pvc-name> -n self-healing-platform`<br>2. Verify storage class exists: `oc get storageclass`<br>3. Check for available PVs<br>4. Verify ODF is healthy: `oc get cephcluster -n openshift-storage` |
| **E502** | Critical | ODF Unhealthy | OpenShift Data Foundation cluster degraded | 1. Check Ceph status: `oc get cephcluster -n openshift-storage`<br>2. View ODF operator logs<br>3. Check OSD pods: `oc get pods -n openshift-storage | grep osd`<br>4. Re-run infrastructure setup: `make configure-cluster` |
| **E503** | High | Storage Class Not Found | Referenced storage class doesn't exist | 1. List available storage classes: `oc get storageclass`<br>2. Update values-hub.yaml with correct storage class<br>3. For SNO: use `gp3-csi` instead of `ocs-storagecluster-cephfs`<br>4. See [SNO Configuration](../../CLAUDE.md#sno-specific-configuration) |
| **E504** | Medium | NooBaa Unhealthy | NooBaa S3 service not ready | 1. Check NooBaa status: `oc get noobaa -n openshift-storage`<br>2. View NooBaa core pod logs: `oc logs -n openshift-storage -l app=noobaa-core`<br>3. Check ObjectBucketClaim: `oc get objectbucketclaim -n self-healing-platform`<br>4. Verify MCG pods running (SNO) |
| **E505** | Low | Insufficient Storage | Storage capacity exhausted | 1. Check PVC usage: `oc get pvc -n self-healing-platform`<br>2. Expand PVC if supported: `oc patch pvc <pvc> -n self-healing-platform -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'`<br>3. Clean up old data<br>4. Add more ODF storage nodes (HA) |

### GPU Errors (E601-E603)

| Code | Severity | Description | Causes | Solutions |
|------|----------|-------------|---------|-----------|
| **E601** | Critical | GPU Not Available | `nvidia-smi` not found or GPU not detected | 1. Verify GPU nodes: `oc get nodes -l nvidia.com/gpu.present=true`<br>2. Check GPU operator: `oc get csv -n openshift-operators | grep gpu-operator`<br>3. Verify GPU pods running: `oc get pods -n nvidia-gpu-operator`<br>4. Label GPU node: `oc label node <node-name> nvidia.com/gpu.present=true` |
| **E602** | High | GPU Driver Not Loaded | NVIDIA driver not loaded on node | 1. Check driver pod logs: `oc logs -n nvidia-gpu-operator -l app=nvidia-driver-daemonset`<br>2. Verify kernel compatibility<br>3. Check GPU operator version<br>4. Restart driver pods if needed |
| **E603** | Medium | GPU Allocation Failed | Notebook/Pod cannot allocate GPU | 1. Check GPU resource limits in notebook spec<br>2. Verify GPU available: `oc describe node <gpu-node> | grep nvidia.com/gpu`<br>3. Check for resource conflicts<br>4. Scale down other GPU workloads if needed |

### Notebook Errors (E701-E704)

| Code | Severity | Description | Causes | Solutions |
|------|----------|-------------|---------|-----------|
| **E701** | High | Notebook Execution Failed | Jupyter notebook failed during validation | 1. View job logs: `oc logs job/<notebook-job-name> -n self-healing-platform`<br>2. Check notebook syntax: `jupyter nbconvert --to notebook --execute <notebook.ipynb>`<br>3. Verify notebook dependencies installed<br>4. Check for cell errors in notebook output |
| **E702** | High | Notebook Image Pull Error | Cannot pull notebook container image | 1. Check ImageStream: `oc get imagestream -n redhat-ods-applications`<br>2. Verify BuildConfig: `oc get buildconfig notebook-validator -n self-healing-platform`<br>3. Check pull secret if using private registry<br>4. Use fallback image in values-hub.yaml |
| **E703** | Medium | Notebook Timeout | Notebook execution exceeded timeout | 1. Increase timeout in values-hub.yaml<br>2. Optimize notebook (reduce cells, faster algorithms)<br>3. Check for infinite loops<br>4. Increase resources (CPU/memory) |
| **E704** | Medium | Notebook Resource Exhausted | Notebook OOM or CPU throttled | 1. Increase resource limits for tier in values-hub.yaml<br>2. Optimize notebook memory usage<br>3. Use smaller datasets for testing<br>4. Enable GPU for ML workloads |

---

## Quick Symptom Lookup

Use this table for fast diagnosis based on what you observe.

| Symptom | Likely Cause | Error Code | Quick Check | Quick Fix |
|---------|--------------|------------|-------------|-----------|
| **Pods stuck in Pending** | Resource constraints or storage | E501, E505 | `oc describe pod <pod>` | Check PVC status, resource quotas, node capacity |
| **Pods in CrashLoopBackOff** | Application error, missing config | E001-E006 | `oc logs <pod>` | Check logs, verify ConfigMaps/Secrets exist |
| **ArgoCD app degraded** | Sync failed, missing permissions | E301-E305 | `oc describe application self-healing-platform -n self-healing-platform-hub` | Re-run `make operator-deploy-prereqs`, check git credentials |
| **Model inference 503** | Predictor pods not ready | E104 | `oc get pods -l serving.kserve.io/inferenceservice=<name>` | Check InferenceService status, verify model loaded |
| **Notebook execution failed** | Syntax error, missing dependency | E701, E704 | `oc logs job/<job-name>` | Check notebook syntax, increase resources |
| **GPU not available** | Driver not loaded, operator failed | E601, E602 | `oc get nodes -l nvidia.com/gpu.present=true` | Check GPU operator, verify driver pods |
| **Storage class not found** | Wrong storage class for topology | E503 | `oc get storageclass` | Update values-hub.yaml (SNO: use `gp3-csi`) |
| **Operators failing** | Multiple OperatorGroups | E401 | `oc get operatorgroups -n openshift-operators` | Delete extra OperatorGroup |
| **ODF unhealthy** | Ceph daemons not ready | E502, E504 | `oc get cephcluster -n openshift-storage` | Re-run `make configure-cluster` |
| **ArgoCD cluster-level error** | Missing cluster-admin | E302 | `oc get clusterrolebinding | grep hub-gitops` | Run `make operator-deploy-prereqs` |
| **Pipeline failed** | Task error, missing resource | E201-E203 | `tkn pipelinerun logs <run>` | Check task logs, verify pipeline parameters |
| **NooBaa not ready** | MCG pods failing | E504 | `oc get noobaa -n openshift-storage` | Check NooBaa core pod logs |
| **Values files not found** | Didn't create values files | N/A | `ls values-global.yaml values-hub.yaml` | Run: `cp values-global.yaml.example values-global.yaml` |
| **Coordination engine timeout** | Slow backend services | E004 | `oc logs deployment/coordination-engine` | Increase timeout, check resource limits |

---

## Diagnostic Commands

### Cluster Health

```bash
# Overall cluster status
make show-cluster-info

# Cluster operators
oc get clusteroperators

# Node status
oc get nodes

# Resource utilization
oc adm top nodes
oc adm top pods -n self-healing-platform
```

### Platform Components

```bash
# All pods in platform namespace
oc get pods -n self-healing-platform

# ArgoCD application status
oc get applications -n self-healing-platform-hub
make argo-healthcheck

# Pattern CR status
oc get pattern self-healing-platform -n openshift-operators -o yaml

# Validated Patterns operator
oc get pods -n openshift-operators | grep validated-patterns
oc logs -n openshift-operators deployment/validated-patterns-operator
```

### Storage

```bash
# PVCs
oc get pvc -n self-healing-platform

# Storage classes
oc get storageclass

# ODF status
oc get cephcluster -n openshift-storage
oc get storagecluster -n openshift-storage
oc get noobaa -n openshift-storage

# ODF pods
oc get pods -n openshift-storage | grep -E "osd|mon|mgr|noobaa"

# ObjectBucketClaim
oc get objectbucketclaim -n self-healing-platform
oc describe objectbucketclaim model-storage -n self-healing-platform
```

### Model Serving

```bash
# InferenceServices
oc get inferenceservices -n self-healing-platform

# Predictor pods
oc get pods -n self-healing-platform -l serving.kserve.io/inferenceservice=anomaly-detector

# InferenceService details
oc describe inferenceservice anomaly-detector -n self-healing-platform

# Test inference
INGRESS=$(oc get route anomaly-detector -n self-healing-platform -o jsonpath='{.spec.host}')
curl -X POST https://${INGRESS}/v1/models/anomaly-detector:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[1.0, 2.0, 3.0]]}'
```

### Pipelines

```bash
# Tekton pipelines
tkn pipeline list -n self-healing-platform

# Pipeline runs
tkn pipelinerun list -n self-healing-platform

# Pipeline run logs
tkn pipelinerun logs <pipelinerun-name> -n self-healing-platform -f

# Task runs
tkn taskrun list -n self-healing-platform
```

### Operators

```bash
# Subscriptions
oc get subscriptions -n openshift-operators

# ClusterServiceVersions (CSVs)
oc get csv -n openshift-operators

# OperatorGroups
oc get operatorgroups -n openshift-operators

# InstallPlans
oc get installplans -n openshift-operators

# CatalogSources
oc get catalogsource -n openshift-marketplace
```

### GPU

```bash
# GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# GPU operator
oc get csv -n openshift-operators | grep gpu-operator

# GPU operator pods
oc get pods -n nvidia-gpu-operator

# Node GPU capacity
oc describe node <gpu-node> | grep -A 10 "Capacity"
```

### Logs

```bash
# Coordination engine logs
oc logs -n self-healing-platform deployment/coordination-engine --tail=100 -f

# Workbench logs
oc logs -n self-healing-platform self-healing-workbench-0 --tail=100 -f

# KServe predictor logs
oc logs -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=anomaly-detector \
  -c kserve-container --tail=100 -f

# ArgoCD controller logs
oc logs -n self-healing-platform-hub \
  deployment/hub-gitops-application-controller --tail=100 -f

# Notebook validation job logs
oc logs -n self-healing-platform job/<notebook-job-name> --tail=100
```

### Events

```bash
# Recent events in platform namespace
oc get events -n self-healing-platform --sort-by='.lastTimestamp' | tail -20

# Recent events cluster-wide
oc get events --all-namespaces --sort-by='.lastTimestamp' | tail -30

# Watch events
oc get events -n self-healing-platform --watch
```

---

## Common Issue Resolution Workflows

### Workflow 1: "Nothing is deploying"

1. **Check if values files exist**:
   ```bash
   ls -l values-global.yaml values-hub.yaml
   ```
   If missing: `cp values-global.yaml.example values-global.yaml` and `cp values-hub.yaml.example values-hub.yaml`

2. **Verify repoURL is YOUR fork**:
   ```bash
   grep repoURL values-global.yaml values-hub.yaml
   ```
   Should show: `https://github.com/YOUR-USERNAME/openshift-aiops-platform.git`

3. **Check Pattern CR status**:
   ```bash
   oc get pattern self-healing-platform -n openshift-operators -o yaml | grep -A 20 "status:"
   ```

4. **Verify ArgoCD application exists**:
   ```bash
   oc get application self-healing-platform -n self-healing-platform-hub
   ```
   If missing: Wait up to 120s or check operator logs

5. **Check ArgoCD permissions**:
   ```bash
   oc get clusterrolebinding | grep hub-gitops-argocd-application-controller-cluster-admin
   ```
   If missing: Run `make operator-deploy-prereqs`

### Workflow 2: "Model inference not working"

1. **Check InferenceService status**:
   ```bash
   oc get inferenceservice anomaly-detector -n self-healing-platform
   ```
   Should show: `READY: True`

2. **Check predictor pods**:
   ```bash
   oc get pods -n self-healing-platform -l serving.kserve.io/inferenceservice=anomaly-detector
   ```
   Should show: Running pods

3. **Check model artifacts in S3**:
   ```bash
   oc describe objectbucketclaim model-storage -n self-healing-platform
   ```
   Verify bucket exists and credentials are valid

4. **Check predictor logs for model loading errors**:
   ```bash
   oc logs -n self-healing-platform \
     -l serving.kserve.io/inferenceservice=anomaly-detector \
     -c kserve-container --tail=50
   ```

5. **If model not found, re-run training pipeline**:
   ```bash
   tkn pipeline start model-training-pipeline \
     -p model-name=anomaly-detector \
     -p notebook-path=notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb \
     -n self-healing-platform --showlog
   ```

### Workflow 3: "Operators are all failing"

1. **Check for multiple OperatorGroups**:
   ```bash
   oc get operatorgroups -n openshift-operators
   ```
   Expected: Only `global-operators` should exist

2. **Delete extra OperatorGroup**:
   ```bash
   oc delete operatorgroup jupyter-validator-operatorgroup -n openshift-operators
   ```

3. **Wait for operators to reconcile** (30-60 seconds):
   ```bash
   oc get csv -n openshift-operators --watch
   ```

4. **Verify all CSVs are Succeeded**:
   ```bash
   oc get csv -n openshift-operators
   ```

### Workflow 4: "ODF/Storage not working"

1. **Check cluster topology**:
   ```bash
   make show-cluster-info
   ```
   If SNO: Update values-hub.yaml storage classes to `gp3-csi`

2. **Check ODF operator**:
   ```bash
   oc get csv -n openshift-storage | grep odf-operator
   ```

3. **Check Ceph cluster status** (HA only):
   ```bash
   oc get cephcluster -n openshift-storage
   ```
   Should show: `HEALTH: HEALTH_OK`

4. **Check NooBaa status** (all topologies):
   ```bash
   oc get noobaa -n openshift-storage
   ```
   Should show: `PHASE: Ready`

5. **If ODF not healthy, re-run infrastructure setup**:
   ```bash
   make configure-cluster
   ```

### Workflow 5: "GPU not available in notebook"

1. **Check GPU nodes exist**:
   ```bash
   oc get nodes -l nvidia.com/gpu.present=true
   ```

2. **Check GPU operator**:
   ```bash
   oc get csv -n openshift-operators | grep gpu-operator
   ```

3. **Check GPU driver pods**:
   ```bash
   oc get pods -n nvidia-gpu-operator | grep nvidia-driver
   ```
   Should show: Running pods on GPU nodes

4. **Verify notebook requests GPU**:
   ```bash
   oc describe notebook self-healing-workbench -n self-healing-platform | grep -A 5 "nvidia.com/gpu"
   ```
   Should show: `nvidia.com/gpu: 1`

5. **If GPU not requested, update values-hub.yaml**:
   ```yaml
   workbench:
     gpu:
       enabled: true
   ```
   Then sync ArgoCD

---

## Emergency Procedures

### Procedure 1: Complete Platform Reset

**⚠️ WARNING**: This deletes all platform resources and data. Only use for troubleshooting.

```bash
# 1. Delete ArgoCD application
oc delete application self-healing-platform -n self-healing-platform-hub --ignore-not-found=true

# 2. Delete Pattern CR
oc delete pattern self-healing-platform -n openshift-operators --ignore-not-found=true

# 3. Delete platform namespace
oc delete namespace self-healing-platform --ignore-not-found=true

# 4. Delete GitOps namespace
oc delete namespace self-healing-platform-hub --ignore-not-found=true

# 5. Clean up ClusterRoleBindings
oc delete clusterrolebinding hub-gitops-argocd-application-controller-cluster-admin --ignore-not-found=true

# 6. Wait 60 seconds for cleanup
sleep 60

# 7. Re-deploy
make operator-deploy
```

### Procedure 2: Force ArgoCD Sync

**Use when application is stuck OutOfSync**:

```bash
# Hard refresh ArgoCD application
oc annotate application self-healing-platform \
  -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite

# Wait 30 seconds
sleep 30

# Check sync status
oc get application self-healing-platform -n self-healing-platform-hub \
  -o jsonpath='{.status.sync.status}'
```

### Procedure 3: Restart ODF (Emergency)

**⚠️ WARNING**: This restarts ODF daemons. May cause temporary storage unavailability.

```bash
# Restart ODF operator
oc rollout restart deployment/odf-operator-controller-manager -n openshift-storage

# Restart Rook-Ceph operator
oc rollout restart deployment/rook-ceph-operator -n openshift-storage

# Wait for ODF to stabilize (5-10 minutes)
oc get cephcluster -n openshift-storage --watch

# Verify health
oc get cephcluster -n openshift-storage -o jsonpath='{.items[0].status.ceph.health}'
```

---

## Related Documentation

- [CLAUDE.md Section 5: Common Troubleshooting](../../CLAUDE.md#section-5-common-troubleshooting) - Detailed troubleshooting guide for AI agents
- [docs/guides/TROUBLESHOOTING-GUIDE.md](../guides/TROUBLESHOOTING-GUIDE.md) - Complete troubleshooting guide
- [docs/reference/api-documentation.md](api-documentation.md) - API error response schemas
- [ADR-043: Deployment Stability and Health Checks](../adrs/043-deployment-stability-health-checks.md) - Health check best practices
- [ADR-042: ArgoCD Deployment Lessons Learned](../adrs/042-argocd-deployment-lessons-learned.md) - ArgoCD troubleshooting

---

**Last Updated**: 2026-05-19  
**Next Review**: 2026-06-19  
**Maintained By**: Platform Engineering Team
