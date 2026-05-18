# Documentation Directory

This directory contains all documentation served by MkDocs at https://kubeheal.github.io/openshift-aiops-platform/

## Duplicated Root Files

The following files are **copies** of root-level files, duplicated here because MkDocs only serves files from the `docs/` directory:

- `README.md` → Copy of `../README.md`
- `DEPLOYMENT.md` → Copy of `../DEPLOYMENT.md`
- `CONTRIBUTING.md` → Copy of `../CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md` → Copy of `../CODE_OF_CONDUCT.md`
- `AGENTS.md` → Copy of `../AGENTS.md`

**IMPORTANT**: The **root files are the source of truth**. When you update these files, they are **automatically synced** to docs/ by a GitHub Actions workflow.

### Automatic Sync (Recommended)

Just edit the root file and commit - the sync happens automatically:

```bash
# 1. Edit the root file
vi ../README.md

# 2. Commit (sync happens automatically via GitHub Actions)
git add ../README.md
git commit -s -m "docs: Update README"
git push origin main

# 3. GitHub Actions automatically:
#    - Copies ../README.md to docs/README.md
#    - Commits the synced file
#    - Triggers documentation deployment
```

**Workflow**: `.github/workflows/sync-docs.yml`

### Manual Sync (Alternative)

If you prefer to sync manually or need immediate local testing:

```bash
# 1. Edit the root file
vi ../README.md

# 2. Run sync script
../scripts/sync-docs.sh

# 3. Commit both files
git add ../README.md docs/README.md
git commit -s -m "docs: Update README"
git push origin main
```

**Why this duplication?** MkDocs design requires all documentation to be within the `docs_dir` (which is `docs/` in our case). We cannot use the repository root as `docs_dir` because it would include all non-documentation files and cause build errors.

## How Automatic Sync Works

```
┌─────────────────────────────────────────────────────────────────┐
│ Developer Updates Root File                                      │
│                                                                   │
│  $ vim README.md                                                 │
│  $ git add README.md                                             │
│  $ git commit -m "docs: Update README"                           │
│  $ git push origin main                                          │
└──────────────────────┬────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│ GitHub Actions: sync-docs.yml (Automatic)                        │
│                                                                   │
│  Triggered by: Changes to README.md, DEPLOYMENT.md, etc.        │
│                                                                   │
│  Actions:                                                        │
│   1. cp README.md docs/README.md                                │
│   2. git commit -m "docs: Auto-sync root files to docs/"        │
│   3. git push origin main                                        │
└──────────────────────┬────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│ GitHub Actions: deploy-docs.yml (Automatic)                      │
│                                                                   │
│  Triggered by: Changes to docs/**                               │
│                                                                   │
│  Actions:                                                        │
│   1. pip install -r requirements-docs.txt                        │
│   2. mkdocs build                                                │
│   3. mkdocs gh-deploy --force (pushes to gh-pages branch)       │
└──────────────────────┬────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│ GitHub Pages: Site Updated                                       │
│                                                                   │
│  https://kubeheal.github.io/openshift-aiops-platform/           │
│                                                                   │
│  Updated files visible within 1-2 minutes                        │
└─────────────────────────────────────────────────────────────────┘
```

**Timeline**: Root file update → Auto-sync (30s) → Deploy (2 min) → Live (1 min) = **~3-4 minutes total**

## Directory Structure

```
docs/
├── index.md                    # Documentation homepage
├── README.md                   # Copy of root README
├── DEPLOYMENT.md               # Copy of root DEPLOYMENT
├── CONTRIBUTING.md             # Copy of root CONTRIBUTING
├── CODE_OF_CONDUCT.md          # Copy of root CODE_OF_CONDUCT
├── AGENTS.md                   # Copy of root AGENTS guide
├── tutorials/                  # Diataxis: Learning-oriented guides
├── how-to/                     # Diataxis: Problem-solving guides
├── reference/                  # Diataxis: Information-oriented docs
├── explanation/                # Diataxis: Understanding-oriented docs
├── adrs/                       # Architectural Decision Records
├── guides/                     # Comprehensive deployment/troubleshooting guides
└── blog/                       # Blog posts and announcements
```

## Updating Documentation

### For Tutorials, How-To Guides, Reference, Explanation

Edit files directly in their respective directories. No duplication needed.

### For Root-Level Files

```bash
# 1. Edit the root file
vi ../README.md

# 2. Copy to docs/
cp ../README.md docs/README.md

# 3. Test locally
mkdocs serve

# 4. Commit both
git add ../README.md docs/README.md
git commit -s -m "docs: Update README"
git push origin main
```

### Automation Option

Consider adding a pre-commit hook or script to keep these in sync:

```bash
#!/bin/bash
# scripts/sync-docs.sh
cp README.md docs/README.md
cp DEPLOYMENT.md docs/DEPLOYMENT.md
cp CONTRIBUTING.md docs/CONTRIBUTING.md
cp CODE_OF_CONDUCT.md docs/CODE_OF_CONDUCT.md
cp AGENTS.md docs/AGENTS.md
echo "✅ Root files synced to docs/"
```

## Building Locally

```bash
# Install dependencies
pip install -r requirements-docs.txt

# Build documentation
mkdocs build

# Serve locally (with live reload)
mkdocs serve
# Open http://127.0.0.1:8000

# Check for broken links
find docs -name "*.md" -exec markdown-link-check {} \;
```

## Navigation Configuration

Navigation is defined in `mkdocs.yml`. When adding new pages:

1. Create the markdown file in the appropriate directory
2. Add it to the `nav:` section in `mkdocs.yml`
3. Use paths **relative to docs/** (no `docs/` prefix in nav)

Example:
```yaml
nav:
  - Tutorials:
      - My New Tutorial: tutorials/my-new-tutorial.md  # ✅ Correct
      # - My New Tutorial: docs/tutorials/my-new-tutorial.md  # ❌ Wrong
```

## Deployment

Documentation deploys automatically via GitHub Actions when changes are pushed to `main`:

- Workflow: `.github/workflows/deploy-docs.yml`
- Trigger: Changes to `docs/**`, `mkdocs.yml`, or root markdown files
- Build: `mkdocs build`
- Deploy: `mkdocs gh-deploy --force` (pushes to `gh-pages` branch)
- Live site: https://kubeheal.github.io/openshift-aiops-platform/

## Troubleshooting

### Navigation links return 404

**Cause**: File referenced in `mkdocs.yml` nav doesn't exist in docs/ directory.

**Fix**: Ensure the file exists and the path in nav is correct (no `docs/` prefix).

### Build fails with "docs_dir cannot be parent directory"

**Cause**: Attempting to set `docs_dir: .` (repository root).

**Fix**: Keep `docs_dir: docs` (default). Copy root files into docs/ instead.

### Links to notebooks/code don't work

**Cause**: Files outside docs/ are not included in the build.

**Fix**: Link to the GitHub repository instead:
```markdown
[View notebook](https://github.com/KubeHeal/openshift-aiops-platform/blob/main/notebooks/...)
```

## Related Files

- `mkdocs.yml` - MkDocs configuration
- `requirements-docs.txt` - Python dependencies for building docs
- `.github/workflows/deploy-docs.yml` - Automated deployment
- `.github/workflows/validate-docs.yml` - Link validation on PRs
