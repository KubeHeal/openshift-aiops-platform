# Validated Patterns Ansible Toolkit Reference
## Local Reference Guide for OpenShift AIOps Platform

**Date:** 2025-11-02
**Toolkit Version:** 1.0.0
**Local Clone:** `my-pattern/` (git-ignored)
**Repository:** https://github.com/tosin2013/validated-patterns-ansible-toolkit

---

## Overview

The validated-patterns-ansible-toolkit has been cloned locally to `my-pattern/` for reference and development. This directory is git-ignored to prevent accidental commits while providing easy access to the toolkit's roles, playbooks, and documentation.

---

## Local Reference Structure

```
my-pattern/
├── ansible/
│   ├── roles/                    # 8 production-ready Ansible roles
│   │   ├── validated_patterns_prerequisites/
│   │   ├── validated_patterns_common/
│   │   ├── validated_patterns_operator/
│   │   ├── validated_patterns_deploy/
│   │   ├── validated_patterns_gitea/
│   │   ├── validated_patterns_secrets/
│   │   ├── validated_patterns_validate/
│   │   └── validated_patterns_cleanup/
│   └── playbooks/                # Example playbooks
│       ├── deploy_complete_pattern.yml
│       ├── install_gitops.yml
│       ├── test_prerequisites.yml
│       └── cleanup_pattern.yml
├── docs/                         # Comprehensive documentation
│   ├── ANSIBLE-ROLES-REFERENCE.md
│   ├── DEVELOPER-GUIDE.md
│   ├── END-USER-GUIDE.md
│   ├── QUICK-START-ROLES.md
│   ├── TROUBLESHOOTING-COMPREHENSIVE.md
│   └── adr/                      # Architectural Decision Records
├── collection/                   # Ansible Collection
│   └── tosin2013.validated_patterns_toolkit/
├── tests/                        # Integration tests
│   ├── integration/
│   ├── week8/
│   ├── week9/
│   └── week10/
└── ONBOARDING.md                 # Getting started guide
```

---

## Ansible Roles Reference

### 1. validated_patterns_prerequisites

**Purpose:** Validate cluster prerequisites before deployment

**Location:** `my-pattern/ansible/roles/validated_patterns_prerequisites/`

**Key Tasks:**
- Verify OpenShift cluster version
- Check cluster resources (CPU, memory, storage)
- Validate operator availability
- Test cluster connectivity

**Example Usage:**
```yaml
- name: Validate cluster prerequisites
  include_role:
    name: validated_patterns_prerequisites
  vars:
    min_openshift_version: "4.18"
    required_operators:
      - openshift-gitops-operator
      - openshift-pipelines-operator
```

**Related ADRs:** ADR-001 (OpenShift Platform Selection)

---

### 2. validated_patterns_common

**Purpose:** Deploy common GitOps infrastructure (Helm, ArgoCD)

**Location:** `my-pattern/ansible/roles/validated_patterns_common/`

**Key Tasks:**
- Install Helm
- Deploy OpenShift GitOps (ArgoCD)
- Configure GitOps repositories
- Setup ArgoCD applications

**Example Usage:**
```yaml
- name: Deploy GitOps infrastructure
  include_role:
    name: validated_patterns_common
  vars:
    gitops_enabled: true
    gitops_namespace: openshift-gitops
    helm_version: "3.12.0"
```

**Related ADRs:** ADR-019 (Validated Patterns Framework), ADR-027 (CI/CD Automation)

---

### 3. validated_patterns_operator

**Purpose:** Deploy patterns using the Validated Patterns Operator

**Location:** `my-pattern/ansible/roles/validated_patterns_operator/`

**Key Tasks:**
- Install Validated Patterns Operator
- Create Pattern custom resources
- Configure multi-cluster support
- Manage pattern lifecycle

**Example Usage:**
```yaml
- name: Deploy via Validated Patterns Operator
  include_role:
    name: validated_patterns_operator
  vars:
    pattern_name: self-healing-platform
    pattern_repo: https://github.com/KubeHeal/openshift-aiops-platform.git
    pattern_branch: main
```

**Related ADRs:** ADR-020 (Bootstrap Deployment Lifecycle), ADR-029 (Multi-Cluster)

---

### 4. validated_patterns_deploy

**Purpose:** Deploy applications and configure Tekton pipelines

**Location:** `my-pattern/ansible/roles/validated_patterns_deploy/`

**Key Tasks:**
- Deploy Tekton pipelines
- Configure pipeline triggers
- Deploy applications via Helm
- Setup CI/CD workflows

**Example Usage:**
```yaml
- name: Deploy Tekton pipelines
  include_role:
    name: validated_patterns_deploy
  vars:
    deploy_tekton_pipelines: true
    tekton_namespace: openshift-pipelines
    pipelines:
      - deployment-validation-pipeline
      - model-serving-validation-pipeline
```

**Related ADRs:** ADR-023 (Tekton Configuration), ADR-027 (CI/CD Automation)

---

### 5. validated_patterns_gitea

**Purpose:** Deploy Gitea local Git repository

**Location:** `my-pattern/ansible/roles/validated_patterns_gitea/`

**Key Tasks:**
- Deploy Gitea operator
- Create Gitea instance
- Configure admin and user accounts
- Setup repository mirroring

**Example Usage:**
```yaml
- name: Deploy Gitea
  include_role:
    name: validated_patterns_gitea
  vars:
    gitea_namespace: gitea
    gitea_admin_user: opentlc-mgr
    gitea_ssl_enabled: true
    gitea_create_users: true
```

**Related ADRs:** ADR-028 (Gitea Local Git Repository)

---

### 6. validated_patterns_secrets

**Purpose:** Manage secrets with External Secrets Operator

**Location:** `my-pattern/ansible/roles/validated_patterns_secrets/`

**Key Tasks:**
- Deploy External Secrets Operator
- Configure SecretStores
- Create ExternalSecrets
- Integrate with Vault/AWS Secrets Manager

**Example Usage:**
```yaml
- name: Deploy secrets management
  include_role:
    name: validated_patterns_secrets
  vars:
    secrets_backend: external-secrets
    secrets_vault_enabled: true
    secrets_vault_address: "https://vault.example.com"
    secrets_rotation_enabled: true
```

**Related ADRs:** ADR-024 (External Secrets Model Storage), ADR-026 (Secrets Management Automation)

---

### 7. validated_patterns_validate

**Purpose:** Validate pattern deployment and health

**Location:** `my-pattern/ansible/roles/validated_patterns_validate/`

**Key Tasks:**
- Run deployment validation tests
- Check application health
- Verify GitOps sync status
- Generate validation reports

**Example Usage:**
```yaml
- name: Validate deployment
  include_role:
    name: validated_patterns_validate
  vars:
    validate_gitops: true
    validate_tekton: true
    validate_applications: true
```

**Related ADRs:** ADR-021 (Tekton Pipeline Deployment Validation)

---

### 8. validated_patterns_cleanup

**Purpose:** Clean up pattern resources

**Location:** `my-pattern/ansible/roles/validated_patterns_cleanup/`

**Key Tasks:**
- Remove pattern applications
- Clean up operators
- Delete namespaces
- Restore cluster state

**Example Usage:**
```yaml
- name: Cleanup pattern
  include_role:
    name: validated_patterns_cleanup
  vars:
    cleanup_namespaces:
      - self-healing-platform
      - gitea
    cleanup_operators: true
```

---

## Example Playbooks

### Deploy Complete Pattern

**Location:** `my-pattern/ansible/playbooks/deploy_complete_pattern.yml`

```yaml
---
- name: Deploy Complete Validated Pattern
  hosts: localhost
  gather_facts: false

  tasks:
    - name: Validate prerequisites
      include_role:
        name: validated_patterns_prerequisites

    - name: Deploy GitOps infrastructure
      include_role:
        name: validated_patterns_common

    - name: Deploy pattern via operator
      include_role:
        name: validated_patterns_operator

    - name: Validate deployment
      include_role:
        name: validated_patterns_validate
```

### Install GitOps

**Location:** `my-pattern/ansible/playbooks/install_gitops.yml`

```yaml
---
- name: Install OpenShift GitOps
  hosts: localhost
  gather_facts: false

  roles:
    - validated_patterns_common
```

---

## Quick Reference Commands

### Explore Roles
```bash
# List all roles
ls -la my-pattern/ansible/roles/

# View role README
cat my-pattern/ansible/roles/validated_patterns_gitea/README.md

# View role defaults
cat my-pattern/ansible/roles/validated_patterns_secrets/defaults/main.yml

# View role tasks
cat my-pattern/ansible/roles/validated_patterns_common/tasks/main.yml
```

### Explore Playbooks
```bash
# List playbooks
ls -la my-pattern/ansible/playbooks/

# View playbook
cat my-pattern/ansible/playbooks/deploy_complete_pattern.yml
```

### Explore Documentation
```bash
# View onboarding guide
cat my-pattern/ONBOARDING.md

# View developer guide
cat my-pattern/docs/DEVELOPER-GUIDE.md

# View roles reference
cat my-pattern/docs/ANSIBLE-ROLES-REFERENCE.md

# View troubleshooting guide
cat my-pattern/docs/TROUBLESHOOTING-COMPREHENSIVE.md
```

### Explore Tests
```bash
# List integration tests
ls -la my-pattern/tests/integration/

# View test examples
cat my-pattern/tests/week10/test_complete_workflow.yml
```

---

## Integration with OpenShift AIOps Platform

### Current Integration Status

| Role | ADR | Status | Playbook |
|------|-----|--------|----------|
| validated_patterns_prerequisites | ADR-001 | ✅ Documented | - |
| validated_patterns_common | ADR-019, ADR-027 | ✅ Documented | deploy_cicd_pipelines.yml |
| validated_patterns_operator | ADR-020 | ✅ Documented | - |
| validated_patterns_deploy | ADR-023, ADR-027 | ✅ Documented | deploy_cicd_pipelines.yml |
| validated_patterns_gitea | ADR-028 | ✅ Deployed | deploy_gitea.yml |
| validated_patterns_secrets | ADR-024, ADR-026 | ✅ Documented | deploy_secrets_management.yml |
| validated_patterns_validate | ADR-021 | ✅ Documented | validate_deployment.yml |
| validated_patterns_cleanup | - | ✅ Available | cleanup_pattern.yml |

---

## Creating Custom Playbooks

### Template for New Playbooks

```yaml
---
- name: Custom Pattern Deployment
  hosts: localhost
  gather_facts: false

  vars:
    # Custom variables
    pattern_name: my-custom-pattern
    namespace: my-namespace

  tasks:
    - name: Step 1 - Prerequisites
      include_role:
        name: validated_patterns_prerequisites
      vars:
        min_openshift_version: "4.18"

    - name: Step 2 - Deploy infrastructure
      include_role:
        name: validated_patterns_common
      vars:
        gitops_enabled: true

    - name: Step 3 - Deploy secrets
      include_role:
        name: validated_patterns_secrets
      vars:
        secrets_backend: external-secrets

    - name: Step 4 - Validate
      include_role:
        name: validated_patterns_validate
      vars:
        validate_gitops: true
```

---

## Updating the Local Reference

### Pull Latest Changes

```bash
# Navigate to reference directory
cd my-pattern/

# Pull latest changes
git pull origin main

# View changelog
cat CHANGELOG.md

# Return to project root
cd ..
```

### Check for Updates

```bash
# Check remote for updates
cd my-pattern/
git fetch origin
git log HEAD..origin/main --oneline

# View specific changes
git diff HEAD..origin/main -- ansible/roles/validated_patterns_gitea/
```

---

## Best Practices

### 1. Keep Reference Updated
```bash
# Weekly update
cd my-pattern/ && git pull && cd ..
```

### 2. Copy, Don't Modify
- Copy roles/playbooks to project directory
- Customize copies, not originals
- Keep `my-pattern/` pristine for reference

### 3. Document Customizations
- Document any role customizations in ADRs
- Track changes in project documentation
- Reference original role in comments

### 4. Test Before Production
- Test playbooks in development environment
- Use `--check` mode for dry runs
- Validate with `validated_patterns_validate` role

---

## Troubleshooting

### Issue: Role Not Found

```bash
# Verify role exists
ls -la my-pattern/ansible/roles/validated_patterns_<role_name>/

# Check role path in playbook
# Ensure roles_path includes my-pattern/ansible/roles/
```

### Issue: Outdated Reference

```bash
# Update reference
cd my-pattern/
git pull origin main
cd ..
```

### Issue: Permission Denied

```bash
# Check directory permissions
ls -la my-pattern/

# Fix permissions if needed
chmod -R u+rw my-pattern/
```

---

## Related Documentation

### Project Documentation
- [ADR-to-Automation Mapping](ADR-TO-AUTOMATION-MAPPING.md)
- [Gitea Integration Guide](GITEA-INTEGRATION-GUIDE.md)
- [Architectural Analysis Report](../ARCHITECTURAL-ANALYSIS-AND-ADR-AUTOMATION-REPORT.md)

### Toolkit Documentation (Local)
- `my-pattern/ONBOARDING.md` - Getting started
- `my-pattern/docs/DEVELOPER-GUIDE.md` - Developer guide
- `my-pattern/docs/ANSIBLE-ROLES-REFERENCE.md` - Roles reference
- `my-pattern/docs/TROUBLESHOOTING-COMPREHENSIVE.md` - Troubleshooting

### External Links
- [GitHub Repository](https://github.com/tosin2013/validated-patterns-ansible-toolkit)
- [Validated Patterns Documentation](https://validatedpatterns.io/)
- [Red Hat Hybrid Cloud Patterns](https://hybrid-cloud-patterns.io/)

---

**Last Updated:** 2025-11-02
**Local Clone:** `my-pattern/` (git-ignored)
**Status:** ✅ Reference Available
