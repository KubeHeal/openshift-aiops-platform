# ADR-019: Validated Patterns Framework Adoption

## Status
**ACCEPTED** - 2025-10-16

## Implementation Status
**Status:** ✅ IMPLEMENTED
**Verification Date:** 2026-03-03
**Implementation Score:** 10.0/10
**Verified On:** SNO + HA clusters
**Evidence:** Patterns Operator 0.0.65, GitOps 1.19.1 deployed. Pattern CR created and reconciling on both clusters. ArgoCD applications synced. Multi-source Helm support validated.

## Context

The Self-Healing Platform initially implemented a custom bootstrap deployment system (ADR-009) using Kustomize and shell scripts. While functional, this approach diverges from industry standards and Red Hat's official Validated Patterns framework.

### Current State Issues

1. **Non-Standard Approach**: Custom bootstrap.sh doesn't follow Red Hat's official deployment patterns
2. **Limited GitOps Integration**: Manual deployment scripts instead of ArgoCD-native workflows
3. **Scalability Concerns**: Custom approach doesn't support multi-cluster deployments
4. **Maintenance Burden**: Requires custom script maintenance instead of leveraging community patterns
5. **Image Management**: Custom image building and registry management adds complexity

### Validated Patterns Framework Benefits

The Validated Patterns OpenShift Framework (https://validatedpatterns.io/) provides:

1. **Industry Standard**: Red Hat's official framework for deploying patterns on OpenShift
2. **GitOps Native**: Built on OpenShift GitOps (ArgoCD) for declarative deployments
3. **Multi-Cluster Support**: Red Hat Advanced Cluster Management (ACM) integration
4. **Helm + Kustomize**: Combines Helm for templating with Kustomize for customization
5. **Secrets Management**: Integrated Vault + External Secrets Operator support
6. **Community Patterns**: Access to validated, tested deployment patterns
7. **Makefile Automation**: Standardized `make install` entry point

## Decision

We will **adopt the Validated Patterns OpenShift Framework** as the primary deployment mechanism for the Self-Healing Platform, replacing the custom bootstrap system while maintaining backward compatibility.

### Ansible Role Architecture

The framework uses 9 production-ready Ansible roles (8 from validated-patterns-ansible-toolkit + 1 custom):

1. **validated_patterns_prerequisites** - Cluster validation (OpenShift version, operators, resources, RBAC, storage, network). Auto-installs OpenShift GitOps operator if missing (controlled by `validated_patterns_auto_install_gitops` variable).
2. **validated_patterns_common** - Helm/GitOps infrastructure (Helm install, ArgoCD, clustergroup chart)
3. **validated_patterns_operator** - Simplified end-user deployment via VP Operator
4. **validated_patterns_deploy** - Application deployment via ArgoCD and BuildConfigs
5. **validated_patterns_gitea** - Local git repository for development environments
6. **validated_patterns_secrets** - Secrets management (sealed secrets, credentials, validation)
7. **validated_patterns_validate** - Comprehensive pre/post-deployment validation and health checks
8. **validated_patterns_cleanup** - Resource cleanup (Pattern CRs, ArgoCD apps, namespaces)
9. **validated_patterns_deploy_cluster_resources** - Deploy cluster-scoped resources separately for namespaced ArgoCD (see ADR-030)

**Key Principle**: Each role uses modular `include_tasks` for reusable task files that can be used independently in E2E tests and custom playbooks.

### Implementation Strategy

#### Phase 1: Framework Integration
- ✅ Create `values-hub.yaml` - Hub cluster configuration
- ✅ Create `values-secret.yaml.template` - Secrets template
- ✅ Update `Makefile` - Add `make install` target
- ✅ Install `yq` tool - Required for Makefile operations
- ⏳ Integrate common repository - Git subtree with shared utilities
- ⏳ Copy 8 Ansible roles into `ansible/roles/` directory

#### Phase 2: Chart Refactoring
- Refactor `k8s/base/` → `charts/hub/templates/`
- Create `charts/hub/Chart.yaml` and `charts/hub/values.yaml`
- Maintain Kustomize compatibility for overlays

#### Phase 3: GitOps Deployment
- Configure OpenShift GitOps operator
- Create ArgoCD Application resources
- Test `make install` deployment workflow

#### Phase 4: Multi-Cluster Support
- Document ACM integration
- Test cluster registration
- Validate GitOps propagation

### Configuration Files

#### values-global.yaml (Existing)
```yaml
global:
  pattern: self-healing-platform
  version: "1.0.0"

main:
  multiSourceConfig:
    enabled: true
  clusterGroupName: hub
  namespace: self-healing-platform
  components:
    openshift-ai: true
    gpu-operator: true
    serverless: true
```

#### values-hub.yaml (New)
Hub cluster-specific configuration including:
- Operator subscriptions (GitOps, AI, GPU, Serverless, Pipelines, ODF)
- Application deployments (coordination-engine, model-serving, notebooks, monitoring)
- Storage configuration
- Networking and security policies
- Monitoring and observability settings

#### values-secret.yaml.template (New)
Secrets template for:
- Git repository credentials
- Container registry credentials
- Vault configuration
- Database credentials
- External API keys
- SSL/TLS certificates

### Deployment Workflow

**Before (Custom Bootstrap)**:
```bash
./bootstrap.sh
./validate_bootstrap.sh
```

**After (Validated Patterns)**:
```bash
make install
make argo-healthcheck
```

### Deployment Workflows for Different Audiences

#### Development Workflow (Granular Control)

**Audience**: Pattern developers, maintainers, advanced users

Uses roles 1-2, 4-7 for step-by-step deployment with full control:

```bash
ansible-playbook ansible/playbooks/deploy_complete_pattern.yml
```

**Best for**: Pattern development, debugging, learning, customization

#### End-User Workflow (Simplified) - **RECOMMENDED FOR END USERS**

**Audience**: End users, production deployments, operations teams

Uses role 3 (VP Operator) for simplified, one-command deployment:

```bash
make -f common/Makefile operator-deploy
```

**Key Benefits for End Users**:
- ✅ Single command deployment
- ✅ Automatic prerequisite validation
- ✅ Built-in error handling and recovery
- ✅ No need to understand Ansible roles
- ✅ Consistent, repeatable deployments
- ✅ Production-ready with health checks

**End-User Deployment Steps**:
1. Clone the repository
2. Configure `values-hub.yaml` with environment-specific settings
3. Create `values-secret.yaml` from template with credentials
4. Run: `make -f common/Makefile operator-deploy`
5. Validate: `make -f common/Makefile argo-healthcheck`
6. Run post-deployment validation: Tekton pipeline (see ADR-021)

### E2E Testing Best Practices

All E2E tests MUST follow the role-based approach:

```yaml
# E2E Test Template
- name: E2E Test with Role-Based Approach
  hosts: localhost
  tasks:
    # 1. Pre-test cleanup using role (MANDATORY)
    - include_role:
        name: validated_patterns_cleanup
      # Default behavior retains shared infrastructure:
      # cleanup_gitops: false   # Keep ArgoCD (from common/ subtree)
      # cleanup_gitea: false    # Keep Gitea (for development)
      # cleanup_operator: false # Keep operator (reusable)

    # 2. Deploy using role
    - include_role:
        name: validated_patterns_operator

    # 3. Validate using specific task files (not entire roles)
    - include_tasks: ../../ansible/roles/validated_patterns_validate/tasks/validate_health.yml

    # 4. Post-test cleanup using role
    - include_role:
        name: validated_patterns_cleanup
```

**Critical Rules**:
- ✅ Always clean up BEFORE testing to ensure fresh state
- ✅ Reuse specific task files, not entire roles, during validation
- ✅ Retain shared infrastructure (GitOps, Gitea, Operator) for efficiency
- ✅ Use `validated_patterns_cleanup` role for consistent cleanup

### Benefits

1. **Standardization**: Follows Red Hat's official deployment patterns
2. **Maintainability**: Leverages community-maintained common repository
3. **Scalability**: Supports multi-cluster deployments via ACM
4. **GitOps**: Native ArgoCD integration for continuous deployment
5. **Secrets Management**: Integrated Vault + ESO for secure credential handling
6. **Community Support**: Access to validated patterns and best practices

### Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Learning curve for team | Comprehensive documentation and training |
| Compatibility with existing scripts | Maintain bootstrap.sh as fallback during transition |
| Dependency on common repository | Git subtree integration ensures local copy |
| Helm complexity | Leverage existing values files and templates |

## Consequences

### Positive
- ✅ Alignment with Red Hat standards
- ✅ Improved multi-cluster support
- ✅ Better GitOps integration
- ✅ Reduced custom maintenance burden
- ✅ Access to community patterns and support

### Negative
- ⚠️ Requires refactoring existing Kustomize structure
- ⚠️ Team needs to learn Validated Patterns framework
- ⚠️ Temporary deployment complexity during transition

### Common Subtree Management (CRITICAL)

The `common/` directory is a **git subtree** imported from [validatedpatterns/common.git](https://github.com/validatedpatterns/common.git).

**⚠️ IMPORTANT**: This repository updates frequently. Keep in sync before major development work.

**Update Procedure**:
```bash
# Option 1: Using utilities script (recommended)
curl -s https://raw.githubusercontent.com/validatedpatterns/utilities/main/scripts/update-common-everywhere.sh | bash

# Option 2: Manual update
git remote add -f common-upstream https://github.com/validatedpatterns/common.git
git merge -s subtree -Xtheirs -Xsubtree=common common-upstream/main
```

**When to Update**:
- ✅ Before starting new feature development
- ✅ Before running comprehensive e2e tests
- ✅ When pattern deployment fails with unknown errors
- ✅ When upstream releases new features/fixes
- ✅ Monthly or before major releases

## Related ADRs

- **ADR-009**: Bootstrap Deployment Automation (superseded by this decision)
- **ADR-001**: OpenShift Platform Selection (foundation for this decision)
- **ADR-014**: MCP Server Integration (deployment target)
- **ADR-020**: Bootstrap Deployment and Deletion Lifecycle
- **ADR-021**: Tekton Pipeline for Post-Deployment Validation
- **ADR-030**: Hybrid Management Model for Namespaced ArgoCD Deployments (cluster-scoped resource deployment)
- **ADR-DEVELOPMENT-RULES**: Development rules and best practices

## References

- [Validated Patterns OpenShift Framework](https://validatedpatterns.io/learn/vp_openshift_framework/)
- [Validated Patterns Common Repository](https://github.com/validatedpatterns/common)
- [OpenShift GitOps Documentation](https://docs.openshift.com/gitops/latest/index.html)
- [Red Hat Advanced Cluster Management](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/)

## Implementation Timeline

- **Week 1**: Framework integration and configuration files (COMPLETE)
- **Week 2**: Chart refactoring and GitOps setup
- **Week 3**: Testing and validation
- **Week 4**: Documentation and team training
- **Week 5**: Production deployment

## Approval

- **Architect**: Approved
- **Platform Team**: Approved
- **Date**: 2025-10-16
