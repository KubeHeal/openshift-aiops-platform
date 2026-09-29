# Makefile Migration Guide: end2end-deployment → operator-deploy

**Date**: 2025-12-01
**Status**: Migration Complete
**Related ADR**: ADR-019 (Validated Patterns Framework Adoption)

---

## Executive Summary

The Makefile has been updated to align with the **Validated Patterns Framework** best practices. The custom `end2end-deployment` targets have been removed in favor of the standard `operator-deploy` workflow from the validated-patterns-ansible-toolkit.

---

## What Changed

### Removed Targets

The following custom targets have been **REMOVED**:

```makefile
# ❌ REMOVED
make end2end-deployment
make end2end-deployment-interactive
make end2end-cleanup
make end2end-help
```

### New Recommended Workflow

Use the **standard Validated Patterns workflow**:

```makefile
# ✅ RECOMMENDED
make operator-deploy          # Deploy pattern (Ansible prereqs + Helm)
make operator-deploy-only     # Skip Ansible prereqs, Helm only
make deployment-help          # Show deployment workflow
make uninstall                # Cleanup pattern
```

---

## Migration Path

### Old Workflow (DEPRECATED)

```bash
# ❌ OLD APPROACH (No longer supported)
make build-ee
make check-prerequisites
make end2end-deployment
make end2end-cleanup
```

### New Workflow (RECOMMENDED)

```bash
# ✅ NEW APPROACH (Validated Patterns Framework)

# Step 1: Build Execution Environment (if needed)
make build-ee

# Step 2: Check prerequisites
make check-prerequisites

# Step 3: Deploy pattern using operator-deploy
make operator-deploy

# Step 4: Load secrets (if needed)
make load-secrets

# Step 5: Validate deployment
make argo-healthcheck

# Step 6: Cleanup when done
make uninstall
```

---

## Detailed Comparison

### Deployment Process

| Aspect | Old (end2end-deployment) | New (operator-deploy) |
|--------|--------------------------|------------------------|
| **Method** | Custom Ansible playbook | Validated Patterns Framework |
| **Helm Integration** | Manual | Automatic via common/scripts/deploy-pattern.sh |
| **Prerequisites** | Custom checks | Standard validate-prereq + validate-cluster |
| **Secrets** | Custom load-env-secrets | Standard load-secrets + ESO integration |
| **ArgoCD** | Manual setup | Automatic via Validated Patterns Operator |
| **Cleanup** | Custom playbook | Standard uninstall |

### What operator-deploy Does

```bash
make operator-deploy
```

**Internally executes**:
1. `operator-deploy-prereqs` - Runs Ansible prerequisites playbook
2. `validate-prereq` - Validates Python dependencies and collections
3. `validate-origin` - Verifies git repository access
4. `validate-cluster` - Checks cluster connectivity and storage
5. `common/scripts/deploy-pattern.sh` - Deploys pattern via Helm + VP Operator

**Equivalent to**:
```bash
# What operator-deploy does under the hood
ansible-navigator run ansible/playbooks/operator_deploy_prereqs.yml
helm install <pattern-name> oci://quay.io/hybridcloudpatterns/pattern-install \
  -f values-global.yaml \
  -f values-clustergroup.yaml \
  --set main.git.repoURL="<repo>" \
  --set main.git.revision="<branch>"
```

---

## Why This Change?

### Benefits of operator-deploy

1. **Framework Alignment**: Follows validated-patterns-ansible-toolkit best practices
2. **Consistency**: Same workflow as all other Validated Patterns
3. **Maintainability**: Leverages common/ subtree scripts (auto-updated)
4. **Operator Integration**: Uses Validated Patterns Operator for GitOps
5. **Helm-Based**: Standard Helm chart deployment (pattern-install)
6. **Multi-Cluster Ready**: Supports ACM integration (ADR-022)

### Issues with end2end-deployment

1. **Custom Implementation**: Non-standard approach requiring custom maintenance
2. **Divergence**: Didn't follow Validated Patterns conventions
3. **Duplication**: Reimplemented functionality already in common/ subtree
4. **Limited Features**: Missing multi-cluster, secrets backend options
5. **No Operator**: Didn't use Validated Patterns Operator

---

## Frequently Asked Questions

### Q: Can I still use Ansible playbooks?

**A**: Yes! The `operator-deploy-prereqs` target runs Ansible prerequisites:

```bash
# Ansible prereqs are still used
make operator-deploy-prereqs
```

This runs `ansible/playbooks/operator_deploy_prereqs.yml` which:
- Sets up Gitea (if configured)
- Configures External Secrets Operator
- Prepares cluster for pattern deployment

### Q: What about the Execution Environment (EE)?

**A**: The EE is still used for Ansible prerequisites:

```bash
# Build EE (still needed)
make build-ee

# EE is used by operator-deploy-prereqs
make operator-deploy
```

### Q: How do I debug deployment issues?

**A**: Use the standard Validated Patterns debugging approach:

```bash
# Check ArgoCD applications
make argo-healthcheck

# View pattern status
oc get pattern -A

# Check ArgoCD apps
oc get applications -n openshift-gitops

# View operator logs
oc logs -n openshift-operators -l control-plane=controller-manager
```

### Q: Can I skip Ansible prerequisites?

**A**: Yes, use `operator-deploy-only`:

```bash
# Skip Ansible prereqs (if already run)
make operator-deploy-only
```

### Q: How do I customize deployment?

**A**: Use Helm options:

```bash
# Pass extra Helm options
make operator-deploy EXTRA_HELM_OPTS="--set foo=bar"

# Set target site
make operator-deploy TARGET_SITE=edge
```

---

## Troubleshooting

### Issue: "operator-deploy failed"

**Solution**: Check prerequisites first:

```bash
make validate-prereq
make validate-cluster
make validate-origin
```

### Issue: "Pattern not deploying"

**Solution**: Check ArgoCD applications:

```bash
make argo-healthcheck
oc get applications -n openshift-gitops
```

### Issue: "Secrets not loading"

**Solution**: Use standard secrets workflow:

```bash
# Load secrets via External Secrets Operator
make load-secrets

# Or setup ESO secrets manually
make setup-eso-secrets
```

### Issue: "Need to cleanup deployment"

**Solution**: Use standard uninstall:

```bash
# Uninstall pattern
make uninstall

# Or full cleanup (if needed)
./tests/integration/cleanup/cleanup.sh
```

---

## References

### Documentation
- **Validated Patterns Framework**: https://validatedpatterns.io/
- **ADR-019**: Validated Patterns Framework Adoption
- **Toolkit Repository**: https://github.com/tosin2013/validated-patterns-ansible-toolkit
- **Common Makefile**: `common/Makefile` (from validatedpatterns/common.git)

### Related ADRs
- **ADR-019**: Validated Patterns Framework Adoption (deployment framework)
- **ADR-020**: Bootstrap Deployment and Deletion Lifecycle
- **ADR-026**: Secrets Management Automation (ESO integration)
- **ADR-027**: CI/CD Pipeline Automation (Tekton + ArgoCD)
- **ADR-030**: Hybrid Management Model (namespaced ArgoCD)

### Makefile Targets Reference

```bash
# Show all available targets
make help

# Show deployment workflow
make deployment-help

# Pattern deployment
make operator-deploy              # Full deployment (prereqs + helm)
make operator-deploy-only         # Skip prereqs, helm only
make install                      # Deploy + load secrets

# Validation
make validate-prereq              # Validate prerequisites
make validate-cluster             # Validate cluster
make validate-origin              # Validate git access
make argo-healthcheck             # Check ArgoCD apps

# Secrets
make load-secrets                 # Load secrets (ESO)
make setup-eso-secrets            # Setup ESO secrets
make load-env-secrets             # Load from .env (source secrets)

# Cleanup
make uninstall                    # Uninstall pattern

# EE Management
make build-ee                     # Build execution environment
make test-ee                      # Test EE
make clean-ee                     # Clean EE
```

---

## Summary

✅ **Migration Complete**: Makefile now uses standard `operator-deploy` workflow
✅ **Framework Aligned**: Follows validated-patterns-ansible-toolkit best practices
✅ **Backward Compatible**: Ansible prerequisites still used via `operator-deploy-prereqs`
✅ **Better Maintainability**: Leverages common/ subtree scripts
✅ **Production Ready**: Uses Validated Patterns Operator for GitOps

**Next Steps**: Update any CI/CD pipelines or documentation referencing `end2end-deployment` to use `operator-deploy`.
