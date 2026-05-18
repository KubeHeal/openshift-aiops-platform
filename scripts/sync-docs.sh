#!/bin/bash
# Sync root-level markdown files to docs/ directory for MkDocs
# Usage: ./scripts/sync-docs.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "🔄 Syncing root markdown files to docs/..."

# List of files to sync
FILES=(
  "README.md"
  "DEPLOYMENT.md"
  "CONTRIBUTING.md"
  "CODE_OF_CONDUCT.md"
  "AGENTS.md"
)

for file in "${FILES[@]}"; do
  if [[ -f "$file" ]]; then
    cp "$file" "docs/$file"
    echo "  ✅ $file → docs/$file"
  else
    echo "  ⚠️  $file not found in root"
  fi
done

echo ""
echo "✅ Sync complete!"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff docs/"
echo "  2. Test locally: mkdocs serve"
echo "  3. Commit: git add docs/ && git commit -m 'docs: Sync root files to docs/'"
