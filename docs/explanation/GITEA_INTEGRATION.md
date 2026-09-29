# Gitea Integration for Self-Healing Platform

This document describes how the Self-Healing Platform integrates with Gitea for MLOps workflows, source code management, and model versioning.

## 🎯 Overview

The Self-Healing Platform can automatically detect and integrate with Gitea when available in the cluster. This integration provides:

- **MLOps Repository Management**: Store and version ML models, pipelines, and configurations
- **Source Code Management**: Manage coordination engine and custom component code
- **Model Versioning**: Track model artifacts and experiment results
- **Pipeline Definitions**: Store Kubeflow pipeline definitions and configurations
- **Documentation**: Maintain platform documentation and runbooks

## 🔍 Automatic Detection

The bootstrap script automatically detects Gitea by running:
```bash
oc get all -n gitea
```

If Gitea is found and running, the platform will:
1. Configure Jupyter notebooks with Gitea environment variables
2. Create integration ConfigMaps
3. Set up repository templates for MLOps workflows
4. Enable Git-based model versioning

## 📁 Repository Structure

When Gitea integration is enabled, the following repository structure is recommended:

```
self-healing/
├── model-templates/              # ML model templates and examples
│   ├── anomaly-detection/
│   ├── predictive-analytics/
│   └── common-utilities/
├── mlops-pipelines/              # Kubeflow pipeline definitions
│   ├── training-pipelines/
│   ├── deployment-pipelines/
│   └── monitoring-pipelines/
├── coordination-engine/          # Coordination engine source code
│   ├── src/
│   ├── tests/
│   └── configs/
├── model-artifacts/              # Versioned model artifacts
│   ├── anomaly-detector/
│   └── predictive-analytics/
└── documentation/                # Platform documentation
    ├── runbooks/
    ├── troubleshooting/
    └── api-docs/
```

## 🔧 Configuration Details

### Environment Variables

When Gitea is detected, the following environment variables are configured:

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `GITEA_URL` | External Gitea URL | `https://gitea.apps.cluster.local` |
| `GITEA_SERVICE_URL` | Internal service URL | `http://gitea-http.gitea.svc.cluster.local:3000` |
| `GITEA_ENABLED` | Integration status | `true` |
| `GIT_REPO_TEMPLATE` | Template repository URL | `https://gitea.../self-healing/model-templates.git` |
| `MLOPS_REPO_URL` | MLOps pipeline repository | `https://gitea.../self-healing/mlops-pipelines.git` |

### ConfigMap Configuration

The integration creates a ConfigMap with Gitea settings:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gitea-integration-config
  namespace: self-healing-platform
data:
  GITEA_URL: "https://gitea.apps.cluster.local"
  GITEA_SERVICE_URL: "http://gitea-http.gitea.svc.cluster.local:3000"
  GITEA_ENABLED: "true"
  GIT_REPO_TEMPLATE: "https://gitea.../self-healing/model-templates.git"
  MLOPS_REPO_URL: "https://gitea.../self-healing/mlops-pipelines.git"
```

## 🚀 MLOps Workflow Integration

### Model Development Workflow

1. **Clone Template Repository**:
   ```bash
   git clone $GIT_REPO_TEMPLATE my-new-model
   cd my-new-model
   ```

2. **Develop Model in Jupyter**:
   - Use pre-configured environment variables
   - Access Gitea repositories directly from notebooks
   - Commit and push changes regularly

3. **Version Model Artifacts**:
   ```bash
   git add model.pkl scaler.pkl
   git commit -m "Model v1.2.3 - improved accuracy to 85%"
   git tag v1.2.3
   git push origin main --tags
   ```

### Pipeline Integration

Kubeflow pipelines can reference Gitea repositories:

```python
from kfp import dsl

@dsl.component
def clone_model_repo():
    """Clone model repository from Gitea"""
    import subprocess
    import os

    gitea_url = os.environ.get('GITEA_SERVICE_URL')
    repo_url = f"{gitea_url}/self-healing/model-templates.git"

    subprocess.run(['git', 'clone', repo_url, '/tmp/model-repo'])
    return '/tmp/model-repo'
```

## 🔒 Security Considerations

### Authentication

For production deployments, configure Git credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitea-credentials
  namespace: self-healing-platform
type: kubernetes.io/basic-auth
stringData:
  username: "self-healing-bot"
  password: "secure-token"
```

### Access Control

Recommended Gitea organization structure:
- **self-healing-admin**: Full access to all repositories
- **self-healing-dev**: Read/write access to development repositories
- **self-healing-readonly**: Read-only access for monitoring and auditing

### Network Security

Configure network policies to allow communication:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-gitea-access
  namespace: self-healing-platform
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: self-healing-platform
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: gitea
    ports:
    - protocol: TCP
      port: 3000
```

## 📊 Monitoring and Observability

### Gitea Health Checks

The validation script includes Gitea health checks:
- Gitea deployment status
- Service accessibility
- Route configuration
- Integration ConfigMap presence

### Metrics Integration

Monitor Gitea usage through:
- Repository commit frequency
- Model artifact versions
- Pipeline execution from Git triggers

## 🛠️ Manual Setup (if Gitea not auto-detected)

If you have Gitea in a different namespace or configuration:

1. **Set Environment Variables**:
   ```bash
   export GITEA_AVAILABLE=true
   export GITEA_URL="https://your-gitea-url.com"
   ```

2. **Run Bootstrap with Gitea**:
   ```bash
   ./bootstrap.sh --environment development
   ```

3. **Manually Configure Integration**:
   ```bash
   oc create configmap gitea-integration-config \
     --from-literal=GITEA_URL="https://your-gitea-url.com" \
     --from-literal=GITEA_ENABLED="true" \
     -n self-healing-platform
   ```

## 🔄 Backup and Disaster Recovery

### Repository Backup

Ensure Gitea repositories are included in backup strategies:
- Model artifacts and code
- Pipeline definitions
- Configuration files
- Documentation

### Recovery Procedures

In case of Gitea unavailability:
1. Platform continues to function with cached models
2. New model development paused until Gitea recovery
3. Fallback to external Git repositories if configured

## 📚 Best Practices

### Repository Management
- Use semantic versioning for models (v1.2.3)
- Tag releases with performance metrics
- Maintain clear commit messages
- Use branch protection for main branches

### Model Versioning
- Store model metadata alongside artifacts
- Include training data checksums
- Document model performance metrics
- Maintain model lineage information

### Pipeline Management
- Version pipeline definitions
- Use GitOps for pipeline deployments
- Maintain pipeline documentation
- Test pipelines in development branches

## 🆘 Troubleshooting

### Common Issues

1. **Gitea Not Detected**:
   ```bash
   # Check Gitea namespace and deployment
   oc get all -n gitea
   oc describe deployment gitea -n gitea
   ```

2. **Authentication Failures**:
   ```bash
   # Check credentials and network connectivity
   oc exec -it deployment/coordination-engine -- curl -I http://gitea-http.gitea.svc.cluster.local:3000
   ```

3. **Repository Access Issues**:
   ```bash
   # Test Git operations from notebook
   git clone http://gitea-http.gitea.svc.cluster.local:3000/self-healing/model-templates.git
   ```

### Debug Commands

```bash
# Check Gitea integration status
oc get configmap gitea-integration-config -n self-healing-platform -o yaml

# Verify environment variables in notebook
oc exec -it deployment/self-healing-workbench -- env | grep GITEA

# Test Gitea connectivity
oc run test-gitea --image=curlimages/curl --rm -it -- curl -I http://gitea-http.gitea.svc.cluster.local:3000
```

## 📖 References

- [Gitea Documentation](https://docs.gitea.io/)
- [Kubeflow Pipelines Git Integration](https://www.kubeflow.org/docs/components/pipelines/)
- [Self-Healing Platform ADRs](adrs/)
- [MLOps Best Practices](https://ml-ops.org/)
