#!/bin/bash
# Manually trigger model training pipeline
#
# Two pipelines are available (see ADR-053):
#   model-training-pipeline      - CPU models (default)
#   model-training-pipeline-gpu  - GPU models (--gpu flag)

set -e

# Optional flags (for custom models or overrides)
USE_GPU="false"
NOTEBOOK_PATH=""
INFERENCE_SERVICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --notebook-path)
            NOTEBOOK_PATH="$2"
            shift 2
            ;;
        --inference-service)
            INFERENCE_SERVICE="$2"
            shift 2
            ;;
        --gpu)
            USE_GPU="true"
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ -z "$1" ]; then
    echo "Usage: $0 [OPTIONS] <model-name> [training-hours] [data-source] [namespace]"
    echo ""
    echo "Options (optional, for custom models or overrides):"
    echo "  --notebook-path PATH       Path to training notebook in repo (required for custom models)"
    echo "  --inference-service NAME   InferenceService name to restart (required for custom models)"
    echo "  --gpu                      Use GPU pipeline (model-training-pipeline-gpu)"
    echo ""
    echo "Examples:"
    echo "  $0 anomaly-detector                      # Train with default settings (24h, synthetic)"
    echo "  $0 anomaly-detector 168                  # Train with 1 week of data"
    echo "  $0 anomaly-detector 168 prometheus       # Train with 1 week of Prometheus data"
    echo "  $0 predictive-analytics 720 prometheus   # Train with 30 days of Prometheus data (auto-GPU)"
    echo "  $0 --notebook-path notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb \\"
    echo "     --inference-service my-model --gpu my-model 720"
    echo ""
    echo "Built-in models:"
    echo "  - anomaly-detector       (CPU pipeline)"
    echo "  - predictive-analytics   (GPU pipeline)"
    echo ""
    echo "Custom models: pass --notebook-path and --inference-service with any model name."
    echo "Add --gpu to use the GPU pipeline for custom models."
    echo ""
    echo "Training hours:"
    echo "  24   = 1 day (quick iteration, development)"
    echo "  168  = 1 week (weekly retraining)"
    echo "  720  = 30 days (monthly training, seasonal patterns)"
    echo ""
    echo "Data sources:"
    echo "  synthetic  = 100% synthetic data (development)"
    echo "  prometheus = Real Prometheus metrics + synthetic anomalies (production)"
    echo "  hybrid     = 50% Prometheus + 50% synthetic (staging)"
    exit 1
fi

MODEL_NAME=$1
TRAINING_HOURS="${2:-24}"
DATA_SOURCE="${3:-synthetic}"
NAMESPACE="${4:-self-healing-platform}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Set defaults for known models; require flags for custom models
case $MODEL_NAME in
    anomaly-detector)
        NOTEBOOK_PATH="${NOTEBOOK_PATH:-notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb}"
        INFERENCE_SERVICE="${INFERENCE_SERVICE:-anomaly-detector}"
        ;;
    predictive-analytics)
        NOTEBOOK_PATH="${NOTEBOOK_PATH:-notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb}"
        INFERENCE_SERVICE="${INFERENCE_SERVICE:-predictive-analytics}"
        USE_GPU="true"
        ;;
    *)
        if [ -z "$NOTEBOOK_PATH" ] || [ -z "$INFERENCE_SERVICE" ]; then
            echo "Error: Unknown model '$MODEL_NAME'. For custom models, pass --notebook-path and --inference-service."
            exit 1
        fi
        ;;
esac

# Select pipeline based on GPU flag
if [ "$USE_GPU" = "true" ]; then
    PIPELINE_NAME="model-training-pipeline-gpu"
    PIPELINE_TIMEOUT="45m"
else
    PIPELINE_NAME="model-training-pipeline"
    PIPELINE_TIMEOUT="30m"
fi

# Get Git configuration from values.yaml or use defaults
GIT_URL="${GIT_URL:-https://github.com/KubeHeal/openshift-aiops-platform.git}"
GIT_REF="${GIT_REF:-main}"

echo "=========================================="
echo "Triggering Model Training"
echo "=========================================="
echo "Model:             $MODEL_NAME"
echo "Notebook:          $NOTEBOOK_PATH"
echo "Inference service: $INFERENCE_SERVICE"
echo "Training hours:    $TRAINING_HOURS ($(echo "scale=1; $TRAINING_HOURS/24" | bc) days)"
echo "Data source:       $DATA_SOURCE"
echo "Pipeline:          $PIPELINE_NAME"
echo "Namespace:         $NAMESPACE"
echo "Git URL:           $GIT_URL"
echo "Git ref:           $GIT_REF"
echo "=========================================="
echo ""

# Confirm before proceeding
read -p "Proceed with training? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Create PipelineRun
echo ""
echo -e "${BLUE}Creating PipelineRun...${NC}"

PIPELINERUN=$(oc create -f - <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: train-${MODEL_NAME}-
  namespace: $NAMESPACE
  labels:
    model-name: $MODEL_NAME
    triggered-by: manual
spec:
  pipelineRef:
    name: $PIPELINE_NAME
  params:
    - name: model-name
      value: "$MODEL_NAME"
    - name: notebook-path
      value: "$NOTEBOOK_PATH"
    - name: data-source
      value: "$DATA_SOURCE"
    - name: training-hours
      value: "$TRAINING_HOURS"
    - name: inference-service-name
      value: "$INFERENCE_SERVICE"
    - name: health-check-enabled
      value: "true"
    - name: git-url
      value: "$GIT_URL"
    - name: git-ref
      value: "$GIT_REF"
  timeout: $PIPELINE_TIMEOUT
EOF
)

PIPELINERUN_NAME=$(echo "$PIPELINERUN" | awk '{print $1}')

echo -e "${GREEN}PipelineRun created: $PIPELINERUN_NAME${NC}"
echo ""

# Check if tkn is available
if command -v tkn &> /dev/null; then
    echo "Follow logs with:"
    echo "  tkn pipelinerun logs $PIPELINERUN_NAME -f -n $NAMESPACE"
    echo ""
    echo -e "${YELLOW}Would you like to follow the logs now? (y/N)${NC}"
    read -p "" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        tkn pipelinerun logs $PIPELINERUN_NAME -f -n $NAMESPACE
    fi
else
    echo "To view logs, install Tekton CLI or use:"
    echo "  oc logs -n $NAMESPACE -l tekton.dev/pipelineRun=$PIPELINERUN_NAME -f"
fi

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo "1. Monitor training:"
echo "   tkn pipelinerun logs $PIPELINERUN_NAME -f -n $NAMESPACE"
echo ""
echo "2. Check status:"
echo "   ./scripts/check-training-status.sh"
echo ""
echo "3. Validate model after training:"
echo "   ./scripts/validate-models.sh"
echo ""
echo "4. Test model endpoint:"
echo "   ./scripts/test-model-endpoint.sh $MODEL_NAME"
