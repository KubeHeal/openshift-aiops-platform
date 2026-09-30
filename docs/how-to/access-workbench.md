# How to Access the Self-Healing Workbench

## Overview

This guide provides comprehensive step-by-step instructions for accessing and using the Self-Healing Platform workbench through both RHODS and terminal methods. The workbench is your development environment for creating AI/ML models and self-healing algorithms.

## Prerequisites

- **OpenShift Cluster Access**: Access to an OpenShift 4.20+ cluster with RHODS installed
- **CLI Tools**: `oc` CLI tool installed and configured on your local machine
- **Namespace Access**: User permissions for the `self-healing-platform` namespace
- **Browser**: Modern web browser for RHODS dashboard access (optional for terminal method)

## Method 1: RHODS Dashboard Access (Recommended for Web Users)

### Step 1: Access the RHODS Dashboard

Navigate to the RHODS dashboard URL:

```
https://rhods-dashboard-redhat-ods-applications.apps.cluster-dzqpc.dzqpc.sandbox29.opentlc.com/
```

Log in with your OpenShift credentials. You'll see the RHODS home page with available workbenches.

### Step 2: Locate the Self-Healing Workbench

In the RHODS dashboard:

1. Look for **"self-healing-workbench-dev"** in the workbench list
2. Check the status indicator:
   - **Green (Running)**: Workbench is ready to use
   - **Gray (Stopped)**: Workbench needs to be started
   - **Yellow (Starting)**: Workbench is initializing

### Step 3: Start the Workbench (if needed)

If the workbench is stopped:

1. Click the **Start** button next to the workbench
2. Wait for the status to change to **Running** (typically 1-2 minutes)
3. You'll see a **Connect** button appear when ready

### Step 4: Connect via Web Interface

Click the **Connect** button to open JupyterLab:

1. The JupyterLab interface will load in a new tab
2. You'll see the file browser on the left
3. The terminal and notebook editors are available in the main area

**Note**: The web interface may have configuration complexities with the PyTorch base image. If you experience issues, use terminal access (Method 2) instead.

## Method 2: Terminal Access via `oc` CLI (Recommended for Power Users)

Terminal access provides immediate productivity and full control over your development environment.

### Step 1: Verify Workbench Status

Check if the workbench pod is running:

```bash
# List workbench pods
oc get pods -n self-healing-platform | grep workbench

# Expected output:
# self-healing-workbench-dev-0   2/2     Running     0          10m
```

If the pod is not running, check the notebook resource:

```bash
# Check notebook status
oc get notebook -n self-healing-platform

# Get detailed information
oc describe notebook self-healing-workbench-dev -n self-healing-platform
```

### Step 2: Connect to the Workbench Terminal

Open a terminal connection to the workbench:

```bash
# Connect to the workbench container
oc exec -it self-healing-workbench-dev-0 -c self-healing-workbench \
  -n self-healing-platform -- /bin/bash
```

You should see a prompt like:
```
(base) 1001@self-healing-workbench-dev-0:/opt/app-root/src$
```

### Step 3: Verify Your Environment

Verify that all required components are available:

```bash
# Check Python version
python --version
# Expected: Python 3.11.x or higher

# Check PyTorch installation
python -c "import torch; print(f'PyTorch: {torch.__version__}')"
# Expected: PyTorch: 2.x.x

# Check available packages
pip list | grep -E "(torch|numpy|pandas|scikit-learn|prometheus)"

# Verify mounted volumes
ls -la /opt/app-root/src/
# Should show: data/, models/, and other directories
```

### Step 4: Verify GPU Access (Optional)

If GPU nodes are available:

```bash
# Check CUDA availability
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"

# Check GPU count
python -c "import torch; print(f'GPU count: {torch.cuda.device_count()}')"

# Test GPU tensor creation
python -c "
import torch
if torch.cuda.is_available():
    x = torch.randn(3, 3).cuda()
    print(f'GPU tensor created: {x.device}')
else:
    print('CUDA not available - CPU mode')
"
```

## Working in the Workbench

### Clone the Repository

Once connected to the workbench, clone the Self-Healing Platform repository:

```bash
# Inside the workbench terminal
git clone https://gitea-with-admin-gitea.apps.cluster-dzqpc.dzqpc.sandbox29.opentlc.com/user1/openshift-aiops-platform.git

# Navigate to the project directory
cd openshift-aiops-platform

# Verify the clone
ls -la
```

### Set Up Development Environment

Install project dependencies and create working directories:

```bash
# Install project requirements
pip install --user -r requirements.txt

# Install additional ML libraries
pip install --user \
    statsmodels>=0.14.0 \
    prophet>=1.1.4 \
    tslearn>=0.6.0 \
    pyod>=1.1.0 \
    xgboost>=2.0.0 \
    prometheus-client>=0.17.0

# Create working directories
mkdir -p notebooks/experiments
mkdir -p data/training
mkdir -p data/datasets
mkdir -p models/checkpoints
```

### Understand the Project Structure

Familiarize yourself with the repository layout:

```bash
# View the project structure
tree -L 2 -I '__pycache__|*.pyc'

# Or use ls for a simpler view
ls -la
```

Expected structure:
```
openshift-aiops-platform/
├── docs/                    # Documentation and ADRs
│   ├── adrs/               # Architectural Decision Records
│   ├── tutorials/          # Learning guides
│   ├── how-to/             # Task-oriented guides
│   └── explanation/        # Conceptual documentation
├── src/                    # Source code
│   └── coordination-engine/ # Self-healing logic
├── k8s/                    # Kubernetes manifests
├── notebooks/              # Jupyter notebooks (create this)
├── data/                   # Training data (create this)
├── models/                 # Trained models (create this)
└── requirements.txt        # Python dependencies
```

## Persistent Storage

The workbench has access to persistent volumes for storing your work and data:

### Data Volume (5Gi)

```bash
# Location: /opt/app-root/src/data
# Use for: Training datasets, notebooks, temporary files

# Check available space
df -h /opt/app-root/src/data

# List contents
ls -la /opt/app-root/src/data

# Create subdirectories for organization
mkdir -p /opt/app-root/src/data/notebooks
mkdir -p /opt/app-root/src/data/datasets
mkdir -p /opt/app-root/src/data/experiments
```

### Models Volume (10Gi, ReadWriteMany)

```bash
# Location: /opt/app-root/src/models
# Use for: Trained models, shared artifacts, checkpoints
# Note: ReadWriteMany means multiple pods can access simultaneously

# Check available space
df -h /opt/app-root/src/models

# List contents
ls -la /opt/app-root/src/models

# Create subdirectories for organization
mkdir -p /opt/app-root/src/models/checkpoints
mkdir -p /opt/app-root/src/models/trained
mkdir -p /opt/app-root/src/models/artifacts
```

### Storage Best Practices

```bash
# Monitor storage usage
du -sh /opt/app-root/src/data/*
du -sh /opt/app-root/src/models/*

# Clean up old files
find /opt/app-root/src/data -type f -mtime +30 -delete

# Archive large datasets
tar -czf /opt/app-root/src/data/archive_$(date +%Y%m%d).tar.gz /opt/app-root/src/data/old_datasets/
```

## Common Tasks

### Install Additional Packages

```bash
# Install a single package in user directory
pip install --user package_name

# Install from requirements file
pip install --user -r requirements.txt

# Install specific version
pip install --user package_name==1.2.3

# Upgrade a package
pip install --user --upgrade package_name
```

### Save Your Work

```bash
# Save notebooks to persistent storage
cp my_notebook.ipynb /opt/app-root/src/data/notebooks/

# Save trained models
cp trained_model.pkl /opt/app-root/src/models/trained/

# Save experiment results
cp experiment_results.json /opt/app-root/src/data/experiments/

# Backup your work
tar -czf /opt/app-root/src/data/backup_$(date +%Y%m%d).tar.gz \
  /opt/app-root/src/data/notebooks/ \
  /opt/app-root/src/models/
```

### Start Jupyter Lab (Optional)

If you prefer web-based notebook development:

```bash
# Start Jupyter Lab server
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --allow-origin='*'

# Access via browser (from your local machine)
# Forward the port: oc port-forward pod/self-healing-workbench-dev-0 8888:8888
# Then open: http://localhost:8888
```

### Work with Git

```bash
# Configure git (if not already configured)
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Create a new branch for your work
git checkout -b feature/my-anomaly-detector

# Commit your changes
git add .
git commit -m "Add anomaly detection model"

# Push to remote
git push origin feature/my-anomaly-detector
```

## Troubleshooting

### Issue: Workbench Pod Not Running

**Symptoms**: Pod status shows "Pending", "CrashLoopBackOff", or "Error"

**Solution**:

```bash
# Check pod status in detail
oc describe pod self-healing-workbench-dev-0 -n self-healing-platform

# Check recent events
oc get events -n self-healing-platform --sort-by='.lastTimestamp' | head -20

# Check pod logs
oc logs self-healing-workbench-dev-0 -c self-healing-workbench -n self-healing-platform

# Restart the workbench
oc delete pod self-healing-workbench-dev-0 -n self-healing-platform

# Wait for new pod to start
oc get pods -n self-healing-platform -w
```

### Issue: Cannot Connect to Workbench

**Symptoms**: Connection timeout or "Connection refused"

**Solution**:

```bash
# Verify pod is running
oc get pods -n self-healing-platform | grep workbench

# Check if pod is ready
oc get pod self-healing-workbench-dev-0 -n self-healing-platform -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# Check pod events
oc describe pod self-healing-workbench-dev-0 -n self-healing-platform

# Try port-forwarding as alternative
oc port-forward pod/self-healing-workbench-dev-0 8888:8888 -n self-healing-platform
```

### Issue: Permission Denied Errors

**Symptoms**: "Permission denied" when accessing files or directories

**Solution**:

```bash
# Check current user
whoami
id

# Verify volume permissions
ls -la /opt/app-root/src/

# Check file ownership
ls -la /opt/app-root/src/data/
ls -la /opt/app-root/src/models/

# Fix permissions if needed
chmod 755 /opt/app-root/src/data
chmod 755 /opt/app-root/src/models
```

### Issue: Package Installation Fails

**Symptoms**: "ERROR: Could not find a version that satisfies the requirement"

**Solution**:

```bash
# Use user installation (recommended)
pip install --user package_name

# Check pip configuration
pip config list

# Clear pip cache
pip cache purge

# Upgrade pip
pip install --user --upgrade pip

# Try installing from specific index
pip install --user -i https://pypi.org/simple/ package_name
```

### Issue: Git Clone or Push Fails

**Symptoms**: "fatal: could not read Username" or authentication errors

**Solution**:

```bash
# Configure git credentials
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# For private repositories, use token authentication
git clone https://username:token@gitea-server/repo.git

# Or use SSH (if configured)
git clone git@gitea-server:user1/openshift-aiops-platform.git

# Check git configuration
git config --list
```

### Issue: Out of Storage Space

**Symptoms**: "No space left on device" errors

**Solution**:

```bash
# Check storage usage
df -h /opt/app-root/src/

# Find large files
find /opt/app-root/src -type f -size +100M

# Clean up old files
find /opt/app-root/src/data -type f -mtime +30 -delete

# Archive and remove old datasets
tar -czf /opt/app-root/src/data/archive_old.tar.gz /opt/app-root/src/data/old_data/
rm -rf /opt/app-root/src/data/old_data/
```

### Issue: GPU Not Available

**Symptoms**: `torch.cuda.is_available()` returns False

**Solution**:

```bash
# Check if GPU nodes are available in cluster
oc get nodes -L nvidia.com/gpu

# Check if GPU operator is installed
oc get pods -n nvidia-gpu-operator

# Check pod GPU requests
oc describe pod self-healing-workbench-dev-0 -n self-healing-platform | grep -A 5 "Limits\|Requests"

# Note: GPU availability depends on cluster configuration
# CPU-only mode is fully supported
```

## Next Steps

Now that you can access the workbench, explore these resources:

1. **[Getting Started Tutorial](../tutorials/getting-started.md)** - Step-by-step introduction
2. **[Workbench Development Guide](../tutorials/workbench-development-guide.md)** - Deep dive into development
3. **[Architecture Overview](../explanation/architecture-overview.md)** - Understand the system design
4. **[ADR Reference](../reference/adrs.md)** - Review architectural decisions

## Support

If you encounter issues not covered here:

1. **Check the logs**: `oc logs self-healing-workbench-dev-0 -c self-healing-workbench -n self-healing-platform`
2. **Review ADR-011**: [Self-Healing Workbench Base Image](../adrs/011-self-healing-workbench-base-image.md)
3. **Check cluster status**: `oc status -n self-healing-platform`
4. **Contact the platform team** for additional assistance
