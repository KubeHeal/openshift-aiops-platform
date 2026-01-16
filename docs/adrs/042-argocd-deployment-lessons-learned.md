# ADR-042: ArgoCD Deployment Lessons Learned

## Status
**ACCEPTED** - 2025-11-28

## Context

During the end-to-end deployment of the self-healing platform, several issues were encountered that required fixes. This ADR documents the lessons learned and recommended patterns for future deployments.

## Issues Encountered and Fixes Applied

### 1. PVC with WaitForFirstConsumer Blocking Sync

**Problem**: PVCs using `WaitForFirstConsumer` storage class remain in `Pending` state until a pod uses them. ArgoCD's default health check marks these as unhealthy, blocking sync.

**Fix Applied**: Added custom `resourceHealthChecks` to ArgoCD CR:
```yaml
spec:
  resourceHealthChecks:
    - group: ""
      kind: PersistentVolumeClaim
      check: |
        hs = {}
        if obj.status.phase == "Pending" then
          hs.status = "Healthy"
          hs.message = "PVC is pending (likely WaitForFirstConsumer)"
        elseif obj.status.phase == "Bound" then
          hs.status = "Healthy"
          hs.message = "PVC is bound"
        else
          hs.status = "Progressing"
          hs.message = "PVC status: " .. obj.status.phase
        end
        return hs
```

**Recommendation**: Add this to `validated_patterns_deploy` Ansible role or ArgoCD Helm chart.

### 2. BuildConfig Git URI Not Resolved

**Problem**: BuildConfigs failed with `spec.source.git.uri: Required value` because the git URL wasn't being resolved from values.

**Fix Applied**: Added fallback chain in Helm templates:
```yaml
{{- $gitUrl := .Values.imageBuilds.gitRepository | default .Values.git.repoURL | default .Values.global.git.repoURL | default "" }}
{{- if $gitUrl }}
spec:
  source:
    git:
      uri: {{ $gitUrl }}
{{- end }}
```

**Recommendation**: Always use fallback chains for critical values. Document required values in `values.yaml`.

### 3. ArgoCD Excludes PipelineRun Resources

**Problem**: ArgoCD excludes `tekton.dev/PipelineRun` by default. Attempts to use Jobs to trigger pipelines had race conditions with sync waves.

**Fix Applied**: Converted to BuildConfig instead of Tekton Pipeline:
- BuildConfigs are native OpenShift resources that ArgoCD handles well
- Simpler configuration, no need for workarounds

**Recommendation**: Prefer BuildConfigs over Tekton Pipelines for image builds in ArgoCD-managed environments. If Tekton is required, use webhooks/EventListeners instead of declarative PipelineRuns.

### 4. Dependent Resources Need to Wait for Image Builds

**Problem**: NotebookValidationJobs and Workbench pods tried to pull images before BuildConfig completed, causing `ErrImagePull`.

**Fix Applied**: Added a Sync hook Job that waits for the image:
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: wait-for-notebook-validator-image
  annotations:
    argocd.argoproj.io/sync-wave: "-3"  # After BuildConfig at -4
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      containers:
      - name: wait-for-image
        command: ["/bin/bash", "-c"]
        args:
        - |
          # Wait for imagestreamtag to exist
          while ! oc get imagestreamtag notebook-validator:latest; do
            sleep 30
          done
```

**Recommendation**: Add wait-for-image pattern to Helm charts for any resources that depend on built images.

### 5. ServiceAccount Permissions for Wait Jobs

**Problem**: Wait-for-image Job couldn't check ImageStreamTags because ServiceAccount lacked permissions.

**Fix Applied**: Added to Role:
```yaml
- apiGroups: ["image.openshift.io"]
  resources: ["imagestreams", "imagestreamtags"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["build.openshift.io"]
  resources: ["builds"]
  verbs: ["get", "list", "watch"]
```

**Recommendation**: Ensure ServiceAccounts used by Jobs have all required permissions.

### 6. ExternalSecret Source Secrets Need Correct Credentials

**Problem**: `gitea-credentials-source` had wrong password, causing git clone failures in BuildConfigs.

**Fix Applied**: Updated Makefile `load-env-secrets` to read password from Gitea CR:
```makefile
GITEA_PASSWORD=$(oc get gitea gitea-with-admin -n gitea -o jsonpath='{.status.adminPassword}')
```

**Recommendation**: Document how to obtain correct credentials. Consider reading from Gitea CR automatically.

### 7. NotebookValidationJob Image Configuration

**Problem**: Different tiers used different images, but all notebooks needed ML packages only available in the custom image.

**Fix Applied**: Updated `values-notebooks-validation.yaml` to use `notebook-validator:latest` for all tiers:
```yaml
images:
  tier1: "image-registry.openshift-image-registry.svc:5000/self-healing-platform/notebook-validator:latest"
  tier2: "image-registry.openshift-image-registry.svc:5000/self-healing-platform/notebook-validator:latest"
  tier3: "image-registry.openshift-image-registry.svc:5000/self-healing-platform/notebook-validator:latest"
```

**Recommendation**: Use a single well-tested image for all validation jobs rather than tiered images.

### 8. InferenceService Health Check Blocking Sync

**Problem**: InferenceServices show as unhealthy when models don't exist, blocking ArgoCD sync.

**Fix Applied**: Added custom health check and ignoreDifferences:
```yaml
spec:
  resourceHealthChecks:
    - group: "serving.kserve.io"
      kind: "InferenceService"
      check: |
        hs = {}
        hs.status = "Healthy"
        hs.message = "InferenceService status ignored for sync"
        return hs
  ignoreDifferences:
    - group: serving.kserve.io
      kind: InferenceService
      jqPathExpressions:
        - .status
```

**Recommendation**: InferenceServices should not block initial deployment since models are trained later.

## Recommended Changes to Ansible Roles

### 1. `validated_patterns_deploy` Role

Add ArgoCD resource health checks:
```yaml
# In tasks/configure_argocd.yml
- name: Configure ArgoCD resource health checks
  kubernetes.core.k8s:
    state: patched
    definition:
      apiVersion: argoproj.io/v1beta1
      kind: ArgoCD
      metadata:
        name: openshift-gitops
        namespace: openshift-gitops
      spec:
        resourceHealthChecks:
          - group: ""
            kind: PersistentVolumeClaim
            check: "{{ lookup('file', 'files/pvc-health-check.lua') }}"
          - group: "serving.kserve.io"
            kind: "InferenceService"
            check: "{{ lookup('file', 'files/inferenceservice-health-check.lua') }}"
```

### 2. `validated_patterns_secrets` Role

Add automatic Gitea credential discovery:
```yaml
- name: Get Gitea admin password
  kubernetes.core.k8s_info:
    kind: Gitea
    name: gitea-with-admin
    namespace: gitea
  register: gitea_info

- name: Create gitea-credentials-source secret
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: v1
      kind: Secret
      metadata:
        name: gitea-credentials-source
        namespace: "{{ namespace }}"
      stringData:
        username: "{{ gitea_info.resources[0].spec.giteaAdminUser }}"
        password: "{{ gitea_info.resources[0].status.adminPassword }}"
```

## Recommended Changes to Helm Charts

### 1. Add Wait-for-Image Pattern

Create a helper template in `_helpers.tpl`:
```yaml
{{- define "wait-for-image" -}}
apiVersion: batch/v1
kind: Job
metadata:
  name: wait-for-{{ .name }}-image
  annotations:
    argocd.argoproj.io/sync-wave: "{{ .syncWave }}"
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    spec:
      serviceAccountName: {{ .serviceAccount }}
      restartPolicy: Never
      containers:
      - name: wait
        image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
        command: ["/bin/bash", "-c"]
        args:
        - |
          TIMEOUT={{ .timeout | default 3600 }}
          while [ $ELAPSED -lt $TIMEOUT ]; do
            if oc get imagestreamtag {{ .imageTag }} -n {{ .namespace }}; then
              exit 0
            fi
            sleep 30
            ELAPSED=$((ELAPSED + 30))
          done
          exit 1
{{- end }}
```

### 2. Use Fallback Chains for Required Values

Document and implement fallback chains:
```yaml
# In values.yaml, document:
# git:
#   repoURL: ""  # REQUIRED: Set in values-global.yaml or override
#   revision: "main"

# In templates, use:
{{- $gitUrl := .Values.git.repoURL | default .Values.global.git.repoURL | required "git.repoURL is required" }}
```

## Decision

1. Implement ArgoCD health check customizations in `validated_patterns_deploy` role
2. Add automatic Gitea credential discovery to `validated_patterns_secrets` role
3. Add wait-for-image pattern to Helm charts that depend on built images
4. Use single validated image for all NotebookValidationJobs
5. Document sync wave ordering requirements in ADRs

## Consequences

### Positive
- More reliable first-time deployments
- Clear documentation of deployment order dependencies
- Reusable patterns for future charts

### Negative
- Additional complexity in Ansible roles
- Wait-for-image Jobs add deployment time (but prevent failures)

## Related ADRs

- [ADR-024: External Secrets for Model Storage](024-external-secrets-model-storage.md)
- [ADR-029: Jupyter Notebook Validator Operator](029-jupyter-notebook-validator-operator.md)
- [ADR-030: Hybrid Management Model for Namespaced ArgoCD Deployments](030-hybrid-management-model-namespaced-argocd.md)
- [ADR-027: CI/CD Pipeline Automation with Tekton and ArgoCD](027-cicd-pipeline-automation.md)

## References

- ArgoCD Resource Health Checks: https://argo-cd.readthedocs.io/en/stable/operator-manual/health/
