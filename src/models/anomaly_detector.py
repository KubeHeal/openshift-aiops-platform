#!/usr/bin/env python3
"""
Anomaly Detection Model for Self-Healing Platform
Implements basic anomaly detection for infrastructure metrics
"""

import os
import joblib
import numpy as np
import pandas as pd
from typing import Dict, List, Any, Optional
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
from sklearn.pipeline import Pipeline
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class AnomalyDetector:
    """
    Anomaly detection model for infrastructure metrics
    Uses Isolation Forest algorithm for unsupervised anomaly detection
    """

    def __init__(self, contamination: float = 0.1, random_state: int = 42):
        """
        Initialize the anomaly detector

        Args:
            contamination: Expected proportion of anomalies in the data
            random_state: Random state for reproducibility
        """
        self.contamination = contamination
        self.random_state = random_state
        self.model = IsolationForest(
            contamination=contamination,
            random_state=random_state,
            n_estimators=100
        )
        self.scaler = StandardScaler()
        self.feature_names = []
        self.is_trained = False

    def prepare_features(self, data: pd.DataFrame) -> pd.DataFrame:
        """
        Prepare features for anomaly detection

        Args:
            data: Raw metrics data

        Returns:
            Processed feature DataFrame
        """
        features = data.copy()

        # Basic feature engineering
        if 'timestamp' in features.columns:
            features['timestamp'] = pd.to_datetime(features['timestamp'])
            features['hour'] = features['timestamp'].dt.hour
            features['day_of_week'] = features['timestamp'].dt.dayofweek
            features = features.drop('timestamp', axis=1)

        # Rolling statistics (if enough data)
        numeric_cols = features.select_dtypes(include=[np.number]).columns
        if len(features) > 10:
            for col in numeric_cols:
                if col not in ['hour', 'day_of_week']:
                    features[f'{col}_rolling_mean'] = features[col].rolling(window=5, min_periods=1).mean()
                    features[f'{col}_rolling_std'] = features[col].rolling(window=5, min_periods=1).std()

        # Fill NaN values
        features = features.fillna(0)

        # Store feature names
        self.feature_names = list(features.columns)

        return features

    def train(self, data: pd.DataFrame) -> Dict[str, Any]:
        """
        Train the anomaly detection model

        Args:
            data: Training data with metrics

        Returns:
            Training results and metrics
        """
        logger.info("Starting anomaly detector training...")

        # Prepare features
        features = self.prepare_features(data)

        # Scale features
        X_scaled = self.scaler.fit_transform(features)

        # Train model
        self.model.fit(X_scaled)
        self.is_trained = True

        # Generate predictions for training data
        predictions = self.model.predict(X_scaled)
        anomaly_scores = self.model.decision_function(X_scaled)

        # Calculate metrics
        n_anomalies = np.sum(predictions == -1)
        anomaly_rate = n_anomalies / len(predictions)

        results = {
            'training_samples': len(data),
            'features_used': len(self.feature_names),
            'anomalies_detected': int(n_anomalies),
            'anomaly_rate': float(anomaly_rate),
            'feature_names': self.feature_names,
            'model_params': {
                'contamination': self.contamination,
                'n_estimators': self.model.n_estimators,
                'random_state': self.random_state
            }
        }

        logger.info(f"Training completed: {n_anomalies} anomalies detected in {len(data)} samples")
        return results

    def predict(self, data: pd.DataFrame) -> Dict[str, Any]:
        """
        Predict anomalies in new data

        Args:
            data: New data to analyze

        Returns:
            Predictions and anomaly scores
        """
        if not self.is_trained:
            raise ValueError("Model must be trained before making predictions")

        # Prepare features
        features = self.prepare_features(data)

        # Ensure same features as training
        for feature in self.feature_names:
            if feature not in features.columns:
                features[feature] = 0

        features = features[self.feature_names]

        # Scale features
        X_scaled = self.scaler.transform(features)

        # Make predictions
        predictions = self.model.predict(X_scaled)
        anomaly_scores = self.model.decision_function(X_scaled)

        # Convert to human-readable format
        is_anomaly = predictions == -1

        results = {
            'predictions': predictions.tolist(),
            'anomaly_scores': anomaly_scores.tolist(),
            'is_anomaly': is_anomaly.tolist(),
            'anomaly_count': int(np.sum(is_anomaly)),
            'total_samples': len(data)
        }

        return results

    def save_model(self, model_path: str, scaler_path: Optional[str] = None):
        """
        Save trained model as sklearn Pipeline (KServe compatible).

        Args:
            model_path: Path to save pipeline file (single .pkl file)
            scaler_path: DEPRECATED - kept for backwards compatibility, ignored

        Note:
            This method creates a Pipeline combining scaler + model and saves
            as a single .pkl file, compatible with KServe sklearn runtime.
        """
        if not self.is_trained:
            raise ValueError("Model must be trained before saving")

        # Create pipeline if not already one
        if isinstance(self.model, Pipeline):
            pipeline = self.model
        else:
            pipeline = Pipeline([
                ('scaler', self.scaler),
                ('model', self.model)
            ])

        # Save single pipeline file (KServe compatible)
        joblib.dump(pipeline, model_path)

        # Save metadata
        metadata = {
            'feature_names': self.feature_names,
            'contamination': self.contamination,
            'random_state': self.random_state,
            'is_trained': self.is_trained,
            'format': 'pipeline'  # Indicate this is a pipeline format
        }

        metadata_path = model_path.replace('.pkl', '_metadata.json')
        import json
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2)

        logger.info(f"✅ Pipeline saved to {model_path}")
        logger.info(f"   Single .pkl file (scaler + model combined)")
        logger.info(f"   KServe compatible - no 'multiple files' error")
        logger.info(f"   Metadata saved to {metadata_path}")

    def load_model(self, model_path: str, scaler_path: Optional[str] = None):
        """
        Load trained model (supports both Pipeline and legacy separate files).

        Args:
            model_path: Path to pipeline file or model file
            scaler_path: DEPRECATED - Path to scaler file (for backwards compatibility)

        Note:
            This method supports both:
            1. New format: Single pipeline file (KServe compatible)
            2. Legacy format: Separate model + scaler files
        """
        loaded_model = joblib.load(model_path)

        # Check if this is a pipeline or separate model
        if isinstance(loaded_model, Pipeline):
            # New format: Pipeline with scaler + model
            self.model = loaded_model
            # Extract scaler from pipeline for backwards compatibility
            if 'scaler' in loaded_model.named_steps:
                self.scaler = loaded_model.named_steps['scaler']
            logger.info(f"✅ Pipeline loaded from {model_path}")
        else:
            # Legacy format: Separate model and scaler
            self.model = loaded_model
            if scaler_path and os.path.exists(scaler_path):
                self.scaler = joblib.load(scaler_path)
                logger.info(f"   Scaler loaded from {scaler_path}")
            logger.info(f"   Model loaded from {model_path}")

        # Load metadata
        metadata_path = model_path.replace('.pkl', '_metadata.json')
        if os.path.exists(metadata_path):
            import json
            with open(metadata_path, 'r') as f:
                metadata = json.load(f)

            self.feature_names = metadata.get('feature_names', [])
            self.contamination = metadata.get('contamination', 0.1)
            self.random_state = metadata.get('random_state', 42)
            self.is_trained = metadata.get('is_trained', True)

        self.is_trained = True
        logger.info(f"Model loaded successfully")

def generate_sample_data(n_samples: int = 1000) -> pd.DataFrame:
    """
    Generate sample infrastructure metrics data for testing

    Args:
        n_samples: Number of samples to generate

    Returns:
        Sample DataFrame with metrics
    """
    np.random.seed(42)

    # Generate normal operational data
    data = {
        'cpu_usage': np.random.normal(0.3, 0.1, n_samples),
        'memory_usage': np.random.normal(0.6, 0.15, n_samples),
        'disk_usage': np.random.normal(0.4, 0.1, n_samples),
        'network_in': np.random.exponential(100, n_samples),
        'network_out': np.random.exponential(80, n_samples),
        'response_time': np.random.gamma(2, 50, n_samples),
    }

    # Add some anomalies
    n_anomalies = int(n_samples * 0.05)  # 5% anomalies
    anomaly_indices = np.random.choice(n_samples, n_anomalies, replace=False)

    for idx in anomaly_indices:
        # Create different types of anomalies
        anomaly_type = np.random.choice(['cpu_spike', 'memory_leak', 'network_issue'])

        if anomaly_type == 'cpu_spike':
            data['cpu_usage'][idx] = np.random.uniform(0.8, 1.0)
        elif anomaly_type == 'memory_leak':
            data['memory_usage'][idx] = np.random.uniform(0.9, 1.0)
        elif anomaly_type == 'network_issue':
            data['network_in'][idx] = np.random.uniform(1000, 2000)
            data['network_out'][idx] = np.random.uniform(1000, 2000)

    # Ensure values are within reasonable bounds
    for key in data:
        if key in ['cpu_usage', 'memory_usage', 'disk_usage']:
            data[key] = np.clip(data[key], 0, 1)
        else:
            data[key] = np.clip(data[key], 0, None)

    df = pd.DataFrame(data)

    # Add timestamp
    df['timestamp'] = pd.date_range(
        start='2024-01-01',
        periods=n_samples,
        freq='1min'
    )

    return df

if __name__ == "__main__":
    # Example usage and testing
    print("Testing Anomaly Detector...")

    # Generate sample data
    print("Generating sample data...")
    sample_data = generate_sample_data(1000)

    # Split data
    train_data, test_data = train_test_split(sample_data, test_size=0.3, random_state=42)

    # Initialize and train model
    detector = AnomalyDetector(contamination=0.1)

    print("Training model...")
    training_results = detector.train(train_data)
    print(f"Training results: {training_results}")

    # Test predictions
    print("Making predictions...")
    predictions = detector.predict(test_data)
    print(f"Predictions: {predictions['anomaly_count']} anomalies in {predictions['total_samples']} samples")

    # Save model
    print("Saving model...")
    detector.save_model('/tmp/anomaly_model.pkl', '/tmp/scaler.pkl')

    print("Anomaly detector test completed successfully!")
