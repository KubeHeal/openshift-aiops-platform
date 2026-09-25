# Notebook Validator Image
# Base: Red Hat OpenShift AI PyTorch Notebook (RHEL 9, enterprise supported)
# Purpose: Pre-install ML packages missing from base for full notebook validation
# Usage: Prebuilt image for NotebookValidationJob CRDs
# Reference: ADR-029 Jupyter Notebook Validator Operator + RHOAI ImageStreams
#
# Base image already includes:
#   - torch, numpy, pandas, scikit-learn, matplotlib, plotly
#   - papermill, nbformat, nbconvert, jupyter
#   - kubernetes, prometheus_client
#   - curl, wget, git, jq, oc CLI

FROM image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/pytorch:2025.2

USER root

# Install only the Python packages that are MISSING from base image
# These are required by the ML notebooks for full validation
RUN pip install --no-cache-dir \
    # Time series and forecasting
    statsmodels \
    prophet \
    # Anomaly detection
    pyod \
    # Gradient boosting models
    xgboost \
    lightgbm \
    # Visualization
    seaborn \
    # Model serving client
    kserve

# Switch back to default user for runtime
USER 1001

WORKDIR /opt/app-root/src

# Labels
LABEL name="notebook-validator" \
      version="1.0.0" \
      description="Validated notebook image for OpenShift AI Ops Platform" \
      maintainer="openshift-aiops-platform"

CMD ["start-notebook.sh"]
