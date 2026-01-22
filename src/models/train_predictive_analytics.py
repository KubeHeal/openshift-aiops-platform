#!/usr/bin/env python3
"""
Train and save Predictive Analytics model with KServe-compatible structure
This script trains the model and saves it in the format expected by KServe

Usage:
    python train_predictive_analytics.py [--model-dir /mnt/models] [--samples 2000]
"""

import os
import argparse
import logging
from pathlib import Path
from predictive_analytics import PredictiveAnalytics, generate_sample_timeseries_data

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def train_and_save_model(model_dir: str = '/mnt/models', n_samples: int = 2000,
                         forecast_horizon: int = 12, lookback_window: int = 24):
    """
    Train predictive analytics model and save in KServe-compatible format

    Args:
        model_dir: Base directory for model storage (default: /mnt/models)
        n_samples: Number of samples to generate for training
        forecast_horizon: Number of time steps to forecast ahead
        lookback_window: Number of historical time steps to use
    """
    logger.info("=" * 80)
    logger.info("Training Predictive Analytics Model for KServe Deployment")
    logger.info("=" * 80)

    # Step 1: Generate or load training data
    logger.info(f"\n[1/4] Generating sample time series data ({n_samples} samples)...")
    sample_data = generate_sample_timeseries_data(n_samples)
    logger.info(f"  ✅ Generated data with shape: {sample_data.shape}")
    logger.info(f"  Metrics: {', '.join(sample_data.columns.tolist())}")

    # Split data for training and validation
    split_point = int(n_samples * 0.8)
    train_data = sample_data.iloc[:split_point]
    val_data = sample_data.iloc[split_point:]
    logger.info(f"  Training samples: {len(train_data)}")
    logger.info(f"  Validation samples: {len(val_data)}")

    # Step 2: Initialize and train model
    logger.info(f"\n[2/4] Training predictive models...")
    logger.info(f"  Forecast horizon: {forecast_horizon} steps")
    logger.info(f"  Lookback window: {lookback_window} steps")

    predictor = PredictiveAnalytics(
        forecast_horizon=forecast_horizon,
        lookback_window=lookback_window
    )

    training_results = predictor.train(train_data)

    logger.info(f"  ✅ Training completed")
    logger.info(f"  Models trained: {training_results['models_trained']}")
    logger.info(f"  Features: {training_results['feature_count']}")

    # Print metrics for each model
    for metric_name, metric_results in training_results['metrics'].items():
        logger.info(f"\n  {metric_name}:")
        logger.info(f"    MAE: {metric_results['mae']:.4f}")
        logger.info(f"    RMSE: {metric_results['rmse']:.4f}")
        logger.info(f"    R²: {metric_results['r2']:.4f}")

    # Step 3: Validate predictions
    logger.info(f"\n[3/4] Validating predictions...")
    predictions = predictor.predict(val_data.head(50))
    logger.info(f"  ✅ Generated predictions for {len(predictions['predictions'])} metrics")

    # Step 4: Save model in KServe-compatible format
    logger.info(f"\n[4/4] Saving model in KServe-compatible format...")
    logger.info(f"  Base directory: {model_dir}")

    # Ensure model directory exists
    Path(model_dir).mkdir(parents=True, exist_ok=True)

    # Save with KServe-compatible structure
    predictor.save_models(model_dir, kserve_compatible=True)

    # Verify the saved model structure
    expected_path = Path(model_dir) / 'predictive-analytics' / 'model.pkl'
    if expected_path.exists():
        size_kb = expected_path.stat().st_size / 1024
        logger.info(f"\n✅ Model saved successfully!")
        logger.info(f"  Location: {expected_path}")
        logger.info(f"  Size: {size_kb:.2f} KB")
        logger.info(f"\nKServe InferenceService will:")
        logger.info(f"  1. Mount this model from: pvc://model-storage-pvc/predictive-analytics")
        logger.info(f"  2. Load model from: /mnt/models/predictive-analytics/model.pkl")
        logger.info(f"  3. Register as model name: 'predictive-analytics'")
        logger.info(f"  4. Expose endpoint: /v1/models/predictive-analytics:predict")
    else:
        logger.error(f"❌ Model file not found at expected location: {expected_path}")
        return False

    logger.info("\n" + "=" * 80)
    logger.info("Training Complete!")
    logger.info("=" * 80)

    return True


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='Train Predictive Analytics model for KServe')
    parser.add_argument(
        '--model-dir',
        type=str,
        default='/mnt/models',
        help='Base directory for model storage (default: /mnt/models)'
    )
    parser.add_argument(
        '--samples',
        type=int,
        default=2000,
        help='Number of training samples to generate (default: 2000)'
    )
    parser.add_argument(
        '--forecast-horizon',
        type=int,
        default=12,
        help='Forecast horizon in time steps (default: 12)'
    )
    parser.add_argument(
        '--lookback-window',
        type=int,
        default=24,
        help='Lookback window in time steps (default: 24)'
    )

    args = parser.parse_args()

    # Fallback to /tmp if /mnt/models doesn't exist (for testing)
    model_dir = args.model_dir
    if not os.path.exists(model_dir):
        logger.warning(f"Model directory {model_dir} doesn't exist")
        model_dir = '/tmp'
        logger.info(f"Using fallback directory: {model_dir}")

    # Train and save model
    success = train_and_save_model(
        model_dir=model_dir,
        n_samples=args.samples,
        forecast_horizon=args.forecast_horizon,
        lookback_window=args.lookback_window
    )

    if success:
        logger.info("\n✅ Success! Model is ready for KServe deployment")
        return 0
    else:
        logger.error("\n❌ Training failed")
        return 1


if __name__ == "__main__":
    exit(main())
