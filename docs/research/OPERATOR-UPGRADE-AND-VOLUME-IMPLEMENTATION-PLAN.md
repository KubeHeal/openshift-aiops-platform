# Jupyter Notebook Validator Operator Upgrade & Volume Support Implementation Plan

**Date:** 2025-12-01
**Status:** Planning Phase
**Goal:** Upgrade to latest Jupyter Notebook Validator Operator version with enhanced volume support and implement PVC-based model storage workflow

---

## Executive Summary

This plan outlines the upgrade path for the Jupyter Notebook Validator Operator to leverage the latest volume support capabilities documented at https://operatorhub.io/operator/jupyter-notebook-validator-operator. The upgrade enables persistent model storage via PVCs, allowing trained models to be shared between notebooks and KServe InferenceServices without S3 dependencies.

### Key Objectives

1. ✅ **Upgrade Operator** - Deploy latest version from OperatorHub.io with volume support
2. ✅ **Update Documentation** - Align implementation plan with operator-deploy workflow
3. ✅ **Verify Infrastructure** - Confirm PVC mounts are correctly configured
4. ✅ **Migrate Notebooks** - Update 40+ notebooks to use PVC storage
5. ✅ **Test Workflow** - Validate end-to-end model training → serving pipeline

---

## Current State Analysis

### ✅ Infrastructure Already Deployed

**Workbench PVC Mount (CONFIRMED):**
```yaml
# charts/hub/templates/ai-ml-workbench.yaml (lines 154-155, 243-245)
volumeMounts:
- name: model-storage
  mountPath: /mnt/models

volumes:
- name: model-storage
  persistentVolumeClaim:
    claimName: model-storage-pvc
```

**Storage Infrastructure:**
- ✅ `model-storage-pvc` (10Gi RWX) - Defined in `charts/hub/templates/storage.yaml`
- ✅ `sklearn-pvc-runtime` - KServe runtime with PVC support
- ✅ `model_storage_helpers.py` - 380-line helper module with PVC functions

**Operator Deployment:**
- **Current Version:** v1.0.2 (from `ansible/roles/validated_patterns_notebooks/tasks/deploy_operator.yml:187`)
- **Latest Version:** **v1.0.4-ocp4.20** (Released: 2025-11-30) ✅ **UPGRADE AVAILABLE**
- **Installation Method:** OLM via OperatorHub.io
- **Namespace:** `openshift-operators` (AllNamespaces mode)
- **Channel:** `alpha`
- **Version Research:** See `docs/OPERATOR-VERSION-RESEARCH-SUMMARY.md` for detailed analysis

### ❌ Gaps Identified

1. **Operator Version:** Need to verify latest version on OperatorHub.io
2. **Notebook Storage:** 40+ notebooks use local storage (`/opt/app-root/src/models`) instead of PVC (`/mnt/models`)
3. **Documentation:** Implementation plan doesn't reflect volume support capabilities
4. **Testing:** No end-to-end validation of model training → PVC → KServe workflow

---

## Phase 1: Operator Upgrade (Week 1)

### Task 1.1: Research Latest Operator Version

**Action:** Query OperatorHub.io for latest Jupyter Notebook Validator Operator version

**Current Configuration:**
```yaml
# ansible/roles/validated_patterns_notebooks/defaults/main.yml
notebooks_operator_channel: "alpha"
notebooks_operator_catalog_source: "operatorhubio-catalog"
notebooks_operatorhubio_catalog_image: "quay.io/operatorhubio/catalog:latest"
```

**Research Questions:**
- What is the latest stable version?
- What new volume support features are available?
- Are there breaking changes from v1.0.2?
- What is the recommended upgrade path?

**Deliverable:** Version comparison matrix and upgrade decision

### Task 1.2: Update Ansible Role Configuration

**Files to Update:**
1. `ansible/roles/validated_patterns_notebooks/defaults/main.yml`
   - Update operator version/channel if needed
   - Add volume support configuration variables

2. `ansible/roles/validated_patterns_notebooks/tasks/deploy_operator.yml`
   - Update version reference (line 187)
   - Add volume support validation checks

**Example Configuration Addition:**
```yaml
# Volume support configuration (NEW)
notebooks_enable_volume_support: true
notebooks_default_pvc_mount_path: "/mnt/models"
notebooks_default_pvc_name: "model-storage-pvc"
```

### Task 1.3: Test Operator Upgrade

**Upgrade Workflow:**
```bash
# Step 1: Backup current operator configuration
oc get subscription jupyter-notebook-validator-operator -n openshift-operators -o yaml > backup-subscription.yaml
oc get csv -n openshift-operators | grep jupyter > backup-csv.txt

# Step 2: Run Ansible upgrade playbook
ansible-playbook ansible/playbooks/operator_deploy_prereqs.yml \
  -e notebooks_operator_enabled=true \
  -e notebooks_upgrade_operator=true

# Step 3: Verify upgrade
oc get csv -n openshift-operators | grep jupyter
oc get deployment notebook-validator-controller-manager -n openshift-operators
```

**Validation Checks:**
- ✅ Operator deployment ready (1/1 replicas)
- ✅ NotebookValidationJob CRD updated
- ✅ Webhook configuration valid
- ✅ Volume support capabilities available

---

## Phase 2: Documentation Updates (Week 1)

### Task 2.1: Update Implementation Plan

**File:** `docs/IMPLEMENTATION-PLAN.md`

**Changes Required:**

1. **Update ADR-029 Status (Line 48)**
   ```markdown
   # BEFORE:
   | **ADR-029** | Jupyter Notebook Validator Operator | ✅ Proposed, 🔴 Implementation Pending |

   # AFTER:
   | **ADR-029** | Jupyter Notebook Validator Operator | ✅ IMPLEMENTED (with PVC volume support) |
   ```

2. **Replace end2end-deployment with operator-deploy (Lines 397, 444-492, 613)**
   ```markdown
   # BEFORE:
   make end2end-deployment

   # AFTER:
   make operator-deploy  # Validated Patterns Framework (ADR-019)
   ```

3. **Deprecate ADR-008 (Line 35)**
   ```markdown
   # BEFORE:
   | **ADR-008** | Kubeflow Pipelines for MLOps | ✅ Available |

   # AFTER:
   | **ADR-008** | Kubeflow Pipelines for MLOps | ⚠️ DEPRECATED | Superseded by ADR-021 (Tekton) + ADR-029 (Notebooks) |
   ```

4. **Add Model Storage Workflow Section (After Line 546)**
   - Document PVC-based storage architecture
   - Add workflow diagram: Training → PVC → KServe
   - Cross-reference ADR-024, ADR-025, ADR-029, ADR-035
   - Document `model_storage_helpers.py` API

### Task 2.2: Update ADR-029

**File:** `docs/adrs/029-jupyter-notebook-validator-operator.md`

**Add Volume Support Examples:**
```yaml
# NotebookValidationJob with PVC mount
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: model-training-with-pvc
spec:
  notebookPath: notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb
  volumes:
    - name: model-storage
      persistentVolumeClaim:
        claimName: model-storage-pvc
  volumeMounts:
    - name: model-storage
      mountPath: /mnt/models
```

---

## Phase 3: Notebook Migration (Week 2-3)

### Task 3.1: Update Tier 1 Notebooks (5 notebooks)

**Target Notebooks:**
- `00-setup/environment-setup.ipynb`
- `00-setup/00-platform-readiness-validation.ipynb`
- `01-data-collection/openshift-events-analysis.ipynb`
- `01-data-collection/synthetic-anomaly-generation.ipynb`

**Migration Pattern:**
```python
# BEFORE (Local Storage):
MODELS_DIR = Path('/opt/app-root/src/models')
model_path = MODELS_DIR / 'model.pkl'
joblib.dump(model, model_path)

# AFTER (PVC Storage):
from model_storage_helpers import save_model_to_pvc, load_model_from_pvc

# Save to PVC
model_path = save_model_to_pvc(
    model=model,
    model_name="anomaly-detector",
    metadata={'version': '1.0.0', 'accuracy': 0.95}
)
print(f"Model saved to PVC: {model_path}")
```

**Validation:**
- ✅ Model saved to `/mnt/models/` (PVC)
- ✅ Model accessible from other notebooks
- ✅ KServe can reference via `pvc://model-storage-pvc/model.pkl`

### Task 3.2: Update Tier 2 Notebooks (10 notebooks)

**Target Notebooks:** All notebooks in `02-anomaly-detection/` and `03-self-healing-logic/`

**Additional Changes:**
- Update model loading logic
- Add PVC availability checks
- Document migration in notebook markdown cells

### Task 3.3: Update Tier 3 Notebooks (15 notebooks)

**Target Notebooks:** All notebooks in `04-model-serving/`, `05-end-to-end-scenarios/`, `06-mcp-lightspeed-integration/`, `07-monitoring-operations/`, `08-advanced-scenarios/`

**GPU Notebooks Special Handling:**
- Ensure PVC mounts work with GPU-enabled pods
- Test model training with GPU + PVC storage
- Validate KServe deployment with GPU-trained models

---

## Phase 4: End-to-End Testing (Week 3)

### Test Scenario 1: Model Training → PVC → KServe

**Steps:**
1. Train model in notebook: `02-anomaly-detection/01-isolation-forest-implementation.ipynb`
2. Save to PVC: `save_model_to_pvc(model, "isolation-forest-v1")`
3. Deploy to KServe:
   ```yaml
   apiVersion: serving.kserve.io/v1beta1
   kind: InferenceService
   metadata:
     name: isolation-forest
   spec:
     predictor:
       model:
         modelFormat:
           name: sklearn
         runtime: sklearn-pvc-runtime
         storageUri: "pvc://model-storage-pvc/isolation-forest-v1.pkl"
   ```
4. Test inference: `curl -X POST http://isolation-forest.../v1/models/isolation-forest:predict`

**Success Criteria:**
- ✅ Model trains successfully
- ✅ Model saved to PVC (visible in `/mnt/models/`)
- ✅ KServe InferenceService deploys successfully
- ✅ Inference requests return predictions

### Test Scenario 2: Multi-Notebook Model Sharing

**Steps:**
1. Train model in notebook A
2. Save to PVC with metadata
3. Load model in notebook B
4. Verify model metadata and predictions match

---

## Success Metrics

- ✅ Operator upgraded to latest version
- ✅ 40+ notebooks migrated to PVC storage
- ✅ End-to-end workflow validated
- ✅ Documentation updated and accurate
- ✅ Zero S3 dependencies for model storage

---

## Rollback Plan

If upgrade fails:
1. Restore operator subscription: `oc apply -f backup-subscription.yaml`
2. Revert Ansible configuration changes
3. Notebooks continue using local storage (no breaking changes)
4. Document issues and retry with fixes
