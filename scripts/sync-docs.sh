#!/bin/bash
# Sync root-level markdown files to docs/ directory for MkDocs
# Usage: ./scripts/sync-docs.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "🔄 Syncing root markdown files to docs/..."

# List of files to sync
# NOTE: CONTRIBUTING.md, CODE_OF_CONDUCT.md, and AGENTS.md are NOT synced here.
# They now live in docs/reference/ and docs/explanation/ respectively.
# README.md is also not synced; docs/README.md is a short pointer to index.md.
FILES=(
  "DEPLOYMENT.md:docs/how-to/DEPLOYMENT.md"
)

for entry in "${FILES[@]}"; do
  src="${entry%%:*}"
  dest="${entry##*:}"
  if [[ -f "$src" ]]; then
    cp "$src" "$dest"
    echo "  ✅ $src → $dest"
  else
    echo "  ⚠️  $src not found in root"
  fi
done

echo ""
echo "✅ Sync complete!"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff docs/"
echo "  2. Test locally: mkdocs serve"
echo "  3. Commit: git add docs/ && git commit -m 'docs: Sync root files to docs/'"
