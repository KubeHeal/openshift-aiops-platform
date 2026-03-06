# ADR-016: OpenShift Lightspeed OLSConfig Integration

## Status
accepted - 2025-10-14
**IN PROGRESS** - 2025-10-14 (Architecture analysis complete, implementation pending)

## Context

Following the successful implementation of **ADR-014** (Cluster Health MCP Server) and **ADR-015** (Service Separation), we have discovered that **OpenShift Lightspeed Operator** provides native MCP server integration through the `OLSConfig` Custom Resource Definition.

### Discovery Analysis

**OpenShift Lightspeed Operator v1.0.6** includes:
- `olsconfigs.ols.openshift.io` CRD with MCP server support
- `MCPServer` feature gate for enabling MCP functionality
- **Streamable HTTP Transport** requirement (not stdio transport)
- Cluster-scoped singleton configuration pattern (`metadata.name: cluster`)

### Current Architecture Gap

Our existing MCP server (ADR-014) implements **stdio transport** for direct Lightspeed spawning:
```typescript
// Current implementation - stdio only
const transport = new StdioServerTransport();
await this.server.connect(transport);
```

However, **OLSConfig requires HTTP transport**:
```yaml
# OLSConfig mcpServers field structure
mcpServers:
  - name: "cluster-health"
    streamableHTTP:
      url: "http://cluster-health-mcp-server.self-healing-platform.svc:3000"
      timeout: 5
      enableSSE: false
```

### Integration Requirements

1. **Dual Transport Support**: MCP server must support both stdio and HTTP transports
2. **Feature Gate Activation**: `MCPServer` feature gate must be enabled in OLSConfig
3. **HTTP Service Exposure**: Kubernetes Service required for HTTP transport
4. **LLM Provider Configuration**: OLSConfig requires LLM provider setup
5. **Cluster-Scoped Resource**: Single OLSConfig named `cluster` for entire cluster

## Decision

**Extend our MCP server architecture to support dual transport modes** while maintaining ADR-015 service separation principles:

1. **Dual Transport MCP Server**: Support both stdio (existing) and HTTP (new) transports
2. **OLSConfig Integration**: Create cluster-scoped OLSConfig resource for Lightspeed integration
3. **HTTP Service Layer**: Add minimal HTTP wrapper around existing MCP server core
4. **Feature Gate Management**: Enable MCPServer feature gate in OLSConfig
5. **Deployment Automation**: Update scripts to handle OLSConfig lifecycle

## Rationale

### **Why Dual Transport Architecture**
- **Backward Compatibility**: Maintains existing stdio transport for direct spawning
- **OLSConfig Compliance**: Adds required HTTP transport for Lightspeed integration
- **ADR-015 Alignment**: HTTP layer is minimal wrapper, not REST API service
- **Flexibility**: Supports both integration patterns as needed

### **Why OLSConfig Integration**
- **Native Integration**: Leverages official OpenShift Lightspeed Operator capabilities
- **Enterprise Features**: Access to Lightspeed's authentication, authorization, audit
- **Unified Interface**: Single Lightspeed UI for all conversational AI interactions
- **Operator Management**: Automatic lifecycle management by Lightspeed Operator

### **Why Minimal HTTP Wrapper**
- **Service Separation**: Maintains ADR-015 principle of pure MCP server core
- **Protocol Compliance**: HTTP wrapper only translates transport, not functionality
- **Security**: No additional attack surface beyond MCP protocol requirements
- **Performance**: Minimal overhead for transport translation

## Architecture

### **Dual Transport MCP Server**
```
┌─────────────────────────────────────────────────────────────┐
│                 Cluster Health MCP Server                   │
│  ┌─────────────────┐    ┌──────────────────┐              │
│  │   MCP Core      │    │  Transport       │              │
│  │   (Unchanged)   │◄───│  Abstraction     │              │
│  │   - Resources   │    │  Layer           │              │
│  │   - Tools       │    └──────────────────┘              │
│  │   - Handlers    │             │                         │
│  └─────────────────┘             ▼                         │
│           │              ┌──────────────────┐              │
│           │              │  Stdio Transport │              │
│           │              │  (Existing)      │              │
│           │              └──────────────────┘              │
│           │              ┌──────────────────┐              │
│           └─────────────▶│  HTTP Transport  │              │
│                          │  (New)           │              │
│                          └──────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

### **OLSConfig Integration Flow**
```
OpenShift Lightspeed Integration:
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   User Query    │───▶│  OpenShift       │───▶│  LLM Engine     │
│   "Show health" │    │  Lightspeed UI   │    │  (GPT-4/Granite)│
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                       │
         ▼                        ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   OLSConfig     │    │  MCPServer       │    │  HTTP Request   │
│   cluster       │    │  Feature Gate    │    │  to MCP Server  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                       │
         ▼                        ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   mcpServers:   │    │  streamableHTTP: │    │  MCP Protocol   │
│   - cluster-    │    │  url: http://... │    │  over HTTP      │
│     health      │    │  timeout: 5      │    │  Transport      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Implementation

### **Phase 1: MCP Server HTTP Transport (Week 1)**

#### **1.1 Add HTTP Transport Support**
```typescript
// src/mcp-server/src/transports/httpTransport.ts
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import express from 'express';

export class HttpMcpTransport {
  private app: express.Application;
  private server: Server;

  constructor(server: Server, port: number = 3000) {
    this.server = server;
    this.app = express();
    this.setupRoutes();
  }

  private setupRoutes(): void {
    // MCP over HTTP endpoint
    this.app.post('/mcp', async (req, res) => {
      try {
        const response = await this.server.handleRequest(req.body);
        res.json(response);
      } catch (error) {
        res.status(500).json({ error: error.message });
      }
    });

    // Health check for OLSConfig
    this.app.get('/health', (req, res) => {
      res.json({ status: 'healthy', transport: 'http' });
    });
  }

  public listen(port: number): void {
    this.app.listen(port, () => {
      logger.info(`🌐 HTTP MCP Transport listening on port ${port}`);
    });
  }
}
```

#### **1.2 Update Main Server for Dual Transport**
```typescript
// src/mcp-server/src/index.ts - Updated
class ClusterHealthMCPServer {
  private server: Server;
  private healthService: HealthService;

  public async start(): Promise<void> {
    const transport = process.env.MCP_TRANSPORT || 'stdio';

    if (transport === 'http') {
      // HTTP transport for OLSConfig integration
      const httpTransport = new HttpMcpTransport(this.server, 3000);
      httpTransport.listen(3000);
      logger.info('🌐 HTTP MCP Server started for OLSConfig integration');
    } else {
      // Stdio transport for direct spawning
      const stdioTransport = new StdioServerTransport();
      await this.server.connect(stdioTransport);
      logger.info('📊 Stdio MCP Server started for direct spawning');
    }
  }
}
```

### **Phase 2: OLSConfig Resource Creation (Week 1)**

#### **2.1 OLSConfig Manifest**
```yaml
# k8s/olsconfig/cluster-olsconfig.yaml
apiVersion: ols.openshift.io/v1alpha1
kind: OLSConfig
metadata:
  name: cluster
spec:
  # Enable MCP Server feature gate
  featureGates:
    - MCPServer

  # LLM Provider configuration (required)
  llm:
    providers:
      - name: openai
        type: openai
        credentialsSecretRef:
          name: openai-credentials
        models:
          - name: gpt-4
            url: https://api.openai.com/v1/chat/completions

  # MCP Server configuration
  mcpServers:
    - name: cluster-health
      streamableHTTP:
        url: http://cluster-health-mcp-server.self-healing-platform.svc:3000/mcp
        timeout: 10
        enableSSE: false
        headers:
          Content-Type: application/json

  # OLS deployment configuration
  ols:
    defaultProvider: openai
    defaultModel: gpt-4
    deployment:
      replicas: 1
```

### **Phase 3: Helm Chart Updates (Week 1)**

#### **3.1 Add HTTP Service**
```yaml
# charts/mcp-server/templates/service.yaml
{{- if eq .Values.transport "http" }}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "mcp-server.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "mcp-server.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  ports:
    - port: 3000
      targetPort: 3000
      protocol: TCP
      name: mcp-http
  selector:
    {{- include "mcp-server.selectorLabels" . | nindent 4 }}
{{- end }}
```

## Related ADRs

- **ADR-014**: Cluster Health MCP Server for OpenShift Lightspeed Integration
  - Provides the foundation MCP server implementation
  - Defines the core resources and tools architecture
- **ADR-015**: Service Separation - MCP Server vs REST API Service
  - Maintains service separation principles with minimal HTTP wrapper
  - HTTP transport is protocol compliance, not REST API service

## Deployment Infrastructure Updates Required

**Critical Gap Identified**: Current deployment infrastructure is configured for stdio-only transport and needs updates for HTTP transport support.

### **Helm Chart Updates Needed**
```yaml
# charts/mcp-server/values/values.yaml - ADD HTTP service support
service:
  enabled: true  # Enable when MCP_TRANSPORT=http
  type: ClusterIP
  port: 3000
  targetPort: 3000
  annotations:
    service.beta.openshift.io/serving-cert-secret-name: mcp-server-tls

# Update environment variables
env:
  MCP_TRANSPORT: http  # Change from stdio for OLSConfig mode
  PORT: "3000"         # Add port configuration
```

### **Missing Kubernetes Resources**
1. **Service Template**: `charts/mcp-server/templates/service.yaml` - MISSING
2. **OLSConfig Template**: `charts/mcp-server/templates/olsconfig.yaml` - MISSING
3. **LLM Provider Secrets**: Templates for OpenAI/Gemini credentials - MISSING

### **Deployment Script Updates**
```bash
# deploy-mcp-server.sh needs OLSConfig mode
./deploy-mcp-server.sh self-healing-platform olsconfig  # New mode needed
```

## Implementation Status

- ✅ **Architecture Analysis**: OLSConfig CRD structure and requirements understood
- ✅ **Gap Identification**: HTTP transport requirement vs stdio implementation
- ✅ **MCP Server Code**: Dual transport implementation complete (SDK compliant)
- 🔄 **ADR Documentation**: This ADR created and accepted
- ❌ **Helm Chart Updates**: Service template and HTTP configuration MISSING
- ❌ **OLSConfig Resource**: Cluster configuration template MISSING
- ❌ **Deployment Scripts**: OLSConfig deployment mode MISSING
- ⏳ **Integration Testing**: End-to-end validation pending

---

*This ADR extends ADR-014 with native OpenShift Lightspeed integration while maintaining ADR-015 service separation principles through minimal HTTP transport wrapper.*
