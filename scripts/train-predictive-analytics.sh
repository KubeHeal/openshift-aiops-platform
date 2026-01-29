#!/bin/bash
# =============================================================================
# train-predictive-analytics.sh
# =============================================================================
# Repeatable script for training the predictive analytics model
# Supports both Prometheus and synthetic data sources
#
# Usage:
#   ./scripts/train-predictive-analytics.sh [OPTIONS]
#
# Options:
#   --data-source    Data source: prometheus|synthetic|hybrid (default: prometheus)
#   --hours          Training window in hours (default: 168 = 7 days)
#   --gpu            Use GPU node for training (requires gpu-training-pvc)
#   --wait           Wait for training to complete
#   --help           Show this help message
#
# Examples:
#   ./scripts/train-predictive-analytics.sh --data-source prometheus --hours 168
#   ./scripts/train-predictive-analytics.sh --data-source synthetic --wait
#   ./scripts/train-predictive-analytics.sh --gpu --hours 720
# =============================================================================

set -e

# Default values
DATA_SOURCE="${DATA_SOURCE:-prometheus}"
TRAINING_HOURS="${TRAINING_HOURS:-168}"
USE_GPU=false
WAIT_FOR_COMPLETION=false
NAMESPACE="self-healing-platform"
MODEL_NAME="predictive-analytics"
GIT_URL="${GIT_URL:-https://github.com/tosin2013/openshift-aiops-platform.git}"
GIT_REF="${GIT_REF:-main}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_help() {
    head -30 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --data-source)
            DATA_SOURCE="$2"
            shift 2
            ;;
        --hours)
            TRAINING_HOURS="$2"
            shift 2
            ;;
        --gpu)
            USE_GPU=true
            shift
            ;;
        --wait)
            WAIT_FOR_COMPLETION=true
            shift
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
done

# Validate data source
if [[ ! "$DATA_SOURCE" =~ ^(prometheus|synthetic|hybrid)$ ]]; then
    log_error "Invalid data source: $DATA_SOURCE"
    log_info "Valid options: prometheus, synthetic, hybrid"
    exit 1
fi

# Generate unique job name
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JOB_NAME="train-${MODEL_NAME}-${TIMESTAMP}"

log_info "=========================================="
log_info "Predictive Analytics Model Training"
log_info "=========================================="
log_info "Job Name:       $JOB_NAME"
log_info "Data Source:    $DATA_SOURCE"
log_info "Training Hours: $TRAINING_HOURS ($(echo "scale=1; $TRAINING_HOURS / 24" | bc) days)"
log_info "GPU Enabled:    $USE_GPU"
log_info "Namespace:      $NAMESPACE"
log_info "Git URL:        $GIT_URL"
log_info "Git Ref:        $GIT_REF"
log_info "=========================================="

# Check if oc is available
if ! command -v oc &> /dev/null; then
    log_error "oc CLI not found. Please install OpenShift CLI."
    exit 1
fi

# Check cluster connection
if ! oc whoami &> /dev/null; then
    log_error "Not logged into OpenShift cluster. Please run 'oc login'."
    exit 1
fi

log_info "Connected to cluster as: $(oc whoami)"

# Set PVC based on GPU usage
if [ "$USE_GPU" = true ]; then
    PVC_NAME="gpu-training-pvc"
    log_info "Using GPU training with GP3 storage ($PVC_NAME)"
else
    PVC_NAME="model-storage-pvc"
    log_info "Using CPU training with CephFS storage ($PVC_NAME)"
fi

# Create the NotebookValidationJob
log_info "Creating NotebookValidationJob: $JOB_NAME"

if [ "$USE_GPU" = true ]; then
    # GPU-enabled job
    cat <<EOF | oc create -f -
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    model-name: ${MODEL_NAME}
    data-source: ${DATA_SOURCE}
    training-type: gpu
spec:
  notebook:
    git:
      ref: ${GIT_REF}
      url: ${GIT_URL}
    path: notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb
  podConfig:
    containerImage: image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/notebook-validator:latest
    env:
    - name: DATA_SOURCE
      value: "${DATA_SOURCE}"
    - name: PROMETHEUS_URL
      value: "https://prometheus-k8s.openshift-monitoring.svc:9091"
    - name: TRAINING_HOURS
      value: "${TRAINING_HOURS}"
    - name: MODEL_NAME
      value: "${MODEL_NAME}"
    - name: PROMETHEUS_VERIFY_SSL
      value: "false"
    envFrom:
    - secretRef:
        name: model-storage-config
    nodeSelector:
      nvidia.com/gpu.present: "true"
    resources:
      limits:
        cpu: "4"
        memory: 8Gi
        nvidia.com/gpu: "1"
      requests:
        cpu: "2"
        memory: 4Gi
        nvidia.com/gpu: "1"
    serviceAccountName: self-healing-workbench
    tolerations:
    - effect: NoSchedule
      key: nvidia.com/gpu
      operator: Exists
    volumeMounts:
    - mountPath: /mnt/models
      name: model-storage
    volumes:
    - name: model-storage
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
  timeout: 45m
EOF
else
    # CPU-only job
    cat <<EOF | oc create -f -
apiVersion: mlops.mlops.dev/v1alpha1
kind: NotebookValidationJob
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    model-name: ${MODEL_NAME}
    data-source: ${DATA_SOURCE}
    training-type: cpu
spec:
  notebook:
    git:
      ref: ${GIT_REF}
      url: ${GIT_URL}
    path: notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb
  podConfig:
    containerImage: image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/notebook-validator:latest
    env:
    - name: DATA_SOURCE
      value: "${DATA_SOURCE}"
    - name: PROMETHEUS_URL
      value: "https://prometheus-k8s.openshift-monitoring.svc:9091"
    - name: TRAINING_HOURS
      value: "${TRAINING_HOURS}"
    - name: MODEL_NAME
      value: "${MODEL_NAME}"
    - name: PROMETHEUS_VERIFY_SSL
      value: "false"
    envFrom:
    - secretRef:
        name: model-storage-config
    resources:
      limits:
        cpu: "4"
        memory: 16Gi
      requests:
        cpu: "2"
        memory: 8Gi
    serviceAccountName: self-healing-workbench
    volumeMounts:
    - mountPath: /mnt/models
      name: model-storage
    volumes:
    - name: model-storage
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
  timeout: 30m
EOF
fi

log_success "NotebookValidationJob created: $JOB_NAME"

# Wait for completion if requested
if [ "$WAIT_FOR_COMPLETION" = true ]; then
    log_info "Waiting for training to complete..."

    while true; do
        STATUS=$(oc get notebookvalidationjob "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")

        case "$STATUS" in
            "Succeeded")
                log_success "Training completed successfully!"
                break
                ;;
            "Failed")
                log_error "Training failed!"
                log_info "Check logs with: oc logs ${JOB_NAME}-validation -n ${NAMESPACE}"
                exit 1
                ;;
            *)
                echo -ne "\r${BLUE}[INFO]${NC} Training status: $STATUS ... "
                sleep 30
                ;;
        esac
    done

    # Show final logs
    log_info "Training logs (last 30 lines):"
    oc logs "${JOB_NAME}-validation" -n "$NAMESPACE" --tail=30 2>/dev/null || true
fi

# Print monitoring commands
echo ""
log_info "=========================================="
log_info "Monitoring Commands:"
log_info "=========================================="
echo "# Check job status:"
echo "oc get notebookvalidationjob $JOB_NAME -n $NAMESPACE"
echo ""
echo "# View training logs:"
echo "oc logs ${JOB_NAME}-validation -n $NAMESPACE -f"
echo ""
echo "# Check model file after training:"
echo "oc exec -n $NAMESPACE deployment/model-troubleshooting-utilities -- ls -lh /mnt/models/${MODEL_NAME}/"
echo ""
echo "# Restart predictor to load new model:"
echo "oc delete pod -l serving.kserve.io/inferenceservice=${MODEL_NAME}-stable -n $NAMESPACE"
echo ""
log_info "=========================================="
