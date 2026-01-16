# Time Series Anomaly Detection for Kubernetes

*Part 4 of the OpenShift AI Ops Learning Series*

---

## Introduction

Time matters in anomaly detection. A sudden CPU spike at 3 AM might be normal (scheduled backup), but the same spike at 3 PM during peak traffic could indicate a problem. Time series anomaly detection captures these temporal patterns that simple threshold-based methods miss.

This guide explores ARIMA and Prophet for time series forecasting, using predicted values to detect anomalies when actual metrics deviate significantly from expected patterns.

---

## What You'll Learn

- Why time matters in anomaly detection
- Understanding ARIMA (AutoRegressive Integrated Moving Average)
- Using Prophet for seasonal pattern detection
- Detecting anomalies via forecast deviations
- Handling gradual degradation vs. sudden spikes

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 2: Collecting Data for AI Ops](02-collecting-data-for-aiops.md)
- [ ] Completed [Blog 3: Isolation Forest Anomaly Detection](03-isolation-forest-anomaly-detection.md)
- [ ] Time series data collected from Prometheus
- [ ] Statsmodels and Prophet libraries installed

---

## Understanding Time Series Anomalies

### Why Time Matters

In Kubernetes, many patterns are time-dependent:

- **Daily cycles**: CPU usage peaks during business hours
- **Weekly patterns**: Lower usage on weekends
- **Seasonal trends**: Gradual increases as user base grows
- **Event-driven spikes**: Deployments, scaling events, batch jobs

### Types of Time Series Anomalies

1. **Point anomalies**: Single data point deviates (sudden spike)
2. **Contextual anomalies**: Normal value at wrong time (high CPU at 3 AM)
3. **Collective anomalies**: Sequence of values is anomalous (gradual memory leak)
4. **Trend anomalies**: Deviation from expected trend (unexpected growth)

---

## Step 1: Prepare Time Series Data

### Open the Time Series Notebook

1. Navigate to `notebooks/02-anomaly-detection/`
2. Open `02-time-series-anomaly-detection.ipynb`

### Load Historical Metrics

```python
import pandas as pd
import numpy as np

# Load metrics from Prometheus (collected in Blog 2)
metrics = pd.read_parquet('/opt/app-root/src/data/prometheus/cpu_metrics.parquet')

# Ensure datetime index
metrics['timestamp'] = pd.to_datetime(metrics['timestamp'])
metrics = metrics.set_index('timestamp')

# Resample to hourly (if needed)
metrics = metrics.resample('1H').mean()

print(f"📊 Time series data: {len(metrics)} points")
print(f"   Date range: {metrics.index.min()} to {metrics.index.max()}")
```

### Visualize Time Series

```python
import matplotlib.pyplot as plt

plt.figure(figsize=(14, 6))
plt.plot(metrics.index, metrics['cpu_usage'], label='CPU Usage')
plt.xlabel('Time')
plt.ylabel('CPU Usage (%)')
plt.title('CPU Usage Over Time')
plt.legend()
plt.grid(True)
plt.show()
```

---

## Step 2: ARIMA Forecasting

ARIMA (AutoRegressive Integrated Moving Average) is a classic time series forecasting method.

### Understanding ARIMA Components

- **AR (AutoRegressive)**: Uses past values to predict future
- **I (Integrated)**: Differencing to make series stationary
- **MA (Moving Average)**: Uses past forecast errors

### Fit ARIMA Model

```python
from statsmodels.tsa.arima.model import ARIMA
import warnings
warnings.filterwarnings('ignore')

# Split into train/test
train_size = int(len(metrics) * 0.8)
train = metrics[:train_size]
test = metrics[train_size:]

# Fit ARIMA model
# Order: (p, d, q) where:
#   p = autoregressive order
#   d = differencing order
#   q = moving average order
model = ARIMA(train['cpu_usage'], order=(2, 1, 2))
fitted_model = model.fit()

print(f"✅ ARIMA model fitted")
print(f"   AIC: {fitted_model.aic:.2f}")
```

### Make Forecasts

```python
# Forecast next 24 hours
forecast = fitted_model.forecast(steps=24)

# Calculate forecast intervals (confidence bands)
forecast_ci = fitted_model.get_forecast(steps=24).conf_int()

# Plot results
plt.figure(figsize=(14, 6))
plt.plot(train.index[-48:], train['cpu_usage'][-48:], label='Historical')
plt.plot(test.index[:24], test['cpu_usage'][:24], label='Actual', color='green')
plt.plot(test.index[:24], forecast, label='Forecast', color='red')
plt.fill_between(test.index[:24],
                 forecast_ci.iloc[:, 0],
                 forecast_ci.iloc[:, 1],
                 alpha=0.2, color='red', label='95% Confidence')
plt.xlabel('Time')
plt.ylabel('CPU Usage (%)')
plt.title('ARIMA Forecast')
plt.legend()
plt.grid(True)
plt.show()
```

---

## Step 3: Prophet Forecasting

Prophet is Facebook's time series forecasting tool, excellent for handling seasonality.

### Why Prophet?

- ✅ **Automatic seasonality**: Detects daily, weekly, yearly patterns
- ✅ **Holiday effects**: Handles special events
- ✅ **Robust to missing data**: Works with gaps in time series
- ✅ **Interpretable**: Provides trend and seasonality components

### Fit Prophet Model

```python
from prophet import Prophet

# Prepare data for Prophet (requires 'ds' and 'y' columns)
prophet_data = pd.DataFrame({
    'ds': metrics.index,
    'y': metrics['cpu_usage'].values
})

# Split train/test
train_prophet = prophet_data[:train_size]
test_prophet = prophet_data[train_size:]

# Create and fit model
prophet_model = Prophet(
    yearly_seasonality=True,   # Annual patterns
    weekly_seasonality=True,    # Weekly patterns
    daily_seasonality=True,     # Daily patterns
    changepoint_prior_scale=0.05  # Flexibility for trend changes
)
prophet_model.fit(train_prophet)

print("✅ Prophet model fitted")
```

### Make Forecasts

```python
# Create future dataframe (next 24 hours)
future = prophet_model.make_future_dataframe(periods=24, freq='H')

# Forecast
forecast_prophet = prophet_model.predict(future)

# Plot components
fig = prophet_model.plot_components(forecast_prophet)
plt.show()

# Plot forecast
fig = prophet_model.plot(forecast_prophet)
plt.show()
```

### Understanding Prophet Components

Prophet decomposes time series into:
- **Trend**: Long-term direction (increasing, decreasing, stable)
- **Seasonality**: Repeating patterns (daily, weekly)
- **Holidays**: Special event effects
- **Noise**: Random variation

---

## Step 4: Detect Anomalies via Forecast Deviation

Anomalies are detected when actual values deviate significantly from forecasts.

### Calculate Forecast Errors

```python
def detect_anomalies_via_forecast(actual, forecast, forecast_std, threshold=2.0):
    """
    Detect anomalies when actual deviates from forecast by more than threshold standard deviations.

    Args:
        actual: Actual values
        forecast: Forecasted values
        forecast_std: Standard deviation of forecast errors
        threshold: Number of standard deviations for anomaly threshold

    Returns:
        Boolean array indicating anomalies
    """
    # Calculate forecast error
    errors = actual - forecast

    # Calculate z-scores
    z_scores = errors / forecast_std

    # Anomalies are points beyond threshold
    anomalies = np.abs(z_scores) > threshold

    return anomalies, z_scores
```

### Apply to ARIMA Forecast

```python
# Get forecast for test period
arima_forecast = fitted_model.forecast(steps=len(test))

# Calculate forecast standard deviation (from residuals)
forecast_std = np.std(fitted_model.resid)

# Detect anomalies
anomalies_arima, z_scores_arima = detect_anomalies_via_forecast(
    test['cpu_usage'].values,
    arima_forecast,
    forecast_std,
    threshold=2.0
)

print(f"🔍 ARIMA detected {anomalies_arima.sum()} anomalies")
```

### Apply to Prophet Forecast

```python
# Get forecast for test period
prophet_forecast_test = forecast_prophet[train_size:train_size+len(test)]

# Prophet provides uncertainty intervals
forecast_std_prophet = (prophet_forecast_test['yhat_upper'] -
                        prophet_forecast_test['yhat_lower']) / 4  # Approximate std

# Detect anomalies
anomalies_prophet, z_scores_prophet = detect_anomalies_via_forecast(
    test['cpu_usage'].values,
    prophet_forecast_test['yhat'].values,
    forecast_std_prophet.values,
    threshold=2.0
)

print(f"🔍 Prophet detected {anomalies_prophet.sum()} anomalies")
```

### Visualize Anomalies

```python
plt.figure(figsize=(14, 8))

# Plot actual vs forecast
plt.subplot(2, 1, 1)
plt.plot(test.index, test['cpu_usage'], label='Actual', color='blue')
plt.plot(test.index, arima_forecast, label='ARIMA Forecast', color='red')
plt.scatter(test.index[anomalies_arima],
           test['cpu_usage'].values[anomalies_arima],
           color='red', s=100, marker='x', label='Anomalies', zorder=5)
plt.xlabel('Time')
plt.ylabel('CPU Usage (%)')
plt.title('ARIMA Anomaly Detection')
plt.legend()
plt.grid(True)

# Plot z-scores
plt.subplot(2, 1, 2)
plt.plot(test.index, z_scores_arima, label='Z-Scores', color='purple')
plt.axhline(y=2.0, color='red', linestyle='--', label='Threshold (+2σ)')
plt.axhline(y=-2.0, color='red', linestyle='--', label='Threshold (-2σ)')
plt.fill_between(test.index, -2, 2, alpha=0.2, color='green', label='Normal Range')
plt.xlabel('Time')
plt.ylabel('Z-Score')
plt.title('Anomaly Scores')
plt.legend()
plt.grid(True)

plt.tight_layout()
plt.show()
```

---

## Step 5: Evaluate Performance

If you have labeled anomaly data, evaluate detection performance.

### Calculate Metrics

```python
from sklearn.metrics import precision_score, recall_score, f1_score, confusion_matrix

# Assuming you have ground truth labels
y_true = test['is_anomaly'].values  # From synthetic data

# Calculate metrics for ARIMA
precision_arima = precision_score(y_true, anomalies_arima)
recall_arima = recall_score(y_true, anomalies_arima)
f1_arima = f1_score(y_true, anomalies_arima)

print("📊 ARIMA Performance:")
print(f"   Precision: {precision_arima:.3f}")
print(f"   Recall: {recall_arima:.3f}")
print(f"   F1-Score: {f1_arima:.3f}")

# Calculate metrics for Prophet
precision_prophet = precision_score(y_true, anomalies_prophet)
recall_prophet = recall_score(y_true, anomalies_prophet)
f1_prophet = f1_score(y_true, anomalies_prophet)

print("\n📊 Prophet Performance:")
print(f"   Precision: {precision_prophet:.3f}")
print(f"   Recall: {recall_prophet:.3f}")
print(f"   F1-Score: {f1_prophet:.3f}")
```

---

## Step 6: Save Models for Production

### Save ARIMA Model

```python
import joblib

# Save ARIMA model
arima_path = '/opt/app-root/src/models/timeseries-predictor/arima_model.pkl'
joblib.dump(fitted_model, arima_path)
print(f"✅ ARIMA model saved: {arima_path}")
```

### Save Prophet Model

```python
# Save Prophet model
prophet_path = '/opt/app-root/src/models/timeseries-predictor/prophet_model.pkl'
with open(prophet_path, 'wb') as f:
    pickle.dump(prophet_model, f)
print(f"✅ Prophet model saved: {prophet_path}")
```

---

## What Just Happened?

You've implemented time series anomaly detection:

### 1. ARIMA Forecasting

- **Classical approach**: Well-established statistical method
- **Good for**: Short-term forecasts, stationary series
- **Limitations**: Requires manual parameter tuning, doesn't handle seasonality well

### 2. Prophet Forecasting

- **Modern approach**: Designed for business time series
- **Good for**: Long-term forecasts, strong seasonality, missing data
- **Advantages**: Automatic seasonality detection, interpretable components

### 3. Anomaly Detection

- **Forecast deviation**: Anomalies are points far from predicted values
- **Statistical threshold**: Uses z-scores (standard deviations)
- **Context-aware**: Considers time of day, day of week

### 4. Performance Evaluation

- **Precision**: How many detected anomalies are real
- **Recall**: How many real anomalies are detected
- **F1-Score**: Balanced measure of both

---

## When to Use Each Method

### Use ARIMA When:
- Short-term forecasting (hours to days)
- Series is relatively stationary
- You need fast inference
- Simple patterns without strong seasonality

### Use Prophet When:
- Long-term forecasting (weeks to months)
- Strong daily/weekly seasonality
- Missing data or irregular intervals
- Need interpretable trend/seasonality components

### Use Both:
- Ensemble approach: Combine predictions
- Validation: Cross-check anomalies detected by both
- Robustness: Different methods catch different anomaly types

---

## Next Steps

Explore advanced time series methods:

1. **Deep Learning**: [Blog 5: LSTM Deep Learning](05-lstm-deep-learning-anomalies.md) for sequence-based detection
2. **Ensemble Methods**: [Blog 6: Ensemble Anomaly Methods](06-ensemble-anomaly-methods.md) to combine multiple detectors
3. **Predictive Scaling**: [Blog 14: Predictive Scaling](14-predictive-scaling-cost-optimization.md) uses time series for capacity planning

---

## Related Resources

- **Notebook**: `notebooks/02-anomaly-detection/02-time-series-anomaly-detection.ipynb`
- **ADRs**:
  - [ADR-013: Data Collection and Preprocessing](docs/adrs/013-data-collection-and-preprocessing-workflows.md)
- **Research**:
  - [Prophet Paper](https://peerj.com/articles/3190/) (Taylor & Letham, 2018)
  - [ARIMA Reference](https://otexts.com/fpp2/arima.html) (Hyndman & Athanasopoulos)
- **Libraries**:
  - [Statsmodels ARIMA](https://www.statsmodels.org/stable/generated/statsmodels.tsa.arima.model.ARIMA.html)
  - [Prophet Documentation](https://facebook.github.io/prophet/)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/tosin2013/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/04-time-series-anomaly-detection.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 4 of 15 in the OpenShift AI Ops Learning Series*
