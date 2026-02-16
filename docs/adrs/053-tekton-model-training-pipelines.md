# ADR-053: Tekton Pipelines for Model Training (Replaces ArgoCD Sync Wave Approach)

## Status
**PROPOSED** - 2026-01-27

**Supersedes**: Portions of ADR-050 and ADR-051 regarding training triggers

## Context

### Current Architecture (ADR-050, ADR-051)

Model training is currently triggered by **ArgoCD sync waves**:

```yaml
# charts/hub/values-notebooks-validation.yaml
wave3:
  notebooks:
    - name: "isolation-forest-implementation"
      blockNextWave: true  # Blocks wave 4 until training completes
      inferenceServiceTrigger:
        name: "anomaly-detector"
```

**Problems with ArgoCD-Triggered Training**:

1. **Wrong Abstraction**:
   - ArgoCD is for **deploying infrastructure**, not running **CI/CD workflows**
   - Model training is a workflow, not a deployment artifact
   - Mixes deployment concerns with operational tasks

2. **Poor Trigger Control**:
   - Training happens on every ArgoCD sync (git push, manual sync, auto-sync)
   - No way to schedule training independently (e.g., weekly cron)
   - No way to trigger training on-demand without full sync
   - No event-driven triggers (e.g., new data arrived, model drift detected)

3. **No Health Checks**:
   - No validation pipeline after training
   - No model quality gates
   - No rollback mechanism if new model is worse
   - InferenceService auto-restarts even if model is broken

4. **Resource Inefficiency**:
   - Blocks entire ArgoCD sync wave while training (minutes to hours)
   - Other deployments wait unnecessarily
   - Training resources tied to deployment lifecycle

5. **Limited Integration**:
   - Can't integrate with CI/CD pipelines
   - Can't chain with other Tekton tasks (e.g., data preparation, testing)
   - Can't leverage Tekton's retry, timeout, and notification features

### NotebookValidationJob CRD Capabilities

The NotebookValidationJob CRD **already supports Tekton** as a build strategy:

```yaml
spec:
  build:
    strategy: tekton  # Also supports: s2i, kaniko, shipwright, custom
    strategyConfig:
      pipelineName: "model-training-pipeline"
      taskName: "train-model-task"
```

This means we can use Tekton pipelines natively!

## Decision

**Replace ArgoCD sync wave model training with Tekton Pipelines.**

### New Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ ArgoCD (Deployment Only)                                     │
├──────────────────────────────────────────────────────────────┤
│ Wave -1: Operators, CRDs, RBAC                               │
│ Wave 0:  PVCs, ConfigMaps, Secrets                           │
│ Wave 1:  InferenceServices (empty models initially)          │
│ Wave 2:  NotebookValidationJob CRs (no blockNextWave)        │
│ Wave 3:  Tekton Pipelines, Tasks, Triggers                   │
│ Wave 4:  Monitoring, Dashboards                              │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ Tekton Pipelines (Model Training & Validation)              │
├──────────────────────────────────────────────────────────────┤
│ 1. model-training-pipeline                                   │
│    - Fetch data (Prometheus + synthetic)                     │
│    - Train model (NotebookValidationJob)                     │
│    - Save model to PVC                                       │
│    - Health check (prediction tests)                         │
│    - Rollout to InferenceService (if healthy)                │
│                                                              │
│ 2. model-health-check-pipeline                              │
│    - Load model from PVC                                     │
│    - Run prediction tests                                    │
│    - Compare with baseline metrics                           │
│    - Report to Prometheus                                    │
│                                                              │
│ 3. Triggers:                                                 │
│    - CronTrigger (weekly)                                    │
│    - EventTrigger (git push to notebooks/)                   │
│    - WebhookTrigger (manual API call)                        │
│    - EventListenerTrigger (model drift alert)                │
└──────────────────────────────────────────────────────────────┘
```

### Tekton Pipeline: Model Training

**File**: `charts/hub/templates/tekton-model-training-pipeline.yaml`

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: model-training-pipeline
  namespace: self-healing-platform
spec:
  description: |
    Trains ML models using NotebookValidationJobs and deploys to KServe.
    Supports health checks and rollback.

  params:
    - name: model-name
      type: string
      description: "Model to train (anomaly-detector or predictive-analytics)"
    - name: notebook-path
      type: string
      description: "Path to training notebook"
    - name: data-source
      type: string
      default: "hybrid"
      description: "Data source mode (synthetic|prometheus|hybrid)"
    - name: inference-service-name
      type: string
      description: "InferenceService to restart after training"
    - name: health-check-enabled
      type: string
      default: "true"
      description: "Run health checks before deployment"

  workspaces:
    - name: model-storage
      description: "PVC for storing trained models"

  tasks:
    # Task 1: Train model using NotebookValidationJob
    - name: train-model
      taskRef:
        name: run-notebook-validation
      params:
        - name: model-name
          value: $(params.model-name)
        - name: notebook-path
          value: $(params.notebook-path)
        - name: data-source
          value: $(params.data-source)
      workspaces:
        - name: model-storage
          workspace: model-storage

    # Task 2: Health check (only if enabled)
    - name: health-check
      when:
        - input: "$(params.health-check-enabled)"
          operator: in
          values: ["true"]
      runAfter:
        - train-model
      taskRef:
        name: validate-model-health
      params:
        - name: model-name
          value: $(params.model-name)
      workspaces:
        - name: model-storage
          workspace: model-storage

    # Task 3: Deploy to InferenceService (only if health check passed)
    - name: deploy-model
      runAfter:
        - health-check
      taskRef:
        name: restart-inference-service
      params:
        - name: inference-service-name
          value: $(params.inference-service-name)
        - name: namespace
          value: self-healing-platform

    # Task 4: Post-deployment validation
    - name: post-deployment-check
      runAfter:
        - deploy-model
      taskRef:
        name: test-inference-endpoint
      params:
        - name: inference-service-name
          value: $(params.inference-service-name)
        - name: model-name
          value: $(params.model-name)
```

### Tekton Task: Run Notebook Validation

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: run-notebook-validation
  namespace: self-healing-platform
spec:
  description: "Executes a notebook via NotebookValidationJob"

  params:
    - name: model-name
    - name: notebook-path
    - name: data-source
      default: "synthetic"

  workspaces:
    - name: model-storage

  steps:
    - name: create-validation-job
      image: quay.io/openshift/origin-cli:latest
      script: |
        #!/bin/bash
        set -e

        MODEL_NAME="$(params.model-name)"
        NOTEBOOK_PATH="$(params.notebook-path)"
        DATA_SOURCE="$(params.data-source)"
        JOB_NAME="train-${MODEL_NAME}-$(date +%s)"

        echo "Creating NotebookValidationJob: $JOB_NAME"

        cat <<EOF | oc apply -f -
        apiVersion: mlops.mlops.dev/v1alpha1
        kind: NotebookValidationJob
        metadata:
          name: $JOB_NAME
          namespace: self-healing-platform
        spec:
          notebook:
            path: $NOTEBOOK_PATH
            git:
              url: https://github.com/KubeHeal/openshift-aiops-platform.git
              ref: main
          podConfig:
            containerImage: image-registry.openshift-image-registry.svc:5000/self-healing-platform/notebook-validator:latest
            env:
              - name: DATA_SOURCE
                value: $DATA_SOURCE
              - name: PROMETHEUS_URL
                value: http://prometheus-k8s.openshift-monitoring.svc:9090
            envFrom:
              - secretRef:
                  name: model-storage-config
            serviceAccountName: self-healing-workbench
            volumeMounts:
              - name: model-storage
                mountPath: /mnt/models
            volumes:
              - name: model-storage
                persistentVolumeClaim:
                  claimName: model-storage-pvc
            resources:
              requests:
                memory: "2Gi"
                cpu: "1000m"
              limits:
                memory: "4Gi"
                cpu: "2000m"
          timeout: 15m
        EOF

        # Wait for completion
        echo "Waiting for job to complete..."
        oc wait --for=condition=complete notebookvalidationjob/$JOB_NAME \
          --timeout=20m -n self-healing-platform

        echo "✅ Model training completed successfully"
```

### Tekton Task: Model Health Check

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: validate-model-health
  namespace: self-healing-platform
spec:
  description: "Validates trained model health before deployment"

  params:
    - name: model-name

  workspaces:
    - name: model-storage

  steps:
    - name: check-model-file
      image: image-registry.openshift-image-registry.svc:5000/self-healing-platform/notebook-validator:latest
      script: |
        #!/bin/bash
        set -e

        MODEL_NAME="$(params.model-name)"
        MODEL_PATH="/workspace/model-storage/${MODEL_NAME}/model.pkl"

        echo "Checking model file: $MODEL_PATH"

        if [ ! -f "$MODEL_PATH" ]; then
          echo "❌ Model file not found: $MODEL_PATH"
          exit 1
        fi

        SIZE=$(stat -f%z "$MODEL_PATH" 2>/dev/null || stat -c%s "$MODEL_PATH")
        echo "✅ Model file exists: $MODEL_PATH ($SIZE bytes)"

        if [ "$SIZE" -lt 1000 ]; then
          echo "❌ Model file too small (< 1KB), likely corrupted"
          exit 1
        fi

    - name: test-model-load
      image: image-registry.openshift-image-registry.svc:5000/self-healing-platform/notebook-validator:latest
      script: |
        #!/usr/bin/env python3
        import joblib
        import sys
        from pathlib import Path

        model_name = "$(params.model-name)"
        model_path = Path(f"/workspace/model-storage/{model_name}/model.pkl")

        print(f"Loading model: {model_path}")

        try:
            model = joblib.load(model_path)
            print(f"✅ Model loaded successfully")
            print(f"   Type: {type(model)}")
            print(f"   Class: {model.__class__.__name__}")
        except Exception as e:
            print(f"❌ Failed to load model: {e}")
            sys.exit(1)

    - name: test-predictions
      image: image-registry.openshift-image-registry.svc:5000/self-healing-platform/notebook-validator:latest
      script: |
        #!/usr/bin/env python3
        import joblib
        import numpy as np
        import sys
        from pathlib import Path

        model_name = "$(params.model-name)"
        model_path = Path(f"/workspace/model-storage/{model_name}/model.pkl")

        print(f"Testing predictions: {model_name}")

        model = joblib.load(model_path)

        # Generate test data based on model type
        if model_name == "anomaly-detector":
            # 45 features for Isolation Forest
            test_data = np.random.rand(10, 45)
        elif model_name == "predictive-analytics":
            # 120 features for predictive analytics
            test_data = np.random.rand(10, 120)
        else:
            print(f"❌ Unknown model type: {model_name}")
            sys.exit(1)

        try:
            predictions = model.predict(test_data)
            print(f"✅ Predictions successful")
            print(f"   Shape: {predictions.shape}")
            print(f"   Sample: {predictions[:3]}")
        except Exception as e:
            print(f"❌ Prediction failed: {e}")
            sys.exit(1)
      volumeMounts:
        - name: model-storage
          mountPath: /workspace/model-storage
```

### Tekton CronTrigger: Weekly Training

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: model-training-trigger
  namespace: self-healing-platform
spec:
  params:
    - name: model-name
    - name: notebook-path
    - name: inference-service-name
  resourcetemplates:
    - apiVersion: tekton.dev/v1beta1
      kind: PipelineRun
      metadata:
        generateName: train-$(tt.params.model-name)-
      spec:
        pipelineRef:
          name: model-training-pipeline
        params:
          - name: model-name
            value: $(tt.params.model-name)
          - name: notebook-path
            value: $(tt.params.notebook-path)
          - name: data-source
            value: "prometheus"  # Use real data for scheduled training
          - name: inference-service-name
            value: $(tt.params.inference-service-name)
          - name: health-check-enabled
            value: "true"
        workspaces:
          - name: model-storage
            persistentVolumeClaim:
              claimName: model-storage-pvc

---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: weekly-anomaly-detector-training
  namespace: self-healing-platform
spec:
  schedule: "0 2 * * 0"  # Every Sunday at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: pipeline
          restartPolicy: OnFailure
          containers:
            - name: trigger-training
              image: quay.io/openshift/origin-cli:latest
              command:
                - /bin/bash
                - -c
                - |
                  oc create -f - <<EOF
                  apiVersion: tekton.dev/v1beta1
                  kind: PipelineRun
                  metadata:
                    generateName: train-anomaly-detector-
                    namespace: self-healing-platform
                  spec:
                    pipelineRef:
                      name: model-training-pipeline
                    params:
                      - name: model-name
                        value: "anomaly-detector"
                      - name: notebook-path
                        value: "notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb"
                      - name: data-source
                        value: "prometheus"
                      - name: inference-service-name
                        value: "anomaly-detector"
                      - name: health-check-enabled
                        value: "true"
                    workspaces:
                      - name: model-storage
                        persistentVolumeClaim:
                          claimName: model-storage-pvc
                  EOF
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: weekly-predictive-analytics-training
  namespace: self-healing-platform
spec:
  schedule: "0 3 * * 0"  # Every Sunday at 3 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: pipeline
          restartPolicy: OnFailure
          containers:
            - name: trigger-training
              image: quay.io/openshift/origin-cli:latest
              command:
                - /bin/bash
                - -c
                - |
                  oc create -f - <<EOF
                  apiVersion: tekton.dev/v1beta1
                  kind: PipelineRun
                  metadata:
                    generateName: train-predictive-analytics-
                    namespace: self-healing-platform
                  spec:
                    pipelineRef:
                      name: model-training-pipeline
                    params:
                      - name: model-name
                        value: "predictive-analytics"
                      - name: notebook-path
                        value: "notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb"
                      - name: data-source
                        value: "prometheus"
                      - name: inference-service-name
                        value: "predictive-analytics"
                      - name: health-check-enabled
                        value: "true"
                    workspaces:
                      - name: model-storage
                        persistentVolumeClaim:
                          claimName: model-storage-pvc
                  EOF
```

## Rationale

### Why Tekton Instead of ArgoCD Sync Waves

| Concern | ArgoCD Sync Waves | Tekton Pipelines |
|---------|-------------------|------------------|
| **Purpose** | Deploy infrastructure | Run workflows |
| **Trigger Control** | Git push, manual sync | Cron, events, webhooks, manual |
| **Blocking** | Blocks entire sync wave | Only blocks pipeline tasks |
| **Health Checks** | Manual in notebook | Built-in pipeline tasks |
| **Retry Logic** | None | Tekton retries |
| **Notifications** | ArgoCD notifications | Tekton interceptors |
| **Integration** | Limited | Full CI/CD integration |
| **Rollback** | Manual | Pipeline-based |

### Why NotebookValidationJob + Tekton

1. **Existing Infrastructure**: NotebookValidationJob CRD already exists and works
2. **Tekton Support**: CRD already supports `strategy: tekton`
3. **No Code Changes**: Notebooks don't need modification
4. **Gradual Migration**: Can run both approaches in parallel during transition

### Why Health Checks Matter

**Current Risk** (ArgoCD approach):
```
Train model → Auto-restart InferenceService
              ↓
              Model broken? Service crashes ❌
```

**New Safety** (Tekton approach):
```
Train model → Health check → Deploy only if healthy ✅
              ↓
              Broken? Keep old model, alert ops
```

## Consequences

### Positive

- ✅ **Separation of Concerns**: ArgoCD deploys, Tekton trains
- ✅ **Better Trigger Control**: Cron, events, webhooks, manual
- ✅ **Health Checks**: Validate before deployment
- ✅ **No Blocking**: ArgoCD sync doesn't wait for training
- ✅ **CI/CD Integration**: Tekton integrates with existing pipelines
- ✅ **Rollback Capability**: Keep old model if new one fails health checks
- ✅ **Notifications**: Tekton can notify on failure/success
- ✅ **Retry Logic**: Automatic retries on transient failures

### Negative

- ⚠️ **More Complexity**: Additional Tekton resources to manage
- ⚠️ **Initial Setup**: Need to create pipelines, tasks, triggers
- ⚠️ **RBAC**: Pipeline service account needs permissions
- ⚠️ **Learning Curve**: Team needs to understand Tekton

### Migration Path

**Phase 1** (Current): ArgoCD sync waves
- ✅ Already implemented
- ⚠️ Has limitations

**Phase 2** (Proposed): Tekton pipelines
- ⏭️ Create Tekton resources
- ⏭️ Remove `blockNextWave` from NotebookValidationJobs
- ⏭️ Deploy CronJobs for weekly training
- ⏭️ Test pipelines in parallel with ArgoCD

**Phase 3** (Final): Pure Tekton
- ⏭️ Remove all model training from ArgoCD sync waves
- ⏭️ ArgoCD only deploys infrastructure
- ⏭️ Tekton handles all model training

## Alternatives Considered

### Alternative 1: Keep ArgoCD Sync Waves

**Rejected** because:
- ❌ Wrong abstraction (deployment tool for workflows)
- ❌ Blocks entire sync wave
- ❌ No health checks
- ❌ Limited trigger options

### Alternative 2: Kubernetes CronJobs Only

**Rejected** because:
- ❌ No pipeline orchestration
- ❌ No health checks
- ❌ No integration with Tekton ecosystem
- ❌ Limited retry/failure handling

### Alternative 3: Kubeflow Pipelines

**Rejected** because:
- ❌ Additional infrastructure (Kubeflow installation)
- ❌ Overlap with existing Tekton
- ❌ NotebookValidationJob already supports Tekton
- ✅ Could be future enhancement for complex ML workflows

## Implementation

### Files to Create

1. `charts/hub/templates/tekton-model-training-pipeline.yaml` - Two pipelines (CPU + GPU), six tasks
2. `charts/hub/templates/tekton-model-training-cronjobs.yaml` - CronJobs + RBAC

### Files to Modify

1. `charts/hub/values-notebooks-validation.yaml` - Remove `blockNextWave: true`
2. `docs/adrs/050-anomaly-detector-model-training.md` - Update trigger section
3. `docs/adrs/051-predictive-analytics-model-training.md` - Update trigger section
4. `docs/model-training-guide.md` - Add Tekton pipeline usage

### RBAC Requirements

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: model-training-pipeline
rules:
  - apiGroups: ["mlops.mlops.dev"]
    resources: ["notebookvalidationjobs"]
    verbs: ["create", "get", "list", "watch", "delete"]
  - apiGroups: ["serving.kserve.io"]
    resources: ["inferenceservices"]
    verbs: ["get", "patch", "update"]
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
```

## Validation

### Test Manual Trigger

```bash
# Manually trigger training pipeline
oc create -f - <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: test-train-anomaly-detector-
  namespace: self-healing-platform
spec:
  pipelineRef:
    name: model-training-pipeline
  params:
    - name: model-name
      value: "anomaly-detector"
    - name: notebook-path
      value: "notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb"
    - name: data-source
      value: "synthetic"  # Use synthetic for testing
    - name: inference-service-name
      value: "anomaly-detector"
    - name: health-check-enabled
      value: "true"
  workspaces:
    - name: model-storage
      persistentVolumeClaim:
        claimName: model-storage-pvc
EOF

# Monitor pipeline
tkn pipelinerun logs -f -n self-healing-platform

# Check results
oc get pipelineruns -n self-healing-platform
```

### Test CronJob

```bash
# Manually trigger CronJob (for testing)
oc create job --from=cronjob/weekly-anomaly-detector-training test-cron-$(date +%s) -n self-healing-platform

# Monitor
oc logs -f job/test-cron-* -n self-healing-platform
```

## Amendment: CPU/GPU Pipeline Split (2026-02-16, Issue #38)

### Problem

The original single-pipeline design used `sed` to patch the NotebookValidationJob YAML
at runtime, replacing the CPU resources block with a GPU block (resources, tolerations,
nodeSelector) for the `predictive-analytics` model:

```bash
# Original (broken) approach
JOB_YAML=$(echo "$JOB_YAML" | sed '/resources:/,/cpu: "4000m"/c\'"$GPU_CONFIG")
```

The `sed` `c\` command cannot handle multi-line replacement text without explicit
line-continuation backslashes. When `$GPU_CONFIG` expanded to multiple lines, `sed`
treated only the first line as the replacement and interpreted subsequent lines
(e.g., `memory: "4Gi"`) as new sed commands, failing with:

```
sed: -e expression #1, char 77: unknown command: `m'
```

This blocked all predictive-analytics training and made the pipeline fragile for
any custom model using a different notebook path.

### Solution

Split into two separate pipelines with static YAML heredocs (no `sed`, no shell
variable interpolation for the resources block):

| Pipeline | Task | Resources | Use Case |
|----------|------|-----------|----------|
| `model-training-pipeline` | `run-notebook-validation` | CPU only (4Gi/2CPU) | anomaly-detector, custom CPU models |
| `model-training-pipeline-gpu` | `run-notebook-validation-gpu` | GPU (4Gi/2CPU/1 GPU + tolerations + nodeSelector) | predictive-analytics, custom GPU models |

### Updated Architecture

```
Tekton Pipelines (Model Training & Validation)

1. model-training-pipeline (CPU)
   train-model -> health-check -> deploy-model -> post-deployment-check

2. model-training-pipeline-gpu (GPU)
   train-model -> copy-gpu-model -> health-check -> deploy-model -> post-deployment-check
```

Shared tasks used by both pipelines:
- `validate-model-health` - Model file, load, and prediction checks
- `restart-inference-service` - Pod restart for KServe
- `test-inference-endpoint` - Endpoint validation
- `copy-gpu-model-to-shared` - GPU PVC to shared PVC copy (GPU pipeline only)

### Updated Files

- `charts/hub/templates/tekton-model-training-pipeline.yaml` - Two tasks + two pipelines
- `charts/hub/templates/tekton-model-training-cronjobs.yaml` - predictive-analytics uses `model-training-pipeline-gpu`
- `scripts/trigger-model-training.sh` - `--gpu` flag selects pipeline; removed `gpu-trained`/`training-timeout` params

### Custom Model Support

Users can now train any custom model by providing a notebook path and inference service name:

```bash
# CPU custom model
./scripts/trigger-model-training.sh \
  --notebook-path notebooks/02-anomaly-detection/my-custom-model.ipynb \
  --inference-service my-custom-model \
  my-custom-model 168

# GPU custom model
./scripts/trigger-model-training.sh \
  --notebook-path notebooks/02-anomaly-detection/my-gpu-model.ipynb \
  --inference-service my-gpu-model --gpu \
  my-gpu-model 720
```

## Amendment: GPU Task PVC Fix (2026-02-16, Issue #40)

### Problem

The `run-notebook-validation-gpu` task was using `model-storage-pvc` (CephFS storage
class) for its volume mount. GPU nodes do not have the CephFS CSI driver
(`openshift-storage.cephfs.csi.ceph.com`) installed, causing the validation job pod
to get stuck in `Init:0/1` with:

```
MountVolume.MountDevice failed for volume "pvc-..." :
kubernetes.io/csi: attacher.MountDevice failed to create newCsiDriverClient:
driver name openshift-storage.cephfs.csi.ceph.com not found in the list of registered CSI drivers
```

This broke all GPU pipeline training (predictive-analytics and any custom GPU model).

### Root Cause

When the CPU/GPU pipeline split was implemented (Issue #38 amendment above), the
`run-notebook-validation-gpu` task's volume was not updated from `model-storage-pvc`
(CephFS) to `model-storage-gpu-pvc` (GP3). The `copy-gpu-model-to-shared` task
already correctly referenced `model-storage-gpu-pvc` as its source volume, but the
training task itself still wrote to the CephFS-backed PVC that GPU nodes cannot mount.

### Fix

Single-line change in `charts/hub/templates/tekton-model-training-pipeline.yaml`,
in the `run-notebook-validation-gpu` task's NotebookValidationJob spec:

```yaml
# Before (broken)
volumes:
  - name: model-storage
    persistentVolumeClaim:
      claimName: model-storage-pvc        # CephFS - not available on GPU nodes

# After (fixed)
volumes:
  - name: model-storage
    persistentVolumeClaim:
      claimName: model-storage-gpu-pvc    # GP3 - available on GPU nodes
```

The pipeline flow is now correct end-to-end:

```
run-notebook-validation-gpu (writes to model-storage-gpu-pvc, GP3)
  -> copy-gpu-model-to-shared (copies model-storage-gpu-pvc -> model-storage-pvc)
  -> validate-model-health (reads from model-storage-pvc, CephFS)
  -> restart-inference-service / test-inference-endpoint
```

### Environment Note

This fix was identified and validated on a **demo.redhat.com** provisioned cluster
where GPU nodes do not include CephFS CSI drivers. If you are deploying this platform
in your own environment, your storage configuration may differ:

- Your GPU nodes may have CephFS drivers available (e.g., ODF deployed across all nodes).
- You may use a different storage class for GPU-accessible volumes (not necessarily `gp3-csi`).
- The PVC names (`model-storage-pvc`, `model-storage-gpu-pvc`) are defined in
  `charts/hub/templates/storage.yaml` and can be adjusted to match your cluster's
  storage classes.

The key principle remains: GPU training tasks must use a PVC backed by a storage class
whose CSI driver is available on GPU-capable nodes.

## Related ADRs

- [ADR-050: Anomaly Detector Model Training](050-anomaly-detector-model-training.md) - **Updated trigger section**
- [ADR-051: Predictive Analytics Model Training](051-predictive-analytics-model-training.md) - **Updated trigger section**
- [ADR-052: Model Training Data Sources](052-model-training-data-sources.md) - No changes
- [ADR-029: Jupyter Notebook Validator Operator](029-jupyter-notebook-validator-operator.md) - Used by Tekton tasks
- [ADR-030: Hybrid Management Model (Namespaced ArgoCD)](030-hybrid-management-model-namespaced-argocd.md) - Tekton resources in pattern namespace

## References

- Tekton Pipelines: https://tekton.dev/docs/pipelines/
- Tekton Triggers: https://tekton.dev/docs/triggers/
- NotebookValidationJob CRD: `oc get crd notebookvalidationjobs.mlops.mlops.dev -o yaml`
- KServe InferenceService: https://kserve.github.io/website/latest/

## Decision

**APPROVED**: Migrate model training from ArgoCD sync waves to Tekton Pipelines

**Timeline**:
- Week 1: Create Tekton resources (pipelines, tasks, triggers)
- Week 2: Test pipelines in parallel with existing ArgoCD approach
- Week 3: Migrate anomaly-detector to Tekton-only
- Week 4: Migrate predictive-analytics to Tekton-only
- Week 5: Remove ArgoCD model training sync waves

**Success Criteria**:
- ✅ Models train successfully via Tekton pipelines
- ✅ Health checks catch broken models before deployment
- ✅ CronJobs trigger weekly training
- ✅ Manual triggers work via `tkn` or `oc create`
- ✅ ArgoCD no longer blocks on model training
