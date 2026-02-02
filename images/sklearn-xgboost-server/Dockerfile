# Custom sklearn server with XGBoost support
# Extends the official KServe sklearn server to add XGBoost
FROM kserve/sklearnserver:latest

USER root

# Install XGBoost
RUN pip install --no-cache-dir xgboost lightgbm

# Switch back to non-root user
USER 1000

# Labels
LABEL name="sklearn-xgboost-server" \
      description="KServe sklearn server with XGBoost support" \
      maintainer="openshift-aiops-platform"
