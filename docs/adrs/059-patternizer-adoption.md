# ADR-059: Patternizer Adoption for Pattern Scaffolding Automation

**Status:** PROPOSED

## Status
proposed - 2026-05-15

## Context

The OpenShift AIOps Self-Healing Platform currently uses the Validated Patterns Framework (ADR-019) with **manual creation** of pattern scaffolding files:

**Current Manual Process:**
```bash
# Step 1: Manual file creation (error-prone)
cp values-global.yaml.example values-global.yaml
cp values-hub.yaml.example values-hub.yaml

# Step 2: Manual configuration editing
vi values-global.yaml  # Update repoURL, pattern name, etc.
vi values-hub.yaml     # Update cluster-specific settings

# Step 3: Manual Makefile management
# No standardized way to keep Makefile in sync with upstream common/
```

### Problems with Manual Approach

1. **Error-Prone**: Users frequently forget to update `repoURL` in both files
2. **No Standardization**: Pattern structure varies from community patterns
3. **Difficult Updates**: No automated way to upgrade to latest Validated Patterns common structure
4. **Documentation Overhead**: Extensive documentation required for setup steps
5. **Secrets Management**: Manual integration with External Secrets Operator (ADR-026)
6. **Onboarding Friction**: New users struggle with initial pattern setup

### Available Solution: Patternizer

The Validated Patterns community provides **Patternizer** ([validatedpatterns/patternizer](https://github.com/validatedpatterns/patternizer)), a CLI tool that:

- **Automatically generates** pattern scaffolding from existing Helm charts
- **Standardizes structure** using community templates
- **Runs in container** (no local installation required)
- **Supports upgrades** to keep pattern infrastructure current
- **Integrates secrets** via `--with-secrets` flag

## Decision

**Adopt Patternizer as the standard tool for pattern scaffolding generation and upgrades** in the OpenShift AIOps Self-Healing Platform.

### Implementation Strategy

#### Phase 1: Initial Patternizer Integration (Week 1)

**Update Repository Structure:**
```bash
# 1. Run Patternizer initialization
podman run --pull=newer -v "$PWD:$PWD:z" -w "$PWD" \
  quay.io/validatedpatterns/patternizer init --with-secrets

# 2. Review generated files
git status
# New/Updated files:
#   values-global.yaml
#   values-hub.yaml (from values-<cluster_group>.yaml template)
#   pattern.sh (utility wrapper)
#   Makefile (includes Makefile-common)
#   Makefile-common (core pattern logic)
#   ansible.cfg
#   values-secret.yaml.template

# 3. Commit changes
git add .
git commit -m 'feat: adopt Patternizer for pattern scaffolding'
```

**Remove Manual Examples:**
- Delete `values-global.yaml.example`
- Delete `values-hub.yaml.example`
- Update documentation to use Patternizer workflow

#### Phase 2: Documentation Update (Week 1)

**Update README.md, DEPLOYMENT.md, CLAUDE.md:**
```markdown
## Prerequisites

### 1. Fork Repository
Fork https://github.com/KubeHeal/openshift-aiops-platform to YOUR-USERNAME/openshift-aiops-platform

### 2. Initialize Pattern Scaffolding (NEW - Patternizer)
```bash
cd openshift-aiops-platform
podman run --pull=newer -v "$PWD:$PWD:z" -w "$PWD" \
  quay.io/validatedpatterns/patternizer init --with-secrets
```

### 3. Configure Values Files
```bash
# Edit generated files
vi values-global.yaml  # Update repoURL to YOUR fork
vi values-hub.yaml     # Update cluster-specific settings
vi values-secret.yaml  # Configure secrets (from template)
```

### 4. Deploy Pattern
```bash
./pattern.sh make install  # Uses pattern.sh wrapper
# OR
make operator-deploy       # Direct Makefile approach
```
```

#### Phase 3: Upgrade Workflow Documentation (Week 2)

**Document Patternizer Upgrade Process:**
```bash
# Keep pattern infrastructure up-to-date with Validated Patterns common
# Run periodically (monthly or before major releases)

# 1. Commit current state
git add .
git commit -m 'chore: pre-upgrade checkpoint'

# 2. Run Patternizer upgrade
podman run --pull=newer -v "$PWD:$PWD:z" -w "$PWD" \
  quay.io/validatedpatterns/patternizer upgrade

# 3. Review changes
git diff

# 4. Commit upgrades
git add ansible.cfg Makefile-common pattern.sh
git commit -m 'chore: upgrade pattern infrastructure via Patternizer'
```

### Integration with Existing ADRs

#### ADR-019: Validated Patterns Framework
**Enhancement**: Patternizer automates the manual scaffolding steps

**Before (Manual)**:
```bash
cp values-global.yaml.example values-global.yaml
vi values-global.yaml  # Manual editing
```

**After (Patternizer)**:
```bash
podman run ... patternizer init
vi values-global.yaml  # Edit generated file with correct defaults
```

#### ADR-026: Secrets Management Automation
**Enhancement**: `--with-secrets` flag generates `values-secret.yaml.template` with External Secrets Operator integration pre-configured

**Generated Integration:**
- `values-global.yaml` sets `global.secretLoader.disabled: false`
- `values-secret.yaml.template` provides structure for ESO secrets
- Vault and ESO automatically added to cluster group configuration

#### ADR-030: Hybrid Management Model
**No Change**: Patternizer generates standard pattern structure; hybrid RBAC deployment strategy remains unchanged

**Compatibility**: Generated `Makefile-common` includes all standard Validated Patterns targets (prerequisites, deploy, validate, cleanup)

#### ADR-055: Multi-Cluster Topology Support
**Enhancement**: Patternizer-generated structure standardizes cluster group naming

**Cluster Groups:**
- `values-hub.yaml` - Standard/HA cluster configuration
- `values-sno.yaml` - SNO-specific cluster configuration (if needed)

## Architecture

### Before Patternizer (Current State)

```
openshift-aiops-platform/
├── values-global.yaml.example       # Manual template
├── values-hub.yaml.example          # Manual template
├── Makefile                         # Custom Makefile (may diverge from common)
├── common/                          # Git subtree (manual sync required)
└── docs/how-to/                     # Extensive manual setup docs
```

**Problems:**
- Manual file creation and editing
- Makefile may diverge from Validated Patterns standards
- No automated upgrade path

### After Patternizer (Proposed State)

```
openshift-aiops-platform/
├── values-global.yaml               # Generated by Patternizer
├── values-hub.yaml                  # Generated by Patternizer
├── values-secret.yaml.template      # Generated by --with-secrets
├── pattern.sh                       # Generated utility wrapper
├── Makefile                         # Generated wrapper (includes Makefile-common)
├── Makefile-common                  # Generated core logic (upgradeable)
├── ansible.cfg                      # Generated Ansible config
├── common/                          # Git subtree (if still used)
└── docs/how-to/                     # Simplified docs (reference Patternizer)
```

**Benefits:**
- Automated scaffolding generation
- Standardized structure across Validated Patterns community
- Automated upgrade path via `patternizer upgrade`

## Consequences

### Positive

1. **Reduced Onboarding Friction**
   - Single command generates all scaffolding files
   - Users don't need to understand values file structure upfront
   - Generated templates have correct defaults

2. **Standardization**
   - Pattern structure matches community best practices
   - Consistent across all Validated Patterns
   - Easier for community contributors to understand

3. **Upgrade Path**
   - `patternizer upgrade` keeps infrastructure current
   - Automatically incorporates Validated Patterns improvements
   - Preserves custom Makefile targets

4. **Better Secrets Integration**
   - `--with-secrets` flag auto-configures ESO integration
   - Aligns with ADR-026 (External Secrets Operator)
   - Reduces manual configuration errors

5. **Container-First**
   - No local tool installation required
   - Consistent execution across environments
   - Aligns with execution environment approach (ADR-019)

6. **Documentation Simplification**
   - Less extensive setup documentation required
   - Reference Patternizer documentation for scaffolding
   - Focus documentation on platform-specific configuration

### Negative

1. **Additional Dependency**
   - Requires Podman or Docker for Patternizer execution
   - Network access to pull `quay.io/validatedpatterns/patternizer` image
   - Additional tool to learn (though simple CLI)

2. **Generated File Customization**
   - Generated files may need manual editing
   - Need to understand Patternizer output structure
   - Some fields (repoURL, pattern name) require post-generation editing

3. **Migration Effort**
   - Existing pattern needs one-time Patternizer initialization
   - Need to test upgrade workflow thoroughly
   - Documentation needs significant updates

4. **Makefile Changes**
   - Patternizer uses `Makefile` + `Makefile-common` split
   - Custom targets may need migration
   - Need to test all existing `make` targets still work

### Neutral

1. **Learning Curve**
   - Team needs to understand Patternizer workflow
   - Additional training for contributors
   - Community Patternizer documentation available

2. **Version Control**
   - Generated files committed to repository
   - Git diff shows Patternizer changes explicitly
   - Easier to track infrastructure updates

## Implementation Checklist

- [ ] Run Patternizer initialization with `--with-secrets`
- [ ] Review generated files vs. current pattern structure
- [ ] Test `pattern.sh make install` deployment workflow
- [ ] Update `values-global.yaml` with correct repoURL
- [ ] Update `values-hub.yaml` with platform-specific settings
- [ ] Migrate custom Makefile targets (if any)
- [ ] Test Patternizer upgrade workflow
- [ ] Update README.md with Patternizer workflow
- [ ] Update DEPLOYMENT.md with Patternizer steps
- [ ] Update CLAUDE.md agent quick reference
- [ ] Update docs/how-to/ guides
- [ ] Remove `values-global.yaml.example` and `values-hub.yaml.example`
- [ ] Test SNO and HA deployments with new structure
- [ ] Validate all ADR-021 Tekton pipelines still work
- [ ] Document Patternizer upgrade schedule (monthly)
- [ ] Add Patternizer upgrade to CI/CD pipeline (ADR-027)

## Related ADRs

- **ADR-019**: Validated Patterns Framework Adoption (foundation for this decision)
- **ADR-026**: Secrets Management Automation (enhanced by `--with-secrets`)
- **ADR-027**: CI/CD Pipeline Automation (Patternizer in CI/CD)
- **ADR-030**: Hybrid Management Model (unchanged, compatible)
- **ADR-055**: Multi-Cluster Topology Support (cluster group naming)

## References

- [Patternizer GitHub Repository](https://github.com/validatedpatterns/patternizer)
- [Validated Patterns OpenShift Framework](https://validatedpatterns.io/learn/vp_openshift_framework/)
- [Secrets Management in Validated Patterns](https://validatedpatterns.io/learn/secrets-management-in-the-validated-patterns-framework/)
- [Validated Patterns Common Repository](https://github.com/validatedpatterns/common)

## Timeline

- **Week 1**: Patternizer initialization, documentation updates
- **Week 2**: Upgrade workflow testing, CI/CD integration
- **Week 3**: Community testing, SNO/HA validation
- **Week 4**: Production deployment, team training

## Approval

- **Architect**: Pending
- **Platform Team**: Pending
- **Date**: 2026-05-15
