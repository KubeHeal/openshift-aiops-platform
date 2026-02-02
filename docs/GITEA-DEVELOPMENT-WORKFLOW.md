# Gitea Development Workflow

**Date:** 2025-11-02
**Purpose:** Quick reference for using Gitea in development

---

## Quick Access

**Gitea Web UI**: https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com

**Credentials**:
- Admin: `opentlc-mgr` / `pQF1QnP8pf3AzkoXY5wlm0C5XhzoHxaw`
- Lab User: `lab-user-0` / `VyyBum5vYrW95jgR`

**Repository**: `opentlc-mgr/openshift-aiops-platform`

---

## Git Commands

### Push Changes to Gitea (Development)
```bash
# Commit your changes
git add .
git commit -m "Your commit message"

# Push to Gitea
git push gitea main
```

### Push Changes to GitHub (Upstream)
```bash
# Push to GitHub
git push origin main
```

### Pull Latest Changes
```bash
# From Gitea
git pull gitea main

# From GitHub
git pull origin main
```

### Check Remotes
```bash
git remote -v
```

---

## Why Use Gitea for Development?

1. **Local Testing**: Test GitOps workflows without affecting upstream
2. **Air-Gapped Development**: Works in disconnected environments
3. **Faster Iteration**: No external network latency
4. **Safe Experimentation**: Test ArgoCD sync without production impact
5. **Validated Patterns Compliance**: Follows framework best practices

---

## ArgoCD Integration

### Configure ArgoCD to Use Gitea

1. **Create Repository Secret**:
```bash
oc create secret generic gitea-repo-secret \
  -n openshift-gitops \
  --from-literal=url=https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/opentlc-mgr/openshift-aiops-platform.git \
  --from-literal=username=opentlc-mgr \
  --from-literal=password=pQF1QnP8pf3AzkoXY5wlm0C5XhzoHxaw

oc label secret gitea-repo-secret \
  -n openshift-gitops \
  argocd.argoproj.io/secret-type=repository
```

2. **Update Application to Use Gitea**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: self-healing-platform
  namespace: openshift-gitops
spec:
  source:
    repoURL: https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/opentlc-mgr/openshift-aiops-platform.git
    targetRevision: main
    path: charts/hub
```

3. **Sync Application**:
```bash
# Via CLI
argocd app sync self-healing-platform

# Via Web UI
# Navigate to ArgoCD UI and click "Sync"
```

---

## Webhook Configuration

### Configure Gitea Webhook for Tekton

1. **Get EventListener URL**:
```bash
oc get route -n self-healing-platform | grep el-
```

2. **Add Webhook in Gitea**:
   - Navigate to: Repository → Settings → Webhooks
   - Click "Add Webhook" → "Gitea"
   - Payload URL: `<EventListener-URL>`
   - Content Type: `application/json`
   - Secret: (from webhook secret)
   - Events: "Push events"
   - Active: ✓

3. **Test Webhook**:
```bash
# Make a commit and push
git commit --allow-empty -m "Test webhook"
git push gitea main

# Check Tekton PipelineRun
oc get pipelinerun -n self-healing-platform
```

---

## Development Workflow

### Standard Development Cycle

1. **Make Changes Locally**:
```bash
# Edit files
vim charts/hub/values.yaml

# Test locally
make install
```

2. **Commit and Push to Gitea**:
```bash
git add .
git commit -m "Update values configuration"
git push gitea main
```

3. **Verify ArgoCD Sync**:
```bash
# Check sync status
oc get application self-healing-platform -n openshift-gitops

# Watch sync progress
argocd app watch self-healing-platform
```

4. **Validate Deployment**:
```bash
# Check resources
oc get all -n self-healing-platform

# Check logs
oc logs -f deployment/<deployment-name> -n self-healing-platform
```

5. **Push to GitHub (when ready)**:
```bash
git push origin main
```

---

## Switching Between Gitea and GitHub

### Use Gitea for Development
```bash
# Update ArgoCD Application
oc patch application self-healing-platform \
  -n openshift-gitops \
  --type merge \
  -p '{"spec":{"source":{"repoURL":"https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/opentlc-mgr/openshift-aiops-platform.git"}}}'
```

### Use GitHub for Production
```bash
# Update ArgoCD Application
oc patch application self-healing-platform \
  -n openshift-gitops \
  --type merge \
  -p '{"spec":{"source":{"repoURL":"https://github.com/KubeHeal/openshift-aiops-platform.git"}}}'
```

---

## Troubleshooting

### Cannot Push to Gitea

**Error**: `Authentication failed`

**Solution**:
```bash
# Re-add remote with credentials
git remote remove gitea
git remote add gitea https://opentlc-mgr:pQF1QnP8pf3AzkoXY5wlm0C5XhzoHxaw@gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/opentlc-mgr/openshift-aiops-platform.git
```

### ArgoCD Cannot Access Gitea

**Error**: `Repository not found`

**Solution**:
```bash
# Verify repository secret
oc get secret gitea-repo-secret -n openshift-gitops -o yaml

# Recreate if needed
oc delete secret gitea-repo-secret -n openshift-gitops
# Then recreate using commands above
```

### Gitea Web UI Not Accessible

**Error**: `Connection refused`

**Solution**:
```bash
# Check Gitea pods
oc get pods -n gitea

# Check route
oc get route -n gitea

# Restart Gitea if needed
oc rollout restart deployment gitea-with-admin -n gitea
```

---

## Best Practices

1. **Always Test in Gitea First**: Push to Gitea, verify ArgoCD sync, then push to GitHub
2. **Use Descriptive Commit Messages**: Helps track changes in both repositories
3. **Keep Gitea and GitHub in Sync**: Regularly push to both remotes
4. **Use Branches for Features**: Create feature branches for major changes
5. **Tag Releases**: Tag stable versions in both repositories

---

## References

- [Gitea Documentation](https://docs.gitea.io/)
- [ArgoCD Repository Credentials](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/)
- [Validated Patterns Gitea Integration](https://validatedpatterns.io/learn/gitops/)
- [ADR-028: Gitea for Local Development](adrs/028-gitea-local-development.md)

---

*This workflow enables rapid development and testing using local Gitea while maintaining GitHub as the upstream source of truth.*
