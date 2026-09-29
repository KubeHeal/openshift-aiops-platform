# AI/ML Workbench Access Guide

## Quick Access

**Direct URL** (Recommended):
```
https://self-healing-workbench-dev-self-healing-platform.apps.cluster-dzqpc.dzqpc.sandbox29.opentlc.com/
```

## What You Get

✅ **JupyterLab** - Full Jupyter notebook environment
✅ **PyTorch 2025.1** - Deep learning framework with GPU support
✅ **GPU Access** - 1x NVIDIA GPU allocated
✅ **20GB Storage** - Persistent volume for notebooks and data
✅ **50GB Model Storage** - Shared model artifacts volume
✅ **Git Integration** - Built-in Git support for version control

## Pre-installed Libraries

### Deep Learning
- PyTorch 2.x with CUDA support
- TensorFlow 2.x
- Keras

### Data Science
- NumPy, Pandas, Scikit-learn
- Matplotlib, Seaborn, Plotly
- Jupyter, JupyterLab

### ML/AI Tools
- XGBoost, LightGBM
- Statsmodels, Prophet
- Scikit-optimize

### Platform Integration
- Prometheus client
- Kubernetes Python client
- Requests, PyYAML

## Mounted Volumes

| Mount Point | Size | Purpose |
|------------|------|---------|
| `/opt/app-root/src/data` | 20GB | Notebook and data storage |
| `/opt/app-root/src/models` | 50GB | Model artifacts and checkpoints |
| `/opt/app-root/src/.jupyter/config` | - | Jupyter configuration |

## First Steps

### 1. Access the Workbench
```bash
# Open in browser
https://self-healing-workbench-dev-self-healing-platform.apps.cluster-dzqpc.dzqpc.sandbox29.opentlc.com/
```

### 2. Authenticate
- You'll be redirected to OpenShift OAuth login
- Use your OpenShift credentials
- You'll be redirected back to JupyterLab

### 3. Verify GPU Access
Create a new notebook and run:
```python
import torch
print(f"GPU Available: {torch.cuda.is_available()}")
print(f"GPU Count: {torch.cuda.device_count()}")
print(f"GPU Name: {torch.cuda.get_device_name(0)}")
```

### 4. Clone the Repository
In JupyterLab terminal:
```bash
cd /opt/app-root/src
git clone https://gitea-with-admin-gitea.apps.cluster-dzqpc.dzqpc.sandbox29.opentlc.com/user1/openshift-aiops-platform.git
```

## Common Tasks

### Create a New Notebook
1. Click "File" → "New" → "Notebook"
2. Select "Python 3" kernel
3. Start coding!

### Upload Files
1. Click the upload button in the file browser
2. Select files from your computer
3. Files will be saved to `/opt/app-root/src/data`

### Access Model Artifacts
```python
import os
model_path = "/opt/app-root/src/models"
files = os.listdir(model_path)
print(f"Available models: {files}")
```

### Run Terminal Commands
1. Click "File" → "New" → "Terminal"
2. Run any shell command
3. Example: `nvidia-smi` to check GPU

## Troubleshooting

### Can't Access Workbench
- Check if pod is running: `oc get pods -n self-healing-platform`
- Check pod logs: `oc logs -n self-healing-platform self-healing-workbench-dev-0 -c self-healing-workbench`
- Verify Route: `oc get route -n self-healing-platform self-healing-workbench-dev`

### GPU Not Available
- Check GPU node: `oc get nodes -L nvidia.com/gpu`
- Verify pod is on GPU node: `oc get pod -n self-healing-platform self-healing-workbench-dev-0 -o wide`
- Check GPU operator: `oc get pods -n nvidia-gpu-operator`

### Storage Issues
- Check PVCs: `oc get pvc -n self-healing-platform`
- Check disk usage: `df -h` in terminal
- Check PV status: `oc get pv | grep self-healing`

### Kernel Crashes
- Restart kernel: "Kernel" → "Restart Kernel"
- Check memory: `free -h` in terminal
- Check pod resources: `oc describe pod -n self-healing-platform self-healing-workbench-dev-0`

## Advanced Usage

### Connect to Coordination Engine
```python
import requests
import json

# Get coordination engine health
response = requests.get(
    'http://coordination-engine:8080/health',
    verify=False
)
health = response.json()
print(json.dumps(health, indent=2))
```

### Access Prometheus Metrics
```python
import requests

# Query Prometheus
response = requests.get(
    'https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091/api/v1/query',
    params={'query': 'up'},
    verify=False
)
print(response.json())
```

### Use S3 Storage
```python
import boto3
import os

# Get S3 credentials from environment
s3_endpoint = os.environ.get('S3_ENDPOINT')
s3_bucket = os.environ.get('S3_BUCKET')

# Create S3 client
s3 = boto3.client('s3', endpoint_url=s3_endpoint)
```

## Performance Tips

1. **Use GPU for Training**: PyTorch automatically uses GPU if available
2. **Monitor Resources**: Use `nvidia-smi` to monitor GPU usage
3. **Save Checkpoints**: Regularly save model checkpoints to `/opt/app-root/src/models`
4. **Use Persistent Storage**: Don't store large files in `/tmp`

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review pod logs: `oc logs -n self-healing-platform self-healing-workbench-dev-0`
3. Check cluster events: `oc get events -n self-healing-platform`
4. Review ADR-RHODS-NOTEBOOK-ROUTING for routing issues

## Related Documentation

- [ADR-RHODS-NOTEBOOK-ROUTING](docs/adrs/ADR-RHODS-NOTEBOOK-ROUTING.md) - Notebook routing configuration
- [ADR-STORAGE-STRATEGY](docs/adrs/ADR-STORAGE-STRATEGY.md) - Storage configuration
- [ADR-GPU-SCHEDULING](docs/adrs/ADR-GPU-SCHEDULING.md) - GPU node configuration

---

**Last Updated**: 2025-10-17
**Status**: Active
