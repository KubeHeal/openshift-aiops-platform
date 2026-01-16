"""
Coordination Engine Client Library

A Python client for interacting with the OpenShift Coordination Engine's
KServe model proxy integration. This enables notebooks to call KServe
InferenceServices through the coordination engine as a central orchestrator.

Reference: ADR-039, ADR-040, GitHub Issue #18
"""

import os
import json
import logging
from typing import List, Dict, Any, Optional, Union
from dataclasses import dataclass
from urllib.parse import urljoin

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class DetectResponse:
    """Response from a KServe model prediction via coordination engine."""
    predictions: List[int]
    model_name: str
    model_version: Optional[str] = None

    def has_anomalies(self) -> bool:
        """Check if any predictions indicate anomalies (-1)."""
        return -1 in self.predictions

    def anomaly_count(self) -> int:
        """Count the number of anomalies detected."""
        return sum(1 for p in self.predictions if p == -1)

    def anomaly_rate(self) -> float:
        """Calculate the anomaly rate as a percentage."""
        if not self.predictions:
            return 0.0
        return self.anomaly_count() / len(self.predictions)


@dataclass
class ModelHealth:
    """Health status of a KServe model."""
    model: str
    status: str
    service: str
    namespace: str
    message: Optional[str] = None

    def is_healthy(self) -> bool:
        """Check if the model is healthy and ready."""
        return self.status == "ready"


class CoordinationEngineError(Exception):
    """Base exception for Coordination Engine errors."""
    pass


class ModelNotFoundError(CoordinationEngineError):
    """Raised when a model is not registered in the coordination engine."""
    pass


class ModelUnavailableError(CoordinationEngineError):
    """Raised when a model is unavailable or unhealthy."""
    pass


class InvalidRequestError(CoordinationEngineError):
    """Raised when a request is invalid."""
    pass


class CoordinationEngineClient:
    """
    Client for the OpenShift Coordination Engine.

    Provides methods to:
    - Call KServe models for predictions via /api/v1/detect
    - List registered models via /api/v1/models
    - Check model health via /api/v1/models/{model}/health

    Example:
        >>> client = CoordinationEngineClient()
        >>>
        >>> # List available models
        >>> models = client.list_models()
        >>> print(f"Available models: {models}")
        >>>
        >>> # Make a prediction
        >>> result = client.detect_anomaly(
        ...     model_name="anomaly-detector",
        ...     instances=[[0.5, 1.2, 0.8], [0.3, 0.9, 1.1]]
        ... )
        >>> print(f"Predictions: {result.predictions}")
        >>> print(f"Has anomalies: {result.has_anomalies()}")
    """

    DEFAULT_BASE_URL = "http://coordination-engine:8080"

    def __init__(
        self,
        base_url: Optional[str] = None,
        timeout: int = 30,
        max_retries: int = 3,
        verify_ssl: bool = True
    ):
        """
        Initialize the Coordination Engine client.

        Args:
            base_url: Base URL of the coordination engine.
                     Defaults to COORDINATION_ENGINE_URL env var or http://coordination-engine:8080
            timeout: Request timeout in seconds
            max_retries: Maximum number of retry attempts for failed requests
            verify_ssl: Whether to verify SSL certificates
        """
        self.base_url = base_url or os.getenv(
            "COORDINATION_ENGINE_URL",
            self.DEFAULT_BASE_URL
        )
        self.timeout = timeout
        self.verify_ssl = verify_ssl

        # Configure session with retry logic
        self.session = requests.Session()
        retry_strategy = Retry(
            total=max_retries,
            backoff_factor=0.5,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET", "POST"]
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

        logger.info(f"Initialized CoordinationEngineClient with base_url={self.base_url}")

    def _make_request(
        self,
        method: str,
        endpoint: str,
        json_data: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """Make an HTTP request to the coordination engine."""
        url = urljoin(self.base_url, endpoint)

        try:
            response = self.session.request(
                method=method,
                url=url,
                json=json_data,
                timeout=self.timeout,
                verify=self.verify_ssl
            )

            # Handle error responses
            if response.status_code == 400:
                error_msg = response.json().get("error", "Invalid request")
                raise InvalidRequestError(error_msg)
            elif response.status_code == 404:
                error_msg = response.json().get("error", "Model not found")
                raise ModelNotFoundError(error_msg)
            elif response.status_code == 503:
                error_msg = response.json().get("error", "Model unavailable")
                raise ModelUnavailableError(error_msg)
            elif response.status_code >= 400:
                response.raise_for_status()

            return response.json()

        except requests.exceptions.ConnectionError as e:
            raise CoordinationEngineError(
                f"Failed to connect to coordination engine at {url}: {e}"
            )
        except requests.exceptions.Timeout as e:
            raise CoordinationEngineError(
                f"Request to coordination engine timed out: {e}"
            )
        except requests.exceptions.RequestException as e:
            raise CoordinationEngineError(
                f"Request to coordination engine failed: {e}"
            )

    def health_check(self) -> Dict[str, Any]:
        """
        Check the health of the coordination engine.

        Returns:
            Dict containing health status
        """
        return self._make_request("GET", "/health")

    def list_models(self) -> List[str]:
        """
        List all registered KServe models.

        Returns:
            List of model names

        Example:
            >>> models = client.list_models()
            >>> print(models)
            ['anomaly-detector', 'predictive-analytics', 'disk-failure-predictor']
        """
        response = self._make_request("GET", "/api/v1/models")
        return response.get("models", [])

    def get_model_count(self) -> int:
        """
        Get the count of registered models.

        Returns:
            Number of registered models
        """
        response = self._make_request("GET", "/api/v1/models")
        return response.get("count", 0)

    def check_model_health(self, model_name: str) -> ModelHealth:
        """
        Check the health of a specific KServe model.

        Args:
            model_name: Name of the model to check

        Returns:
            ModelHealth object with status information

        Example:
            >>> health = client.check_model_health("anomaly-detector")
            >>> print(f"Status: {health.status}")
            >>> print(f"Is healthy: {health.is_healthy()}")
        """
        response = self._make_request("GET", f"/api/v1/models/{model_name}/health")
        return ModelHealth(
            model=response.get("model", model_name),
            status=response.get("status", "unknown"),
            service=response.get("service", ""),
            namespace=response.get("namespace", ""),
            message=response.get("message")
        )

    def detect_anomaly(
        self,
        model_name: str,
        instances: List[List[float]]
    ) -> DetectResponse:
        """
        Call a KServe model for anomaly detection predictions.

        This is the primary method for calling ML models through the
        coordination engine proxy.

        Args:
            model_name: Name of the model to call (e.g., "anomaly-detector")
            instances: List of feature vectors for prediction.
                      Each instance is a list of float values.

        Returns:
            DetectResponse containing predictions and metadata

        Raises:
            ModelNotFoundError: If the model is not registered
            ModelUnavailableError: If the model service is unavailable
            InvalidRequestError: If the request format is invalid

        Example:
            >>> # Single instance
            >>> result = client.detect_anomaly(
            ...     model_name="anomaly-detector",
            ...     instances=[[0.5, 1.2, 0.8]]
            ... )
            >>> print(result.predictions)  # [-1] means anomaly, [1] means normal

            >>> # Multiple instances
            >>> result = client.detect_anomaly(
            ...     model_name="anomaly-detector",
            ...     instances=[
            ...         [0.5, 1.2, 0.8],
            ...         [0.3, 0.9, 1.1],
            ...         [2.5, 3.0, 4.0]
            ...     ]
            ... )
            >>> print(f"Anomaly rate: {result.anomaly_rate():.1%}")
        """
        request_data = {
            "model": model_name,
            "instances": instances
        }

        response = self._make_request("POST", "/api/v1/detect", request_data)

        return DetectResponse(
            predictions=response.get("predictions", []),
            model_name=response.get("model_name", model_name),
            model_version=response.get("model_version")
        )

    def predict(
        self,
        model_name: str,
        instances: List[List[float]]
    ) -> DetectResponse:
        """
        Alias for detect_anomaly for general predictions.

        This method is provided for semantic clarity when calling
        models that may not be specifically for anomaly detection.
        """
        return self.detect_anomaly(model_name, instances)

    def batch_predict(
        self,
        model_name: str,
        instances: List[List[float]],
        batch_size: int = 100
    ) -> DetectResponse:
        """
        Make predictions in batches for large datasets.

        Args:
            model_name: Name of the model to call
            instances: List of feature vectors
            batch_size: Number of instances per batch

        Returns:
            Combined DetectResponse with all predictions
        """
        all_predictions = []

        for i in range(0, len(instances), batch_size):
            batch = instances[i:i + batch_size]
            result = self.detect_anomaly(model_name, batch)
            all_predictions.extend(result.predictions)
            logger.debug(f"Processed batch {i//batch_size + 1}")

        return DetectResponse(
            predictions=all_predictions,
            model_name=model_name
        )

    def get_available_models_with_health(self) -> Dict[str, ModelHealth]:
        """
        Get all models with their health status.

        Returns:
            Dict mapping model names to their health status
        """
        models = self.list_models()
        health_map = {}

        for model_name in models:
            try:
                health = self.check_model_health(model_name)
                health_map[model_name] = health
            except CoordinationEngineError as e:
                logger.warning(f"Failed to get health for {model_name}: {e}")
                health_map[model_name] = ModelHealth(
                    model=model_name,
                    status="error",
                    service="",
                    namespace="",
                    message=str(e)
                )

        return health_map

    def wait_for_model_ready(
        self,
        model_name: str,
        timeout: int = 300,
        interval: int = 5
    ) -> bool:
        """
        Wait for a model to become ready.

        Args:
            model_name: Name of the model
            timeout: Maximum time to wait in seconds
            interval: Time between checks in seconds

        Returns:
            True if model became ready, False if timeout
        """
        import time

        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                health = self.check_model_health(model_name)
                if health.is_healthy():
                    logger.info(f"Model {model_name} is ready")
                    return True
            except CoordinationEngineError as e:
                logger.debug(f"Model {model_name} not ready: {e}")

            time.sleep(interval)

        logger.warning(f"Timeout waiting for model {model_name}")
        return False

    def __repr__(self) -> str:
        return f"CoordinationEngineClient(base_url='{self.base_url}')"


# Convenience function for quick access
def get_client(**kwargs) -> CoordinationEngineClient:
    """
    Get a CoordinationEngineClient instance.

    This is a convenience function for quickly getting a client:

        >>> from utils.coordination_engine_client import get_client
        >>> client = get_client()
        >>> models = client.list_models()
    """
    return CoordinationEngineClient(**kwargs)


# For backwards compatibility and easy imports
__all__ = [
    "CoordinationEngineClient",
    "DetectResponse",
    "ModelHealth",
    "CoordinationEngineError",
    "ModelNotFoundError",
    "ModelUnavailableError",
    "InvalidRequestError",
    "get_client"
]
