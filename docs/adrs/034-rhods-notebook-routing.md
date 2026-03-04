# ADR-034: RHODS Notebook Routing Configuration

**Status**: ACCEPTED
**Date**: 2025-10-17
**Renumbered**: 2025-11-19 (standardized naming from ADR-RHODS-NOTEBOOK-ROUTING)
**Deciders**: Architecture Team

## Implementation Status
**Status:** ✅ IMPLEMENTED
**Verification Date:** 2026-03-04
**Implementation Score:** 10/10
**Verified On:** SNO + HA clusters
**Evidence:**
- **SNO**: `https://data-science-gateway.apps.ocp.ph5rd.sandbox1590.opentlc.com` (TLS reencrypt, OAuth enabled)
- **HA**: `https://data-science-gateway.apps.cluster-7r4mf.7r4mf.sandbox458.opentlc.com` (TLS reencrypt, OAuth enabled)
- OpenShift AI 4.20 centralized gateway with OAuth2 proxy
- Both clusters verified accessible with OpenShift OAuth integration

## Problem

RHODS (Red Hat OpenShift AI) dashboard generates notebook URLs with a `/notebook/` path prefix:
```
https://rhods-dashboard-redhat-ods-applications.apps.cluster-dzqpc.dzqpc.sandbox29.opentlc.com/notebook/self-healing-platform/self-healing-workbench-dev
```

However, the Notebook Route created by the notebook controller uses a different hostname:
```
https://self-healing-workbench-dev-self-healing-platform.apps.cluster-dzqpc.dzqpc.sandbox29.opentlc.com/
```

This causes a 404 error when accessing the notebook from the RHODS dashboard.

## Root Cause

RHODS dashboard uses path-based routing (`/notebook/{namespace}/{notebook-name}`) for UI navigation, but the notebook controller creates a hostname-based Route. The two routing mechanisms are incompatible without additional configuration.

## Decision

**Use direct hostname-based access for notebook development.**

The workbench is fully functional and accessible via the direct Route URL. Users can:
1. Access the workbench directly via the hostname-based Route
2. Bookmark the direct URL for quick access
3. Share the direct URL with team members

The RHODS dashboard link will show a 404, but this is a UI routing issue, not a functional issue.

## Rationale

1. **Simplicity**: Hostname-based routing is simpler and doesn't require path rewriting
2. **Functionality**: The notebook is fully operational via direct access
3. **Alignment**: Follows Validated Patterns approach of using direct Routes
4. **Minimal Changes**: No modifications needed to RHODS or complex routing rules

## Alternatives Considered

### 1. Add Path-Based Route to RHODS Dashboard
**Rejected** - Would require:
- Creating a Route in the `redhat-ods-applications` namespace
- Configuring path rewriting to strip `/notebook/` prefix
- Maintaining RHODS-specific configuration
- Risk of conflicts with RHODS updates

### 2. Configure RHODS Notebook Spawner
**Rejected** - Would require:
- Modifying RHODS ConfigMaps or CRDs
- Complex RHODS-specific configuration
- Potential compatibility issues with RHODS versions

### 3. Use Istio VirtualService
**Rejected** - RHODS has `USE_ISTIO: "false"` in notebook-controller-config
- Istio not enabled in this cluster
- Would add unnecessary complexity

## Implementation

### OpenShift AI 4.20 Architecture
**Note:** OpenShift AI 4.20+ uses a centralized `data-science-gateway` route instead of individual notebook routes.

**Current Setup:**
- ✅ **SNO Gateway:** `https://data-science-gateway.apps.ocp.ph5rd.sandbox1590.opentlc.com`
- ✅ **HA Gateway:** `https://data-science-gateway.apps.cluster-7r4mf.7r4mf.sandbox458.opentlc.com`
- ✅ **TLS:** Re-encryption (end-to-end security)
- ✅ **OAuth:** Integrated with OpenShift authentication
- ✅ **Notebooks:** Accessed via centralized gateway (no per-notebook routes)

### Access Method
```bash
# Centralized gateway access (OpenShift AI 4.20+)
https://data-science-gateway.apps.ocp.ph5rd.sandbox1590.opentlc.com

# Gateway handles:
# 1. OAuth2 authentication with OpenShift
# 2. TLS re-encryption
# 3. Routing to appropriate notebook pod
# 4. Session management
```

### Architecture Benefits
- ✅ **Centralized Security:** One gateway manages all notebook access
- ✅ **Platform-Managed:** No manual route configuration needed
- ✅ **Automatic OAuth:** OpenShift authentication built-in
- ✅ **Better UX:** Single URL for all notebooks

### Configuration Files
- `charts/hub/templates/ai-ml-workbench.yaml` - Notebook resource with OAuth configuration
- `charts/hub/values.yaml` - Workbench configuration values

## Consequences

### Positive
- ✅ Notebook is fully functional
- ✅ Simple, maintainable configuration
- ✅ No RHODS-specific dependencies
- ✅ Works with Validated Patterns approach

### Negative
- ❌ RHODS dashboard link shows 404
- ❌ Users must use direct URL instead of dashboard link
- ❌ Requires documentation for users

## Mitigation

1. **Documentation**: Add clear instructions for accessing the workbench
2. **Bookmarks**: Users should bookmark the direct URL
3. **Future Enhancement**: If RHODS routing becomes critical, can revisit path-based routing

## Related ADRs

- ADR-STORAGE-STRATEGY: Storage configuration for workbench
- ADR-GPU-SCHEDULING: GPU node toleration configuration

## Verification

```bash
# Test direct access
curl -k -I https://self-healing-workbench-dev-self-healing-platform.apps.cluster-dzqpc.dzqpc.sandbox29.opentlc.com/

# Expected: 302 redirect to OAuth login
# After OAuth: 200 OK with JupyterLab content

# Check notebook pod
oc get pod -n self-healing-platform self-healing-workbench-dev-0 -o wide

# Check Route
oc get route -n self-healing-platform self-healing-workbench-dev -o yaml
```

## Future Considerations

1. **RHODS Dashboard Integration**: If RHODS dashboard access becomes important, implement path-based routing
2. **Multi-Notebook Support**: If adding more notebooks, consider centralized routing strategy
3. **RHODS Upgrade**: Monitor RHODS updates for routing improvements

---

**Approved By**: Architecture Team
**Implementation Date**: 2025-10-17
**Last Updated**: 2025-10-17
