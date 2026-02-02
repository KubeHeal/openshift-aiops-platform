# GitHub Issue: Dynamic KServe Model Loading Support

**Repository**: `KubeHeal/openshift-coordination-engine`

---

## Title

Support Dynamic KServe Model Loading via KSERVE_MODEL_REGISTRY

## Description

### Summary

The coordination engine should support dynamic discovery of KServe InferenceServices via a JSON-based model registry, allowing users to register custom ML models without modifying the coordination engine code.

### Context

The OpenShift AIOps Platform follows a **user-deployed model architecture** (see [ADR-039](https://github.com/KubeHeal/openshift-aiops-platform/blob/main/docs/adrs/039-user-deployed-kserve-models.md) and [ADR-040](https://github.com/KubeHeal/openshift-aiops-platform/blob/main/docs/adrs/040-extensible-kserve-model-registry.md)) where:

- **Users** train and deploy their own models via KServe InferenceServices
- **Platform** provides coordination engine and infrastructure
- **Goal**: Enable users to register domain-specific models (database anomalies, network prediction, disk failure, etc.) without platform code changes

### Current Limitation

The coordination engine has **hardcoded KServe service discovery**:

```go
// Current approach (hardcoded)
anomalyDetectorURL := os.Getenv("KSERVE_ANOMALY_DETECTOR_SERVICE")
predictiveAnalyticsURL := os.Getenv("KSERVE_PREDICTIVE_ANALYTICS_SERVICE")
```

**Problem**: Users cannot add custom models (e.g., `disk-failure-predictor`, `postgres-query-anomaly`) without coordination engine code changes.

### Proposed Solution

Support dynamic model loading via `KSERVE_MODEL_REGISTRY` environment variable containing a JSON array of model configurations.

#### Example Configuration

```bash
# Environment variable from Helm chart
export KSERVE_MODEL_REGISTRY='[
  {
    "name": "anomaly-detector",
    "service": "anomaly-detector-predictor",
    "namespace": "self-healing-platform",
    "type": "anomaly",
    "description": "Isolation Forest anomaly detection"
  },
  {
    "name": "disk-failure-predictor",
    "service": "disk-failure-predictor-predictor",
    "namespace": "storage-monitoring",
    "type": "predictive",
    "description": "Predicts disk failures using SMART metrics"
  }
]'
```

## Implementation Requirements

### 1. Model Registry Data Structure

```go
// pkg/kserve/types.go
package kserve

type ModelType string

const (
    ModelTypeAnomaly        ModelType = "anomaly"
    ModelTypePredictive     ModelType = "predictive"
    ModelTypeClassification ModelType = "classification"
)

type KServeModel struct {
    Name        string    `json:"name"`        // Unique model identifier
    Service     string    `json:"service"`     // KServe InferenceService name
    Namespace   string    `json:"namespace"`   // Kubernetes namespace (optional)
    Type        ModelType `json:"type"`        // Model type
    Description string    `json:"description"` // Human-readable description (optional)
}

type ModelRegistry struct {
    Models        []KServeModel
    DefaultNS     string
    BaseURLFormat string // "http://{service}.{namespace}.svc.cluster.local"
}
```

### 2. Model Registry Loader

```go
// pkg/kserve/registry.go
package kserve

import (
    "encoding/json"
    "fmt"
    "os"
)

func LoadModelRegistry() (*ModelRegistry, error) {
    registryJSON := os.Getenv("KSERVE_MODEL_REGISTRY")
    if registryJSON == "" {
        return nil, fmt.Errorf("KSERVE_MODEL_REGISTRY not set")
    }

    var models []KServeModel
    if err := json.Unmarshal([]byte(registryJSON), &models); err != nil {
        return nil, fmt.Errorf("failed to parse KSERVE_MODEL_REGISTRY: %w", err)
    }

    defaultNS := os.Getenv("KSERVE_NAMESPACE")
    if defaultNS == "" {
        defaultNS = "self-healing-platform"
    }

    return &ModelRegistry{
        Models:        models,
        DefaultNS:     defaultNS,
        BaseURLFormat: "http://{service}.{namespace}.svc.cluster.local",
    }, nil
}

func (r *ModelRegistry) GetModelURL(modelName string) (string, error) {
    for _, model := range r.Models {
        if model.Name == modelName {
            namespace := model.Namespace
            if namespace == "" {
                namespace = r.DefaultNS
            }
            return fmt.Sprintf("http://%s.%s.svc.cluster.local", model.Service, namespace), nil
        }
    }
    return "", fmt.Errorf("model not found: %s", modelName)
}

func (r *ModelRegistry) GetModelsByType(modelType ModelType) []KServeModel {
    var result []KServeModel
    for _, model := range r.Models {
        if model.Type == modelType {
            result = append(result, model)
        }
    }
    return result
}
```

### 3. API Endpoints

Add REST API endpoints to expose registered models:

```go
// internal/api/models.go
package api

import (
    "net/http"
    "github.com/gin-gonic/gin"
)

// GET /api/v1/models - List all registered models
func (s *Server) listModels(c *gin.Context) {
    c.JSON(http.StatusOK, gin.H{
        "models": s.modelRegistry.Models,
    })
}

// GET /api/v1/models/:name - Get specific model details
func (s *Server) getModel(c *gin.Context) {
    modelName := c.Param("name")

    for _, model := range s.modelRegistry.Models {
        if model.Name == modelName {
            url, _ := s.modelRegistry.GetModelURL(modelName)
            c.JSON(http.StatusOK, gin.H{
                "name":        model.Name,
                "service":     model.Service,
                "namespace":   model.Namespace,
                "type":        model.Type,
                "description": model.Description,
                "url":         url,
            })
            return
        }
    }

    c.JSON(http.StatusNotFound, gin.H{"error": "model not found"})
}

// POST /api/v1/models/:name/predict - Proxy to KServe model
func (s *Server) predictWithModel(c *gin.Context) {
    modelName := c.Param("name")

    modelURL, err := s.modelRegistry.GetModelURL(modelName)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
        return
    }

    // Forward request to KServe InferenceService
    // POST {modelURL}/v1/models/{modelName}:predict
    // ... proxy implementation ...
}
```

### 4. Startup Validation

```go
// cmd/coordination-engine/main.go
package main

import (
    "log"
    "github.com/KubeHeal/openshift-coordination-engine/pkg/kserve"
)

func main() {
    // Load model registry at startup
    registry, err := kserve.LoadModelRegistry()
    if err != nil {
        log.Fatalf("Failed to load model registry: %v", err)
    }

    log.Printf("Loaded %d models from registry:", len(registry.Models))
    for _, model := range registry.Models {
        url, _ := registry.GetModelURL(model.Name)
        log.Printf("  - %s (%s) at %s", model.Name, model.Type, url)
    }

    // Continue with server initialization...
}
```

### 5. Backward Compatibility

Support both old (hardcoded) and new (dynamic) configurations:

```go
func LoadModelRegistryWithFallback() (*ModelRegistry, error) {
    // Try new approach first
    registry, err := LoadModelRegistry()
    if err == nil {
        return registry, nil
    }

    // Fall back to old approach (hardcoded env vars)
    log.Println("KSERVE_MODEL_REGISTRY not found, using legacy configuration")

    models := []KServeModel{}
    if svc := os.Getenv("KSERVE_ANOMALY_DETECTOR_SERVICE"); svc != "" {
        models = append(models, KServeModel{
            Name:    "anomaly-detector",
            Service: svc,
            Type:    ModelTypeAnomaly,
        })
    }
    if svc := os.Getenv("KSERVE_PREDICTIVE_ANALYTICS_SERVICE"); svc != "" {
        models = append(models, KServeModel{
            Name:    "predictive-analytics",
            Service: svc,
            Type:    ModelTypePredictive,
        })
    }

    return &ModelRegistry{
        Models:    models,
        DefaultNS: os.Getenv("KSERVE_NAMESPACE"),
    }, nil
}
```

## Helm Chart Integration

The platform Helm chart will pass the model registry via environment variable:

```yaml
# charts/hub/templates/coordination-engine.yaml
env:
  - name: ENABLE_KSERVE_INTEGRATION
    value: "true"
  - name: KSERVE_NAMESPACE
    value: {{ .Values.coordinationEngine.kserve.namespace | default .Release.Namespace | quote }}
  - name: KSERVE_MODEL_REGISTRY
    value: {{ toJson .Values.coordinationEngine.kserve.models | quote }}
```

## Testing Requirements

### Unit Tests

```go
// pkg/kserve/registry_test.go
func TestLoadModelRegistry(t *testing.T) {
    os.Setenv("KSERVE_MODEL_REGISTRY", `[
        {"name": "anomaly-detector", "service": "anomaly-detector-predictor", "type": "anomaly"},
        {"name": "disk-predictor", "service": "disk-predictor", "namespace": "storage", "type": "predictive"}
    ]`)

    registry, err := LoadModelRegistry()
    assert.NoError(t, err)
    assert.Len(t, registry.Models, 2)
}

func TestGetModelURL(t *testing.T) {
    registry := &ModelRegistry{
        Models: []KServeModel{
            {Name: "test-model", Service: "test-predictor", Namespace: "test-ns"},
        },
        DefaultNS: "default",
    }

    url, err := registry.GetModelURL("test-model")
    assert.NoError(t, err)
    assert.Equal(t, "http://test-predictor.test-ns.svc.cluster.local", url)
}
```

### Integration Tests

- Deploy coordination engine with custom model registry
- Register 3+ models in different namespaces
- Verify `/api/v1/models` returns all registered models
- Test prediction proxy to each model

## Success Criteria

- [ ] Coordination engine loads models from `KSERVE_MODEL_REGISTRY` JSON
- [ ] Supports multi-namespace model deployment
- [ ] `/api/v1/models` API endpoint lists registered models
- [ ] `/api/v1/models/:name/predict` proxies to KServe InferenceServices
- [ ] Backward compatible with old `KSERVE_ANOMALY_DETECTOR_SERVICE` env vars
- [ ] Unit tests for model registry loading
- [ ] Integration tests with 3+ custom models
- [ ] Documentation updated (API.md, README.md)

## Documentation

Update the following files in `KubeHeal/openshift-coordination-engine`:

1. **README.md**: Add "Model Registry Configuration" section
2. **API.md**: Document `/api/v1/models` endpoints
3. **CONFIGURATION.md**: Document `KSERVE_MODEL_REGISTRY` environment variable

## Example User Workflow

**Before** (hardcoded, limited):
```bash
# User cannot add custom models
```

**After** (dynamic, extensible):
```yaml
# values-hub.yaml in openshift-aiops-platform
coordinationEngine:
  kserve:
    models:
      - name: anomaly-detector
        service: anomaly-detector-predictor
        type: anomaly
      - name: disk-failure-predictor  # USER ADDS THIS
        service: disk-failure-predictor-predictor
        namespace: storage-monitoring
        type: predictive
```

```bash
# Deploy platform
helm upgrade self-healing-platform charts/hub -f values-hub.yaml

# Verify model registered
curl http://coordination-engine:8080/api/v1/models
# {
#   "models": [
#     {"name": "anomaly-detector", ...},
#     {"name": "disk-failure-predictor", ...}
#   ]
# }

# Use custom model
curl -X POST http://coordination-engine:8080/api/v1/models/disk-failure-predictor/predict \
  -d '{"instances": [[85.5, 5000, 365]]}'
```

## References

- **Platform ADR-039**: [User-Deployed KServe Models](https://github.com/KubeHeal/openshift-aiops-platform/blob/main/docs/adrs/039-user-deployed-kserve-models.md)
- **Platform ADR-040**: [Extensible KServe Model Registry](https://github.com/KubeHeal/openshift-aiops-platform/blob/main/docs/adrs/040-extensible-kserve-model-registry.md)
- **User Guide**: [USER-MODEL-DEPLOYMENT-GUIDE.md](https://github.com/KubeHeal/openshift-aiops-platform/blob/main/docs/guides/USER-MODEL-DEPLOYMENT-GUIDE.md)
- **KServe v1 Prediction API**: https://kserve.github.io/website/latest/modelserving/data_plane/v1_protocol/

## Labels

- `enhancement`
- `kserve-integration`
- `user-extensibility`
- `platform-agnostic`

## Priority

**Medium** - Enables user extensibility but platform functions with default models

## Milestone

**v2.0.0** - Next major release with extensibility features

---

**Created by**: OpenShift AIOps Platform Team
**Related Platform Issue**: N/A (architecture decision)
