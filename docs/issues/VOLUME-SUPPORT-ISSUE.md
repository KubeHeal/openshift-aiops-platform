# Volume Support Issue - Jupyter Notebook Validator Operator v1.0.4-ocp4.18

**Date**: December 1, 2025
**Operator Version**: v1.0.4-ocp4.18
**Issue Status**: Confirmed - Feature Not Implemented

## Summary

Volume support (volumes and volumeMounts) is **NOT working** in v1.0.4-ocp4.18. The operator accepts the configuration in the NotebookValidationJob spec but does not pass it through to the validation pods.

## Test Results

### Test Configuration
Created a NotebookValidationJob with custom volumes:

```yaml
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: test-volume-simple
  namespace: jupyter-notebook-validator-system
spec:
  podConfig:
    volumes:
    - name: test-data
      emptyDir: {}
    - name: test-models
      emptyDir: {}
    volumeMounts:
    - name: test-data
      mountPath: /mnt/data
    - name: test-models
      mountPath: /mnt/models
```

### Expected Behavior
The validation pod should have the custom volumes mounted at `/mnt/data` and `/mnt/models`.

### Actual Behavior
The validation pod was created with **only default volumes**:
- `workspace` (emptyDir)
- `jovyan-home` (emptyDir)
- `kube-api-access-*` (service account token)

**Custom volumes (`test-data`, `test-models`) were NOT present in the pod.**

### Evidence

#### Pod Volume Configuration
```bash
$ oc get pod test-volume-simple-validation -n jupyter-notebook-validator-system -o yaml | grep -A 30 "volumes:"
volumes:
  - emptyDir: {}
    name: workspace
  - emptyDir: {}
    name: jovyan-home
  - name: kube-api-access-mcstc
    projected:
      ...
```

#### Pod Volume Mounts
```bash
$ oc get pod test-volume-simple-validation -n jupyter-notebook-validator-system -o yaml | grep -A 15 "volumeMounts:"
volumeMounts:
- mountPath: /workspace
  name: workspace
- mountPath: /home/jovyan
  name: jovyan-home
- mountPath: /var/run/secrets/kubernetes.io/serviceaccount
  name: kube-api-access-mcstc
  readOnly: true
```

**No `/mnt/data` or `/mnt/models` mounts present.**

#### Operator Logs
No errors or warnings about volume configuration. The operator logs show normal reconciliation but no mention of processing custom volumes.

## Root Cause

The operator's pod creation logic does not include code to:
1. Read the `volumes` and `volumeMounts` fields from `spec.podConfig`
2. Merge custom volumes with default volumes
3. Add custom volume mounts to the validation pod containers

## Impact

Users **cannot** use persistent volumes or custom volume mounts with the operator. This affects:
- ✗ Mounting PVCs for model storage
- ✗ Mounting ConfigMaps for configuration
- ✗ Mounting Secrets for credentials
- ✗ Using emptyDir for shared data between init containers and main container
- ✗ Any use case requiring custom volume mounts

## Workaround

**None available.** The feature must be implemented in the operator code.

## Recommendation for Developers

The operator needs to be updated to:

1. **Parse volume configuration** from NotebookValidationJob spec:
   ```go
   volumes := nvj.Spec.PodConfig.Volumes
   volumeMounts := nvj.Spec.PodConfig.VolumeMounts
   ```

2. **Merge with default volumes**:
   ```go
   podSpec.Volumes = append(defaultVolumes, volumes...)
   ```

3. **Add volume mounts to containers**:
   ```go
   for _, container := range podSpec.Containers {
       container.VolumeMounts = append(container.VolumeMounts, volumeMounts...)
   }
   ```

4. **Validate volume references**:
   - Ensure all volumeMounts reference existing volumes
   - Check for mount path conflicts
   - Validate PVC existence if using persistentVolumeClaim

## Related Files

- Test manifest: `tests/test-volume-simple.yaml`
- Operator deployment: `manifests/jupyter-operator-direct-deployment.yaml`
- CRD definition: Applied from bundle v1.0.4-ocp4.18

## Next Steps

1. ✅ Issue documented for developers
2. ⏳ Waiting for operator code fix
3. ⏳ Test with updated operator version
4. ⏳ Resume implementation plan after fix is deployed

## Operator Installation Status

The operator itself is **fully operational**:
- ✅ Deployment: 1/1 READY
- ✅ Pods: 2/2 Running
- ✅ Controller: Started with leader election
- ✅ Webhooks: Enabled and serving
- ✅ CRD: Installed and functional

Only the volume support feature is not working.
