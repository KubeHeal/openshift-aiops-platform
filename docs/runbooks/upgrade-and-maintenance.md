# Runbook: Platform Upgrade and Maintenance

**Owner**: Platform Engineering Team
**Risk Level**: High
**Last Updated**: 2026-09-29
**Last Tested**: 2026-09-29
**Approved By**: Platform Architect
**Version**: 1.0.0

---

## Quick Reference

| Attribute | Value |
|-----------|-------|
| **Execution Time** | 30-120 minutes (varies by upgrade scope) |
| **Impact Window** | Rolling upgrades: minimal downtime. Major versions: 5-15 min window. |
| **Rollback Time** | ~30 minutes for operator rollback. Cluster rollback is not supported. |
| **Prerequisites** | Cluster-admin access, tested upgrade path, current backups |

---

## Scope and Use Case

### When to Use This Runbook

Use this runbook for planned maintenance activities: OpenShift version upgrades, operator version upgrades, Helm chart updates, certificate renewal, and backup/restore operations.

**Triggers**:
- Scheduled maintenance window
- New OpenShift minor or patch version available
- Operator update required (security fix, feature addition)
- Certificate expiration approaching

### Expected Outcome

Platform components upgraded to target versions with all functionality validated and zero or minimal downtime.

### What This Does NOT Cover

- Emergency incident response (see [incident-response.md](incident-response.md))
- Initial platform deployment (see [platform-deployment.md](platform-deployment.md))
- Model retraining procedures (see [model-training-operations.md](model-training-operations.md))

---

## Prerequisites

### Required Access and Permissions

- [ ] `oc` CLI logged in with cluster-admin
- [ ] For ROSA: `rosa` CLI logged in
- [ ] Repository write access to push updated configurations
- [ ] Maintenance window approved

### Required Tools

- [ ] `oc` 4.20+ (OpenShift CLI)
- [ ] `helm` 3.16.4+
- [ ] `yq` 4.44.6+
- [ ] `jq` 1.6+
- [ ] `git` 2.40+

### Communication Requirements

- [ ] Notify stakeholders of the maintenance window
- [ ] Post in #aiops-platform Slack channel
- [ ] Create a change management ticket

---

## Procedure 1: OpenShift Version Upgrade

**Estimated Time**: 30-90 minutes per minor version hop

### Pre-Upgrade Assessment

#### Step 1: Check Current Version

```bash
oc get clusterversion
oc version
```

#### Step 2: Review Available Updates

```bash
oc adm upgrade
```

#### Step 3: Run Automated Upgrade Script (Dry Run)

The platform includes an automated upgrade script with safety checks and multi-hop support:

```bash
./scripts/upgrade-cluster.sh --target-ocp 4.22 --dry-run
```

Review the output. The script will display:
- Current version and target version
- Required upgrade hops (if multi-hop)
- Pre-flight health check results
- Commands that would be executed

#### Step 4: Verify Pre-Flight Checks

```bash
oc get clusteroperators | grep -v "True.*False.*False"
oc get nodes
oc adm top nodes
```

All cluster operators should show `Available=True`, `Progressing=False`, `Degraded=False`. All nodes should be `Ready`.

### Execute Upgrade

#### Step 5: Run Upgrade

```bash
./scripts/upgrade-cluster.sh --target-ocp 4.22 --execute
```

The script handles:
- Multi-hop upgrades (4.20 to 4.21 to 4.22)
- Health gates between hops
- SNO-specific retry logic for API unavailability during node reboot
- Repository configuration file updates

For manual control, upgrade one hop at a time:

```bash
oc adm upgrade --to=4.21.latest
```

Monitor progress:

```bash
oc get clusterversion --watch
```

#### Step 6: Wait for Completion

```bash
oc wait --for=condition=Available clusterversion/version --timeout=90m
```

For SNO clusters, the node will reboot. The API may be unavailable for 5-15 minutes.

### Post-Upgrade Validation

#### Step 7: Verify Cluster Health

```bash
oc get clusterversion
oc get clusteroperators
oc get nodes
```

All operators should return to `Available=True`.

#### Step 8: Verify Platform Health

```bash
make argo-healthcheck
oc get pods -n self-healing-platform
oc get inferenceservices -n self-healing-platform
```

#### Step 9: Update Repository Configuration

If not using `--execute` with the upgrade script, update repository files manually:

```bash
yq -i '.cluster.version = "4.22"' charts/hub/values.yaml
git add charts/hub/values.yaml
git commit -s -m "chore: update cluster version to 4.22"
git push origin main
```

---

## Procedure 2: Operator Upgrade

**Estimated Time**: 10-30 minutes per operator

### Supported Operators

| Operator | Current Channel | Update Strategy |
|----------|----------------|-----------------|
| Red Hat OpenShift AI | stable-2.22 | Automatic (OLM) |
| GPU Operator | v24.9 | Automatic (OLM) |
| OpenShift Pipelines | latest | Automatic (OLM) |
| OpenShift GitOps | latest | Automatic (OLM) |
| External Secrets Operator | stable | Automatic (OLM) |

### Step 1: Check Current Operator Versions

```bash
oc get csv -n openshift-operators -o custom-columns=NAME:.metadata.name,VERSION:.spec.version,PHASE:.status.phase
```

### Step 2: Check Available Updates

```bash
oc get subscriptions -n openshift-operators -o custom-columns=NAME:.metadata.name,CHANNEL:.spec.channel,APPROVAL:.spec.installPlanApproval
```

### Step 3: Upgrade RHOAI (Automated)

The upgrade script supports RHOAI upgrades:

```bash
./scripts/upgrade-cluster.sh --skip-ocp --target-rhoai stable-2.23 --execute
```

Or manually update the subscription channel:

```bash
oc patch subscription rhods-operator -n openshift-operators \
  --type merge -p '{"spec":{"channel":"stable-2.23"}}'
```

### Step 4: Approve InstallPlan (if manual approval)

```bash
oc get installplan -n openshift-operators
oc patch installplan <NAME> -n openshift-operators \
  --type merge -p '{"spec":{"approved":true}}'
```

### Step 5: Wait for Upgrade

```bash
oc get csv -n openshift-operators --watch
```

Wait for the new CSV to reach `Succeeded` phase.

### Step 6: Verify Operator Health

```bash
oc get csv -n openshift-operators -o custom-columns=NAME:.metadata.name,PHASE:.status.phase | grep -v Succeeded
```

This command should return no results (all operators in `Succeeded` phase).

> **WARNING**: After upgrading OpenShift AI, KServe InferenceServices may need to be restarted. Monitor model serving pods for 10 minutes after upgrade.

---

## Procedure 3: Helm Chart Update and ArgoCD Sync

**Estimated Time**: 10-15 minutes

### Step 1: Review Changes

Before updating chart values, review the diff:

```bash
git diff charts/hub/values.yaml
git diff charts/hub/templates/
```

### Step 2: Validate Helm Template Locally

```bash
helm template test charts/hub -f values-global.yaml -f values-hub.yaml > /dev/null
```

If this command fails, fix template errors before proceeding.

### Step 3: Commit and Push Changes

```bash
git add charts/hub/
git commit -s -m "chore(helm): update chart values for <reason>"
git push origin main
```

### Step 4: Trigger ArgoCD Sync

ArgoCD will auto-sync if configured. To force an immediate sync:

```bash
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite
```

### Step 5: Monitor Sync

```bash
watch -n 5 'oc get application self-healing-platform -n self-healing-platform-hub \
  -o jsonpath="{.status.sync.status} - {.status.health.status}"'
```

**Success criteria**: `Synced - Healthy`.

---

## Procedure 4: Certificate Renewal

**Estimated Time**: 10-20 minutes

### Step 1: Check Certificate Expiration

```bash
oc get secrets -n openshift-ingress -o json | \
  jq -r '.items[] | select(.type=="kubernetes.io/tls") | .metadata.name'
```

For each TLS secret:

```bash
oc get secret <SECRET_NAME> -n openshift-ingress -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates
```

### Step 2: Check API Server Certificate

```bash
echo | openssl s_client -connect api.$(oc get dns cluster -o jsonpath='{.spec.baseDomain}'):6443 2>/dev/null | \
  openssl x509 -noout -dates
```

### Step 3: Renew Certificates

OpenShift manages most certificates automatically. For custom certificates:

```bash
oc create secret tls <SECRET_NAME> \
  --cert=new-cert.pem \
  --key=new-key.pem \
  -n <NAMESPACE> \
  --dry-run=client -o yaml | oc apply -f -
```

### Step 4: Verify Renewal

```bash
oc get secret <SECRET_NAME> -n <NAMESPACE> -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates
```

---

## Procedure 5: Backup and Restore

**Estimated Time**: 15-45 minutes

### What to Back Up

| Component | Location | Method |
|-----------|----------|--------|
| Platform configuration | Git repository | Git push (already backed up) |
| Values files | Local filesystem | `cp values-*.yaml backup/` |
| Model artifacts | S3/NooBaa bucket | S3 copy or PVC snapshot |
| Jupyter notebooks | PVC: workbench-data | PVC snapshot |
| Secrets | Kubernetes secrets | ExternalSecret backend |

### Backup Model Artifacts

#### From PVC

```bash
oc exec -it self-healing-workbench-0 -n self-healing-platform -- \
  tar czf /tmp/models-backup.tar.gz /opt/app-root/src/models/

oc cp self-healing-platform/self-healing-workbench-0:/tmp/models-backup.tar.gz \
  ./models-backup-$(date +%Y%m%d).tar.gz
```

#### From S3 (AWS)

```bash
aws s3 sync s3://<BUCKET_NAME>/models/ ./backup/models/ --region us-east-1
```

### Backup Workbench Data

```bash
oc exec -it self-healing-workbench-0 -n self-healing-platform -- \
  tar czf /tmp/workbench-backup.tar.gz /opt/app-root/src/data/

oc cp self-healing-platform/self-healing-workbench-0:/tmp/workbench-backup.tar.gz \
  ./workbench-backup-$(date +%Y%m%d).tar.gz
```

### Restore Model Artifacts

```bash
oc cp ./models-backup-YYYYMMDD.tar.gz \
  self-healing-platform/self-healing-workbench-0:/tmp/models-backup.tar.gz

oc exec -it self-healing-workbench-0 -n self-healing-platform -- \
  tar xzf /tmp/models-backup.tar.gz -C /
```

Restart InferenceServices to pick up restored models:

```bash
oc rollout restart deployment -n self-healing-platform \
  -l serving.kserve.io/inferenceservice
```

### Restore from Full Platform Redeployment

If the platform must be rebuilt from scratch:

1. Follow the [Platform Deployment](platform-deployment.md) runbook.
2. Restore model artifacts using the procedure above.
3. Retrain models if no backup is available:

```bash
./scripts/trigger-model-training.sh anomaly-detector 168 prometheus
./scripts/trigger-model-training.sh predictive-analytics 720 prometheus
```

---

## Procedure 6: Periodic Maintenance Tasks

### Weekly Tasks

- [ ] Review model training pipeline results:

```bash
./scripts/check-training-status.sh
```

- [ ] Check for failed CronJobs:

```bash
oc get cronjobs -n self-healing-platform -o custom-columns=NAME:.metadata.name,LAST:.status.lastScheduleTime,ACTIVE:.status.active
```

### Monthly Tasks

- [ ] Review Prometheus storage utilization:

```bash
oc exec -n openshift-monitoring prometheus-k8s-0 -- \
  df -h /prometheus
```

- [ ] Check PVC utilization:

```bash
oc get pvc -n self-healing-platform -o custom-columns=NAME:.metadata.name,CAPACITY:.status.capacity.storage
```

- [ ] Review and clean up completed PipelineRuns:

```bash
tkn pipelinerun list -n self-healing-platform --limit 50
tkn pipelinerun delete -n self-healing-platform --keep 10
```

### Quarterly Tasks

- [ ] Run the full Tekton validation pipeline:

```bash
tkn pipeline start deployment-validation-pipeline --showlog -n self-healing-platform
```

- [ ] Review and update operator channels for new versions
- [ ] Test backup and restore procedures
- [ ] Review and update this runbook

---

## Rollback Procedure

### Operator Rollback

OpenShift operators can be rolled back by switching to a previous channel or version:

```bash
oc patch subscription rhods-operator -n openshift-operators \
  --type merge -p '{"spec":{"channel":"stable-2.22"}}'
```

> **WARNING**: Operator rollbacks may leave CRDs in an inconsistent state. Test in a non-production environment first.

### Helm Chart Rollback

Revert the Git commit and trigger ArgoCD sync:

```bash
git revert HEAD
git push origin main
oc annotate application self-healing-platform -n self-healing-platform-hub \
  argocd.argoproj.io/refresh=hard --overwrite
```

### Cluster Version Rollback

> **WARNING**: OpenShift cluster version rollbacks are NOT supported. Plan upgrades carefully and test in staging first.

---

## Troubleshooting

### Issue 1: Upgrade Stuck in Progressing

**Symptoms**: `oc get clusterversion` shows `Progressing=True` for more than 60 minutes.

**Diagnosis**:

```bash
oc get clusterversion -o jsonpath='{.items[0].status.conditions}' | jq
oc get clusteroperators | grep -v "True.*False.*False"
```

**Solution**: Identify the degraded operator and check its logs. For SNO, the API may be unreachable during node reboot. Wait up to 30 minutes.

### Issue 2: Operator Upgrade Breaks InferenceServices

**Symptoms**: InferenceServices become `NotReady` after KServe/RHOAI upgrade.

**Solution**:

```bash
oc rollout restart deployment -n self-healing-platform \
  -l serving.kserve.io/inferenceservice
```

If predictor pods fail to start with new runtime version, check runtime compatibility:

```bash
oc get servingruntime -n self-healing-platform -o yaml
```

---

## Escalation Path

| Severity | First Contact | Response Time | Next Escalation |
|----------|---------------|---------------|-----------------|
| **P1 (Critical)** | On-call engineer | Immediate | Engineering Manager (15 min) |
| **P2 (High)** | Team Slack #aiops-platform | 30 minutes | Team Lead (1 hour) |
| **P3 (Medium)** | Team Slack #aiops-platform | 2 hours | N/A |

---

## Appendix

### Related Runbooks

- [Platform Deployment](platform-deployment.md)
- [Incident Response](incident-response.md)
- [Model Training Operations](model-training-operations.md)
- [Monitoring and Alerting](monitoring-and-alerting.md)

### Reference Documentation

- Upgrade script: `scripts/upgrade-cluster.sh`
- Cluster configuration script: `scripts/configure-cluster-infrastructure.sh`
- [ADR-055: Multi-Cluster Topology Support](../adrs/055-openshift-420-multi-cluster-topology-support.md)
- [ADR-062: ROSA as Primary Deployment Target](../adrs/062-rosa-primary-deployment-target.md)

### Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-29 | Platform Engineering | Initial version |

---

**Last Reviewed**: 2026-09-29
**Next Review**: 2026-12-29
**Feedback**: Report issues at https://github.com/KubeHeal/openshift-aiops-platform/issues
