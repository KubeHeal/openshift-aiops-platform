#!/usr/bin/env bash
# deploy.sh - Deploy OpenShift AI Ops Self-Healing Platform
# Supports: HA and SNO topologies, non-interactive mode (-y)
set -euo pipefail

PATTERN_ROOT="${PATTERN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
cd "$PATTERN_ROOT"

AUTO_YES="${1:-}"

confirm() {
  if [[ "$AUTO_YES" == "-y" || "$AUTO_YES" == "--yes" ]]; then
    return 0
  fi
  read -rp "$1 [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

echo "=========================================="
echo "OpenShift AI Ops Platform Deployment"
echo "=========================================="

# Prerequisites validation
echo "==> Validating prerequisites..."

if ! oc whoami &>/dev/null; then
  echo "ERROR: Not logged into OpenShift cluster"
  echo "Run: oc login <cluster-url>"
  exit 1
fi

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

REPO_URL=$(grep "repoURL:" values-global.yaml | head -1 | awk '{print $2}' | tr -d '"')
if [[ "$REPO_URL" == *"KubeHeal/openshift-aiops-platform"* ]]; then
  echo "WARNING: repoURL still points to upstream repository"
  echo "Update values-global.yaml and values-hub.yaml with YOUR fork URL"
  confirm "Continue anyway?" || exit 0
fi

# Cluster topology detection
echo "==> Detecting cluster topology..."
TOPOLOGY=$(make show-cluster-info 2>/dev/null | grep "Topology:" | awk '{print $2}' || echo "unknown")
echo "Cluster topology: $TOPOLOGY"

if [ "$TOPOLOGY" == "sno" ]; then
  echo "WARNING: Deploying on Single Node OpenShift (SNO)"
  echo "Ensure values-hub.yaml is configured for SNO"
  echo "  cluster.topology: sno"
  echo "  storage.modelStorage.storageClass: gp3-csi"
  confirm "Continue with SNO deployment?" || exit 0
fi

# Execution Environment check
echo "==> Checking Execution Environment..."
if ! podman images --format '{{.Repository}}' 2>/dev/null | grep -q "openshift-aiops-platform-ee"; then
  echo "Pulling Execution Environment image..."
  podman pull quay.io/takinosh/openshift-aiops-platform-ee:latest
  podman tag quay.io/takinosh/openshift-aiops-platform-ee:latest openshift-aiops-platform-ee:latest
fi

# Deployment
echo "==> Starting deployment..."
echo "Step 1/3: Deploying prerequisites (RBAC, namespaces, secrets)..."
make operator-deploy-prereqs

echo "Step 2/3: Deploying pattern via Validated Patterns Operator..."
make operator-deploy

echo "Step 3/3: Waiting for ArgoCD application (max 120s)..."
if oc wait --for=jsonpath='{.kind}'=Application \
  application/self-healing-platform -n self-healing-platform-hub --timeout=120s 2>/dev/null; then
  echo "ArgoCD application created successfully"
else
  echo "WARNING: ArgoCD application creation timeout - check manually"
fi

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
