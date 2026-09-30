# Documentation Directory

This directory contains all documentation served by MkDocs at https://kubeheal.github.io/openshift-aiops-platform/

## Homepage

The MkDocs homepage is **`index.md`** (not `README.md`). The index page provides persona-based onboarding for platform engineers, developers, and data scientists, with links to all documentation sections.

## Synced Root Files

The following root-level files are copied into `docs/` because MkDocs only serves files from the `docs/` directory:

| Root File | Synced To | Purpose |
|-----------|-----------|---------|
| `../DEPLOYMENT.md` | `docs/how-to/DEPLOYMENT.md` | Deployment instructions |

**Files that are NOT synced** (they live only in their subdirectories):
- `CONTRIBUTING.md` lives at `docs/reference/CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md` lives at `docs/reference/CODE_OF_CONDUCT.md`
- `AGENTS.md` lives at `docs/explanation/AGENTS.md`

The root `README.md` is the authoritative project overview. The `docs/README.md` file is a short pointer to `index.md` and is not synced from root.

### Automatic Sync

Edit the root file and commit. GitHub Actions handles the rest:

```bash
# 1. Edit the root file
vi ../DEPLOYMENT.md

# 2. Commit (sync happens automatically via GitHub Actions)
git add ../DEPLOYMENT.md
git commit -s -m "docs: update deployment guide"
git push origin main

# 3. GitHub Actions automatically:
#    - Copies DEPLOYMENT.md to docs/how-to/DEPLOYMENT.md
#    - Commits the synced file
#    - Triggers documentation deployment
```

**Workflow**: `.github/workflows/sync-docs.yml`

### Manual Sync

```bash
# Run sync script
../scripts/sync-docs.sh

# Commit
git add docs/
git commit -s -m "docs: sync root files to docs/"
git push origin main
```

## Directory Structure

The documentation follows the [Diataxis](https://diataxis.fr/) framework:

```
docs/
├── index.md                    # Documentation homepage (MkDocs home)
├── README.md                   # Pointer to index.md (for GitHub browsing)
├── README-DOCS.md              # This file (meta-documentation)
├── mkdocs.yml                  # (STALE - use root mkdocs.yml instead)
├── requirements.txt            # MkDocs Python dependencies
│
├── user-guide/                 # Role-based guides (engineers, devs, data scientists)
├── tutorials/                  # Diataxis: Learning-oriented step-by-step guides
├── how-to/                     # Diataxis: Task-oriented deployment guides
├── guides/                     # Procedural guides (migrations, integrations)
├── reference/                  # Diataxis: Configuration, checklists, community docs
├── explanation/                # Diataxis: Architecture explanations, design rationale
├── troubleshooting/            # Problem/solution diagnostics
├── runbooks/                   # Operational procedures for day-2 management
├── diagrams/                   # Mermaid architecture and workflow diagrams
├── adrs/                       # Architectural Decision Records (58+ ADRs)
├── research/                   # Roadmaps, enhancement proposals, plans
├── github-issues/              # Bug reports and feature request tracking
├── issues/                     # Known issues and workarounds
├── blog/                       # Blog posts and announcements
└── assets/                     # Branding, images
```

## Updating Documentation

### For Tutorials, How-To Guides, Reference, Explanation

Edit files directly in their respective directories. No duplication is needed.

### For Root-Level Files (DEPLOYMENT.md)

```bash
# 1. Edit the root file
vi ../DEPLOYMENT.md

# 2. Run sync script (or let GitHub Actions handle it)
../scripts/sync-docs.sh

# 3. Test locally
mkdocs serve

# 4. Commit
git add ../DEPLOYMENT.md docs/how-to/DEPLOYMENT.md
git commit -s -m "docs: update deployment guide"
git push origin main
```

## Building Locally

```bash
# Install dependencies
pip install -r requirements.txt

# Serve locally (with live reload)
mkdocs serve
# Open http://127.0.0.1:8000

# Build static site
mkdocs build
```

## Navigation Configuration

Navigation is defined in the **root** `mkdocs.yml` (not `docs/mkdocs.yml`). When adding new pages:

1. Create the markdown file in the appropriate directory
2. Add it to the `nav:` section in the root `mkdocs.yml`
3. Use paths **relative to docs/** (no `docs/` prefix in nav)

Example:
```yaml
nav:
  - Tutorials:
      - My New Tutorial: tutorials/my-new-tutorial.md  # Correct
      # - My New Tutorial: docs/tutorials/my-new-tutorial.md  # Wrong
```

## Deployment

Documentation deploys automatically via GitHub Actions when changes are pushed to `main`:

- Workflow: `.github/workflows/deploy-docs.yml`
- Trigger: Changes to `docs/**`, `mkdocs.yml`, or root markdown files
- Build: `mkdocs build`
- Deploy: `mkdocs gh-deploy --force` (pushes to `gh-pages` branch)
- Live site: https://kubeheal.github.io/openshift-aiops-platform/

## Related Files

- `../mkdocs.yml` - MkDocs configuration (the authoritative config)
- `requirements.txt` - Python dependencies for building docs
- `../.github/workflows/deploy-docs.yml` - Automated deployment
- `../.github/workflows/sync-docs.yml` - Root file sync automation
- `../scripts/sync-docs.sh` - Manual sync script
