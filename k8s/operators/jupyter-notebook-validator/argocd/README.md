# ArgoCD Integration for Jupyter Notebook Validator Operator

This directory contains ArgoCD integration resources for the Jupyter Notebook Validator Operator v1.0.5+.

## Features

- **Health Assessment**: NotebookValidationJob status visible in ArgoCD UI
- **Post-Success Resource Hooks**: Auto-restart InferenceServices when notebooks succeed
- **Sync Wave Awareness**: Coordinate notebook execution with ArgoCD deployment waves
- **Application Status Integration**: Aggregated notebook status in ArgoCD Applications
- **Notification Events**: Kubernetes Events for ArgoCD notifications

## Installation

### 1. Apply Health Check ConfigMap

```bash
kubectl apply -f health-check-configmap.yaml

# Restart ArgoCD application-controller to reload health checks
kubectl rollout restart deployment argocd-application-controller -n argocd
```

### 2. Verify Installation

```bash
# Check ConfigMap applied
oc get cm argocd-cm -n argocd -o yaml | grep NotebookValidationJob

# Verify ArgoCD reloaded (wait for deployment to be ready)
oc rollout status deployment argocd-application-controller -n argocd
```

## Usage

### Auto-Restart InferenceServices

Add annotation to NotebookValidationJob to automatically restart InferenceServices when notebook validation succeeds:

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: predictive-analytics-kserve-validation
  namespace: self-healing-platform
  annotations:
    # ArgoCD sync wave - run notebook before InferenceService
    argocd.argoproj.io/sync-wave: "3"

    # CRITICAL: Auto-restart InferenceService when notebook succeeds
    mlops.dev/on-success-trigger: |
      - apiVersion: serving.kserve.io/v1beta1
        kind: InferenceService
        name: predictive-analytics
        namespace: self-healing-platform
        action: restart

    # Optional: Block next wave until this completes
    mlops.dev/block-wave: "4"
spec:
  # ... notebook validation spec
```

### Health Status in ArgoCD UI

Once installed, NotebookValidationJob resources will show health status in ArgoCD:

- **Healthy**: Validation succeeded
- **Degraded**: Validation failed
- **Progressing**: Validation in progress

## References

- Operator ADR-049: ArgoCD Integration Strategy
- Operator docs: `/home/lab-user/jupyter-notebook-validator-operator/docs/ARGOCD_INTEGRATION.md`
- Platform ADR-029: Jupyter Notebook Validator Operator
