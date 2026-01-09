# How-To: Deploy MCP Server and Configure OpenShift Lightspeed

## Overview

This guide provides quick deployment instructions for the Cluster Health MCP Server and its integration with OpenShift Lightspeed. For architectural details, see [ADR-014](../adrs/014-openshift-aiops-platform-mcp-server.md).

## Prerequisites

- OpenShift 4.18+ cluster with admin access
- Self-healing platform deployed (`self-healing-platform` namespace exists)
- OpenShift Lightspeed operator installed
- MCP server image built (via BuildConfig)

## Quick Start

### 1. Deploy MCP Server

Deploy the MCP server using Kustomize:

```bash
# Development deployment (with debug logging)
oc apply -k k8s/mcp-server/overlays/development

# OR: Production deployment
oc apply -k k8s/mcp-server/base
```

**Verify deployment:**

```bash
oc get deployment cluster-health-mcp-server -n self-healing-platform
oc get service cluster-health-mcp-server -n self-healing-platform
oc logs deployment/cluster-health-mcp-server -n self-healing-platform
```

### 2. LLM Provider Configuration

OpenShift Lightspeed supports multiple LLM providers. For complete configuration details, see the [official Red Hat documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_lightspeed/1.0/html/configure/ols-configuring-openshift-lightspeed).

#### Supported Providers

| Provider | Type | Secret Key Name | Example Config | Get API Key |
|----------|------|-----------------|----------------|-------------|
| OpenAI | `openai` | `apitoken` | `olsconfig-openai.yaml` | https://platform.openai.com/api-keys |
| Google Gemini | `openai` (compatible) | `apitoken` | `olsconfig-google.yaml` | https://aistudio.google.com/apikey |
| Anthropic Claude | `openai` (compatible) | `apitoken` | `olsconfig-anthropic.yaml` | https://console.anthropic.com/ |
| Red Hat AI vLLM | `rhelai_vllm` | `apitoken` | `olsconfig-rhelai-vllm.yaml` | Internal Red Hat AI |
| Azure OpenAI | `azure_openai` | `apitoken` | See official docs | https://portal.azure.com |
| IBM watsonx | `watsonx` | `apitoken` | See official docs | IBM Cloud Console |

**IMPORTANT**: The secret key must be named `apitoken` (not `apiKey`, `api_key`, etc.). OpenShift Lightspeed validates this and will fail reconciliation if the key name is incorrect.

#### Secret Creation Examples

**OpenAI**:
```bash
# Get API key from https://platform.openai.com/api-keys
oc create secret generic openai-api-key \
  -n openshift-lightspeed \
  --from-literal=apitoken='sk-proj-...'
```

**Google Gemini**:
```bash
# Get API key from https://aistudio.google.com/apikey
# Enable Generative Language API: https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com
# Ensure billing is enabled on your Google Cloud project
oc create secret generic google-api-key \
  -n openshift-lightspeed \
  --from-literal=apitoken='AIzaSy...'
```

**Anthropic Claude**:
```bash
# Get API key from https://console.anthropic.com/
oc create secret generic anthropic-api-key \
  -n openshift-lightspeed \
  --from-literal=apitoken='sk-ant-...'
```

**Red Hat AI vLLM**:
```bash
# For internal Red Hat AI deployments
oc create secret generic rhelai-api-key \
  -n openshift-lightspeed \
  --from-literal=apitoken='YOUR_RHELAI_TOKEN'
```

### 3. Create OLSConfig

Create an OLSConfig resource to integrate the MCP server with OpenShift Lightspeed. This configuration is **manually customized** based on your LLM provider.

**IMPORTANT**: See the [official Red Hat OpenShift Lightspeed documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_lightspeed/1.0/html/configure/ols-configuring-openshift-lightspeed) for complete provider configuration details.

#### OLSConfig Structure

The OLSConfig supports multiple LLM providers. Choose the configuration that matches your provider:

```yaml
apiVersion: ols.openshift.io/v1alpha1
kind: OLSConfig
metadata:
  name: cluster  # MUST be 'cluster' (cluster-scoped singleton)
spec:
  # Enable MCP Server integration
  featureGates:
    - MCPServer

  # LLM Provider configuration (choose one or configure multiple)
  llm:
    providers:
      # OpenAI (GPT-4, GPT-4o)
      - name: openai
        type: openai
        url: "https://api.openai.com/v1"
        credentialsSecretRef:
          name: openai-api-key
        models:
          - name: gpt-4o-mini      # Recommended for cost/performance
          - name: gpt-4o           # For complex reasoning

      # Google Gemini (OpenAI-compatible endpoint)
      - name: google
        type: openai
        url: "https://generativelanguage.googleapis.com/v1beta/openai"
        credentialsSecretRef:
          name: google-api-key
        models:
          - name: gemini-1.5-pro
          - name: gemini-1.5-flash

      # IBM BAM (Granite models)
      - name: bam
        type: bam
        url: "https://bam-api.res.ibm.com"
        credentialsSecretRef:
          name: bam-api-key
        models:
          - name: granite-13b-chat-v2  # Open source option

      # Azure OpenAI
      - name: azure
        type: azure_openai
        url: "https://YOUR_RESOURCE.openai.azure.com"
        credentialsSecretRef:
          name: azure-openai-key
        models:
          - name: gpt-4o

  # MCP Server configuration (integrates with self-healing platform)
  mcpServers:
    - name: cluster-health
      streamableHTTP:
        url: http://mcp-server.self-healing-platform.svc:8080/mcp
        timeout: 30
        enableSSE: false

  # OLS deployment configuration
  ols:
    defaultModel: gpt-4o-mini     # Choose your default model
    defaultProvider: openai        # Choose your default provider
    deployment:
      replicas: 1
    conversationCache:
      type: postgres               # REQUIRED: Only 'postgres' is supported
      redis:
        maxMemory: "2000mb"
        maxMemoryPolicy: "allkeys-lru"

  # Console plugin configuration
  console:
    enabled: true
```

**Apply your customized configuration:**

```bash
# Save the above YAML to a file (e.g., olsconfig.yaml) with your provider details
# Then apply it:
oc apply -f olsconfig.yaml
```

**Verify configuration:**

```bash
# Check OLSConfig exists (name must be 'cluster')
oc get olsconfig cluster

# View detailed status
oc describe olsconfig cluster
```

**Check reconciliation status:**
```bash
# Watch for all conditions to become Ready
oc get olsconfig cluster -o jsonpath='{.status.conditions[*].type}' && echo
oc get olsconfig cluster -o jsonpath='{.status.conditions[*].status}' && echo

# Check specific conditions
# - ConsolePluginReady: True
# - CacheReady: True
# - ApiReady: True (requires valid API key)
```

#### Configuration Requirements

Per [Red Hat OpenShift Lightspeed CRD specification](https://docs.redhat.com/en/documentation/red_hat_openshift_lightspeed/1.0/html/configure/ols-olsconfig-api-reference):

1. **metadata.name**: MUST be `cluster` (cluster-scoped singleton resource)
2. **conversationCache.type**: MUST be `postgres` (only supported type, not `memory`)
3. **Secret key name**: MUST be `apitoken` (not `apiKey`, `api_key`, etc.)
4. **MCP transport**: MUST use `streamableHTTP` configuration (stdio not supported by CRD)
5. **Feature gates**: Include `MCPServer` to enable MCP functionality
6. **Models**: MUST be nested inside each provider's `models` array
7. **Provider types**: Supported values are `azure_openai`, `bam`, `openai`, `watsonx`, `rhoai_vllm`, `rhelai_vllm`, `fake_provider`

#### Provider-Specific Notes

**Google Gemini**:
- Configured as `openai` type (Google provides OpenAI-compatible endpoint)
- URL: `https://generativelanguage.googleapis.com/v1beta/openai`
- Models: `gemini-1.5-pro`, `gemini-1.5-flash`, or `models/gemini-3-pro-preview` (experimental)
- Requires Generative Language API enabled and billing configured

**Anthropic Claude**:
- Configured as `openai` type (Anthropic provides OpenAI-compatible API)
- URL: `https://api.anthropic.com/v1`
- Models: `claude-3-5-sonnet-20241022`, `claude-3-5-haiku-20241022`

**Red Hat AI vLLM**:
- Uses dedicated `rhelai_vllm` provider type
- URL: Internal cluster service (e.g., `http://vllm-service.rhelai.svc.cluster.local:8000/v1`)
- Models: IBM Granite models (`granite-3.1-8b-instruct`, `granite-3.1-2b-instruct`)

### 4. Test Integration

Test the MCP server health endpoint:

```bash
# From a test pod
oc run test-curl --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  --rm -i --restart=Never -n self-healing-platform -- \
  curl -s http://cluster-health-mcp-server:3000/health
```

Expected response:

```json
{
  "status": "healthy",
  "mcpServer": "cluster-health",
  "version": "1.0.0"
}
```

## Detailed Configuration

### MCP Server Environment Variables

Customize the deployment by editing environment variables:

```yaml
# k8s/mcp-server/base/deployment.yaml
env:
  - name: MCP_TRANSPORT
    value: "stdio"  # or "http" for HTTP transport
  - name: COORDINATION_ENGINE_URL
    value: "http://coordination-engine:8080"
  - name: LOG_LEVEL
    value: "info"  # or "debug" for detailed logs
  - name: NODE_ENV
    value: "production"
```

### OLSConfig Options

The OLSConfig supports multiple LLM providers:

```yaml
spec:
  llm:
    providers:
      # OpenAI (default)
      - name: openai
        type: openai
        url: "https://api.openai.com/v1"
        credentialsSecretRef:
          name: openai-api-key

      # IBM BAM (Granite models)
      - name: bam
        type: bam
        url: "https://bam-api.res.ibm.com"
        credentialsSecretRef:
          name: bam-api-key

      # Azure OpenAI
      - name: azure
        type: azure_openai
        url: "https://YOUR_RESOURCE.openai.azure.com"
        credentialsSecretRef:
          name: azure-openai-key

    models:
      - name: gpt-4o-mini      # Recommended for cost/performance
        provider: openai
      - name: gpt-4o           # For complex reasoning
        provider: openai
      - name: granite-13b-chat-v2  # Open source option
        provider: bam

  ols:
    defaultModel: gpt-4o-mini  # Choose your default
    defaultProvider: openai
```

### MCP Server Tools and Resources

The MCP server exposes these capabilities to OpenShift Lightspeed:

**Tools** (Actions):
- `trigger-remediation` - Initiate self-healing actions
- `analyze-anomalies` - Run anomaly detection analysis
- `get-cluster-health` - Retrieve current cluster health status
- `query-incidents` - Search incident history

**Resources** (Data):
- `cluster://health` - Real-time cluster health metrics
- `cluster://incidents` - Incident history and details
- `cluster://nodes` - Node health and status
- `cluster://anomalies` - Detected anomalies

## Usage Examples

### Ask OpenShift Lightspeed

Once configured, you can ask Lightspeed natural language questions:

```
You: "Show me the current cluster health"
Lightspeed: *Uses MCP server's cluster://health resource*

You: "What incidents happened in the last hour?"
Lightspeed: *Uses query-incidents tool*

You: "Trigger remediation for incident INC-12345"
Lightspeed: *Uses trigger-remediation tool*
```

### Programmatic Access (from Notebooks)

```python
import requests

# MCP server health
response = requests.get('http://cluster-health-mcp-server.self-healing-platform.svc:3000/health')
print(response.json())

# OpenShift Lightspeed query (requires auth token)
import openai
openai.api_base = "https://lightspeed-console-openshift-lightspeed.apps.YOUR_CLUSTER/api"
response = openai.ChatCompletion.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Show cluster health"}]
)
print(response.choices[0].message.content)
```

## Troubleshooting

### MCP Server Not Starting

```bash
# Check pod status
oc get pods -n self-healing-platform -l app=cluster-health-mcp-server

# Check logs
oc logs deployment/cluster-health-mcp-server -n self-healing-platform --tail=50

# Common issues:
# 1. Image not found - ensure BuildConfig completed
oc get build -n self-healing-platform | grep mcp-server

# 2. ServiceAccount missing - create if needed
oc get sa self-healing-operator -n self-healing-platform
```

### OpenShift Lightspeed Not Connecting

```bash
# Check OLSConfig status
oc get olsconfig cluster-health-assistant -o yaml

# Verify MCP server service
oc get service cluster-health-mcp-server -n self-healing-platform

# Test connectivity from Lightspeed namespace
oc run test-curl -n openshift-lightspeed --image=curlimages/curl:latest \
  --rm -i --restart=Never -- \
  curl -v http://cluster-health-mcp-server.self-healing-platform.svc:3000/health
```

### LLM Provider Issues

**Error: "missing key 'apitoken'"**

This is the most common error. The secret must have a key named `apitoken`.

```bash
# Check current secret keys
oc get secret google-api-key -n openshift-lightspeed -o jsonpath='{.data}' | jq

# If it shows "apiKey" instead of "apitoken", fix it:
# 1. Get the current value
API_KEY=$(oc get secret google-api-key -n openshift-lightspeed -o jsonpath='{.data.apiKey}' | base64 -d)

# 2. Delete and recreate with correct key
oc delete secret google-api-key -n openshift-lightspeed
oc create secret generic google-api-key -n openshift-lightspeed --from-literal=apitoken="$API_KEY"
```

**Error: "Unsupported value: \"google\""**

Google is not a native provider type. Use `type: openai` with Google's OpenAI-compatible endpoint:
```yaml
providers:
  - name: google-gemini
    type: openai
    url: "https://generativelanguage.googleapis.com/v1beta/openai"
```

**Error: "Unsupported value: \"memory\""**

Only `postgres` is supported for conversation cache:
```yaml
conversationCache:
  type: postgres
```

**Error: "Required value for field spec.llm.providers[0].models"**

Models must be inside each provider configuration:
```yaml
providers:
  - name: google-gemini
    type: openai
    models:              # ✅ Inside provider
      - name: gemini-1.5-pro
```

**General Debugging**:
```bash
# Check API key secret
oc get secret google-api-key -n openshift-lightspeed -o yaml

# Verify OLSConfig provider configuration
oc get olsconfig cluster -o jsonpath='{.spec.llm.providers}' | jq .

# Check reconciliation status and errors
oc get olsconfig cluster -o yaml | grep -A 10 "conditions:"

# Check lightspeed-app-server logs for LLM connection errors
oc logs -n openshift-lightspeed deployment/lightspeed-app-server -c lightspeed-service-api --tail=50 | grep -i "llm\|error"
```

### Provider-Specific Issues

For detailed provider configuration, see [Red Hat OpenShift Lightspeed documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_lightspeed/1.0/html/configure/ols-configuring-openshift-lightspeed).

**OpenAI**:

Error: `API key not valid`
```bash
# Verify API key is correct
# Get new key from: https://platform.openai.com/api-keys

# Check key format (should start with 'sk-proj-' or 'sk-')
oc get secret openai-api-key -n openshift-lightspeed -o jsonpath='{.data.apitoken}' | base64 -d

# Recreate secret if needed
oc delete secret openai-api-key -n openshift-lightspeed
oc create secret generic openai-api-key \
  -n openshift-lightspeed \
  --from-literal=apitoken='sk-proj-YOUR_KEY_HERE'
```

Error: `Rate limit exceeded`
- Upgrade to paid tier at https://platform.openai.com/account/billing
- Or wait for rate limit reset (depends on your plan)
- Consider using `gpt-4o-mini` for lower costs

**Google Gemini**:

Error: `API key not valid. Please pass a valid API key`
```bash
# 1. Get API key from: https://aistudio.google.com/apikey
# 2. Enable Generative Language API:
#    https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com
# 3. Ensure billing is enabled on your Google Cloud project
# 4. Recreate secret with correct API key (starts with 'AIzaSy')

oc delete secret google-api-key -n openshift-lightspeed
oc create secret generic google-api-key \
  -n openshift-lightspeed \
  --from-literal=apitoken='AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'

# Restart lightspeed pods to pick up new key
oc rollout restart deployment lightspeed-app-server -n openshift-lightspeed
```

Error: `Model not found`
- Google Gemini models via OpenAI-compatible endpoint: `gemini-1.5-pro`, `gemini-1.5-flash`
- Experimental models may require `models/` prefix: `models/gemini-3-pro-preview`
- Check available models at: https://ai.google.dev/gemini-api/docs/models/gemini

Configuration:
- Provider type: `openai` (not `google`)
- URL: `https://generativelanguage.googleapis.com/v1beta/openai`

**Anthropic Claude**:

Error: `Invalid API key`
```bash
# Get API key from: https://console.anthropic.com/
# API key format: starts with 'sk-ant-'

oc delete secret anthropic-api-key -n openshift-lightspeed
oc create secret generic anthropic-api-key \
  -n openshift-lightspeed \
  --from-literal=apitoken='sk-ant-YOUR_KEY_HERE'
```

Error: `Model not found`
- Anthropic Claude models: `claude-3-5-sonnet-20241022`, `claude-3-5-haiku-20241022`, `claude-3-opus-20240229`
- Use full model name with date suffix
- Check latest models at: https://docs.anthropic.com/en/docs/about-claude/models

Configuration:
- Provider type: `openai` (Anthropic supports OpenAI-compatible API)
- URL: `https://api.anthropic.com/v1`

**Red Hat AI vLLM**:

Error: `Connection refused` or `Service not found`
```bash
# Check vLLM service exists
oc get service vllm-service -n rhelai

# Verify service URL in OLSConfig matches actual deployment
oc get olsconfig cluster -o jsonpath='{.spec.llm.providers[?(@.name=="rhelai-vllm")].url}'

# Test connectivity from lightspeed namespace
oc run test-curl -n openshift-lightspeed --image=curlimages/curl:latest \
  --rm -i --restart=Never -- \
  curl -v http://vllm-service.rhelai.svc.cluster.local:8000/v1/models
```

Error: `Model not found`
- Verify model name matches deployed model in vLLM service
- Common IBM Granite models: `granite-3.1-8b-instruct`, `granite-3.1-2b-instruct`
- Check deployed models:
  ```bash
  oc exec -n rhelai <vllm-pod> -- curl http://localhost:8000/v1/models
  ```

Configuration:
- Provider type: `rhelai_vllm` (specific type for Red Hat AI)
- URL: Internal cluster service (e.g., `http://vllm-service.rhelai.svc.cluster.local:8000/v1`)
- Requires internal Red Hat AI deployment

**Azure OpenAI**:

For Azure OpenAI configuration, see [Red Hat official documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_lightspeed/1.0/html/configure/ols-configuring-openshift-lightspeed#ols-creating-lightspeed-cr-file-using-cli_ols-configuring-openshift-lightspeed).

**IBM watsonx**:

For IBM watsonx configuration, see [Red Hat official documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_lightspeed/1.0/html/configure/ols-configuring-openshift-lightspeed#ols-creating-lightspeed-cr-file-using-cli_ols-configuring-openshift-lightspeed).

## Interacting with MCP Server via OpenShift Lightspeed

### Overview

Once the MCP server is integrated with OpenShift Lightspeed, you can interact with your self-healing platform using natural language queries. The MCP server exposes cluster health data, incident management, and remediation tools through conversational AI.

### Accessing OpenShift Lightspeed

**Option 1: OpenShift Console**
1. Navigate to **OpenShift Console** → **Help** (top right)
2. Click **OpenShift Lightspeed** or the chatbot icon
3. Start asking questions about your cluster

**Option 2: Command Line (if CLI integration available)**
```bash
# Check if Lightspeed CLI is available
oc lightspeed --help

# Example query
oc lightspeed query "What is the current cluster health status?"
```

### Example Queries and MCP Tools

The MCP server provides several tools and resources. Here's how to interact with them:

#### 1. Cluster Health Queries

**Query**: "What is the current health status of my cluster?"

**MCP Tool Used**: `get-cluster-health`

**Response Example**:
```
The cluster is healthy with:
- 7 nodes (3 control-plane, 4 workers)
- 95% node availability
- 2 active InferenceServices
- 1 coordination engine running
- No critical alerts
```

**Related Notebook**: `notebooks/00-setup/00-platform-readiness-validation.ipynb`
- **Update When**: Health checks fail, new validation criteria needed
- **What to Update**: Add new validation functions, update health scoring logic

---

#### 2. Incident and Anomaly Queries

**Query**: "Show me recent anomalies detected in the last hour"

**MCP Tool Used**: `query-incidents`

**Response Example**:
```
Found 3 anomalies in the last hour:
1. High CPU usage on worker-2 (95% @ 14:23 UTC)
2. Memory pressure on predictive-analytics pod (87% @ 14:45 UTC)
3. Increased API latency in coordination-engine (450ms @ 15:01 UTC)

All anomalies are being monitored. No immediate action required.
```

**Related Notebooks**:
- `notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb`
- `notebooks/02-anomaly-detection/02-time-series-anomaly-detection.ipynb`

**Update When**:
- False positives/negatives detected
- New anomaly patterns emerge
- Model accuracy drops below threshold

**What to Update**:
- Adjust isolation forest contamination parameter
- Retrain time-series models with recent data
- Update threshold values based on observed patterns

---

#### 3. Remediation Workflow Queries

**Query**: "Trigger remediation for the high memory usage anomaly"

**MCP Tool Used**: `trigger-remediation`

**Response Example**:
```
Remediation initiated for incident #1234:
- Type: Memory pressure
- Target: predictive-analytics-predictor
- Action: Scale down replicas and restart
- Status: In progress
- Estimated completion: 2 minutes

Tracking remediation workflow...
```

**Related Notebooks**:
- `notebooks/03-self-healing-logic/coordination-engine-integration.ipynb`
- `notebooks/03-self-healing-logic/hybrid-healing-workflows.ipynb`

**Update When**:
- Remediation actions fail or incomplete
- New remediation strategies needed
- Coordination engine logic requires tuning

**What to Update**:
- Add new remediation action types
- Update coordination engine decision logic
- Adjust priority scoring for conflicts

---

#### 4. Model Serving Health Queries

**Query**: "How are my InferenceServices performing?"

**MCP Resource Used**: `cluster://anomalies`

**Response Example**:
```
InferenceService Status:
1. predictive-analytics: Ready (2 replicas, 99.5% uptime)
   - Average latency: 45ms
   - Requests/min: 120
   - Error rate: 0.1%

2. anomaly-detector: Ready (1 replica, 98.2% uptime)
   - Average latency: 78ms
   - Requests/min: 85
   - Error rate: 0.3%
```

**Related Notebooks**:
- `notebooks/04-model-serving/kserve-model-deployment.ipynb`
- `notebooks/07-monitoring-operations/model-performance-monitoring.ipynb`

**Update When**:
- Model performance degrades
- Latency increases beyond SLA
- Error rates spike

**What to Update**:
- Retrain models with recent data
- Adjust KServe autoscaling configuration
- Optimize model inference code
- Update model serving resources (CPU/memory)

---

#### 5. Advanced Analytics Queries

**Query**: "Run anomaly analysis on the past week's metrics"

**MCP Tool Used**: `analyze-anomalies`

**Response Example**:
```
Weekly Anomaly Analysis (Dec 2-9, 2025):
- Total anomalies detected: 47
- Critical: 3, High: 12, Medium: 18, Low: 14
- Most common: Resource exhaustion (18 instances)
- Peak anomaly times: 14:00-16:00 UTC
- Accuracy: 94% (based on validated incidents)

Recommendations:
1. Scale up during peak hours (14:00-16:00)
2. Review resource limits for high-usage pods
3. Consider adding predictive scaling policies
```

**Related Notebooks**:
- `notebooks/05-end-to-end-scenarios/resource-exhaustion-detection.ipynb`
- `notebooks/05-end-to-end-scenarios/pod-crash-loop-healing.ipynb`

**Update When**:
- Analysis reveals new patterns
- Recommendations not actionable
- Accuracy drops below 90%

**What to Update**:
- Enhance feature engineering
- Add new anomaly detection algorithms
- Update recommendation logic
- Create new end-to-end scenario notebooks

---

### Iterative Improvement Workflow

Use this cycle to continuously improve your notebooks based on OpenShift Lightspeed interactions:

```
┌─────────────────────────────────────────────────┐
│  1. Interact with OpenShift Lightspeed          │
│     └─> Ask questions, trigger actions          │
└────────────┬────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────┐
│  2. Monitor MCP Server Logs                     │
│     └─> oc logs deployment/cluster-health-mcp-  │
│         server -n self-healing-platform          │
└────────────┬────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────┐
│  3. Identify Gaps or Issues                     │
│     - Inaccurate responses                      │
│     - Missing data or tools                     │
│     - Poor model performance                    │
│     - Failed remediation actions                │
└────────────┬────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────┐
│  4. Update Corresponding Notebooks              │
│     └─> See "Related Notebooks" above           │
└────────────┬────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────┐
│  5. Run Updated Notebooks                       │
│     - Train new models                          │
│     - Update logic/thresholds                   │
│     - Deploy via NotebookValidationJob          │
└────────────┬────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────┐
│  6. Verify Improvements                         │
│     └─> Re-test with OpenShift Lightspeed      │
└────────────┬────────────────────────────────────┘
             │
             └──────> Repeat ───────────────────────┘
```

### Monitoring MCP Server Interactions

**Check MCP Server Logs**:
```bash
# Real-time log streaming
oc logs -f deployment/cluster-health-mcp-server -n self-healing-platform

# Filter for tool invocations
oc logs deployment/cluster-health-mcp-server -n self-healing-platform \
  | grep "Tool invoked"

# Check for errors
oc logs deployment/cluster-health-mcp-server -n self-healing-platform \
  | grep -i error | tail -20
```

**Log Patterns to Watch**:
- `Tool invoked: <tool-name>` - Which tools are being used
- `Response time: <ms>` - Performance metrics
- `Error:` - Failed tool invocations or data access issues
- `Model inference failed` - Model serving problems

### Notebook Update Decision Matrix

Use this matrix to decide which notebooks to update based on MCP server interactions:

| Issue Observed | Notebook to Update | Priority |
|----------------|-------------------|----------|
| Health check failure | `00-setup/00-platform-readiness-validation.ipynb` | HIGH |
| False positive anomaly | `02-anomaly-detection/01-isolation-forest-implementation.ipynb` | HIGH |
| Missed anomaly | `02-anomaly-detection/02-time-series-anomaly-detection.ipynb` | HIGH |
| Remediation failure | `03-self-healing-logic/coordination-engine-integration.ipynb` | CRITICAL |
| Model serving timeout | `04-model-serving/kserve-model-deployment.ipynb` | HIGH |
| Slow inference | `07-monitoring-operations/model-performance-monitoring.ipynb` | MEDIUM |
| Inaccurate recommendations | `05-end-to-end-scenarios/*.ipynb` | MEDIUM |
| New use case identified | Create new notebook in appropriate category | MEDIUM |

### Example: Complete Interaction → Notebook Update Cycle

**Step 1: User Query**
```
User: "Why is the predictive-analytics pod restarting frequently?"
```

**Step 2: MCP Server Response**
```
Lightspeed: "The predictive-analytics pod has restarted 12 times in the last hour
due to memory pressure (OOMKilled). Current memory usage: 1.8GB / 2GB limit."
```

**Step 3: Identify Gap**
- Memory limit too low for current workload
- No proactive detection of memory pressure before OOM

**Step 4: Update Notebooks**
1. **`02-anomaly-detection/03-lstm-based-prediction.ipynb`**
   - Add memory pressure detection
   - Train model to predict OOM before it happens
   - Adjust warning thresholds

2. **`05-end-to-end-scenarios/resource-exhaustion-detection.ipynb`**
   - Add memory pressure scenario
   - Implement proactive scaling logic

3. **`04-model-serving/kserve-model-deployment.ipynb`**
   - Update resource requests/limits based on actual usage
   - Add autoscaling based on memory metrics

**Step 5: Deploy Updates**
```bash
# Run validation jobs to retrain models
oc get notebookvalidationjob -n self-healing-platform

# Or manually run in workbench
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
# Open notebooks and execute
```

**Step 6: Verify**
```
User: "Are there any memory pressure issues now?"
Lightspeed: "No memory pressure detected. All pods are within 70% of memory limits.
Proactive scaling recommendations are now available in the coordination engine."
```

---

## Next Steps

- **Explore MCP Tools**: Try different tools via Lightspeed queries
- **Monitor Interactions**: Track which queries are most common
- **Iterative Improvement**: Use the workflow above to enhance notebooks
- **Scale**: Increase replicas for high-traffic environments

## Related Documentation

- [ADR-014: Cluster Health MCP Server](../adrs/014-openshift-aiops-platform-mcp-server.md) - Architecture and design decisions
- [Notebook: MCP Server Integration](../../notebooks/06-mcp-lightspeed-integration/mcp-server-integration.ipynb) - Development and testing
- [Notebook: OpenShift Lightspeed Integration](../../notebooks/06-mcp-lightspeed-integration/openshift-lightspeed-integration.ipynb) - Advanced usage
- [MCP Protocol Documentation](https://modelcontextprotocol.io/) - Upstream MCP specification

## Support

For issues, questions, or contributions:
- Check existing ADRs in `docs/adrs/`
- Review notebooks in `notebooks/06-mcp-lightspeed-integration/`
- Open an issue in the project repository
