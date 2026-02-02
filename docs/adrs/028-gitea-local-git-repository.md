# ADR-028: Gitea Local Git Repository for Air-Gapped Environments

**Status:** Accepted
**Date:** 2025-11-02
**Decision Makers:** Architecture Team
**Technical Story:** Deploy Gitea as local Git repository for air-gapped and disconnected OpenShift environments

---

## Context and Problem Statement

The OpenShift AIOps Platform requires a reliable Git repository for GitOps workflows, pattern deployment, and CI/CD automation. In air-gapped, disconnected, or restricted network environments, external Git services (GitHub, GitLab) may not be accessible. We need a local, self-hosted Git solution that:

1. Provides full Git functionality for GitOps workflows
2. Integrates seamlessly with ArgoCD and Tekton pipelines
3. Supports user authentication and access control
4. Operates reliably in disconnected environments
5. Aligns with validated-patterns framework requirements

**Current State:**
- External GitHub repository: `https://github.com/KubeHeal/openshift-aiops-platform.git`
- ArgoCD configured to sync from external GitHub
- No local Git repository for air-gapped scenarios
- Manual repository mirroring required for disconnected environments

**Desired State:**
- Local Gitea instance deployed on OpenShift
- Automated repository mirroring from external sources
- ArgoCD configured to use local Gitea
- Tekton pipelines integrated with Gitea webhooks
- Validated-patterns framework using local Git

---

## Decision Drivers

1. **Air-Gapped Support**: Enable GitOps in disconnected environments
2. **GitOps Reliability**: Reduce dependency on external services
3. **Validated Patterns Compliance**: Align with `validated_patterns_gitea` role
4. **Developer Experience**: Provide familiar Git interface
5. **Automation**: Support webhook-driven CI/CD pipelines
6. **Security**: Keep sensitive code within cluster boundaries

---

## Considered Options

### Option 1: Gitea (SELECTED)
**Pros:**
- Lightweight and fast (written in Go)
- Native Kubernetes/OpenShift deployment
- Full Git functionality with web UI
- Webhook support for CI/CD integration
- Validated-patterns-ansible-toolkit has dedicated role
- Active community and Red Hat support via RHPDS operator

**Cons:**
- Additional operational overhead
- Requires persistent storage
- Manual repository mirroring setup

### Option 2: GitLab CE
**Pros:**
- Comprehensive DevOps platform
- Built-in CI/CD capabilities
- Advanced user management

**Cons:**
- Heavy resource requirements (4GB+ RAM)
- Complex deployment and configuration
- Overlaps with existing Tekton/ArgoCD
- No validated-patterns role

### Option 3: Gogs
**Pros:**
- Very lightweight
- Simple deployment

**Cons:**
- Less active development
- Limited enterprise features
- No validated-patterns integration
- Smaller community

### Option 4: Continue with External GitHub
**Pros:**
- No additional infrastructure
- Managed service

**Cons:**
- Not suitable for air-gapped environments
- External dependency
- Potential compliance issues
- Network latency

---

## Decision Outcome

**Chosen Option:** Gitea with RHPDS Operator

We will deploy Gitea using the Red Hat RHPDS Gitea Operator for the following reasons:

1. **Validated Patterns Integration**: The `validated_patterns_gitea` Ansible role provides production-ready deployment automation
2. **Air-Gapped Support**: Enables full GitOps functionality in disconnected environments
3. **Resource Efficiency**: Lightweight footprint suitable for edge deployments
4. **OpenShift Native**: Deployed as Kubernetes-native application with operator lifecycle management
5. **Webhook Support**: Native integration with Tekton EventListeners for automated CI/CD
6. **Security**: Keeps sensitive code and configurations within cluster boundaries

---

## Implementation Details

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenShift Cluster                         │
│                                                              │
│  ┌──────────────┐         ┌──────────────┐                 │
│  │   Gitea      │◄────────│   ArgoCD     │                 │
│  │  (Local Git) │         │  (GitOps)    │                 │
│  └──────┬───────┘         └──────────────┘                 │
│         │                                                    │
│         │ Webhooks                                          │
│         ▼                                                    │
│  ┌──────────────┐         ┌──────────────┐                 │
│  │   Tekton     │         │  Developers  │                 │
│  │  (CI/CD)     │         │  (Git Push)  │                 │
│  └──────────────┘         └──────────────┘                 │
│                                                              │
│  ┌──────────────────────────────────────┐                  │
│  │  PostgreSQL (Gitea Database)         │                  │
│  └──────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### Deployment Configuration

**Namespace:** `gitea`

**Components:**
1. **Gitea Operator** (RHPDS): Manages Gitea lifecycle
2. **Gitea Application**: Git server with web UI
3. **PostgreSQL Database**: Gitea metadata storage
4. **Persistent Volumes**: Git repository storage

**Resource Requirements:**
- Gitea: 512Mi memory, 0.5 CPU
- PostgreSQL: 512Mi memory, 0.5 CPU
- Storage: 10Gi PVC for repositories

**Admin Credentials:**
- Username: `opentlc-mgr`
- Password: Auto-generated (32 characters)
- Email: `opentlc-mgr@redhat.com`

**User Configuration:**
- Format: `lab-user`
- Count: 1 user
- Password Length: 16 characters

---

## Ansible Automation

### Validated Patterns Role

**Role:** `validated_patterns_gitea`

**Playbook:** `ansible/playbooks/deploy_gitea.yml`

```yaml
---
- name: Deploy Gitea Local Git Repository
  hosts: localhost
  gather_facts: false

  roles:
    - role: validated_patterns_gitea
      vars:
        gitea_namespace: gitea
        gitea_admin_user: opentlc-mgr
        gitea_admin_email: opentlc-mgr@redhat.com
        gitea_admin_password_length: 32
        gitea_ssl_enabled: true
        gitea_create_users: true
        gitea_user_format: lab-user
        gitea_user_count: 1
        gitea_user_password_length: 16
```

### Repository Mirroring Playbook

**Playbook:** `ansible/playbooks/mirror_repositories.yml`

```yaml
---
- name: Mirror External Repositories to Gitea
  hosts: localhost
  gather_facts: false

  vars:
    gitea_url: "https://gitea-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com"
    gitea_admin_user: opentlc-mgr
    external_repos:
      - name: openshift-aiops-platform
        url: https://github.com/KubeHeal/openshift-aiops-platform.git
        private: false
      - name: validated-patterns-ansible-toolkit
        url: https://github.com/tosin2013/validated-patterns-ansible-toolkit.git
        private: false

  tasks:
    - name: Get Gitea admin password
      kubernetes.core.k8s_info:
        api_version: v1
        kind: Secret
        name: gitea-with-admin-admin-credentials
        namespace: gitea
      register: gitea_secret

    - name: Create organizations in Gitea
      uri:
        url: "{{ gitea_url }}/api/v1/orgs"
        method: POST
        user: "{{ gitea_admin_user }}"
        password: "{{ gitea_secret.resources[0].data.password | b64decode }}"
        force_basic_auth: yes
        body_format: json
        body:
          username: validated-patterns
          full_name: Validated Patterns
        status_code: [201, 422]  # 422 if already exists

    - name: Mirror repositories to Gitea
      uri:
        url: "{{ gitea_url }}/api/v1/repos/migrate"
        method: POST
        user: "{{ gitea_admin_user }}"
        password: "{{ gitea_secret.resources[0].data.password | b64decode }}"
        force_basic_auth: yes
        body_format: json
        body:
          clone_addr: "{{ item.url }}"
          repo_name: "{{ item.name }}"
          mirror: true
          private: "{{ item.private }}"
          uid: 1
        status_code: [201, 409]  # 409 if already exists
      loop: "{{ external_repos }}"
```

---

## ArgoCD Integration

### Update ArgoCD Application to Use Gitea

**File:** `values-hub.yaml`

```yaml
applications:
  coordination-engine:
    name: coordination-engine
    namespace: self-healing-platform
    project: default
    source:
      repoURL: https://gitea-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/validated-patterns/openshift-aiops-platform.git
      targetRevision: main
      path: charts/coordination-engine
    destination:
      server: https://kubernetes.default.svc
      namespace: self-healing-platform
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
```

### ArgoCD Repository Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitea-repo-secret
  namespace: openshift-gitops
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://gitea-gitea.apps.cluster-fn2qb.fn2qb.sandbox1343.opentlc.com/validated-patterns/openshift-aiops-platform.git
  username: opentlc-mgr
  password: <gitea-admin-password>
```

---

## Tekton Integration

### Gitea Webhook Configuration

**EventListener:** `tekton/triggers/gitea-webhook-trigger.yaml`

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: gitea-webhook-listener
  namespace: openshift-pipelines
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
    - name: gitea-push-trigger
      interceptors:
        - ref:
            name: gitea
          params:
            - name: eventTypes
              value: ["push"]
            - name: secretRef
              value:
                secretName: gitea-webhook-secret
                secretKey: secretToken
      bindings:
        - ref: gitea-push-binding
      template:
        ref: cicd-pipeline-template
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: gitea-push-binding
  namespace: openshift-pipelines
spec:
  params:
    - name: gitrevision
      value: $(body.after)
    - name: gitrepositoryurl
      value: $(body.repository.clone_url)
    - name: gitrepositoryname
      value: $(body.repository.name)
```

---

## Validation and Testing

### Validation Script

**File:** `scripts/validate-gitea-deployment.sh`

```bash
#!/bin/bash
# Validate Gitea deployment and integration

set -e

GITEA_NAMESPACE=${GITEA_NAMESPACE:-gitea}
GITEA_ROUTE=$(oc get route gitea -n $GITEA_NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

echo "Validating Gitea Deployment..."

# Test 1: Gitea pods running
if oc get pods -n $GITEA_NAMESPACE | grep -q "Running"; then
    echo "✅ Gitea pods are running"
else
    echo "❌ Gitea pods not running"
    exit 1
fi

# Test 2: Gitea route accessible
if [ -n "$GITEA_ROUTE" ]; then
    echo "✅ Gitea route: https://$GITEA_ROUTE"
else
    echo "❌ Gitea route not found"
    exit 1
fi

# Test 3: Gitea API accessible
if curl -k -s "https://$GITEA_ROUTE/api/v1/version" | grep -q "version"; then
    echo "✅ Gitea API is accessible"
else
    echo "❌ Gitea API not accessible"
    exit 1
fi

# Test 4: Admin credentials exist
if oc get secret gitea-with-admin-admin-credentials -n $GITEA_NAMESPACE &>/dev/null; then
    echo "✅ Admin credentials secret exists"
else
    echo "❌ Admin credentials not found"
    exit 1
fi

echo "✅ All Gitea validation checks passed"
```

---

## Migration Strategy

### Phase 1: Deployment (Week 1)
1. ✅ Deploy Gitea operator
2. ✅ Create Gitea instance
3. Validate deployment
4. Extract admin credentials

### Phase 2: Repository Mirroring (Week 1)
1. Mirror openshift-aiops-platform repository
2. Mirror validated-patterns-ansible-toolkit
3. Configure automatic sync
4. Validate repository access

### Phase 3: ArgoCD Integration (Week 2)
1. Create ArgoCD repository secret
2. Update application manifests
3. Test ArgoCD sync from Gitea
4. Validate automated sync

### Phase 4: Tekton Integration (Week 2)
1. Deploy Gitea webhook EventListener
2. Configure webhook in Gitea
3. Test webhook-triggered pipelines
4. Validate end-to-end CI/CD

---

## Consequences

### Positive

1. **Air-Gapped Support**: Full GitOps functionality in disconnected environments
2. **Reduced External Dependencies**: No reliance on external Git services
3. **Improved Security**: Sensitive code stays within cluster boundaries
4. **Validated Patterns Compliance**: Uses official `validated_patterns_gitea` role
5. **Developer Familiarity**: Standard Git interface and workflows
6. **Webhook Integration**: Native support for Tekton CI/CD automation

### Negative

1. **Operational Overhead**: Additional component to manage and monitor
2. **Storage Requirements**: Requires persistent storage for repositories
3. **Manual Mirroring**: Initial repository mirroring requires manual setup
4. **Backup Responsibility**: Must implement backup strategy for Git data

### Neutral

1. **Resource Usage**: Minimal impact (1GB memory, 1 CPU total)
2. **Learning Curve**: Developers familiar with Git will adapt quickly
3. **Migration Effort**: One-time effort to update ArgoCD configurations

---

## Compliance and Standards

- **Validated Patterns Framework**: Uses `validated_patterns_gitea` role
- **OpenShift Best Practices**: Deployed via operator with proper RBAC
- **GitOps Principles**: Supports declarative configuration management
- **Security**: SSL/TLS enabled, credential management via secrets

---

## Related ADRs

- **ADR-019**: Validated Patterns Framework Adoption
- **ADR-027**: CI/CD Pipeline Automation with Tekton and ArgoCD
- **ADR-026**: Secrets Management Automation (for Gitea credentials)

---

## References

- [Gitea Documentation](https://docs.gitea.io/)
- [RHPDS Gitea Operator](https://github.com/rhpds/gitea-operator)
- [Validated Patterns Gitea Role](https://github.com/tosin2013/validated-patterns-ansible-toolkit/tree/main/ansible/roles/validated_patterns_gitea)
- [ArgoCD Private Repositories](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/)
- [Tekton Gitea Integration](https://tekton.dev/docs/triggers/eventlisteners/)

---

**Last Updated:** 2025-11-02
**Review Date:** 2025-12-02
**Status:** Accepted - Deployment in progress
