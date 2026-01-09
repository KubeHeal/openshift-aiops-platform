# ADR-033: Coordination Engine RBAC Permissions

**Status**: DEPRECATED (Python coordination engine removed - see ADR-038)
**Date**: 2025-10-17
**Deprecated**: 2026-01-09
**Renumbered From**: Originally ADR-025 (renumbered 2025-11-19 to standardize naming)
**Author**: Platform Team
**Relates to**: ADR-001, ADR-008, ADR-012, ADR-038

> **Note**: This ADR is specific to the Python-based coordination engine which has been replaced by the Go-based engine from https://github.com/tosin2013/openshift-coordination-engine. This document is retained for historical reference only.

## Problem Statement

The coordination engine pod (`coordination-engine-678b76f77c-zwmct`) is receiving HTTP 403 Forbidden errors when attempting to access the Kubernetes API:

```
2025-10-17 18:52:29,541 - __main__ - WARNING - K8s API connectivity check failed: (403)
Reason: Forbidden
```

This prevents the coordination engine from:
- Querying pod status and metrics
- Monitoring cluster health
- Detecting anomalies in resource utilization
- Executing healing actions on pods/deployments

## Root Cause Analysis

The coordination engine uses the `self-healing-operator` ServiceAccount, which has a Role with limited permissions. The 403 errors indicate missing RBAC permissions for specific API resources or verbs needed by the coordination engine.

### Current RBAC Configuration

**ServiceAccount**: `self-healing-operator`

**Current Role Permissions**:
- Core API: pods, services, configmaps, secrets, events (get, list, watch, create, update, patch, delete)
- Namespaces, nodes (get, list, watch)
- Apps API: deployments, replicasets, daemonsets, statefulsets (get, list, watch, create, update, patch, delete)
- Monitoring: servicemonitors, prometheusrules (get, list, watch, create, update, patch, delete)
- KServe: inferenceservices (get, list, watch, create, update, patch, delete)
- Kubeflow: notebooks (get, list, watch, create, update, patch, delete)
- Machine Configuration: machineconfigs, machineconfigpools (get, list, watch)

## Decision

We will enhance the RBAC configuration for the coordination engine by:

1. **Adding missing resource permissions**:
   - `persistentvolumes` and `persistentvolumeclaims` (get, list, watch)
   - `storageclasses` (get, list, watch)
   - `endpoints` (get, list, watch)
   - `leases` (get, list, watch, create, update, patch, delete) - for leader election

2. **Adding missing API groups**:
   - `batch` API: jobs, cronjobs (get, list, watch, create, update, patch, delete)
   - `policy` API: poddisruptionbudgets (get, list, watch)
   - `autoscaling` API: horizontalpodautoscalers (get, list, watch)
   - `networking.k8s.io` API: networkpolicies (get, list, watch)

3. **Implementing least-privilege access**:
   - Create separate roles for read-only operations vs. healing actions
   - Use RoleBindings to scope permissions to the self-healing-platform namespace
   - Document which permissions are required for each healing action

4. **Adding audit logging**:
   - Enable audit logging for all API calls made by the coordination engine
   - Track which resources are accessed and modified
   - Monitor for permission denials

## Implementation

### Step 1: Update RBAC Role

Update `charts/hub/templates/rbac.yaml` and `k8s/base/rbac.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: self-healing-operator
rules:
# Core API resources
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets", "events"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["namespaces", "nodes", "endpoints"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["persistentvolumes", "persistentvolumeclaims"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["leases"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Apps API resources
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "daemonsets", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Batch API resources
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Autoscaling resources
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list", "watch"]

# Policy resources
- apiGroups: ["policy"]
  resources: ["poddisruptionbudgets"]
  verbs: ["get", "list", "watch"]

# Networking resources
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "list", "watch"]

# Storage resources
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]

# Monitoring resources
- apiGroups: ["monitoring.coreos.com"]
  resources: ["servicemonitors", "prometheusrules"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# KServe resources
- apiGroups: ["serving.kserve.io"]
  resources: ["inferenceservices"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Kubeflow resources
- apiGroups: ["kubeflow.org"]
  resources: ["notebooks"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Machine configuration resources
- apiGroups: ["machineconfiguration.openshift.io"]
  resources: ["machineconfigs", "machineconfigpools"]
  verbs: ["get", "list", "watch"]
```

### Step 2: Test Permissions

After applying the updated RBAC:

```bash
# Test pod access
kubectl auth can-i get pods --as=system:serviceaccount:self-healing-platform:self-healing-operator -n self-healing-platform

# Test deployment access
kubectl auth can-i patch deployments --as=system:serviceaccount:self-healing-platform:self-healing-operator -n self-healing-platform

# Test job access
kubectl auth can-i create jobs --as=system:serviceaccount:self-healing-platform:self-healing-operator -n self-healing-platform
```

### Step 3: Monitor Coordination Engine

After applying RBAC changes:

```bash
# Check coordination engine logs
kubectl logs -f deployment/coordination-engine -n self-healing-platform

# Verify health endpoint
kubectl port-forward svc/coordination-engine 8080:8080 -n self-healing-platform
curl http://localhost:8080/health
```

## Consequences

### Positive
- ✅ Coordination engine can access all required Kubernetes resources
- ✅ Healing actions can be executed on pods, deployments, and jobs
- ✅ Cluster health monitoring works correctly
- ✅ Anomaly detection can query resource metrics
- ✅ Leader election works for HA deployments

### Negative
- ⚠️ Broader permissions increase security surface area
- ⚠️ Requires careful monitoring of API access patterns
- ⚠️ Must implement audit logging to track permission usage

### Mitigation
- Use namespace-scoped Roles (not ClusterRoles) to limit scope
- Implement RBAC audit logging
- Regular security reviews of permission usage
- Document which permissions are used by each healing action

## Alternatives Considered

1. **Use ClusterRole instead of Role**
   - Rejected: Too broad, violates least-privilege principle
   - Would grant permissions across all namespaces

2. **Create separate ServiceAccounts for different functions**
   - Considered: Could separate read-only vs. write operations
   - Deferred: Adds complexity, revisit if needed

3. **Use OpenShift-specific RBAC**
   - Considered: OpenShift has additional RBAC features
   - Deferred: Keep Kubernetes-compatible for portability

## Related ADRs

- **ADR-001**: Kubernetes-Native Architecture
- **ADR-008**: Security and RBAC Strategy
- **ADR-012**: Notebook Architecture for End-to-End Workflows

## Testing Strategy

1. Unit tests for RBAC permission validation
2. Integration tests for coordination engine API access
3. E2E tests for healing action execution
4. Security audit of permission usage

## Deployment Checklist

- [ ] Update RBAC configuration in charts/hub/templates/rbac.yaml
- [ ] Update RBAC configuration in k8s/base/rbac.yaml
- [ ] Apply changes to cluster: `kubectl apply -f k8s/base/rbac.yaml`
- [ ] Verify permissions: `kubectl auth can-i ...`
- [ ] Check coordination engine logs for 403 errors
- [ ] Test health endpoint
- [ ] Monitor audit logs for permission usage
- [ ] Document any additional permissions needed

## References

- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [OpenShift RBAC Guide](https://docs.openshift.com/container-platform/latest/authentication/using-rbac.html)
- [Kubernetes API Groups](https://kubernetes.io/docs/reference/using-api/api-overview/#api-groups)
