# Values Files Guide - What to Commit vs. Ignore

## 📋 Quick Reference

### ✅ Committed to Git (Safe Templates)
- `values-global.yaml.example` - Template with placeholder values
- `values-global.yaml.template` - Template with detailed comments
- `values-hub.yaml.example` - Template for hub configuration
- `values-hub.yaml.template` - Template with detailed comments
- `values-secret.yaml.template` - Template for secrets (NO real secrets)
- `values-clustergroup.yaml` - Cluster topology (usually safe)

### ❌ NOT Committed (Git-Ignored)
- **`values-secret.yaml`** ⚠️ **CRITICAL** - Contains REAL secrets
- **`values-hub.yaml`** - User-specific cluster configuration
- **`values-global.yaml`** - User-specific global settings

---

## Why This Structure?

### Pattern Philosophy

The Validated Patterns framework uses a **template + override** pattern:

1. **Templates** (`.example`, `.template`) - Committed to git
   - Safe placeholder values
   - Documentation and comments
   - Reference for new deployments

2. **User Files** (no suffix) - Git-ignored
   - Real credentials
   - Cluster-specific URLs
   - Environment-specific settings

---

## 📖 Detailed Explanation

### `values-secret.yaml` ⚠️ NEVER COMMIT

**Contains:**
- Git credentials (Gitea/GitHub passwords)
- S3/NooBaa access keys
- Vault tokens
- API keys (OpenAI, Gemini)
- Grafana passwords

**Why git-ignore:**
- Real credentials that grant access to systems
- Leaking these to GitHub = security incident
- Should be stored in password manager or vault

**How to create:**
```bash
cp values-secret.yaml.template values-secret.yaml
# Edit and fill in real credentials
```

### `values-hub.yaml` - Git-ignore recommended

**Contains:**
- Cluster-specific URLs and domains
- ArgoCD application configurations
- Namespace settings
- Component enable/disable flags

**Why git-ignore:**
- Each deployment has different cluster URLs
- Port numbers and routes vary by environment
- Prevents accidental deployment to wrong cluster

**How to create:**
```bash
cp values-hub.yaml.example values-hub.yaml
# Customize for your cluster
```

### `values-global.yaml` - Git-ignore recommended

**Contains:**
- Pattern name and version
- Global enable/disable flags
- Storage class names
- Network policy settings

**Why git-ignore:**
- Storage classes vary by cloud provider
- Pattern names should be unique per deployment
- Prevents conflicts between multiple users

**How to create:**
```bash
cp values-global.yaml.example values-global.yaml
# Customize pattern name and storage
```

### `values-clustergroup.yaml` - Usually safe to commit

**Contains:**
- Cluster topology (hub/spoke relationships)
- Multi-cluster routing
- Cluster group definitions

**Why usually safe:**
- Contains topology, not credentials
- Useful for documentation
- Part of pattern architecture

**When to git-ignore:**
- If it contains specific cluster names/IDs
- If used for internal-only infrastructure

---

## 🔒 Security Best Practices

### 1. Use `.gitignore` Properly

Current `.gitignore` settings:
```gitignore
# Real secrets (NEVER commit)
values-secret.yaml
values-secret*.yaml

# User-specific configuration (git-ignore recommended)
values-hub.yaml
values-global.yaml
```

### 2. Use Templates

Always provide `.example` or `.template` versions:
- Document expected structure
- Provide safe placeholder values
- Help new users get started

### 3. External Secrets Operator (Production)

For production deployments, use External Secrets Operator instead of `values-secret.yaml`:

```yaml
# values-hub.yaml
secrets:
  backend: external-secrets  # Use ESO instead of files

  externalSecrets:
    enabled: true
    secretStore:
      name: aws-secretstore  # or vault, azure, etc.
```

---

## 📝 Workflow for New Deployments

### For Pattern Developers (Contributors)

1. **Only commit templates:**
   ```bash
   git add values-global.yaml.example
   git add values-hub.yaml.example
   git add values-secret.yaml.template
   git commit -m "docs: Update pattern templates"
   ```

2. **Never commit your actual config:**
   ```bash
   # These should be git-ignored
   git status | grep values-secret.yaml  # Should not appear
   git status | grep values-hub.yaml     # Should not appear
   ```

### For Pattern Users (Deployers)

1. **Copy templates to working files:**
   ```bash
   cp values-global.yaml.example values-global.yaml
   cp values-hub.yaml.example values-hub.yaml
   cp values-secret.yaml.template values-secret.yaml
   ```

2. **Customize your deployment:**
   ```bash
   vi values-global.yaml    # Set pattern name
   vi values-hub.yaml       # Set cluster URLs
   vi values-secret.yaml    # Add real credentials
   ```

3. **Deploy:**
   ```bash
   make -f common/Makefile operator-deploy
   ```

---

## 🔍 Verification Commands

### Check what will be committed:
```bash
git status | grep values-

# Should see:
#   new file:   values-global.yaml.example  ✅
#   new file:   values-hub.yaml.example     ✅
#   new file:   values-secret.yaml.template ✅

# Should NOT see:
#   values-secret.yaml  ❌
#   values-hub.yaml     ❌ (optional, but recommended)
#   values-global.yaml  ❌ (optional, but recommended)
```

### Check what is git-ignored:
```bash
git check-ignore values-secret.yaml values-hub.yaml values-global.yaml

# Should output:
#   values-secret.yaml  ✅
#   values-hub.yaml     ✅
#   values-global.yaml  ✅
```

### Search for secrets in git:
```bash
git log --all -S 'password' --source -- values*.yaml

# Should return empty (no passwords in committed files)
```

---

## ⚠️ Common Mistakes

### ❌ DON'T DO THIS:
```bash
# Committing real credentials
git add values-secret.yaml  # WRONG! Contains real secrets
git commit -m "Add secrets"
git push  # Now secrets are public!
```

### ✅ DO THIS INSTEAD:
```bash
# Commit templates only
git add values-secret.yaml.template  # Safe placeholder
git commit -m "Add secret template"
git push  # Safe to push
```

---

## 📚 Related Documentation

- **`.gitignore`** - Complete list of ignored files
- **`docs/SECURE-CONFIGURATION.md`** - Comprehensive security guide
- **`AGENTS.md`** - Agent-specific rules (includes this guidance)
- **[ADR-026](docs/adrs/026-secrets-management-automation.md)** - Secrets management architecture

---

## 🆘 What If I Already Committed Secrets?

If you accidentally committed `values-secret.yaml` or real credentials:

1. **DO NOT** just delete the file and commit
2. **DO** follow the security incident process:
   - Remove from git history (use `git filter-repo`)
   - Revoke/rotate all exposed credentials
   - Force push to replace history
   - See `docs/SECURE-CONFIGURATION.md` for details

---

## ✅ Checklist Before Push

- [ ] `values-secret.yaml` is in `.gitignore`
- [ ] `values-hub.yaml` is in `.gitignore` (recommended)
- [ ] `values-global.yaml` is in `.gitignore` (recommended)
- [ ] Only `.example` and `.template` files are staged
- [ ] No real passwords/tokens in committed files
- [ ] Verified with: `git log -S 'password' -- values*.yaml`

---

**Last Updated:** 2025-12-10
**Version:** 1.0
