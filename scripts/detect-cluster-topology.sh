#!/bin/bash

# Script: detect-cluster-topology.sh
# Purpose: Detect OpenShift cluster topology (SNO vs HA)
# Exit Codes:
#   0 = HA (HighlyAvailable)
#   1 = SNO (SingleReplica)
#   2 = Unknown topology
#   3 = Error querying cluster

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if verbose mode is enabled
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]] || [[ "${1:-}" == "-v" ]]; then
    VERBOSE=true
fi

# Function to print verbose messages
verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "$1"
    fi
}

# Check if oc is available
if ! command -v oc &> /dev/null; then
    echo -e "${RED}ERROR: 'oc' command not found. Please install the OpenShift CLI.${NC}" >&2
    exit 3
fi

# Check if logged into cluster
if ! oc whoami &> /dev/null; then
    echo -e "${RED}ERROR: Not logged into an OpenShift cluster. Please run 'oc login'.${NC}" >&2
    exit 3
fi

# Query cluster infrastructure
verbose "${GREEN}Querying cluster infrastructure...${NC}"

INFRASTRUCTURE_JSON=$(oc get infrastructure cluster -o json 2>&1)
if [[ $? -ne 0 ]]; then
    echo -e "${RED}ERROR: Failed to query cluster infrastructure.${NC}" >&2
    echo "$INFRASTRUCTURE_JSON" >&2
    exit 3
fi

# Extract topology information
CONTROL_PLANE_TOPOLOGY=$(echo "$INFRASTRUCTURE_JSON" | jq -r '.status.controlPlaneTopology // "Unknown"')
INFRASTRUCTURE_TOPOLOGY=$(echo "$INFRASTRUCTURE_JSON" | jq -r '.status.infrastructureTopology // "Unknown"')
PLATFORM_TYPE=$(echo "$INFRASTRUCTURE_JSON" | jq -r '.status.platformStatus.type // "Unknown"')

# Display verbose information
if [[ "$VERBOSE" == "true" ]]; then
    echo ""
    echo -e "${GREEN}=== Cluster Topology Information ===${NC}"
    echo -e "Control Plane Topology:    ${YELLOW}${CONTROL_PLANE_TOPOLOGY}${NC}"
    echo -e "Infrastructure Topology:   ${YELLOW}${INFRASTRUCTURE_TOPOLOGY}${NC}"
    echo -e "Platform Type:             ${YELLOW}${PLATFORM_TYPE}${NC}"
    echo ""
fi

# Determine cluster type
if [[ "$CONTROL_PLANE_TOPOLOGY" == "SingleReplica" ]] && [[ "$INFRASTRUCTURE_TOPOLOGY" == "SingleReplica" ]]; then
    # SNO cluster
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${GREEN}Cluster Type:              ${YELLOW}SNO (Single Node OpenShift)${NC}"
        echo ""
        echo -e "${YELLOW}Characteristics:${NC}"
        echo "  - Single node with all roles (control-plane, master, worker)"
        echo "  - No MachineSet scaling support"
        echo "  - ODF (OpenShift Data Foundation) not supported"
        echo "  - CSI storage classes only"
        echo "  - Resource-constrained environment"
    else
        echo "SNO"
    fi
    exit 1
elif [[ "$CONTROL_PLANE_TOPOLOGY" == "HighlyAvailable" ]] && [[ "$INFRASTRUCTURE_TOPOLOGY" == "HighlyAvailable" ]]; then
    # HA (HighlyAvailable) cluster
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${GREEN}Cluster Type:              ${YELLOW}HA (HighlyAvailable)${NC}"
        echo ""
        echo -e "${YELLOW}Characteristics:${NC}"
        echo "  - Multiple nodes (3+ recommended)"
        echo "  - Separate control-plane and worker nodes"
        echo "  - MachineSet scaling supported"
        echo "  - ODF (OpenShift Data Foundation) supported"
        echo "  - Full storage options (ODF + CSI)"
        echo "  - Production-ready high availability"
    else
        echo "HA"
    fi
    exit 0
else
    # Unknown topology
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${RED}Cluster Type:              Unknown/Unsupported${NC}"
        echo ""
        echo -e "${RED}This cluster has an unexpected topology configuration:${NC}"
        echo "  Control Plane: $CONTROL_PLANE_TOPOLOGY"
        echo "  Infrastructure: $INFRASTRUCTURE_TOPOLOGY"
    else
        echo "Unknown"
    fi
    exit 2
fi
