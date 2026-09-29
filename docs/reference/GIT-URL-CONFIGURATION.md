# Git Repository URL Configuration Guide

This guide explains how to configure the Git repository URL when deploying to different clusters or switching between Gitea (development) and GitHub (production).

## Single Source of Truth

The Git repository URL is configured in **`values-global.yaml`**:

```yaml
# values-global.yaml
git:
  # Git repository URL - SINGLE SOURCE OF TRUTH
  repoURL: "https://gitea-with-admin-gitea.apps.<cluster-domain>/<org>/<repo>.git"
  revision: "main"
```

## Quick Configuration

### For Gitea (Development/Testing)

```bash
# Format: https://gitea-with-admin-gitea.apps.<cluster-domain>/<org>/<repo>.git

# Example for cluster fn2qb:
git.repoURL: "https://gitea-with-admin-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/opentlc-mgr/openshift-aiops-platform.git"
```

### For GitHub (Production)

```bash
# Format: https://github.com/<org>/<repo>.git

git.repoURL: "https://github.com/KubeHeal/openshift-aiops-platform.git"
```

## Where the Value is Used

The `git.repoURL` from `values-global.yaml` is used by:

| Component | File | Usage |
|-----------|------|-------|
| ArgoCD Applications | `charts/hub/argocd-application.yaml` | Source repository |
| Notebook Validation | `charts/hub/templates/notebook-validation-jobs.yaml` | Git clone for validation |
| Image Builds | `charts/hub/templates/*.yaml` | BuildConfig source |
| Tekton Pipelines | `charts/hub/templates/notebook-validator-tekton.yaml` | Pipeline git-clone |

## Changing the URL

### Option 1: Edit values-global.yaml

```bash
# Edit the file
vim values-global.yaml

# Change this line:
git:
  repoURL: "https://github.com/your-org/openshift-aiops-platform.git"
  revision: "main"

# Commit and push
git add values-global.yaml
git commit -m "chore: update git URL for production"
git push
```

### Option 2: Override via Helm

```bash
# During Helm install/upgrade
helm upgrade self-healing-platform charts/hub \
  --set global.git.repoURL="https://github.com/your-org/openshift-aiops-platform.git" \
  --set global.git.revision="main"
```

### Option 3: ArgoCD Application Override

```yaml
# In your ArgoCD Application
spec:
  source:
    helm:
      parameters:
      - name: global.git.repoURL
        value: "https://github.com/your-org/openshift-aiops-platform.git"
```

## Migration Checklist

When migrating from Gitea to GitHub:

- [ ] Update `values-global.yaml` with new `git.repoURL`
- [ ] Ensure GitHub repository exists and is accessible
- [ ] Push all changes to GitHub
- [ ] Update ArgoCD to point to GitHub (if using direct ArgoCD management)
- [ ] Update any webhooks for CI/CD
- [ ] Verify notebook validation jobs can clone from new URL

## Files with Hardcoded URLs (Documentation Only)

These files contain Gitea URLs for **documentation purposes only** and don't need to be updated for deployment:

- `docs/*.md` - Documentation references
- `CLAUDE.md` - AI assistant context
- `*-SUMMARY.md` - Implementation summaries

## Cluster Domain Detection

For Gitea URLs, the cluster domain can be detected automatically:

```bash
# Get cluster domain
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
echo "Cluster domain: $CLUSTER_DOMAIN"

# Construct Gitea URL
GITEA_URL="https://gitea-with-admin-gitea.${CLUSTER_DOMAIN}/opentlc-mgr/openshift-aiops-platform.git"
echo "Gitea URL: $GITEA_URL"
```

## Troubleshooting

### ArgoCD Can't Clone Repository

```bash
# Check ArgoCD repository configuration
argocd repo list

# Add repository with credentials
argocd repo add https://github.com/your-org/openshift-aiops-platform.git \
  --username <username> \
  --password <token>
```

### Notebook Validation Jobs Failing

```bash
# Check if git clone works from within cluster
oc run git-test --rm -it --image=alpine/git -- \
  git clone https://github.com/your-org/openshift-aiops-platform.git /tmp/repo
```

### BuildConfig Source Errors

```bash
# Check BuildConfig source
oc get bc -n self-healing-platform -o yaml | grep -A5 "source:"
```

## Related Documentation

- [Validated Patterns Git Configuration](https://validatedpatterns.io/patterns/getting-started/)
- [ArgoCD Repository Management](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/)
- [ADR-028: Gitea Local Git Repository](adrs/028-gitea-local-git-repository.md)
