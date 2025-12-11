# Notebook Validator Image
# HYBRID APPROACH: RHOAI PyTorch base + validation tools
# See: ADR-029 - Notebook Validation with RHOAI ImageStreams
#
# Base: Red Hat OpenShift AI PyTorch 2025.1
# Adds: papermill, nbformat, nbconvert, oc CLI, kubectl
# Purpose: Execute and validate Jupyter notebooks in ArgoCD sync jobs

FROM image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/pytorch:2025.1

USER root

# Install OpenShift CLI (oc) and kubectl
RUN curl -sLo /tmp/oc.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz && \
    tar -xzf /tmp/oc.tar.gz -C /usr/local/bin/ oc kubectl && \
    chmod +x /usr/local/bin/oc /usr/local/bin/kubectl && \
    rm -f /tmp/oc.tar.gz

# Switch back to default notebook user (1000)
USER 1000

# Install notebook validation tools
# papermill: Execute notebooks programmatically
# nbformat: Read/write notebook files
# nbconvert: Convert notebooks to other formats
# ipykernel: Jupyter kernel for execution
RUN pip install --no-cache-dir \
    papermill==2.5.0 \
    nbformat==5.10.4 \
    nbconvert==7.16.4 \
    ipykernel==6.29.5 \
    && \
    python -m ipykernel install --user --name python3

# Verify installations
RUN papermill --version && \
    oc version --client && \
    kubectl version --client

WORKDIR /opt/app-root/src

# Default command (can be overridden by Job)
CMD ["/opt/app-root/bin/start-notebook.sh"]
