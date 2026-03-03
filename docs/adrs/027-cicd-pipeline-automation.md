# ADR-027: CI/CD Pipeline Automation with Tekton and ArgoCD

**Status:** ACCEPTED
**Date:** 2025-11-02
**Decision Makers:** Architecture Team, DevOps Team
**Consulted:** Validated Patterns Community
**Informed:** Development Team, Operations Team

## Implementation Status
**Status:** 🚧 PARTIALLY IMPLEMENTED
**Verification Date:** 2026-01-25
**Implementation Score:** 7.5/10
**Verified On:** SNO + HA clusters
**Evidence:** ArgoCD GitOps + Tekton pipelines operational; GitHub webhook automation pending.

## Context

The OpenShift AIOps Platform requires automated CI/CD pipelines for:
- **Deployment Validation**: 26 comprehensive checks across infrastructure, operators, storage, model serving
- **Model Configuration**: S3 credential discovery, model upload, InferenceService reconciliation
- **Continuous Integration**: Automated testing on code changes
- **Continuous Deployment**: GitOps-based deployment via ArgoCD
- **Compliance Validation**: Automated security and compliance checks

### Current State Analysis

**Existing Pipelines:**
1. **deployment-validation-pipeline**: 26 checks (prerequisites, operators, storage, model serving, coordination engine, monitoring)
2. **model-serving-validation-pipeline**: Specialized KServe validation
3. **s3-configuration-pipeline**: S3 setup and model deployment

**Installed Operators:**
- OpenShift Pipelines (Tekton): 1.17.2
- OpenShift GitOps (ArgoCD): 1.15.4

**Gaps Identified:**
1. No automated trigger on git push/merge
2. Manual pipeline execution required
3. No integration with GitHub webhooks
4. Limited CI/CD observability
5. No automated rollback mechanism

## Decision

We will implement **comprehensive CI/CD automation using Tekton Pipelines and ArgoCD** with the following architecture:

### 1. GitOps-First Deployment Model

**ArgoCD as Source of Truth:**
- All deployments declarative in git
- Automated sync on git changes
- Self-healing enabled (auto-correction of drift)
- Progressive rollout with health checks

**Implementation:**
```yaml
# values-global.yaml (existing)
gitOps:
  namespace: openshift-gitops
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

### 2. Tekton Pipeline Orchestration

**Pipeline Hierarchy:**
```
1. Pre-Deployment Validation (deployment-validation-pipeline)
   ├─ Prerequisites Check
   ├─ Operator Validation
   ├─ Storage Validation
   └─ Security Compliance

2. Deployment (ArgoCD Sync)
   ├─ Application Sync
   ├─ Health Check
   └─ Rollout Status

3. Post-Deployment Validation (model-serving-validation-pipeline)
   ├─ Model Serving Validation
   ├─ Inference Testing
   └─ Performance Metrics

4. Configuration (s3-configuration-pipeline)
   ├─ S3 Credential Discovery
   ├─ Model Upload
   └─ InferenceService Reconciliation
```

### 3. Automated Triggers

**GitHub Webhook Integration:**
- Trigger on push to main branch
- Trigger on pull request merge
- Trigger on release tag creation

**EventListener Configuration:**
```yaml
# tekton/triggers/github-webhook-trigger.yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-webhook-listener
  namespace: openshift-pipelines
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
    - name: github-push-trigger
      interceptors:
        - ref:
            name: github
          params:
            - name: eventTypes
              value: ["push", "pull_request"]
            - name: secretRef
              value:
                secretName: github-webhook-secret
                secretKey: secretToken
      bindings:
        - ref: github-push-binding
      template:
        ref: cicd-pipeline-template
```

### 4. Ansible Automation Mapping

**Validated Patterns Toolkit Integration:**

```yaml
# ansible/playbooks/deploy_cicd_pipelines.yml
- name: Deploy CI/CD Pipelines
  hosts: localhost
  roles:
    # Deploy GitOps infrastructure
    - role: validated_patterns_common
      vars:
        gitops_enabled: true
        gitops_namespace: openshift-gitops

    # Deploy Tekton pipelines
    - role: validated_patterns_deploy
      vars:
        deploy_tekton_pipelines: true
        tekton_namespace: openshift-pipelines

    # Validate deployment
    - role: validated_patterns_validate
      vars:
        validate_gitops: true
        validate_tekton: true
```

**Role Responsibilities:**
- `validated_patterns_common`: ArgoCD installation, clustergroup chart deployment
- `validated_patterns_deploy`: Tekton pipeline deployment, trigger configuration
- `validated_patterns_validate`: Pipeline health checks, ArgoCD sync validation

## Alternatives Considered

### Alternative 1: Jenkins
**Pros:**
- Mature ecosystem
- Extensive plugin library
- Familiar to many teams

**Cons:**
- Not Kubernetes-native
- Resource-heavy
- Complex configuration management
- Not aligned with GitOps principles

**Decision:** Rejected; Tekton is Kubernetes-native and GitOps-aligned

### Alternative 2: GitHub Actions
**Pros:**
- Integrated with GitHub
- Simple YAML configuration
- Large marketplace

**Cons:**
- External dependency (GitHub)
- Limited OpenShift integration
- Not suitable for on-premises deployments
- Vendor lock-in

**Decision:** Rejected for primary CI/CD; acceptable for auxiliary tasks

### Alternative 3: GitLab CI/CD
**Pros:**
- Integrated CI/CD platform
- Good Kubernetes integration
- Built-in container registry

**Cons:**
- Additional infrastructure to manage
- Not OpenShift-native
- Licensing costs for enterprise features

**Decision:** Rejected; Tekton + ArgoCD provides better OpenShift integration

## Consequences

### Positive

1. **Automation**
   - 100% automated deployment on git push
   - Zero manual intervention for standard deployments
   - Automated rollback on failure

2. **Reliability**
   - 26 automated validation checks before deployment
   - Health checks during rollout
   - Self-healing via ArgoCD

3. **Observability**
   - Real-time pipeline execution logs
   - ArgoCD UI for deployment status
   - Prometheus metrics for pipeline performance

4. **Developer Experience**
   - Git-based workflow (familiar)
   - Fast feedback loop (<10 minutes)
   - Clear failure messages

### Negative

1. **Complexity**
   - Multiple tools to learn (Tekton, ArgoCD)
   - YAML configuration overhead
   - Debugging pipeline issues

2. **Resource Usage**
   - Tekton pods consume cluster resources
   - ArgoCD continuous reconciliation
   - Storage for pipeline logs

3. **Migration Effort**
   - Existing manual processes need automation
   - Team training required
   - Pipeline development time

### Neutral

1. **Maintenance**
   - Pipeline updates via git (GitOps)
   - Operator-managed upgrades
   - Regular validation required

## Implementation Plan

### Phase 1: Foundation (Week 1-2)
**Objective:** Deploy core CI/CD infrastructure

**Tasks:**
1. Deploy ArgoCD via validated_patterns_common role
   ```bash
   ansible-playbook ansible/playbooks/deploy_gitops.yml
   ```

2. Deploy Tekton pipelines
   ```bash
   oc apply -f tekton/tasks/
   oc apply -f tekton/pipelines/
   ```

3. Configure ArgoCD applications
   ```bash
   oc apply -f charts/hub/templates/argocd-applications.yaml
   ```

**Validation:**
```bash
# Verify ArgoCD
oc get applications -n openshift-gitops

# Verify Tekton
tkn pipeline list -n openshift-pipelines
```

### Phase 2: Automated Triggers (Week 3-4)
**Objective:** Enable webhook-based automation

**Tasks:**
1. Create GitHub webhook secret
   ```bash
   oc create secret generic github-webhook-secret \
     -n openshift-pipelines \
     --from-literal=secretToken=$(openssl rand -hex 20)
   ```

2. Deploy EventListener and triggers
   ```bash
   oc apply -f tekton/triggers/
   ```

3. Configure GitHub webhook
   - URL: `https://el-github-webhook-listener-openshift-pipelines.apps.<cluster-domain>`
   - Events: push, pull_request
   - Secret: from github-webhook-secret

4. Test webhook trigger
   ```bash
   # Make a commit and push
   git commit -m "test: trigger CI/CD pipeline"
   git push origin main

   # Verify pipeline started
   tkn pipelinerun list -n openshift-pipelines
   ```

**Validation:**
```bash
# Check EventListener
oc get eventlistener -n openshift-pipelines

# View trigger logs
oc logs -n openshift-pipelines -l eventlistener=github-webhook-listener
```

### Phase 3: Progressive Rollout (Week 5-6)
**Objective:** Implement safe deployment strategies

**Tasks:**
1. Configure ArgoCD sync waves
   ```yaml
   # charts/hub/templates/coordination-engine.yaml
   metadata:
     annotations:
       argocd.argoproj.io/sync-wave: "1"
   ```

2. Implement health checks
   ```yaml
   # charts/hub/templates/coordination-engine.yaml
   spec:
     template:
       spec:
         containers:
           - name: coordination-engine
             livenessProbe:
               httpGet:
                 path: /health
                 port: 8080
             readinessProbe:
               httpGet:
                 path: /ready
                 port: 8080
   ```

3. Configure automated rollback
   ```yaml
   # values-global.yaml
   gitOps:
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       retry:
         limit: 5
         backoff:
           duration: 5s
           factor: 2
           maxDuration: 3m
   ```

4. Create rollback Tekton task
   ```yaml
   # tekton/tasks/rollback-deployment.yaml
   apiVersion: tekton.dev/v1beta1
   kind: Task
   metadata:
     name: rollback-deployment
   spec:
     params:
       - name: application
         type: string
       - name: revision
         type: string
     steps:
       - name: rollback
         image: quay.io/argoproj/argocd:latest
         script: |
           #!/bin/bash
           argocd app rollback $(params.application) $(params.revision)
   ```

**Validation:**
```bash
# Test rollback
tkn task start rollback-deployment \
  -p application=self-healing-platform \
  -p revision=HEAD~1 \
  -n openshift-pipelines
```

### Phase 4: Observability (Week 7-8)
**Objective:** Comprehensive CI/CD monitoring

**Tasks:**
1. Deploy Tekton Dashboard
   ```bash
   oc apply -f https://github.com/tektoncd/dashboard/releases/latest/download/tekton-dashboard-release.yaml
   ```

2. Configure Prometheus ServiceMonitors
   ```yaml
   # monitoring/servicemonitors/tekton-pipelines.yaml
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: tekton-pipelines
     namespace: openshift-pipelines
   spec:
     selector:
       matchLabels:
         app: tekton-pipelines
     endpoints:
       - port: metrics
         interval: 30s
   ```

3. Create Grafana dashboards
   ```bash
   oc apply -f monitoring/grafana/dashboards/tekton-pipelines.yaml
   ```

4. Configure alerting rules
   ```yaml
   # monitoring/prometheus/rules/tekton-alerts.yaml
   apiVersion: monitoring.coreos.com/v1
   kind: PrometheusRule
   metadata:
     name: tekton-alerts
     namespace: openshift-pipelines
   spec:
     groups:
       - name: tekton
         rules:
           - alert: PipelineRunFailed
             expr: tekton_pipelinerun_failed_total > 0
             for: 5m
             labels:
               severity: warning
             annotations:
               summary: "Tekton pipeline run failed"
   ```

**Validation:**
```bash
# Access Tekton Dashboard
oc get route tekton-dashboard -n openshift-pipelines

# View Grafana dashboards
oc get route grafana -n openshift-monitoring
```

## Automation Scripts

### 1. CI/CD Pipeline Deployment
**Location:** `ansible/playbooks/deploy_cicd_pipelines.yml`

**Purpose:** Automated deployment of all CI/CD components

```yaml
---
- name: Deploy CI/CD Pipelines
  hosts: localhost
  gather_facts: false

  tasks:
    - name: Deploy GitOps infrastructure
      include_role:
        name: validated_patterns_common
      vars:
        gitops_enabled: true

    - name: Deploy Tekton pipelines
      include_role:
        name: validated_patterns_deploy
      vars:
        deploy_tekton_pipelines: true

    - name: Validate CI/CD deployment
      include_role:
        name: validated_patterns_validate
      vars:
        validate_gitops: true
        validate_tekton: true
```

### 2. Pipeline Validation Script
**Location:** `scripts/validate-cicd-pipelines.sh`

**Purpose:** Validate CI/CD pipeline health

```bash
#!/bin/bash
set -e

echo "=== CI/CD Pipeline Validation ==="

# Check ArgoCD
echo "Checking ArgoCD..."
oc get applications -n openshift-gitops
oc get appprojects -n openshift-gitops

# Check Tekton
echo "Checking Tekton pipelines..."
tkn pipeline list -n openshift-pipelines
tkn task list -n openshift-pipelines

# Check triggers
echo "Checking Tekton triggers..."
oc get eventlistener -n openshift-pipelines
oc get triggerbinding -n openshift-pipelines
oc get triggertemplate -n openshift-pipelines

# Check recent pipeline runs
echo "Recent pipeline runs:"
tkn pipelinerun list -n openshift-pipelines --limit 5

echo "✅ CI/CD validation complete"
```

### 3. Automated Rollback Script
**Location:** `scripts/rollback-deployment.sh`

**Purpose:** Automated rollback on deployment failure

```bash
#!/bin/bash
set -e

APPLICATION=${1:-self-healing-platform}
REVISION=${2:-HEAD~1}

echo "=== Rolling back $APPLICATION to $REVISION ==="

# Get ArgoCD server
ARGOCD_SERVER=$(oc get route argocd-server -n openshift-gitops -o jsonpath='{.spec.host}')

# Login to ArgoCD
argocd login $ARGOCD_SERVER --grpc-web

# Rollback application
argocd app rollback $APPLICATION $REVISION

# Wait for sync
argocd app wait $APPLICATION --sync

echo "✅ Rollback complete"
```

## Success Metrics

1. **Automation Metrics**
   - Deployment automation: 100% (zero manual deployments)
   - Pipeline success rate: >95%
   - Average pipeline duration: <10 minutes

2. **Reliability Metrics**
   - Deployment failures: <5% (with automated rollback)
   - Mean time to recovery (MTTR): <5 minutes
   - Change failure rate: <10%

3. **Developer Metrics**
   - Commit to production time: <15 minutes
   - Developer satisfaction: >4/5
   - Pipeline debugging time: <30 minutes

## Related ADRs

- [ADR-019: Validated Patterns Framework Adoption](019-validated-patterns-framework-adoption.md)
- [ADR-021: Tekton Pipeline Deployment Validation](021-tekton-pipeline-deployment-validation.md)
- [ADR-023: Tekton Configuration Pipeline](023-tekton-configuration-pipeline.md)
- [ADR-DEVELOPMENT-RULES: Development Guidelines](ADR-DEVELOPMENT-RULES.md)

## References

- [OpenShift Pipelines Documentation](https://docs.openshift.com/pipelines/latest/index.html)
- [OpenShift GitOps Documentation](https://docs.openshift.com/gitops/latest/index.html)
- [Tekton Documentation](https://tekton.dev/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Validated Patterns Toolkit](https://github.com/tosin2013/validated-patterns-ansible-toolkit)

## Approval

- **Architecture Team**: Approved
- **DevOps Team**: Approved
- **Date**: 2025-11-02
