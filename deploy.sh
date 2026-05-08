#!/usr/bin/env bash
# deploy.sh — Deploy OpenShift AI Ops Self-Healing Platform
# Generated from patternizer skill pattern for Validated Patterns compliance
set -euo pipefail

PATTERN_ROOT="${PATTERN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
cd "$PATTERN_ROOT"

echo "=========================================="
echo "OpenShift AI Ops Platform Deployment"
echo "=========================================="

# Prerequisites validation
echo "==> Validating prerequisites..."

# Check kubeconfig
if ! oc whoami &>/dev/null; then
  echo "ERROR: Not logged into OpenShift cluster"
  echo "Run: oc login <cluster-url>"
  exit 1
fi

# Check values files
if [ ! -f values-global.yaml ]; then
  echo "ERROR: values-global.yaml not found"
  echo "Run: cp values-global.yaml.example values-global.yaml"
  echo "Then update repoURL to your GitHub fork"
  exit 1
fi

if [ ! -f values-hub.yaml ]; then
  echo "ERROR: values-hub.yaml not found"
  echo "Run: cp values-hub.yaml.example values-hub.yaml"
  echo "Then update repoURL to your GitHub fork"
  exit 1
fi

# Check repoURL is updated (not pointing to upstream)
REPO_URL=$(grep "repoURL:" values-global.yaml | head -1 | awk '{print $2}' | tr -d '"')
if [[ "$REPO_URL" == *"KubeHeal/openshift-aiops-platform"* ]]; then
  echo "WARNING: repoURL still points to upstream repository"
  echo "Update values-global.yaml and values-hub.yaml with YOUR fork URL"
  read -rp "Continue anyway? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
fi

# Check values-secret.yaml (optional but recommended)
if [ ! -f values-secret.yaml ]; then
  echo "INFO: values-secret.yaml not found (optional for public GitHub deployments)"
  echo "If using External Secrets Operator, ensure SecretStore backend is configured"
fi

# Cluster topology detection
echo "==> Detecting cluster topology..."
TOPOLOGY=$(make show-cluster-info 2>/dev/null | grep "Topology:" | awk '{print $2}' || echo "unknown")
echo "Cluster topology: $TOPOLOGY"

if [ "$TOPOLOGY" == "sno" ]; then
  echo "INFO: Deploying on Single Node OpenShift (SNO)"
  echo "GPU will be disabled for workbench to avoid contention (Issue #74 fix)"

  # Verify values-hub.yaml has correct SNO settings
  if ! grep -q "topology: sno" values-hub.yaml; then
    echo "WARNING: values-hub.yaml does not have 'cluster.topology: sno'"
    echo "GPU contention fix requires this setting"
    read -rp "Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
  fi
fi

# Execution Environment check
echo "==> Checking Execution Environment..."
if ! podman images | grep -q "openshift-aiops-platform-ee"; then
  echo "INFO: Execution Environment image not found locally"
  echo "Pulling from quay.io/takinosh/openshift-aiops-platform-ee:latest..."
  podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
  podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest openshift-aiops-platform-ee:latest
fi

# Deployment
echo "==> Starting deployment..."
echo "Using: ./pattern.sh make operator-deploy"
echo "Note: Skipping traditional VP secret loading (using ESO with source secrets)"
echo ""

# Run deployment via pattern.sh (operator-deploy skips load-secrets)
./pattern.sh make operator-deploy

echo ""
echo "=========================================="
echo "Deployment initiated successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Monitor deployment: make argo-healthcheck"
echo "  2. Watch pods: watch oc get pods -n self-healing-platform"
echo "  3. View ArgoCD UI: oc get route -n self-healing-platform-hub"
echo "  4. Run validation: tkn pipeline start deployment-validation-pipeline --showlog"
echo ""
echo "Deployment typically takes 10-15 minutes to complete."
echo ""
