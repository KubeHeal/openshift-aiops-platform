# GitHub Issues for OpenShift AI Ops Platform

This directory contains GitHub issue templates for implementing features and fixing bugs across the OpenShift AI Ops platform.

## Overview

These issues cover:
- **Bug Fixes**: Critical bugs blocking end-to-end self-healing demo
- **Feature Engineering**: ML model integration with MCP server and coordination engine
- **Prediction Tools**: Time-specific predictions, capacity planning, scaling analysis
- **Infrastructure monitoring**: Works for any pod (applications + OpenShift infrastructure)

---

## 🔴 Critical Bug Fixes (Blocking E2E Demo)

These issues must be fixed before the end-to-end self-healing demo works:

### 1. MCP Server: KServe URL Bug
**File**: [`mcp-server-kserve-url-bug.md`](./mcp-server-kserve-url-bug.md)
- **Problem**: KServe client uses model name instead of literal "model" in URL path
- **Impact**: 404 errors when calling ML models
- **Fix**: Change URL from `.../models/{modelName}:predict` to `.../models/model:predict`
- **Priority**: 🔴 **Critical**

### 2. MCP Server: Feature Engineering Missing
**File**: [`mcp-server-anomaly-detection-feature-engineering.md`](./mcp-server-anomaly-detection-feature-engineering.md)
- **Problem**: Sends metadata instead of 45 numeric features to anomaly-detector model
- **Impact**: Model receives wrong input format, returns errors
- **Fix**: Implement Prometheus queries + feature engineering in MCP server or coordination engine
- **Priority**: 🔴 **Critical**

### 3. Coordination Engine: Add Anomaly Analysis Endpoint
**File**: [`coordination-engine-anomaly-analysis-endpoint.md`](./coordination-engine-anomaly-analysis-endpoint.md)
- **Problem**: No centralized endpoint for anomaly analysis with feature engineering
- **Impact**: MCP server cannot properly call ML models
- **Fix**: Add `/api/v1/anomalies/analyze` endpoint with feature engineering
- **Priority**: 🔴 **Critical**

### 4. Coordination Engine: Flexible Model Response Parsing ⭐ NEW
**File**: [`coordination-engine-flexible-model-response-parsing.md`](./coordination-engine-flexible-model-response-parsing.md)
- **Problem**: Cannot use custom sklearn wrappers (pickle class not available at inference)
- **Root Cause**: KServe sklearn runtime doesn't have custom class definitions
- **Impact**: Models must output nested format manually or coordination engine must handle array format
- **Fix**: Update `parseForecastResponse()` to handle both nested and array formats
- **Priority**: 🔴 **Critical** (Blocking E2E demo)

### 5. Coordination Engine: Type Mismatch Bug (Superseded by #4)
**File**: [`coordination-engine-prediction-type-mismatch.md`](./coordination-engine-prediction-type-mismatch.md)
- **Problem**: Cannot parse model response - expects int, gets dict
- **Impact**: Prediction API returns 503 errors
- **Fix**: Update Go struct to handle both int and dict response types
- **Note**: Issue #4 provides a more comprehensive fix that includes this
- **Priority**: 🟠 **High**

### 6. MCP Server: Tool Default Behavior
**File**: [`mcp-server-tool-default-behavior.md`](./mcp-server-tool-default-behavior.md)
- **Problem**: LLM asks clarifying questions instead of using defaults
- **Impact**: Poor user experience, requires extra interaction
- **Fix**: Update tool description to guide LLM to use defaults
- **Priority**: 🟡 **Medium**

---

## Issue Templates (Features)

### openshift-cluster-health-mcp (4 issues)

**Repository**: https://github.com/tosin2013/openshift-cluster-health-mcp

**File**: [`mcp-server-prediction-tools.md`](./mcp-server-prediction-tools.md)

1. **Issue 1**: Add `predict-resource-usage` MCP Tool
   - Time-specific resource forecasting
   - Supports pod, deployment, namespace, cluster scopes
   - Priority: **HIGH** (Phase 1 - Quick Win)

2. **Issue 2**: Add `analyze-scaling-impact` MCP Tool
   - Replica scaling impact analysis
   - Infrastructure impact assessment
   - Priority: **MEDIUM** (Phase 3)

3. **Issue 3**: Add `calculate-pod-capacity` MCP Tool
   - Namespace/cluster capacity planning
   - Pod profile estimates (small/medium/large)
   - Trending analysis
   - Priority: **MEDIUM** (Phase 2)

4. **Issue 4**: Enhance `analyze-anomalies` Tool
   - Add deployment/pod filtering
   - Label selector support
   - Priority: **HIGH** (Phase 1 - Quick Win)

### openshift-coordination-engine (3 issues)

**Repository**: https://github.com/tosin2013/openshift-coordination-engine

**File**: [`coordination-engine-prediction-apis.md`](./coordination-engine-prediction-apis.md)

1. **Issue 1**: Add `/api/v1/predict` Endpoint
   - Time-specific resource predictions
   - KServe ML model integration
   - Scoped queries (pod/deployment/namespace/cluster)
   - Priority: **HIGH** (Phase 1 - Required for MCP tool)

2. **Issue 2**: Add `/api/v1/capacity/namespace` Endpoint
   - Namespace/cluster capacity analysis
   - Trending data (7d/30d windows)
   - Infrastructure impact metrics
   - Priority: **MEDIUM** (Phase 2)

3. **Issue 3**: Enhance Prometheus Client
   - Scoped query builder
   - Trending analysis calculations
   - Infrastructure metrics (etcd, API server, scheduler)
   - Priority: **HIGH** (Phase 1 - Required for endpoints)

## How to Create Issues

### Option 1: Copy & Paste Individual Issues

1. Navigate to the respective repository
2. Click "Issues" → "New issue"
3. Copy the issue content from the markdown file
4. Paste into the issue description
5. Add appropriate labels (shown in each issue)
6. Submit

### Option 2: Use GitHub CLI

```bash
# For MCP Server repository
cd /path/to/openshift-cluster-health-mcp

# Create Issue 1: predict-resource-usage
gh issue create --title "Add predict-resource-usage MCP Tool for Time-Specific Forecasting" \
  --body-file /home/lab-user/openshift-aiops-platform/docs/github-issues/mcp-server-prediction-tools.md \
  --label enhancement,mcp-tool,prediction,ml-integration

# Create Issue 2: analyze-scaling-impact
gh issue create --title "Add analyze-scaling-impact MCP Tool for Replica Scaling Analysis" \
  --body-file <(sed -n '/^## Issue 2:/,/^## Issue 3:/p' /home/lab-user/openshift-aiops-platform/docs/github-issues/mcp-server-prediction-tools.md) \
  --label enhancement,mcp-tool,capacity-planning,scaling

# ... and so on for each issue
```

### Option 3: Script to Create All Issues

```bash
#!/bin/bash
# create-all-issues.sh

# MCP Server Issues
cd /path/to/openshift-cluster-health-mcp

gh issue create --title "Add predict-resource-usage MCP Tool" \
  --label enhancement,mcp-tool,prediction,ml-integration \
  --body "See: docs/github-issues/mcp-server-prediction-tools.md - Issue 1"

gh issue create --title "Add analyze-scaling-impact MCP Tool" \
  --label enhancement,mcp-tool,capacity-planning,scaling \
  --body "See: docs/github-issues/mcp-server-prediction-tools.md - Issue 2"

gh issue create --title "Add calculate-pod-capacity MCP Tool" \
  --label enhancement,mcp-tool,capacity-planning,quota-management \
  --body "See: docs/github-issues/mcp-server-prediction-tools.md - Issue 3"

gh issue create --title "Enhance analyze-anomalies with Deployment/Pod Filtering" \
  --label enhancement,mcp-tool,filtering,existing-tool \
  --body "See: docs/github-issues/mcp-server-prediction-tools.md - Issue 4"

# Coordination Engine Issues
cd /path/to/openshift-coordination-engine

gh issue create --title "Add /api/v1/predict Endpoint" \
  --label enhancement,api,ml-integration,prediction \
  --body "See: docs/github-issues/coordination-engine-prediction-apis.md - Issue 1"

gh issue create --title "Add /api/v1/capacity/namespace Endpoint" \
  --label enhancement,api,capacity-planning,quota-management \
  --body "See: docs/github-issues/coordination-engine-prediction-apis.md - Issue 2"

gh issue create --title "Enhance Prometheus Client" \
  --label enhancement,prometheus,metrics,infrastructure \
  --body "See: docs/github-issues/coordination-engine-prediction-apis.md - Issue 3"
```

## Implementation Priority

### Phase 1: Quick Wins (1-2 weeks)

**MCP Server**:
- ✅ Issue 4: Enhance `analyze-anomalies` (add deployment/pod filters)
- ✅ Issue 1: Add `predict-resource-usage` tool

**Coordination Engine**:
- ✅ Issue 3: Enhance Prometheus client (scoped queries)
- ✅ Issue 1: Add `/api/v1/predict` endpoint

**Outcome**: Enable time-specific predictions via Lightspeed

### Phase 2: Capacity Planning (2-3 weeks)

**MCP Server**:
- ✅ Issue 3: Add `calculate-pod-capacity` tool

**Coordination Engine**:
- ✅ Issue 2: Add `/api/v1/capacity/namespace` endpoint
- ✅ Issue 3: Enhance Prometheus client (trending analysis)

**Outcome**: Enable capacity planning via Lightspeed

### Phase 3: Advanced Features (3-4 weeks)

**MCP Server**:
- ✅ Issue 2: Add `analyze-scaling-impact` tool

**Outcome**: Full scaling impact analysis

## Testing Strategy

### Unit Tests
- All new tools and endpoints must have >80% code coverage
- Mock Prometheus, KServe, and Kubernetes clients
- Test all scopes: pod, deployment, namespace, cluster

### Integration Tests
- Test with real OpenShift cluster
- Test with infrastructure pods (openshift-*, kube-system)
- Test with application pods
- Test end-to-end with Lightspeed

### Example Lightspeed Queries to Test

**After Phase 1**:
```
"What will CPU be at 3 PM today?"
"Predict memory usage for my flask app tomorrow at 9 AM"
"What will openshift-monitoring namespace resources be at midnight?"
```

**After Phase 2**:
```
"How many more pods can I run?"
"Do I have capacity for 10 medium-sized pods?"
"What's the cluster capacity remaining?"
```

**After Phase 3**:
```
"If I scale to 5 replicas, what happens?"
"Impact of scaling my logging pods to 20?"
"Can the cluster handle scaling my app to 100 replicas?"
```

## Related Documentation

- **Implementation Plan**: [`docs/implementation-plan-prediction-features.md`](../implementation-plan-prediction-features.md)
- **Blog Post**: [`docs/blog/16-end-to-end-self-healing-with-lightspeed.md`](../blog/16-end-to-end-self-healing-with-lightspeed.md)
- **ADR-036**: Go-Based MCP Server
- **ADR-038**: Go Coordination Engine Migration

## Issue Dependencies

```
MCP Server Issues:
├── Issue 4: analyze-anomalies enhancement (INDEPENDENT)
├── Issue 1: predict-resource-usage
│   └── Depends on: Coordination Engine Issue 1 + 3
├── Issue 3: calculate-pod-capacity
│   └── Depends on: Coordination Engine Issue 2 + 3
└── Issue 2: analyze-scaling-impact
    └── Depends on: Coordination Engine Issue 2 + 3

Coordination Engine Issues:
├── Issue 3: Prometheus client enhancement (INDEPENDENT)
├── Issue 1: /api/v1/predict endpoint
│   └── Depends on: Issue 3 (Prometheus client)
└── Issue 2: /api/v1/capacity/namespace endpoint
    └── Depends on: Issue 3 (Prometheus client)
```

## Success Criteria

### Phase 1 Complete
- [ ] `predict-resource-usage` tool returns accurate forecasts
- [ ] Lightspeed can answer "What will CPU be at X time?"
- [ ] Works for application and infrastructure pods
- [ ] Response time < 500ms

### Phase 2 Complete
- [ ] `calculate-pod-capacity` tool returns accurate estimates
- [ ] Lightspeed can answer "How many more pods?"
- [ ] Trending analysis shows accurate projections
- [ ] Response time < 300ms

### Phase 3 Complete
- [ ] `analyze-scaling-impact` tool calculates accurate impacts
- [ ] Lightspeed can answer "What if I scale to N replicas?"
- [ ] Infrastructure impact analysis working
- [ ] Response time < 500ms

### Overall Success
- [ ] All Lightspeed queries in blog Part 3 work correctly
- [ ] 100+ end-to-end tests passing
- [ ] Documentation complete
- [ ] Production deployment successful

## Bug Fix Priority Order

For the end-to-end self-healing demo to work, fix in this order:

```
1. MCP Server: KServe URL Bug (quick fix - 1 line change)
   └── Enables: Model calls to succeed
   
2. Coordination Engine: Flexible Model Response Parsing ⭐ NEW
   └── Enables: Handle both array [[cpu,mem]] and nested {cpu_usage:...} formats
   └── Root Cause: Pickle requires class definitions at deserialization (KServe doesn't have custom classes)
   └── Supersedes: Type Mismatch Bug (provides comprehensive fix)
   
3. Coordination Engine: Add Anomaly Analysis Endpoint (medium effort)
   └── Enables: Centralized feature engineering for anomaly detection
   └── Depends on: #1, #2 working
   
4. MCP Server: Update to call Coordination Engine (small change)
   └── Enables: End-to-end anomaly detection flow
   └── Depends on: #3 working
   
5. MCP Server: Tool Default Behavior (enhancement)
   └── Improves: User experience with default parameters
```

## Questions or Issues?

- **Implementation Questions**: See [`docs/implementation-plan-prediction-features.md`](../implementation-plan-prediction-features.md)
- **Architecture Questions**: See ADRs in `docs/adrs/`
- **MCP Server**: https://github.com/tosin2013/openshift-cluster-health-mcp
- **Coordination Engine**: https://github.com/tosin2013/openshift-coordination-engine
- **Platform Repo**: https://github.com/tosin2013/openshift-aiops-platform
