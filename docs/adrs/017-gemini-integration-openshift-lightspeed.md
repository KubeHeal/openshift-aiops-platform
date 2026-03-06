# ADR-017: Gemini Integration for OpenShift Lightspeed

## Status
accepted - 2025-10-14
**PLANNED** - 2025-10-14 (Architecture defined, implementation pending)

## Context

Following **ADR-016** (OpenShift Lightspeed OLSConfig Integration), we need to support **Google Gemini** as an alternative LLM provider for the OpenShift AIOps Self-Healing Platform. This provides:

1. **Cost Optimization**: Gemini offers competitive pricing for enterprise workloads
2. **Performance Diversity**: Different model architectures for varied use cases
3. **Vendor Diversification**: Reduces dependency on single LLM provider
4. **Regional Compliance**: Google Cloud regions for data sovereignty requirements

### Current Architecture Context

Our **Cluster Health MCP Server** (ADR-014) integrates with OpenShift Lightspeed via **OLSConfig** (ADR-016). The current configuration supports OpenAI:

```yaml
# Current OLSConfig (OpenAI only)
spec:
  llm:
    providers:
      - name: openai
        type: openai
        credentialsSecretRef:
          name: openai-credentials
        models:
          - name: gpt-4
            url: https://api.openai.com/v1/chat/completions
```

### Gemini Integration Requirements

1. **Multi-Provider Support**: Support both OpenAI and Gemini simultaneously
2. **Model Selection**: Allow dynamic model selection based on workload type
3. **Cost Optimization**: Route queries to most cost-effective model
4. **Fallback Strategy**: Automatic failover between providers
5. **Enterprise Security**: Secure credential management for both providers

## Decision

**Implement dual-provider OLSConfig architecture** supporting both OpenAI and Gemini with intelligent routing:

1. **Multi-Provider OLSConfig**: Configure both OpenAI and Gemini providers
2. **Intelligent Model Routing**: Route queries based on complexity and cost
3. **Secure Credential Management**: Separate secrets for each provider
4. **Fallback Strategy**: Automatic provider switching on failures
5. **Performance Monitoring**: Track usage, costs, and performance metrics

## Rationale

### **Why Gemini Integration**
- **Cost Efficiency**: Gemini Pro offers competitive pricing for high-volume queries
- **Performance Optimization**: Gemini Flash for low-latency responses
- **Enterprise Features**: Google Cloud integration, audit logging, compliance
- **Model Diversity**: Different architectures complement OpenAI models

### **Why Multi-Provider Architecture**
- **Resilience**: Eliminates single point of failure
- **Cost Optimization**: Route to most cost-effective provider per query type
- **Performance**: Use best model for specific workload characteristics
- **Compliance**: Meet diverse regulatory requirements across regions

### **Why Intelligent Routing**
- **Operational Efficiency**: Automatic optimization without manual intervention
- **Cost Control**: Minimize LLM costs while maintaining quality
- **Performance**: Route complex queries to most capable models
- **Reliability**: Seamless failover maintains service availability

## Architecture

### **Multi-Provider OLSConfig**
```yaml
apiVersion: ols.openshift.io/v1alpha1
kind: OLSConfig
metadata:
  name: cluster
spec:
  # Enable MCP Server feature gate
  featureGates:
    - MCPServer

  # Multi-provider LLM configuration
  llm:
    providers:
      # OpenAI Provider
      - name: openai
        type: openai
        credentialsSecretRef:
          name: openai-credentials
        models:
          - name: gpt-4
            url: https://api.openai.com/v1/chat/completions
            contextWindowSize: 128000
            parameters:
              maxTokensForResponse: 4096
          - name: gpt-4-turbo
            url: https://api.openai.com/v1/chat/completions
            contextWindowSize: 128000
            parameters:
              maxTokensForResponse: 4096

      # Gemini Provider
      - name: gemini
        type: openai  # Use OpenAI-compatible API format
        url: https://generativelanguage.googleapis.com/v1beta
        credentialsSecretRef:
          name: gemini-credentials
        models:
          - name: gemini-pro
            url: https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent
            contextWindowSize: 32768
            parameters:
              maxTokensForResponse: 2048
          - name: gemini-flash
            url: https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent
            contextWindowSize: 1048576
            parameters:
              maxTokensForResponse: 8192

  # Default routing strategy
  ols:
    defaultProvider: openai
    defaultModel: gpt-4

    # Intelligent routing configuration
    routingStrategy:
      enabled: true
      rules:
        - condition: "query_length < 1000"
          provider: gemini
          model: gemini-flash
        - condition: "query_type == 'cluster_health'"
          provider: gemini
          model: gemini-pro
        - condition: "query_complexity == 'high'"
          provider: openai
          model: gpt-4-turbo
      fallback:
        provider: openai
        model: gpt-4
```

### **Credential Management**
```yaml
# OpenAI Credentials Secret
apiVersion: v1
kind: Secret
metadata:
  name: openai-credentials
  namespace: openshift-lightspeed
type: Opaque
data:
  api_key: <base64-encoded-openai-key>
---
# Gemini Credentials Secret
apiVersion: v1
kind: Secret
metadata:
  name: gemini-credentials
  namespace: openshift-lightspeed
type: Opaque
data:
  api_key: <base64-encoded-gemini-key>
```

### **MCP Server Integration**
```typescript
// Enhanced MCP Server with provider awareness
class ClusterHealthMCPServer {
  private providerMetrics: Map<string, ProviderMetrics> = new Map();

  // Tool that provides provider recommendations
  registerTool(
    'recommend-provider',
    {
      title: 'LLM Provider Recommendation',
      description: 'Recommend optimal LLM provider for query type',
      inputSchema: {
        queryType: z.enum(['cluster_health', 'incident_analysis', 'remediation']),
        complexity: z.enum(['low', 'medium', 'high']),
        urgency: z.enum(['low', 'medium', 'high'])
      },
      outputSchema: {
        provider: z.string(),
        model: z.string(),
        reasoning: z.string(),
        estimatedCost: z.number()
      }
    },
    async ({ queryType, complexity, urgency }) => {
      const recommendation = this.getProviderRecommendation(queryType, complexity, urgency);
      return {
        content: [{ type: 'text', text: JSON.stringify(recommendation) }],
        structuredContent: recommendation
      };
    }
  );

  private getProviderRecommendation(queryType: string, complexity: string, urgency: string) {
    // Intelligent routing logic
    if (urgency === 'high' && complexity === 'low') {
      return {
        provider: 'gemini',
        model: 'gemini-flash',
        reasoning: 'High urgency, low complexity - use fastest model',
        estimatedCost: 0.001
      };
    }

    if (queryType === 'cluster_health' && complexity === 'medium') {
      return {
        provider: 'gemini',
        model: 'gemini-pro',
        reasoning: 'Cluster health queries work well with Gemini Pro',
        estimatedCost: 0.005
      };
    }

    return {
      provider: 'openai',
      model: 'gpt-4',
      reasoning: 'Complex analysis requires GPT-4 capabilities',
      estimatedCost: 0.03
    };
  }
}
```

## Implementation

### **Phase 1: Multi-Provider OLSConfig (Week 1)**

#### **1.1 Update OLSConfig Manifest**
```yaml
# k8s/olsconfig/cluster-olsconfig-gemini.yaml
apiVersion: ols.openshift.io/v1alpha1
kind: OLSConfig
metadata:
  name: cluster
spec:
  featureGates:
    - MCPServer

  llm:
    providers:
      - name: openai
        type: openai
        credentialsSecretRef:
          name: openai-credentials
        models:
          - name: gpt-4
            url: https://api.openai.com/v1/chat/completions

      - name: gemini
        type: openai  # OpenAI-compatible format
        url: https://generativelanguage.googleapis.com/v1beta
        credentialsSecretRef:
          name: gemini-credentials
        models:
          - name: gemini-pro
            url: https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent

  mcpServers:
    - name: cluster-health
      streamableHTTP:
        url: http://cluster-health-mcp-server.self-healing-platform.svc:3000/mcp
        timeout: 10
        enableSSE: false

  ols:
    defaultProvider: gemini  # Use Gemini as default for cost optimization
    defaultModel: gemini-pro
```

#### **1.2 Credential Secrets**
```bash
# Create OpenAI credentials
oc create secret generic openai-credentials \
  --from-literal=api_key="${OPENAI_API_KEY}" \
  -n openshift-lightspeed

# Create Gemini credentials
oc create secret generic gemini-credentials \
  --from-literal=api_key="${GEMINI_API_KEY}" \
  -n openshift-lightspeed
```

### **Phase 2: Enhanced MCP Server (Week 2)**

#### **2.1 Provider Metrics and Monitoring**
```typescript
// src/mcp-server/src/services/providerService.ts
export class ProviderService {
  private metrics = new Map<string, {
    requestCount: number;
    totalCost: number;
    averageLatency: number;
    errorRate: number;
  }>();

  async trackProviderUsage(provider: string, model: string, cost: number, latency: number) {
    // Track usage metrics for cost optimization
  }

  async getProviderRecommendation(context: QueryContext): Promise<ProviderRecommendation> {
    // Intelligent routing based on metrics and context
  }
}
```

## Related ADRs

- **ADR-014**: Cluster Health MCP Server for OpenShift Lightspeed Integration
  - Provides the foundation MCP server that integrates with multiple providers
- **ADR-016**: OpenShift Lightspeed OLSConfig Integration
  - Establishes the OLSConfig integration pattern extended here for multi-provider support

## Deployment Infrastructure

**Helm Chart Integration**: Multi-provider support added to deployment infrastructure:

```yaml
# charts/mcp-server/values/values.yaml
olsconfig:
  enabled: true
  llm:
    providers:
      - name: openai
        type: openai
        credentialsSecretRef:
          name: openai-credentials
        models:
          - name: gpt-4
            url: https://api.openai.com/v1/chat/completions

      - name: gemini
        type: openai
        url: https://generativelanguage.googleapis.com/v1beta
        credentialsSecretRef:
          name: gemini-credentials
        models:
          - name: gemini-pro
            url: https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent
```

**Deployment Commands**:
```bash
# Deploy with Gemini support
./deploy-mcp-server.sh self-healing-platform olsconfig

# Create credentials
oc create secret generic openai-credentials --from-literal=api_key=$OPENAI_API_KEY -n openshift-lightspeed
oc create secret generic gemini-credentials --from-literal=api_key=$GEMINI_API_KEY -n openshift-lightspeed
```

## Implementation Status

- ✅ **Architecture Design**: Multi-provider OLSConfig architecture defined
- ✅ **Credential Strategy**: Secure secret management approach established
- ✅ **Helm Chart Updates**: OLSConfig template and multi-provider values added
- ✅ **Deployment Scripts**: OLSConfig mode support added to deploy-mcp-server.sh
- ⏳ **Provider Routing**: Intelligent routing logic pending
- ⏳ **Testing**: Multi-provider integration testing pending

---

*This ADR extends ADR-016 with Gemini support, providing cost optimization and vendor diversification while maintaining the established OLSConfig integration pattern.*
