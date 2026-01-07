# ADR-036: Go-Based Standalone MCP Server for OpenShift Cluster Health

## Status
**ACCEPTED** - 2025-12-09
**IN PROGRESS** - Phase 1.4 completed (2025-12-10)
**UPDATED** - 2026-01-07 (Integration with Go Coordination Engine per [ADR-038](038-go-coordination-engine-migration.md))

## Implementation Status

**Standalone Repository**: `/home/lab-user/openshift-cluster-health-mcp`
**Current Phase**: 1.4 (list-pods tool) - ✅ COMPLETED
**Next Phase**: 1.5 (Stateless Cache)

**Completed Deliverables**:
- ✅ **Phase 0**: Project Setup (Go 1.21+, Makefile, Dockerfile, K8s manifests)
- ✅ **Phase 1.1**: MCP Tool - `get-cluster-health` (nodes, pods, deployments)
- ✅ **Phase 1.2**: Kubernetes Client (connection pooling, retry logic, RBAC)
- ✅ **Phase 1.3**: HTTP Transport Layer (OpenShift Lightspeed integration)
- ✅ **Phase 1.4**: MCP Tool - `list-pods` (namespace/label/field selectors)

**Deployment Status**:
- ✅ Running on OpenShift 4.18.21
- ✅ HTTP transport: `http://localhost:8080/mcp`
- ✅ 2 MCP tools operational: `get-cluster-health`, `list-pods`
- ✅ Kubernetes RBAC configured with ClusterRole
- ✅ Live tested with 10+ scenarios across 523 cluster pods

**Architectural Decisions** (10 ADRs in standalone repo):
1. **ADR-001**: Go Language Selection (vs TypeScript)
2. **ADR-002**: Official MCP Go SDK Adoption
3. **ADR-003**: Standalone Architecture (vs Embedded)
4. **ADR-004**: Transport Layer Strategy (HTTP + future SSE)
5. **ADR-005**: Stateless Design (no database)
6. **ADR-006**: Integration Architecture (HTTP REST to Coordination Engine)
7. **ADR-007**: RBAC-Based Security Model
8. **ADR-008**: Distroless Container Images
9. **ADR-009**: Architecture Evolution Roadmap
10. **ADR-010**: Version Compatibility & Upgrade Roadmap

**Documentation**:
- Comprehensive PRD (35KB, 5-week implementation timeline)
- 4 Phase Completion Reports (Phase 0, 1.1, 1.2, 1.3, 1.4)
- Implementation Plan with detailed task breakdown

## Previous Status
Proposed

## Context

### Problem Statement
After analyzing the current TypeScript-based MCP server implementation (`src/mcp-server/`), we've identified several architectural challenges:

1. **Language Ecosystem Misalignment**: TypeScript/Node.js ecosystem doesn't align well with Kubernetes-native tooling and patterns
2. **Complexity Overhead**: Current implementation has 1,589+ lines, 48 dependencies, TypeORM database, workflow orchestration embedded
3. **Limited Reusability**: Tightly coupled to the openshift-aiops-platform project structure
4. **SDK Non-Compliance**: Uses deprecated low-level `Server` API, doesn't fully follow official MCP patterns from [@modelcontextprotocol/sdk](https://github.com/modelcontextprotocol/typescript-sdk)
5. **Maintenance Burden**: Requires maintaining both TypeScript toolchain and Go-based Kubernetes ecosystem

### Research Findings

#### containers/kubernetes-mcp-server (Mature Go Implementation)
- **Repository**: https://github.com/containers/kubernetes-mcp-server
- **Stats**: 856 stars, 194 forks, Apache 2.0 license
- **Language**: Go 89.5%
- **Maturity**: 55 releases, 27 contributors, comprehensive test coverage
- **Features**:
  - **Core Kubernetes**: pods, deployments, services, nodes, events, logs, port-forwarding
  - **Kiali Service Mesh**: application graph, metrics, traces, workload logs, Istio config management
  - **KubeVirt**: VM creation and management (aligned with OpenShift Virtualization)
  - **OpenShift-native**: Built by Red Hat/containers team, production-ready
  - **MCP Compliance**: Uses official Go SDK, supports both stdio and HTTP transports

#### modelcontextprotocol/go-sdk (Official Go SDK)
- **Repository**: https://github.com/modelcontextprotocol/go-sdk
- **Maintainer**: Anthropic (official MCP specification authors)
- **Status**: Active development, follows MCP protocol 2025-03-26
- **Features**: High-level server API, stdio/HTTP transports, tool/resource/prompt registration

### User Goals (from Context)
1. **Standalone Project**: Reusable across multiple OpenShift clusters
2. **Leverage Proven Patterns**: containers/kubernetes-mcp-server as reference architecture
3. **Official SDK Compliance**: Use modelcontextprotocol/go-sdk for protocol implementation
4. **Platform Integration**: Integrate with existing Coordination Engine (Python/Flask) and KServe models
5. **Go Ecosystem Alignment**: Better fit with Kubernetes client libraries, tooling, and patterns

## Decision

**We will create a new standalone Go-based MCP server project** (`openshift-cluster-health-mcp`) as a separate repository, leveraging:

1. **Language**: **Go 1.21+** (instead of TypeScript)
2. **MCP SDK**: **modelcontextprotocol/go-sdk** (official Anthropic SDK)
3. **Architecture Reference**: **containers/kubernetes-mcp-server** patterns and structure
4. **Integration Strategy**: HTTP REST clients to existing services (Coordination Engine, KServe, Prometheus)
5. **Deployment Model**: Standalone Helm chart, independent release cycle

### Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│  OpenShift Cluster Health MCP Server (Go)                │
│  Repository: openshift-cluster-health-mcp                │
├──────────────────────────────────────────────────────────┤
│  MCP Protocol Handler (modelcontextprotocol/go-sdk)      │
│  ├─ Tool: get-cluster-health                             │
│  ├─ Tool: analyze-anomalies (→ KServe predictor)         │
│  ├─ Tool: trigger-remediation (→ Coordination Engine)    │
│  ├─ Tool: list-pods (native K8s API)                     │
│  ├─ Resource: cluster://health (→ Coordination Engine)   │
│  ├─ Resource: cluster://incidents (→ Coordination Engine)│
│  └─ Resource: cluster://nodes (native K8s API)           │
├──────────────────────────────────────────────────────────┤
│  HTTP Clients (Go net/http)                              │
│  ├─ CoordinationEngineClient (REST API)                  │
│  ├─ KServeClient (InferenceService API)                  │
│  ├─ PrometheusClient (PromQL API)                        │
│  └─ KubernetesClient (client-go)                         │
└──────────────────────────────────────────────────────────┘
           │                    │                    │
           │ HTTP REST          │ HTTP REST          │ K8s API
           ▼                    ▼                    ▼
┌────────────────────┐  ┌─────────────────┐  ┌─────────────┐
│ Coordination Engine│  │ KServe Predictor│  │ Kubernetes  │
│ (Python/Flask)     │  │ (ML Models)     │  │ API Server  │
│ - Incidents        │  │ - Anomaly Det.  │  │ - Pods      │
│ - Remediation      │  │ - Predictions   │  │ - Nodes     │
└────────────────────┘  └─────────────────┘  └─────────────┘
```

### Why Go Over TypeScript?

| Criterion | Go | TypeScript | Winner |
|-----------|----|-----------:|--------|
| **Kubernetes Ecosystem** | Native `client-go`, `controller-runtime` | `@kubernetes/client-node` (wrapper) | ✅ Go |
| **Performance** | Compiled binary, low memory (~30MB) | Node.js runtime (~256MB) | ✅ Go |
| **Deployment** | Single binary, no runtime | Requires Node.js runtime | ✅ Go |
| **OpenShift Alignment** | Red Hat's primary language for operators | Used for web UIs | ✅ Go |
| **MCP SDK Maturity** | Official SDK, active development | Official SDK, mature | 🟰 Tie |
| **Existing Codebase** | New project (no legacy) | TypeScript MCP server exists | ⚠️ Migration Cost |
| **Team Expertise** | Kubernetes/OpenShift standard | JavaScript ecosystem | 🟰 Context-dependent |
| **Tooling** | go build, go test, goreleaser | npm, webpack, jest | ✅ Go (simpler) |
| **Containerization** | Distroless images (~10MB) | Node.js base (~100MB+) | ✅ Go |
| **Security** | Smaller attack surface, no npm supply chain | npm dependency vulnerabilities | ✅ Go |

### What We'll Leverage from containers/kubernetes-mcp-server

✅ **Adopt:**
- Go project structure (`cmd/`, `internal/`, `pkg/`)
- MCP tool/resource registration patterns
- Kubernetes client initialization and RBAC patterns
- Helm chart deployment strategy
- Testing approach with mcp-inspector

❌ **Don't Duplicate:**
- Basic Kubernetes tools (pods, nodes, events) - reference or extend
- Port-forwarding, exec functionality - use their implementation
- KubeVirt VM management - optional, only if needed

➕ **Add Custom:**
- `CoordinationEngineClient` for remediation workflows
- `KServeClient` for ML model inference (predictive-analytics-predictor)
- Custom tools: `analyze-anomalies`, `trigger-remediation`
- Custom resources: `cluster://health`, `cluster://incidents`

### Integration Points

| Integration | Protocol | Endpoint | Purpose | Implementation |
|-------------|----------|----------|---------|----------------|
| **Coordination Engine** | HTTP REST | `http://coordination-engine:8080/api/v1/` | Remediation actions, incident management, workflow orchestration | **Go-based** (per [ADR-038](038-go-coordination-engine-migration.md)) |
| **KServe Predictive Model** | HTTP REST | `http://predictive-analytics-predictor:8080/v1/models/predictive-analytics:predict` | Anomaly detection, ML-powered analysis | Python ML service |
| **Prometheus** | HTTP REST | `https://prometheus-k8s.openshift-monitoring.svc:9091/api/v1/query` | Metrics queries, cluster health data | OpenShift monitoring |
| **Kubernetes API** | K8s client-go | In-cluster ServiceAccount | Pods, nodes, events, deployments | Native Go client |
| **OpenShift Lightspeed** | MCP (HTTP) | Bidirectional MCP protocol | Natural language interface | MCP HTTP transport |

## Consequences

### Positive

1. **Ecosystem Alignment**: Go is the native language for Kubernetes/OpenShift tooling
   - Direct access to `client-go`, `controller-runtime`, `apimachinery`
   - Easier contribution from OpenShift/Kubernetes community
   - Better documentation and examples for K8s operations

2. **Reusability**: Standalone project can be deployed on any OpenShift cluster
   - Independent versioning and release cycle
   - No coupling to openshift-aiops-platform deployment
   - Can be contributed to broader open source community

3. **Performance**: Compiled Go binary vs. interpreted Node.js
   - Lower memory footprint (~30MB vs ~256MB)
   - Faster startup time (<1s vs ~5s)
   - Better resource utilization in constrained environments

4. **Proven Architecture**: Leverage 856-star project with production experience
   - Battle-tested patterns from Red Hat containers team
   - Comprehensive test coverage and CI/CD
   - Active maintenance and community support

5. **Simplified Dependencies**: Go modules vs npm dependency tree
   - ~10-15 direct dependencies vs 48+ npm packages
   - No transitive dependency vulnerabilities (npm supply chain attacks)
   - Easier security auditing and compliance

6. **Operational Excellence**: Single binary deployment
   - No Node.js runtime required
   - Smaller container images (distroless ~10MB vs node:alpine ~100MB+)
   - Easier debugging and troubleshooting

### Negative

1. **Migration Cost**: Requires rewriting existing TypeScript MCP server
   - **Mitigation**: Gradual migration, keep TypeScript as interim solution
   - **Mitigation**: Start with minimal viable tools, expand incrementally
   - **Estimate**: 2-3 weeks for MVP with 3-4 core tools

2. **Learning Curve**: If team is TypeScript-heavy, Go may require upskilling
   - **Mitigation**: Leverage containers/kubernetes-mcp-server as reference implementation
   - **Mitigation**: Go is simpler than TypeScript for this use case (no async complexity)
   - **Estimate**: 1 week for TypeScript developers to become productive in Go

3. **Coordination Engine Dependency**: Still requires Python/Flask service to be running
   - **Mitigation**: This is intentional - separation of concerns (MCP protocol vs business logic)
   - **Mitigation**: MCP server can degrade gracefully if Coordination Engine unavailable
   - **Design**: Coordination Engine remains the source of truth for remediation logic

4. **Dual MCP Implementations**: Temporary period with both TypeScript and Go servers
   - **Mitigation**: Clear migration plan, deprecate TypeScript after Go stabilizes
   - **Timeline**: Phase out TypeScript MCP server in 6 months after Go production validation

5. **Less Mature Go MCP SDK**: Go SDK is newer than TypeScript SDK
   - **Mitigation**: Official Anthropic SDK, follows same protocol specification
   - **Evidence**: containers/kubernetes-mcp-server successfully uses Go SDK in production
   - **Risk**: Low - protocol is stable, SDK is officially maintained

### Neutral

1. **Two-Language Stack**: Go MCP server + Python Coordination Engine + TypeScript (legacy)
   - Acceptable for microservices architecture
   - Each service uses the best-fit language for its domain

2. **New Repository Management**: Separate CI/CD, releases, documentation
   - Industry standard for reusable components
   - Allows independent evolution and contribution

## Alternatives Considered

### Alternative 1: Keep TypeScript MCP Server, Refactor to Standards
**Rejected**: While this avoids rewrite cost, it doesn't address:
- Kubernetes ecosystem misalignment (still using Node.js wrapper libraries)
- Performance overhead (Node.js runtime)
- Deployment complexity (npm dependencies, larger images)
- **Key Issue**: Fighting against the ecosystem instead of embracing it

### Alternative 2: Python-Based MCP Server (Align with Coordination Engine)
**Rejected**: Python has challenges for Kubernetes operations:
- Python Kubernetes clients are less mature than Go `client-go`
- Performance overhead similar to Node.js (interpreted language)
- Container images even larger than Node.js
- **Key Issue**: Python is great for Coordination Engine (ML, workflow), but Go is better for K8s API operations

### Alternative 3: Rust-Based MCP Server (Maximum Performance)
**Rejected**: Over-engineering for this use case:
- Steeper learning curve than Go
- Less mature Kubernetes client ecosystem
- Longer development time
- **Key Issue**: Diminishing returns - Go provides sufficient performance with better productivity

### Alternative 4: Fork containers/kubernetes-mcp-server Directly
**Rejected**: Too much scope, different goals:
- Their focus: General Kubernetes tooling (pods, logs, exec, Kiali, KubeVirt)
- Our focus: OpenShift AI Ops platform integration (Coordination Engine, KServe, Prometheus)
- **Decision**: Reference their architecture, add custom tools, avoid duplication

## Implementation Plan

### Phase 1: Repository Setup and MVP (Week 1-2)
```bash
# Repository structure
openshift-cluster-health-mcp/
├── cmd/
│   └── mcp-server/
│       └── main.go                   # Server entry point
├── internal/
│   ├── server/
│   │   └── server.go                 # MCP server setup (Go SDK)
│   ├── tools/                        # MCP tool implementations
│   │   ├── cluster_health.go
│   │   ├── analyze_anomalies.go
│   │   ├── trigger_remediation.go
│   │   └── list_pods.go
│   └── resources/                    # MCP resource handlers
│       ├── cluster_health.go
│       ├── incidents.go
│       └── nodes.go
├── pkg/
│   ├── clients/                      # HTTP clients for integrations
│   │   ├── coordination_engine.go
│   │   ├── kserve.go
│   │   ├── prometheus.go
│   │   └── kubernetes.go
│   └── models/
│       └── types.go                  # Common data structures
├── charts/
│   └── openshift-cluster-health-mcp/ # Helm chart
├── Makefile
├── go.mod
├── go.sum
└── README.md
```

**Deliverables**:
- ✅ Repository initialized with Go modules
- ✅ Basic MCP server with 4 tools (cluster-health, analyze-anomalies, trigger-remediation, list-pods)
- ✅ HTTP clients for Coordination Engine and KServe
- ✅ Unit tests with >80% coverage
- ✅ Dockerfile and Helm chart

### Phase 2: Integration Testing (Week 3)
- ✅ Deploy to dev OpenShift cluster
- ✅ Test with OpenShift Lightspeed integration
- ✅ Verify Coordination Engine API calls
- ✅ Validate KServe predictor integration
- ✅ E2E tests with mcp-inspector

### Phase 3: Production Hardening (Week 4)
- ✅ RBAC configuration (ServiceAccount, ClusterRole, ClusterRoleBinding)
- ✅ Prometheus metrics export
- ✅ Health check endpoints (liveness, readiness)
- ✅ Graceful degradation (if Coordination Engine unavailable)
- ✅ Security scanning (gosec, trivy)
- ✅ Performance benchmarking

### Phase 4: Documentation and Release (Week 5)
- ✅ API documentation (tools, resources, integration points)
- ✅ Deployment guide (Helm chart, RBAC, configuration)
- ✅ Migration guide from TypeScript MCP server
- ✅ GitHub release with binaries and Helm chart
- ✅ Quay.io container image publication

### Phase 5: TypeScript Deprecation (Month 2-6)
- ✅ Run both MCP servers in parallel for validation
- ✅ Migrate all Lightspeed integrations to Go server
- ✅ Deprecate TypeScript MCP server
- ✅ Archive TypeScript implementation with migration notes

## Related ADRs

- **ADR-014**: [Cluster Health MCP Server for OpenShift Lightspeed Integration](014-openshift-aiops-platform-mcp-server.md) - **SUPERSEDED** by this ADR
- **ADR-015**: [Service Separation - MCP Server vs REST API](015-service-separation-mcp-vs-rest-api.md) - **STILL VALID** - Coordination Engine remains REST API layer, both now Go-based
- **ADR-038**: [Migration from Python to Go Coordination Engine](038-go-coordination-engine-migration.md) - **NEW (2026-01-07)** - Coordination Engine now Go-based, optimized Go-to-Go communication
- **ADR-002**: [Hybrid Deterministic-AI Self-Healing Approach](002-hybrid-self-healing-approach.md) - Integration point for remediation workflows
- **ADR-004**: [KServe for Model Serving Infrastructure](004-kserve-model-serving.md) - Integration point for ML inference

## References

### External Projects
- **containers/kubernetes-mcp-server**: https://github.com/containers/kubernetes-mcp-server
  - Go implementation, 856 stars, Apache 2.0
  - Reference architecture for project structure
- **modelcontextprotocol/go-sdk**: https://github.com/modelcontextprotocol/go-sdk
  - Official Anthropic Go SDK
  - MCP protocol 2025-03-26 compliance
- **Model Context Protocol Specification**: https://spec.modelcontextprotocol.io/
  - Protocol specification for MCP
- **Red Hat OpenShift Lightspeed**: https://docs.openshift.com/lightspeed/
  - MCP client integration documentation

### Internal Documentation
- `src/mcp-server/` - Current TypeScript implementation (to be deprecated)
- `src/coordination-engine/` - Python/Flask REST API service
- `notebooks/06-mcp-lightspeed-integration/` - Integration testing notebooks
- `charts/hub/templates/mcp-server-*.yaml` - Current deployment manifests

## Decision Metadata

- **Proposed**: 2025-12-09
- **Proposed By**: Platform Architecture Team
- **Reviewed By**: [Pending]
- **Research Conducted**: 2025-12-09 (containers/kubernetes-mcp-server analysis, Go SDK evaluation)
- **Confidence Level**: High (90%)
  - Proven reference implementation (kubernetes-mcp-server)
  - Official SDK support (modelcontextprotocol/go-sdk)
  - Clear migration path and timeline
  - Strong ecosystem alignment

## Success Criteria

1. **Functional**: All tools from TypeScript MCP server replicated in Go
2. **Performance**: <100ms p95 response time for tools, <50MB memory at rest
3. **Integration**: Successful OpenShift Lightspeed integration
4. **Reliability**: >99.9% uptime, graceful degradation if dependencies unavailable
5. **Adoption**: Deployed to 3+ OpenShift clusters within 3 months
6. **Community**: Open source contribution, external adoption by other OpenShift users

---

**Next Steps**:
1. **Review and approve this ADR** with platform team
2. **Create new repository**: `openshift-cluster-health-mcp`
3. **Start Phase 1 implementation** (MVP with 4 tools)
4. **Update openshift-aiops-platform integration** to reference external MCP server
