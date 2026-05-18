#!/bin/bash
# Validates pattern readiness for validated-patterns submission
# Usage: ./scripts/validate-pattern-submission.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "🔍 Validating pattern submission readiness..."
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check required files exist
echo "📁 Checking required files..."
required_files=(
  "pattern-metadata.yaml"
  "values-hub.yaml.example"
  "values-global.yaml.example"
  "charts/hub/Chart.yaml"
  "charts/hub/values.yaml"
  "README.md"
  "CONTRIBUTING.md"
  "CODE_OF_CONDUCT.md"
  "CHANGELOG.md"
  "LICENSE"
  "ansible/playbooks/operator_deploy_prereqs.yml"
  "Makefile"
  "Makefile-common"
  "docs/guides/FRESH-CLUSTER-DEPLOYMENT.md"
  "docs/guides/VALIDATED-PATTERNS-SUBMISSION.md"
)

missing_files=()
for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    missing_files+=("$file")
  fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
  echo -e "${RED}❌ Missing required files:${NC}"
  printf '  - %s\n' "${missing_files[@]}"
  exit 1
fi

echo -e "${GREEN}✅ All required files present${NC}"
echo ""

# Check for secrets in values files
echo "🔒 Checking for hard-coded secrets in example values files..."
secrets_found=false

if grep -rq "password\|token\|secret" values-*.yaml.example 2>/dev/null; then
  echo -e "${YELLOW}⚠️  WARNING: Potential secrets found in example values files${NC}"
  echo "   The following lines may contain sensitive data:"
  grep -rn "password\|token\|secret" values-*.yaml.example | head -10
  echo ""
  echo "   Action required:"
  echo "   - Remove actual secret values"
  echo "   - Replace with placeholders like <INSERT_TOKEN_HERE>"
  echo ""
  secrets_found=true
fi

if [[ "$secrets_found" == "false" ]]; then
  echo -e "${GREEN}✅ No obvious secrets found in example values files${NC}"
fi
echo ""

# Validate pattern-metadata.yaml structure
echo "📋 Validating pattern-metadata.yaml structure..."

if ! command -v yq &> /dev/null; then
  echo -e "${YELLOW}⚠️  yq not found, skipping pattern-metadata validation${NC}"
else
  # Check required fields
  required_fields=(
    ".tier"
    ".supportedPlatforms"
    ".supportedTopologies"
    ".minOpenShiftVersion"
    ".resourceRequirements"
  )

  metadata_valid=true
  for field in "${required_fields[@]}"; do
    if ! yq eval "$field" pattern-metadata.yaml &>/dev/null; then
      echo -e "${RED}❌ pattern-metadata.yaml missing field: $field${NC}"
      metadata_valid=false
    fi
  done

  if [[ "$metadata_valid" == "true" ]]; then
    echo -e "${GREEN}✅ pattern-metadata.yaml structure valid${NC}"

    # Display key metadata
    echo ""
    echo "Pattern Metadata Summary:"
    echo "  Tier: $(yq eval '.tier' pattern-metadata.yaml)"
    echo "  Platforms: $(yq eval '.supportedPlatforms | join(", ")' pattern-metadata.yaml)"
    echo "  Topologies: $(yq eval '.supportedTopologies | join(", ")' pattern-metadata.yaml)"
    echo "  Min OpenShift: $(yq eval '.minOpenShiftVersion' pattern-metadata.yaml)"
  else
    echo -e "${RED}❌ pattern-metadata.yaml validation failed${NC}"
    exit 1
  fi
fi
echo ""

# Validate Helm chart
echo "⎈ Validating Helm chart..."

if ! command -v helm &> /dev/null; then
  echo -e "${YELLOW}⚠️  helm not found, skipping chart validation${NC}"
else
  if helm lint charts/hub/ &>/dev/null; then
    echo -e "${GREEN}✅ Helm chart validation passed${NC}"
  else
    echo -e "${RED}❌ Helm chart validation failed${NC}"
    echo ""
    echo "Helm lint output:"
    helm lint charts/hub/
    exit 1
  fi
fi
echo ""

# Check Diataxis structure
echo "📚 Validating Diataxis documentation structure..."

diataxis_dirs=(
  "docs/tutorials"
  "docs/how-to"
  "docs/reference"
  "docs/explanation"
)

diataxis_valid=true
for dir in "${diataxis_dirs[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo -e "${RED}❌ Missing Diataxis directory: $dir${NC}"
    diataxis_valid=false
  fi
done

if [[ "$diataxis_valid" == "true" ]]; then
  echo -e "${GREEN}✅ Diataxis structure validated${NC}"
else
  echo -e "${RED}❌ Diataxis structure incomplete${NC}"
  exit 1
fi
echo ""

# Check GitHub Pages configuration
echo "🌐 Checking GitHub Pages configuration..."

if [[ -f "mkdocs.yml" ]]; then
  echo -e "${GREEN}✅ MkDocs configuration found${NC}"

  if [[ -f ".github/workflows/deploy-docs.yml" ]]; then
    echo -e "${GREEN}✅ GitHub Pages deployment workflow found${NC}"
  else
    echo -e "${YELLOW}⚠️  GitHub Pages deployment workflow not found${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  MkDocs configuration not found (optional but recommended)${NC}"
fi
echo ""

# Check Makefile targets
echo "🔨 Validating Makefile targets..."

required_targets=(
  "show-cluster-info"
  "check-prerequisites"
  "configure-cluster"
  "operator-deploy"
  "argo-healthcheck"
)

makefile_valid=true
for target in "${required_targets[@]}"; do
  if ! grep -q "^${target}:" Makefile; then
    echo -e "${RED}❌ Missing Makefile target: $target${NC}"
    makefile_valid=false
  fi
done

if [[ "$makefile_valid" == "true" ]]; then
  echo -e "${GREEN}✅ All required Makefile targets present${NC}"
else
  echo -e "${RED}❌ Makefile missing required targets${NC}"
  exit 1
fi
echo ""

# Final summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Pattern submission validation complete${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. Test deployment on fresh SNO and HA clusters"
echo "   - Run: make show-cluster-info"
echo "   - Run: make configure-cluster"
echo "   - Run: make operator-deploy"
echo "   - Run: make argo-healthcheck"
echo ""
echo "2. Review submission guide:"
echo "   - Read: docs/guides/VALIDATED-PATTERNS-SUBMISSION.md"
echo ""
echo "3. Fork validated patterns repository:"
echo "   - Visit: https://github.com/validatedpatterns/patterns"
echo "   - Click Fork"
echo ""
echo "4. Create PR with your pattern"
echo "   - Follow submission guide steps"
echo ""

if [[ "$secrets_found" == "true" ]]; then
  echo -e "${YELLOW}⚠️  IMPORTANT: Address secrets in example values files before submission${NC}"
  echo ""
fi

exit 0
