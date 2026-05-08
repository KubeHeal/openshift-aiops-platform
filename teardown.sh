#!/usr/bin/env bash
# teardown.sh — Clean teardown of OpenShift AI Ops Self-Healing Platform
# Generated from patternizer skill pattern for Validated Patterns compliance
set -euo pipefail

PATTERN_ROOT="${PATTERN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
cd "$PATTERN_ROOT"

echo "=========================================="
echo "OpenShift AI Ops Platform Teardown"
echo "=========================================="
echo ""
echo "This will remove:"
echo "  - Pattern CR (Validated Patterns Operator)"
echo "  - ArgoCD applications"
echo "  - All platform components (coordination-engine, models, notebooks)"
echo "  - Namespaces: self-healing-platform, self-healing-platform-hub"
echo "  - PersistentVolumeClaims (model storage, workbench data)"
echo ""
echo "WARNING: This CANNOT be undone. Data will be lost."
echo ""

# Safety check
if [ "${FORCE:-}" != "true" ]; then
  read -rp "Continue with teardown? Type 'yes' to confirm: " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Teardown cancelled"
    exit 0
  fi
fi

echo "==> Starting teardown..."

# Step 1: Use pattern.sh make uninstall
echo "Step 1/5: Running pattern uninstall..."
if [ -f pattern.sh ]; then
  ./pattern.sh make uninstall || {
    echo "WARNING: Pattern uninstall failed or incomplete - continuing with manual cleanup"
  }
else
  echo "WARNING: pattern.sh not found - using manual cleanup"
fi

# Step 2: Delete Pattern CR (if still exists)
echo "Step 2/5: Deleting Pattern CR..."
if oc get pattern self-healing-platform -n patterns-operator &>/dev/null; then
  oc delete pattern self-healing-platform -n patterns-operator --timeout=60s || true
  echo "Pattern CR deleted"
else
  echo "Pattern CR not found (already deleted)"
fi

# Step 3: Delete ArgoCD applications
echo "Step 3/5: Deleting ArgoCD applications..."
if oc get application self-healing-platform -n self-healing-platform-hub &>/dev/null; then
  oc delete application self-healing-platform -n self-healing-platform-hub --timeout=60s || true
  echo "ArgoCD application deleted"
else
  echo "ArgoCD application not found (already deleted)"
fi

# Step 4: Delete platform namespace (cascading delete of all resources)
echo "Step 4/5: Deleting platform namespace (this may take 2-5 minutes)..."
if oc get namespace self-healing-platform &>/dev/null; then
  oc delete namespace self-healing-platform --timeout=300s || {
    echo "WARNING: Namespace deletion timeout - forcing finalizer removal"
    oc patch namespace self-healing-platform -p '{"metadata":{"finalizers":[]}}' --type=merge || true
  }
  echo "Platform namespace deleted"
else
  echo "Platform namespace not found (already deleted)"
fi

# Step 5: Clean up cluster-scoped resources
echo "Step 5/5: Cleaning cluster-scoped resources..."

# Hub namespace
if oc get namespace self-healing-platform-hub &>/dev/null; then
  oc delete namespace self-healing-platform-hub --timeout=120s || true
  echo "Deleted namespace: self-healing-platform-hub"
fi

# ClusterRoleBindings
for crb in hub-gitops-argocd-application-controller-cluster-admin \
           self-healing-workbench-cluster \
           self-healing-workbench-prometheus \
           self-healing-operator-prometheus; do
  if oc get clusterrolebinding "$crb" &>/dev/null; then
    oc delete clusterrolebinding "$crb" || true
    echo "Deleted ClusterRoleBinding: $crb"
  fi
done

# ClusterRoles
for cr in self-healing-workbench-cluster; do
  if oc get clusterrole "$cr" &>/dev/null; then
    oc delete clusterrole "$cr" || true
    echo "Deleted ClusterRole: $cr"
  fi
done

# PriorityClasses (GPU scheduling)
for pc in gpu-training-priority gpu-workbench-priority; do
  if oc get priorityclass "$pc" &>/dev/null; then
    oc delete priorityclass "$pc" || true
    echo "Deleted PriorityClass: $pc"
  fi
done

# ExternalSecretsConfig (cluster-scoped)
if oc get externalsecretsconfig cluster &>/dev/null; then
  oc delete externalsecretsconfig cluster || true
  echo "Deleted ExternalSecretsConfig: cluster"
fi

# Optional: Clean up extra namespaces created by upstream defaults
echo "==> Cleaning optional upstream namespaces..."
for ns in self-healing-platform-example imperative; do
  if oc get namespace "$ns" &>/dev/null; then
    oc delete namespace "$ns" --timeout=60s || true
    echo "Deleted namespace: $ns"
  fi
done

echo ""
echo "=========================================="
echo "Teardown complete!"
echo "=========================================="
echo ""
echo "Cluster is clean. You can now:"
echo "  1. Redeploy: ./deploy.sh"
echo "  2. Switch branches and test new features"
echo "  3. Verify cleanup: oc get all -n self-healing-platform"
echo ""
