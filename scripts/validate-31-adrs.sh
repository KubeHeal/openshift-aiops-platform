#!/bin/bash
# Main ADR Validation Orchestrator
# Coordinates validation across SNO and HA clusters

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_ROOT/results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Cluster credentials
SNO_TOKEN="${SNO_TOKEN:-sha256~lPn8PxX-kcF8nv7Ein_OFnspI8MXa72ykr-J-JkyWmQ}"
SNO_SERVER="${SNO_SERVER:-https://api.ocp.ph5rd.sandbox1590.opentlc.com:6443}"

HA_TOKEN="${HA_TOKEN:-}"
HA_SERVER="${HA_SERVER:-https://api.cluster-7r4mf.7r4mf.sandbox458.opentlc.com:6443}"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Validates 31 implemented ADRs across SNO and HA OpenShift clusters.

OPTIONS:
    --sno-only              Validate SNO cluster only
    --ha-only               Validate HA cluster only
    --skip-login            Skip cluster login (use current context)
    --sno-token TOKEN       SNO cluster token (or use SNO_TOKEN env var)
    --ha-token TOKEN        HA cluster token (or use HA_TOKEN env var)
    -h, --help              Show this help message

ENVIRONMENT VARIABLES:
    SNO_TOKEN               SNO cluster token
    SNO_SERVER              SNO cluster server (default: $SNO_SERVER)
    HA_TOKEN                HA cluster token
    HA_SERVER               HA cluster server (default: $HA_SERVER)

EXAMPLES:
    # Validate both clusters (using environment variables)
    export SNO_TOKEN="sha256~..."
    export HA_TOKEN="sha256~..."
    $0

    # Validate SNO only
    $0 --sno-only --sno-token "sha256~..."

    # Validate both with inline tokens
    $0 --sno-token "sha256~..." --ha-token "sha256~..."

    # Use current cluster context (no login)
    $0 --sno-only --skip-login

OUTPUT:
    - results/sno-complete.json - SNO validation results
    - results/ha-complete.json - HA validation results
    - results/validation-comparison.json - Comparative analysis
EOF
    exit 1
}

# Parse arguments
VALIDATE_SNO=true
VALIDATE_HA=true
SKIP_LOGIN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --sno-only)
            VALIDATE_HA=false
            shift
            ;;
        --ha-only)
            VALIDATE_SNO=false
            shift
            ;;
        --skip-login)
            SKIP_LOGIN=true
            shift
            ;;
        --sno-token)
            SNO_TOKEN="$2"
            shift 2
            ;;
        --ha-token)
            HA_TOKEN="$2"
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

# Verify prerequisites
command -v oc >/dev/null 2>&1 || { echo -e "${RED}Error: oc CLI not found${NC}"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${RED}Error: jq not found${NC}"; exit 1; }

# Create results directory
mkdir -p "$RESULTS_DIR"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   ADR Implementation Validation - 31 ADRs                  ║${NC}"
echo -e "${BLUE}║   SNO + HA Topology Verification                           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Validation results tracking
SNO_SUCCESS=false
HA_SUCCESS=false

# Validate SNO cluster
if [[ $VALIDATE_SNO == true ]]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  PHASE 1: SNO Cluster Validation${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [[ $SKIP_LOGIN == false ]]; then
        if [[ -z "$SNO_TOKEN" ]]; then
            echo -e "${RED}Error: SNO token not provided${NC}"
            echo "Set SNO_TOKEN environment variable or use --sno-token"
            exit 1
        fi

        echo -e "${YELLOW}Logging into SNO cluster...${NC}"
        if oc login --token="$SNO_TOKEN" --server="$SNO_SERVER" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Successfully logged into SNO cluster${NC}"
        else
            echo -e "${RED}✗ Failed to login to SNO cluster${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}Using current cluster context${NC}"
    fi

    echo ""
    if "$SCRIPT_DIR/run-adr-validation.sh" --cluster sno; then
        SNO_SUCCESS=true
        echo -e "${GREEN}✓ SNO validation completed successfully${NC}"
    else
        echo -e "${YELLOW}⚠ SNO validation completed with warnings/failures${NC}"
    fi
    echo ""
fi

# Validate HA cluster
if [[ $VALIDATE_HA == true ]]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  PHASE 2: HA Cluster Validation${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [[ $SKIP_LOGIN == false ]]; then
        if [[ -z "$HA_TOKEN" ]]; then
            echo -e "${YELLOW}⚠ HA token not provided, skipping HA cluster validation${NC}"
            VALIDATE_HA=false
        else
            echo -e "${YELLOW}Logging into HA cluster...${NC}"
            if oc login --token="$HA_TOKEN" --server="$HA_SERVER" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Successfully logged into HA cluster${NC}"
            else
                echo -e "${RED}✗ Failed to login to HA cluster${NC}"
                echo -e "${YELLOW}Continuing with SNO validation only${NC}"
                VALIDATE_HA=false
            fi
        fi
    fi

    if [[ $VALIDATE_HA == true ]]; then
        echo ""
        if "$SCRIPT_DIR/run-adr-validation.sh" --cluster ha; then
            HA_SUCCESS=true
            echo -e "${GREEN}✓ HA validation completed successfully${NC}"
        else
            echo -e "${YELLOW}⚠ HA validation completed with warnings/failures${NC}"
        fi
        echo ""
    fi
fi

# Logout from clusters
if [[ $SKIP_LOGIN == false ]]; then
    echo -e "${YELLOW}Logging out from clusters...${NC}"
    oc logout >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Logged out${NC}"
    echo ""
fi

# Generate comparison report if both clusters were validated
if [[ $VALIDATE_SNO == true ]] && [[ $VALIDATE_HA == true ]]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  PHASE 3: Comparative Analysis${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [[ -f "$RESULTS_DIR/sno-complete.json" ]] && [[ -f "$RESULTS_DIR/ha-complete.json" ]]; then
        echo -e "${YELLOW}Generating comparative analysis...${NC}"

        # Simple comparison (detailed report generator will be created separately)
        SNO_PASS=$(jq '[.[] | select(.status=="PASS")] | length' "$RESULTS_DIR/sno-complete.json")
        SNO_FAIL=$(jq '[.[] | select(.status=="FAIL")] | length' "$RESULTS_DIR/sno-complete.json")
        SNO_PARTIAL=$(jq '[.[] | select(.status=="PARTIAL")] | length' "$RESULTS_DIR/sno-complete.json")

        HA_PASS=$(jq '[.[] | select(.status=="PASS")] | length' "$RESULTS_DIR/ha-complete.json")
        HA_FAIL=$(jq '[.[] | select(.status=="FAIL")] | length' "$RESULTS_DIR/ha-complete.json")
        HA_PARTIAL=$(jq '[.[] | select(.status=="PARTIAL")] | length' "$RESULTS_DIR/ha-complete.json")

        cat > "$RESULTS_DIR/validation-comparison.json" <<EOF
{
  "validation_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "total_adrs_validated": 31,
  "sno": {
    "pass": $SNO_PASS,
    "fail": $SNO_FAIL,
    "partial": $SNO_PARTIAL,
    "success_rate": $((SNO_PASS * 100 / (SNO_PASS + SNO_FAIL + SNO_PARTIAL)))
  },
  "ha": {
    "pass": $HA_PASS,
    "fail": $HA_FAIL,
    "partial": $HA_PARTIAL,
    "success_rate": $((HA_PASS * 100 / (HA_PASS + HA_FAIL + HA_PARTIAL)))
  }
}
EOF

        echo -e "${GREEN}✓ Comparison report generated: $RESULTS_DIR/validation-comparison.json${NC}"
        echo ""

        # Display comparison
        echo -e "${BLUE}Validation Results Comparison:${NC}"
        echo ""
        echo -e "  ${BLUE}SNO Cluster:${NC}"
        echo -e "    PASS:    ${GREEN}$SNO_PASS${NC}"
        echo -e "    FAIL:    ${RED}$SNO_FAIL${NC}"
        echo -e "    PARTIAL: ${YELLOW}$SNO_PARTIAL${NC}"
        echo ""
        echo -e "  ${BLUE}HA Cluster:${NC}"
        echo -e "    PASS:    ${GREEN}$HA_PASS${NC}"
        echo -e "    FAIL:    ${RED}$HA_FAIL${NC}"
        echo -e "    PARTIAL: ${YELLOW}$HA_PARTIAL${NC}"
        echo ""
    fi
fi

# Final summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Validation Complete                                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Results directory: $RESULTS_DIR${NC}"
echo ""

if [[ $VALIDATE_SNO == true ]]; then
    echo -e "  SNO Results:        ${BLUE}$RESULTS_DIR/sno-complete.json${NC}"
fi
if [[ $VALIDATE_HA == true ]]; then
    echo -e "  HA Results:         ${BLUE}$RESULTS_DIR/ha-complete.json${NC}"
fi
if [[ $VALIDATE_SNO == true ]] && [[ $VALIDATE_HA == true ]]; then
    echo -e "  Comparison:         ${BLUE}$RESULTS_DIR/validation-comparison.json${NC}"
fi
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Review results with: jq . $RESULTS_DIR/sno-complete.json"
echo -e "  2. Generate detailed report with: scripts/generate-validation-report.py"
echo -e "  3. Update IMPLEMENTATION-TRACKER.md with evidence"
echo ""

# Exit code
if [[ $SNO_SUCCESS == true ]] || [[ $HA_SUCCESS == true ]]; then
    exit 0
else
    exit 1
fi
