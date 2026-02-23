#!/bin/bash

# Script: detect-ocp-version.sh
# Purpose: Detect OpenShift version and map to overlay/channel names
# Exit Codes:
#   0 = Success
#   1 = Error querying cluster

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if verbose mode is enabled
VERBOSE=false
OUTPUT_FORMAT="version"  # version, overlay, channel, all

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --overlay)
            OUTPUT_FORMAT="overlay"
            shift
            ;;
        --channel)
            OUTPUT_FORMAT="channel"
            shift
            ;;
        --all)
            OUTPUT_FORMAT="all"
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            echo "Usage: $0 [--verbose] [--overlay|--channel|--all]" >&2
            exit 1
            ;;
    esac
done

# Function to print verbose messages
verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "$1" >&2
    fi
}

# Check if oc is available
if ! command -v oc &> /dev/null; then
    echo -e "${RED}ERROR: 'oc' command not found. Please install the OpenShift CLI.${NC}" >&2
    exit 1
fi

# Check if logged into cluster
if ! oc whoami &> /dev/null; then
    echo -e "${RED}ERROR: Not logged into an OpenShift cluster. Please run 'oc login'.${NC}" >&2
    exit 1
fi

# Query OpenShift version
verbose "${GREEN}Querying OpenShift version...${NC}"

VERSION_JSON=$(oc version -o json 2>&1)
if [[ $? -ne 0 ]]; then
    echo -e "${RED}ERROR: Failed to query OpenShift version.${NC}" >&2
    echo "$VERSION_JSON" >&2
    exit 1
fi

# Extract version information
FULL_VERSION=$(echo "$VERSION_JSON" | jq -r '.openshiftVersion // "4.18.0"')
MAJOR_MINOR=$(echo "$FULL_VERSION" | cut -d. -f1-2)

# Map to overlay directory name
OVERLAY_NAME="ocp${MAJOR_MINOR}"

# Map to ODF channel name
ODF_CHANNEL="stable-${MAJOR_MINOR}"

# Display verbose information
if [[ "$VERBOSE" == "true" ]]; then
    KUBERNETES_VERSION=$(echo "$VERSION_JSON" | jq -r '.kubernetesVersion // "Unknown"')

    echo "" >&2
    echo -e "${GREEN}=== OpenShift Version Information ===${NC}" >&2
    echo -e "Full Version:              ${YELLOW}${FULL_VERSION}${NC}" >&2
    echo -e "Major.Minor Version:       ${YELLOW}${MAJOR_MINOR}${NC}" >&2
    echo -e "Kubernetes Version:        ${YELLOW}${KUBERNETES_VERSION}${NC}" >&2
    echo -e "Kustomize Overlay:         ${YELLOW}overlays/dev-${OVERLAY_NAME}${NC}" >&2
    echo -e "ODF Channel:               ${YELLOW}${ODF_CHANNEL}${NC}" >&2
    echo "" >&2
fi

# Output based on format
case "$OUTPUT_FORMAT" in
    version)
        echo "$MAJOR_MINOR"
        ;;
    overlay)
        echo "$OVERLAY_NAME"
        ;;
    channel)
        echo "$ODF_CHANNEL"
        ;;
    all)
        echo "VERSION=$MAJOR_MINOR"
        echo "OVERLAY=$OVERLAY_NAME"
        echo "ODF_CHANNEL=$ODF_CHANNEL"
        ;;
esac

exit 0
