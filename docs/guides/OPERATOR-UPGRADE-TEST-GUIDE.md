# Jupyter Notebook Validator Operator Upgrade - Test Guide

**Date:** 2025-12-01
**Operator Version:** v1.0.2 → v1.0.4-ocp4.20
**Test Script:** `scripts/test-operator-upgrade.sh`

---

## Quick Start

### Option 1: Full Test (Recommended)

```bash
# Run complete test: pre-flight checks + make install + validation
./scripts/test-operator-upgrade.sh
```

### Option 2: Dry Run (Pre-Flight Checks Only)

```bash
# Check prerequisites without running installation
./scripts/test-operator-upgrade.sh --dry-run
```

### Option 3: Validation Only

```bash
# Skip installation, only validate existing deployment
./scripts/test-operator-upgrade.sh --skip-install
```

### Option 4: Verbose Mode

```bash
# Show detailed output during execution
./scripts/test-operator-upgrade.sh --verbose
```

---

## Test Script Features

### Phase 1: Pre-Flight Checks ✅
- Cluster connectivity verification
- Current operator status check
- Execution environment image validation
- Ansible configuration verification
- Storage prerequisites check
- Required namespaces validation
- Values files verification

### Phase 2: Backup Current State ✅
- Operator subscription backup
- CSV (ClusterServiceVersion) backup
- Deployment configuration backup
- CRD (CustomResourceDefinition) backup
- State summary generation

### Phase 3: Execute Installation ✅
- Runs `make install` (operator-deploy + load-secrets)
- Captures full output to log file
- Monitors exit codes
- Provides verbose mode option

### Phase 4: Post-Installation Validation ✅
- CSV version verification
- Deployment status check
- Pod health validation
- CRD existence verification
- Webhook configuration check
- Operator logs error scanning
- Catalog source validation

### Phase 5: Save Post-Installation State ✅
- Deployment state capture
- CSV state capture
- CRD state capture
- State summary generation

### Phase 6: Generate Test Report ✅
- Comprehensive test report in Markdown
- Status summary table
- Backup location documentation
- Next steps guidance
- Rollback instructions

---

## Test Outputs

### Log Files

**Main Test Log:**
```
operator-upgrade-test-YYYYMMDD-HHMMSS.log
```

**Backup Directory:**
```
backups/operator-upgrade-YYYYMMDD-HHMMSS/
├── state-before.txt              # State before installation
├── state-after.txt               # State after installation
├── subscription-before.yaml      # Subscription backup
├── csv-before.yaml               # CSV backup (if existed)
├── deployment-before.yaml        # Deployment backup (if existed)
├── deployment-after.yaml         # Deployment state after installation
├── csv-after.yaml                # CSV state after installation
├── crd-after.yaml                # CRD state after installation
└── test-report.md                # Comprehensive test report
```

---

## Volume Support Validation

After successful operator upgrade, test volume support:

### Step 1: Apply Test Jobs

```bash
# Create test NotebookValidationJob with PVC mount
oc apply -f tests/test-volume-support.yaml
```

### Step 2: Monitor Job Status

```bash
# Watch job status
oc get notebookvalidationjob -n self-healing-platform -w

# Check pod status
oc get pods -n self-healing-platform -l test=volume-support
```

### Step 3: Verify Volume Mounts

```bash
# Get pod name
POD_NAME=$(oc get pods -n self-healing-platform -l test=volume-support -o jsonpath='{.items[0].metadata.name}')

# Verify mount exists
oc exec -n self-healing-platform ${POD_NAME} -- ls -la /mnt/models

# Check disk usage
oc exec -n self-healing-platform ${POD_NAME} -- df -h /mnt/models

# Test write access
oc exec -n self-healing-platform ${POD_NAME} -- touch /mnt/models/test-file.txt
oc exec -n self-healing-platform ${POD_NAME} -- ls -la /mnt/models/test-file.txt
```

### Step 4: Check Job Logs

```bash
# View job logs
oc logs -n self-healing-platform ${POD_NAME} --tail=100

# Check job status
oc get notebookvalidationjob test-volume-support-v1.0.4 -n self-healing-platform -o yaml
```

### Step 5: Clean Up

```bash
# Delete test jobs
oc delete notebookvalidationjob test-volume-support-v1.0.4 -n self-healing-platform
oc delete notebookvalidationjob test-multi-volume-support -n self-healing-platform
```

---

## Troubleshooting

### Issue: Execution Environment Image Not Found

**Solution:**
```bash
# Build execution environment image
make build-ee

# Verify image exists
podman images | grep openshift-aiops-platform-ee
```

### Issue: Operator Not Upgrading

**Check subscription:**
```bash
oc get subscription jupyter-notebook-validator-operator -n openshift-operators -o yaml
```

**Check install plan:**
```bash
oc get installplan -n openshift-operators
```

**Force upgrade:**
```bash
# Delete subscription and rerun
oc delete subscription jupyter-notebook-validator-operator -n openshift-operators
./scripts/test-operator-upgrade.sh
```

### Issue: Pod Not Starting

**Check pod events:**
```bash
POD_NAME=$(oc get pods -n openshift-operators -l control-plane=controller-manager -o jsonpath='{.items[0].metadata.name}')
oc describe pod ${POD_NAME} -n openshift-operators
```

**Check pod logs:**
```bash
oc logs ${POD_NAME} -n openshift-operators --tail=100
```

### Issue: Volume Mount Fails

**Check PVC exists:**
```bash
oc get pvc model-storage-pvc -n self-healing-platform
```

**Check PVC status:**
```bash
oc describe pvc model-storage-pvc -n self-healing-platform
```

**Check storage class:**
```bash
oc get storageclass
```

---

## Rollback Procedure

If issues are encountered after upgrade:

```bash
# Step 1: Locate backup directory
BACKUP_DIR=$(ls -td backups/operator-upgrade-* | head -1)
echo "Using backup: ${BACKUP_DIR}"

# Step 2: Delete current subscription
oc delete subscription jupyter-notebook-validator-operator -n openshift-operators

# Step 3: Restore previous subscription
oc apply -f ${BACKUP_DIR}/subscription-before.yaml

# Step 4: Wait for operator to redeploy
oc get csv -n openshift-operators | grep jupyter

# Step 5: Verify rollback
oc get deployment notebook-validator-controller-manager -n openshift-operators
```

---

## Success Criteria

### Operator Upgrade Success ✅
- [ ] CSV shows v1.0.4-ocp4.20
- [ ] Deployment ready (1/1 replicas)
- [ ] Pod running and healthy
- [ ] No errors in operator logs
- [ ] CRD updated successfully

### Volume Support Validation ✅
- [ ] Test NotebookValidationJob with PVC mount succeeds
- [ ] `/mnt/models` directory accessible in validation pod
- [ ] Model files can be written to PVC
- [ ] Model files persist after pod deletion
- [ ] Multiple volume mounts work correctly

---

## References

- **Version Research:** `docs/OPERATOR-VERSION-RESEARCH-SUMMARY.md`
- **Upgrade Plan:** `docs/OPERATOR-UPGRADE-AND-VOLUME-IMPLEMENTATION-PLAN.md`
- **Completion Summary:** `docs/OPERATOR-UPGRADE-COMPLETION-SUMMARY.md`
- **Test Script:** `scripts/test-operator-upgrade.sh`
- **Test YAML:** `tests/test-volume-support.yaml`
- **GitHub Repository:** https://github.com/tosin2013/jupyter-notebook-validator-operator
- **Latest Release:** https://github.com/tosin2013/jupyter-notebook-validator-operator/releases/tag/v1.0.4-ocp4.20
