# ADR-021: Tekton Pipeline for Post-Deployment Validation

**Status:** ACCEPTED (Infrastructure Validation) | SUPERSEDED (Notebook Validation by ADR-029)
**Date:** 2025-10-31
**Updated:** 2025-11-18 (Notebook validation superseded by ADR-029)
**Decision Makers:** Architecture Team
**Consulted:** DevOps Team, ML Engineering
**Informed:** Operations Team

## Implementation Status
**Status:** ✅ IMPLEMENTED
**Verification Date:** 2026-01-25
**Implementation Score:** 9.0/10
**Verified On:** SNO + HA clusters
**Evidence:** 4 Tekton pipelines operational (deployment-validation, model-serving, s3-configuration, platform-readiness). Infrastructure validation fully deployed.

## Superseded Notice

**Notebook Validation Responsibilities (SUPERSEDED by ADR-029)**:
- Jupyter notebook execution and validation moved to Jupyter Notebook Validator Operator
- NotebookValidationJob CRDs provide declarative notebook validation
- See [ADR-029: Jupyter Notebook Validator Operator](029-jupyter-notebook-validator-operator.md)

**Retained Responsibilities (ACTIVE)**:
- Infrastructure validation (prerequisites, operators, storage, monitoring)
- Model serving validation (KServe InferenceServices, endpoints, metrics)
- Coordination engine validation (deployment, health, API, database)
- End-to-end platform health checks

## Context

The OpenShift AIOps Self-Healing Platform includes model serving services (KServe) that require comprehensive post-deployment validation. After the Validated Patterns framework deploys the platform via `make -f common/Makefile operator-deploy`, we need automated validation to ensure:

1. **Model Serving Services**: KServe InferenceServices are deployed and responding correctly
2. **Coordination Engine**: Health checks and API endpoints are functional
3. **Storage Integration**: Object storage (ODF/S3) is accessible and configured
4. **Monitoring Stack**: Prometheus and observability components are operational
5. **End-to-End Workflows**: Complete data pipeline from ingestion to model inference works

### Current Validation Gaps

- Manual validation requires multiple `oc` commands and manual testing
- No automated health checks for model serving endpoints
- Difficult to validate complex multi-component interactions
- No CI/CD integration for deployment validation
- Lack of repeatable validation for different environments

## Decision

Implement a **Tekton Pipeline for Post-Deployment Validation** that automatically validates the entire platform after deployment, with specific focus on model serving services and end-to-end workflows.

### Pipeline Architecture

```
tekton/
├── pipelines/
│   ├── deployment-validation-pipeline.yaml    # Main validation pipeline
│   └── model-serving-validation-pipeline.yaml # Model serving specific
├── tasks/
│   ├── validate-prerequisites.yaml            # Cluster readiness
│   ├── validate-operators.yaml                # Required operators
│   ├── validate-storage.yaml                  # ODF/S3 connectivity
│   ├── validate-model-serving.yaml            # KServe InferenceServices
│   ├── validate-coordination-engine.yaml      # Coordination engine health
│   ├── validate-monitoring.yaml               # Prometheus/observability
│   ├── validate-end-to-end.yaml               # Complete workflows
│   └── generate-validation-report.yaml        # Summary report
├── triggers/
│   ├── deployment-validation-trigger.yaml     # Webhook trigger
│   └── manual-validation-trigger.yaml         # Manual execution
└── README.md
```

### Validation Pipeline Workflow

```
1. Prerequisites Check
   ├─ Cluster connectivity
   ├─ Required tools (oc, kubectl, helm)
   └─ RBAC permissions

2. Operator Validation
   ├─ OpenShift GitOps
   ├─ OpenShift AI
   ├─ KServe
   ├─ GPU Operator
   └─ ODF Operator

3. Storage Validation
   ├─ ODF cluster health
   ├─ S3 endpoint connectivity
   ├─ RWO storage class
   └─ RWX storage class

4. Model Serving Validation
   ├─ InferenceService deployment
   ├─ Model endpoint availability
   ├─ Inference request/response
   └─ Model performance metrics

5. Coordination Engine Validation
   ├─ Deployment status
   ├─ Health check endpoint
   ├─ API connectivity
   └─ Database connectivity

6. Monitoring Validation
   ├─ Prometheus scrape targets
   ├─ Alert rules
   ├─ Grafana dashboards
   └─ Log aggregation

7. End-to-End Workflow Validation
   ├─ Data ingestion pipeline
   ├─ Model inference pipeline
   ├─ Result storage
   └─ Monitoring integration

8. Report Generation
   ├─ Validation summary
   ├─ Pass/fail status
   ├─ Performance metrics
   └─ Remediation recommendations
```

### Tekton Task Examples

**Model Serving Validation Task**:
```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: validate-model-serving
spec:
  steps:
    - name: check-inferenceservices
      image: quay.io/openshift/origin-cli:latest
      script: |
        #!/bin/bash
        set -e

        # Check InferenceService deployment
        oc get inferenceservices -n self-healing-platform

        # Verify model endpoints are ready
        oc get inferenceservices -n self-healing-platform \
          -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

        # Test model inference
        MODEL_URL=$(oc get inferenceservice -n self-healing-platform -o jsonpath='{.items[0].status.url}')
        curl -v "${MODEL_URL}/v1/models/model-name:predict" \
          -H "Content-Type: application/json" \
          -d '{"instances": [[1.0, 2.0, 3.0]]}'
```

**Coordination Engine Validation Task**:
```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: validate-coordination-engine
spec:
  steps:
    - name: check-deployment
      image: quay.io/openshift/origin-cli:latest
      script: |
        #!/bin/bash
        set -e

        # Check deployment status
        oc get deployment coordination-engine -n self-healing-platform

        # Verify pods are running
        oc get pods -n self-healing-platform -l app=coordination-engine

        # Test health endpoint
        POD=$(oc get pods -n self-healing-platform -l app=coordination-engine -o jsonpath='{.items[0].metadata.name}')
        oc exec -n self-healing-platform "$POD" -- curl -s http://localhost:8080/health
```

### Execution Triggers

**Manual Execution** (End-user validation):
```bash
# Run validation pipeline after deployment
tkn pipeline start deployment-validation-pipeline \
  --workspace name=shared-workspace,volumeClaimTemplateFile=pvc.yaml \
  --showlog
```

**Automated Execution** (CI/CD integration):
- Triggered automatically after `make -f common/Makefile operator-deploy`
- Webhook integration with ArgoCD for post-sync validation
- Scheduled validation runs (daily/weekly health checks)

### Validation Report

The pipeline generates a comprehensive validation report:

```json
{
  "timestamp": "2025-10-31T10:30:00Z",
  "deployment_status": "SUCCESS",
  "validation_results": {
    "prerequisites": { "status": "PASS", "checks": 5 },
    "operators": { "status": "PASS", "checks": 5 },
    "storage": { "status": "PASS", "checks": 4 },
    "model_serving": { "status": "PASS", "checks": 4 },
    "coordination_engine": { "status": "PASS", "checks": 3 },
    "monitoring": { "status": "PASS", "checks": 4 },
    "end_to_end": { "status": "PASS", "checks": 3 }
  },
  "performance_metrics": {
    "model_inference_latency_ms": 45,
    "coordination_engine_response_time_ms": 120,
    "storage_throughput_mbps": 850
  },
  "recommendations": []
}
```

## Consequences

### Positive Consequences

- ✅ Automated validation ensures deployment quality
- ✅ Early detection of model serving issues
- ✅ Comprehensive health checks for all components
- ✅ Repeatable validation across environments
- ✅ CI/CD integration for continuous validation
- ✅ Clear pass/fail criteria for deployments
- ✅ Performance metrics for optimization

### Negative Consequences

- ⚠️ Additional Tekton pipeline maintenance
- ⚠️ Requires Tekton Pipelines operator installation
- ⚠️ Validation pipeline execution time (10-15 minutes)
- ⚠️ Requires test data for end-to-end validation

## Implementation Tasks

1. Create Tekton tasks for each validation component
2. Implement deployment-validation-pipeline
3. Create model-serving-validation-pipeline
4. Set up webhook triggers for ArgoCD integration
5. Implement validation report generation
6. Create runbooks for remediation
7. Document validation procedures for end-users
8. Integrate with CI/CD pipeline

## Related ADRs

- **ADR-029**: Jupyter Notebook Validator Operator (SUPERSEDES notebook validation from this ADR)
- **ADR-019**: Validated Patterns Framework Adoption
- **ADR-020**: Bootstrap Deployment and Deletion Lifecycle
- **ADR-004**: KServe Model Serving
- **ADR-007**: Prometheus Monitoring Integration
- **ADR-014**: OpenShift AIOps Platform MCP Server Integration

## References

- [Tekton Pipelines Documentation](https://tekton.dev/docs/)
- [OpenShift Pipelines](https://docs.openshift.com/pipelines/latest/index.html)
- [KServe Documentation](https://kserve.github.io/website/)
- [Validated Patterns Framework](https://validatedpatterns.io/)

## Approval

- **Architecture Team**: Approved
- **DevOps Team**: Approved
- **Date**: 2025-10-31
