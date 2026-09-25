# Notebook Validator Image
# Base: Red Hat OpenShift AI PyTorch Notebook (enterprise supported)
# Adds: papermill, nbformat, nbconvert, oc CLI, kubectl for validation
# Usage: Prebuilt image for NotebookValidationJob CRDs
# Reference: ADR-029 Jupyter Notebook Validator Operator + RHOAI ImageStreams

FROM image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/pytorch:2025.2

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install OpenShift CLI (oc)
RUN curl -sLO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz \
    && tar -xzf openshift-client-linux.tar.gz -C /usr/local/bin/ \
    && rm openshift-client-linux.tar.gz \
    && chmod +x /usr/local/bin/oc

# Install kubectl
RUN curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl

USER ${NB_UID}

# Install Python packages for OpenShift validation and ML workflows
# Note: RHOAI PyTorch base has torch, numpy, pandas but missing some ML viz/utils
RUN pip install --no-cache-dir \
    papermill==2.5.0 \
    nbformat==5.9.2 \
    nbconvert==7.14.0 \
    kubernetes==28.1.0 \
    openshift==0.13.2 \
    prometheus-api-client==0.5.5 \
    pyyaml==6.0.1 \
    seaborn \
    joblib \
    requests

# Set working directory
WORKDIR /workspace

# Add health check script
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/healthcheck.sh || true

# Labels
LABEL name="notebook-validator" \
      version="1.0.0" \
      description="Prebuilt notebook validation image for OpenShift AI Ops Platform" \
      maintainer="openshift-aiops-platform" \
      io.openshift.expose-services="" \
      io.k8s.description="Jupyter notebook validator with OpenShift tools" \
      io.k8s.display-name="Notebook Validator" \
      io.openshift.tags="jupyter,notebook,validation,openshift,ai-ops"

# Default command
CMD ["start-notebook.sh"]
