# ADR-031: Dockerfile Strategy for Notebook Validation Images

## Status
Proposed

## Implementation Status
**Status:** ✅ IMPLEMENTED
**Verification Date:** 2026-01-25
**Implementation Score:** 9.5/10
**Verified On:** SNO + HA clusters
**Evidence:** Option A (single Dockerfile) implemented. Unified notebook validation image strategy operational.

## Context

Currently, we use a **single Dockerfile** (`notebooks/Dockerfile`) to build validation images for all notebook tiers (Tier 1-3). This Dockerfile:
- Includes ALL dependencies for all notebooks (papermill, seaborn, joblib, prometheus-api-client, etc.)
- Results in a single image: `notebook-validator:latest`
- Used by Tekton builds via `buildConfig.dockerfile: "Dockerfile"`

### Current Notebook Tiers
1. **Tier 1** (Setup/Infrastructure): Minimal deps - papermill, kubernetes, prometheus-api-client
2. **Tier 2** (ML Training): ML deps - seaborn, joblib, scikit-learn, torch
3. **Tier 3** (Model Serving): KServe deps - requests, grpcio, tritonclient

### Architectural Question
**Should we use multiple Dockerfiles** (tier-specific or notebook-specific) instead of a single shared Dockerfile?

## Decision Options

### Option A: Single Shared Dockerfile (Current)
**File**: `notebooks/Dockerfile`
**Strategy**: All dependencies in one image

**Pros**:
- ✅ **Simple maintenance**: One Dockerfile to update
- ✅ **Consistent environment**: Same base for all notebooks
- ✅ **Faster validation cycles**: Image built once, reused for all tiers
- ✅ **Operator simplicity**: `buildConfig.dockerfile: "Dockerfile"`
- ✅ **Reduced build time**: One Tekton build vs. three
- ✅ **No dependency conflicts**: Guaranteed compatibility across notebooks

**Cons**:
- ❌ **Larger image size**: ~2-3GB with all dependencies
- ❌ **Unnecessary deps**: Tier 1 notebooks don't need seaborn/joblib
- ❌ **Longer build time**: Installing all deps takes ~5-10 min
- ❌ **Storage overhead**: Each tier workspace pulls full image

**Build Time**: ~5-10 minutes (one build)
**Image Size**: ~2-3GB
**Maintenance**: Low (1 file)

---

### Option B: Tier-Specific Dockerfiles
**Files**: `notebooks/Dockerfile.tier1`, `Dockerfile.tier2`, `Dockerfile.tier3`
**Strategy**: Separate images per tier

**Pros**:
- ✅ **Smaller images**: Tier 1 ~500MB, Tier 2 ~2GB, Tier 3 ~1.5GB
- ✅ **Faster tier 1 builds**: No ML dependencies needed
- ✅ **Optimized for use case**: Only install what's needed
- ✅ **Storage efficiency**: Smaller images for basic validation

**Cons**:
- ❌ **3x maintenance**: Three Dockerfiles to update
- ❌ **Inconsistent environments**: Risk of version mismatches
- ❌ **3x build time**: Three separate Tekton builds (~15-30 min total)
- ❌ **Complexity**: Operator must select correct Dockerfile per tier
- ❌ **Debugging harder**: Different environments per tier

**Build Time**: ~15-30 minutes (three builds in parallel, or sequential)
**Image Size**: ~4GB total (500MB + 2GB + 1.5GB)
**Maintenance**: High (3 files)

---

### Option C: Notebook-Specific Dockerfiles
**Files**: `notebooks/01-isolation-forest/Dockerfile`, `02-time-series/Dockerfile`, etc.
**Strategy**: Per-notebook images

**Pros**:
- ✅ **Maximum optimization**: Exact dependencies per notebook
- ✅ **Smallest images**: ~300MB-1.5GB per notebook

**Cons**:
- ❌ **High maintenance**: 8+ Dockerfiles to manage
- ❌ **Build explosion**: 8+ separate builds (~40-80 min total)
- ❌ **High complexity**: Operator must map notebooks to Dockerfiles
- ❌ **Brittle**: Any shared dependency change requires updating all files
- ❌ **Environment drift**: High risk of inconsistencies

**Build Time**: ~40-80 minutes (8+ builds)
**Image Size**: ~8-10GB total
**Maintenance**: Very High (8+ files)

---

### Option D: Multi-Stage Dockerfile with Base + Tier Layers
**File**: `notebooks/Dockerfile` (multi-stage)
**Strategy**: Base image + tier-specific layers

```dockerfile
# Stage 1: Base (shared by all tiers)
FROM rhoai/pytorch:2025.1 AS base
RUN pip install papermill nbformat nbconvert kubernetes

# Stage 2: Tier 1 (minimal)
FROM base AS tier1
RUN pip install prometheus-api-client pyyaml

# Stage 3: Tier 2 (ML training)
FROM base AS tier2
RUN pip install seaborn joblib prometheus-api-client

# Stage 4: Tier 3 (model serving)
FROM base AS tier3
RUN pip install requests grpcio tritonclient
```

**Operator usage**: `buildConfig.dockerfile: "Dockerfile" buildConfig.target: "tier2"`

**Pros**:
- ✅ **Single file maintenance**: One Dockerfile with stages
- ✅ **Optimized images**: Layer caching, smaller finals
- ✅ **Flexible**: Can build any tier from same file
- ✅ **Shared base**: Consistency for common dependencies
- ✅ **Docker best practice**: Multi-stage builds

**Cons**:
- ❌ **Operator support needed**: Must support `--target` flag
- ❌ **Slightly complex**: Requires understanding multi-stage builds
- ❌ **Still 3x builds**: Each tier needs separate build (but faster due to caching)

**Build Time**: ~10-15 minutes (three builds with layer caching)
**Image Size**: ~3GB total (shared layers)
**Maintenance**: Medium (1 file, multiple stages)

---

## Recommendation

### **Option A: Single Shared Dockerfile** ✅

**Reasoning**:
1. **Build time is acceptable**: 5-10 min for one build vs. 15-30 min for three
2. **Operator simplicity**: No need to manage tier-to-dockerfile mapping
3. **Environment consistency**: Guaranteed no version conflicts
4. **Image size is manageable**: 2-3GB is reasonable for RHOAI base
5. **Maintenance burden is low**: One file to update when dependencies change
6. **Validation is fast**: Build once, validate all tiers

**When to reconsider**:
- ❗ If image size exceeds 5GB (storage constraints)
- ❗ If Tier 1 validation becomes time-critical (every minute matters)
- ❗ If we have 10+ notebook tiers (scale issue)
- ❗ If operator adds multi-stage build support (`--target` flag)

### Alternative: **Option D** (if operator supports `--target`)
If the Jupyter Notebook Validator Operator adds support for `buildConfig.target: "tier2"`, then **multi-stage Dockerfile** becomes the best option.

---

## Consequences

### Positive (Option A)
- ✅ Faster time-to-validation (single build)
- ✅ Lower maintenance burden (one Dockerfile)
- ✅ Consistent environment (no version drift)
- ✅ Simpler operator integration (no tier mapping)

### Negative (Option A)
- ❌ Larger image size (~2-3GB)
- ❌ Tier 1 notebooks pull unnecessary ML dependencies
- ❌ Slightly longer build times (all deps installed)

### Neutral
- 📊 Can migrate to multi-stage (Option D) later if operator adds support
- 📊 Current storage overhead is acceptable for 1-3 tier deployment

---

## Implementation

### Current Dockerfile
```dockerfile
FROM image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/pytorch:2025.1

# Install ALL dependencies for ALL tiers
RUN pip install --no-cache-dir \
    papermill nbformat nbconvert \
    kubernetes openshift prometheus-api-client \
    seaborn joblib requests pyyaml
```

### NotebookValidationJob (all tiers use same image)
```yaml
podConfig:
  buildConfig:
    enabled: true
    strategy: tekton
    dockerfile: "Dockerfile"  # Same for all tiers
    baseImage: "image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/pytorch:2025.1"
```

### Future Migration Path (if needed)
1. Add multi-stage support to Dockerfile
2. Wait for operator to support `buildConfig.target`
3. Update NotebookValidationJob templates per tier
4. Validate layer caching works correctly

---

## Related ADRs
- [ADR-029: Jupyter Notebook Validator Operator Adoption](029-jupyter-notebook-validator-operator-adoption.md)
- [ADR-011: Self-Healing Workbench Base Image](011-self-healing-workbench-base-image.md)

## References
- Docker multi-stage builds: https://docs.docker.com/build/building/multi-stage/
- RHOAI ImageStreams: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/
- NotebookValidationJob CRD: `oc get crd notebookvalidationjobs.mlops.mlops.dev -o yaml`

---

**Decision**: Stick with **Option A (Single Shared Dockerfile)** for now.
**Review**: When operator adds multi-stage support, migrate to **Option D**.
**Date**: 2025-11-19
**Confidence**: 85%
