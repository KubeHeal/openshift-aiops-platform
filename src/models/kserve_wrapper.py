#!/usr/bin/env python3
"""
KServe-compatible wrapper for PredictiveAnalytics model
This wrapper provides a sklearn-compatible interface that KServe can serve
"""

import logging
import numpy as np
import pandas as pd
from typing import List, Dict, Any, Union

logger = logging.getLogger(__name__)


class PredictiveAnalyticsWrapper:
    """
    KServe-compatible wrapper for PredictiveAnalytics model
    Provides a simple predict() interface that KServe sklearn server can use
    """

    def __init__(self, model_package: Dict[str, Any]):
        """
        Initialize wrapper with loaded model package

        Args:
            model_package: Dictionary containing models, scalers, and metadata
        """
        self.models = model_package['models']
        self.scalers = model_package['scalers']
        self.metadata = model_package['metadata']

        self.forecast_horizon = self.metadata['forecast_horizon']
        self.lookback_window = self.metadata['lookback_window']
        self.feature_names = self.metadata['feature_names']
        self.target_metrics = self.metadata['target_metrics']

        logger.info(f"KServe wrapper initialized: {len(self.models)} metrics")

    def predict(self, X: Union[np.ndarray, pd.DataFrame, List]) -> Dict[str, Any]:
        """
        Make predictions - KServe-compatible interface

        Args:
            X: Input data (can be array, DataFrame, or list)

        Returns:
            Dictionary with predictions for each metric
        """
        # Convert input to DataFrame if needed
        if isinstance(X, np.ndarray):
            data = pd.DataFrame(X)
        elif isinstance(X, list):
            data = pd.DataFrame(X)
        else:
            data = X.copy()

        # Engineer features (simplified version for inference)
        features = self._engineer_features(data)

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
            X_input = recent_data.reshape(1, -1)  # Flatten for Random Forest

            # Scale features
            X_scaled = self.scalers[target_metric].transform(X_input)

            # Generate predictions for each forecast step
            forecast = []
            for step in range(self.forecast_horizon):
                pred = models[step].predict(X_scaled)[0]
                forecast.append(float(pred))

            predictions[target_metric] = {
                'forecast': forecast,
                'forecast_horizon': self.forecast_horizon
            }

        return predictions

    def _engineer_features(self, data: pd.DataFrame) -> pd.DataFrame:
        """
        Engineer features for time series prediction (simplified for inference)

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
        features = features.fillna(method='ffill').fillna(method='bfill').fillna(0)

        # Remove timestamp column for modeling
        if 'timestamp' in features.columns:
            features = features.drop('timestamp', axis=1)

        return features


def create_kserve_model(model_package: Dict[str, Any]) -> PredictiveAnalyticsWrapper:
    """
    Factory function to create KServe-compatible model wrapper

    Args:
        model_package: Loaded model package from predictive_analytics.py

    Returns:
        KServe-compatible wrapper instance
    """
    return PredictiveAnalyticsWrapper(model_package)


if __name__ == "__main__":
    print("KServe wrapper for PredictiveAnalytics model")
    print("This module provides sklearn-compatible interface for KServe serving")
