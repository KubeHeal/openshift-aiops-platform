# Release Guide — openshift-aiops-platform

This document covers the Helm chart release process, the Validated Patterns (VP) submission
checklist, and the branch/versioning standards for the OpenShift AIOps Self-Healing Platform.

---

## Versioning Policy

The platform uses **Semantic Versioning** (`MAJOR.MINOR.PATCH`) aligned with the overall
KubeHeal suite release train:

| Increment | When |
|-----------|------|
| **MAJOR** | Breaking changes to `values-hub.yaml` schema, Helm chart API, or GitOps structure |
| **MINOR** | New AIOps capabilities, new Helm subcharts, new ADRs implemented |
| **PATCH** | Bug fixes, image tag bumps, documentation corrections |

### OpenShift Compatibility Matrix

| OCP Version | Kubernetes | RHOAI Version | Status |
|-------------|------------|---------------|--------|
| 4.20        | 1.33       | 2.19+         | Active |
| 4.19        | 1.32       | 2.18+         | Active |
| 4.18        | 1.31       | 2.17+         | Maintenance |

---

## Branch Strategy

```
main          ← integration branch (branch protection required — see issue #49)
develop       ← feature development (optional long-running features)
release-4.18  ← OCP 4.18 train patches
release-4.19  ← OCP 4.19 train patches
release-4.20  ← OCP 4.20 train patches
```

---

## Required Checks Before Merge (Branch Protection)

All PRs targeting `main` must pass (see issue [#49](https://github.com/KubeHeal/openshift-aiops-platform/issues/49)):

| Check | Workflow | Required |
|-------|----------|----------|
| `helm-lint` | `helm-validation.yml` | ✅ |
| `helm-template` | `helm-validation.yml` | ✅ |
| `notebook-tests` | `ci.yml` | ✅ |
| `pre-commit` | `ci.yml` | ✅ |

---

## Developer Certificate of Origin (DCO)

All commits **must** include a DCO sign-off:

```bash
git commit -s -m "feat: your commit message"
# Adds: Signed-off-by: Your Name <your@email.com>
```

---

## Helm Chart Release Checklist

### 1. Pre-Release

- [ ] All issues in the target milestone are closed or moved to next milestone
- [ ] `CHANGELOG.md` `[Unreleased]` section is complete
- [ ] All ADRs for new features are in `Accepted` or `Implemented` status
- [ ] CI green on `main` — all required checks pass (issue [#49](https://github.com/KubeHeal/openshift-aiops-platform/issues/49))
- [ ] Notebook test paths correct in `ci.yml` (issue [#53](https://github.com/KubeHeal/openshift-aiops-platform/issues/53))
- [ ] All image references pinned to explicit tags in `values-hub.yaml` (issue [#51](https://github.com/KubeHeal/openshift-aiops-platform/issues/51))

### 2. Version Bump

```bash
# Bump Chart.yaml version and appVersion
VERSION=1.1.0
sed -i "s/^version:.*/version: $VERSION/" charts/openshift-aiops-platform/Chart.yaml
sed -i "s/^appVersion:.*/appVersion: \"$VERSION\"/" charts/openshift-aiops-platform/Chart.yaml

# Validate
helm lint charts/openshift-aiops-platform
helm template charts/openshift-aiops-platform | grep "image:"
```

### 3. Update CHANGELOG

Move the `[Unreleased]` section to a dated version:

```markdown
## [1.1.0] - YYYY-MM-DD
```

Commit:
```bash
git add CHANGELOG.md charts/
git commit -s -m "release: prepare v1.1.0 — bump Chart.yaml and update CHANGELOG"
```

### 4. Tag and Push

```bash
VERSION=v1.1.0
git tag -a "$VERSION" -m "Release $VERSION"
git push origin main --tags
```

### 5. GitHub Release

```bash
gh release create "$VERSION" \
  --repo KubeHeal/openshift-aiops-platform \
  --title "openshift-aiops-platform $VERSION" \
  --notes-file <(sed -n "/^## \[$VERSION\]/,/^## \[/p" CHANGELOG.md | head -n -1) \
  --draft
```

---

## Validated Patterns (VP) Submission Checklist

The platform targets VP **Sandbox** tier submission (issue [#54](https://github.com/KubeHeal/openshift-aiops-platform/issues/54)).
See [ADR-019](./docs/adrs/019-validated-patterns-framework-adoption.md) for the adoption decision.

### Pre-Submission Requirements

- [ ] `patternizer init --with-secrets` run and output committed
- [ ] `values-hub.yaml` uses `pattern.clusterGroupName` and VP secret conventions
- [ ] `common/` submodule pinned to correct VP framework commit
- [ ] VP Operator installs cleanly: `make install` or `pattern.sh make install`
- [ ] All ArgoCD `Application` resources converge to `Synced/Healthy`
- [ ] Architecture diagram added to `README.md`
- [ ] Support policy documented in `README.md` (community-supported)
- [ ] VP ADR authored and merged (covers secret management via Vault/ESO)

### Submission Steps

1. Fork `validatedpatterns/patterns-catalog`
2. Add entry under `catalog/` following VP catalog format
3. Open PR titled: `Add openshift-aiops-platform to Sandbox tier`
4. Attach CI evidence (GitHub Actions run URL)
5. Notify VP team in `#validated-patterns` Slack channel

### VP CI Requirements

| Check | Description |
|-------|-------------|
| `pattern-tests` | `make test` must pass |
| `helm-lint` | All charts must lint cleanly |
| `secrets-check` | No plaintext secrets in values files |

---

## Related Documentation

- [CHANGELOG.md](./CHANGELOG.md) — full version history
- [CONTRIBUTING.md](./CONTRIBUTING.md) — development workflow and PR standards
- [docs/adrs/](./docs/adrs/) — Architectural Decision Records (32+ ADRs)
- [DEPLOYMENT.md](./DEPLOYMENT.md) — step-by-step deployment guide
- [GitHub Issues](https://github.com/KubeHeal/openshift-aiops-platform/issues)
