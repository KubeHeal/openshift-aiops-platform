# Secure Configuration Guide

## Overview

This guide explains how to properly manage secrets and credentials in the OpenShift AI Ops Platform without committing them to git.

**⚠️ CRITICAL**: This project previously had secrets leaked to the public GitHub repository. This guide ensures that never happens again.

## Security Principles

1. **NEVER commit secrets to git** - Use environment variables or External Secrets Operator
2. **Use .gitignore** - Ensure sensitive files are git-ignored
3. **Rotate credentials regularly** - Change secrets every 90 days minimum
4. **Use External Secrets Operator** - Store secrets in external vaults (AWS, HashiCorp, Azure)
5. **Implement pre-commit hooks** - Scan for secrets before commits

---

## 1. Red Hat Automation Hub Token

### Get Your Token

1. Visit [Red Hat Automation Hub](https://console.redhat.com/ansible/automation-hub/token)
2. Log in with your Red Hat account
3. Click "Load Token"
4. Copy the token (starts with `eyJhbGc...`)

### Option A: Environment Variable (Recommended for CI/CD)

```bash
# Export token
export ANSIBLE_HUB_TOKEN='eyJhbGc...'

# Or add to ~/.bashrc
echo "export ANSIBLE_HUB_TOKEN='eyJhbGc...'" >> ~/.bashrc
source ~/.bashrc

# Ansible will use ANSIBLE_HUB_TOKEN automatically
```

### Option B: Local Configuration File (Recommended for Development)

```bash
# Copy example
cp ansible.cfg.example ansible.cfg.local

# Edit ansible.cfg.local and replace YOUR_TOKEN_HERE with real token
vi ansible.cfg.local

# Use local config
export ANSIBLE_CONFIG=ansible.cfg.local

# Verify
ansible-galaxy collection list
```

### Revoke Compromised Token

If your token is leaked:

1. Visit [Red Hat Automation Hub](https://console.redhat.com/ansible/automation-hub/token)
2. Click "Load Token"
3. Click "Revoke" button (⚠️ This invalidates the current token)
4. Generate new token
5. Update your environment variable or local config file

---

## 2. S3/NooBaa Credentials

### Get NooBaa Credentials

```bash
# Get access key
oc get secret noobaa-admin -n openshift-storage \
  -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d

# Get secret key
oc get secret noobaa-admin -n openshift-storage \
  -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d
```

### Option A: External Secrets Operator (RECOMMENDED)

Create ExternalSecret:

```yaml
# k8s/base/s3-credentials-externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: s3-credentials
  namespace: self-healing-platform
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretstore
    kind: SecretStore
  target:
    name: s3-credentials
    creationPolicy: Owner
  data:
    - secretKey: accessKey
      remoteRef:
        key: self-healing-platform/s3
        property: access_key_id
    - secretKey: secretKey
      remoteRef:
        key: self-healing-platform/s3
        property: secret_access_key
```

Deploy:

```bash
oc apply -f k8s/base/s3-credentials-externalsecret.yaml
```

### Option B: values-secret.yaml (Development)

```bash
# Copy example
cp charts/hub/values-secret.yaml.example charts/hub/values-secret.yaml

# Edit and add real credentials
vi charts/hub/values-secret.yaml

# Deploy (Helm will merge values-secret.yaml with values-global.yaml)
make -f common/Makefile operator-deploy
```

### Rotate NooBaa Credentials

```bash
# Delete old credentials
oc exec -n openshift-storage \
  $(oc get pods -n openshift-storage -l app=noobaa-core -o name) \
  -- noobaa-cli account delete noobaa-admin

# Create new credentials
oc exec -n openshift-storage \
  $(oc get pods -n openshift-storage -l app=noobaa-core -o name) \
  -- noobaa-cli account create noobaa-admin --new_password

# Update External Secrets or values-secret.yaml
```

---

## 3. Webhook Secrets

### Generate Webhook Secret

```bash
# Generate random secret
openssl rand -hex 20

# Create Kubernetes secret
oc create secret generic github-webhook-secret \
  --from-literal=secretToken=$(openssl rand -hex 20) \
  -n openshift-pipelines

# Get webhook URL
oc get route el-github-webhook-listener -n openshift-pipelines -o jsonpath='{.spec.host}'
```

### Configure GitHub Webhook

1. Go to repository Settings → Webhooks → Add webhook
2. **Payload URL**: `https://<route-from-above>`
3. **Content type**: `application/json`
4. **Secret**: Paste the generated secret token
5. **Events**: Select "Just the push event"
6. Click "Add webhook"

### Configure Gitea Webhook

1. Go to repository Settings → Webhooks → Add webhook → Gitea
2. **Target URL**: `https://<route-from-above>`
3. **HTTP Method**: POST
4. **POST Content Type**: `application/json`
5. **Secret**: Paste the generated secret token
6. **Trigger On**: Push events
7. Click "Add webhook"

---

## 4. Pre-Commit Secret Scanning

Install and configure pre-commit hooks to prevent secret commits:

### Install detect-secrets

```bash
pip install detect-secrets
```

### Create .pre-commit-config.yaml

```yaml
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
        exclude: |
          (?x)^(
            .*\.example$|
            .*\.md$|
            SECURITY-INCIDENT-RESPONSE\.md
          )
```

### Setup Baseline

```bash
# Generate baseline (scan current repo)
detect-secrets scan --baseline .secrets.baseline

# Install pre-commit hooks
pre-commit install

# Test
pre-commit run --all-files
```

### Update Baseline (After Remediation)

```bash
# After fixing secrets, update baseline
detect-secrets scan --baseline .secrets.baseline --force
```

---

## 5. Automated Secret Scanning in CI/CD

Add to Tekton pipeline or GitHub Actions:

### Tekton Task

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: secret-scan
spec:
  steps:
    - name: detect-secrets
      image: python:3.9-slim
      script: |
        #!/bin/bash
        pip install detect-secrets
        detect-secrets scan --baseline .secrets.baseline
        if [ $? -ne 0 ]; then
          echo "❌ SECRETS DETECTED IN CODE!"
          exit 1
        fi
```

### GitHub Actions

```yaml
name: Secret Scanning
on: [push, pull_request]

jobs:
  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install detect-secrets
        run: pip install detect-secrets
      - name: Scan for secrets
        run: detect-secrets scan --baseline .secrets.baseline
```

---

## 6. Credential Rotation Schedule

| Credential Type | Rotation Frequency | Owner | Notes |
|-----------------|-------------------|-------|-------|
| Red Hat OAuth Token | 180 days | Platform Team | Expires automatically |
| S3/NooBaa Credentials | 90 days | Platform Team | Rotate via noobaa-cli |
| Webhook Secrets | 90 days | DevOps Team | Update GitHub/Gitea webhooks |
| Gitea Admin Password | 90 days | Platform Team | Update via Gitea UI |
| Service Account Tokens | N/A | Kubernetes | Auto-rotated by K8s |

---

## 7. Security Incident Response

If secrets are accidentally committed:

1. **IMMEDIATELY revoke** all exposed credentials
2. **DO NOT just delete the files** - they remain in git history
3. **Use git-filter-repo** to remove secrets from history:
   ```bash
   chmod +x scripts/remove-secrets-from-git-history.sh
   ./scripts/remove-secrets-from-git-history.sh
   ```
4. **Force push** to remote (requires coordination with team)
5. **Notify all contributors** to re-clone repository
6. **Update SECURITY-INCIDENT-RESPONSE.md** with timeline
7. **Review access logs** for unauthorized usage

---

## 8. Checklist for New Contributors

Before committing any code:

- [ ] Read this security guide completely
- [ ] Install pre-commit hooks: `pre-commit install`
- [ ] Never commit `ansible.cfg.local`, `values-secret.yaml`, or `*.env` files
- [ ] Use example files (`.example` suffix) for templates
- [ ] Verify `.gitignore` includes sensitive files
- [ ] Test pre-commit hooks: `pre-commit run --all-files`
- [ ] Use External Secrets Operator for production deployments

---

## 9. Resources

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [Red Hat External Secrets Operator for OpenShift](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/security_and_compliance/external-secrets-operator-for-red-hat-openshift)
- [ADR-026: Secrets Management Automation](../docs/adrs/026-secrets-management-automation.md)
- [detect-secrets Documentation](https://github.com/Yelp/detect-secrets)
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)

---

## Questions?

Contact: Platform Security Team

**Last Updated**: 2025-12-10
**Version**: 1.0
**Status**: CRITICAL - MANDATORY READING
