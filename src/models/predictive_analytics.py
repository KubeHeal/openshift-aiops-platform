#!/usr/bin/env python3
"""
Predictive Analytics Model for Self-Healing Platform
Implements time series forecasting for resource usage prediction
"""

import os
import joblib
import numpy as np
import pandas as pd
from typing import Dict, List, Any, Optional, Tuple
from sklearn.ensemble import RandomForestRegressor
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.model_selection import train_test_split, TimeSeriesSplit
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class PredictiveAnalytics:
    """
    Predictive analytics model for infrastructure resource forecasting
    Uses Random Forest for multi-step time series prediction
    """

    def __init__(self, forecast_horizon: int = 12, lookback_window: int = 24):
        """
        Initialize the predictive analytics model

        Args:
            forecast_horizon: Number of time steps to forecast ahead
            lookback_window: Number of historical time steps to use for prediction
        """
        self.forecast_horizon = forecast_horizon
        self.lookback_window = lookback_window
        self.models = {}  # Separate models for different metrics
        self.scalers = {}  # Separate scalers for different metrics
        self.feature_names = []
        self.target_metrics = ['cpu_usage', 'memory_usage', 'disk_usage', 'network_in', 'network_out']
        self.is_trained = False

    def create_sequences(self, data: pd.DataFrame, target_col: str) -> Tuple[np.ndarray, np.ndarray]:
        """
        Create sequences for time series prediction

        Args:
            data: Time series data
            target_col: Target column to predict

        Returns:
            X: Feature sequences, y: Target sequences
        """
        X, y = [], []

        for i in range(self.lookback_window, len(data) - self.forecast_horizon + 1):
            # Features: lookback_window of historical data
            X.append(data.iloc[i-self.lookback_window:i].values)
            # Target: forecast_horizon of future values
            y.append(data[target_col].iloc[i:i+self.forecast_horizon].values)

        return np.array(X), np.array(y)

    def engineer_features(self, data: pd.DataFrame) -> pd.DataFrame:
        """
        Engineer features for time series prediction

        Args:
            data: Raw time series data

        Returns:
            Enhanced DataFrame with engineered features
        """
        features = data.copy()

        # Time-based features
        if 'timestamp' in features.columns:
            features['timestamp'] = pd.to_datetime(features['timestamp'])
            features['hour'] = features['timestamp'].dt.hour
            features['day_of_week'] = features['timestamp'].dt.dayofweek
            features['day_of_month'] = features['timestamp'].dt.day
            features['month'] = features['timestamp'].dt.month
            features['is_weekend'] = (features['timestamp'].dt.dayofweek >= 5).astype(int)
            features['is_business_hours'] = ((features['hour'] >= 9) & (features['hour'] <= 17)).astype(int)

        # Lag features
        for metric in self.target_metrics:
            if metric in features.columns:
                for lag in [1, 2, 3, 6, 12, 24]:
                    features[f'{metric}_lag_{lag}'] = features[metric].shift(lag)

        # Rolling statistics
        for metric in self.target_metrics:
            if metric in features.columns:
                for window in [3, 6, 12, 24]:
                    features[f'{metric}_rolling_mean_{window}'] = features[metric].rolling(window=window, min_periods=1).mean()
                    features[f'{metric}_rolling_std_{window}'] = features[metric].rolling(window=window, min_periods=1).std()
                    features[f'{metric}_rolling_max_{window}'] = features[metric].rolling(window=window, min_periods=1).max()
                    features[f'{metric}_rolling_min_{window}'] = features[metric].rolling(window=window, min_periods=1).min()

        # Trend features
        for metric in self.target_metrics:
            if metric in features.columns:
                features[f'{metric}_trend_3'] = features[metric].diff(3)
                features[f'{metric}_trend_6'] = features[metric].diff(6)
                features[f'{metric}_pct_change'] = features[metric].pct_change()

        # Fill NaN values
        features = features.fillna(method='forward').fillna(method='backward').fillna(0)

        # Remove timestamp column for modeling
        if 'timestamp' in features.columns:
            features = features.drop('timestamp', axis=1)

        return features

    def train(self, data: pd.DataFrame) -> Dict[str, Any]:
        """
        Train predictive models for each target metric

        Args:
            data: Training data with time series metrics

        Returns:
            Training results and metrics
        """
        logger.info("Starting predictive analytics training...")

        # Engineer features
        features = self.engineer_features(data)
        self.feature_names = list(features.columns)

        results = {}

        for target_metric in self.target_metrics:
            if target_metric not in features.columns:
                logger.warning(f"Target metric {target_metric} not found in data")
                continue

            logger.info(f"Training model for {target_metric}...")

            # Create sequences
            X, y = self.create_sequences(features, target_metric)

            if len(X) == 0:
                logger.warning(f"Not enough data for {target_metric}")
                continue

            # Reshape X for Random Forest (flatten sequences)
            X_reshaped = X.reshape(X.shape[0], -1)

            # Split data
            X_train, X_test, y_train, y_test = train_test_split(
                X_reshaped, y, test_size=0.2, random_state=42, shuffle=False
            )

            # Scale features
            scaler = StandardScaler()
            X_train_scaled = scaler.fit_transform(X_train)
            X_test_scaled = scaler.transform(X_test)

            # Train model for each forecast step
            models_for_metric = []
            for step in range(self.forecast_horizon):
                model = RandomForestRegressor(
                    n_estimators=100,
                    max_depth=10,
                    random_state=42,
                    n_jobs=-1
                )
                model.fit(X_train_scaled, y_train[:, step])
                models_for_metric.append(model)

            # Store models and scaler
            self.models[target_metric] = models_for_metric
            self.scalers[target_metric] = scaler

            # Evaluate model
            y_pred = np.zeros_like(y_test)
            for step in range(self.forecast_horizon):
                y_pred[:, step] = models_for_metric[step].predict(X_test_scaled)

            # Calculate metrics
            mae = mean_absolute_error(y_test.flatten(), y_pred.flatten())
            mse = mean_squared_error(y_test.flatten(), y_pred.flatten())
            rmse = np.sqrt(mse)
            r2 = r2_score(y_test.flatten(), y_pred.flatten())

            results[target_metric] = {
                'mae': float(mae),
                'mse': float(mse),
                'rmse': float(rmse),
                'r2': float(r2),
                'training_samples': len(X_train),
                'test_samples': len(X_test)
            }

            logger.info(f"Model for {target_metric} - MAE: {mae:.4f}, RMSE: {rmse:.4f}, R2: {r2:.4f}")

        self.is_trained = True

        overall_results = {
            'models_trained': len(self.models),
            'forecast_horizon': self.forecast_horizon,
            'lookback_window': self.lookback_window,
            'feature_count': len(self.feature_names),
            'metrics': results
        }

        logger.info(f"Training completed: {len(self.models)} models trained")
        return overall_results

    def predict(self, data: pd.DataFrame) -> Dict[str, Any]:
        """
        Generate predictions for all target metrics

        Args:
            data: Recent data for prediction

        Returns:
            Predictions for each metric
        """
        if not self.is_trained:
            raise ValueError("Models must be trained before making predictions")

        # Engineer features
        features = self.engineer_features(data)

        # Ensure same features as training
        for feature in self.feature_names:
            if feature not in features.columns:
                features[feature] = 0

        features = features[self.feature_names]

        predictions = {}

        for target_metric, models in self.models.items():
            if len(features) < self.lookback_window:
                logger.warning(f"Not enough data for prediction of {target_metric}")
                continue

            # Use the last lookback_window data points
            recent_data = features.tail(self.lookback_window).values
            X = recent_data.reshape(1, -1)  # Flatten for Random Forest

            # Scale features
            X_scaled = self.scalers[target_metric].transform(X)

            # Generate predictions for each forecast step
            forecast = []
            for step in range(self.forecast_horizon):
                pred = models[step].predict(X_scaled)[0]
                forecast.append(float(pred))

            predictions[target_metric] = {
                'forecast': forecast,
                'forecast_horizon': self.forecast_horizon,
                'confidence': self._calculate_confidence(target_metric, X_scaled)
            }

        return {
            'predictions': predictions,
            'timestamp': pd.Timestamp.now().isoformat(),
            'lookback_window': self.lookback_window
        }

    def _calculate_confidence(self, target_metric: str, X_scaled: np.ndarray) -> List[float]:
        """
        Calculate prediction confidence based on model variance

        Args:
            target_metric: Target metric name
            X_scaled: Scaled input features

        Returns:
            Confidence scores for each forecast step
        """
        confidence_scores = []

        for step in range(self.forecast_horizon):
            model = self.models[target_metric][step]

            # Use tree variance as confidence measure
            if hasattr(model, 'estimators_'):
                predictions = [tree.predict(X_scaled)[0] for tree in model.estimators_]
                variance = np.var(predictions)
                # Convert variance to confidence (0-1 scale)
                confidence = max(0, min(1, 1 - (variance / np.mean(predictions) if np.mean(predictions) != 0 else 1)))
            else:
                confidence = 0.5  # Default confidence

            confidence_scores.append(float(confidence))

        return confidence_scores

    def detect_anomalies(self, data: pd.DataFrame, threshold: float = 2.0) -> Dict[str, Any]:
        """
        Detect anomalies by comparing actual vs predicted values

        Args:
            data: Recent data including actual values
            threshold: Standard deviations threshold for anomaly detection

        Returns:
            Anomaly detection results
        """
        if not self.is_trained:
            raise ValueError("Models must be trained before anomaly detection")

        predictions = self.predict(data)
        anomalies = {}

        for target_metric in self.target_metrics:
            if target_metric not in data.columns or target_metric not in predictions['predictions']:
                continue

            actual_values = data[target_metric].tail(self.forecast_horizon).values
            predicted_values = np.array(predictions['predictions'][target_metric]['forecast'])

            if len(actual_values) != len(predicted_values):
                continue

            # Calculate residuals
            residuals = actual_values - predicted_values
            residual_std = np.std(residuals)
            residual_mean = np.mean(residuals)

            # Detect anomalies
            anomaly_scores = np.abs(residuals - residual_mean) / (residual_std + 1e-8)
            is_anomaly = anomaly_scores > threshold

            anomalies[target_metric] = {
                'anomaly_detected': bool(np.any(is_anomaly)),
                'anomaly_scores': anomaly_scores.tolist(),
                'anomaly_indices': np.where(is_anomaly)[0].tolist(),
                'severity': float(np.max(anomaly_scores)) if len(anomaly_scores) > 0 else 0.0
            }

        return {
            'anomalies': anomalies,
            'timestamp': pd.Timestamp.now().isoformat(),
            'threshold': threshold
        }

    def save_models(self, model_dir: str, kserve_compatible: bool = True):
        """
        Save all trained models and scalers

        Args:
            model_dir: Base directory for model storage (e.g., /mnt/models)
            kserve_compatible: If True, creates KServe-compatible structure with single model.pkl
        """
        if not self.is_trained:
            raise ValueError("Models must be trained before saving")

        if kserve_compatible:
            # KServe-compatible structure: /mnt/models/predictive-analytics/model.pkl
            from pathlib import Path
            base_dir = Path(model_dir)
            model_name = 'predictive-analytics'
            kserve_dir = base_dir / model_name
            kserve_dir.mkdir(parents=True, exist_ok=True)

            # Package everything into a single model.pkl file
            model_package = {
                'models': self.models,
                'scalers': self.scalers,
                'metadata': {
                    'forecast_horizon': self.forecast_horizon,
                    'lookback_window': self.lookback_window,
                    'feature_names': self.feature_names,
                    'target_metrics': self.target_metrics,
                    'is_trained': self.is_trained
                }
            }

            # Wrap in KServe-compatible wrapper
            try:
                from kserve_wrapper import create_kserve_model
                kserve_model = create_kserve_model(model_package)
                model_to_save = kserve_model
                logger.info("Using KServe wrapper for sklearn server compatibility")
            except ImportError:
                # Fallback if wrapper not available (still works but less compatible)
                logger.warning("KServe wrapper not found, saving raw model package")
                model_to_save = model_package

            model_path = kserve_dir / 'model.pkl'

            # Migration: Move old files if they exist
            old_files = list(base_dir.glob('*_step_*_model.pkl')) + list(base_dir.glob('*_scaler.pkl'))
            if old_files and not model_path.exists():
                logger.info(f"🔄 Migrating {len(old_files)} old model files to KServe structure")

            joblib.dump(model_to_save, model_path)
            logger.info(f"💾 Saved KServe-compatible model to: {model_path}")
            logger.info(f"   ✅ KServe-compatible path: {model_name}/model.pkl")
            logger.info(f"   ✅ Single .pkl file (models + scalers + metadata)")

            # Clean up old files
            for old_file in old_files:
                try:
                    old_file.unlink()
                    logger.info(f"🗑️  Removed old file: {old_file.name}")
                except Exception as e:
                    logger.warning(f"Could not remove old file {old_file}: {e}")

            # Also clean up old metadata.json if exists
            old_metadata = base_dir / 'metadata.json'
            if old_metadata.exists():
                try:
                    old_metadata.unlink()
                    logger.info(f"🗑️  Removed old metadata.json")
                except Exception as e:
                    logger.warning(f"Could not remove old metadata: {e}")

        else:
            # Legacy structure (deprecated) - multiple files
            os.makedirs(model_dir, exist_ok=True)

            for target_metric in self.models:
                # Save models for each forecast step
                for step, model in enumerate(self.models[target_metric]):
                    model_path = os.path.join(model_dir, f"{target_metric}_step_{step}_model.pkl")
                    joblib.dump(model, model_path)

                # Save scaler
                scaler_path = os.path.join(model_dir, f"{target_metric}_scaler.pkl")
                joblib.dump(self.scalers[target_metric], scaler_path)

            # Save metadata
            metadata = {
                'forecast_horizon': self.forecast_horizon,
                'lookback_window': self.lookback_window,
                'feature_names': self.feature_names,
                'target_metrics': self.target_metrics,
                'is_trained': self.is_trained
            }

            metadata_path = os.path.join(model_dir, 'metadata.json')
            import json
            with open(metadata_path, 'w') as f:
                json.dump(metadata, f, indent=2)

            logger.info(f"Models saved to {model_dir} (legacy structure)")

    def load_models(self, model_dir: str):
        """
        Load trained models and scalers
        Supports both KServe-compatible structure and legacy structure
        """
        from pathlib import Path
        base_dir = Path(model_dir)

        # Try KServe-compatible structure first: /mnt/models/predictive-analytics/model.pkl
        kserve_path = base_dir / 'predictive-analytics' / 'model.pkl'

        if kserve_path.exists():
            # Load KServe-compatible single-file model
            logger.info(f"Loading KServe-compatible model from: {kserve_path}")
            loaded_model = joblib.load(kserve_path)

            # Check if it's a wrapper or raw model package
            if hasattr(loaded_model, 'models') and hasattr(loaded_model, 'metadata'):
                # It's a wrapper instance - extract the internal components
                logger.info("Detected KServe wrapper, extracting model components")
                self.models = loaded_model.models
                self.scalers = loaded_model.scalers
                metadata = loaded_model.metadata
            elif isinstance(loaded_model, dict) and 'models' in loaded_model:
                # It's a raw model package
                logger.info("Detected raw model package")
                self.models = loaded_model['models']
                self.scalers = loaded_model['scalers']
                metadata = loaded_model['metadata']
            else:
                raise ValueError(f"Unknown model format at {kserve_path}")

            self.forecast_horizon = metadata['forecast_horizon']
            self.lookback_window = metadata['lookback_window']
            self.feature_names = metadata['feature_names']
            self.target_metrics = metadata['target_metrics']
            self.is_trained = metadata['is_trained']

            logger.info(f"✅ Loaded KServe model: {len(self.models)} metrics")

        else:
            # Fall back to legacy structure
            logger.info(f"Loading legacy model structure from: {model_dir}")

            # Load metadata
            metadata_path = os.path.join(model_dir, 'metadata.json')
            import json

            if not os.path.exists(metadata_path):
                raise FileNotFoundError(
                    f"No model found at {kserve_path} or legacy metadata at {metadata_path}"
                )

            with open(metadata_path, 'r') as f:
                metadata = json.load(f)

            self.forecast_horizon = metadata['forecast_horizon']
            self.lookback_window = metadata['lookback_window']
            self.feature_names = metadata['feature_names']
            self.target_metrics = metadata['target_metrics']
            self.is_trained = metadata['is_trained']

            # Load models and scalers
            self.models = {}
            self.scalers = {}

            for target_metric in self.target_metrics:
                # Load models for each forecast step
                models_for_metric = []
                for step in range(self.forecast_horizon):
                    model_path = os.path.join(model_dir, f"{target_metric}_step_{step}_model.pkl")
                    if os.path.exists(model_path):
                        model = joblib.load(model_path)
                        models_for_metric.append(model)

                if models_for_metric:
                    self.models[target_metric] = models_for_metric

                # Load scaler
                scaler_path = os.path.join(model_dir, f"{target_metric}_scaler.pkl")
                if os.path.exists(scaler_path):
                    self.scalers[target_metric] = joblib.load(scaler_path)

            logger.info(f"✅ Loaded legacy models from {model_dir}")

def generate_sample_timeseries_data(n_samples: int = 1000) -> pd.DataFrame:
    """
    Generate sample time series data for testing

    Args:
        n_samples: Number of time series samples

    Returns:
        Sample DataFrame with time series metrics
    """
    np.random.seed(42)

    # Generate timestamps
    timestamps = pd.date_range(start='2024-01-01', periods=n_samples, freq='5min')

    # Generate base patterns with seasonality
    hours = timestamps.hour
    days = timestamps.dayofweek

    # CPU usage with daily and weekly patterns
    cpu_base = 0.3 + 0.2 * np.sin(2 * np.pi * hours / 24) + 0.1 * np.sin(2 * np.pi * days / 7)
    cpu_noise = np.random.normal(0, 0.05, n_samples)
    cpu_usage = np.clip(cpu_base + cpu_noise, 0, 1)

    # Memory usage with trend
    memory_base = 0.5 + 0.1 * np.sin(2 * np.pi * hours / 24) + np.linspace(0, 0.2, n_samples)
    memory_noise = np.random.normal(0, 0.03, n_samples)
    memory_usage = np.clip(memory_base + memory_noise, 0, 1)

    # Disk usage with slow growth
    disk_base = 0.4 + np.linspace(0, 0.3, n_samples)
    disk_noise = np.random.normal(0, 0.02, n_samples)
    disk_usage = np.clip(disk_base + disk_noise, 0, 1)

    # Network with business hours pattern
    business_hours = ((hours >= 9) & (hours <= 17) & (days < 5)).astype(float)
    network_in = 50 + 100 * business_hours + np.random.exponential(20, n_samples)
    network_out = 40 + 80 * business_hours + np.random.exponential(15, n_samples)

    df = pd.DataFrame({
        'timestamp': timestamps,
        'cpu_usage': cpu_usage,
        'memory_usage': memory_usage,
        'disk_usage': disk_usage,
        'network_in': network_in,
        'network_out': network_out
    })

    return df

if __name__ == "__main__":
    # Example usage and testing
    print("Testing Predictive Analytics Model...")

    # Generate sample data
    print("Generating sample time series data...")
    sample_data = generate_sample_timeseries_data(2000)

    # Split data for training and testing
    train_data = sample_data.iloc[:1600]
    test_data = sample_data.iloc[1600:]

    # Initialize and train model
    predictor = PredictiveAnalytics(forecast_horizon=12, lookback_window=24)

    print("Training predictive models...")
    training_results = predictor.train(train_data)
    print(f"Training results: {training_results}")

    # Make predictions
    print("Making predictions...")
    predictions = predictor.predict(test_data.head(50))  # Use first 50 samples for prediction
    print(f"Predictions generated for {len(predictions['predictions'])} metrics")

    # Detect anomalies
    print("Detecting anomalies...")
    anomalies = predictor.detect_anomalies(test_data.head(50))
    anomaly_count = sum(1 for metric_anomalies in anomalies['anomalies'].values()
                       if metric_anomalies['anomaly_detected'])
    print(f"Anomalies detected in {anomaly_count} metrics")

    # Save models (KServe-compatible)
    print("Saving models...")
    # Use /mnt/models in production, /tmp for testing
    model_base_dir = '/mnt/models' if os.path.exists('/mnt/models') else '/tmp'
    predictor.save_models(model_base_dir, kserve_compatible=True)

    # Test loading
    print("Testing model loading...")
    predictor_loaded = PredictiveAnalytics()
    predictor_loaded.load_models(model_base_dir)
    print(f"Model loaded successfully with {len(predictor_loaded.models)} metrics")

    print("Predictive analytics test completed successfully!")
