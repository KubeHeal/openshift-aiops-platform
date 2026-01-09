"""
Model Storage Helpers for OpenShift AI Ops Platform

This module provides utilities for saving and loading models with support for
both PVC storage (primary) and S3 storage (backwards compatibility).

Author: OpenShift AI Ops Platform Team
License: GPL-3.0
"""

import os
import joblib
import logging
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

# Storage Paths
PVC_MODEL_PATH = Path("/mnt/models")  # Shared PVC mount (primary)
LOCAL_MODEL_PATH = Path("/opt/app-root/src/models")  # Local workbench storage (legacy)


def validate_kserve_model_structure(model_dir: Path, model_name: str) -> bool:
    """
    Validate that model directory structure is KServe-compatible.

    KServe Requirements:
    - Only ONE .pkl file per model directory
    - File must be named 'model.pkl' (recommended)
    - Directory path: /mnt/models/{model-name}/

    Args:
        model_dir: Path to model directory
        model_name: Name of the model

    Returns:
        True if valid, raises exception if invalid

    Raises:
        FileNotFoundError: If model directory doesn't exist or no .pkl files found
        RuntimeError: If multiple .pkl files found (KServe incompatible)

    Example:
        >>> model_dir = Path("/mnt/models/anomaly-detector")
        >>> validate_kserve_model_structure(model_dir, "anomaly-detector")
        ✅ KServe validation passed: /mnt/models/anomaly-detector/model.pkl
    """
    # Check directory exists
    if not model_dir.exists():
        raise FileNotFoundError(f"Model directory not found: {model_dir}")

    # Find all .pkl files
    pkl_files = list(model_dir.glob('*.pkl'))

    if len(pkl_files) == 0:
        raise FileNotFoundError(
            f"No .pkl files found in {model_dir}. "
            f"KServe requires exactly ONE .pkl file."
        )

    if len(pkl_files) > 1:
        raise RuntimeError(
            f"KServe ERROR: Found {len(pkl_files)} .pkl files in {model_dir}. "
            f"KServe sklearn server requires EXACTLY ONE .pkl file per model.\n"
            f"Files found: {[f.name for f in pkl_files]}\n"
            f"Solution: Combine multiple models into a single wrapper class or Pipeline."
        )

    logger.info(f"✅ KServe validation passed: {pkl_files[0]}")
    return True


def save_model_to_pvc(
    model: Any,
    model_name: str,
    metadata: Optional[Dict[str, Any]] = None,
    overwrite: bool = False,
    validate_kserve: bool = True,
    use_subdirectory: bool = True
) -> str:
    """
    Save trained model to shared PVC storage for KServe deployment.

    This is the PRIMARY method for model storage. Models saved here can be:
    - Directly accessed by KServe InferenceServices using pvc:// URIs
    - Shared between multiple notebook instances
    - Persisted across workbench restarts

    Args:
        model: Trained sklearn/torch/tensorflow model (Pipeline recommended)
        model_name: Name of model (e.g., "anomaly-detector")
        metadata: Optional metadata dictionary to save alongside model
        overwrite: If True, overwrite existing model
        validate_kserve: If True, validate KServe compatibility after save (default: True)
        use_subdirectory: If True, use /mnt/models/{model_name}/model.pkl structure (default: True, KServe recommended)

    Returns:
        Path to saved model file

    Example:
        >>> from sklearn.pipeline import Pipeline
        >>> from sklearn.preprocessing import RobustScaler
        >>> from sklearn.ensemble import IsolationForest
        >>> pipeline = Pipeline([
        ...     ('scaler', RobustScaler()),
        ...     ('model', IsolationForest())
        ... ])
        >>> pipeline.fit(X_train, y_train)
        >>> model_path = save_model_to_pvc(pipeline, "anomaly-detector")
        >>> print(f"Model saved: {model_path}")
        ✅ Model saved to PVC: /mnt/models/anomaly-detector/model.pkl
        ✅ KServe validation passed

    KServe Deployment:
        Once saved, deploy to KServe with:
        storageUri: "pvc://model-storage-pvc/anomaly-detector"
    """
    if not PVC_MODEL_PATH.exists():
        raise RuntimeError(
            f"PVC model path not mounted: {PVC_MODEL_PATH}\n"
            "Ensure workbench pod has model-storage PVC mounted."
        )

    # Use KServe-compatible subdirectory structure
    if use_subdirectory:
        model_dir = PVC_MODEL_PATH / model_name
        model_dir.mkdir(parents=True, exist_ok=True)
        model_file = model_dir / 'model.pkl'
    else:
        # Legacy flat structure
        model_file = PVC_MODEL_PATH / f"{model_name}.pkl"

    if model_file.exists() and not overwrite:
        raise FileExistsError(
            f"Model already exists: {model_file}\n"
            "Set overwrite=True to replace it."
        )

    # Save model
    joblib.dump(model, model_file)
    logger.info(f"✅ Model saved to PVC: {model_file}")
    logger.info(f"   Size: {model_file.stat().st_size / (1024*1024):.2f} MB")

    # Save metadata if provided
    if metadata:
        metadata_file = model_file.parent / f"{model_name}_metadata.json"
        import json
        with open(metadata_file, 'w') as f:
            json.dump(metadata, f, indent=2, default=str)
        logger.info(f"   Metadata: {metadata_file}")

    # Validate KServe compatibility
    if validate_kserve and use_subdirectory:
        try:
            validate_kserve_model_structure(model_file.parent, model_name)
        except Exception as e:
            logger.error(f"❌ KServe validation failed: {e}")
            raise

    return str(model_file)


def load_model_from_pvc(model_name: str) -> Any:
    """
    Load model from shared PVC storage.

    Args:
        model_name: Name of model (without .pkl extension)

    Returns:
        Loaded model object

    Example:
        >>> model = load_model_from_pvc("anomaly-detector")
        >>> predictions = model.predict(X_test)
    """
    model_file = PVC_MODEL_PATH / f"{model_name}.pkl"

    if not model_file.exists():
        raise FileNotFoundError(
            f"Model not found: {model_file}\n"
            f"Available models: {list_models_in_pvc()}"
        )

    model = joblib.load(model_file)
    logger.info(f"✅ Model loaded from PVC: {model_file}")

    return model


def list_models_in_pvc() -> list:
    """
    List all models stored in PVC.

    Returns:
        List of model names (without .pkl extension)

    Example:
        >>> models = list_models_in_pvc()
        >>> print(f"Available models: {models}")
        Available models: ['anomaly-detector', 'predictive-analytics', 'lstm-autoencoder']
    """
    if not PVC_MODEL_PATH.exists():
        return []

    models = [
        f.stem for f in PVC_MODEL_PATH.glob("*.pkl")
        if not f.name.endswith("_metadata.pkl")
    ]

    return sorted(models)


def get_kserve_storage_uri(model_name: str, use_subpath: bool = False) -> str:
    """
    Generate KServe-compatible storageUri for PVC-based model.

    Args:
        model_name: Name of model (without .pkl extension)
        use_subpath: If True, include full path to model.pkl
                    If False, use PVC root (KServe will look for model.pkl)

    Returns:
        KServe storageUri string

    Example:
        >>> uri = get_kserve_storage_uri("anomaly-detector")
        >>> print(uri)
        pvc://model-storage-pvc

        >>> # In InferenceService YAML
        >>> inference_service = {
        >>>     'spec': {
        >>>         'predictor': {
        >>>             'model': {
        >>>                 'modelFormat': {'name': 'sklearn'},
        >>>                 'runtime': 'sklearn-pvc-runtime',
        >>>                 'storageUri': uri
        >>>             }
        >>>         }
        >>>     }
        >>> }
    """
    if use_subpath:
        return f"pvc://model-storage-pvc/{model_name}.pkl"
    else:
        # KServe will automatically look for model.pkl in PVC root
        return "pvc://model-storage-pvc"


def migrate_model_to_pvc(model_name: str, source_path: Optional[str] = None) -> str:
    """
    Migrate model from local workbench storage or custom path to shared PVC.

    Args:
        model_name: Name of model (without .pkl extension)
        source_path: Optional custom source path. If None, uses LOCAL_MODEL_PATH

    Returns:
        Path to model in PVC

    Example:
        >>> # Migrate from legacy local storage
        >>> migrate_model_to_pvc("anomaly-detector")

        >>> # Migrate from custom location
        >>> migrate_model_to_pvc("custom-model", "/opt/app-root/src/data/custom.pkl")
    """
    if source_path:
        source_file = Path(source_path)
    else:
        source_file = LOCAL_MODEL_PATH / f"{model_name}.pkl"

    if not source_file.exists():
        raise FileNotFoundError(f"Source model not found: {source_file}")

    # Load from source
    model = joblib.load(source_file)
    logger.info(f"📦 Loaded model from: {source_file}")

    # Save to PVC
    dest_path = save_model_to_pvc(model, model_name, overwrite=True)
    logger.info(f"✅ Migrated to PVC: {dest_path}")

    return dest_path


# Backwards Compatibility: S3 Support (optional)
def save_model_to_s3(model: Any, model_name: str, bucket: str = "model-storage") -> str:
    """
    LEGACY: Save model to S3 storage (NooBaa).

    Note: This is provided for backwards compatibility. New code should use
    save_model_to_pvc() instead for better performance and simpler deployment.

    Requires:
        - boto3 installed
        - AWS_* environment variables set (from model-storage-config secret)

    Args:
        model: Trained model
        model_name: Name of model (without .pkl extension)
        bucket: S3 bucket name (default: model-storage)

    Returns:
        S3 URI
    """
    try:
        import boto3
    except ImportError:
        raise ImportError(
            "boto3 not installed. Run: pip install boto3\n"
            "For new deployments, use save_model_to_pvc() instead."
        )

    # Save locally first
    temp_file = Path(f"/tmp/{model_name}.pkl")
    joblib.dump(model, temp_file)

    # Upload to S3
    s3_client = boto3.client('s3')
    s3_key = f"{model_name}.pkl"
    s3_client.upload_file(str(temp_file), bucket, s3_key)

    s3_uri = f"s3://{bucket}/{s3_key}"
    logger.info(f"✅ Model saved to S3: {s3_uri}")

    # Cleanup
    temp_file.unlink()

    return s3_uri
