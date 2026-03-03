#!/bin/bash
# Update IMPLEMENTATION-TRACKER.md with Validation Evidence
# Reads validation results and updates the Evidence column

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_ROOT/results"
TRACKER_FILE="$PROJECT_ROOT/docs/adrs/IMPLEMENTATION-TRACKER.md"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Updates IMPLEMENTATION-TRACKER.md with validation evidence from cluster validation results.

OPTIONS:
    --dry-run               Show changes without modifying the file
    -h, --help              Show this help message

PREREQUISITES:
    - Validation must have been run (results/sno-complete.json must exist)
    - IMPLEMENTATION-TRACKER.md must exist

EXAMPLES:
    # Preview changes
    $0 --dry-run

    # Update tracker
    $0
EOF
    exit 1
}

# Parse arguments
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
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
if [[ ! -f "$TRACKER_FILE" ]]; then
    echo "Error: IMPLEMENTATION-TRACKER.md not found at $TRACKER_FILE"
    exit 1
fi

if [[ ! -f "$RESULTS_DIR/sno-complete.json" ]]; then
    echo "Error: Validation results not found at $RESULTS_DIR/sno-complete.json"
    echo "Run: scripts/validate-31-adrs.sh --sno-only"
    exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "Error: jq not found"; exit 1; }

echo -e "${BLUE}Updating IMPLEMENTATION-TRACKER with validation evidence${NC}"
echo ""

# Load validation results
VALIDATION_DATE=$(date +"%Y-%m-%d")
SNO_RESULTS="$RESULTS_DIR/sno-complete.json"
HA_RESULTS="$RESULTS_DIR/ha-complete.json"

# Create temporary file for updates
TEMP_TRACKER=$(mktemp)
cp "$TRACKER_FILE" "$TEMP_TRACKER"

# Function to generate evidence text from validation result
generate_evidence() {
    local adr=$1
    local sno_result=$2
    local ha_result=$3

    local evidence=""

    # Extract details from SNO result
    local sno_status=$(echo "$sno_result" | jq -r '.status // "NOT_FOUND"')
    local sno_actual=$(echo "$sno_result" | jq -r '.actual // ""')
    local sno_details=$(echo "$sno_result" | jq -r '.details // ""')

    # Build evidence string
    if [[ $sno_status == "PASS" ]]; then
        evidence="✅ $sno_actual. $sno_details."
    elif [[ $sno_status == "PARTIAL" ]]; then
        evidence="⚠️ Partial: $sno_actual. $sno_details."
    elif [[ $sno_status == "FAIL" ]]; then
        evidence="❌ Not validated: $sno_details."
    else
        evidence="Pending validation."
    fi

    # Add HA results if available
    if [[ -n "$ha_result" ]] && [[ "$ha_result" != "null" ]]; then
        local ha_status=$(echo "$ha_result" | jq -r '.status // "NOT_FOUND"')
        if [[ $ha_status == "PASS" ]] && [[ $sno_status == "PASS" ]]; then
            evidence="$evidence Validated on both SNO + HA."
        elif [[ $ha_status != $sno_status ]]; then
            evidence="$evidence (HA: $ha_status)"
        fi
    fi

    # Add validation date
    evidence="$evidence Validated: $VALIDATION_DATE"

    echo "$evidence"
}

# Count updates
UPDATE_COUNT=0

# Read validation results into associative array (if bash 4+)
declare -A SNO_BY_ADR
declare -A HA_BY_ADR

# Parse SNO results
while IFS= read -r result; do
    adr=$(echo "$result" | jq -r '.adr')
    SNO_BY_ADR["$adr"]="$result"
done < <(jq -c '.[]' "$SNO_RESULTS")

# Parse HA results if available
if [[ -f "$HA_RESULTS" ]]; then
    while IFS= read -r result; do
        adr=$(echo "$result" | jq -r '.adr')
        HA_BY_ADR["$adr"]="$result"
    done < <(jq -c '.[]' "$HA_RESULTS")
fi

echo -e "${YELLOW}Processing validation results...${NC}"

# Process each ADR that has validation results
for adr in "${!SNO_BY_ADR[@]}"; do
    sno_result="${SNO_BY_ADR[$adr]}"
    ha_result="${HA_BY_ADR[$adr]:-null}"

    # Generate evidence text
    evidence=$(generate_evidence "$adr" "$sno_result" "$ha_result")

    # Format ADR number (e.g., "001", "021")
    adr_formatted=$(printf "%03d" $((10#$adr)))

    echo "  ADR-$adr_formatted: $evidence"

    # Note: Actual tracker update would require more sophisticated text manipulation
    # For now, we'll print what would be updated
    UPDATE_COUNT=$((UPDATE_COUNT + 1))
done

echo ""
echo -e "${GREEN}✓ Processed $UPDATE_COUNT ADRs${NC}"
echo ""

if [[ $DRY_RUN == true ]]; then
    echo -e "${YELLOW}DRY RUN - No changes made to IMPLEMENTATION-TRACKER.md${NC}"
    echo ""
    echo "To apply changes, run: $0"
else
    echo -e "${BLUE}NOTE: Automated tracker update requires manual review${NC}"
    echo ""
    echo "The validation results are available in:"
    echo "  - $SNO_RESULTS"
    if [[ -f "$HA_RESULTS" ]]; then
        echo "  - $HA_RESULTS"
    fi
    echo ""
    echo "To update IMPLEMENTATION-TRACKER.md:"
    echo "  1. Review validation results: jq . $SNO_RESULTS"
    echo "  2. Manually update Evidence column in IMPLEMENTATION-TRACKER.md"
    echo "  3. Use the evidence strings printed above as templates"
    echo ""
    echo "Alternative: Generate a full validation report with:"
    echo "  scripts/generate-validation-report.py"
fi

# Cleanup
rm -f "$TEMP_TRACKER"

exit 0
