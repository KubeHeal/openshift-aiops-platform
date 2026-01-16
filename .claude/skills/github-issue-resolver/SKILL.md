---
name: github-issue-resolver
description: Strategically resolves GitHub Actions failures, failed pull requests, and Dependabot issues using the gh CLI. Use when managing CI/CD failures, PR check failures, merge conflicts, or automated dependency updates. Triggers on mentions of failed workflows, broken builds, failing tests, Dependabot PRs, or GitHub Actions issues.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# GitHub Issue Resolver

Automates GitHub repository maintenance by diagnosing and fixing GitHub Actions failures, managing failed pull requests, and strategically handling Dependabot updates using the GitHub CLI.

## Prerequisites

Before using this skill, verify:

```bash
# Check gh CLI is installed and authenticated
gh auth status

# Verify repository access (must have write permissions)
gh repo view

# Confirm you're in a git repository
git rev-parse --git-dir
```

**Required permissions**: Write access to the repository (for pushing fixes, merging PRs, re-running workflows)

**Required tools**:
- GitHub CLI (`gh`) version 2.0+
- Git CLI
- Appropriate language toolchains for the repository (npm, python, etc.)

---

## When to Use This Skill

Activate this skill when you need to:

- **Fix failing GitHub Actions workflows** - "diagnose the failed CI build", "fix the failing tests in Actions"
- **Resolve PR check failures** - "fix the failing PR checks", "resolve conflicts in PR #123"
- **Handle Dependabot updates** - "merge safe Dependabot PRs", "resolve Dependabot conflicts"
- **Triage multiple failures** - "fix all failing workflows", "clean up failed PRs"
- **Generate maintenance reports** - "show me all failing checks", "summarize GitHub issues"

---

## Core Workflows

### 1. GitHub Actions Failure Resolution

**Objective**: Identify failed workflow runs, analyze logs, diagnose root causes, implement fixes, and verify resolution.

#### Step 1: List Failed Workflows

```bash
# Get recent failed workflow runs
gh run list --status failure --limit 20

# Filter by specific workflow
gh run list --workflow "CI" --status failure --limit 10

# Get failed runs from specific branch
gh run list --branch main --status failure
```

**Output analysis**: Note the Run ID, workflow name, branch, and when it failed.

#### Step 2: Retrieve Failure Logs

```bash
# View summary of failed run
gh run view <run-id>

# Get detailed logs for failed jobs only
gh run view <run-id> --log-failed

# Get all logs (if needed for context)
gh run view <run-id> --log
```

**Log analysis checklist**:
- [ ] Identify the failing job(s) and step(s)
- [ ] Extract error messages and stack traces
- [ ] Determine failure category (test, build, lint, dependency, environment)
- [ ] Check for patterns across multiple failures

#### Step 3: Diagnose Root Cause

Common failure patterns and diagnostic approaches:

**Test Failures**:
```bash
# Look for test file references in logs
# Common indicators: "FAIL", "AssertionError", "Expected X but got Y"
# Action: Read test files, understand assertion failures
```

**Build Errors**:
```bash
# Look for compilation/build tool errors
# Common indicators: "error TS", "npm ERR!", "ModuleNotFoundError"
# Action: Check dependencies, configuration files, recent code changes
```

**Linting Issues**:
```bash
# Look for linter output
# Common indicators: "eslint", "flake8", "error: formatting"
# Action: Run linter locally, apply fixes
```

**Dependency Problems**:
```bash
# Look for package installation failures
# Common indicators: "Could not resolve", "ENOTFOUND", "version conflict"
# Action: Check package.json/requirements.txt, update lockfiles
```

**Environment Issues**:
```bash
# Look for environment-specific errors
# Common indicators: "command not found", "permission denied", "timeout"
# Action: Review workflow YAML, check environment configuration
```

#### Step 4: Implement Fix

Based on diagnosis, implement the appropriate fix:

```bash
# For code fixes - edit the relevant files
# Use Read to examine files, Edit to fix issues

# For dependency fixes
npm install              # Update package-lock.json
npm audit fix           # Fix security vulnerabilities
pip install -r requirements.txt  # Update Python dependencies

# For configuration fixes
# Edit .github/workflows/*.yml as needed

# For linting fixes
npm run lint:fix        # Auto-fix linting issues
black .                 # Python formatting
```

#### Step 5: Commit and Push Fix

```bash
# Stage changes
git add .

# Create descriptive commit
git commit -m "fix: resolve <failure-type> in <workflow-name>

- <specific fix description>
- Addresses run #<run-id>"

# Push to appropriate branch
git push origin <branch-name>
```

#### Step 6: Verify Resolution

```bash
# Wait for workflow to complete
gh run watch

# Or manually rerun the failed workflow
gh run rerun <run-id>

# Monitor until completion
gh run view <run-id> --watch

# Verify success
gh run list --workflow "<workflow-name>" --limit 5
```

**Success criteria**: Workflow status changes to "completed" with conclusion "success"

---

### 2. Failed Pull Request Management

**Objective**: Identify PRs with failing checks, diagnose issues, implement fixes, and get PRs back to mergeable state.

#### Step 1: List PRs with Failed Checks

```bash
# List all open PRs
gh pr list --state open

# Check status of specific PR
gh pr checks <pr-number>

# List PRs with detailed status
gh pr status

# Filter PRs by author (useful for Dependabot later)
gh pr list --author "app/dependabot"
```

#### Step 2: Analyze PR Failures

```bash
# View PR details
gh pr view <pr-number>

# Get check details
gh pr checks <pr-number> --watch

# See PR diff
gh pr diff <pr-number>
```

**Failure categories**:
1. **Failed CI checks** → Follow GitHub Actions resolution workflow
2. **Merge conflicts** → Resolve conflicts (see below)
3. **Failed required reviews** → Address review comments
4. **Branch out of date** → Update with base branch

#### Step 3: Checkout PR Branch

```bash
# Checkout the PR branch locally
gh pr checkout <pr-number>

# Verify you're on the PR branch
git branch --show-current

# See what changes were made
git log --oneline origin/main..HEAD
```

#### Step 4: Resolve Issues

**For merge conflicts**:
```bash
# Update branch with latest from base (usually main)
gh pr update-branch <pr-number>

# Or manually merge
git fetch origin
git merge origin/main

# Resolve conflicts in files
# Use Edit tool to fix conflict markers

# Complete merge
git add .
git commit -m "fix: resolve merge conflicts with main"
git push
```

**For failed checks**:
```bash
# Follow GitHub Actions workflow to fix failing tests/builds
# Run checks locally first
npm test                # Run tests
npm run build          # Run build
npm run lint           # Run linting

# Fix issues, commit, push
git add .
git commit -m "fix: address PR check failures"
git push
```

**For review comments**:
```bash
# Read review comments
gh pr view <pr-number> --comments

# Address each comment in code
# Use Edit tool to make changes

# Commit fixes
git add .
git commit -m "fix: address review comments"
git push

# Optionally request re-review
gh pr review <pr-number> --request-review
```

#### Step 5: Add PR Comment

Document what was fixed:

```bash
# Add comment explaining changes
gh pr comment <pr-number> --body "### Fixes Applied

- ✅ Resolved merge conflicts with main
- ✅ Fixed failing test in \`test/feature.test.js\`
- ✅ Updated dependencies to resolve build error

All checks now passing. Ready for review."
```

#### Step 6: Verify PR Status

```bash
# Check if all checks pass
gh pr checks <pr-number>

# View updated PR status
gh pr view <pr-number>

# If ready, merge (only with explicit approval)
# gh pr merge <pr-number> --merge  # Use with caution
```

---

### 3. Dependabot Issue Handling

**Objective**: Efficiently manage automated dependency updates with strategic merging, conflict resolution, and security prioritization.

#### Step 1: List Dependabot PRs

```bash
# Get all Dependabot PRs
gh pr list --author "app/dependabot" --state open

# Get Dependabot PRs with status
gh pr list --author "app/dependabot" --json number,title,headRefName,statusCheckRollup

# Check for failed Dependabot checks
for pr in $(gh pr list --author "app/dependabot" --json number -q '.[].number'); do
  echo "PR #$pr:"
  gh pr checks $pr
done
```

#### Step 2: Categorize Updates

Group Dependabot PRs by type and risk:

**Patch updates (1.2.3 → 1.2.4)**: Low risk, usually safe to batch merge
**Minor updates (1.2.3 → 1.3.0)**: Medium risk, review changelog
**Major updates (1.2.3 → 2.0.0)**: High risk, potential breaking changes
**Security updates**: High priority regardless of version change

```bash
# View PR to see version change and changelog
gh pr view <pr-number>

# Check for security updates (labeled by Dependabot)
gh pr list --author "app/dependabot" --label "security"
```

#### Step 3: Evaluate Breaking Changes

For each PR, especially major/minor updates:

```bash
# Read the PR description for changelog
gh pr view <pr-number>

# Check the dependency's changelog/release notes
# (Dependabot usually includes this in PR description)

# For critical dependencies, review their GitHub releases
gh release list --repo <dependency-repo>
```

**Decision criteria**:
- **Auto-merge candidates**: Patch updates with passing checks, no conflicts
- **Manual review needed**: Major updates, failed checks, security updates
- **Batch merge candidates**: Multiple patch updates to unrelated dependencies

#### Step 4: Resolve Dependabot PR Conflicts

```bash
# Checkout Dependabot PR
gh pr checkout <pr-number>

# Option 1: Use Dependabot commands (preferred)
gh pr comment <pr-number> --body "@dependabot rebase"

# Wait for Dependabot to rebase
sleep 30
gh pr checks <pr-number>

# Option 2: Manual rebase if Dependabot fails
git fetch origin
git rebase origin/main

# Resolve conflicts if any
# Edit conflicting files (usually package-lock.json, yarn.lock)

git add .
git rebase --continue
git push --force-with-lease
```

#### Step 5: Handle Failed Dependabot Checks

```bash
# Get failure details
gh pr checks <pr-number>
gh run view <run-id> --log-failed

# Common Dependabot check failures:
# 1. Incompatible API changes → Update code to new API
# 2. Transitive dependency conflicts → Update other dependencies
# 3. Breaking test changes → Update tests
# 4. Build configuration changes → Update build config
```

**For incompatibility issues**:
```bash
# Checkout PR
gh pr checkout <pr-number>

# Identify breaking changes from changelogs
gh pr view <pr-number>

# Update code to match new API
# Use Read and Edit tools to fix incompatibilities

# Run tests locally
npm test

# Commit fixes
git add .
git commit -m "fix: update code for <package>@<version> compatibility"
git push
```

#### Step 6: Strategic Merging

**Security updates (highest priority)**:
```bash
# Merge immediately after checks pass
gh pr checks <pr-number>
gh pr merge <pr-number> --auto --merge
```

**Batch safe patch updates**:
```bash
# For each passing patch update:
gh pr checks <pr-number> && gh pr merge <pr-number> --auto --squash

# Or use Dependabot's merge command
gh pr comment <pr-number> --body "@dependabot merge"
```

**Major updates (careful review)**:
```bash
# Ensure all checks pass
gh pr checks <pr-number>

# Review changes thoroughly
gh pr diff <pr-number>

# Merge manually after verification
gh pr merge <pr-number> --merge
```

---

### 4. Strategic Prioritization & Triage

**Objective**: Systematically process multiple failures with appropriate prioritization.

#### Priority Levels

1. **🔴 Critical (P0)** - Handle immediately
   - Security vulnerabilities
   - Production build failures
   - Main branch workflow failures

2. **🟡 High (P1)** - Handle within hours
   - Failed PR checks blocking merges
   - Breaking test failures
   - Dependabot security updates

3. **🟢 Medium (P2)** - Handle within days
   - Dependabot minor/major updates
   - Non-blocking linting failures
   - Documentation build failures

4. **⚪ Low (P3)** - Handle when convenient
   - Dependabot patch updates (passing)
   - Optional workflow failures
   - Deprecated warnings

#### Triage Workflow

```bash
# Step 1: Gather all issues
echo "=== Failed Workflows ==="
gh run list --status failure --limit 10

echo "=== Failed PR Checks ==="
for pr in $(gh pr list --json number -q '.[].number'); do
  echo "Checking PR #$pr"
  gh pr checks $pr | grep -i "fail" && echo "PR #$pr has failures"
done

echo "=== Dependabot PRs ==="
gh pr list --author "app/dependabot"

# Step 2: Categorize by priority
# Create priority list (manual assessment needed)

# Step 3: Create action plan
```

#### Systematic Processing

```bash
# Process in priority order:

# 1. Fix critical failures first
gh run list --status failure --workflow "Production Deploy" --limit 5
# → Follow Actions resolution workflow

# 2. Merge security updates
gh pr list --author "app/dependabot" --label "security"
# → Follow Dependabot workflow, prioritize merging

# 3. Fix failed PR checks
gh pr list --search "is:open status:failure"
# → Follow PR management workflow

# 4. Batch merge safe Dependabot updates
gh pr list --author "app/dependabot" --search "is:open status:success"
# → Batch merge patch updates

# 5. Address remaining issues
# → Process medium/low priority items
```

#### Generate Summary Report

```bash
# Create markdown summary of actions taken
cat > GITHUB_MAINTENANCE_REPORT.md << 'EOF'
# GitHub Maintenance Report
**Date**: $(date +%Y-%m-%d)
**Repository**: $(gh repo view --json nameWithOwner -q .nameWithOwner)

## Actions Taken

### Critical Issues Resolved
- [ ] Fixed production workflow failure (run #1234)
- [ ] Merged security update for package X

### PR Failures Resolved
- [ ] Fixed failing tests in PR #56
- [ ] Resolved merge conflicts in PR #78

### Dependabot Updates
- [ ] Merged 5 patch updates
- [ ] Updated major version of library Y (breaking changes addressed)

## Pending Issues

### Requires Manual Review
- PR #90 - Major refactor, needs architecture review
- Workflow "Performance Tests" - Intermittent failures, needs investigation

### Blocked
- PR #45 - Waiting for external dependency release

## Statistics
- Workflows fixed: 3
- PRs unblocked: 4
- Dependabot PRs merged: 8
- Total issues resolved: 15
EOF
```

---

## Command Reference

### Essential gh CLI Commands

**Workflow Management**:
```bash
gh run list [--status STATUS] [--workflow NAME] [--limit N]
gh run view <run-id> [--log] [--log-failed] [--web]
gh run watch [<run-id>]
gh run rerun <run-id> [--failed]
gh run download <run-id>  # Download artifacts
gh workflow list
gh workflow view <workflow-name>
gh workflow run <workflow-name>
```

**Pull Request Management**:
```bash
gh pr list [--state STATE] [--author USER] [--label LABEL]
gh pr view <pr-number> [--web] [--comments]
gh pr checkout <pr-number>
gh pr checks <pr-number> [--watch]
gh pr diff <pr-number>
gh pr update-branch <pr-number>
gh pr comment <pr-number> --body "MESSAGE"
gh pr review <pr-number> [--approve|--request-changes|--comment]
gh pr merge <pr-number> [--merge|--squash|--rebase] [--auto]
gh pr status
```

**Issue Management**:
```bash
gh issue list [--state STATE] [--label LABEL]
gh issue view <issue-number>
gh issue comment <issue-number> --body "MESSAGE"
gh issue close <issue-number>
gh issue create --title "TITLE" --body "BODY"
```

**Repository Operations**:
```bash
gh repo view [--web]
gh api <endpoint>  # Direct API access
```

### Common Flags and Options

- `--limit N` - Limit results to N items
- `--json FIELDS` - Output as JSON with specific fields
- `-q QUERY` - JQ query for JSON output
- `--web` - Open in web browser
- `--watch` - Monitor for changes
- `--state [open|closed|merged|all]` - Filter by state

### Output Parsing Patterns

```bash
# Get PR numbers matching criteria
gh pr list --json number -q '.[].number'

# Get failed workflow run IDs
gh run list --status failure --json databaseId -q '.[].databaseId'

# Get PR titles and check status
gh pr list --json number,title,statusCheckRollup \
  -q '.[] | select(.statusCheckRollup[].status=="FAILURE")'

# Count Dependabot PRs
gh pr list --author "app/dependabot" --json number -q '. | length'
```

---

## Decision Trees

### Workflow Failure Diagnosis

```
Failed Workflow Run
│
├─ Build Failure?
│  ├─ YES → Check compilation errors
│  │       ├─ TypeScript errors? → Fix type issues, update tsconfig
│  │       ├─ Missing dependencies? → npm install, update lockfile
│  │       └─ Build config issue? → Check webpack/vite/etc config
│  └─ NO → Continue
│
├─ Test Failure?
│  ├─ YES → Identify failing tests
│  │       ├─ Assertion failures? → Fix logic, update tests
│  │       ├─ Timeout? → Increase timeout, optimize code
│  │       └─ Flaky tests? → Add retries, fix race conditions
│  └─ NO → Continue
│
├─ Linting Failure?
│  ├─ YES → Run linter locally
│  │       ├─ Auto-fixable? → Run lint:fix
│  │       └─ Manual fix needed? → Edit files per linter output
│  └─ NO → Continue
│
├─ Dependency Installation Failure?
│  ├─ YES → Check package manager logs
│  │       ├─ Version conflict? → Update dependencies
│  │       ├─ Network issue? → Retry, check registry
│  │       └─ Missing package? → Add to dependencies
│  └─ NO → Continue
│
└─ Environment Issue?
   ├─ YES → Check workflow YAML
   │       ├─ Missing step? → Add required step
   │       ├─ Wrong environment? → Update actions/setup-* versions
   │       └─ Permission issue? → Update workflow permissions
   └─ NO → Escalate to manual investigation
```

### Dependabot Merge Strategy

```
Dependabot PR
│
├─ Security Update?
│  ├─ YES → Priority: CRITICAL
│  │       ├─ Checks pass? → Merge immediately
│  │       └─ Checks fail? → Fix and merge ASAP
│  └─ NO → Continue
│
├─ Version Change Type?
│  ├─ PATCH (x.y.Z) → Priority: LOW
│  │   ├─ Checks pass? → Batch merge
│  │   ├─ Conflicts? → @dependabot rebase → merge
│  │   └─ Checks fail? → Investigate, fix if simple
│  │
│  ├─ MINOR (x.Y.0) → Priority: MEDIUM
│  │   ├─ Review changelog → Breaking changes?
│  │   │   ├─ NO → Treat as patch
│  │   │   └─ YES → Treat as major
│  │   └─ Checks fail? → Must fix before merge
│  │
│  └─ MAJOR (X.0.0) → Priority: HIGH (careful review)
│      ├─ Review migration guide
│      ├─ Check for breaking API changes
│      ├─ Update code for compatibility
│      ├─ Ensure all tests pass
│      └─ Merge only after thorough verification
│
└─ Special Cases
   ├─ Multiple updates to same package? → Take latest
   ├─ Conflicting updates? → Resolve dependencies first
   └─ Deprecated package? → Consider alternatives
```

### PR Check Failure Resolution

```
PR with Failed Checks
│
├─ What failed?
│  ├─ CI Workflow → Follow "Workflow Failure Diagnosis" tree
│  ├─ Required Review → Wait for reviewer or address comments
│  └─ Branch Protection → Check protection rules
│
├─ Merge Conflicts?
│  ├─ YES → Resolution path
│  │       ├─ gh pr update-branch (automatic)
│  │       └─ Manual merge if automatic fails
│  └─ NO → Continue
│
├─ Branch Out of Date?
│  ├─ YES → gh pr update-branch
│  └─ NO → Continue
│
└─ After fixes applied
   ├─ All checks pass? → Ready to merge
   ├─ Some checks still fail? → Iterate
   └─ Blocked by external factor? → Document and wait
```

---

## Safety Guidelines

### Actions Requiring Confirmation

**ALWAYS ask before**:
- Merging to protected branches (main, production, etc.)
- Force-pushing to any branch
- Deleting branches
- Closing issues or PRs
- Running destructive workflow operations
- Batch merging more than 5 PRs

**Example confirmation request**:
```
I've fixed the failing tests and all checks now pass.
Ready to merge PR #123 to main. Should I proceed with the merge?
```

### Rollback Procedures

If a fix makes things worse:

```bash
# 1. Identify the problematic commit
git log --oneline -5

# 2. Create revert commit
git revert <commit-hash>

# 3. Push revert
git push origin <branch-name>

# 4. If merged to main, create hotfix PR
git checkout -b hotfix/revert-broken-change
git revert <commit-hash>
git push origin hotfix/revert-broken-change
gh pr create --title "Hotfix: Revert broken change" \
  --body "Reverts commit <hash> which caused <issue>"
```

### What NOT to Automate

**Never automatically**:
- Merge PRs without check verification
- Ignore security warnings
- Disable required checks
- Skip code review requirements
- Force-push to protected branches
- Modify workflow permissions without review
- Approve your own PRs
- Merge major version updates without testing

### Defensive Practices

```bash
# Always verify before destructive actions
gh pr checks <pr-number>  # Before merging
git status                 # Before committing
git diff                   # Before pushing

# Create branches for risky fixes
git checkout -b fix/issue-name
# Make changes
# Test thoroughly
# Then merge

# Save work frequently
git add .
git stash  # If switching contexts

# Document your actions
gh pr comment <pr-number> --body "Detailed explanation"
git commit -m "Detailed message"
```

---

## Examples

### Example 1: Fix Failed CI Workflow

**Scenario**: Main branch CI workflow fails with test errors.

```bash
# 1. Identify failure
$ gh run list --status failure --limit 5
STATUS  NAME  BRANCH  EVENT  ID
X       CI    main    push   12345678

# 2. Get failure details
$ gh run view 12345678 --log-failed
# Output shows: "TypeError: Cannot read property 'map' of undefined in src/utils.js:42"

# 3. Diagnose
$ # Read the file to understand the issue
# (Use Read tool to examine src/utils.js:42)

# 4. Fix the issue
$ # (Use Edit tool to add null check)
# Change: data.map(x => x.id)
# To: data?.map(x => x.id) || []

# 5. Commit and push
$ git add src/utils.js
$ git commit -m "fix: add null check in utils.js map operation

- Prevents TypeError when data is undefined
- Addresses CI failure in run #12345678"

$ git push origin main

# 6. Monitor resolution
$ gh run watch
✓ CI completed successfully
```

### Example 2: Resolve PR with Failed Checks and Conflicts

**Scenario**: PR #89 has failing tests and merge conflicts.

```bash
# 1. Check PR status
$ gh pr view 89
#89 Add user authentication (feature/auth)
Status: Some checks failing, conflicts with base branch

$ gh pr checks 89
X  CI - Tests Failed
X  Merge conflict

# 2. Checkout PR
$ gh pr checkout 89
Switched to branch 'feature/auth'

# 3. Resolve conflicts
$ gh pr update-branch 89
# If automatic fails:
$ git fetch origin
$ git merge origin/main
# CONFLICT in src/auth.js
# (Use Edit tool to resolve conflicts)

$ git add src/auth.js
$ git commit -m "fix: resolve merge conflicts with main"

# 4. Fix failing tests
$ npm test
# FAIL: auth.test.js - Expected mock to be called once, but was called 0 times

# (Use Read tool to examine auth.test.js)
# (Use Edit tool to fix test)

$ npm test
# PASS: All tests passed

# 5. Commit fix
$ git add .
$ git commit -m "fix: update auth tests for new API structure"
$ git push

# 6. Verify and comment
$ gh pr checks 89
✓ All checks passing

$ gh pr comment 89 --body "### Fixes Applied

✅ Resolved merge conflicts with main
✅ Fixed failing auth tests (updated for new API structure)

All checks now passing. Ready for review."
```

### Example 3: Strategic Dependabot Management

**Scenario**: 15 Dependabot PRs pending, mix of security, patch, and major updates.

```bash
# 1. List all Dependabot PRs
$ gh pr list --author "app/dependabot"
#95  Bump axios from 0.21.1 to 1.6.2 (security)
#94  Bump lodash from 4.17.20 to 4.17.21 (patch)
#93  Bump express from 4.17.1 to 4.18.2 (minor)
#92  Bump react from 17.0.2 to 18.2.0 (major)
... (11 more)

# 2. Categorize by priority
$ gh pr list --author "app/dependabot" --label "security"
#95  Bump axios from 0.21.1 to 1.6.2

# Priority 1: Security update
$ gh pr checks 95
✓ All checks passing
$ gh pr merge 95 --squash
✓ Merged

# 3. Batch merge safe patch updates
$ for pr in 94 96 98 100 102; do
  echo "Checking PR #$pr"
  if gh pr checks $pr | grep -q "✓"; then
    gh pr merge $pr --squash
    echo "Merged PR #$pr"
  fi
done

# 4. Handle major update carefully
$ gh pr view 92
# Review changelog, breaking changes

$ gh pr checkout 92
$ npm test
# FAIL: Component tests fail due to React 18 API changes

# Fix incompatibilities
# (Use Read/Edit tools to update React APIs)
# Update: ReactDOM.render → createRoot

$ npm test
# PASS

$ git add .
$ git commit -m "fix: update React APIs for v18 compatibility"
$ git push

$ gh pr checks 92
✓ All checks passing

$ gh pr comment 92 --body "@dependabot merge"

# 5. Summary
# Total Dependabot PRs processed: 15
# Security updates merged: 1
# Patch updates merged: 8
# Minor updates merged: 4
# Major updates merged: 1 (after compatibility fixes)
# Pending manual review: 1 (complex breaking change)
```

### Example 4: Triage Multiple Failures

**Scenario**: Monday morning - multiple failures accumulated over weekend.

```bash
# 1. Assess situation
$ echo "=== Workflow Failures ==="
$ gh run list --status failure --limit 10
# 3 failed runs: 2x CI (main), 1x Deploy (staging)

$ echo "=== PR Check Failures ==="
$ for pr in $(gh pr list --json number -q '.[].number'); do
  if gh pr checks $pr | grep -q "X"; then
    echo "PR #$pr has failures"
  fi
done
# PR #87, #91, #103 have failures

$ echo "=== Dependabot ==="
$ gh pr list --author "app/dependabot" | wc -l
# 12 Dependabot PRs

# 2. Prioritize
# P0: Deploy failure (blocks staging releases)
# P1: Main branch CI failures (blocks development)
# P1: Security Dependabot PRs
# P2: PR check failures
# P3: Other Dependabot PRs

# 3. Execute in priority order
# Fix deploy failure first
$ gh run view <deploy-run-id> --log-failed
# (Follow workflow failure resolution...)

# Fix main branch CI
$ gh run view <ci-run-id> --log-failed
# (Follow workflow failure resolution...)

# Process security Dependabot
$ gh pr list --author "app/dependabot" --label "security"
# (Follow Dependabot workflow...)

# Fix PR failures
# (Follow PR management workflow...)

# Batch process remaining Dependabot
# (Follow Dependabot workflow...)

# 4. Generate report
$ cat > TRIAGE_REPORT_$(date +%Y%m%d).md << 'EOF'
# Triage Report - 2024-01-15

## Summary
- Total issues identified: 18
- Critical issues resolved: 1 (deploy failure)
- Workflows fixed: 2
- PRs unblocked: 3
- Dependabot PRs merged: 10
- Pending manual review: 2

## Time spent: 2 hours
## Status: All critical issues resolved
EOF
```

---

## Error Handling

### Common Failure Modes

**1. Authentication Issues**
```bash
Error: authentication required
```
**Recovery**:
```bash
gh auth login
gh auth status
```

**2. Permission Denied**
```bash
Error: Resource not accessible by integration
```
**Recovery**: Verify you have write access to the repository. Contact repository admin if needed.

**3. Rate Limiting**
```bash
Error: API rate limit exceeded
```
**Recovery**: Wait for rate limit reset or authenticate with a different token.
```bash
gh auth status  # Check rate limit
# Wait or use authenticated requests
```

**4. Merge Conflicts Too Complex**
```bash
Error: Automatic merge failed
```
**Recovery**: Manual intervention required.
```bash
# Escalate to manual resolution
echo "Merge conflicts require manual review:"
git status
# Document conflict areas
# Request human intervention
```

**5. Failed Checks Cannot Be Fixed Automatically**
```bash
# When root cause is unclear or fix is complex
```
**Recovery**: Document findings and escalate.
```bash
gh pr comment <pr-number> --body "## Automated Fix Attempted

Unable to automatically resolve check failures.

### Diagnosis
- [Finding 1]
- [Finding 2]

### Recommended Actions
- [ ] Manual review of [specific area]
- [ ] Consider [alternative approach]

cc @maintainer"
```

### Recovery Strategies

**Strategy 1: Incremental Fixes**
- Fix one issue at a time
- Verify after each fix
- Rollback if new issues emerge

**Strategy 2: Safe Rollback**
```bash
git log --oneline -5
git revert <hash>
git push
```

**Strategy 3: Create Issue for Complex Problems**
```bash
gh issue create --title "Automated fix failed for workflow X" \
  --body "## Context
Attempted to fix workflow failure but encountered:
[detailed description]

## Logs
\`\`\`
[relevant logs]
\`\`\`

## Next Steps
- [ ] Manual investigation needed
- [ ] Possible root cause: [hypothesis]"
```

### When to Abort and Alert

**Abort immediately if**:
- Fixes would require force-pushing to protected branches
- Changes would affect critical production code without tests
- Root cause cannot be diagnosed from available information
- Fix requires architectural decisions beyond code changes
- Security implications are unclear

**Alert maintainers when**:
- Multiple fix attempts fail
- Issues indicate deeper architectural problems
- Security vulnerabilities are discovered
- Breaking changes affect multiple systems

**Escalation template**:
```bash
gh issue create --title "🚨 Automated resolution failed: [Issue]" \
  --label "needs-attention" \
  --body "## Automated Resolution Attempted

**Issue**: [Description]
**Severity**: [Critical/High/Medium]
**Workflow/PR**: [Link]

## What Was Tried
1. [Action 1] - Result: [Outcome]
2. [Action 2] - Result: [Outcome]

## Current State
- [Status of system]
- [Blockers identified]

## Recommendation
Manual intervention required for:
- [ ] [Specific task]
- [ ] [Specific task]

## Additional Context
[Logs, stack traces, relevant info]"
```

---

## Best Practices

1. **Verify Before Acting**: Always check current state before making changes
2. **Document Everything**: Use descriptive commits and PR comments
3. **Test Locally**: Run tests and builds locally before pushing when possible
4. **Incremental Changes**: Make small, focused commits rather than large batch changes
5. **Monitor Results**: Watch workflow runs and PR checks after changes
6. **Communicate Clearly**: Explain what was fixed and why in PR comments
7. **Know Your Limits**: Escalate complex issues rather than forcing fixes
8. **Maintain Audit Trail**: Keep detailed logs of automated actions
9. **Security First**: Prioritize security updates over feature updates
10. **Respect Review Process**: Don't bypass code review requirements

---

## Quick Reference Card

```bash
# Triage
gh run list --status failure --limit 10
gh pr list --search "is:open status:failure"
gh pr list --author "app/dependabot"

# Diagnose
gh run view <run-id> --log-failed
gh pr checks <pr-number>
gh pr view <pr-number>

# Fix
gh pr checkout <pr-number>
gh pr update-branch <pr-number>
git add . && git commit -m "fix: description"
git push

# Verify
gh run watch
gh pr checks <pr-number>

# Merge (with confirmation)
gh pr merge <pr-number> --squash

# Emergency
git revert <hash> && git push
gh issue create --title "Alert" --label "urgent"
```

---

## Conclusion

This skill enables systematic, safe, and efficient GitHub repository maintenance. Always prioritize safety over speed, document all actions, and escalate when uncertain. The goal is to reduce toil while maintaining code quality and security standards.
