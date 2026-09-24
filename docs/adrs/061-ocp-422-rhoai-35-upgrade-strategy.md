# ADR-061: OCP 4.22 and OpenShift AI 3.5 Upgrade Strategy

## Status

Proposed

## Date

2026-09-24

## Context

The platform was originally built and validated on OpenShift 4.18-4.20 with Red Hat
OpenShift AI (RHOAI) 2.22.2+ on the `stable` channel. As OpenShift 4.22 and RHOAI
3.5 become available, the platform needs a documented and repeatable upgrade strategy
that safely transitions both the cluster infrastructure and all repository
configuration files.

Key challenges:

1. **Multi-hop upgrades**: OpenShift does not support direct jumps across multiple
   minor versions. A cluster on 4.20 must upgrade through 4.21 before reaching 4.22.
2. **SNO considerations**: Single Node OpenShift clusters experience a full node
   reboot during upgrades, causing temporary API unavailability.
3. **RHOAI channel migration**: RHOAI 3.5 may use a different subscription channel
   (e.g., `stable-3.5`) than the previous `stable` channel that served 2.x versions.
4. **Operator compatibility**: ODF, Pipelines, GitOps, and other operators have
   version-specific channels that must be updated alongside the cluster.
5. **Repository config drift**: Multiple files across the repository reference the
   OCP version (values files, Helm chart defaults, Kustomize overlays, Ansible
   defaults, validation scripts, documentation).

## Decision

We will implement an automated upgrade script (`scripts/upgrade-cluster.sh`) that
handles the full upgrade lifecycle in five phases, with dry-run mode enabled by
default and manual confirmation gates between destructive operations.

### Upgrade Phases

1. **Pre-flight Checks**: Verify cluster health, detect current versions, confirm
   no in-progress upgrades, validate ClusterOperator and node readiness.
2. **OCP Multi-Hop Upgrade**: For each minor version hop (e.g., 4.20 -> 4.21 ->
   4.22), set the channel, verify available updates, trigger the upgrade, and wait
   for completion with health gates.
3. **RHOAI Upgrade**: Patch the `rhods-operator` subscription to the target channel,
   wait for the new CSV to succeed, and verify DataScienceCluster health.
4. **Repository Config Updates**: Update all version-dependent files in the
   repository to match the new target versions.
5. **Post-Upgrade Validation**: Verify final cluster state, operator CSVs, ArgoCD
   application health, and RHOAI dashboard accessibility.

### Safety Features

- **Dry-run by default**: The script shows what it would do without making changes.
  The `--execute` flag is required to apply changes.
- **Manual confirmations**: Each phase and each hop prompts for confirmation (skip
  with `--yes` for CI/CD use).
- **SNO-aware retry logic**: When the API becomes unavailable during SNO node
  reboots, the script retries with exponential backoff instead of failing.
- **Health gates**: Between each upgrade hop, the script validates that all
  ClusterOperators are available and all nodes are Ready before proceeding.
- **Phase skip flags**: `--skip-ocp`, `--skip-rhoai`, and `--skip-config` allow
  running only the phases needed.
- **CCO Manual mode fix**: When the root cloud credential secret is missing or
  expired (common on sandbox/lab clusters), `--fix-cco-manual` switches the Cloud
  Credential Operator to Manual mode and adds the `upgradeable-to` annotation,
  clearing the `Upgradeable=False` gate without requiring root IAM credentials.
  Works on AWS, Azure, and GCP clusters running OCP 4.18+.

### Files Updated for 4.22 Compatibility

| File | Change |
|------|--------|
| `values-hub.yaml` | `cluster.version: "4.22"`, RHOAI channel to `stable-3.5` |
| `values-hub.yaml.example` | `cluster.version: "4.22"` |
| `charts/hub/values.yaml` | `cluster.version: "4.22"` |
| `charts/hub/templates/_helpers.tpl` | Default version fallbacks to `"4.22"` |
| `charts/hub/templates/ai-ml-workbench.yaml` | Default version fallback to `"4.22"` |
| `charts/hub/templates/pre-deployment-validation.yaml` | Minimum version to `"4.18"` |
| `charts/hub/templates/tekton-deployment-validation.yaml` | Default min version to `"4.20"` |
| `pattern-metadata.yaml` | `openshift_version: "4.22+"` |
| `ansible/roles/validated_patterns_operator/defaults/main.yml` | `vp_min_openshift_version: "4.20"` |
| `scripts/install-prerequisites-rhel.sh` | `OC_VERSION` default to `4.22` |
| `docs/reference/operator-versions.md` | Add 4.21/4.22 rows, RHOAI 3.5 |
| `k8s/operators/.../overlays/` | Add `dev-ocp4.21` and `dev-ocp4.22` overlays |

### Version Compatibility

| OCP | RHOAI | ODF Channel | Dashboard Route |
|-----|-------|-------------|-----------------|
| 4.18 | 2.x | stable-4.18 | rhods-dashboard-redhat-ods-applications |
| 4.19 | 2.x / 3.x | stable-4.19 | rhods-dashboard-redhat-ods-applications |
| 4.20 | 3.x | stable-4.20 | data-science-gateway |
| 4.21 | 3.5 | stable-4.21 | data-science-gateway |
| 4.22 | 3.5 | stable-4.22 | data-science-gateway |

### Helm Template Compatibility

The existing `semverCompare ">=4.20"` checks in Helm templates remain correct for
4.22 (since 4.22 >= 4.20 is true). This means:

- RHOAI 3.x features (inject-auth, data-science-gateway route) are automatically
  enabled for 4.20+.
- No new semverCompare thresholds are needed unless RHOAI 3.5 introduces
  behavior that differs from RHOAI 3.x on 4.20.

## Consequences

### Positive

- Repeatable, scriptable upgrade process that reduces manual errors
- Dry-run mode allows operators to preview changes before applying
- Multi-hop logic handles arbitrary starting versions
- SNO-aware retry logic prevents false failures during node reboots
- All version-dependent config files updated consistently
- Repository stays in sync with the deployed cluster version

### Negative

- Script depends on `oc adm upgrade` output format, which could change
- RHOAI channel naming is assumed (must be verified against live catalog)
- Operator version floors in the compatibility matrix are estimated for
  4.21/4.22 and should be verified after release

### Neutral

- The script can be re-run with `--skip-ocp` to update only config files
- Phase skip flags allow partial upgrades for testing
- The Cincinnati upgrade graph API could be integrated in the future for
  more precise upgrade path planning

## Related ADRs

- [ADR-001](001-openshift-platform-selection.md): OpenShift 4.18+ as Foundation
- [ADR-003](003-openshift-ai-ml-platform.md): Red Hat OpenShift AI for ML
- [ADR-055](055-openshift-420-multi-cluster-topology-support.md): Multi-cluster Topology Support
- [ADR-056](056-standalone-mcg-on-sno.md): Standalone MCG on SNO
- [ADR-057](057-topology-aware-gpu-scheduling-and-storage.md): Topology-Aware GPU Scheduling

## References

- [OpenShift Update Graph](https://access.redhat.com/labs/ocpupgradegraph/update_channel)
- [OpenShift Upgrade Documentation](https://docs.openshift.com/container-platform/4.22/updating/index.html)
- [RHOAI Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
- Script: `scripts/upgrade-cluster.sh`
- Operator versions: `docs/reference/operator-versions.md`
