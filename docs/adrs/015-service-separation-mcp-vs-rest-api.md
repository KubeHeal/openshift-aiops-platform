# ADR-015: Service Separation - MCP Server vs REST API Service

## Status
**SUPERSEDED** - 2025-12-09 by [ADR-036: Go-Based Standalone MCP Server](036-go-based-standalone-mcp-server.md)
**UPDATED** - 2026-01-07 (Both MCP server AND Coordination Engine now Go-based per [ADR-038](038-go-coordination-engine-migration.md))

**Previous Status**:
- ~~ACCEPTED - 2025-10-13~~

## Supersession Notice

This ADR documented service separation principles for the TypeScript-based MCP server embedded in `openshift-aiops-platform`.

**Current Architecture (2026-01-07)**:
- **MCP Server**: Go-based standalone service (ADR-036)
- **Coordination Engine**: Go-based standalone service (ADR-038)
- **Integration**: HTTP REST APIs between services
- **Benefit**: Optimized Go-to-Go communication with consistent ecosystem

**These concerns are now addressed** through:

1. **Clear Architectural Separation**: MCP server is now a standalone project, Coordination Engine remains separate
2. **HTTP REST Integration**: MCP server integrates with platform via HTTP REST APIs (no tight coupling)
3. **Independent Deployment**: Each service deployed independently with its own lifecycle
4. **Protocol Clarity**: MCP protocol for Lightspeed, HTTP REST for inter-service communication
5. **Stateless Design**: No shared database, no mixed concerns

**Principles Preserved in ADR-036**:
| ADR-015 Principle | ADR-036 Implementation |
|-------------------|------------------------|
| Single Responsibility | ✅ MCP server only handles MCP protocol |
| Protocol Alignment | ✅ HTTP transport for MCP, REST for integration |
| Deployment Flexibility | ✅ Standalone deployment, independent scaling |
| Maintenance Clarity | ✅ Separate repositories, clear boundaries |
| No Mixed Concerns | ✅ No database, no workflow orchestration |

**See Also**:
- [ADR-036](036-go-based-standalone-mcp-server.md) - Go-based MCP server architecture
- [ADR-038](038-go-coordination-engine-migration.md) - Go-based coordination engine migration
- Standalone repo ADR-003 (MCP Server) and ADR-006 (Integration Architecture)

---

**Historical Documentation Below** (for archival purposes only)

## Context

During the implementation of ADR-014 (Cluster Health MCP Server), we initially mixed concerns by attempting to add Express.js HTTP endpoints to the MCP server. This violated MCP architectural principles and created confusion about service boundaries.

### Current Architecture Issues

1. **Mixed Concerns**: The MCP server in `src/mcp-server/` was incorrectly designed with Express.js endpoints
2. **Protocol Confusion**: MCP servers communicate via stdio, not HTTP
3. **Architectural Violation**: MCP SDK is designed for stdio transport, not REST APIs
4. **Maintenance Complexity**: Single service trying to serve two different protocols

### MCP Server Requirements (from ADR-014)

- **stdio Communication**: MCP servers communicate with clients via standard input/output
- **MCP Protocol**: Uses structured MCP protocol messages, not HTTP requests
- **OpenShift Lightspeed Integration**: Lightspeed connects to MCP servers via stdio transport
- **Pure MCP Implementation**: Should only implement MCP resources and tools

### Potential REST API Requirements

If we need HTTP endpoints for:
- **Prometheus Metrics Scraping**: `/metrics` endpoint for monitoring
- **Health Checks**: `/health` endpoint for Kubernetes probes
- **External Integrations**: REST APIs for third-party tools
- **Dashboard/UI**: Web interface for platform management

## Decision

**Separate concerns into two distinct services**:

### 1. Pure MCP Server (`src/mcp-server/`)
- **Purpose**: OpenShift Lightspeed integration via MCP protocol
- **Communication**: stdio transport only
- **Responsibilities**:
  - MCP resources: `cluster://health`, `cluster://incidents`, `cluster://nodes`
  - MCP tools: `trigger-remediation`, `analyze-anomalies`
  - Direct integration with HealthService, PrometheusClient, KubernetesClient
- **Deployment**: Kubernetes Job/Pod that Lightspeed can spawn and communicate with

### 2. REST API Service (`src/api-server/`) - *If Needed*
- **Purpose**: HTTP endpoints for monitoring, health checks, and external integrations
- **Communication**: HTTP/REST protocols
- **Responsibilities**:
  - Prometheus metrics endpoint (`/metrics`)
  - Kubernetes health probes (`/health`, `/ready`)
  - External API integrations
  - Optional web dashboard
- **Deployment**: Standard Kubernetes Deployment with Service

## Rationale

### **Why Separate Services**

1. **Single Responsibility Principle**: Each service has one clear purpose
2. **Protocol Alignment**: MCP server uses stdio, API server uses HTTP
3. **Deployment Flexibility**: Different scaling and lifecycle requirements
4. **Maintenance Clarity**: Clear boundaries for development and debugging
5. **MCP Best Practices**: Follows MCP SDK design patterns

### **Why Keep MCP Server Pure**

1. **OpenShift Lightspeed Integration**: Lightspeed expects stdio communication
2. **MCP Protocol Compliance**: MCP SDK is designed for stdio transport
3. **Resource Efficiency**: No unnecessary HTTP server overhead
4. **Security**: Reduced attack surface with no network endpoints

### **When to Create API Server**

Only create `src/api-server/` if we have concrete requirements for:
- Prometheus metrics scraping
- External system integrations
- Web dashboard/UI
- Kubernetes health probes (if not handled by MCP server lifecycle)

## Implementation Plan

### Phase 1: MCP Server Purity (COMPLETED)
- ✅ Remove Express.js from `src/mcp-server/`
- ✅ Ensure stdio-only communication
- ✅ Validate MCP protocol implementation
- ✅ Update tests for pure MCP functionality

### Phase 2: Evaluate API Server Need
- [ ] Assess concrete requirements for HTTP endpoints
- [ ] Determine if Prometheus metrics are needed
- [ ] Evaluate external integration requirements
- [ ] Decide if web dashboard is required

### Phase 3: API Server Creation (If Needed)
- [ ] Create `src/api-server/` directory structure
- [ ] Implement Express.js service with specific endpoints
- [ ] Add proper authentication and rate limiting
- [ ] Create separate Helm chart for API server
- [ ] Implement service-to-service communication if needed

## Consequences

### Positive
- **Clear Architecture**: Each service has well-defined responsibilities
- **MCP Compliance**: MCP server follows protocol best practices
- **Scalability**: Services can be scaled independently
- **Maintainability**: Easier to debug and maintain separate concerns
- **Deployment Flexibility**: Different deployment strategies per service

### Negative
- **Potential Duplication**: May need shared libraries for common functionality
- **Service Communication**: If API server needs MCP data, requires inter-service communication
- **Operational Complexity**: Two services to monitor instead of one

### Neutral
- **Development Overhead**: Minimal if API server is not needed
- **Resource Usage**: Similar overall resource consumption

## Monitoring and Review

- **Success Metrics**: MCP server successfully integrates with OpenShift Lightspeed
- **Review Trigger**: When concrete HTTP endpoint requirements emerge
- **Rollback Plan**: Can combine services if separation proves unnecessary

## Update: Dual Transport Architecture (2025-10-14)

**Context**: ADR-016 identified that OpenShift Lightspeed OLSConfig requires HTTP transport, not stdio.

**Solution**: Extended MCP server with dual transport support while maintaining service separation principles:

```typescript
// Environment-based transport selection
const transport = process.env['MCP_TRANSPORT'] || 'stdio';

if (transport === 'http') {
  // HTTP transport for OLSConfig integration
  await this.startHttpTransport();
} else {
  // Stdio transport for direct spawning (default)
  await this.startStdioTransport();
}
```

**Key Principles Maintained**:
- ✅ **Single Responsibility**: MCP server only handles MCP protocol
- ✅ **Transport Abstraction**: HTTP layer is minimal wrapper, no business logic
- ✅ **Default Behavior**: Stdio transport remains default (pure MCP)
- ✅ **Service Separation**: HTTP endpoints only for MCP protocol, not REST API

## Implementation Status

- ✅ **Express.js Removal**: All HTTP endpoints, controllers, and middleware removed from MCP server
- ✅ **Pure MCP Implementation**: Server uses stdio transport by default
- ✅ **Service Boundaries**: Clear separation between MCP server and potential REST API service
- ✅ **Testing**: All tests passing with pure MCP functionality
- ✅ **Architecture Compliance**: Follows MCP protocol best practices
- ✅ **Dual Transport Support**: Added HTTP transport for OLSConfig integration (ADR-016)
- ✅ **SDK Compliance**: Updated to use official @modelcontextprotocol/sdk patterns

## Related ADRs

- **ADR-014**: Cluster Health MCP Server for OpenShift Lightspeed Integration
- **ADR-016**: OpenShift Lightspeed OLSConfig Integration (requires HTTP transport)
- **Future ADR**: REST API Service Architecture (if created)

---

*This ADR ensures clean separation of concerns and maintains MCP architectural integrity while providing flexibility for future HTTP endpoint requirements and supporting OLSConfig integration needs.*
