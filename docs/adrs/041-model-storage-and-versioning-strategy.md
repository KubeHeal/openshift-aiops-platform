# ADR-041: Model Storage and Versioning Strategy

## Status
**ACCEPTED** - 2025-12-09

## Context

KServe InferenceServices using the sklearn serving runtime require **exactly ONE model file** per `storageUri` directory. When multiple model files exist in the same directory, the sklearn server raises a `RuntimeError`:

```
RuntimeError: More than one model file detected in /mnt/models/, Only one is allowed within model_dir
Found: ['arima_model.pkl', 'prophet_model.pkl']
```

### Problem Scenario

Prior to this ADR, notebooks saved multiple models to shared directories:

- **Notebook 02** (time-series): Saved both `arima_model.pkl` and `prophet_model.pkl` to `/mnt/models/anomaly-detector/`
- **Notebook 03** (LSTM): Also saved to `/mnt/models/anomaly-detector/` (conflict!)
- **Notebook 04** (ensemble): Saved to root `/mnt/models/` directory

This caused KServe InferenceService pods to crash with `CrashLoopBackOff` when attempting to load models.

### Requirements

1. Each InferenceService must have a dedicated storage directory
2. Model storage paths must be predictable and consistent
3. Notebooks must be able to save models without manual directory creation
4. Storage isolation must work with both PVC-based (`/mnt/models`) and local (`/opt/app-root/src/models`) storage
5. Future model versioning should be possible without breaking changes

## Decision

Implement **one directory per InferenceService** storage strategy:

### Directory Structure

```
/mnt/models/
├── predictive-analytics/       # Isolation Forest models
│   ├── isolation_forest_model.pkl
│   └── isolation_forest_scaler.pkl
├── arima-predictor/             # ARIMA time-series models
│   └── arima_model.pkl
├── prophet-predictor/           # Prophet time-series models
│   └── prophet_model.pkl
├── lstm-predictor/              # LSTM autoencoder models
│   ├── lstm_autoencoder.pt
│   └── lstm_scaler.pkl
├── ensemble-predictor/          # Ensemble configuration
│   └── ensemble_config.pkl
└── anomaly-detector/            # Legacy (for backward compatibility)
```

### Implementation Rules

1. **Notebook Storage Pattern**:
   ```python
   # Each notebook uses dedicated directory matching InferenceService name
   MODELS_DIR = Path('/mnt/models/{inferenceservice-name}')
   MODELS_DIR.mkdir(parents=True, exist_ok=True)
   ```

2. **InferenceService Configuration**:
   ```yaml
   spec:
     predictor:
       model:
         storageUri: "pvc://model-storage-pvc/{inferenceservice-name}"
   ```

3. **Init Job**: Create all directories during deployment:
   ```bash
   mkdir -p /mnt/models/predictive-analytics
   mkdir -p /mnt/models/arima-predictor
   mkdir -p /mnt/models/prophet-predictor
   mkdir -p /mnt/models/lstm-predictor
   mkdir -p /mnt/models/ensemble-predictor
   ```

### Future Model Versioning (Placeholder)

Directory structure supports future versioning:

```
/mnt/models/{inferenceservice-name}/{version}/
Example:
/mnt/models/predictive-analytics/v1/
/mnt/models/predictive-analytics/v2/
```

This will require:
- Updates to notebooks to include version in path
- Updates to InferenceService `storageUri` to specify version
- Model version management logic in coordination engine

## Rationale

### Why One Directory Per InferenceService

1. **KServe Requirement**: sklearn runtime expects single model file per directory
2. **Clear Ownership**: Each InferenceService owns its storage directory
3. **No Conflicts**: Multiple notebooks can save models without collision
4. **Predictable Paths**: InferenceService name = directory name = storage path

### Why Not Model Registry (e.g., MLflow, ModelMesh)

**Pros of Model Registry**:
- Version tracking
- Model metadata management
- A/B testing support
- Governance and auditing

**Cons** (why deferred):
- Additional infrastructure complexity
- Not required for MVP
- Can be added later without breaking changes
- Current PVC-based approach is simpler for initial deployment

**Decision**: Start with PVC-based storage, evaluate Model Registry for Phase 2.

### Why Not Subdirectories for Multi-File Models

Some models require multiple files (e.g., Isolation Forest needs model + scaler). Options:

**Option 1** (Chosen): Allow multiple files in same directory if they're for **one model**
- `isolation_forest_model.pkl` + `isolation_forest_scaler.pkl` = one logical model
- KServe loads all pkl files in directory

**Option 2** (Rejected): Separate subdirectories per file
- `/mnt/models/predictive-analytics/model/`
- `/mnt/models/predictive-analytics/scaler/`
- **Problem**: Breaks KServe's expectation of flat directory structure

**Option 3** (Rejected): Combine into single file
- **Problem**: Requires custom model wrapper, increases complexity

## Consequences

### Positive

- ✅ **KServe Compatibility**: InferenceServices start successfully
- ✅ **No Model Conflicts**: Each notebook has isolated storage
- ✅ **Predictable Paths**: Naming convention is clear and consistent
- ✅ **Backward Compatible**: Legacy `/mnt/models/anomaly-detector/` kept for transition
- ✅ **Version-Ready**: Directory structure supports future versioning

### Negative

- ⚠️ **Manual Directory Management**: Init job must create directories before notebooks run
- ⚠️ **No Built-in Versioning**: Version management must be implemented manually
- ⚠️ **No Metadata Storage**: Model metadata (training date, metrics) not captured

### Neutral

- 📝 **PVC Dependency**: All models stored on shared PVC (alternative: S3/ODF)
- 📝 **No Model Lineage**: Can't track which notebook/commit produced which model

## Implementation

### Files Updated

1. **Notebooks** (3 files):
   - `notebooks/02-anomaly-detection/02-time-series-anomaly-detection.ipynb` → Split into `ARIMA_DIR` and `PROPHET_DIR`
   - `notebooks/02-anomaly-detection/03-lstm-based-prediction.ipynb` → Use `lstm-predictor` directory
   - `notebooks/02-anomaly-detection/04-ensemble-anomaly-methods.ipynb` → Use `ensemble-predictor` directory

2. **Init Job**:
   - `charts/hub/templates/init-models-job.yaml` → Create all model subdirectories

3. **InferenceServices**:
   - `charts/hub/templates/model-serving.yaml` → Update `storageUri` paths (if needed)

### Validation

```bash
# Verify directory structure
oc exec -it self-healing-workbench-0 -n self-healing-platform -- \
  ls -la /mnt/models/

# Check InferenceService health
oc get inferenceservices -n self-healing-platform

# Test inference endpoint
curl -X POST http://predictive-analytics-predictor:8080/v1/models/predictive-analytics:predict \
  -d '{"instances": [[0.5, 0.3, 0.8]]}'
```

## Related ADRs

- [ADR-004: KServe for Model Serving Infrastructure](004-kserve-model-serving.md)
- [ADR-012: Notebook Architecture for End-to-End Workflows](012-notebook-architecture-for-end-to-end-workflows.md)
- [ADR-010: OpenShift Data Foundation as Storage Infrastructure](010-openshift-data-foundation-requirement.md)
- [ADR-037: MLOps Workflow for Model Training, Versioning, and Deployment](037-mlops-workflow-strategy.md)
- [ADR-039: User-Deployed KServe Models](039-user-deployed-kserve-models.md)
- [ADR-040: Extensible KServe Model Registry](040-extensible-kserve-model-registry.md)

## References

- KServe sklearn server: https://github.com/kserve/kserve/tree/master/python/sklearnserver
- Notebook implementations: `notebooks/02-anomaly-detection/*.ipynb`
- End-user feedback: GitHub issue #XX (model serving multiple file conflict)

## Next Steps

**Phase 2 (Future)**:
1. Implement model versioning (v1, v2, v3 subdirectories)
2. Evaluate Model Registry (MLflow, KServe ModelMesh)
3. Add model metadata storage (training date, accuracy, data version)
4. Implement A/B testing for model versions
5. Add model rollback capability
