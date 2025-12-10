# ADR-030: Hybrid Management Model for Namespaced ArgoCD Deployments

**Status:** ACCEPTED
**Date:** 2025-11-06
**Decision Makers:** Architecture Team
**Consulted:** DevOps Team, Platform Operations
**Informed:** Development Team, Operations Team

## Context

The Self-Healing Platform uses a **namespaced ArgoCD instance** (`hub-gitops` in `self-healing-platform-hub` namespace) to manage application deployments. However, the platform requires both:

1. **Cluster-scoped resources**: ClusterRole, ClusterRoleBinding, ClusterServingRuntime (KServe)
2. **Namespaced resources**: InferenceService, ConfigMap, ServiceAccount, Deployment, etc.

### The Problem

**Namespaced ArgoCD controllers cannot manage cluster-scoped resources**. This is an architectural limitation, not a configuration issue. When ArgoCD attempts to sync resources that include cluster-scoped dependencies, it fails with errors like:

```
Failed to load live state: Cluster level ClusterRole "self-healing-operator-cluster" can not be managed when in namespaced mode
```

### Attempted Solutions (Rejected)

1. **ignoreDifferences Configuration**: Attempted to ignore cluster-scoped resources using `spec.ignoreDifferences`. **Rejected** because:
   - `ignoreDifferences` is applied during the **Comparison Phase** (Phase 5)
   - Namespace/cluster-scope validation occurs during **Load Live State Phase** (Phase 3)
   - Validation happens **before** ignore rules are applied
   - This is architecturally impossible to bypass

2. **resource.exclusions**: Attempted to exclude cluster-scoped resources globally. **Rejected** because:
   - Creates a GitOps "black hole" - resources exist but aren't managed
   - Breaks GitOps principles (resources not in git)
   - Anti-pattern that reduces observability

3. **Migrate to Cluster-Scoped ArgoCD**: **Rejected** because:
   - Sacrifices multi-tenancy and security isolation
   - Increases "blast radius" for tenant applications
   - Violates security best practices for multi-tenant platforms

### Research Findings

A comprehensive architectural analysis (see `docs/research/argocd-namespace-management-validation-research.md`) revealed:

1. **Phase Order Mismatch**: Validation occurs before comparison, making `ignoreDifferences` ineffective
2. **Two-Key Security System**: Namespaced ArgoCD requires both:
   - **Key 1**: `argocd.argoproj.io/managed-by` label (operator creates RBAC)
   - **Key 2**: `applicationNamespaces` or `sourceNamespaces` in ArgoCD CR (controller validation)
3. **Hidden Dependencies**: KServe InferenceService resources depend on ClusterServingRuntime, which cannot be managed by namespaced controllers

## Decision

We will implement **Pattern 3: Hybrid Management Model** (also called "Platform-Tenant Model"):

### Architecture

**Separation of Concerns**:
- **Cluster-scoped resources**: Deployed via **Ansible role** (`validated_patterns_deploy_cluster_resources`) **BEFORE** ArgoCD Application creation
- **Namespaced resources**: Deployed via **ArgoCD Application** with `rbac.clusterScoped.enabled=false` in Helm values

### Implementation

#### Step 1: Deploy Cluster-Scoped Resources (Ansible)

**Role**: `validated_patterns_deploy_cluster_resources`

**Resources Deployed**:
- External Secrets Operator ClusterRole/ClusterRoleBinding
- Self-Healing Operator ClusterRole/ClusterRoleBinding
- Workbench ClusterRole/ClusterRoleBinding
- ArgoCD ClusterRole/ClusterRoleBinding
- KServe ClusterServingRuntime resources (if any)

**When**: Executed **before** ArgoCD Application creation in deployment playbook

**How**: Extracts cluster-scoped resources from Helm chart using `helm template` with `rbac.clusterScoped.enabled=true`, then deploys them directly via Kubernetes API

#### Step 2: Deploy Namespaced Resources (ArgoCD)

**Helm Chart Configuration**: `values-global.yaml` sets `rbac.clusterScoped.enabled: false`

**ArgoCD Application**: Manages only namespaced resources (InferenceService, ConfigMap, ServiceAccount, Deployment, etc.)

**ArgoCD CR Configuration**: `spec.sourceNamespaces: ["self-healing-platform"]` (Key 2)

### Deployment Sequence

```
1. Prerequisites Validation
2. Common Infrastructure (Helm, ArgoCD, ESO)
3. Secrets Management Configuration
4. Cluster-Scoped Resources Deployment (NEW - Ansible role)
5. Pattern Deployment (Namespaced Resources via ArgoCD)
6. Post-Deployment Validation
```

### Updated Playbook Structure

```yaml
# ansible/playbooks/deploy_complete_pattern.yml

roles:
  # ... existing roles ...

  # Step 4.5: Deploy Cluster-Scoped Resources
  - name: Deploy cluster-scoped resources
    role: validated_patterns_deploy_cluster_resources
    vars:
      pattern_namespace: "{{ pattern_namespace }}"
      deploy_cluster_resources: true
      helm_chart_path: "{{ helm_chart_path }}"
      values_files:
        - "{{ values_global_path }}"
        - "{{ values_hub_path }}"
      cluster_rbac:
        enabled: true
        external_secrets:
          enabled: true
        operator:
          enabled: true
        workbench:
          enabled: true
        argocd:
          enabled: true
      kserve:
        enabled: true

  # Step 5: Pattern Deployment (Namespaced Resources via ArgoCD)
  - name: Deploy pattern application
    role: validated_patterns_deploy
    # ... existing configuration ...
```

### Helm Chart Changes

**values-global.yaml**:
```yaml
rbac:
  enabled: true
  # Enable cluster-scoped RBAC resources (ClusterRole, ClusterRoleBinding)
  # Set to false when deploying via namespaced ArgoCD (cannot manage cluster-scoped resources)
  clusterScoped:
    enabled: false  # Cluster resources deployed via Ansible role
```

**charts/hub/templates/rbac.yaml**:
```yaml
{{- if .Values.rbac.clusterScoped.enabled }}
# ClusterRole and ClusterRoleBinding definitions
{{- end }}
```

**charts/hub/templates/secretstore.yaml**:
```yaml
{{- if .Values.rbac.clusterScoped.enabled }}
# External Secrets Operator ClusterRole/ClusterRoleBinding
{{- end }}
```

### ArgoCD Configuration

**ArgoCD CR** (`hub-gitops`):
```yaml
spec:
  sourceNamespaces:
    - self-healing-platform  # Key 2: Allow controller to manage this namespace
```

**ArgoCD Application** (`self-healing-platform`):
- Manages only namespaced resources
- References cluster-scoped resources (already deployed by Ansible)
- Uses `ignoreDifferences` for resources that may be modified outside ArgoCD

## Consequences

### Positive

- ✅ **Maintains Security Isolation**: Namespaced ArgoCD controller remains isolated
- ✅ **GitOps Compliant**: All resources still managed declaratively (via Ansible + ArgoCD)
- ✅ **Separation of Concerns**: Platform resources (cluster-scoped) vs. tenant resources (namespaced)
- ✅ **Scalable**: Supports multiple tenant namespaces with same cluster-scoped dependencies
- ✅ **Idempotent**: Ansible role can be safely re-run
- ✅ **Observable**: Both deployment methods provide clear status and logs

### Negative

- ⚠️ **Two Deployment Mechanisms**: Requires understanding both Ansible and ArgoCD
- ⚠️ **Deployment Order Dependency**: Cluster resources must be deployed before ArgoCD sync
- ⚠️ **Manual Coordination**: No automatic dependency enforcement (relies on playbook order)
- ⚠️ **Helm Chart Complexity**: Conditional rendering based on `rbac.clusterScoped.enabled`

### Neutral

- **Deployment Time**: Slightly longer due to additional Ansible role execution
- **Maintenance**: Requires maintaining both Ansible role and Helm chart templates
- **Documentation**: Requires clear documentation of deployment sequence

## Related ADRs

- **ADR-019**: Validated Patterns Framework Adoption (deployment framework)
- **ADR-020**: Bootstrap Deployment and Deletion Lifecycle (deployment sequence)
- **ADR-002**: Hybrid Deterministic-AI Self-Healing Approach (hybrid architecture pattern)
- **ADR-004**: KServe for Model Serving Infrastructure (KServe dependencies)
- **ADR-026**: Secrets Management Automation (External Secrets Operator RBAC)

## References

- [Research: ArgoCD Namespace Management Validation](docs/research/argocd-namespace-management-validation-research.md)
- [ArgoCD Application Namespaces Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/app-any-namespace/)
- [OpenShift GitOps Namespaced Mode](https://docs.redhat.com/en/documentation/openshift_gitops/1.15/html/installing-openshift-gitops/installing-openshift-gitops#installing-openshift-gitops-in-namespace-mode_installing-openshift-gitops)
- [KServe ClusterServingRuntime](https://kserve.github.io/website/0.11/modelserving/runtimes/cluster-serving-runtime/)

## Implementation Checklist

- [x] Create `validated_patterns_deploy_cluster_resources` Ansible role
- [x] Update Helm chart templates to conditionally exclude cluster-scoped resources
- [x] Update `values-global.yaml` with `rbac.clusterScoped.enabled: false`
- [x] Update `deploy_complete_pattern.yml` to include cluster resources deployment step
- [x] Configure ArgoCD CR with `sourceNamespaces`
- [x] Document deployment sequence in playbook comments
- [x] **Automate hub-gitops ArgoCD controller ClusterRoleBinding** (2025-12-10)
- [x] **Create comprehensive troubleshooting guide** (2025-12-10)
- [x] **Update deployment documentation with troubleshooting references** (2025-12-10)
- [ ] Update ADR-019 to reference new role
- [ ] Test end-to-end deployment workflow
- [ ] Update cleanup playbook to remove cluster-scoped resources

## Approval

- **Architect**: Approved
- **Platform Team**: Approved
- **Date**: 2025-11-06
