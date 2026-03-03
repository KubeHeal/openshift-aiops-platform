#!/bin/bash
# ADR Validation Execution Script
# Runs validation on a single cluster (SNO or HA)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VALIDATORS_DIR="$PROJECT_ROOT/validators"
RESULTS_DIR="$PROJECT_ROOT/results"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Runs ADR validation on the currently logged-in OpenShift cluster.

OPTIONS:
    -c, --cluster NAME       Cluster name (sno or ha) for output files
    -h, --help              Show this help message

EXAMPLES:
    # Validate SNO cluster (must be logged in first)
    $0 --cluster sno

    # Validate HA cluster
    $0 --cluster ha

PREREQUISITES:
    - Must be logged into OpenShift cluster (oc login)
    - jq must be installed
    - Validators directory must exist with all modules
EOF
    exit 1
}

# Parse arguments
CLUSTER_NAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate arguments
if [[ -z "$CLUSTER_NAME" ]]; then
    echo "Error: Cluster name required (-c/--cluster)"
    usage
fi

# Verify prerequisites
command -v oc >/dev/null 2>&1 || { echo "Error: oc CLI not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq not found"; exit 1; }

# Check cluster connectivity
echo -e "${BLUE}Checking cluster connectivity...${NC}"
if ! oc whoami >/dev/null 2>&1; then
    echo -e "${RED}Error: Not logged into OpenShift cluster${NC}"
    echo "Run: oc login --token=<token> --server=<server>"
    exit 1
fi

CURRENT_USER=$(oc whoami)
CURRENT_SERVER=$(oc whoami --show-server)
echo -e "${GREEN}✓ Connected as $CURRENT_USER to $CURRENT_SERVER${NC}"

# Detect topology
echo -e "${BLUE}Detecting cluster topology...${NC}"
if [[ -f "$SCRIPT_DIR/detect-cluster-topology.sh" ]]; then
    TOPOLOGY=$("$SCRIPT_DIR/detect-cluster-topology.sh")
else
    NODE_COUNT=$(oc get nodes --no-headers 2>/dev/null | wc -l)
    if [[ $NODE_COUNT -eq 1 ]]; then
        TOPOLOGY="SingleReplica"
    else
        TOPOLOGY="HighlyAvailable"
    fi
fi
echo -e "${GREEN}✓ Topology: $TOPOLOGY${NC}"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ADR Validation - $CLUSTER_NAME ($TOPOLOGY)${NC}"
echo -e "${BLUE}  Started: $TIMESTAMP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

# Validation modules
MODULES=(
    "core-platform:Core Platform (ADRs 001,003,004,006,007,010)"
    "notebooks:Notebooks & Development (ADRs 011,012,013,029,031,032)"
    "mlops-cicd:MLOps & CI/CD (ADRs 021,023,024,025,026,042,043)"
    "deployment:Deployment & GitOps (ADRs 019,030)"
    "coordination:Coordination & LLM (ADRs 036,038)"
    "storage-topology:Storage & Topology (ADRs 034,035,054,055,056,057,058)"
)

# Run each module
VALIDATION_RESULTS=()
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_PARTIAL=0
TOTAL_ERROR=0
TOTAL_NA=0

for module_spec in "${MODULES[@]}"; do
    IFS=':' read -r module_name module_desc <<< "$module_spec"

    echo -e "${YELLOW}Running: $module_desc${NC}"

    MODULE_SCRIPT="$VALIDATORS_DIR/${module_name}.sh"
    MODULE_OUTPUT="$RESULTS_DIR/${CLUSTER_NAME}-${module_name}.json"

    if [[ ! -f "$MODULE_SCRIPT" ]]; then
        echo -e "${RED}✗ Module not found: $MODULE_SCRIPT${NC}"
        continue
    fi

    # Run module and capture output
    if "$MODULE_SCRIPT" > "$MODULE_OUTPUT" 2>&1; then
        # Count results
        local pass=$(jq '[.[] | select(.status=="PASS")] | length' "$MODULE_OUTPUT")
        local fail=$(jq '[.[] | select(.status=="FAIL")] | length' "$MODULE_OUTPUT")
        local partial=$(jq '[.[] | select(.status=="PARTIAL")] | length' "$MODULE_OUTPUT")
        local error=$(jq '[.[] | select(.status=="ERROR")] | length' "$MODULE_OUTPUT")
        local na=$(jq '[.[] | select(.status=="N/A")] | length' "$MODULE_OUTPUT")

        TOTAL_PASS=$((TOTAL_PASS + pass))
        TOTAL_FAIL=$((TOTAL_FAIL + fail))
        TOTAL_PARTIAL=$((TOTAL_PARTIAL + partial))
        TOTAL_ERROR=$((TOTAL_ERROR + error))
        TOTAL_NA=$((TOTAL_NA + na))

        echo -e "${GREEN}✓ Complete: PASS=$pass FAIL=$fail PARTIAL=$partial ERROR=$error N/A=$na${NC}"
        VALIDATION_RESULTS+=("$MODULE_OUTPUT")
    else
        echo -e "${RED}✗ Module failed to execute${NC}"
    fi
    echo ""
done

# Aggregate results
echo -e "${BLUE}Aggregating results...${NC}"
AGGREGATE_OUTPUT="$RESULTS_DIR/${CLUSTER_NAME}-complete.json"

# Combine all module results into single JSON array
jq -s 'add' "${VALIDATION_RESULTS[@]}" > "$AGGREGATE_OUTPUT"

# Create summary
TOTAL_ADRS=$((TOTAL_PASS + TOTAL_FAIL + TOTAL_PARTIAL + TOTAL_ERROR))
SUCCESS_RATE=0
if [[ $TOTAL_ADRS -gt 0 ]]; then
    SUCCESS_RATE=$((TOTAL_PASS * 100 / TOTAL_ADRS))
fi

# Summary report
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Validation Summary - $CLUSTER_NAME${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "Topology:        ${GREEN}$TOPOLOGY${NC}"
echo -e "Total ADRs:      ${BLUE}$TOTAL_ADRS${NC}"
echo -e "✓ PASS:          ${GREEN}$TOTAL_PASS${NC}"
echo -e "✗ FAIL:          ${RED}$TOTAL_FAIL${NC}"
echo -e "◐ PARTIAL:       ${YELLOW}$TOTAL_PARTIAL${NC}"
echo -e "⚠ ERROR:         ${RED}$TOTAL_ERROR${NC}"
echo -e "- N/A:           ${BLUE}$TOTAL_NA${NC}"
echo -e "Success Rate:    ${GREEN}${SUCCESS_RATE}%${NC}"
echo ""
echo -e "Results saved to: ${BLUE}$AGGREGATE_OUTPUT${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

# Create summary JSON
cat > "$RESULTS_DIR/${CLUSTER_NAME}-summary.json" <<EOF
{
  "cluster": "$CLUSTER_NAME",
  "topology": "$TOPOLOGY",
  "server": "$CURRENT_SERVER",
  "timestamp": "$TIMESTAMP",
  "summary": {
    "total_adrs": $TOTAL_ADRS,
    "pass": $TOTAL_PASS,
    "fail": $TOTAL_FAIL,
    "partial": $TOTAL_PARTIAL,
    "error": $TOTAL_ERROR,
    "na": $TOTAL_NA,
    "success_rate": $SUCCESS_RATE
  },
  "results_file": "$AGGREGATE_OUTPUT"
}
EOF

# Exit code based on results
if [[ $TOTAL_ERROR -gt 0 ]]; then
    exit 2
elif [[ $TOTAL_FAIL -gt 5 ]]; then
    exit 1
else
    exit 0
fi
