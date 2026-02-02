# Feature: Support initContainers in NotebookValidationJob podConfig

## Priority
**P1 (High)** - Widely applicable pattern for any user of the operator

## Summary
Add support for Kubernetes init containers in `NotebookValidationJob` pod configuration. This enables notebooks to wait for external dependencies (databases, APIs, storage) before execution, improving reliability in multi-component environments and cluster restart scenarios.

## Problem Statement

Currently, `NotebookValidationJob` pods start notebook execution immediately without ability to wait for dependencies. This causes failures when:

1. **External services are not ready** (databases, APIs, model endpoints, feature stores)
2. **Storage is slow to mount** (NFS, CephFS can take 2-5 minutes after cluster restart)
3. **Multi-cluster environments** have network delays between clusters
4. **CI/CD pipelines** run in ephemeral environments where service startup order varies

Users must implement workarounds like:
- Retrying notebook cells with try/except blocks (clutters notebook code)
- Adding sleep commands at notebook start (unreliable, wastes time)
- Running separate wait jobs before NotebookValidationJob (complex ArgoCD sync wave management)

## Proposed Solution

Add `initContainers []corev1.Container` field to `PodConfigSpec` in the NotebookValidationJob API:

```go
type PodConfigSpec struct {
    // ... existing fields (resources, serviceAccountName, volumes, etc.) ...

    // InitContainers run before notebook execution container starts.
    // Use init containers to wait for external dependencies, download datasets,
    // initialize workspaces, or perform other setup tasks.
    // +optional
    InitContainers []corev1.Container `json:"initContainers,omitempty"`
}
```

**Implementation Notes**:
- Operator passes init containers directly to pod spec (standard Kubernetes pattern)
- Users provide their own container images (operator has no dependency on specific images)
- Init containers run sequentially in specified order
- Main notebook container only starts after all init containers succeed

## Use Cases

### General Use Cases (Applicable to Any Organization)

1. **Wait for External Services** (Healthcare, Finance, E-commerce)
   - Database readiness checks before data analysis
   - API health checks before calling external systems
   - Message queue availability before processing streams
   - Feature store readiness before model training

2. **Download Large Datasets** (Research, Data Science Teams)
   - Pre-fetch training datasets from S3/cloud storage to PVCs
   - Download encrypted data and decrypt before notebook access
   - Clone additional repositories with shared utilities
   - Pull reference data from data lakes

3. **Storage Initialization** (Platform Teams, MLOps)
   - Wait for NFS/CephFS mounts after cluster restart
   - Verify PVC is bound and accessible before notebook writes
   - Create required directory structures
   - Initialize workspaces with templates

4. **Security and Compliance** (Healthcare, Financial Services)
   - Fetch secrets from vault before notebook execution
   - Verify compliance policies are loaded
   - Download encrypted patient/transaction data with proper authorization

5. **Multi-Cluster Scenarios** (Large Organizations)
   - Wait for cross-cluster network availability
   - Verify remote service endpoints are reachable
   - Sync data from central clusters to edge clusters

6. **CI/CD Pipeline Reliability** (DevOps Teams)
   - Wait for test databases to be ready in ephemeral environments
   - Verify container registry availability before pulling images
   - Check artifact storage accessibility

### Specific Example: openshift-aiops-platform

The [openshift-aiops-platform](https://github.com/KubeHeal/openshift-aiops-platform) is **one example user** of this operator that would benefit:

- **Cluster Restart Resilience**: Wait for Prometheus and ArgoCD before metrics collection notebooks
- **MLOps Workflow**: Ensure model registry is ready before training notebooks
- **Cross-Namespace Dependencies**: Platform services in openshift-monitoring must be available before analysis

See: [ADR-043: Deployment Stability Patterns](https://github.com/KubeHeal/openshift-aiops-platform/blob/main/docs/adrs/043-deployment-stability-health-checks.md)

## Implementation Examples

### Example 1: Wait for Database (PostgreSQL)

```yaml
apiVersion: notebook.validation.io/v1alpha1
kind: NotebookValidationJob
metadata:
  name: analyze-customer-data
spec:
  notebook:
    path: "analysis/customer-segmentation.ipynb"

  podConfig:
    # Wait for PostgreSQL before notebook execution
    initContainers:
    - name: wait-for-postgres
      image: postgres:15-alpine  # Standard PostgreSQL image
      command: [pg_isready, -h, postgres.database.svc, -p, "5432"]

    # Notebook will execute after database is ready
    resources:
      requests:
        memory: "2Gi"
        cpu: "1"
```

### Example 2: Download Dataset from S3

```yaml
apiVersion: notebook.validation.io/v1alpha1
kind: NotebookValidationJob
metadata:
  name: train-model-with-large-dataset
spec:
  notebook:
    path: "models/train-recommendation-model.ipynb"

  podConfig:
    # Download dataset before notebook starts
    initContainers:
    - name: download-dataset
      image: amazon/aws-cli
      command: [aws, s3, cp, s3://ml-datasets/training-2024.parquet, /data/]
      volumeMounts:
      - name: data-volume
        mountPath: /data
      env:
      - name: AWS_ACCESS_KEY_ID
        valueFrom:
          secretKeyRef:
            name: s3-credentials
            key: access-key
      - name: AWS_SECRET_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: s3-credentials
            key: secret-key

    volumes:
    - name: data-volume
      persistentVolumeClaim:
        claimName: datasets-pvc

    volumeMounts:
    - name: data-volume
      mountPath: /data
```

### Example 3: Wait for Multiple Services (API + Storage)

```yaml
apiVersion: notebook.validation.io/v1alpha1
kind: NotebookValidationJob
metadata:
  name: end-to-end-pipeline
spec:
  notebook:
    path: "pipelines/e2e-workflow.ipynb"

  podConfig:
    # Init containers run sequentially
    initContainers:
    # 1. Wait for API
    - name: wait-for-api
      image: curlimages/curl:latest
      command: [sh, -c]
      args:
      - |
        until curl -f http://ml-api.default.svc:8080/health; do
          echo "Waiting for ML API..."
          sleep 5
        done
        echo "API ready"

    # 2. Wait for storage mount
    - name: wait-for-storage
      image: busybox
      command: [sh, -c]
      args:
      - |
        until [ -d /mnt/models/.initialized ]; do
          echo "Waiting for storage initialization..."
          sleep 5
        done
        echo "Storage ready"
      volumeMounts:
      - name: model-storage
        mountPath: /mnt/models

    volumes:
    - name: model-storage
      persistentVolumeClaim:
        claimName: model-storage-pvc

    volumeMounts:
    - name: model-storage
      mountPath: /mnt/models
```

### Example 4: Using Custom Healthcheck Tool (openshift-aiops-platform)

```yaml
apiVersion: notebook.validation.io/v1alpha1
kind: NotebookValidationJob
metadata:
  name: prometheus-metrics-collection
  namespace: self-healing-platform
spec:
  notebook:
    path: "monitoring/collect-prometheus-metrics.ipynb"

  podConfig:
    # Use organization-specific healthcheck tool
    initContainers:
    - name: wait-for-prometheus
      image: quay.io/takinosh/openshift-cluster-health-mcp:ocp-4.18-latest
      command:
      - /usr/local/bin/healthcheck
      - --bearer-token-file=/var/run/secrets/kubernetes.io/serviceaccount/token
      - --insecure-skip-verify
      - --timeout=10s
      - --interval=15s
      - https://prometheus-k8s.openshift-monitoring.svc:9091/-/ready
```

**Note**: This example shows openshift-aiops-platform's custom healthcheck binary, but users can use any image with their own tools (curl, custom binaries, etc.).

## Technical Design

### API Changes

**File**: `api/v1alpha1/notebookvalidationjob_types.go`

```go
type PodConfigSpec struct {
    // Existing fields
    Resources          corev1.ResourceRequirements `json:"resources,omitempty"`
    ServiceAccountName string                      `json:"serviceAccountName,omitempty"`
    NodeSelector       map[string]string           `json:"nodeSelector,omitempty"`
    Tolerations        []corev1.Toleration         `json:"tolerations,omitempty"`
    Affinity           *corev1.Affinity            `json:"affinity,omitempty"`
    Volumes            []corev1.Volume             `json:"volumes,omitempty"`
    VolumeMounts       []corev1.VolumeMount        `json:"volumeMounts,omitempty"`

    // NEW: Init containers for pre-execution setup
    // +optional
    // +kubebuilder:validation:Optional
    InitContainers     []corev1.Container          `json:"initContainers,omitempty"`
}
```

### Controller Changes

**File**: `controllers/notebookvalidationjob_controller.go`

In the pod creation logic, add init containers to pod spec:

```go
func (r *NotebookValidationJobReconciler) createPod(
    ctx context.Context,
    job *validationv1alpha1.NotebookValidationJob,
) (*corev1.Pod, error) {

    pod := &corev1.Pod{
        ObjectMeta: metav1.ObjectMeta{
            Name:      job.Name + "-pod",
            Namespace: job.Namespace,
            Labels:    labels,
        },
        Spec: corev1.PodSpec{
            // Add init containers from podConfig
            InitContainers:     job.Spec.PodConfig.InitContainers,  // NEW

            Containers: []corev1.Container{
                {
                    Name:  "notebook-executor",
                    Image: job.Spec.Image,
                    // ... existing container spec ...
                },
            },
            // ... rest of pod spec ...
        },
    }

    return pod, nil
}
```

### Validation

Add validation for init containers (optional but recommended):

```go
// ValidateInitContainers ensures init containers have required fields
func validateInitContainers(initContainers []corev1.Container) error {
    for i, container := range initContainers {
        if container.Name == "" {
            return fmt.Errorf("initContainers[%d]: name is required", i)
        }
        if container.Image == "" {
            return fmt.Errorf("initContainers[%d]: image is required", i)
        }
    }
    return nil
}
```

## Testing Strategy

### Unit Tests

```go
func TestPodCreationWithInitContainers(t *testing.T) {
    job := &validationv1alpha1.NotebookValidationJob{
        Spec: validationv1alpha1.NotebookValidationJobSpec{
            PodConfig: validationv1alpha1.PodConfigSpec{
                InitContainers: []corev1.Container{
                    {
                        Name:    "wait-for-db",
                        Image:   "postgres:15-alpine",
                        Command: []string{"pg_isready", "-h", "postgres"},
                    },
                },
            },
        },
    }

    pod, err := createPod(context.TODO(), job)
    assert.NoError(t, err)
    assert.Len(t, pod.Spec.InitContainers, 1)
    assert.Equal(t, "wait-for-db", pod.Spec.InitContainers[0].Name)
}
```

### E2E Tests

1. **Test init container success**: Init container succeeds, notebook executes
2. **Test init container failure**: Init container fails, pod fails (notebook never runs)
3. **Test multiple init containers**: All run sequentially, notebook waits for all
4. **Test init container with volumes**: Init container can access mounted volumes

## Documentation Updates

### 1. API Reference

Document the new field in API documentation:

```markdown
## PodConfigSpec

| Field | Type | Description |
|-------|------|-------------|
| `initContainers` | `[]corev1.Container` | (Optional) Init containers run before notebook execution. Use to wait for dependencies, download data, or perform setup tasks. |
```

### 2. User Guide

Add new section: **"Using Init Containers for Dependency Management"**

```markdown
# Using Init Containers

Init containers run before your notebook executes. Common use cases:

- **Wait for services**: Databases, APIs, storage
- **Download data**: Large datasets from S3, GCS, Azure Blob
- **Setup tasks**: Create directories, fetch secrets, verify configuration

See examples in the [examples/init-containers](examples/init-containers/) directory.
```

### 3. Examples Directory

Create `examples/init-containers/` with:
- `wait-for-database.yaml`
- `download-dataset.yaml`
- `multi-step-init.yaml`

## Migration Path

**Backward Compatible**: Existing NotebookValidationJobs without `initContainers` continue to work unchanged.

No migration needed - this is a purely additive feature.

## Related Work

### Existing ADRs in jupyter-notebook-validator-operator

- **ADR-045: Volume and PVC Support** - Init containers can use volumes defined in podConfig
- **ADR-010: Observability** - Track init container duration in metrics
- **ADR-011: Error Handling** - Handle init container failures in status conditions

### Reference Implementations

- **Kubernetes Init Containers**: https://kubernetes.io/docs/concepts/workloads/pods/init-containers/
- **openshift-aiops-platform ADR-043**: Health check patterns using init containers

## Acceptance Criteria

- [ ] API field `initContainers` added to `PodConfigSpec`
- [ ] Controller creates pods with init containers from spec
- [ ] Unit tests cover init container creation and validation
- [ ] E2E tests verify init container success/failure scenarios
- [ ] API documentation updated with new field
- [ ] User guide includes init container usage examples
- [ ] Example YAML files provided for common patterns
- [ ] CRD updated with OpenAPI schema for init containers
- [ ] Webhook validation (if applicable) checks init container requirements

## Benefits

### For Users
- **Cleaner notebooks**: No need for retry logic in notebook cells
- **More reliable**: Guaranteed dependencies are ready before execution
- **Kubernetes-native**: Standard pattern familiar to platform engineers
- **Flexible**: Users choose their own tools and images

### For Operator
- **No new dependencies**: Leverages existing Kubernetes features
- **Simple implementation**: Pass-through to pod spec, minimal code changes
- **Widely applicable**: Benefits all users, not specific to one organization

## Alternatives Considered

### Alternative 1: Operator-Managed Retry Logic
Operator could retry notebook execution if it fails due to missing dependencies.

**Rejected**:
- Requires operator to distinguish "dependency not ready" from "notebook logic error"
- Adds complexity to operator error handling
- Less transparent to users than init containers

### Alternative 2: Pre-Job Hooks
Add a separate hook mechanism for running commands before notebook.

**Rejected**:
- Reinvents init containers, which already solve this problem
- Adds operator-specific concepts instead of using Kubernetes standards
- More implementation complexity

### Alternative 3: Do Nothing (Users Handle in Notebooks)
Let users implement retry logic in notebook cells.

**Rejected**:
- Clutters notebooks with infrastructure concerns
- Violates separation of concerns (notebook = data analysis, not dependency management)
- Unreliable (notebooks may fail before retry logic runs)

## Priority Justification

**Why P1 (High Priority)**:

1. **Broad Applicability**: Benefits any organization using the operator, not just one project
2. **Cluster Restart Resilience**: Critical for production environments (services start in unpredictable order)
3. **Cloud-Native Best Practice**: Init containers are standard Kubernetes pattern
4. **Low Implementation Cost**: Simple pass-through to pod spec, minimal code changes
5. **High User Value**: Improves reliability without requiring notebook code changes

## References

- **Kubernetes Init Containers**: https://kubernetes.io/docs/concepts/workloads/pods/init-containers/
- **openshift-aiops-platform**: https://github.com/KubeHeal/openshift-aiops-platform
- **ADR-043**: https://github.com/KubeHeal/openshift-aiops-platform/blob/main/docs/adrs/043-deployment-stability-health-checks.md
- **ADR-045 (Volume Support)**: Complementary feature for init container volume access

---

**Labels**: `enhancement`, `high-priority`, `api-change`, `kubernetes-native`

**Estimated Effort**: 3-5 days (API change, controller update, tests, docs, examples)
