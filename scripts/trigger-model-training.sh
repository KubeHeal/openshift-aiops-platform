#!/bin/bash
# Manually trigger model training pipeline

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <model-name> [training-hours] [data-source] [namespace]"
    echo ""
    echo "Examples:"
    echo "  $0 anomaly-detector                      # Train with default settings (24h, synthetic)"
    echo "  $0 anomaly-detector 168                  # Train with 1 week of data"
    echo "  $0 anomaly-detector 168 prometheus       # Train with 1 week of Prometheus data"
    echo "  $0 predictive-analytics 720 prometheus   # Train with 30 days of Prometheus data"
    echo ""
    echo "Supported models:"
    echo "  - anomaly-detector"
    echo "  - predictive-analytics"
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

# Determine notebook path and InferenceService based on model name
case $MODEL_NAME in
    anomaly-detector)
        NOTEBOOK_PATH="notebooks/02-anomaly-detection/01-isolation-forest-implementation.ipynb"
        INFERENCE_SERVICE="anomaly-detector"
        ;;
    predictive-analytics)
        NOTEBOOK_PATH="notebooks/02-anomaly-detection/05-predictive-analytics-kserve.ipynb"
        INFERENCE_SERVICE="predictive-analytics"
        ;;
    *)
        echo "Error: Unknown model '$MODEL_NAME'"
        echo "Supported models: anomaly-detector, predictive-analytics"
        exit 1
        ;;
esac

# Get Git configuration from values.yaml or use defaults
GIT_URL="${GIT_URL:-https://github.com/KubeHeal/openshift-aiops-platform.git}"
GIT_REF="${GIT_REF:-main}"

echo "=========================================="
echo "Triggering Model Training"
echo "=========================================="
echo "Model:          $MODEL_NAME"
echo "Notebook:       $NOTEBOOK_PATH"
echo "Training hours: $TRAINING_HOURS ($(echo "scale=1; $TRAINING_HOURS/24" | bc) days)"
echo "Data source:    $DATA_SOURCE"
echo "Namespace:      $NAMESPACE"
echo "Git URL:        $GIT_URL"
echo "Git ref:        $GIT_REF"
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
    name: model-training-pipeline
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
  timeout: 45m
EOF
)

PIPELINERUN_NAME=$(echo "$PIPELINERUN" | awk '{print $1}')

echo -e "${GREEN}✅ PipelineRun created: $PIPELINERUN_NAME${NC}"
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
