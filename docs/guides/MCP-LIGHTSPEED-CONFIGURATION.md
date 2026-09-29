# MCP Server + OpenShift Lightspeed Configuration Guide

This guide explains how to configure the Model Context Protocol (MCP) server to integrate with OpenShift Lightspeed for AI-powered cluster operations.

## Overview

The self-healing platform includes an MCP server that exposes cluster health tools and resources. When integrated with OpenShift Lightspeed, users can ask natural language questions like:
- "What's the health status of my cluster?"
- "Show me pods with high CPU usage"
- "What anomalies have been detected recently?"

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     OpenShift Lightspeed UI                         │
│                    "Show cluster health"                            │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     OpenShift Lightspeed Server                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │   OLSConfig  │───▶│  LLM Engine  │───▶│  MCP Client  │          │
│  │   (cluster)  │    │ (GPT-4/etc)  │    │              │          │
│  └──────────────┘    └──────────────┘    └──────┬───────┘          │
└────────────────────────────────────────────────┬────────────────────┘
                                                  │ HTTP/MCP Protocol
                                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│               Cluster Health MCP Server (HTTP Mode)                  │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  MCP Resources           │  MCP Tools                    │       │
│  │  - cluster://health      │  - get_cluster_health        │       │
│  │  - cluster://pods        │  - get_pod_metrics           │       │
│  │  - cluster://anomalies   │  - trigger_remediation       │       │
│  │  - cluster://events      │  - get_anomaly_predictions   │       │
│  └──────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **OpenShift Lightspeed Operator** installed (v1.0.6+)
2. **MCP Server** deployed with HTTP transport enabled
3. **LLM Provider** configured (OpenAI, Azure OpenAI, or IBM watsonx)

## Configuration Steps

### Step 1: Deploy MCP Server with HTTP Transport

The MCP server supports dual transport modes:
- **stdio** (default): For direct spawning
- **http**: For OLSConfig integration

Deploy with HTTP transport:

```bash
# Option 1: Using Helm
helm install mcp-server charts/mcp-server \
  --namespace self-healing-platform \
  --set transport=http \
  --set service.enabled=true \
  --set service.port=3000

# Option 2: Using environment variable
kubectl set env deployment/mcp-server \
  MCP_TRANSPORT=http \
  -n self-healing-platform
```

Verify the MCP server service is running:

```bash
# Check service exists
oc get svc mcp-server -n self-healing-platform

# Test HTTP endpoint
oc exec -it deploy/mcp-server -n self-healing-platform -- \
  curl -s http://localhost:3000/health
```

### Step 2: Create LLM Provider Secret

Create a secret with your LLM provider credentials:

```yaml
# k8s/olsconfig/llm-credentials-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: llm-api-credentials
  namespace: openshift-lightspeed
type: Opaque
stringData:
  # For OpenAI
  apiKey: "sk-your-openai-api-key"

  # For Azure OpenAI (uncomment if using Azure)
  # apiKey: "your-azure-api-key"
  # endpoint: "https://your-resource.openai.azure.com"
```

Apply the secret:

```bash
oc apply -f k8s/olsconfig/llm-credentials-secret.yaml
```

### Step 3: Create OLSConfig Resource

Create the OLSConfig custom resource to configure Lightspeed with MCP:

```yaml
# k8s/olsconfig/cluster-olsconfig.yaml
apiVersion: ols.openshift.io/v1
kind: OLSConfig
metadata:
  name: cluster
spec:
  # Enable MCP Server feature gate
  featureGates:
    - MCPServer

  # LLM Provider configuration
  llm:
    providers:
      - name: openai
        type: openai
        credentialsSecretRef:
          name: llm-api-credentials
        models:
          - name: gpt-4
            url: https://api.openai.com/v1/chat/completions

    # Default model selection
    defaultProvider: openai
    defaultModel: gpt-4

  # MCP Server configuration
  mcpServers:
    - name: cluster-health
      streamableHTTP:
        # MCP server service URL
        url: http://mcp-server.self-healing-platform.svc:3000/mcp
        # Request timeout in seconds
        timeout: 10
        # Disable SSE (not supported by current MCP server)
        enableSSE: false
        # Request headers
        headers:
          Content-Type: application/json

  # OLS deployment configuration
  ols:
    defaultProvider: openai
    defaultModel: gpt-4
    deployment:
      replicas: 1
```

Apply the OLSConfig:

```bash
oc apply -f k8s/olsconfig/cluster-olsconfig.yaml
```

### Step 4: Verify Integration

1. **Check OLSConfig status:**
   ```bash
   oc get olsconfig cluster -o yaml
   ```

2. **Check Lightspeed pods:**
   ```bash
   oc get pods -n openshift-lightspeed
   ```

3. **Test the integration:**
   - Open the OpenShift Console
   - Click on the Lightspeed icon (chat bubble)
   - Ask: "What is the health status of the self-healing-platform namespace?"

## Available MCP Tools

The MCP server exposes these tools to Lightspeed:

| Tool | Description |
|------|-------------|
| `get_cluster_health` | Get overall cluster health status |
| `get_namespace_health` | Get health status for a specific namespace |
| `get_pod_metrics` | Get CPU/memory metrics for pods |
| `get_anomaly_predictions` | Get recent anomaly detection results |
| `trigger_remediation` | Trigger a remediation action |
| `get_incidents` | Get active incidents |
| `get_events` | Get recent Kubernetes events |

## Available MCP Resources

These resources can be queried by Lightspeed:

| Resource URI | Description |
|--------------|-------------|
| `cluster://health` | Current cluster health summary |
| `cluster://pods/{namespace}` | Pod status in namespace |
| `cluster://anomalies` | Recent detected anomalies |
| `cluster://incidents` | Active incidents |
| `cluster://events` | Recent cluster events |

## Troubleshooting

### MCP Server Not Connecting

```bash
# Check MCP server logs
oc logs -l app=mcp-server -n self-healing-platform

# Verify HTTP endpoint is accessible
oc exec -it deploy/lightspeed-operator -n openshift-lightspeed -- \
  curl -v http://mcp-server.self-healing-platform.svc:3000/health
```

### Lightspeed Not Using MCP Tools

1. Verify the `MCPServer` feature gate is enabled in OLSConfig
2. Check that the MCP server URL is correct
3. Verify network policies allow traffic between namespaces

### LLM Provider Errors

```bash
# Check Lightspeed logs for API errors
oc logs -l app=lightspeed -n openshift-lightspeed | grep -i error
```

## Security Considerations

1. **Network Policies**: Ensure network policies allow traffic from `openshift-lightspeed` to `self-healing-platform` namespace

2. **RBAC**: The MCP server service account needs appropriate permissions:
   ```yaml
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRole
   metadata:
     name: mcp-server-cluster-reader
   rules:
   - apiGroups: [""]
     resources: ["pods", "nodes", "events", "namespaces"]
     verbs: ["get", "list", "watch"]
   - apiGroups: ["metrics.k8s.io"]
     resources: ["pods", "nodes"]
     verbs: ["get", "list"]
   ```

3. **Secrets**: Never commit LLM API keys to git. Use External Secrets Operator or sealed secrets.

## Related Documentation

- [ADR-014: Cluster Health MCP Server](adrs/014-openshift-aiops-platform-mcp-server.md)
- [ADR-015: Service Separation - MCP vs REST API](adrs/015-service-separation-mcp-vs-rest-api.md)
- [ADR-016: OpenShift Lightspeed OLSConfig Integration](adrs/016-openshift-lightspeed-olsconfig-integration.md)
- [OpenShift Lightspeed Documentation](https://docs.openshift.com/container-platform/latest/lightspeed/)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)

## Example Queries

Once configured, users can ask Lightspeed questions like:

- "What is the health status of my cluster?"
- "Show me pods with high memory usage in self-healing-platform"
- "What anomalies have been detected in the last hour?"
- "Are there any failing pods that need remediation?"
- "Describe the recent events in the production namespace"
- "What's the current model accuracy for anomaly detection?"

The LLM will use the MCP tools to query real cluster data and provide contextual answers.
