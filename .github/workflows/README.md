# Documentation Automation Workflows

This directory contains GitHub Actions workflows for automated documentation validation and maintenance.

## Workflows Overview

### 1. Documentation Link Checker (`docs-link-checker.yml`)

**Trigger**: On PR or push to `main` affecting markdown files

**What it does**:
- ✅ Validates all internal markdown links
- ✅ Checks mkdocs.yml navigation references
- ✅ Builds documentation in strict mode
- ✅ Comments on PRs with results

**Use case**: Catch broken links before merging documentation changes

---

### 2. Version Consistency Checker (`docs-version-checker.yml`)

**Trigger**: On PR or push to `main` affecting documentation

**What it does**:
- ✅ Validates OpenShift version references (4.19+, not 4.18 without maintenance notice)
- ✅ Checks operator versions against `docs/reference/operator-versions.md`
- ✅ Validates version format (X.Y or X.Y.Z)
- ✅ Comments on PRs if inconsistencies found

**Use case**: Ensure all documentation references current supported versions

**Expected versions** (as of 2026-05-19):
- OpenShift: 4.19+ (4.21 recommended; 4.18 maintenance-only)
- GitOps: 1.20.3+
- Pipelines: 1.22.0+
- ODF: 4.20+
- External Secrets: 1.1.0+

---

### 3. ADR Status Checker (`docs-adr-status-checker.yml`)

**Trigger**: On PR affecting ADRs, weekly schedule (Mondays 9 AM UTC)

**What it does**:
- ✅ Validates deprecated ADRs have proper banners
- ✅ Checks deprecated ADRs link to replacements
- ✅ Verifies all ADRs are in `docs/adrs/README.md` index
- ✅ Validates ADR numbering sequence
- ✅ Checks for duplicate ADR numbers
- ✅ Validates ADR status fields (Proposed, Accepted, Deprecated, Superseded, Draft)
- ✅ Generates weekly ADR status report

**Use case**: Maintain ADR quality and consistency

**Deprecation format**:
```markdown
> **⚠️ DEPRECATED**: This ADR describes a superseded approach. See [ADR-XXX](./XXX-new-approach.md) for the current implementation.
```

---

### 4. Documentation Freshness Checker (`docs-freshness-checker.yml`)

**Trigger**: Monthly schedule (1st of month, 9 AM UTC), manual dispatch

**What it does**:
- ✅ Identifies stale documentation (>180 days since last git commit)
- ✅ Flags very stale documentation (>365 days)
- ✅ Checks for missing "Last Updated" metadata
- ✅ Generates freshness metrics (freshness score percentage)
- ✅ Creates GitHub issue for stale documentation
- ✅ Uploads freshness report artifact

**Use case**: Proactively identify documentation needing review

**Staleness thresholds**:
- Fresh: < 90 days
- Recent: 90-180 days
- Stale: 180-365 days
- Very Stale: > 365 days

**Manual dispatch**:
```bash
# From GitHub UI: Actions > Documentation Freshness Checker > Run workflow
# Set custom threshold (default: 180 days)
```

---

### 5. Auto-Generate Documentation (`docs-auto-generate.yml`)

**Trigger**: On PR or push affecting values YAML files, manual dispatch

**What it does**:
- ✅ Auto-generates configuration reference from `values-global.yaml.example` and `values-hub.yaml.example`
- ✅ Extracts parameters, defaults, and comments
- ✅ Generates markdown tables with type inference
- ✅ Creates `docs/reference/auto-generated-config.md`
- ✅ Comments on PRs with preview
- ✅ Auto-commits changes on merge to `main`

**Use case**: Keep configuration documentation synchronized with values files

**Generated file**: `docs/reference/auto-generated-config.md` (auto-generated, do not edit manually)

---

## Workflow Triggers Summary

| Workflow | PR | Push (main) | Schedule | Manual |
|----------|----|-----------|-----------|---------||
| Link Checker | ✅ | ✅ | ❌ | ✅ |
| Version Checker | ✅ | ✅ | ❌ | ✅ |
| ADR Status Checker | ✅ | ✅ | ✅ Weekly (Mon 9am UTC) | ✅ |
| Freshness Checker | ❌ | ❌ | ✅ Monthly (1st 9am UTC) | ✅ |
| Auto-Generate | ✅ | ✅ | ❌ | ✅ |

---

## Manual Workflow Execution

All workflows support manual dispatch via GitHub UI:

1. Go to **Actions** tab
2. Select workflow from left sidebar
3. Click **Run workflow** button
4. Select branch and optional inputs
5. Click **Run workflow**

---

## Workflow Artifacts

Some workflows upload artifacts for later review:

| Workflow | Artifact Name | Retention | Description |
|----------|---------------|-----------|-------------|
| Freshness Checker | `freshness-report` | 90 days | Monthly freshness report markdown |
| Auto-Generate | `auto-generated-config-docs` | 30 days | Generated configuration documentation |

**Download artifacts**:
1. Go to **Actions** tab
2. Click on workflow run
3. Scroll to **Artifacts** section
4. Click artifact name to download

---

## Troubleshooting

### Link Checker Failing

**Symptom**: Workflow reports broken links

**Fix**:
1. Review workflow log for specific broken links
2. Update links or create missing files
3. Verify mkdocs.yml navigation references

### Version Checker Failing

**Symptom**: Workflow reports version inconsistencies

**Fix**:
1. Update OpenShift references to 4.19+ (4.21 recommended)
2. Sync operator versions with `docs/reference/operator-versions.md`
3. Ensure version format is X.Y or X.Y.Z

### ADR Status Checker Failing

**Symptom**: Workflow reports ADR issues

**Fix**:
1. Add deprecation banner to deprecated ADRs
2. Link deprecated ADRs to replacements
3. Update `docs/adrs/README.md` index
4. Validate status field is one of: Proposed, Accepted, Deprecated, Superseded, Draft

### Freshness Checker Creating Too Many Issues

**Symptom**: Monthly issue flagging many stale docs

**Action**:
1. Review and update flagged documentation
2. Add "Last Updated" metadata to key docs
3. Archive or delete truly outdated content
4. Adjust threshold in manual dispatch if needed

### Auto-Generate Not Committing

**Symptom**: Generated docs not committed to main

**Fix**:
1. Verify workflow has write permissions (Settings > Actions > General > Workflow permissions)
2. Check workflow log for commit errors
3. Ensure values YAML files have proper comments

---

## Workflow Permissions

All workflows require the following permissions:

- **Read**: Repository contents
- **Write**: Issues (for creating reports), Pull requests (for comments), Contents (for auto-commits on `docs-auto-generate.yml`)

**Configure** in repository Settings > Actions > General > Workflow permissions:
- ✅ Read and write permissions
- ✅ Allow GitHub Actions to create and approve pull requests (optional)

---

## Maintenance

### Updating Workflows

When modifying workflows:

1. Test locally with `act` (GitHub Actions local runner) if possible
2. Test on feature branch before merging to main
3. Update this README if behavior changes
4. Increment workflow version in comments if major changes

### Adding New Workflows

When adding new documentation workflows:

1. Create workflow file in `.github/workflows/`
2. Follow naming convention: `docs-<purpose>.yml`
3. Add documentation to this README
4. Test thoroughly on feature branch
5. Update workflow triggers summary table

---

## Related Documentation

- [Documentation Automation Plan](../../docs/DOCUMENTATION-AUTOMATION-PLAN.md) - Complete automation strategy
- [Configuration Reference](../../docs/reference/configuration-reference.md) - Manual configuration guide
- [ADR Index](../../docs/adrs/README.md) - Architectural Decision Records index

---

**Last Updated**: 2026-05-19
**Maintained By**: Platform Engineering Team
