# GitHub Secrets Setup for Execution Environment Build

This guide explains how to configure the required GitHub secrets for the automated Execution Environment (EE) build workflow.

## Overview

The `build-ee.yml` GitHub Action workflow automatically builds and pushes the Ansible execution environment image to Quay.io. This requires authentication with multiple registries:

1. **Quay.io** - To push the built image
2. **Red Hat Registry** - To pull the base image
3. **Ansible Automation Hub** - To download certified collections

## Required Secrets

Add these secrets to your GitHub repository:

**Settings → Secrets and variables → Actions → New repository secret**

### 1. QUAY_USERNAME

**Description**: Quay.io username or robot account name

**How to get**:
1. Go to [quay.io](https://quay.io)
2. Log in to your account
3. For robot accounts: Repository Settings → Robot Accounts → Create Robot Account

**Value**: `takinosh` (or your robot account name like `takinosh+github_actions`)

### 2. QUAY_PASSWORD

**Description**: Quay.io password or robot token

**How to get**:
1. For personal account: Use your Quay.io password
2. For robot account (recommended):
   - Go to Repository Settings → Robot Accounts
   - Create or select a robot account
   - Copy the token

**Value**: Your password or robot token

### 3. REDHAT_REGISTRY_USER

**Description**: Red Hat Container Registry username

**How to get**:
1. Go to [Red Hat Registry Service Accounts](https://access.redhat.com/terms-based-registry/)
2. Create a new service account or use existing
3. Copy the username

**Value**: `12345678|your-service-account` (format: registry_key|account_name)

### 4. REDHAT_REGISTRY_PASSWORD

**Description**: Red Hat Container Registry token

**How to get**:
1. Go to [Red Hat Registry Service Accounts](https://access.redhat.com/terms-based-registry/)
2. Click on your service account
3. Go to "Token Information" tab
4. Copy the token

**Value**: The long token string

### 5. ANSIBLE_HUB_TOKEN

**Description**: Red Hat Ansible Automation Hub API token

**How to get**:
1. Go to [console.redhat.com](https://console.redhat.com)
2. Navigate to Ansible Automation Platform → Automation Hub
3. Click "Connect to Hub" or "Get Token"
4. Or directly: [Get Token](https://console.redhat.com/ansible/automation-hub/token)

**Value**: The API token string

## Verification

After adding all secrets, verify they are configured:

1. Go to repository **Settings → Secrets and variables → Actions**
2. You should see all 5 secrets listed:
   - `QUAY_USERNAME`
   - `QUAY_PASSWORD`
   - `REDHAT_REGISTRY_USER`
   - `REDHAT_REGISTRY_PASSWORD`
   - `ANSIBLE_HUB_TOKEN`

## Testing the Workflow

### Manual Trigger

1. Go to **Actions** tab
2. Select "Build Execution Environment" workflow
3. Click "Run workflow"
4. Select branch: `main`
5. Optionally specify a custom tag
6. Click "Run workflow"

### Automatic Triggers

The workflow runs automatically when:
- Push to `main` branch changes EE-related files
- A new release is published
- Manual workflow_dispatch

## Image Location

After successful build, the image is available at:

```
quay.io/takinosh/openshift-aiops-platform-ee:latest
quay.io/takinosh/openshift-aiops-platform-ee:sha-<commit>
quay.io/takinosh/openshift-aiops-platform-ee:<release-tag>
```

## Troubleshooting

### Authentication Errors

**Error**: `unauthorized: access to the requested resource is not authorized`

**Solutions**:
1. Verify QUAY_USERNAME and QUAY_PASSWORD are correct
2. For robot accounts, ensure the robot has write access to the repository
3. Check that the Quay.io repository exists and is accessible

### Base Image Pull Failure

**Error**: `Error: initializing source ... unauthorized`

**Solutions**:
1. Verify REDHAT_REGISTRY_USER and REDHAT_REGISTRY_PASSWORD
2. Ensure the service account has access to the required images
3. Test locally: `podman login registry.redhat.io`

### Collection Download Failure

**Error**: `ERROR! - theass following collections ...`

**Solutions**:
1. Verify ANSIBLE_HUB_TOKEN is valid
2. Check token hasn't expired (tokens are valid for ~90 days)
3. Regenerate token at [console.redhat.com](https://console.redhat.com/ansible/automation-hub/token)

## Security Notes

1. **Never commit secrets** to the repository
2. **Use robot accounts** for Quay.io instead of personal credentials
3. **Rotate secrets** periodically (recommended: every 90 days)
4. **Limit permissions** - Robot accounts should only have write access to specific repositories

## Related Documentation

- [Quay.io Robot Accounts](https://docs.quay.io/guides/robot-accounts.html)
- [Red Hat Registry Service Accounts](https://access.redhat.com/RegistryAuthentication)
- [Ansible Automation Hub Tokens](https://console.redhat.com/ansible/automation-hub/token)
- [GitHub Encrypted Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
