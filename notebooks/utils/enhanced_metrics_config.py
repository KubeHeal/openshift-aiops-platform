"""
Integration Guide: Enhanced Metrics for Self-Healing Platform
==============================================================

This shows how to integrate the enhanced metrics configuration
with your existing Isolation Forest pipeline.

Copy the relevant sections into your notebook.
"""

# =============================================================================
# CELL 1: Import Enhanced Metrics Configuration
# =============================================================================

# Add this at the top of your notebook (after standard imports)

import sys
sys.path.append('/opt/app-root/src/notebooks/utils')

from enhanced_metrics_config import (
    # Configurations
    ISOLATION_FOREST_CONFIGS,
    AnomalyCategory,
    
    # Metric collections
    TARGET_METRICS_ENHANCED,
    STABILITY_METRICS,
    PERFORMANCE_METRICS,
    RESOURCE_EXHAUSTION_METRICS,
    CONTROL_PLANE_HEALTH_METRICS,
    
    # Metric definitions
    NODE_METRICS,
    POD_METRICS,
    KUBERNETES_METRICS,
    CONTROL_PLANE_METRICS,
    
    # Helper functions
    get_prometheus_queries,
    get_thresholds,
    get_metrics_by_category,
)

print("✅ Enhanced metrics configuration loaded")
print(f"   📊 Total target metrics: {len(TARGET_METRICS_ENHANCED)}")

# =============================================================================
# CELL 2: Updated Isolation Forest Configuration
# =============================================================================

# BEFORE (your original):
# ISOLATION_FOREST_CONFIG = {
#     'contamination': 0.05,
#     'n_estimators': 200,
#     'max_samples': 'auto',
#     'max_features': 1.0,
#     'random_state': 42
# }

# AFTER (category-specific):
# Choose the right config based on your detection goal

# For general resource anomalies
ISOLATION_FOREST_CONFIG = ISOLATION_FOREST_CONFIGS[AnomalyCategory.RESOURCE]

# For stability issues (crashes, restarts)
# ISOLATION_FOREST_CONFIG = ISOLATION_FOREST_CONFIGS[AnomalyCategory.STABILITY]

# For performance degradation
# ISOLATION_FOREST_CONFIG = ISOLATION_FOREST_CONFIGS[AnomalyCategory.PERFORMANCE]

print(f"✅ Using config for: {AnomalyCategory.RESOURCE.value}")
print(f"   Contamination: {ISOLATION_FOREST_CONFIG['contamination']}")
print(f"   Estimators: {ISOLATION_FOREST_CONFIG['n_estimators']}")

# =============================================================================
# CELL 3: Enhanced Target Metrics
# =============================================================================

# BEFORE (your original):
# TARGET_METRICS = [
#     'node_cpu_utilization',
#     'node_memory_utilization',
#     'pod_cpu_usage',
#     'pod_memory_usage',
#     'container_restart_count'
# ]

# AFTER (comprehensive):
TARGET_METRICS = TARGET_METRICS_ENHANCED

print(f"✅ Target metrics: {len(TARGET_METRICS)}")
print("\n📊 Metric categories included:")

# Group and display
from collections import Counter
from enhanced_metrics_config import get_all_metrics

all_metrics = get_all_metrics()
categories = []
for m in TARGET_METRICS:
    if m in all_metrics:
        categories.append(all_metrics[m].category.value)

for cat, count in Counter(categories).items():
    print(f"   {cat}: {count} metrics")

# =============================================================================
# CELL 4: Get PromQL Queries for Data Collection
# =============================================================================

# Get the actual Prometheus queries for each metric
prometheus_queries = get_prometheus_queries(TARGET_METRICS)

print(f"✅ Generated {len(prometheus_queries)} PromQL queries")
print("\n📝 Sample queries:")
for name, query in list(prometheus_queries.items())[:5]:
    print(f"\n{name}:")
    print(f"  {query[:80]}..." if len(query) > 80 else f"  {query}")

# =============================================================================
# CELL 5: Updated Prometheus Data Collection
# =============================================================================

def collect_enhanced_metrics(prom_client, namespace='self-healing-platform', hours=24):
    """
    Collect enhanced metrics from Prometheus.
    
    Args:
        prom_client: PrometheusClient instance
        namespace: Target namespace to filter
        hours: Hours of historical data
        
    Returns:
        DataFrame with all metrics
    """
    import pandas as pd
    from datetime import datetime, timedelta
    
    end_time = datetime.now()
    start_time = end_time - timedelta(hours=hours)
    
    all_data = []
    
    for metric_name, query in prometheus_queries.items():
        try:
            # Add namespace filter if applicable
            if 'namespace' in query and namespace:
                query = query.replace('namespace,', f'namespace="{namespace}",')
            
            result = prom_client.query_range(
                query=query,
                start=start_time,
                end=end_time,
                step='5m'
            )
            
            for series in result:
                labels = series.get('metric', {})
                for timestamp, value in series.get('values', []):
                    all_data.append({
                        'timestamp': datetime.fromtimestamp(float(timestamp)),
                        'metric': metric_name,
                        'value': float(value),
                        **labels
                    })
                    
            print(f"  ✅ {metric_name}: {len(result)} series")
            
        except Exception as e:
            print(f"  ⚠️ {metric_name}: {e}")
    
    df = pd.DataFrame(all_data)
    print(f"\n📊 Total samples collected: {len(df)}")
    return df

# =============================================================================
# CELL 6: Feature Engineering with Enhanced Metrics
# =============================================================================

def engineer_enhanced_features(df, metric_definitions):
    """
    Engineer features from collected metrics.
    
    Includes:
    - Normalization based on thresholds
    - Rate of change calculations
    - Rolling statistics
    - Cross-metric correlations
    """
    import numpy as np
    
    features = df.pivot_table(
        index='timestamp',
        columns='metric',
        values='value',
        aggfunc='mean'
    ).reset_index()
    
    # Get thresholds for normalization
    thresholds = get_thresholds(list(df['metric'].unique()))
    
    # 1. Normalize metrics by their critical thresholds
    for col in features.columns:
        if col == 'timestamp':
            continue
        if col in thresholds and thresholds[col][1]:  # Has critical threshold
            features[f'{col}_normalized'] = features[col] / thresholds[col][1]
        else:
            # Standard normalization for metrics without thresholds
            features[f'{col}_normalized'] = (features[col] - features[col].mean()) / features[col].std()
    
    # 2. Calculate rates of change
    for col in features.columns:
        if col.endswith('_normalized'):
            base_col = col.replace('_normalized', '')
            features[f'{base_col}_rate'] = features[col].diff().fillna(0)
    
    # 3. Rolling statistics (1-hour window = 12 samples at 5min intervals)
    window = 12
    for col in features.columns:
        if col.endswith('_normalized'):
            features[f'{col}_rolling_mean'] = features[col].rolling(window).mean()
            features[f'{col}_rolling_std'] = features[col].rolling(window).std()
    
    # 4. Add time features
    features['hour'] = features['timestamp'].dt.hour
    features['day_of_week'] = features['timestamp'].dt.dayofweek
    features['is_business_hours'] = features['hour'].between(9, 17).astype(int)
    features['is_weekend'] = features['day_of_week'].isin([5, 6]).astype(int)
    
    # 5. Create severity scores based on thresholds
    for col in features.columns:
        if col in thresholds:
            warning, critical = thresholds[col]
            if warning and critical:
                features[f'{col}_severity'] = np.where(
                    features[col] >= critical, 2,
                    np.where(features[col] >= warning, 1, 0)
                )
    
    return features.dropna()

# =============================================================================
# CELL 7: Multi-Model Training (Different Anomaly Types)
# =============================================================================

from sklearn.ensemble import IsolationForest
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
import joblib

def train_category_models(features_df):
    """
    Train separate Isolation Forest models for different anomaly categories.
    """
    models = {}
    
    # Define feature sets for each category
    category_features = {
        AnomalyCategory.RESOURCE: [
            'node_cpu_utilization_normalized', 'node_memory_utilization_normalized',
            'pod_cpu_utilization_normalized', 'pod_memory_utilization_normalized',
            'node_cpu_saturation_normalized', 'pod_cpu_throttled_percent_normalized'
        ],
        AnomalyCategory.STABILITY: [
            'container_restart_rate_1h_normalized', 'pod_crash_loop_backoff_normalized',
            'pod_oom_killed_normalized', 'pods_pending_normalized',
            'pods_not_ready_normalized', 'deployment_replicas_unavailable_normalized'
        ],
        AnomalyCategory.PERFORMANCE: [
            'node_disk_read_latency_ms_normalized', 'node_disk_write_latency_ms_normalized',
            'node_disk_io_utilization_normalized', 'pod_cpu_throttled_percent_normalized'
        ],
        AnomalyCategory.NETWORK: [
            'node_network_errors_normalized', 'node_network_drops_normalized',
            'node_tcp_retransmit_rate_normalized', 'pod_network_errors_normalized'
        ]
    }
    
    for category, feature_cols in category_features.items():
        # Filter to available features
        available_features = [f for f in feature_cols if f in features_df.columns]
        
        if len(available_features) < 2:
            print(f"⚠️ {category.value}: Not enough features ({len(available_features)})")
            continue
        
        print(f"\n🔧 Training {category.value} model with {len(available_features)} features...")
        
        X = features_df[available_features].values
        
        # Get category-specific config
        config = ISOLATION_FOREST_CONFIGS[category]
        
        # Create pipeline
        pipeline = Pipeline([
            ('scaler', StandardScaler()),
            ('isolation_forest', IsolationForest(**config))
        ])
        
        pipeline.fit(X)
        models[category] = {
            'pipeline': pipeline,
            'features': available_features,
            'config': config
        }
        
        # Evaluate
        predictions = pipeline.predict(X)
        anomaly_rate = (predictions == -1).sum() / len(predictions) * 100
        print(f"   ✅ Trained - Anomaly rate: {anomaly_rate:.2f}%")
    
    return models

# =============================================================================
# CELL 8: Save Enhanced Models
# =============================================================================

def save_enhanced_models(models, base_path='/mnt/models'):
    """
    Save category-specific models in KServe-compatible format.
    """
    from pathlib import Path
    
    base_path = Path(base_path)
    
    for category, model_data in models.items():
        model_dir = base_path / f'anomaly-detector-{category.value}'
        model_dir.mkdir(parents=True, exist_ok=True)
        
        model_path = model_dir / 'model.pkl'
        joblib.dump(model_data['pipeline'], model_path)
        
        # Save metadata
        metadata = {
            'category': category.value,
            'features': model_data['features'],
            'config': model_data['config']
        }
        
        import json
        metadata_path = model_dir / 'metadata.json'
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2)
        
        print(f"✅ Saved {category.value} model to {model_path}")
        print(f"   Features: {len(model_data['features'])}")
        print(f"   Size: {model_path.stat().st_size / 1024:.2f} KB")

# =============================================================================
# CELL 9: Combined Model for General Detection
# =============================================================================

def train_combined_model(features_df):
    """
    Train a single combined model using all enhanced metrics.
    This is your main anomaly-detector model for KServe.
    """
    # Use all normalized features
    feature_cols = [c for c in features_df.columns if c.endswith('_normalized')]
    
    print(f"🔧 Training combined model with {len(feature_cols)} features...")
    
    X = features_df[feature_cols].values
    
    # Use resource config as base (most balanced)
    config = ISOLATION_FOREST_CONFIGS[AnomalyCategory.RESOURCE].copy()
    
    pipeline = Pipeline([
        ('scaler', StandardScaler()),
        ('isolation_forest', IsolationForest(**config))
    ])
    
    pipeline.fit(X)
    
    predictions = pipeline.predict(X)
    anomaly_rate = (predictions == -1).sum() / len(predictions) * 100
    
    print(f"✅ Combined model trained")
    print(f"   Features: {len(feature_cols)}")
    print(f"   Anomaly rate: {anomaly_rate:.2f}%")
    
    return pipeline, feature_cols

# =============================================================================
# CELL 10: Full Pipeline Integration
# =============================================================================

# Put it all together in your existing notebook:

"""
# 1. Collect data with enhanced metrics
raw_data = collect_enhanced_metrics(prom_client, namespace='self-healing-platform', hours=24)

# 2. Engineer features
features_df = engineer_enhanced_features(raw_data, TARGET_METRICS_ENHANCED)
print(f"Engineered features: {features_df.shape}")

# 3. Option A: Train category-specific models
category_models = train_category_models(features_df)
save_enhanced_models(category_models)

# 4. Option B: Train single combined model (recommended for KServe)
combined_pipeline, feature_names = train_combined_model(features_df)

# 5. Save combined model (your existing code works here)
from pathlib import Path
MODELS_DIR = Path('/mnt/models') if Path('/mnt/models').exists() else Path('/opt/app-root/src/models')
MODEL_NAME = 'anomaly-detector'
MODEL_DIR = MODELS_DIR / MODEL_NAME
MODEL_DIR.mkdir(parents=True, exist_ok=True)

model_path = MODEL_DIR / 'model.pkl'
joblib.dump(combined_pipeline, model_path)

# Save feature names for inference
import json
metadata_path = MODEL_DIR / 'features.json'
with open(metadata_path, 'w') as f:
    json.dump({'features': feature_names}, f)

print(f"💾 Saved model to: {model_path}")
"""

# =============================================================================
# SUMMARY: Metrics Enhancement
# =============================================================================

print("""
╔══════════════════════════════════════════════════════════════════╗
║           ENHANCED METRICS SUMMARY                               ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  ORIGINAL (5 metrics):                                          ║
║    • node_cpu_utilization                                        ║
║    • node_memory_utilization                                     ║
║    • pod_cpu_usage                                               ║
║    • pod_memory_usage                                            ║
║    • container_restart_count                                     ║
║                                                                  ║
║  ENHANCED (30+ metrics):                                         ║
║                                                                  ║
║  CPU (6 new):                                                    ║
║    • node_cpu_saturation - processes waiting for CPU             ║
║    • node_cpu_iowait - disk bottleneck indicator                 ║
║    • node_cpu_steal - noisy neighbor detection                   ║
║    • node_load_per_cpu - normalized load average                 ║
║    • pod_cpu_throttled_percent - throttling detection            ║
║    • pod_cpu_request_utilization - HPA input                     ║
║                                                                  ║
║  Memory (5 new):                                                 ║
║    • node_memory_pressure - pressure stall info                  ║
║    • node_memory_swap_usage - swap as pressure signal            ║
║    • node_memory_oom_kills - OOM event tracking                  ║
║    • pod_memory_utilization - vs limit                           ║
║    • pod_memory_swap - should be zero                            ║
║                                                                  ║
║  Disk I/O (7 new):                                               ║
║    • node_disk_io_utilization - % time doing I/O                 ║
║    • node_disk_read_latency_ms - read performance                ║
║    • node_disk_write_latency_ms - write performance              ║
║    • node_disk_iops - total operations                           ║
║    • node_disk_throughput_mb - bandwidth                         ║
║    • node_disk_await - queue + service time                      ║
║    • node_inode_utilization - often overlooked!                  ║
║                                                                  ║
║  Network (8 new):                                                ║
║    • node_network_errors - interface errors                      ║
║    • node_network_drops - packet drops                           ║
║    • node_conntrack_utilization - connection table               ║
║    • node_tcp_retransmit_rate - network quality                  ║
║    • node_socket_overflow - listen queue issues                  ║
║    • pod_network_errors - per-pod errors                         ║
║    • pod_network_dropped_packets - per-pod drops                 ║
║                                                                  ║
║  Stability (7 new):                                              ║
║    • container_restart_rate_1h - recent restarts                 ║
║    • pod_crash_loop_backoff - CrashLoopBackOff state             ║
║    • pod_oom_killed - OOMKilled terminations                     ║
║    • pod_image_pull_backoff - image pull failures                ║
║    • pods_pending - scheduling issues                            ║
║    • pods_not_ready - readiness failures                         ║
║    • deployment_replicas_unavailable - deployment health         ║
║                                                                  ║
║  Control Plane (if enabled):                                     ║
║    • apiserver_request_latency_p99 - API performance             ║
║    • etcd_leader_changes - cluster stability                     ║
║    • scheduler_pending_pods - scheduling backlog                 ║
║                                                                  ║
╠══════════════════════════════════════════════════════════════════╣
║  BENEFITS:                                                       ║
║    ✓ Better anomaly detection (more signal)                     ║
║    ✓ Root cause hints (which subsystem is affected)              ║
║    ✓ Earlier detection (leading indicators)                     ║
║    ✓ Fewer false positives (context from multiple metrics)      ║
╚══════════════════════════════════════════════════════════════════╝
""")
