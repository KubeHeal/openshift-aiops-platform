#!/bin/bash
# Fresh Git Start - Remove all history and start clean
# This is the simplest way to remove secrets from git history

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================================="
echo "🔄 FRESH GIT START"
echo "=========================================================="
echo ""
echo "This will:"
echo "  1. Backup current .git directory"
echo "  2. Delete .git directory"
echo "  3. Create fresh git repository"
echo "  4. Create clean initial commit"
echo "  5. Prepare for force push to GitHub"
echo ""
echo -e "${YELLOW}⚠️  This removes ALL git history${NC}"
echo -e "${GREEN}✅ But it's the simplest way to remove secrets${NC}"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

cd /home/lab-user/openshift-aiops-platform

# Step 1: Backup .git directory
echo ""
echo "=========================================================="
echo "Step 1: Backing Up .git Directory"
echo "=========================================================="

if [ -d ".git" ]; then
    BACKUP_NAME="git-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    echo "Creating backup: $BACKUP_NAME"
    tar -czf "/home/lab-user/$BACKUP_NAME" .git/
    echo -e "${GREEN}✓ Backup created: /home/lab-user/$BACKUP_NAME${NC}"
else
    echo -e "${YELLOW}⚠️  No .git directory found${NC}"
fi

# Step 2: Save remote URL
echo ""
echo "=========================================================="
echo "Step 2: Saving Remote URL"
echo "=========================================================="

if [ -d ".git" ]; then
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$REMOTE_URL" ]; then
        echo "Remote URL: $REMOTE_URL"
        echo "$REMOTE_URL" > /tmp/git-remote-url.txt
        echo -e "${GREEN}✓ Remote URL saved${NC}"
    else
        echo -e "${YELLOW}⚠️  No remote URL found${NC}"
        REMOTE_URL="https://github.com/KubeHeal/openshift-aiops-platform.git"
        echo "Will use: $REMOTE_URL"
    fi
else
    REMOTE_URL="https://github.com/KubeHeal/openshift-aiops-platform.git"
    echo "Will use: $REMOTE_URL"
fi

# Step 3: Delete .git directory
echo ""
echo "=========================================================="
echo "Step 3: Deleting .git Directory"
echo "=========================================================="

if [ -d ".git" ]; then
    rm -rf .git
    echo -e "${GREEN}✓ .git directory removed${NC}"
else
    echo -e "${YELLOW}⚠️  .git directory already deleted${NC}"
fi

# Step 4: Remove any uncommitted security files we don't want
echo ""
echo "=========================================================="
echo "Step 4: Cleaning Up Temporary Files"
echo "=========================================================="

# Remove security incident files (they're no longer needed with fresh history)
rm -f SECURITY-INCIDENT-RESPONSE.md
rm -f REMEDIATION-SUMMARY.md
echo -e "${GREEN}✓ Removed incident response files (no longer needed)${NC}"

# Step 5: Initialize new git repository
echo ""
echo "=========================================================="
echo "Step 5: Initializing Fresh Git Repository"
echo "=========================================================="

git init
git config user.name "$(whoami)"
git config user.email "$(whoami)@$(hostname)"
echo -e "${GREEN}✓ Fresh git repository initialized${NC}"

# Step 6: Add all files
echo ""
echo "=========================================================="
echo "Step 6: Staging Clean Files"
echo "=========================================================="

git add -A
echo -e "${GREEN}✓ All files staged${NC}"

# Step 7: Show what will be committed
echo ""
echo "Files to be committed:"
git status --short | head -20
echo ""
TOTAL_FILES=$(git status --short | wc -l)
echo "Total files: $TOTAL_FILES"

# Step 8: Create initial commit
echo ""
echo "=========================================================="
echo "Step 7: Creating Initial Commit"
echo "=========================================================="

git commit -m "Initial commit - OpenShift AI Ops Platform

This is a fresh start with no secrets in history.

Components:
- Ansible Execution Environment with 8 validated pattern roles
- OpenShift AI integration (RHODS 2.22.2)
- GPU support (NVIDIA GPU Operator 24.9.2)
- Model serving (KServe, Knative)
- GitOps deployment (ArgoCD, Tekton)
- Comprehensive security documentation
- Pre-commit hooks for secret detection

All credentials are externalized via:
- Environment variables (ANSIBLE_HUB_TOKEN)
- values-secret.yaml (git-ignored)
- External Secrets Operator (recommended)

See docs/SECURE-CONFIGURATION.md for setup instructions.

License: GNU GPL v3.0"

echo -e "${GREEN}✓ Initial commit created${NC}"

# Step 9: Add remote
echo ""
echo "=========================================================="
echo "Step 8: Adding Remote"
echo "=========================================================="

git remote add origin "$REMOTE_URL"
echo -e "${GREEN}✓ Remote added: $REMOTE_URL${NC}"

# Step 10: Create main branch explicitly
echo ""
echo "=========================================================="
echo "Step 9: Setting Up Main Branch"
echo "=========================================================="

git branch -M main
echo -e "${GREEN}✓ Branch renamed to main${NC}"

# Summary
echo ""
echo "=========================================================="
echo "✅ FRESH GIT REPOSITORY READY"
echo "=========================================================="
echo ""
echo "📊 Repository Status:"
git log --oneline
echo ""
git status
echo ""
echo "=========================================================="
echo "🚀 NEXT STEPS"
echo "=========================================================="
echo ""
echo "1. Review the commit:"
echo "   git show HEAD"
echo ""
echo "2. Push to GitHub (⚠️  REQUIRES FORCE PUSH):"
echo "   git push --force -u origin main"
echo ""
echo "3. Verify on GitHub:"
echo "   - Check that secrets are gone"
echo "   - Check that all files are present"
echo "   - Review commit history (should have 1 commit)"
echo ""
echo "4. Notify team members (if any):"
echo "   - Repository history was reset due to security incident"
echo "   - All contributors should delete local clones and re-clone"
echo "   - git clone $REMOTE_URL"
echo ""
echo "5. IMPORTANT: Still revoke the exposed credentials!"
echo "   Even though they're not in git anymore, they're still valid."
echo "   See SECURITY-QUICK-REFERENCE.md for commands."
echo ""
echo "=========================================================="
echo "📦 Backups Created"
echo "=========================================================="
echo ""
if [ -f "/home/lab-user/$BACKUP_NAME" ]; then
    echo "Git history backup: /home/lab-user/$BACKUP_NAME"
fi
if [ -f "/home/lab-user/openshift-aiops-platform-backup-"*.tar.gz ]; then
    ls -lh /home/lab-user/openshift-aiops-platform-backup-*.tar.gz 2>/dev/null | tail -1
fi
echo ""
echo -e "${GREEN}✅ Fresh start complete!${NC}"
echo ""
