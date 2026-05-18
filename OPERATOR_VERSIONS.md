# Operator Version Requirements

This document tracks the required versions of all operators for the OpenShift AI Ops Self-Healing Platform. Use this as a reference for deployments and updates.

**Last Updated**: 2026-05-18

---

## Critical Operators

### Jupyter Notebook Validator Operator

**Required Version**: v1.0.8  
**Channel**: stable  
**Source**: community-operators  
**Install Mode**: AllNamespaces (targetNamespaces: [])

**Why v1.0.8?**
- ADR-029 requires v1.0.6+ for GPU toleration support
- v1.0.8 is latest stable as of 2026-05-18
- v1.0.2 (alpha channel) lacks critical features:
  - GPU node scheduling with native tolerations
  - Advanced scheduling (nodeSelector, affinity)
  - Fixes for "untolerated taint" errors

**Configuration** (`values-hub.yaml`):
```yaml
jupyter-notebook-validator:
  name: jupyter-notebook-validator-operator
  namespace: jupyter-notebook-validator-operator
  channel: stable  # CRITICAL: Must be 'stable' not 'alpha'
  source: community-operators
```

**OperatorGroup Requirement**:
```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: jupyter-notebook-validator-global
  namespace: jupyter-notebook-validator-operator
spec:
  targetNamespaces: []  # Empty = AllNamespaces mode (REQUIRED)
```

**Container Image Requirement** (CRITICAL):
```yaml
notebooks:
  validation:
    containerImage: image-registry.openshift-image-registry.svc:5000/self-healing-platform/notebook-validator:latest
```

**Why Custom Image Required**:
- Base RHODS images (s2i-minimal-notebook, pytorch) run in Python virtualenv
- Standard `pip install --user` fails with: "Can not perform a '--user' install. User site-packages are not visible in this virtualenv"
- Custom notebook-validator image has Papermill and dependencies pre-installed via BuildConfig

**DO NOT USE**:
- ❌ `image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/s2i-minimal-notebook:2025.1`
- ❌ `image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/pytorch:2025.1`

**BuildConfig Details**:
- Name: `notebook-validator`
- Namespace: `self-healing-platform`
- Output: `notebook-validator:latest` ImageStreamTag
- Build Type: Docker (Git source)
- Pre-installs: Papermill, boto3, kubernetes, prometheus-api-client

**Related Issues**: #66  
**Related ADRs**: ADR-029, ADR-054

---

### External Secrets Operator (Red Hat)

**Required Version**: v1.1.0+  
**Channel**: stable-v1  
**Source**: redhat-operators  
**Install Mode**: AllNamespaces

**Why Red Hat Version?**
- Uses `operator.openshift.io/v1alpha1` API (not upstream `operator.external-secrets.io/v1alpha1`)
- ExternalSecretsConfig CR instead of OperatorConfig
- Integrated with OpenShift monitoring

**Configuration** (`values-hub.yaml`):
```yaml
eso:
  name: openshift-external-secrets-operator
  namespace: external-secrets-operator
  channel: stable-v1
  source: redhat-operators
```

**Related Issues**: #72, #84  
**Related ADRs**: ADR-026 (MANDATORY)

---

### Red Hat OpenShift AI

**Required Version**: v2.22.2+  
**Channel**: stable  
**Source**: redhat-operators  
**Install Mode**: AllNamespaces

**Configuration** (`values-hub.yaml`):
```yaml
openshift-ai:
  name: rhods-operator
  namespace: redhat-ods-operator
  channel: stable
  source: redhat-operators
```

**Components Included**:
- Data Science Pipelines (Kubeflow Pipelines)
- KServe v1.36.1+ (model serving)
- ODH Notebook Controller
- Dashboard

**Related ADRs**: ADR-003, ADR-004

---

### Red Hat OpenShift Pipelines

**Required Version**: v1.22.0+  
**Channel**: latest  
**Source**: redhat-operators  
**Install Mode**: AllNamespaces

**Configuration** (`values-hub.yaml`):
```yaml
openshift-pipelines:
  name: openshift-pipelines-operator-rh
  namespace: openshift-operators
  channel: latest
  source: redhat-operators
```

**Features Used**:
- Tekton Pipelines v0.65+
- Tekton Triggers
- Pipeline-as-Code (optional)

**Related ADRs**: ADR-021, ADR-053

---

### Red Hat OpenShift GitOps

**Required Version**: v1.20.3+  
**Channel**: gitops-1.20  
**Source**: redhat-operators  
**Install Mode**: AllNamespaces

**Configuration**: Deployed by Validated Patterns Operator

**Features Used**:
- ArgoCD v2.14+
- Namespaced ArgoCD with cluster-admin permissions (ADR-030)
- ApplicationSets (optional)

**Related ADRs**: ADR-030, ADR-042, ADR-043

---

### Validated Patterns Operator

**Required Version**: v0.0.72+  
**Channel**: fast  
**Source**: community-operators  
**Install Mode**: AllNamespaces

**Configuration**: Deployed via `make operator-deploy`

**Features Used**:
- Pattern CR (GitOps deployment from Git)
- Automatic ArgoCD application creation
- Multi-cluster hub-spoke topology support

**Related ADRs**: ADR-019

---

## Optional Operators

### NVIDIA GPU Operator

**Required Version**: v24.9.2+  
**Channel**: stable  
**Source**: certified-operators  
**Install Mode**: AllNamespaces

**When Required**:
- HA clusters with GPU-based model training
- Predictive analytics model training (ADR-054)

**When NOT Required**:
- SNO clusters (GPU optional per ADR-057)
- CPU-only anomaly detection models

**Configuration**:
```yaml
# Deployed separately, not via values-hub.yaml
# Use NVIDIA GPU Operator from OperatorHub
```

**Related ADRs**: ADR-006, ADR-057

---

### OpenShift Data Foundation (ODF)

**Required Version**: v4.20+ (matches OpenShift version)  
**Channel**: stable-4.20  
**Source**: redhat-operators  
**Install Mode**: AllNamespaces

**When Required**:
- HA clusters: Full ODF (Ceph + NooBaa)
- SNO clusters: MCG-only (NooBaa without Ceph)

**Configuration**: Deployed via `make configure-cluster`

**Related ADRs**: ADR-035, ADR-041, ADR-056

---

## Version Compatibility Matrix

| OpenShift | Jupyter Validator | External Secrets | OpenShift AI | Pipelines | GitOps | GPU Operator | ODF |
|-----------|-------------------|------------------|--------------|-----------|--------|--------------|-----|
| 4.18 | v1.0.8 (stable) | v1.1.0+ | v2.22.2+ | v1.17.2+ | v1.15.4+ | v24.9.2+ | 4.18 |
| 4.19 | v1.0.8 (stable) | v1.1.0+ | v2.22.2+ | v1.19.0+ | v1.17.1+ | v24.9.2+ | 4.19 |
| 4.20 | v1.0.8 (stable) | v1.1.0+ | v2.22.2+ | v1.22.0+ | v1.20.3+ | v24.9.2+ | 4.20 |

---

## Upgrade Strategy

### Safe Upgrade Path

1. **Check compatibility**: Review this matrix before upgrading OpenShift
2. **Upgrade operators first**: Update operators before platform components
3. **Test on non-production**: Validate operator upgrades on dev/staging clusters
4. **Monitor CSV status**: Ensure all CSVs show "Succeeded" after upgrade

### Operator Upgrade Commands

```bash
# Check installed versions
oc get csv -A

# Check available versions in catalog
oc get packagemanifest <operator-name> -n openshift-marketplace \
  -o jsonpath='{.status.channels[*].currentCSVDesc.version}'

# Update subscription channel (if needed)
oc patch subscription <subscription-name> -n <namespace> \
  --type=merge -p '{"spec":{"channel":"<new-channel>"}}'

# Verify upgrade
oc get csv -n <namespace>
```

### Rollback Strategy

If an operator upgrade fails:

1. **Check CSV status**:
   ```bash
   oc get csv -n <namespace>
   oc describe csv <csv-name> -n <namespace>
   ```

2. **Rollback subscription** (if automatic upgrades enabled):
   ```bash
   oc patch subscription <name> -n <namespace> \
     --type=merge -p '{"spec":{"channel":"<previous-channel>"}}'
   ```

3. **Force delete failed CSV** (last resort):
   ```bash
   oc delete csv <failed-csv> -n <namespace>
   # OLM will recreate from subscription
   ```

---

## Troubleshooting

### Operator Fails with "TooManyOperatorGroups"

**Symptoms**: CSV status shows "TooManyOperatorGroups" error

**Solution**:
```bash
# Check for multiple OperatorGroups
oc get operatorgroups -n <namespace>

# Delete extras (keep only one)
oc delete operatorgroup <extra-group> -n <namespace>
```

### Operator Stuck in "Installing" Phase

**Symptoms**: CSV shows "Installing" for >5 minutes

**Solution**:
```bash
# Check InstallPlan status
oc get installplan -n <namespace>

# Check pod logs
oc logs -n <namespace> -l olm.owner.kind=ClusterServiceVersion

# Restart catalog-operator (if needed)
oc delete pod -n openshift-operator-lifecycle-manager \
  -l app=catalog-operator
```

### Wrong Operator Version Installed

**Symptoms**: Expected v1.0.8 but got v1.0.2

**Cause**: Wrong channel in subscription (alpha vs stable)

**Solution**:
1. Delete subscription and CSV
2. Verify OperatorGroup is correct
3. Recreate subscription with correct channel
4. Wait for OLM to create InstallPlan

See Issue #66 for detailed steps.

---

## Verification Commands

```bash
# Check all operator versions
oc get csv -A | grep -E "NAME|external-secrets|jupyter|rhods|pipelines|gitops|patterns|gpu|ocs"

# Verify Jupyter operator version (should show v1.0.8)
oc get csv -n jupyter-notebook-validator-operator | grep jupyter

# Verify channels in subscriptions
oc get subscription -A -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
PACKAGE:.spec.name,\
CHANNEL:.spec.channel,\
CSV:.status.currentCSV

# Check operator health
oc get clusteroperators
oc get csv -A --no-headers | grep -v Succeeded
```

---

## Related Documentation

- [Issue #66](https://github.com/KubeHeal/openshift-aiops-platform/issues/66): Jupyter operator version fix
- [ADR-029](docs/adrs/029-jupyter-notebook-validator-operator.md): Jupyter Notebook Validator Operator
- [ADR-026](docs/adrs/026-secrets-management-automation.md): Secrets Management (MANDATORY)
- [CLAUDE.md](CLAUDE.md): AI agent quick reference
- [TROUBLESHOOTING-GUIDE.md](docs/guides/TROUBLESHOOTING-GUIDE.md): Complete troubleshooting guide

---

**Maintained By**: Platform Team  
**Review Frequency**: After each OpenShift minor version release  
**Last Reviewer**: Architecture Team
