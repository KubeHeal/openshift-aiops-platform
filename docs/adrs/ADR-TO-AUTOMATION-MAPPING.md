# ADR to Automation Mapping
## Validated Patterns Ansible Toolkit Integration

**Date:** 2025-11-02
**Purpose:** Map each Architectural Decision Record (ADR) to corresponding Ansible playbooks and automation scripts
**Toolkit:** [validated-patterns-ansible-toolkit](https://github.com/tosin2013/validated-patterns-ansible-toolkit)

---

## Overview

This document provides a comprehensive mapping between ADRs and their automation implementations using the validated-patterns-ansible-toolkit. Each ADR is linked to:
1. **Ansible Roles**: Production-ready roles from the toolkit
2. **Playbooks**: Deployment and validation playbooks
3. **Tekton Pipelines**: CI/CD automation pipelines
4. **Validation Scripts**: Compliance and health check scripts

---

## ADR Automation Matrix

| ADR | Title | Ansible Role(s) | Playbook | Tekton Pipeline | Validation Script | Priority |
|-----|-------|-----------------|----------|-----------------|-------------------|----------|
| ADR-001 | OpenShift Platform Selection | validated_patterns_prerequisites | validate_cluster.yml | - | - | ✅ Implemented |
| ADR-019 | Validated Patterns Framework | validated_patterns_common | deploy_gitops.yml | - | - | ✅ Implemented |
| ADR-020 | Bootstrap Deployment Lifecycle | validated_patterns_operator | deploy_pattern.yml | - | - | ✅ Implemented |
| ADR-021 | Tekton Pipeline Validation | validated_patterns_validate | validate_deployment.yml | deployment-validation-pipeline | - | ✅ Implemented |
| ADR-023 | Tekton Configuration Pipeline | validated_patterns_deploy | deploy_tekton.yml | s3-configuration-pipeline | - | ✅ Implemented |
| ADR-024 | External Secrets Model Storage | validated_patterns_secrets | deploy_secrets.yml | - | - | ✅ Implemented |
| **ADR-026** | **Secrets Management Automation** | **validated_patterns_secrets** | **deploy_secrets_management.yml** | **secret-rotation-validation** | **validate-secrets-compliance.sh** | 🔴 **CRITICAL** |
| **ADR-027** | **CI/CD Pipeline Automation** | **validated_patterns_common + validated_patterns_deploy** | **deploy_cicd_pipelines.yml** | **deployment-validation-pipeline** | **validate-cicd-pipelines.sh** | 🟠 **HIGH** |
| **ADR-028** | **Gitea Local Git Repository** | **validated_patterns_gitea** | **deploy_gitea.yml** | **-** | **validate-gitea-deployment.sh** | 🟠 **HIGH** |
| ADR-029 | Multi-Cluster Deployment (TBD) | validated_patterns_operator | deploy_multi_cluster.yml | multi-cluster-validation | validate-acm-integration.sh | 🟡 MEDIUM |
| ADR-029 | Disaster Recovery (TBD) | validated_patterns_deploy | deploy_disaster_recovery.yml | backup-validation-pipeline | validate-backup-restore.sh | 🟠 HIGH |
| ADR-030 | Observability Automation (TBD) | validated_patterns_validate | deploy_observability.yml | monitoring-validation-pipeline | validate-observability.sh | 🟡 MEDIUM |

---

## Detailed ADR Mappings

### ADR-026: Secrets Management Automation

**Status:** ✅ ADR Created, 🔴 Implementation Pending

**Ansible Role:** `validated_patterns_secrets`

**Playbook:** `ansible/playbooks/deploy_secrets_management.yml`
```yaml
---
- name: Deploy Secrets Management with External Secrets Operator
  hosts: localhost
  gather_facts: false

  roles:
    - role: validated_patterns_secrets
      vars:
        secrets_backend: external-secrets
        secrets_vault_enabled: true
        secrets_vault_address: "{{ vault_address | default('') }}"
        secrets_rotation_enabled: true
        secrets_rotation_interval: "24h"
        secrets_compliance_standard: "pci-dss"
```

**Tekton Pipeline:** `tekton/pipelines/secret-rotation-validation.yaml`
```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: secret-rotation-validation
  namespace: openshift-pipelines
spec:
  tasks:
    - name: validate-external-secrets
      taskRef:
        name: validate-external-secrets
    - name: test-secret-connectivity
      taskRef:
        name: test-s3-connectivity
      runAfter:
        - validate-external-secrets
    - name: verify-rotation
      taskRef:
        name: verify-secret-rotation
      runAfter:
        - test-secret-connectivity
```

**Validation Script:** `scripts/validate-secrets-compliance.sh`
- ✅ Created
- Tests: ESO installation, SecretStore config, ExternalSecret sync, rotation, encryption, RBAC, audit logging
- Compliance: PCI-DSS, HIPAA, SOC2

**Deployment Command:**
```bash
# Deploy secrets management
ansible-playbook ansible/playbooks/deploy_secrets_management.yml \
  -e secrets_backend=external-secrets \
  -e secrets_vault_enabled=true

# Validate deployment
./scripts/validate-secrets-compliance.sh --compliance-standard pci-dss

# Run Tekton validation
tkn pipeline start secret-rotation-validation -n openshift-pipelines --showlog
```

**Related Documentation:**
- [Red Hat External Secrets Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/security_and_compliance/external-secrets-operator-for-red-hat-openshift)
- [Validated Patterns Secrets Role](https://github.com/tosin2013/validated-patterns-ansible-toolkit/tree/main/ansible/roles/validated_patterns_secrets)

---

### ADR-027: CI/CD Pipeline Automation

**Status:** ✅ ADR Created, 🔴 Implementation Pending

**Ansible Roles:**
- `validated_patterns_common` (ArgoCD/GitOps)
- `validated_patterns_deploy` (Tekton pipelines)

**Playbook:** `ansible/playbooks/deploy_cicd_pipelines.yml`
```yaml
---
- name: Deploy CI/CD Pipelines with Tekton and ArgoCD
  hosts: localhost
  gather_facts: false

  tasks:
    - name: Deploy GitOps infrastructure
      include_role:
        name: validated_patterns_common
      vars:
        gitops_enabled: true
        gitops_namespace: openshift-gitops

    - name: Deploy Tekton pipelines
      include_role:
        name: validated_patterns_deploy
      vars:
        deploy_tekton_pipelines: true
        tekton_namespace: openshift-pipelines

    - name: Validate CI/CD deployment
      include_role:
        name: validated_patterns_validate
      vars:
        validate_gitops: true
        validate_tekton: true
```

**Tekton Pipelines:**
1. `deployment-validation-pipeline` (existing)
2. `model-serving-validation-pipeline` (existing)
3. `s3-configuration-pipeline` (existing)

**Tekton Triggers:** `tekton/triggers/github-webhook-trigger.yaml`
```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-webhook-listener
  namespace: openshift-pipelines
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
    - name: github-push-trigger
      interceptors:
        - ref:
            name: github
          params:
            - name: eventTypes
              value: ["push", "pull_request"]
      bindings:
        - ref: github-push-binding
      template:
        ref: cicd-pipeline-template
```

**Validation Script:** `scripts/validate-cicd-pipelines.sh`
- ✅ Created
- Tests: ArgoCD installation, applications, Tekton pipelines, tasks, triggers, recent runs, sync policies, observability, RBAC

**Deployment Command:**
```bash
# Deploy CI/CD infrastructure
ansible-playbook ansible/playbooks/deploy_cicd_pipelines.yml

# Configure GitHub webhook
oc create secret generic github-webhook-secret \
  -n openshift-pipelines \
  --from-literal=secretToken=$(openssl rand -hex 20)

# Deploy triggers
oc apply -f tekton/triggers/github-webhook-trigger.yaml

# Validate deployment
./scripts/validate-cicd-pipelines.sh --verbose
```

**Related Documentation:**
- [OpenShift Pipelines Documentation](https://docs.openshift.com/pipelines/latest/index.html)
- [OpenShift GitOps Documentation](https://docs.openshift.com/gitops/latest/index.html)

---

### ADR-028: Multi-Cluster Deployment Strategy (To Be Created)

**Status:** 🟡 ADR Pending, Implementation Planned

**Ansible Role:** `validated_patterns_operator`

**Playbook:** `ansible/playbooks/deploy_multi_cluster.yml` (to be created)
```yaml
---
- name: Deploy Multi-Cluster with Advanced Cluster Management
  hosts: localhost
  gather_facts: false

  roles:
    - role: validated_patterns_operator
      vars:
        acm_enabled: true
        hub_cluster: true
        spoke_clusters:
          - name: edge-cluster-1
            location: us-east-1
            labels:
              environment: production
              region: east
          - name: edge-cluster-2
            location: us-west-2
            labels:
              environment: production
              region: west
```

**Tekton Pipeline:** `tekton/pipelines/multi-cluster-validation.yaml` (to be created)

**Validation Script:** `scripts/validate-acm-integration.sh` (to be created)

**Deployment Command:**
```bash
# Deploy ACM
ansible-playbook ansible/playbooks/deploy_multi_cluster.yml \
  -e acm_enabled=true

# Validate multi-cluster
./scripts/validate-acm-integration.sh
```

**Related ADR:** ADR-022 (Multi-Cluster Support ACM Integration)

---

### ADR-029: Disaster Recovery and Backup Automation (To Be Created)

**Status:** 🟡 ADR Pending, Implementation Planned

**Ansible Role:** `validated_patterns_deploy`

**Playbook:** `ansible/playbooks/deploy_disaster_recovery.yml` (to be created)
```yaml
---
- name: Deploy Disaster Recovery with OADP
  hosts: localhost
  gather_facts: false

  roles:
    - role: validated_patterns_deploy
      vars:
        deploy_oadp: true
        backup_schedule: "0 2 * * *"  # Daily at 2 AM
        backup_retention: 30d
        backup_locations:
          - s3://backup-bucket/openshift-aiops
        restore_testing_enabled: true
```

**Tekton Pipeline:** `tekton/pipelines/backup-validation-pipeline.yaml` (to be created)

**Validation Script:** `scripts/validate-backup-restore.sh` (to be created)

**Deployment Command:**
```bash
# Deploy disaster recovery
ansible-playbook ansible/playbooks/deploy_disaster_recovery.yml

# Validate backup
./scripts/validate-backup-restore.sh

# Test restore
tkn pipeline start backup-validation-pipeline -n openshift-pipelines
```

---

### ADR-030: Observability and Monitoring Automation (To Be Created)

**Status:** 🟡 ADR Pending, Implementation Planned

**Ansible Role:** `validated_patterns_validate`

**Playbook:** `ansible/playbooks/deploy_observability.yml` (to be created)
```yaml
---
- name: Deploy Observability Stack
  hosts: localhost
  gather_facts: false

  roles:
    - role: validated_patterns_validate
      vars:
        deploy_prometheus: true
        deploy_grafana: true
        deploy_alertmanager: true
        deploy_loki: true
        monitoring_namespace: openshift-monitoring
```

**Tekton Pipeline:** `tekton/pipelines/monitoring-validation-pipeline.yaml` (to be created)

**Validation Script:** `scripts/validate-observability.sh` (to be created)

**Deployment Command:**
```bash
# Deploy observability
ansible-playbook ansible/playbooks/deploy_observability.yml

# Validate monitoring
./scripts/validate-observability.sh
```

---

## Existing ADR Mappings (Reference)

### ADR-001: OpenShift Platform Selection

**Ansible Role:** `validated_patterns_prerequisites`

**Usage:**
```yaml
- name: Validate OpenShift cluster
  include_role:
    name: validated_patterns_prerequisites
  vars:
    min_openshift_version: "4.18"
```

---

### ADR-019: Validated Patterns Framework Adoption

**Ansible Role:** `validated_patterns_common`

**Usage:**
```yaml
- name: Deploy Validated Patterns infrastructure
  include_role:
    name: validated_patterns_common
  vars:
    gitops_enabled: true
```

---

### ADR-020: Bootstrap Deployment Lifecycle

**Ansible Role:** `validated_patterns_operator`

**Usage:**
```yaml
- name: Deploy via Validated Patterns Operator
  include_role:
    name: validated_patterns_operator
  vars:
    pattern_name: self-healing-platform
```

---

### ADR-021: Tekton Pipeline Deployment Validation

**Ansible Role:** `validated_patterns_validate`

**Tekton Pipeline:** `deployment-validation-pipeline`

**Usage:**
```bash
# Run validation pipeline
tkn pipeline start deployment-validation-pipeline \
  -p namespace=self-healing-platform \
  -n openshift-pipelines \
  --showlog
```

---

### ADR-023: Tekton Configuration Pipeline

**Ansible Role:** `validated_patterns_deploy`

**Tekton Pipeline:** `s3-configuration-pipeline`

**Usage:**
```bash
# Run S3 configuration
tkn pipeline start s3-configuration-pipeline \
  -p namespace=self-healing-platform \
  -n openshift-pipelines \
  --showlog
```

---

### ADR-024: External Secrets Model Storage

**Ansible Role:** `validated_patterns_secrets`

**Usage:**
```yaml
- name: Deploy External Secrets for model storage
  include_role:
    name: validated_patterns_secrets
  vars:
    secrets_backend: external-secrets
```

---

## Quick Reference Commands

### Deploy All Automation
```bash
# 1. Validate cluster prerequisites
ansible-playbook ansible/playbooks/validate_cluster.yml

# 2. Deploy GitOps infrastructure
ansible-playbook ansible/playbooks/deploy_gitops.yml

# 3. Deploy secrets management
ansible-playbook ansible/playbooks/deploy_secrets_management.yml

# 4. Deploy CI/CD pipelines
ansible-playbook ansible/playbooks/deploy_cicd_pipelines.yml

# 5. Deploy pattern
ansible-playbook ansible/playbooks/deploy_pattern.yml

# 6. Validate deployment
ansible-playbook ansible/playbooks/validate_deployment.yml
```

### Validate All Components
```bash
# Validate secrets compliance
./scripts/validate-secrets-compliance.sh --compliance-standard pci-dss

# Validate CI/CD pipelines
./scripts/validate-cicd-pipelines.sh --verbose

# Run Tekton validation
tkn pipeline start deployment-validation-pipeline -n openshift-pipelines --showlog
```

---

## Implementation Priority

### Phase 1: Critical (Weeks 1-2)
- ✅ ADR-026: Secrets Management Automation
- Deploy External Secrets Operator
- Implement automated rotation
- Validate compliance

### Phase 2: High Priority (Weeks 3-4)
- ✅ ADR-027: CI/CD Pipeline Automation
- Deploy webhook triggers
- Automate ArgoCD sync
- Enable observability

### Phase 3: Medium Priority (Weeks 5-8)
- ADR-028: Multi-Cluster Deployment
- ADR-029: Disaster Recovery
- ADR-030: Observability Automation

---

## Related Documentation

- [Validated Patterns Ansible Toolkit](https://github.com/tosin2013/validated-patterns-ansible-toolkit)
- [Validated Patterns Onboarding Guide](https://github.com/tosin2013/validated-patterns-ansible-toolkit/blob/main/ONBOARDING.md)
- [ADR Development Rules](../adrs/ADR-DEVELOPMENT-RULES.md)
- [Architectural Analysis Report](../../ARCHITECTURAL-ANALYSIS-AND-ADR-AUTOMATION-REPORT.md)

---

**Last Updated:** 2025-11-02
**Maintained By:** Architecture Team
