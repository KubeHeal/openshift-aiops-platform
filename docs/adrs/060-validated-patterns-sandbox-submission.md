# ADR-060: Validated Patterns Sandbox Tier Submission

**Status:** PROPOSED

## Status
proposed - 2026-05-20

## Context

The OpenShift AIOps Self-Healing Platform has successfully adopted the Validated Patterns Framework (ADR-019) and Patternizer scaffolding automation (ADR-059). The platform is now ready for submission to the Validated Patterns **Sandbox tier** to gain visibility, community support, and alignment with Red Hat's official pattern ecosystem.

### What is Validated Patterns?

Validated Patterns (https://validatedpatterns.io/) is Red Hat's official framework for deploying complex applications on OpenShift using GitOps best practices. Patterns submitted to the catalog gain:

- **Official Recognition**: Listed in the Validated Patterns catalog
- **Community Support**: Access to VP community Slack, forums, and issue tracking
- **Documentation Standards**: Alignment with VP documentation framework
- **Testing Infrastructure**: Automated testing via VP CI/CD pipelines
- **Promotion Path**: Sandbox → Maintained → Validated tiers

### Validated Patterns Tiers

| Tier | Requirements | Benefits |
|------|-------------|----------|
| **Sandbox** | Basic pattern structure, working deployment | Community visibility, catalog listing |
| **Maintained** | Active maintenance, CI passing, community engagement | Official support, regular updates |
| **Validated** | Red Hat validation, enterprise support SLA | Enterprise certification, production readiness |

### Current Platform Readiness

**✅ Already Complete**:
- Validated Patterns Framework adoption (ADR-019) ✅
- Patternizer scaffolding (`Makefile`, `pattern.sh`, `ansible.cfg`, `values-secret.yaml.template`) ✅
- `common/` submodule integrated (validatedpatterns/common) ✅
- GitOps-native deployment via OpenShift GitOps (ArgoCD) ✅
- Multi-source Helm chart support (`clustergroup-chart` 0.9.*) ✅
- Secret management via External Secrets Operator (ADR-026) ✅
- Comprehensive ADR documentation (60+ ADRs) ✅
- Production testing on SNO and HA clusters ✅

**📋 Remaining for Sandbox Submission**:
- VP submission PR to `validatedpatterns/patterns-catalog`
- CI evidence (GitHub Actions workflow runs)
- Architecture diagram in README.md (already exists)
- Support policy documentation (community-supported)

## Decision

**Submit the OpenShift AIOps Self-Healing Platform to the Validated Patterns Sandbox tier** to increase visibility, gain community support, and align with Red Hat's pattern ecosystem.

### Submission Target: Sandbox Tier

**Rationale for Sandbox**:
- Pattern is production-ready but community-maintained (not Red Hat validated)
- No enterprise SLA commitment required
- Allows community feedback and iteration
- Establishes presence in VP catalog
- Provides promotion path to Maintained → Validated tiers

### Acceptance Criteria

#### 1. Pre-Submission Checklist (from RELEASE.md)

**Pattern Infrastructure** ✅:
- [x] Patternizer scaffolding complete (`pattern.sh`, `Makefile-common`, `ansible.cfg`)
- [x] `common/` submodule added (validatedpatterns/common)
- [x] `values-secret.yaml.template` created with secret key documentation
- [x] Multi-source Helm support (`clustergroup-chart` 0.9.*)
- [x] Image tags pinned to explicit versions (Issue #51) ✅
- [x] All GitHub Actions workflows passing (Issue #49) ✅

**Pattern Configuration**:
- [x] `values-hub.yaml` uses `pattern.clusterGroupName` convention
- [x] VP Operator installs cleanly: `pattern.sh make install`
- [x] All ArgoCD Applications converge to `Synced/Healthy`

**Documentation**:
- [x] Architecture diagram in README.md (Mermaid diagram exists)
- [x] Support policy: Community-supported (documented in README)
- [x] ADR-019: Validated Patterns Framework adoption ✅
- [x] ADR-026: Secrets Management Automation ✅
- [x] ADR-059: Patternizer Adoption ✅
- [x] ADR-060: This ADR (VP Sandbox Submission) ✅

**CI/CD**:
- [x] GitHub Actions workflows passing:
  - `helm-validation.yml` ✅
  - `ci.yml` (notebook tests, helm lint) ✅
  - `pre-commit.yml` ✅
  - `validate-docs.yml` ✅
  - `validate-pattern.yml` ✅

#### 2. Submission Process

**Step 1: Fork Patterns Catalog**
```bash
# Fork https://github.com/validatedpatterns/patterns-catalog
# Creates YOUR-USERNAME/patterns-catalog
```

**Step 2: Add Catalog Entry**

Create `catalog/openshift-aiops-platform.yaml`:
```yaml
apiVersion: validatedpatterns.io/v1
kind: Pattern
metadata:
  name: openshift-aiops-platform
spec:
  displayName: "OpenShift AIOps Self-Healing Platform"
  description: "Production-ready AIOps platform combining deterministic automation with AI-driven analysis for self-healing OpenShift clusters"
  version: "1.0.0"
  tier: sandbox
  repository: https://github.com/KubeHeal/openshift-aiops-platform.git
  documentation: https://kubeheal.github.io/openshift-aiops-platform/
  maintainers:
    - name: KubeHeal Team
      email: maintainers@kubeheal.io
  keywords:
    - aiops
    - self-healing
    - machine-learning
    - anomaly-detection
    - openshift-ai
    - kserve
  category: AI/ML Operations
  platform:
    - OpenShift 4.19+
  dependencies:
    - Red Hat OpenShift AI 2.22+
    - OpenShift GitOps 1.15+
    - OpenShift Pipelines 1.17+
    - GPU Operator 24.9+ (optional)
  architecture:
    - x86_64
  supportedTopologies:
    - HA (HighlyAvailable)
    - SNO (Single Node OpenShift)
```

**Step 3: Open Submission PR**
```bash
cd patterns-catalog
git checkout -b add-openshift-aiops-platform
# Add catalog entry
git add catalog/openshift-aiops-platform.yaml
git commit -s -m "Add openshift-aiops-platform to Sandbox tier"
git push origin add-openshift-aiops-platform
# Open PR titled: "Add openshift-aiops-platform to Sandbox tier"
```

**Step 4: Provide CI Evidence**

In PR description, attach:
- GitHub Actions workflow run URLs (all passing)
- Deployment screenshot (ArgoCD `Synced/Healthy`)
- Architecture diagram link
- Documentation site link

**Step 5: Notify VP Team**

Post in `#validated-patterns` Slack channel:
```
New Sandbox submission: openshift-aiops-platform
PR: <link>
Description: Production-ready AIOps platform for self-healing OpenShift clusters
Key features: Hybrid deterministic + AI-driven approach, KServe model serving, Tekton validation
```

#### 3. VP CI Requirements

| Check | Description | Status |
|-------|-------------|--------|
| `pattern-tests` | `make test` must pass | ✅ (Tekton validation pipeline) |
| `helm-lint` | All charts must lint cleanly | ✅ (GitHub Actions) |
| `secrets-check` | No plaintext secrets in values files | ✅ (detect-secrets pre-commit hook) |

### Post-Submission Responsibilities

**As a Sandbox Pattern Maintainer**:

1. **Respond to Issues**: Monitor `validatedpatterns/patterns-catalog` issues tagged with our pattern
2. **Keep Pattern Updated**: Merge Patternizer updates regularly (`patternizer upgrade`)
3. **Maintain CI**: Ensure GitHub Actions workflows remain green
4. **Update Documentation**: Keep README.md, CLAUDE.md, and docs/ current
5. **Community Engagement**: Answer questions in Slack, forums, GitHub Discussions
6. **Version Releases**: Follow semantic versioning for pattern releases

**Update Cadence**:
- **Patternizer Updates**: Monthly or when common/ has breaking changes
- **Operator Versions**: Align with OPERATOR_VERSIONS.md updates
- **Security Patches**: Immediate (within 7 days of disclosure)
- **Feature Releases**: Quarterly or as needed

## Consequences

### Benefits

**Positive**:

1. **Visibility**: 
   - Listed in official Validated Patterns catalog (https://validatedpatterns.io/patterns/)
   - Increased discoverability by Red Hat customers and partners
   - GitHub topic tags and search optimization

2. **Community Support**:
   - Access to VP Slack workspace for pattern maintainers
   - Community feedback and contributions
   - Shared knowledge base with other pattern authors

3. **Alignment with Red Hat Ecosystem**:
   - Pattern structure matches Red Hat best practices
   - Compatible with Red Hat documentation standards
   - Easier integration with Red Hat Hybrid Cloud Console

4. **Automated Testing**:
   - VP CI/CD pipeline validates pattern on each commit
   - Early detection of breaking changes in dependencies
   - Community-maintained test infrastructure

5. **Promotion Path**:
   - Clear path to **Maintained** tier (with active maintenance)
   - Potential promotion to **Validated** tier (with Red Hat validation)
   - Enterprise support opportunities

### Drawbacks

**Negative**:

1. **Maintenance Commitment**:
   - Obligation to respond to community issues
   - Need to keep pattern updated with VP framework changes
   - Regular testing required to maintain Sandbox status

2. **Breaking Changes**:
   - VP framework updates may require pattern modifications
   - Patternizer upgrades may conflict with custom changes
   - Need to test upgrades before merging

3. **Support Expectations**:
   - Community may expect enterprise-level support
   - Need to clearly document "community-supported" status
   - Potential for high-volume questions/issues

### Mitigation Strategies

**For Maintenance Burden**:
- Document contribution guidelines in CONTRIBUTING.md
- Use GitHub issue templates to streamline support
- Set clear response SLA (e.g., "best effort within 7 days")
- Leverage GitHub Discussions for community Q&A

**For Breaking Changes**:
- Always test Patternizer upgrades in dedicated branch
- Pin `clustergroup-chart` version in values-global.yaml
- Document upgrade procedures in RELEASE.md
- Maintain CHANGELOG.md with breaking change notices

**For Support Expectations**:
- Add prominent "Community Supported" badge in README.md
- Document support policy (community forums, GitHub issues only)
- Link to commercial support options (if available)
- Set clear scope limitations (e.g., "Platform provides framework, not model tuning")

## Related Documentation

- [Validated Patterns Documentation](https://validatedpatterns.io/)
- [Validated Patterns Catalog](https://github.com/validatedpatterns/patterns-catalog)
- [Patternizer Tool](https://github.com/validatedpatterns/patternizer)
- [ADR-019: Validated Patterns Framework Adoption](./019-validated-patterns-framework-adoption.md)
- [ADR-026: Secrets Management Automation](./026-secrets-management-automation.md)
- [ADR-059: Patternizer Adoption](./059-patternizer-adoption.md)
- [RELEASE.md](../../docs/RELEASE.md) - VP submission checklist
- [README.md](../../README.md) - Pattern overview and quick start

## Implementation Plan

### Phase 1: Pre-Submission Validation (Week 1)

**Day 1-2: Local Testing**
```bash
# Test pattern installation on clean cluster
./pattern.sh make install

# Verify ArgoCD convergence
make argo-healthcheck

# Run validation pipeline
tkn pipeline start deployment-validation-pipeline --showlog
```

**Day 3-4: Documentation Review**
- Review README.md for completeness
- Verify architecture diagram renders correctly
- Update support policy section
- Verify all ADRs referenced in RELEASE.md exist

**Day 5: CI Verification**
- Verify all GitHub Actions workflows green
- Check pre-commit hooks passing
- Verify Helm validation successful

### Phase 2: Catalog Submission (Week 2)

**Day 1: Fork and Prepare**
- Fork `validatedpatterns/patterns-catalog`
- Create catalog entry YAML
- Prepare PR description with evidence

**Day 2-3: Submit PR**
- Open PR with catalog entry
- Attach CI evidence (workflow URLs, screenshots)
- Post Slack notification

**Day 4-7: Address Review Feedback**
- Respond to VP team comments
- Make requested changes
- Re-test if needed

### Phase 3: Post-Acceptance (Ongoing)

**Monthly Tasks**:
- Check for Patternizer updates (`patternizer upgrade`)
- Review and merge dependabot PRs
- Update OPERATOR_VERSIONS.md

**Quarterly Tasks**:
- Review pattern health metrics
- Update documentation
- Consider Maintained tier promotion

## Success Metrics

**Submission Success Criteria**:
- PR merged into `validatedpatterns/patterns-catalog` ✅
- Pattern listed at https://validatedpatterns.io/patterns/ ✅
- VP CI/CD pipeline green for our pattern ✅

**Community Engagement Metrics** (6 months post-acceptance):
- GitHub stars: 50+ ⭐
- Forks: 20+ 🍴
- Community PRs: 5+ 🔄
- Slack discussions: 10+ 💬
- Pattern deployments: 100+ (tracked via telemetry if enabled)

**Promotion Readiness Metrics** (12 months post-acceptance):
- 90%+ uptime on VP CI/CD ✅
- <7 day average issue response time ✅
- Active maintenance (monthly commits) ✅
- Community adoption (50+ stars, 10+ forks) ✅
- Documentation complete (all ADRs finalized) ✅

---

**Note**: This ADR will be updated to `accepted` status once the VP Sandbox submission PR is merged.
