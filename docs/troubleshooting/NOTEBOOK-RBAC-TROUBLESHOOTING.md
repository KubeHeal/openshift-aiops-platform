# Notebook RBAC Troubleshooting Guide

**Quick Reference for 403 Forbidden Errors**

---

## Common 403 Forbidden Errors & Solutions

### Error 1: Cannot list resource "pods"
```
pods is forbidden: User "system:serviceaccount:self-healing-platform:self-healing-workbench-dev"
cannot list resource "pods" in API group "" in the namespace "self-healing-platform"
```

**Solution**:
```bash
# Verify permission
kubectl auth can-i list pods --as=system:serviceaccount:self-healing-platform:self-healing-workbench-dev -n self-healing-platform

# Should return: yes
```

**If NO**: Add to Role in k8s/base/rbac.yaml:
```yaml
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
```

---

### Error 2: Cannot get resource "pods/log"
```
pods "pod-name" is forbidden: User "system:serviceaccount:self-healing-platform:self-healing-workbench-dev"
cannot get resource "pods/log" in API group "" in the namespace "self-healing-platform"
```

**Solution**:
```bash
# Verify permission
kubectl auth can-i get pods/log --as=system:serviceaccount:self-healing-platform:self-healing-workbench-dev -n self-healing-platform

# Should return: yes
```

**If NO**: Add to Role in k8s/base/rbac.yaml:
```yaml
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
```

---

### Error 3: Cannot access resource in different namespace
```
pods is forbidden: User "system:serviceaccount:self-healing-platform:self-healing-workbench-dev"
cannot list resource "pods" in API group "" in the namespace "openshift-monitoring"
```

**Solution**:
```bash
# Verify permission in target namespace
kubectl auth can-i list pods --as=system:serviceaccount:self-healing-platform:self-healing-workbench-dev -n openshift-monitoring

# Should return: yes
```

**If NO**: Create Role/RoleBinding in target namespace:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: self-healing-workbench-dev-<namespace>
  namespace: <namespace>
rules:
- apiGroups: [""]
  resources: ["pods", "events", "services"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: self-healing-workbench-dev-<namespace>
  namespace: <namespace>
subjects:
- kind: ServiceAccount
  name: self-healing-workbench-dev
  namespace: self-healing-platform
roleRef:
  kind: Role
  name: self-healing-workbench-dev-<namespace>
  apiGroup: rbac.authorization.k8s.io
```

---

### Error 4: Cannot access cluster-scoped resource
```
namespaces is forbidden: User "system:serviceaccount:self-healing-platform:self-healing-workbench-dev"
cannot list resource "namespaces" in API group "" at the cluster scope
```

**Solution**:
```bash
# Verify permission
kubectl auth can-i list namespaces --as=system:serviceaccount:self-healing-platform:self-healing-workbench-dev

# Should return: yes
```

**If NO**: Add to ClusterRole in k8s/base/rbac.yaml:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: self-healing-workbench-dev-cluster
rules:
- apiGroups: [""]
  resources: ["namespaces", "nodes"]
  verbs: ["get", "list", "watch"]
```

---

## Debugging Steps

### Step 1: Check ServiceAccount exists
```bash
kubectl get sa self-healing-workbench-dev -n self-healing-platform
```

### Step 2: Check Roles exist
```bash
kubectl get role -n self-healing-platform | grep workbench
kubectl get role -n openshift-monitoring | grep workbench
```

### Step 3: Check RoleBindings exist
```bash
kubectl get rolebinding -n self-healing-platform | grep workbench
kubectl get rolebinding -n openshift-monitoring | grep workbench
```

### Step 4: Check ClusterRoles exist
```bash
kubectl get clusterrole | grep workbench
```

### Step 5: Check ClusterRoleBindings exist
```bash
kubectl get clusterrolebinding | grep workbench
```

### Step 6: View full Role definition
```bash
kubectl get role self-healing-workbench-dev -n self-healing-platform -o yaml
```

### Step 7: Test specific permission
```bash
# Test list pods
kubectl auth can-i list pods --as=system:serviceaccount:self-healing-platform:self-healing-workbench-dev -n self-healing-platform

# Test get pod logs
kubectl auth can-i get pods/log --as=system:serviceaccount:self-healing-platform:self-healing-workbench-dev -n self-healing-platform

# Test list namespaces (cluster-scoped)
kubectl auth can-i list namespaces --as=system:serviceaccount:self-healing-platform:self-healing-workbench-dev
```

---

## Quick Fix Workflow

1. **Identify the error** from notebook output
2. **Extract the resource** (e.g., "pods", "pods/log", "namespaces")
3. **Extract the namespace** (e.g., "self-healing-platform", "openshift-monitoring", or cluster-scoped)
4. **Check if permission exists**:
   ```bash
   kubectl auth can-i <verb> <resource> --as=system:serviceaccount:self-healing-platform:self-healing-workbench-dev -n <namespace>
   ```
5. **If NO**: Add rule to appropriate Role/ClusterRole
6. **Apply changes**:
   ```bash
   kubectl apply -f k8s/base/rbac.yaml
   ```
7. **Verify fix**:
   ```bash
   kubectl auth can-i <verb> <resource> --as=system:serviceaccount:self-healing-platform:self-healing-workbench-dev -n <namespace>
   ```
8. **Re-run notebook cell**

---

## Current RBAC Status

**Last Updated**: 2025-10-17 (Commit: 9df76b3c)

✅ **Verified Permissions**:
- [x] List pods in self-healing-platform
- [x] Get pod logs in self-healing-platform
- [x] List events in self-healing-platform
- [x] List pods in openshift-monitoring
- [x] Get pod logs in openshift-monitoring
- [x] List namespaces (cluster-scoped)
- [x] List nodes (cluster-scoped)
- [x] List persistentvolumes (cluster-scoped)
- [x] List storageclasses (cluster-scoped)

---

## Prevention Tips

1. **Always test permissions** before running notebooks
2. **Check error messages carefully** - they tell you exactly what's missing
3. **Use `kubectl auth can-i`** to verify before debugging
4. **Keep RBAC files in sync** - update both k8s/base/rbac.yaml and charts/hub/templates/rbac.yaml
5. **Document new namespaces** - if notebooks need to access new namespaces, add RoleBindings
6. **Review notebooks** - check what resources they access before deployment
