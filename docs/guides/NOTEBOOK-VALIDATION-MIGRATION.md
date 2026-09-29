# Notebook Validation Migration Guide

**From:** Tekton Pipeline-based Notebook Execution
**To:** Jupyter Notebook Validator Operator (CRD-based)
**Status:** Migration in Progress
**Date:** 2025-11-18

## Executive Summary

This guide provides step-by-step instructions for migrating from **Tekton-based notebook validation** (ADR-021) to **Jupyter Notebook Validator Operator** (ADR-029). The migration improves:

- **Declarative Management**: NotebookValidationJob CRDs vs imperative scripts
- **Resource Isolation**: Per-notebook resource requests and limits
- **Git Integration**: Native support for public and private repositories
- **Execution Tracking**: Better visibility into notebook validation status
- **Scalability**: Independent validation pods scale horizontally

## Migration Overview

### What's Changing

| Aspect | Current (Tekton) | New (Operator) |
|--------|------------------|----------------|
| **Execution Model** | Tekton tasks execute notebooks | Operator creates validation pods |
| **Configuration** | Tekton pipeline YAML | NotebookValidationJob CRD |
| **Git Access** | Manual git clone in tasks | Native git integration with credentials |
| **Resource Management** | Shared pipeline resources | Per-notebook resource isolation |
| **Status Tracking** | Pipeline run logs | CRD status conditions |
| **Artifacts** | Pipeline workspace | Validation pod logs |

### What's Staying the Same

- ✅ **Infrastructure Validation**: Tekton pipelines for prerequisites, operators, storage, monitoring
- ✅ **Model Serving Validation**: KServe InferenceService health checks
- ✅ **Coordination Engine Validation**: Deployment and API health checks
- ✅ **Tekton Triggers**: Webhook integration for automated validation

## Prerequisites

Before starting the migration, ensure:

- [ ] **cert-manager v1.13+** installed (required for operator webhooks)
  ```bash
  oc get pods -n cert-manager
  ```

- [ ] **OpenShift 4.19+** (4.21 recommended; 4.18 maintenance-only) or Kubernetes 1.31+ cluster
  ```bash
  oc version
  ```

- [ ] **Helm 3.8+** for operator installation
  ```bash
  helm version
  ```

- [ ] **Git credentials** configured for private repositories (if needed)
  ```bash
  oc get secret github-credentials -n self-healing-platform
  ```

## Migration Phases

### Phase 1: Operator Deployment (Week 1)

#### Step 1.1: Install cert-manager (if not present)

```bash
# Check if cert-manager is installed
oc get pods -n cert-manager

# If not installed, deploy cert-manager
oc apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
oc wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
oc wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
oc wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
```

#### Step 1.2: Deploy Jupyter Notebook Validator Operator

```bash
# Add Helm repository (when published)
helm repo add jupyter-validator https://tosin2013.github.io/jupyter-notebook-validator-operator
helm repo update

# OR: Install from GitHub release
helm install jupyter-validator \
  https://github.com/tosin2013/jupyter-notebook-validator-operator/releases/download/release-4.18/jupyter-notebook-validator-operator-0.1.0.tgz \
  --namespace jupyter-validator-system \
  --create-namespace \
  --set openshift.enabled=true \
  --set prometheus.enabled=true \
  --set image.repository=quay.io/takinosh/jupyter-notebook-validator-operator \
  --set image.tag=latest \
  --wait \
  --timeout 5m
```

#### Step 1.3: Verify Operator Installation

```bash
# Check operator pod
oc get pods -n jupyter-validator-system

# Expected output:
# NAME                                                          READY   STATUS    RESTARTS   AGE
# jupyter-validator-controller-manager-xxxxx                     2/2     Running   0          2m

# Check CRDs
oc get crd notebookvalidationjobs.mlops.mlops.dev

# Check webhooks
oc get mutatingwebhookconfiguration,validatingwebhookconfiguration | grep jupyter

# Check cert-manager certificate
oc get certificate,issuer -n jupyter-validator-system
```

#### Step 1.4: Configure Git Credentials for Private Repositories

```bash
# Create git credentials secret (if using private repos)
oc create secret generic github-credentials \
  --from-literal=username=your-github-username \
  --from-literal=password=ghp_your_personal_access_token \
  -n self-healing-platform

# Verify secret
oc get secret github-credentials -n self-healing-platform
```

### Phase 2: Tier Migration (Week 2-3)

#### Step 2.1: Migrate Tier1-Simple Notebooks (5 notebooks)

Create NotebookValidationJob CRDs for each tier1-simple notebook:

**Example: Hello World Notebook**

```yaml
# k8s/notebooks/tier1-hello-world-validation.yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: hello-world-validation
  namespace: self-healing-platform
spec:
  notebook:
    git:
      url: "https://github.com/openshift-aiops/openshift-aiops-platform.git"
      ref: "main"
      # credentialsSecret: "github-credentials"  # Uncomment for private repos
    path: "notebooks/tier1-simple/01-hello-world.ipynb"

  podConfig:
    containerImage: "quay.io/jupyter/minimal-notebook:latest"
    resources:
      requests:
        memory: "512Mi"
        cpu: "500m"
      limits:
        memory: "1Gi"
        cpu: "1000m"

  timeout: "10m"
```

**Deploy and Test**:

```bash
# Apply NotebookValidationJob
oc apply -f k8s/notebooks/tier1-hello-world-validation.yaml

# Check validation job status
oc get notebookvalidationjob hello-world-validation -n self-healing-platform

# Expected output:
# NAME                       STATUS      COMPLETION   AGE
# hello-world-validation     Succeeded   100%         2m

# Check validation pod logs
POD=$(oc get pods -n self-healing-platform -l job-name=hello-world-validation --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
oc logs $POD -n self-healing-platform
```

**Tier1-Simple Notebook List** (5 notebooks):
1. `01-hello-world.ipynb` - Basic Python execution
2. `02-environment-check.ipynb` - Platform readiness validation
3. `03-data-loading.ipynb` - Load sample datasets
4. `04-basic-ml.ipynb` - Simple ML model training
5. `05-api-interaction.ipynb` - Test coordination engine API

#### Step 2.2: Migrate Tier2-Intermediate Notebooks (10 notebooks)

**Example: Data Collection Notebook**

```yaml
# k8s/notebooks/tier2-data-collection-validation.yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: data-collection-prometheus
  namespace: self-healing-platform
spec:
  notebook:
    git:
      url: "https://github.com/openshift-aiops/openshift-aiops-platform.git"
      ref: "main"
    path: "notebooks/tier2-intermediate/01-data-collection/prometheus-metrics-collection.ipynb"

  podConfig:
    containerImage: "quay.io/jupyter/datascience-notebook:latest"
    resources:
      requests:
        memory: "2Gi"
        cpu: "1000m"
      limits:
        memory: "4Gi"
        cpu: "2000m"

  timeout: "30m"
```

**Tier2-Intermediate Notebook Categories** (10 notebooks):
- Data Collection (3 notebooks): Prometheus, logs, events
- Preprocessing (3 notebooks): Feature engineering, scaling, encoding
- EDA (4 notebooks): Exploratory data analysis, visualization

#### Step 2.3: Migrate Tier3-Advanced Notebooks (15 notebooks)

**Example: Anomaly Detection Notebook**

```yaml
# k8s/notebooks/tier3-anomaly-detection-validation.yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: anomaly-detection-isolation-forest
  namespace: self-healing-platform
spec:
  notebook:
    git:
      url: "https://github.com/openshift-aiops/openshift-aiops-platform.git"
      ref: "main"
    path: "notebooks/tier3-advanced/02-anomaly-detection/01-isolation-forest-implementation.ipynb"

  podConfig:
    containerImage: "quay.io/jupyter/tensorflow-notebook:latest"
    resources:
      requests:
        memory: "4Gi"
        cpu: "2000m"
        nvidia.com/gpu: "1"  # GPU support
      limits:
        memory: "8Gi"
        cpu: "4000m"
        nvidia.com/gpu: "1"

  timeout: "60m"
```

**Tier3-Advanced Notebook Categories** (15 notebooks):
- Anomaly Detection (5 notebooks): Isolation Forest, LSTM, ARIMA, Ensemble
- Self-Healing Logic (3 notebooks): Rule-based, AI-driven, hybrid approaches
- Model Serving (4 notebooks): KServe deployment, inference testing
- End-to-End Scenarios (3 notebooks): Complete workflows

### Phase 3: Full Integration (Week 4)

#### Step 3.1: Create Ansible Role for Operator Deployment

Create `ansible/roles/validated_patterns_notebooks/`:

```yaml
# ansible/roles/validated_patterns_notebooks/tasks/main.yml
---
- name: Check if cert-manager is installed
  kubernetes.core.k8s_info:
    api_version: v1
    kind: Pod
    namespace: cert-manager
  register: certmanager_pods

- name: Fail if cert-manager not installed
  fail:
    msg: "cert-manager is required but not installed"
  when: certmanager_pods.resources | length == 0

- name: Deploy Jupyter Notebook Validator Operator via Helm
  kubernetes.core.helm:
    name: jupyter-validator
    chart_ref: https://github.com/tosin2013/jupyter-notebook-validator-operator/releases/download/release-4.18/jupyter-notebook-validator-operator-0.1.0.tgz
    release_namespace: jupyter-validator-system
    create_namespace: true
    values:
      openshift:
        enabled: true
      prometheus:
        enabled: true
      image:
        repository: quay.io/takinosh/jupyter-notebook-validator-operator
        tag: latest
    wait: true
    wait_timeout: 5m

- name: Verify operator deployment
  kubernetes.core.k8s_info:
    api_version: apps/v1
    kind: Deployment
    name: jupyter-validator-controller-manager
    namespace: jupyter-validator-system
  register: operator_deployment
  until: operator_deployment.resources[0].status.readyReplicas == 2
  retries: 30
  delay: 10

- name: Create NotebookValidationJob CRDs for all tiers
  kubernetes.core.k8s:
    state: present
    definition: "{{ lookup('file', item) }}"
  loop:
    - "{{ role_path }}/files/tier1-validations.yaml"
    - "{{ role_path }}/files/tier2-validations.yaml"
    - "{{ role_path }}/files/tier3-validations.yaml"
```

#### Step 3.2: Update Validation Role for CRD Status Checks

Update `ansible/roles/validated_patterns_validate/tasks/validate_notebooks.yml`:

```yaml
---
- name: Get NotebookValidationJob status
  kubernetes.core.k8s_info:
    api_version: mlops.mlops.dev/v1alpha1
    kind: NotebookValidationJob
    namespace: "{{ namespace }}"
  register: notebook_jobs

- name: Check notebook validation success
  assert:
    that:
      - item.status.phase == "Succeeded"
    fail_msg: "NotebookValidationJob {{ item.metadata.name }} failed"
  loop: "{{ notebook_jobs.resources }}"
  loop_control:
    label: "{{ item.metadata.name }}"

- name: Display notebook validation summary
  debug:
    msg: "{{ notebook_jobs.resources | length }} notebooks validated successfully"
```

#### Step 3.3: Remove Tekton Notebook Execution Tasks

Remove or comment out Tekton notebook execution tasks from `tekton/tasks/`:

**Before** (old Tekton task):
```yaml
# tekton/tasks/validate-notebooks.yaml (TO BE REMOVED)
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: execute-notebooks
spec:
  steps:
    - name: clone-repo
      image: alpine/git
      script: |
        git clone https://github.com/openshift-aiops/openshift-aiops-platform.git /workspace/source

    - name: execute-notebook
      image: quay.io/jupyter/minimal-notebook:latest
      script: |
        jupyter nbconvert --to notebook --execute /workspace/source/notebooks/01-hello-world.ipynb
```

**After** (reference to operator):
```yaml
# tekton/tasks/validate-notebooks.yaml (NEW APPROACH)
# NOTE: Notebook validation now handled by Jupyter Notebook Validator Operator
# See NotebookValidationJob CRDs in k8s/notebooks/
# This task only validates CRD status
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: validate-notebook-jobs
spec:
  steps:
    - name: check-notebook-status
      image: quay.io/openshift/origin-cli:latest
      script: |
        #!/bin/bash
        set -e

        echo "Checking NotebookValidationJob status..."
        oc get notebookvalidationjob -n self-healing-platform

        # Check all notebook jobs succeeded
        FAILED_JOBS=$(oc get notebookvalidationjob -n self-healing-platform -o jsonpath='{.items[?(@.status.phase!="Succeeded")].metadata.name}')

        if [ -n "$FAILED_JOBS" ]; then
          echo "Failed notebook validation jobs: $FAILED_JOBS"
          exit 1
        fi

        echo "All notebook validation jobs succeeded"
```

## Rollback Procedures

If issues arise during migration, you can roll back:

### Rollback Step 1: Disable Operator Validation

```bash
# Delete all NotebookValidationJob CRDs
oc delete notebookvalidationjob --all -n self-healing-platform

# Keep operator installed but not used
```

### Rollback Step 2: Re-enable Tekton Notebook Execution

```bash
# Re-apply old Tekton tasks
oc apply -f tekton/tasks/validate-notebooks-old.yaml

# Run Tekton pipeline
tkn pipeline start deployment-validation-pipeline --showlog
```

### Rollback Step 3: Uninstall Operator (if needed)

```bash
# Uninstall operator
helm uninstall jupyter-validator -n jupyter-validator-system

# Delete CRDs (this will delete all NotebookValidationJob resources!)
oc delete crd notebookvalidationjobs.mlops.mlops.dev

# Delete namespace
oc delete namespace jupyter-validator-system
```

## Comparison: Tekton vs Operator

### Tekton-based Approach

**Pros**:
- ✅ Already implemented and tested
- ✅ Integrated with existing Tekton pipelines
- ✅ Familiar to team (Tekton knowledge)

**Cons**:
- ❌ Notebook execution tightly coupled to Tekton infrastructure
- ❌ No per-notebook resource isolation
- ❌ Manual git clone in each task
- ❌ Difficult to track individual notebook execution history
- ❌ Shared pipeline execution context for all notebooks

### Operator-based Approach

**Pros**:
- ✅ Declarative management via NotebookValidationJob CRDs
- ✅ Per-notebook resource requests and limits
- ✅ Native Git integration with credential management
- ✅ Independent validation pods scale horizontally
- ✅ Clear CRD status for execution tracking
- ✅ Kubernetes-native architecture

**Cons**:
- ❌ New operator dependency to maintain
- ❌ Requires cert-manager installation
- ❌ Team learning curve for NotebookValidationJob CRDs
- ❌ Migration effort for 30+ notebooks

## Success Criteria

Migration is complete when:

- [ ] Jupyter Notebook Validator Operator deployed and operational
- [ ] All 30 notebooks migrated to NotebookValidationJob CRDs
- [ ] CRD-based validation passes for all tiers (tier1, tier2, tier3)
- [ ] Tekton infrastructure validation tasks retained and operational
- [ ] Documentation updated (notebooks/README.md, tekton/README.md)
- [ ] Ansible roles created (`validated_patterns_notebooks`)
- [ ] Rollback procedures tested and documented

## Timeline

- **Week 1**: Operator deployment and tier1-simple migration (5 notebooks)
- **Week 2**: Tier2-intermediate migration (10 notebooks)
- **Week 3**: Tier3-advanced migration (15 notebooks) + documentation updates
- **Week 4**: Full integration testing and validation

**Total Duration**: 4 weeks
**Expected Completion**: 2025-12-15

## References

- [ADR-029: Jupyter Notebook Validator Operator](adrs/029-jupyter-notebook-validator-operator.md)
- [ADR-021: Tekton Pipeline Validation](adrs/021-tekton-pipeline-deployment-validation.md) (Infrastructure validation retained)
- [Jupyter Notebook Validator Operator - Installation Guide](https://raw.githubusercontent.com/tosin2013/jupyter-notebook-validator-operator/refs/heads/release-4.18/helm/jupyter-notebook-validator-operator/INSTALLATION.md)
- [Jupyter Notebook Validator Operator - GitHub Repository](https://github.com/tosin2013/jupyter-notebook-validator-operator)
- [OpenShift cert-manager Documentation](https://docs.openshift.com/container-platform/latest/security/cert_manager_operator/index.html)

## Support

For issues or questions during migration:
1. Check operator logs: `oc logs -n jupyter-validator-system -l control-plane=controller-manager`
2. Check validation pod logs: `oc logs <validation-pod-name> -n self-healing-platform`
3. Review CRD status: `oc describe notebookvalidationjob <job-name> -n self-healing-platform`
4. Consult [ADR-029](adrs/029-jupyter-notebook-validator-operator.md) for architectural context

---

**Last Updated**: 2025-11-18
**Status**: Migration in Progress
**Confidence**: 90%
