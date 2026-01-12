# GitHub Issues for Prediction & Capacity Planning Features

This directory contains GitHub issue templates for implementing prediction and capacity planning features across the OpenShift AI Ops platform.

## Overview

These features enable OpenShift Lightspeed to answer natural language questions about:
- **Time-specific predictions**: "What will CPU be at 3 PM?"
- **Scaling impact**: "If I scale to 5 replicas, what happens?"
- **Capacity planning**: "How many more pods can I run?"
- **Infrastructure monitoring**: Works for any pod (applications + OpenShift infrastructure)

## Issue Templates

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
- **Blog Post**: [`docs/blog/end-to-end-self-healing-with-lightspeed.md`](../blog/end-to-end-self-healing-with-lightspeed.md)
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

## Questions or Issues?

- **Implementation Questions**: See [`docs/implementation-plan-prediction-features.md`](../implementation-plan-prediction-features.md)
- **Architecture Questions**: See ADRs in `docs/adrs/`
- **MCP Server**: https://github.com/tosin2013/openshift-cluster-health-mcp
- **Coordination Engine**: https://github.com/tosin2013/openshift-coordination-engine
- **Platform Repo**: https://github.com/tosin2013/openshift-aiops-platform
