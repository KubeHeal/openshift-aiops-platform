# ADR-020: Bootstrap Deployment and Deletion Lifecycle with Deploy/Delete Modes

## Status
accepted - 2025-10-23

## Context

The OpenShift AIOps Self-Healing Platform requires a reliable, repeatable mechanism to deploy and delete the entire platform stack using the Validated Patterns framework.

**Two Deployment Audiences**:
1. **End Users** (Production): Use simplified end-user workflow via `make -f common/Makefile operator-deploy`
2. **Developers** (Development): Use granular development workflow via Ansible roles for customization

Teams need a single, consistent CLI interface that supports both deployment and cleanup operations, with clear state management, error handling, and operational observability.

The bootstrap process must be idempotent to support repeated deployments across multiple environments (dev, staging, production) and enable safe cleanup without leaving orphaned resources.

### Alternatives Considered

1. **Separate deploy.sh and delete.sh scripts** - Rejected due to code duplication and inconsistent UX
2. **Manual kubectl/helm commands** - Rejected due to lack of validation and error handling
3. **Custom Kubernetes Operator for bootstrap** - Rejected due to complexity and maintenance burden
4. **Terraform-based deployment** - Rejected due to divergence from Validated Patterns framework

### Supporting Evidence

- [Validated Patterns OpenShift Framework](https://validatedpatterns.io/learn/vp_openshift_framework/)
- ADR-019: Validated Patterns Framework Adoption
- Production deployment experience: repeated deployments require idempotency
- Operational requirements: teams need clear, repeatable procedures
- Security requirements: cleanup must remove all resources to prevent leaks

## Decision

Implement a unified **bootstrap.sh** script that supports both `--deploy` and `--delete` modes, following the Validated Patterns OpenShift Framework.

**For End Users**: Use the simplified end-user workflow via `make -f common/Makefile operator-deploy` for production deployments.

**For Developers**: Use the granular development workflow via Ansible roles for customization and debugging.

### Implementation Strategy

The script will:

1. **Use make targets**: `make install` for deployment, `make uninstall` for cleanup
2. **Implement idempotency**: Resource reconciliation and drift detection
3. **Clear CLI interface**: `--deploy`, `--delete`, and `--force` flags
4. **State checkpointing**: Store bootstrap state in Kubernetes ConfigMaps
5. **Error handling**: Comprehensive error handling with automatic rollback
6. **Structured logging**: JSON-formatted logs for observability
7. **Environment support**: Helm values overlays for dev/staging/production

### Deployment Flow (--deploy)

```
Phase 1: Pre-deployment Validation
  ├─ Cluster connectivity check
  ├─ Required tools verification (oc, kubectl, helm, yq, make)
  ├─ Namespace verification
  └─ RBAC permissions check

Phase 2: Infrastructure Validation
  ├─ OpenShift GitOps operator
  ├─ OpenShift Data Foundation
  ├─ KServe availability
  └─ Knative Serverless

Phase 3: Validated Patterns Deployment
  ├─ make validate-prereq
  ├─ make validate-cluster
  └─ make install (with timeout)

Phase 4: Deployment Verification
  ├─ ArgoCD applications sync
  ├─ Pod status verification
  └─ Resource count validation

Phase 5: Health Checks
  ├─ Coordination engine readiness
  ├─ Model serving endpoints
  └─ Object storage availability
```

### Deletion Flow (--delete)

```
Phase 1: Pre-deletion Validation
  ├─ Cluster connectivity check
  ├─ Required tools verification
  ├─ Namespace existence check
  └─ Confirmation prompt (unless --force)

Phase 2: Resource Cleanup
  ├─ make uninstall (Helm uninstall)
  ├─ Delete ArgoCD applications
  └─ Delete namespace

Phase 3: Verification
  ├─ Namespace deletion confirmation
  ├─ Resource cleanup verification
  └─ State cleanup
```

## E2E Testing and Cleanup Procedures

### Mandatory Cleanup Before Testing

**CRITICAL**: Always clean up before running e2e tests to ensure fresh state and avoid conflicts.

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

### Task Reusability Pattern

Reuse specific task files instead of entire roles during validation:

```yaml
# Good: Reuse specific validation task
- include_tasks: ../../ansible/roles/validated_patterns_prerequisites/tasks/check_openshift_version.yml

# Avoid: Re-running entire role when only one check needed
- include_role:
    name: validated_patterns_prerequisites  # Runs ALL checks unnecessarily
```

### Resources to Clean (Checklist)

- ✅ Pattern Custom Resources (`oc get pattern -A`) — **ALWAYS**
- ✅ ArgoCD Applications (`oc get applications -n openshift-gitops`) — **ALWAYS**
- ✅ Application namespaces (self-healing-platform, etc.) — **ALWAYS**
- ✅ ConfigMaps and Secrets created by patterns — **ALWAYS**
- ✅ BuildConfigs and ImageStreams (if testing builds) — **ALWAYS**
- ✅ Routes and Services (application-specific) — **ALWAYS**
- ⚠️ OpenShift GitOps namespace — **RARELY** (only if common/ subtree requires redeployment)
- ⚠️ Gitea namespace — **RARELY** (only if starting completely fresh)
- ⚠️ Subscriptions and CSVs — **RARELY** (only if testing operator installation itself)

## Consequences

### Positive Consequences

- Single source of truth for deployment and deletion logic
- Idempotent operations enable safe re-runs and environment refresh
- Clear CLI reduces operator error
- State checkpointing enables resume on failure
- Structured JSON logging improves troubleshooting
- Supports repeated deployments across environments
- Role-based E2E testing ensures consistency and reusability

### Negative Consequences

- Increased script complexity and maintenance surface
- Requires Kubernetes ConfigMap for state storage
- Longer initial bootstrap time due to validation steps
- Requires pre-bootstrap.sh for dependency installation

### Neutral Considerations

- Depends on existing make targets from Validated Patterns framework
- Requires proper RBAC permissions for bootstrap service account
- Requires 8 Ansible roles to be copied into project

## Implementation Tasks

1. Develop unified bootstrap.sh with --deploy, --delete, --force flags
2. Integrate Kubernetes ConfigMap for state checkpointing
3. Implement idempotent resource reconciliation logic
4. Add structured JSON logging
5. Implement comprehensive error handling and rollback
6. Configure Helm values overlays for environments
7. Create comprehensive documentation and runbooks
8. Conduct end-to-end tests for both workflows

## Related ADRs

- **ADR-009**: Bootstrap Deployment Automation
- **ADR-019**: Validated Patterns Framework Adoption
- **ADR-021**: Tekton Pipeline for Post-Deployment Validation
- **ADR-DEVELOPMENT-RULES**: Development rules and E2E testing best practices

## References

- [Validated Patterns Framework](https://validatedpatterns.io/)
- [validated-patterns-ansible-toolkit](https://github.com/tosin2013/validated-patterns-ansible-toolkit)
- [OpenShift GitOps Documentation](https://docs.openshift.com/gitops/)
- [Helm Documentation](https://helm.sh/docs/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
