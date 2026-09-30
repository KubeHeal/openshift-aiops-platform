#!/usr/bin/env bash
# sync-operator-chart.sh -- Sync charts/hub/ into KubeHeal/kubeheal-operator
#
# Clones the kubeheal-operator repo, replaces its embedded Helm chart with the
# current charts/hub/ content (excluding VP-specific ArgoCD templates), commits,
# and optionally pushes.
#
# Usage:
#   ./scripts/sync-operator-chart.sh [--push] [--dry-run] [--branch BRANCH]
#
# Options:
#   --push      Push the commit to the remote after committing
#   --dry-run   Show what would happen without making changes
#   --branch    Target branch in kubeheal-operator (default: main)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OPERATOR_REPO="https://github.com/KubeHeal/kubeheal-operator.git"
OPERATOR_CHART_DIR="helm-charts/self-healing-platform"
SOURCE_CHART_DIR="${REPO_ROOT}/charts/hub"

PUSH=false
DRY_RUN=false
BRANCH="main"

# VP-specific files to exclude from the operator chart
EXCLUDE_FILES=(
    "argocd-application.yaml"
    "argocd-application-hub.yaml"
)

usage() {
    echo "Usage: $0 [--push] [--dry-run] [--branch BRANCH]"
    echo ""
    echo "Syncs charts/hub/ from this repo into KubeHeal/kubeheal-operator."
    echo ""
    echo "Options:"
    echo "  --push      Push the commit to the remote after committing"
    echo "  --dry-run   Show what would change without modifying anything"
    echo "  --branch    Target branch in kubeheal-operator (default: main)"
    echo "  --help      Show this help message"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --push)
            PUSH=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate source chart exists
if [[ ! -d "${SOURCE_CHART_DIR}" ]]; then
    echo "ERROR: Source chart directory not found: ${SOURCE_CHART_DIR}"
    exit 1
fi

if [[ ! -f "${SOURCE_CHART_DIR}/Chart.yaml" ]]; then
    echo "ERROR: Chart.yaml not found in ${SOURCE_CHART_DIR}"
    exit 1
fi

# Get source repo commit SHA for the commit message
SOURCE_SHA="$(cd "${REPO_ROOT}" && git rev-parse --short HEAD)"
SOURCE_SHA_FULL="$(cd "${REPO_ROOT}" && git rev-parse HEAD)"
CHART_VERSION="$(grep '^version:' "${SOURCE_CHART_DIR}/Chart.yaml" | awk '{print $2}')"

echo "============================================"
echo "  kubeheal-operator Chart Sync"
echo "============================================"
echo ""
echo "Source chart:    ${SOURCE_CHART_DIR}"
echo "Source SHA:      ${SOURCE_SHA} (${SOURCE_SHA_FULL})"
echo "Chart version:   ${CHART_VERSION}"
echo "Target repo:     ${OPERATOR_REPO}"
echo "Target branch:   ${BRANCH}"
echo "Push:            ${PUSH}"
echo "Dry run:         ${DRY_RUN}"
echo ""

if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY RUN] Would sync the following files:"
    echo ""
    echo "Files to copy (from charts/hub/):"
    find "${SOURCE_CHART_DIR}" -type f | sort | while read -r f; do
        rel="${f#${SOURCE_CHART_DIR}/}"
        skip=false
        for excl in "${EXCLUDE_FILES[@]}"; do
            if [[ "${rel}" == "${excl}" ]]; then
                skip=true
                break
            fi
        done
        if [[ "${skip}" == "true" ]]; then
            echo "  SKIP  ${rel}"
        else
            echo "  COPY  ${rel}"
        fi
    done
    echo ""
    echo "[DRY RUN] No changes made."
    exit 0
fi

# Clone operator repo to a temp directory
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

echo "Cloning kubeheal-operator into ${WORK_DIR}..."
git clone --branch "${BRANCH}" --depth=1 "${OPERATOR_REPO}" "${WORK_DIR}/kubeheal-operator"

OPERATOR_DIR="${WORK_DIR}/kubeheal-operator"
TARGET_DIR="${OPERATOR_DIR}/${OPERATOR_CHART_DIR}"

# Verify target directory exists
if [[ ! -d "${TARGET_DIR}" ]]; then
    echo "ERROR: Target chart directory not found in operator repo: ${OPERATOR_CHART_DIR}"
    echo "The operator repo structure may have changed."
    exit 1
fi

# Remove old chart content (keep the directory)
echo "Removing stale chart content..."
rm -rf "${TARGET_DIR:?}/"*

# Copy new chart content, excluding VP-specific files
echo "Copying current chart..."
rsync -a --exclude='.git' "${SOURCE_CHART_DIR}/" "${TARGET_DIR}/"

# Remove VP-specific files that should not be in the operator chart
for excl in "${EXCLUDE_FILES[@]}"; do
    if [[ -f "${TARGET_DIR}/${excl}" ]]; then
        echo "  Removing VP-specific file: ${excl}"
        rm -f "${TARGET_DIR}/${excl}"
    fi
done

# Show what changed
echo ""
echo "Changes in operator repo:"
cd "${OPERATOR_DIR}"
git add -A
git diff --cached --stat

CHANGES="$(git diff --cached --stat | tail -1)"
if [[ -z "${CHANGES}" ]] || echo "${CHANGES}" | grep -q "^$"; then
    echo ""
    echo "No changes detected -- chart is already in sync."
    exit 0
fi

# Commit
COMMIT_MSG="chore: sync chart from openshift-aiops-platform@${SOURCE_SHA}

Source: KubeHeal/openshift-aiops-platform@${SOURCE_SHA_FULL}
Chart version: ${CHART_VERSION}

Synced charts/hub/ content, excluding VP-specific ArgoCD templates.

Signed-off-by: $(git config user.name) <$(git config user.email)>"

echo ""
echo "Committing with message:"
echo "---"
echo "${COMMIT_MSG}"
echo "---"

git commit -m "${COMMIT_MSG}"

if [[ "${PUSH}" == "true" ]]; then
    echo ""
    echo "Pushing to ${BRANCH}..."
    git push origin "${BRANCH}"
    echo "Push complete."
else
    echo ""
    echo "Commit created locally in ${OPERATOR_DIR}."
    echo "Run with --push to push to remote, or manually:"
    echo "  cd ${OPERATOR_DIR} && git push origin ${BRANCH}"
fi

echo ""
echo "Sync complete."
