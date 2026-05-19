# MCP Server Deployment

> **⚠️ MOVED**: The MCP server implementation has been migrated to a standalone repository.

## Current Implementation

The **Model Context Protocol (MCP) server** is now a standalone Go-based service maintained in a separate repository:

**Repository**: [KubeHeal/openshift-cluster-health-mcp](https://github.com/KubeHeal/openshift-cluster-health-mcp)

## Architecture

- **Language**: Go 1.21+
- **SDK**: Official Go SDK for Model Context Protocol
- **Deployment**: Standalone service (independent of the main platform)
- **Integration**: HTTP REST APIs to Coordination Engine and KServe

## Documentation

- **ADR-036**: [Go-Based Standalone MCP Server](../../docs/adrs/036-go-based-standalone-mcp-server.md)
- **Deployment Guide**: [Deploy MCP Server for Lightspeed](../../docs/how-to/deploy-mcp-server-lightspeed.md)
- **Testing Guide**: [Test Custom Applications with MCP](../../docs/how-to/test-custom-applications-with-mcp.md)

## Migration History

- **Previous Implementation**: TypeScript-based MCP server in `src/mcp-server/` (removed 2025-12-09)
- **ADR-014**: [Original TypeScript MCP Server](../../docs/adrs/014-openshift-aiops-platform-mcp-server.md) - **SUPERSEDED**
- **ADR-036**: [Current Go MCP Server](../../docs/adrs/036-go-based-standalone-mcp-server.md) - **CURRENT**

## Quick Start

See the standalone repository's README for deployment instructions:

```bash
git clone https://github.com/KubeHeal/openshift-cluster-health-mcp.git
cd openshift-cluster-health-mcp
# Follow deployment instructions in standalone repo
```

## Integration

This platform's deployment guides and notebooks are updated to work with the standalone Go MCP server. No changes required for platform users.
