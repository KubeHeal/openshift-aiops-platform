# Jupyter Notebook Validator Operator Installation - SUCCESS ✅

**Date**: December 1, 2025
**Operator Version**: v1.0.4-ocp4.18
**Installation Method**: Direct Deployment (bypassing OLM due to catalog sync lag)

## Summary

Successfully installed the Jupyter Notebook Validator Operator v1.0.4-ocp4.18 on OpenShift 4.18.21 by deploying it directly without OLM, after discovering that the OperatorHub.io catalog had not yet been updated with the operator.

## Root Cause Analysis

### Issue 1: Catalog Sync Lag
- **Problem**: The operator exists in the GitHub repository but not in the `quay.io/operatorhubio/catalog:latest` image
- **Impact**: Operator doesn't appear in OpenShift marketplace search
- **Timeline**: Unknown delay between GitHub merge and catalog image rebuild

### Issue 2: Version Mismatch in v1.0.4-ocp4.20 Bundle
- **Problem**: Bundle has `minKubeVersion: 1.33.0` which is incompatible with OpenShift 4.18 (Kubernetes 1.31.10)
- **Solution**: Used v1.0.4-ocp4.18 bundle instead, which has `minKubeVersion: 1.31.0`

### Issue 3: Image Tag Format
- **Problem**: Bundle CSV referenced `v1.0.4-ocp4.18` but actual image tag is `1.0.4-ocp4.18` (no "v" prefix)
- **Solution**: Corrected image reference in deployment manifest

## Installation Approach

### What We Did

1. **Extracted Bundle Manifests**:
   ```bash
   skopeo copy docker://quay.io/takinosh/jupyter-notebook-validator-operator-bundle:v1.0.4-ocp4.18 dir:/tmp/jupyter-bundle-4.18
   ```

2. **Created Direct Deployment Manifests**:
   - Namespace: `jupyter-notebook-validator-system`
   - ServiceAccount with proper RBAC (ClusterRole + ClusterRoleBinding)
   - Deployment with correct image: `quay.io/takinosh/jupyter-notebook-validator-operator:1.0.4-ocp4.18`
   - Webhook service and metrics service

3. **Configured Webhooks with cert-manager**:
   - Created self-signed ClusterIssuer
   - Generated webhook certificate via cert-manager
   - Configured ValidatingWebhookConfiguration and MutatingWebhookConfiguration
   - Enabled webhooks with `ENABLE_WEBHOOKS=true` environment variable

4. **Applied CRD**:
   ```bash
   oc apply -f /tmp/jupyter-bundle-4.18/manifests/mlops.mlops.dev_notebookvalidationjobs.yaml
   ```

## Installation Files

### Primary Manifests
- `manifests/jupyter-operator-direct-deployment.yaml` - Main operator deployment
- `manifests/jupyter-operator-webhook-config.yaml` - Webhook and certificate configuration

### Key Configuration
```yaml
# Operator image
image: quay.io/takinosh/jupyter-notebook-validator-operator:1.0.4-ocp4.18

# Webhooks enabled
env:
- name: ENABLE_WEBHOOKS
  value: "true"
- name: PLATFORM
  value: "openshift"
```

## Verification

### Operator Status
```bash
$ oc get deployment -n jupyter-notebook-validator-system
NAME                                    READY   UP-TO-DATE   AVAILABLE   AGE
notebook-validator-controller-manager   1/1     1            1           6m

$ oc get pods -n jupyter-notebook-validator-system
NAME                                                     READY   STATUS    RESTARTS   AGE
notebook-validator-controller-manager-6f57978c89-6hw4n   2/2     Running   0          2m
```

### Operator Logs (Success Indicators)
```
✅ successfully acquired lease jupyter-notebook-validator-system/16681bfb.mlops.dev
✅ Starting Controller {"controller": "notebookvalidationjob"}
✅ Starting workers {"worker count": 1}
✅ Updated current TLS certificate
✅ Serving webhook server {"host": "", "port": 9443}
```

### CRD Installed
```bash
$ oc get crd notebookvalidationjobs.mlops.mlops.dev
NAME                                     CREATED AT
notebookvalidationjobs.mlops.mlops.dev   2025-11-28T04:33:57Z
```

### Webhooks Configured
```bash
$ oc get validatingwebhookconfiguration notebook-validator-validating-webhook-configuration
NAME                                                  WEBHOOKS   AGE
notebook-validator-validating-webhook-configuration   1          2m

$ oc get mutatingwebhookconfiguration notebook-validator-mutating-webhook-configuration
NAME                                                WEBHOOKS   AGE
notebook-validator-mutating-webhook-configuration   1          2m
```

## Next Steps

1. **Test the Operator**: Create a NotebookValidationJob to verify functionality
2. **Monitor Operator**: Watch logs for any issues during reconciliation
3. **Update Documentation**: Document this installation method for future reference
4. **Track OperatorHub.io**: Monitor when the operator appears in the public catalog

## Lessons Learned

1. **OperatorHub.io Catalog Lag**: There can be significant delays between GitHub merges and catalog updates
2. **Version Compatibility**: Always check `minKubeVersion` in bundle manifests
3. **Image Tag Formats**: Verify actual image tags in registry vs. what's in manifests
4. **Direct Deployment**: Bypassing OLM is viable when catalog sources are unavailable
5. **Webhook Configuration**: cert-manager integration works seamlessly on OpenShift

## References

- Operator Repository: https://github.com/tosin2013/jupyter-notebook-validator-operator
- Webhook Configuration Guide: https://raw.githubusercontent.com/tosin2013/jupyter-notebook-validator-operator/refs/heads/main/docs/WEBHOOK_CONFIGURATION.md
- Bundle Image: `quay.io/takinosh/jupyter-notebook-validator-operator-bundle:v1.0.4-ocp4.18`
- Operator Image: `quay.io/takinosh/jupyter-notebook-validator-operator:1.0.4-ocp4.18`
