# ADR-018: LlamaStack Integration on OpenShift AI

## Status
accepted - 2025-10-14
**RESEARCH** - 2025-10-14 (Architecture research complete, implementation planning)

## Context

Based on research findings, **LlamaStack** is becoming a key component of **Red Hat OpenShift AI** for enterprise AI agent development. LlamaStack provides:

1. **Standardized AI Agent APIs**: Unified interface for AI application development
2. **MCP Integration**: Native Model Context Protocol support for external data
3. **Enterprise Security**: OpenShift-native security, RBAC, and audit capabilities
4. **On-Premises Deployment**: Full control over AI workloads and data sovereignty
5. **Cost Optimization**: Eliminate external API costs with self-hosted models

### Research Findings

**Red Hat OpenShift AI + LlamaStack Integration**:
- **Official Support**: Red Hat announced LlamaStack integration in OpenShift AI 2025 roadmap
- **MCP Native**: LlamaStack includes built-in MCP client capabilities
- **Demo Architecture**: `opendatahub-io/llama-stack-demos` provides reference implementations
- **Enterprise Ready**: Supports distributed training, model serving, and lifecycle management

**LlamaStack Architecture on OpenShift**:
```
┌─────────────────────────────────────────────────────────────┐
│                 Red Hat OpenShift AI                        │
│  ┌─────────────────┐    ┌──────────────────┐              │
│  │   LlamaStack    │◄───│  Model Registry  │              │
│  │   Runtime       │    │  (Llama Models)  │              │
│  └─────────────────┘    └──────────────────┘              │
│           │                        │                       │
│           ▼                        ▼                       │
│  ┌─────────────────┐    ┌──────────────────┐              │
│  │   MCP Client    │◄───│  vLLM Serving    │              │
│  │   (Built-in)    │    │  Infrastructure  │              │
│  └─────────────────┘    └──────────────────┘              │
└─────────────────────────────────────────────────────────────┘
                    │
                    ▼ MCP Protocol
┌─────────────────────────────────────────────────────────────┐
│              Our MCP Server (ADR-014)                       │
│  ┌─────────────────┐    ┌──────────────────┐              │
│  │  Cluster Health │    │  Self-Healing    │              │
│  │  Resources      │    │  Tools           │              │
│  └─────────────────┘    └──────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

### Integration Requirements

1. **LlamaStack Deployment**: Deploy LlamaStack runtime on OpenShift AI
2. **Model Serving**: Configure Llama 3.2/3.3 models with vLLM
3. **MCP Integration**: Connect LlamaStack to our Cluster Health MCP Server
4. **Security Integration**: OpenShift RBAC, service mesh, and audit logging
5. **Performance Optimization**: GPU scheduling, model caching, and scaling

## Decision

**Deploy LlamaStack on OpenShift AI as a self-hosted alternative** to external LLM providers:

1. **LlamaStack Runtime**: Deploy LlamaStack with Llama 3.2 models on OpenShift AI
2. **vLLM Model Serving**: Use vLLM for high-performance model inference
3. **MCP Integration**: Connect LlamaStack MCP client to our MCP server
4. **Hybrid Architecture**: Support both external providers (ADR-016/017) and LlamaStack
5. **Cost Optimization**: Route appropriate queries to self-hosted models

## Rationale

### **Why LlamaStack on OpenShift AI**
- **Data Sovereignty**: Keep sensitive cluster data within OpenShift boundaries
- **Cost Control**: Eliminate per-token costs for high-volume operations
- **Performance**: Reduced latency with in-cluster model serving
- **Compliance**: Meet strict regulatory requirements for data handling
- **Customization**: Fine-tune models for OpenShift-specific operations

### **Why Hybrid Architecture**
- **Flexibility**: Use best model for each workload type
- **Risk Mitigation**: Fallback to external providers during maintenance
- **Cost Optimization**: Balance self-hosted vs external costs
- **Performance**: Route queries to optimal serving infrastructure

### **Why vLLM Integration**
- **Performance**: Optimized inference with continuous batching
- **Scalability**: Horizontal scaling with Kubernetes
- **Memory Efficiency**: Advanced memory management for large models
- **OpenShift Native**: Integrated with OpenShift AI platform

## Architecture

### **LlamaStack Deployment on OpenShift AI**
```yaml
# LlamaStack Runtime Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llamastack-runtime
  namespace: self-healing-platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app: llamastack-runtime
  template:
    metadata:
      labels:
        app: llamastack-runtime
    spec:
      containers:
      - name: llamastack
        image: llamastack/llamastack:latest
        env:
        - name: LLAMASTACK_CONFIG
          value: /config/llamastack.yaml
        - name: MCP_SERVER_URL
          value: http://cluster-health-mcp-server.self-healing-platform.svc:3000/mcp
        resources:
          requests:
            nvidia.com/gpu: 1
            memory: 16Gi
            cpu: 4
          limits:
            nvidia.com/gpu: 1
            memory: 32Gi
            cpu: 8
        volumeMounts:
        - name: config
          mountPath: /config
        - name: models
          mountPath: /models
      volumes:
      - name: config
        configMap:
          name: llamastack-config
      - name: models
        persistentVolumeClaim:
          claimName: llama-models-pvc
```

### **vLLM Model Serving**
```yaml
# vLLM Serving for Llama Models
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama-3-2-vllm
  namespace: self-healing-platform
spec:
  predictor:
    model:
      modelFormat:
        name: vllm
      runtime: vllm-runtime
      storageUri: s3://models/llama-3.2-3b-instruct
    resources:
      requests:
        nvidia.com/gpu: 1
        memory: 16Gi
      limits:
        nvidia.com/gpu: 1
        memory: 32Gi
    env:
    - name: VLLM_MODEL_NAME
      value: meta-llama/Llama-3.2-3B-Instruct
    - name: VLLM_MAX_MODEL_LEN
      value: "8192"
    - name: VLLM_GPU_MEMORY_UTILIZATION
      value: "0.9"
```

### **LlamaStack Configuration**
```yaml
# LlamaStack Configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: llamastack-config
  namespace: self-healing-platform
data:
  llamastack.yaml: |
    # LlamaStack Runtime Configuration
    runtime:
      name: openshift-llamastack
      version: 1.0.0

    # Model Configuration
    models:
      - name: llama-3.2-3b
        provider: vllm
        endpoint: http://llama-3-2-vllm-predictor.self-healing-platform.svc/v1
        context_window: 8192
        max_tokens: 2048

    # MCP Client Configuration
    mcp:
      servers:
        - name: cluster-health
          transport: http
          url: http://cluster-health-mcp-server.self-healing-platform.svc:3000/mcp
          timeout: 30

    # Agent Configuration
    agents:
      - name: openshift-ops-agent
        model: llama-3.2-3b
        system_prompt: |
          You are an OpenShift operations assistant with access to cluster health data.
          Use the available MCP tools to help with cluster management and troubleshooting.
        mcp_servers:
          - cluster-health
```

### **Enhanced OLSConfig with LlamaStack**
```yaml
# Extended OLSConfig supporting LlamaStack
apiVersion: ols.openshift.io/v1alpha1
kind: OLSConfig
metadata:
  name: cluster
spec:
  featureGates:
    - MCPServer

  llm:
    providers:
      # External Providers (ADR-016/017)
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

      # LlamaStack Provider (Self-hosted)
      - name: llamastack
        type: openai  # OpenAI-compatible API
        url: http://llamastack-runtime.self-healing-platform.svc:8080/v1
        models:
          - name: llama-3.2-3b
            url: http://llamastack-runtime.self-healing-platform.svc:8080/v1/chat/completions
            contextWindowSize: 8192
            parameters:
              maxTokensForResponse: 2048

  # Intelligent routing with LlamaStack preference
  ols:
    defaultProvider: llamastack  # Prefer self-hosted for cost optimization
    defaultModel: llama-3.2-3b

    routingStrategy:
      enabled: true
      rules:
        - condition: "data_sensitivity == 'high'"
          provider: llamastack
          model: llama-3.2-3b
        - condition: "query_complexity == 'low'"
          provider: llamastack
          model: llama-3.2-3b
        - condition: "query_complexity == 'high'"
          provider: openai
          model: gpt-4
      fallback:
        provider: gemini
        model: gemini-pro
```

## Implementation

### **Phase 1: OpenShift AI Setup (Week 1)**

#### **1.1 Install OpenShift AI Operator**
```bash
# Install Red Hat OpenShift AI
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: stable
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

#### **1.2 Configure GPU Node Pool**
```yaml
# GPU-enabled MachineSet for model serving
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  name: gpu-workers
spec:
  template:
    spec:
      providerSpec:
        value:
          instanceType: g4dn.xlarge  # AWS GPU instance
          # Configure GPU drivers and NVIDIA operator
```

### **Phase 2: LlamaStack Deployment (Week 2)**

#### **2.1 Deploy vLLM Model Serving**
```bash
# Deploy Llama 3.2 model with vLLM
oc apply -f k8s/llamastack/llama-3.2-vllm-serving.yaml
```

#### **2.2 Deploy LlamaStack Runtime**
```bash
# Deploy LlamaStack with MCP integration
oc apply -f k8s/llamastack/llamastack-runtime.yaml
```

### **Phase 3: Integration Testing (Week 3)**

#### **3.1 MCP Integration Validation**
```bash
# Test MCP connection from LlamaStack to our server
curl -X POST http://llamastack-runtime.self-healing-platform.svc:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.2-3b",
    "messages": [{"role": "user", "content": "Show cluster health status"}]
  }'
```

## Related ADRs

- **ADR-014**: Cluster Health MCP Server for OpenShift Lightspeed Integration
  - Provides the MCP server that LlamaStack connects to
- **ADR-016**: OpenShift Lightspeed OLSConfig Integration
  - Establishes the OLSConfig pattern extended here for LlamaStack
- **ADR-017**: Gemini Integration for OpenShift Lightspeed
  - Provides multi-provider architecture that includes LlamaStack

## Deployment Integration

**OLSConfig Integration**: LlamaStack provider configuration ready for deployment:

```yaml
# Extended OLSConfig with LlamaStack provider
spec:
  llm:
    providers:
      - name: llamastack
        type: openai  # OpenAI-compatible API
        url: http://llamastack-runtime.self-healing-platform.svc:8080/v1
        models:
          - name: llama-3.2-3b
            url: http://llamastack-runtime.self-healing-platform.svc:8080/v1/chat/completions
            contextWindowSize: 8192
            parameters:
              maxTokensForResponse: 2048

  ols:
    defaultProvider: llamastack  # Prefer self-hosted for cost optimization
    defaultModel: llama-3.2-3b
```

**Deployment Readiness**: Infrastructure templates and scripts updated to support LlamaStack integration alongside existing providers.

## Implementation Status

- ✅ **Research**: LlamaStack + OpenShift AI integration patterns identified
- ✅ **Architecture**: Hybrid deployment architecture defined
- ✅ **OLSConfig Integration**: LlamaStack provider configuration ready
- ⏳ **OpenShift AI Setup**: GPU nodes and operators pending
- ⏳ **LlamaStack Deployment**: Runtime and model serving pending
- ⏳ **MCP Integration**: LlamaStack to MCP server connection pending
- ⏳ **Performance Testing**: Model serving optimization pending

---

*This ADR establishes LlamaStack as a self-hosted alternative to external LLM providers, providing data sovereignty and cost optimization while maintaining integration with our existing MCP server architecture.*
