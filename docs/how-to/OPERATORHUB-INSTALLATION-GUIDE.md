# How to Install OperatorHub.io Operators in OpenShift

This guide explains the standard methods for installing operators from OperatorHub.io into OpenShift clusters.

## Overview

**OperatorHub.io** is a community catalog of Kubernetes operators separate from OpenShift's built-in operator catalogs. To use operators from OperatorHub.io in OpenShift, you need to:

1. Add the OperatorHub.io CatalogSource to your cluster
2. Install the operator via OLM (Operator Lifecycle Manager)

---

## Method 1: OpenShift Web Console (GUI) - Recommended for Most Users

### Step 1: Add OperatorHub.io CatalogSource

**Option A: Via Web Console**
1. Navigate to **Administration** → **Cluster Settings** → **Configuration** → **OperatorHub**
2. Click **Sources** tab
3. Click **Create CatalogSource**
4. Enter:
   - **Name**: `operatorhubio-catalog`
   - **Display Name**: `OperatorHub.io Community Operators`
   - **Publisher**: `OperatorHub.io`
   - **Image**: `quay.io/operatorhubio/catalog:latest`
   - **Source Type**: `grpc`
5. Click **Create**

**Option B: Via CLI**
```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: operatorhubio-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/operatorhubio/catalog:latest
  displayName: OperatorHub.io Community Operators
  publisher: OperatorHub.io
  updateStrategy:
    registryPoll:
      interval: 60m
EOF
```

### Step 2: Wait for Catalog to Sync

```bash
# Check catalog status
oc get catalogsource operatorhubio-catalog -n openshift-marketplace

# Wait for READY status
oc get catalogsource operatorhubio-catalog -n openshift-marketplace -o jsonpath='{.status.connectionState.lastObservedState}'
# Should output: READY
```

### Step 3: Install Operator via Web Console

1. Navigate to **Operators** → **OperatorHub**
2. Search for your operator (e.g., "jupyter-notebook-validator-operator")
3. Click on the operator tile
4. Click **Install**
5. Configure installation:
   - **Update Channel**: Select channel (e.g., `alpha`)
   - **Installation Mode**: `All namespaces on the cluster` (recommended)
   - **Installed Namespace**: `openshift-operators`
   - **Update Approval**: `Automatic` (recommended)
6. Click **Install**
7. Wait for installation to complete (Status: **Succeeded**)

---

## Method 2: Command Line (CLI) - For Automation

### Step 1: Add OperatorHub.io CatalogSource

```bash
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: operatorhubio-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/operatorhubio/catalog:latest
  displayName: OperatorHub.io Community Operators
  publisher: OperatorHub.io
  updateStrategy:
    registryPoll:
      interval: 60m
EOF
```

### Step 2: Create OperatorGroup (if not using openshift-operators)

**Note**: If installing to `openshift-operators` namespace, skip this step (OperatorGroup already exists).

```bash
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: my-operatorgroup
  namespace: openshift-operators
spec: {}
EOF
```

### Step 3: Create Subscription

```bash
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: jupyter-notebook-validator-operator
  namespace: openshift-operators
spec:
  channel: alpha
  name: jupyter-notebook-validator-operator
  source: operatorhubio-catalog
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

### Step 4: Verify Installation

```bash
# Check subscription status
oc get subscription jupyter-notebook-validator-operator -n openshift-operators

# Check CSV (ClusterServiceVersion)
oc get csv -n openshift-operators | grep jupyter

# Check operator deployment
oc get deployment -n openshift-operators | grep notebook

# Check operator pods
oc get pods -n openshift-operators | grep notebook
```

---

## Method 3: Using the OperatorHub.io Install YAML

Each operator on OperatorHub.io provides an install YAML at:
```
https://operatorhub.io/install/<operator-name>.yaml
```

**Example for Jupyter Notebook Validator Operator:**

```bash
# Download the install YAML
curl -sL https://operatorhub.io/install/jupyter-notebook-validator-operator.yaml -o /tmp/operator-install.yaml

# Review the YAML
cat /tmp/operator-install.yaml

# Modify namespace if needed (default is 'operators', change to 'openshift-operators')
sed -i 's/namespace: operators/namespace: openshift-operators/g' /tmp/operator-install.yaml

# Apply the subscription
oc apply -f /tmp/operator-install.yaml
```

**⚠️ Important Notes:**
- The OperatorHub.io YAML typically uses `namespace: operators` - you may need to change this to `openshift-operators` for OpenShift
- The YAML only creates a Subscription - you still need to add the CatalogSource first (see Method 1 or 2)

---

## Troubleshooting

### Issue 1: Operator Not Found in OperatorHub

**Symptoms:**
```bash
oc get packagemanifest <operator-name> -n openshift-marketplace
# Error: packagemanifests.packages.operators.coreos.com "<operator-name>" not found
```

**Solution:**
1. Verify CatalogSource exists and is READY:
   ```bash
   oc get catalogsource operatorhubio-catalog -n openshift-marketplace
   oc get catalogsource operatorhubio-catalog -n openshift-marketplace -o yaml | grep -A 5 "status:"
   ```

2. Wait for catalog to sync (can take 5-10 minutes):
   ```bash
   oc get pods -n openshift-marketplace | grep operatorhubio
   ```

3. Check catalog pod logs:
   ```bash
   oc logs -n openshift-marketplace -l olm.catalogSource=operatorhubio-catalog
   ```

### Issue 2: CSV Not Created After Subscription

**Symptoms:**
- Subscription exists but no CSV appears
- `oc get csv -n openshift-operators` shows no operator

**Solution:**
1. Check InstallPlan:
   ```bash
   oc get installplan -n openshift-operators
   oc describe installplan <installplan-name> -n openshift-operators
   ```

2. Check subscription status:
   ```bash
   oc describe subscription <operator-name> -n openshift-operators
   ```

3. Check for approval requirement:
   ```bash
   oc get installplan -n openshift-operators -o yaml | grep -A 5 "approval:"
   ```

4. Manually approve if needed:
   ```bash
   oc patch installplan <installplan-name> -n openshift-operators --type merge -p '{"spec":{"approved":true}}'
   ```

### Issue 3: Operator Pod Not Starting

**Symptoms:**
- CSV shows "Installing" or "Failed"
- Operator deployment exists but pods are not running

**Solution:**
1. Check deployment status:
   ```bash
   oc get deployment -n openshift-operators
   oc describe deployment <operator-deployment> -n openshift-operators
   ```

2. Check pod status:
   ```bash
   oc get pods -n openshift-operators
   oc describe pod <operator-pod> -n openshift-operators
   ```

3. Check pod logs:
   ```bash
   oc logs <operator-pod> -n openshift-operators
   ```

4. Check for image pull errors or resource constraints

---

## Best Practices

### 1. Use Automatic Approval for Development
```yaml
spec:
  installPlanApproval: Automatic
```

### 2. Use Manual Approval for Production
```yaml
spec:
  installPlanApproval: Manual
```

### 3. Pin to Specific Version (Optional)
```yaml
spec:
  startingCSV: jupyter-notebook-validator-operator.v1.0.4
```

### 4. Monitor Operator Health
```bash
# Check CSV status
oc get csv -n openshift-operators -w

# Check operator logs
oc logs -f deployment/<operator-deployment> -n openshift-operators
```

### 5. Use Labels for Organization
```yaml
metadata:
  labels:
    app.kubernetes.io/name: jupyter-notebook-validator-operator
    app.kubernetes.io/managed-by: olm
```

---

## Comparison: OpenShift Built-in vs OperatorHub.io

| Feature | OpenShift Built-in | OperatorHub.io |
|---------|-------------------|----------------|
| **Catalog** | Pre-configured | Requires CatalogSource |
| **Support** | Red Hat supported | Community supported |
| **Updates** | Automatic | Manual catalog updates |
| **Availability** | Always available | Requires internet access |
| **Operators** | Curated by Red Hat | Community contributed |

---

## References

- [OperatorHub.io](https://operatorhub.io/)
- [OpenShift Operator Documentation](https://docs.openshift.com/container-platform/latest/operators/understanding/olm-what-operators-are.html)
- [Operator Lifecycle Manager (OLM)](https://olm.operatorframework.io/)
- [Jupyter Notebook Validator Operator](https://operatorhub.io/operator/jupyter-notebook-validator-operator)
- [GitHub: jupyter-notebook-validator-operator](https://github.com/tosin2013/jupyter-notebook-validator-operator)
