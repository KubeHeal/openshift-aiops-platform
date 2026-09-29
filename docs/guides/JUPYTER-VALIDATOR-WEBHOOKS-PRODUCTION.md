# Jupyter Notebook Validator Operator - Production Webhook Setup

**Date**: 2025-12-04
**Status**: Production Configuration

## Overview

For **production deployments**, the Jupyter Notebook Validator Operator should be deployed **with webhooks enabled** for enhanced validation and user experience.

**Reference Documentation**:
- [Webhook Installation Guide](https://raw.githubusercontent.com/tosin2013/jupyter-notebook-validator-operator/refs/heads/main/docs/WEBHOOK-INSTALLATION-GUIDE.md)
- [Webhook Configuration](https://raw.githubusercontent.com/tosin2013/jupyter-notebook-validator-operator/refs/heads/main/docs/WEBHOOK_CONFIGURATION.md)

## Why Webhooks for Production? 🎯

### ✅ With Webhooks Enabled (Production)

**Mutating Webhook** (Automatic Defaults):
- ✅ Automatically sets `serviceAccountName: "default"` if not specified
- ✅ Automatically sets `timeout: "30m"` if not specified
- ✅ Converts `credentials: [secret-name]` to `envFrom` (simplified syntax)

**Validating Webhook** (Early Error Detection):
- ✅ **Prevents reserved volume names** (`git-clone`, `notebook-data`, `source`)
- ✅ **Catches duplicate volume names** at creation time
- ✅ **Validates volume mounts** reference existing volumes
- ✅ **Clear error messages** instead of cryptic pod failures

### User Experience Comparison

| Feature | With Webhooks (Production) | Without Webhooks (CI/Test) |
|---------|---------------------------|---------------------------|
| **Setup Complexity** | Medium (requires cert-manager) | Low (no dependencies) |
| **Startup Time** | ~60-90s (cert injection) | ~10-20s |
| **User Experience** | ✅ Excellent (automatic defaults) | ⚠️ Manual (verbose config) |
| **Volume Validation** | ✅ Early (at creation) | ❌ Late (at pod runtime) |
| **Error Messages** | ✅ Clear validation errors | ❌ Cryptic pod failures |
| **Credential Syntax** | ✅ Simple (`credentials: [...]`) | ⚠️ Verbose (`envFrom: [...]`) |

## Prerequisites

### 1. cert-manager Installation

Our deployment **automatically detects** cert-manager and enables webhooks if present.

**Verify cert-manager**:
```bash
oc get pods -n cert-manager
```

Expected output:
```
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-xxxxxxxxxx-xxxxx              1/1     Running   0          10m
cert-manager-cainjector-xxxxxxxxxx-xxxxx   1/1     Running   0          10m
cert-manager-webhook-xxxxxxxxxx-xxxxx      1/1     Running   0          10m
```

**If cert-manager is not installed**:
```bash
# Install cert-manager v1.13.0 (or later)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager -n cert-manager
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager-webhook -n cert-manager
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager-cainjector -n cert-manager
```

## Deployment with Webhooks

### Automatic Deployment

The operator deployment automatically:
1. **Detects cert-manager** presence in the cluster
2. **Enables webhooks** if cert-manager is found
3. **Creates Issuer** (self-signed) in operator namespace
4. **Creates Certificate** resource for webhook server
5. **Waits for cert-manager** to issue the certificate
6. **Starts operator pod** once webhook-server-cert secret exists

### Installation Steps

```bash
# 1. Ensure cert-manager is running
oc get pods -n cert-manager

# 2. Install operator (webhooks auto-enabled)
make install-jupyter-validator

# The deployment will:
# - Detect cert-manager ✅
# - Enable webhooks ✅
# - Create Issuer and Certificate ✅
# - Wait for cert-manager to create webhook-server-cert ✅
# - Start operator pod with webhooks enabled ✅
```

### Deployment Flow

```
1. User runs: make install-jupyter-validator
   ↓
2. Ansible detects cert-manager namespace exists
   └─> Sets jupyter_validator_enable_webhooks: true
   ↓
3. Kustomize applies manifests:
   - Namespace: jupyter-notebook-validator-operator
   - CRD: notebookvalidationjobs.mlops.mlops.dev
   - RBAC: ClusterRole, ClusterRoleBinding, ServiceAccounts
   - Issuer: notebook-validator-selfsigned-issuer (self-signed)
   - Certificate: notebook-validator-serving-cert
   - Service: notebook-validator-webhook-service
   - ValidatingWebhookConfiguration
   - MutatingWebhookConfiguration
   ↓
4. Wait for Certificate to be Ready
   └─> cert-manager creates webhook-server-cert secret
   ↓
5. Deployment: notebook-validator-controller-manager
   └─> Mounts webhook-server-cert secret
   └─> Starts webhook server on port 9443
   ↓
6. Operator pod becomes Ready ✅
   └─> Webhooks active and processing requests
```

### Verification

```bash
# Check operator is running with webhooks
oc get pods -n jupyter-notebook-validator-operator
oc logs -n jupyter-notebook-validator-operator -l control-plane=controller-manager | grep webhook

# Expected log output:
# "webhooks enabled - configuring webhook server"

# Check certificate was created
oc get certificate -n jupyter-notebook-validator-operator

# Check webhook secret exists
oc get secret webhook-server-cert -n jupyter-notebook-validator-operator

# Check webhook configurations
oc get validatingwebhookconfigurations | grep jupyter-notebook
oc get mutatingwebhookconfigurations | grep jupyter-notebook
```

## Testing Webhooks

### Test 1: Automatic Defaults (Mutating Webhook)

Create a minimal NotebookValidationJob without specifying serviceAccountName or timeout:

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: test-mutating-webhook
  namespace: self-healing-platform
spec:
  notebook:
    git:
      url: "https://github.com/tosin2013/jupyter-notebook-validator-test-notebooks"
      ref: "main"
    path: "notebooks/tier1-simple/01-hello-world.ipynb"
  podConfig:
    containerImage: "quay.io/jupyter/scipy-notebook:latest"
    # No serviceAccountName specified - webhook will add it
    # No timeout specified - webhook will add it
```

Apply and verify:
```bash
oc apply -f test-mutating-webhook.yaml

# Check the resource was mutated
oc get notebookvalidationjob test-mutating-webhook -o yaml | grep -A 5 podConfig

# Should show:
#   serviceAccountName: default  ← Added by webhook
# And:
# timeout: 30m  ← Added by webhook
```

### Test 2: Volume Validation (Validating Webhook)

Try to create a job with a reserved volume name (should be rejected):

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: test-validating-webhook
spec:
  notebook:
    git:
      url: "https://github.com/tosin2013/jupyter-notebook-validator-test-notebooks"
      ref: "main"
    path: "notebooks/tier1-simple/01-hello-world.ipynb"
  podConfig:
    containerImage: "quay.io/jupyter/scipy-notebook:latest"
    serviceAccountName: "default"
    volumes:
      - name: git-clone  # Reserved name - should be rejected
        emptyDir: {}
```

Apply and verify rejection:
```bash
oc apply -f test-validating-webhook.yaml

# Expected error from webhook:
# Error from server: admission webhook "vnotebookvalidationjob.kb.io" denied the request:
# volume name "git-clone" is reserved by the operator
```

## Troubleshooting

### Issue: Pod stuck in ContainerCreating with "secret not found"

**Symptom**:
```
MountVolume.SetUp failed for volume "cert" : secret "webhook-server-cert" not found
```

**Root Cause**: cert-manager hasn't created the certificate yet

**Solution**: Wait for cert-manager to issue the certificate
```bash
# Check certificate status
oc describe certificate -n jupyter-notebook-validator-operator

# Check cert-manager logs
oc logs -n cert-manager -l app=cert-manager --tail=50

# If certificate is stuck, delete and recreate
oc delete certificate notebook-validator-serving-cert -n jupyter-notebook-validator-operator
# Deployment will recreate it
```

### Issue: Webhook timeouts or connection refused

**Symptom**: Webhook calls timeout or return connection refused

**Solution**: Check webhook service and pod
```bash
# Check webhook service
oc get service -n jupyter-notebook-validator-operator | grep webhook

# Check operator pod logs
oc logs -n jupyter-notebook-validator-operator -l control-plane=controller-manager | grep -i webhook

# Test webhook endpoint
oc port-forward -n jupyter-notebook-validator-operator deployment/notebook-validator-controller-manager 9443:9443
curl -k https://localhost:9443/healthz
```

### Issue: cert-manager not installed

**Symptom**: Deployment detects no cert-manager, webhooks disabled

**Solution**: Install cert-manager first
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for ready
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager

# Uninstall and reinstall operator
make uninstall-jupyter-validator
make install-jupyter-validator
```

## Configuration

### Default Configuration (Production)

The operator automatically enables webhooks when cert-manager is detected:

```yaml
# ansible/roles/validated_patterns_jupyter_validator/defaults/main.yml
jupyter_validator_enable_webhooks: false  # Auto-detected (set to true if cert-manager found)
jupyter_validator_kustomize_overlay: "overlays/dev-ocp4.18"  # Includes webhook resources
```

### Webhook Environment Variables

The operator deployment sets:
```yaml
env:
  - name: ENABLE_WEBHOOKS
    value: "true"  # Enabled automatically when cert-manager detected
  - name: PLATFORM
    value: "openshift"
```

## Uninstallation

```bash
# Uninstall operator (removes webhooks, certificates, issuer)
make uninstall-jupyter-validator

# Verify cleanup
oc get certificate -n jupyter-notebook-validator-operator  # Should be empty
oc get validatingwebhookconfigurations | grep jupyter-notebook  # Should be empty
oc get mutatingwebhookconfigurations | grep jupyter-notebook  # Should be empty
```

## Summary

✅ **For Production**: Webhooks **ENABLED** (requires cert-manager)
- Better user experience
- Early error detection
- Automatic defaults
- Simplified syntax

⚠️ **For CI/Testing**: Webhooks **DISABLED** (optional)
- Faster startup
- No cert-manager dependency
- Manual configuration required

**Reference**: [ADR-029 Jupyter Notebook Validator Operator](adrs/029-jupyter-notebook-validator-operator.md)

---

**Last Updated**: 2025-12-04
**Production Ready**: ✅ Yes (with cert-manager)
