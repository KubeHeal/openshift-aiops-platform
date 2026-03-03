#!/bin/bash
# Validate that values-hub.yaml topology matches actual cluster topology

set -e

echo "=========================================="
echo "Topology Validation"
echo "=========================================="

# Detect actual cluster topology
if ./scripts/detect-cluster-topology.sh >/dev/null 2>&1; then
    ACTUAL_TOPOLOGY="ha"
else
    ACTUAL_TOPOLOGY="sno"
fi
echo "Actual cluster topology: $ACTUAL_TOPOLOGY"

# Read configured topology from values-hub.yaml
CONFIGURED_TOPOLOGY=$(yq '.cluster.topology' values-hub.yaml)
echo "Configured topology (values-hub.yaml): $CONFIGURED_TOPOLOGY"

# Validate match
if [ "$ACTUAL_TOPOLOGY" != "$CONFIGURED_TOPOLOGY" ]; then
    echo ""
    echo "❌ ERROR: Topology mismatch detected!"
    echo ""
    echo "  Cluster is: $ACTUAL_TOPOLOGY"
    echo "  values-hub.yaml says: $CONFIGURED_TOPOLOGY"
    echo ""
    echo "This will cause deployment failures (wrong storage classes, etc.)"
    echo ""
    echo "To fix, run: make show-cluster-info"
    echo "Then update values-hub.yaml:"
    echo "  cluster.topology: \"$ACTUAL_TOPOLOGY\""
    if [ "$ACTUAL_TOPOLOGY" = "sno" ]; then
        echo "  storage.modelArtifacts.storageClass: \"gp3-csi\""
        echo "  storage.modelStorage.storageClass: \"gp3-csi\""
    else
        echo "  storage.modelArtifacts.storageClass: \"ocs-storagecluster-cephfs\""
        echo "  storage.modelStorage.storageClass: \"ocs-storagecluster-cephfs\""
    fi
    echo ""
    exit 1
fi

echo ""
echo "✅ Topology validation passed!"
echo "   Cluster and configuration both set to: $ACTUAL_TOPOLOGY"
echo ""
