# ADR Validation System

## Overview

This document describes the ADR (Architecture Decision Record) validation system implemented for the OpenShift AI/Ops Platform. The system validates 31 implemented ADRs across both SNO (Single Node OpenShift) and HA (Highly Available) cluster topologies.

## Architecture

### Components

The validation system consists of the following components:

```
openshift-aiops-platform/
├── validators/                    # Modular validation scripts
│   ├── core-platform.sh          # ADRs 001, 003, 004, 006, 007, 010
│   ├── notebooks.sh              # ADRs 011, 012, 013, 029, 031, 032
│   ├── mlops-cicd.sh             # ADRs 021, 023, 024, 025, 026, 042, 043
│   ├── deployment.sh             # ADRs 019, 030
│   ├── coordination.sh           # ADRs 036, 038
│   └── storage-topology.sh       # ADRs 034, 035, 054, 055, 056, 057, 058
├── scripts/
│   ├── validate-31-adrs.sh       # Main orchestrator (multi-cluster)
│   ├── run-adr-validation.sh     # Single-cluster validation runner
│   ├── generate-validation-report.py  # Report generator
│   └── update-tracker-with-evidence.sh  # Tracker updater
├── results/                       # Validation results (JSON)
│   ├── sno-complete.json
│   ├── ha-complete.json
│   └── validation-report.json
└── docs/adrs/audit-reports/       # Markdown reports
    └── adr-validation-YYYY-MM-DD.md
```

### Validation Workflow

```
┌─────────────────────┐
│  Login to Cluster   │
│  (SNO or HA)        │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Detect Topology    │
│  (SNO/HA/Unknown)   │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Run Validation     │
│  Modules (6)        │
│  ├─ Core Platform   │
│  ├─ Notebooks       │
│  ├─ MLOps/CI/CD     │
│  ├─ Deployment      │
│  ├─ Coordination    │
│  └─ Storage/Topo    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Aggregate Results  │
│  (JSON per cluster) │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Generate Reports   │
│  - JSON (machine)   │
│  - Markdown (human) │
└─────────────────────┘
```

## Usage

### Validate SNO Cluster

```bash
# Set environment variables
export SNO_TOKEN="sha256~..."

# Run validation
./scripts/validate-31-adrs.sh --sno-only
```

### Validate HA Cluster

```bash
# Set environment variables
export HA_TOKEN="sha256~..."

# Run validation
./scripts/validate-31-adrs.sh --ha-only
```

### Validate Both Clusters

```bash
# Set both tokens
export SNO_TOKEN="sha256~..."
export HA_TOKEN="sha256~..."

# Run validation on both
./scripts/validate-31-adrs.sh
```

### Using Current Cluster Context

```bash
# Already logged in with oc login
./scripts/run-adr-validation.sh --cluster sno
```

### Generate Reports

```bash
# After validation completes
python3 scripts/generate-validation-report.py
```

## Validation Modules

### 1. Core Platform Validator (`validators/core-platform.sh`)

**ADRs**: 001, 003, 004, 006, 007, 010

Validates:
- **ADR-001**: OpenShift 4.18+ cluster version, node count, topology
- **ADR-003**: RHODS/RHOAI deployment (operator, KServe, dashboard)
- **ADR-004**: KServe InferenceServices (2 expected, predictor pods)
- **ADR-006**: GPU Operator deployment, driver pods, GPU nodes
- **ADR-007**: Prometheus StatefulSet, AlertManager, ServiceMonitors
- **ADR-010**: ODF operator, StorageCluster, NooBaa, storage classes

**Example Check**:
```bash
# ADR-004: Check InferenceServices
isvc_count=$(oc get inferenceservice -n self-healing-platform --no-headers | wc -l)
ready_count=$(oc get inferenceservice -n self-healing-platform -o json | \
  jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready"))] | length')

if [[ $ready_count -eq 2 ]]; then
    status="PASS"
else
    status="PARTIAL"
fi
```

### 2. Notebooks Validator (`validators/notebooks.sh`)

**ADRs**: 011, 012, 013, 029, 031, 032

Validates:
- **ADR-011**: PyTorch workbench pod running
- **ADR-012**: Notebook portfolio (32 notebooks across 9 directories)
- **ADR-013**: Data collection notebooks (5 notebooks, utility modules)
- **ADR-029**: Notebook Validator Operator (CRD, deployment)
- **ADR-031**: Custom notebook image (Dockerfile, ImageStream)
- **ADR-032**: Infrastructure validation notebook execution history

### 3. MLOps/CI/CD Validator (`validators/mlops-cicd.sh`)

**ADRs**: 021, 023, 024, 025, 026, 042, 043

Validates:
- **ADR-021**: Tekton pipelines (4+), tasks, recent pipeline runs
- **ADR-023**: S3 configuration pipeline with ExternalSecrets
- **ADR-024**: ExternalSecrets (4), SecretSynced status
- **ADR-025**: ObjectBucketClaim (Bound), NooBaa S3 endpoint
- **ADR-026**: External Secrets Operator (3 components)
- **ADR-042**: ArgoCD custom health checks, BuildConfig
- **ADR-043**: Init containers, startup probes, healthcheck binary

### 4. Deployment Validator (`validators/deployment.sh`)

**ADRs**: 019, 030

Validates:
- **ADR-019**: Validated Patterns Operator, GitOps 1.19.1+, Pattern CR
- **ADR-030**: Namespaced ArgoCD with cluster-scoped RBAC

### 5. Coordination Validator (`validators/coordination.sh`)

**ADRs**: 036, 038

Validates:
- **ADR-036**: MCP Server deployment, HTTP endpoint, tools/resources
- **ADR-038**: Coordination Engine deployment (partial implementation)

### 6. Storage & Topology Validator (`validators/storage-topology.sh`)

**ADRs**: 034, 035, 054, 055, 056, 057, 058

Validates:
- **ADR-034**: Secure notebook routes (TLS, OAuth proxy)
- **ADR-035**: Persistent Volume Claims (4+ Bound)
- **ADR-054**: Model files on PVC, restart-predictors automation
- **ADR-055**: Topology detection, infrastructure settings match
- **ADR-056**: SNO-specific MCG-only StorageCluster (standalone strategy)
- **ADR-057**: GPU affinity rules, storage access patterns
- **ADR-058**: Deployment validation results (94%+ success rate)

## Output Format

### JSON Result Schema

Each validation produces a JSON object:

```json
{
  "adr": "004",
  "status": "PASS",
  "expected": "2 InferenceServices ready",
  "actual": "2/2 ready, 2 predictor pods",
  "details": "KServe operational",
  "timestamp": "2026-03-03T21:25:15Z"
}
```

**Status Values**:
- `PASS`: Fully implemented and operational
- `PARTIAL`: Partially implemented or degraded
- `FAIL`: Not implemented or non-functional
- `ERROR`: Validation error occurred
- `N/A`: Not applicable to this topology

### Aggregated Results

```json
{
  "validation_date": "2026-03-03T21:27:52Z",
  "total_adrs_validated": 31,
  "sno": {
    "total": 30,
    "pass": 13,
    "fail": 4,
    "partial": 13,
    "success_rate": 43.3
  },
  "ha": {
    "total": 30,
    "pass": 20,
    "fail": 2,
    "partial": 8,
    "success_rate": 66.7
  }
}
```

## Report Generation

The validation system generates two types of reports:

### 1. JSON Report (`results/validation-report.json`)

Machine-readable format containing:
- Summary statistics
- Per-category breakdown
- Failed validations with details
- Topology-specific variations

### 2. Markdown Report (`docs/adrs/audit-reports/adr-validation-YYYY-MM-DD.md`)

Human-readable format containing:
- Executive summary with pass/fail counts
- Validation by category table
- Detailed failure descriptions
- Recommendations and next steps

## Topology-Specific Validations

### SNO (Single Node OpenShift)

**Specific Checks**:
- **ADR-056**: MCG-only storage (no Ceph)
  - `reconcileStrategy: standalone`
  - NooBaa without CephFS
  - Storage class: `gp3-csi` (RWO only)

- **ADR-007**: Single Prometheus replica acceptable
  - HA clusters expect 2+ replicas
  - SNO tolerates 1 replica

### HA (Highly Available)

**Specific Checks**:
- **ADR-007**: Prometheus HA (2+ replicas)
- **ADR-010**: Full ODF with CephFS
  - Storage class: `ocs-storagecluster-cephfs` (RWX)
- Multiple node availability zones

## Integration with Existing Tools

The validation system reuses:

1. **`scripts/post-deployment-validation.sh`**
   - 8-category infrastructure validation
   - Referenced for validation patterns

2. **`scripts/detect-cluster-topology.sh`**
   - Automatic topology detection
   - Exit codes: 0=HA, 1=SNO, 2=Unknown

3. **`notebooks/utils/validation_helpers.py`**
   - Python validation library (940 lines)
   - Reusable for notebook-based validation

4. **`tekton/pipelines/deployment-validation-pipeline.yaml`**
   - Optional Tekton execution of validators
   - CI/CD integration point

## Cluster Access

### SNO Cluster
- **Server**: `https://api.ocp.ph5rd.sandbox1590.opentlc.com:6443`
- **Token**: Set via `SNO_TOKEN` environment variable

### HA Cluster
- **Server**: `https://api.cluster-7r4mf.7r4mf.sandbox458.opentlc.com:6443`
- **Token**: Set via `HA_TOKEN` environment variable

### Example Login

```bash
oc login --token=$SNO_TOKEN \
  --server=https://api.ocp.ph5rd.sandbox1590.opentlc.com:6443 \
  --insecure-skip-tls-verify=true
```

## Validation Results

### Latest Validation (2026-03-03)

**SNO Cluster**:
- Total ADRs: 30
- ✅ PASS: 13 (43.3%)
- ⚠️ PARTIAL: 13 (43.3%)
- ❌ FAIL: 4 (13.3%)

**By Category**:
- **Core Platform**: 4 PASS, 2 PARTIAL
- **Notebooks & Development**: 2 PASS, 2 FAIL, 2 PARTIAL
- **MLOps & CI/CD**: 3 PASS, 4 PARTIAL
- **Deployment & GitOps**: 1 PASS, 1 PARTIAL
- **Coordination & LLM**: 2 PARTIAL
- **Storage & Topology**: 3 PASS, 2 FAIL, 2 PARTIAL

**Failed ADRs**:
- **ADR-012**: Notebooks not committed to repo
- **ADR-029**: Notebook Validator Operator not deployed
- **ADR-034**: Secure routes not configured
- **ADR-057**: GPU affinity patterns not configured

## Troubleshooting

### Validator Fails with Syntax Error

**Symptom**: `syntax error in expression (error token is "0")`

**Cause**: Multi-line output from oc commands contains newlines

**Solution**: All validators now include `sanitize_number()` function:
```bash
sanitize_number() {
    local value="$1"
    value=$(echo "$value" | tr -d '[:space:]' | grep -o '^[0-9]*' || echo "0")
    echo "${value:-0}"
}
```

### Cluster Login Fails

**Symptom**: `error: The token provided is invalid or expired`

**Solution**: Obtain new token from OpenShift console:
1. Login to OpenShift web console
2. Click username → "Copy login command"
3. Update `SNO_TOKEN` or `HA_TOKEN` environment variable

### jq Parse Error

**Symptom**: `jq: parse error: Invalid string: control characters`

**Cause**: JSON output contains unescaped control characters

**Solution**: Validators now filter output to remove control characters before JSON generation

## Next Steps

1. **Complete Failed ADRs**: Address the 4 failed validations
2. **Finish Partial Implementations**: Complete the 13 partial ADRs
3. **Update Documentation**: Sync validation evidence to IMPLEMENTATION-TRACKER.md
4. **Dashboard Alignment**: Verify ADR Aggregator reflects actual cluster state
5. **HA Validation**: Run validation on HA cluster for topology comparison
6. **Continuous Validation**: Integrate into CI/CD pipeline for automatic validation

## References

- **IMPLEMENTATION-TRACKER**: `docs/adrs/IMPLEMENTATION-TRACKER.md`
- **Validation Reports**: `docs/adrs/audit-reports/`
- **ADR Aggregator**: https://adraggregator.com/roadmap
- **Topology Detection ADR**: `docs/adrs/058-topology-aware-deployment-validation.md`
