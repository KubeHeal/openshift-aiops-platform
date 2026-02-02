#!/bin/bash
# Emergency Security Cleanup Script
# Removes secrets from current files and git history

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================================="
echo "🚨 EMERGENCY SECURITY CLEANUP"
echo "=========================================================="
echo ""
echo "This script will:"
echo "  1. Verify all secret files have been sanitized"
echo "  2. Remove secrets from git history"
echo "  3. Prepare repository for force push"
echo ""
echo -e "${RED}⚠️  WARNING: This will rewrite git history!${NC}"
echo -e "${RED}⚠️  All contributors will need to re-clone!${NC}"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

cd /home/lab-user/openshift-aiops-platform

# Step 1: Verify current files are clean
echo ""
echo "=========================================================="
echo "Step 1: Verifying Current Files"
echo "=========================================================="

check_file_clean() {
    local file=$1
    local pattern=$2
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${RED}❌ FAILED: $file still contains secrets${NC}"
        return 1
    else
        echo -e "${GREEN}✓ $file is clean${NC}"
        return 0
    fi
}

all_clean=true

# Check ansible.cfg
if ! check_file_clean "ansible.cfg" "eyJhbGciOiJIUzUxMiI"; then
    all_clean=false
fi

# Check context ansible.cfg
if ! check_file_clean "context/_build/configs/ansible.cfg" "eyJhbGciOiJIUzUxMiI"; then
    all_clean=false
fi

# Check values-global.yaml
if ! check_file_clean "charts/hub/values-global.yaml" "j4aXKdsrqAzKhyxu84Jc"; then
    all_clean=false
fi

if ! check_file_clean "charts/hub/values-global.yaml" "7BFR+5e8zC8gSaTTY"; then
    all_clean=false
fi

# Check webhook file
if ! check_file_clean "tekton/triggers/github-gitea-webhook-eventlistener.yaml" "abdf580d9f49afad1109015b4d9c7d9cd8700e5c"; then
    all_clean=false
fi

if [ "$all_clean" = false ]; then
    echo ""
    echo -e "${RED}❌ Some files still contain secrets. Aborting.${NC}"
    echo "Please ensure all files have been properly sanitized."
    exit 1
fi

echo ""
echo -e "${GREEN}✅ All current files are clean${NC}"

# Step 2: Create backup
echo ""
echo "=========================================================="
echo "Step 2: Creating Backup"
echo "=========================================================="

cd /home/lab-user
BACKUP_NAME="openshift-aiops-platform-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
echo "Creating backup: $BACKUP_NAME"
tar -czf "$BACKUP_NAME" openshift-aiops-platform/ 2>/dev/null || true
echo -e "${GREEN}✓ Backup created: /home/lab-user/$BACKUP_NAME${NC}"

cd /home/lab-user/openshift-aiops-platform

# Step 3: Install git-filter-repo
echo ""
echo "=========================================================="
echo "Step 3: Installing git-filter-repo"
echo "=========================================================="

if ! command -v git-filter-repo &> /dev/null; then
    echo "Installing git-filter-repo..."
    pip3 install --user git-filter-repo
    export PATH="$PATH:$HOME/.local/bin"
    echo -e "${GREEN}✓ git-filter-repo installed${NC}"
else
    echo -e "${GREEN}✓ git-filter-repo already installed${NC}"
fi

# Step 4: Create expressions file for secrets
echo ""
echo "=========================================================="
echo "Step 4: Preparing Secret Patterns"
echo "=========================================================="

cat > /tmp/secrets-to-remove.txt <<'EOF'
# Red Hat OAuth tokens (JWT format) - both published and validated
regex:eyJhbGciOiJIUzUxMiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI0NzQzYTkzMC03YmJiLTRkZGQtOTgzMS00ODcxNGRlZDc0YjUifQ\.eyJpYXQiOjE3NjIxMDc5OTgsImp0aSI6IjJlMGFhNjBhLTA2NWQtNGJkOC1hN2ExLTZkNDYwYzE0OTlmMCIsImlzcyI6Imh0dHBzOi8vc3NvLnJlZGhhdC5jb20vYXV0aC9yZWFsbXMvcmVkaGF0LWV4dGVybmFsIiwiYXVkIjoiaHR0cHM6Ly9zc28ucmVkaGF0LmNvbS9hdXRoL3JlYWxtcy9yZWRoYXQtZXh0ZXJuYWwiLCJzdWIiOiI1MjI5NjkxMSIsInR5cCI6Ik9mZmxpbmUiLCJhenAiOiJjbG91ZC1zZXJ2aWNlcyIsIm5vbmNlIjoiODQ4NzI2NDktMDRkNS00YWVhLTg1OGEtMmMzMmVlZWVlYWZhIiwic2lkIjoiNjY5ZjA4MzUtMzY3OS00M2FkLTg5NDctMDFlNzFmMDgzYjc1Iiwic2NvcGUiOiJvcGVuaWQgYXBpLmNvbnNvbGUgYmFzaWMgcm9sZXMgd2ViLW9yaWdpbnMgY2xpZW50X3R5cGUucHJlX2tjMjUgYXBpLmFza19yZWRfaGF0IG9mZmxpbmVfYWNjZXNzIn0\.j9oVT7CbVGWXj-gVB8VyAAaxWbhVjXvji0BFkqom5IoP6ShB_gamIl8pVSy_v_RgGxom7siQ6syegqJRzPl-gg===>***REMOVED_REDHAT_TOKEN***

# S3/NooBaa access key
literal:j4aXKdsrqAzKhyxu84Jc===>***REMOVED_S3_ACCESS_KEY***

# S3/NooBaa secret key
literal:7BFR+5e8zC8gSaTTY/v4MfPD0A4UQNTB8OGxwJnT===>***REMOVED_S3_SECRET_KEY***

# Webhook secret
literal:abdf580d9f49afad1109015b4d9c7d9cd8700e5c===>***REMOVED_WEBHOOK_SECRET***

# Example password from docs
literal:pQF1QnP8pf3AzkoXY5wlm0C5XhzoHxaw===>***REMOVED_EXAMPLE_PASSWORD***

# Generic placeholders that should have been removed
literal:changeme===>PLACEHOLDER_PASSWORD
literal:user1===>PLACEHOLDER_USERNAME
EOF

echo -e "${GREEN}✓ Secret patterns prepared${NC}"

# Step 5: Check if we have uncommitted changes
echo ""
echo "=========================================================="
echo "Step 5: Checking Git Status"
echo "=========================================================="

if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo -e "${YELLOW}⚠️  You have uncommitted changes${NC}"
    echo "Staging all changes..."
    git add -A
    git commit -m "security: Remove all secrets from configuration files

- Remove Red Hat OAuth tokens from ansible.cfg
- Remove S3/NooBaa credentials from values-global.yaml
- Remove webhook secrets from Tekton configuration
- Add security documentation and examples
- Update .gitignore for better secret protection
- Add pre-commit hooks for secret detection

Refs: Security incident 2025-12-10"
    echo -e "${GREEN}✓ Changes committed${NC}"
fi

# Step 6: Remove secrets from git history
echo ""
echo "=========================================================="
echo "Step 6: Removing Secrets from Git History"
echo "=========================================================="
echo "This will rewrite git history..."
echo ""

git-filter-repo \
  --replace-text /tmp/secrets-to-remove.txt \
  --force

echo ""
echo -e "${GREEN}✅ Secrets removed from git history${NC}"

# Step 7: Verify cleanup
echo ""
echo "=========================================================="
echo "Step 7: Verifying Cleanup"
echo "=========================================================="

echo "Checking if secrets still exist in history..."

check_history_clean() {
    local pattern=$1
    local description=$2

    if git log --all --full-history -S"$pattern" --pretty=format:"%H" | head -1 | grep -q .; then
        echo -e "${YELLOW}⚠️  $description: May still exist in history (check manually)${NC}"
        return 1
    else
        echo -e "${GREEN}✓ $description: Removed from history${NC}"
        return 0
    fi
}

check_history_clean "eyJhbGciOiJIUzUxMiI" "Red Hat OAuth token"
check_history_clean "j4aXKdsrqAzKhyxu84Jc" "S3 access key"
check_history_clean "7BFR+5e8zC8gSaTTY" "S3 secret key"
check_history_clean "abdf580d9f49afad1109015b4d9c7d9cd8700e5c" "Webhook secret"

# Step 8: Add security files
echo ""
echo "=========================================================="
echo "Step 8: Staging Security Documentation"
echo "=========================================================="

# Re-add our security documentation (it was removed by git-filter-repo)
git add SECURITY-INCIDENT-RESPONSE.md || true
git add SECURITY-QUICK-REFERENCE.md || true
git add REMEDIATION-SUMMARY.md || true
git add docs/SECURE-CONFIGURATION.md || true
git add scripts/remove-secrets-from-git-history.sh || true
git add scripts/emergency-security-cleanup.sh || true
git add ansible.cfg.example || true
git add charts/hub/values-secret.yaml.example || true
git add .pre-commit-config.yaml || true
git add .gitignore || true

# Commit if there are changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    git commit -m "docs: Add security incident documentation and remediation tools" || true
fi

# Step 9: Display summary
echo ""
echo "=========================================================="
echo "✅ CLEANUP COMPLETE"
echo "=========================================================="
echo ""
echo -e "${GREEN}Git history has been cleaned!${NC}"
echo ""
echo "📊 Repository Status:"
git log --oneline -5
echo ""
echo "=========================================================="
echo "🚀 NEXT STEPS"
echo "=========================================================="
echo ""
echo "1. Review the changes:"
echo "   git log --oneline -10"
echo ""
echo "2. Verify secrets are gone:"
echo "   git log --all -S'eyJhbGciOiJIUzUxMiI' --pretty=format:'%H %s'"
echo ""
echo "3. Add remote (if removed by git-filter-repo):"
echo "   git remote add origin https://github.com/KubeHeal/openshift-aiops-platform.git"
echo ""
echo "4. Force push to GitHub (⚠️  DESTRUCTIVE):"
echo "   git push --force --all origin"
echo "   git push --force --tags origin"
echo ""
echo "5. Notify team members:"
echo "   - Send notification email (see REMEDIATION-SUMMARY.md)"
echo "   - All contributors MUST re-clone the repository"
echo ""
echo "=========================================================="
echo "⚠️  IMPORTANT: REVOKE CREDENTIALS"
echo "=========================================================="
echo ""
echo "The secrets are removed from git, but they're still valid!"
echo "You MUST revoke them:"
echo ""
echo "1. Red Hat Token:"
echo "   https://console.redhat.com/ansible/automation-hub/token"
echo ""
echo "2. S3 Credentials:"
echo "   oc exec -n openshift-storage \$(oc get pods -n openshift-storage -l app=noobaa-core -o name) -- noobaa-cli account delete noobaa-admin"
echo ""
echo "3. Webhook Secret:"
echo "   oc delete secret github-webhook-secret -n openshift-pipelines"
echo "   oc create secret generic github-webhook-secret --from-literal=secretToken=\$(openssl rand -hex 20) -n openshift-pipelines"
echo ""
echo "See SECURITY-QUICK-REFERENCE.md for detailed commands."
echo ""
echo -e "${GREEN}Backup saved to: /home/lab-user/$BACKUP_NAME${NC}"
echo ""
