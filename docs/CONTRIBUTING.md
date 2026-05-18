# Contributing to openshift-aiops-platform

Thank you for your interest in contributing to the OpenShift AIOps Self-Healing Platform.
This guide covers everything you need to get started: branching conventions, DCO requirements,
Helm development setup, and the PR checklist.

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/).
By participating, you agree to uphold a welcoming, respectful environment.

---

## Developer Certificate of Origin (DCO)

All commits **must** be signed off to certify you wrote the code or have the right to
contribute it:

```bash
git commit -s -m "feat: your change description"
# Appends: Signed-off-by: Your Name <your@email.com>
```

Configure Git author to match your DCO identity:
```bash
git config user.name  "Your Name"
git config user.email "your@email.com"
```

---

## Getting Started

### Prerequisites

| Tool | Minimum Version | Notes |
|------|----------------|-------|
| OpenShift CLI (`oc`) | 4.18+ | For local cluster testing |
| Helm | 3.14+ | Chart development |
| Python | 3.11+ | Notebook and script work |
| `pre-commit` | 3.x | Lint hooks |
| `ansible-core` | 2.15+ | Bootstrap automation |
| Go | 1.24+ | If touching CE or MCP client |

### Setup

```bash
git clone https://github.com/KubeHeal/openshift-aiops-platform.git
cd openshift-aiops-platform

# Install pre-commit hooks
pip install pre-commit
pre-commit install

# Validate Helm charts
helm lint charts/openshift-aiops-platform

# Copy and populate values templates
cp values-global.yaml.template values-global.yaml
cp values-secret.yaml.template values-secret.yaml
```

---

## Branch Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feat/<short-description>` | `feat/cpu-throttle-rule` |
| Bug fix | `fix/<short-description>` | `fix/notebook-test-paths` |
| Documentation | `docs/<short-description>` | `docs/add-contributing` |
| Chore / CI | `chore/<short-description>` | `chore/bump-helm-version` |
| Hotfix | `hotfix/<version>-<description>` | `hotfix/1.0.1-kserve-race` |
| Release | `release/<version>` | `release/1.1.0` |

---

## Making Changes

### Helm Charts

1. Edit charts under `charts/openshift-aiops-platform/`
2. Validate before committing:
   ```bash
   helm lint charts/openshift-aiops-platform
   helm template charts/openshift-aiops-platform --debug > /dev/null
   ```
3. If adding a new subchart, update `Chart.yaml` `dependencies:` and run `helm dependency update`

### Notebooks

Jupyter notebooks live under `notebooks/`. Keep notebooks clean before committing:

```bash
jupyter nbconvert --ClearOutputPreprocessor.enabled=True --inplace notebooks/**/*.ipynb
```

### ADRs

Significant decisions require an ADR in `docs/adrs/`. Use the next available number and
follow the existing format. Update `docs/adrs/README.md` to include the new entry in the
index table.

### Values Files

- **Never** commit `values-global.yaml` or `values-secret.yaml` with real credentials
- Always commit only `*.yaml.template` or `*.yaml.example` variants
- The `.gitignore` is pre-configured to block `values-global.yaml` and `values-secret.yaml`

---

## Pull Request Process

1. **Open an issue first** (or reference an existing one) so the change scope is agreed on before you invest significant time
2. Fork the repo and create a branch following the naming conventions above
3. Make your changes with DCO-signed commits
4. Ensure all checks pass locally:
   ```bash
   pre-commit run --all-files
   helm lint charts/openshift-aiops-platform
   ```
5. Open a PR against `main` with:
   - A clear title (imperative mood: "Add ...", "Fix ...", "Update ...")
   - A description covering **what** changed and **why**
   - References to related issues: `Closes #<number>` or `References #<number>`
   - Evidence of local testing (deployment output, screenshot, or CI run link)

### PR Checklist

- [ ] DCO sign-off on all commits (`git commit -s`)
- [ ] `helm lint` passes
- [ ] `pre-commit run --all-files` passes (no linting errors)
- [ ] New ADR added if a significant architecture decision was made
- [ ] `CHANGELOG.md` `[Unreleased]` section updated
- [ ] Notebook outputs cleared before commit
- [ ] No plaintext secrets in any committed file

---

## Reporting Bugs

Open an issue using the **Bug Report** template. Include:

- OpenShift version and cluster topology (HA or SNO)
- OpenShift AI / RHOAI version
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs or error messages

---

## Proposing New Features

Open an issue using the **Feature Request** template or start a discussion. For larger
changes, draft an ADR first and share it in the issue before writing code.

---

## Related Documentation

- [RELEASE.md](./RELEASE.md) — release process and VP submission checklist
- [CHANGELOG.md](./CHANGELOG.md) — version history
- [docs/adrs/](./docs/adrs/) — Architectural Decision Records
- [AGENTS.md](./AGENTS.md) — AI agent development guide
- [DEPLOYMENT.md](./DEPLOYMENT.md) — deployment guide
