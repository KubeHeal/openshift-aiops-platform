# Predictive Scaling and Cost Optimization

*Part 14 of the OpenShift AI Ops Learning Series*

---

## Introduction

Proactive scaling prevents resource exhaustion before it impacts services. This guide covers forecasting resource demand, implementing predictive scaling, and optimizing costs through intelligent resource allocation.

---

## What You'll Learn

- Forecasting resource demand
- Implementing predictive scaling
- Planning capacity requirements
- Optimizing resource allocation
- Balancing performance and cost

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 4: Time Series Detection](04-time-series-anomaly-detection.md)
- [ ] Completed [Blog 11: Memory Exhaustion](11-scenario-memory-exhaustion.md)
- [ ] Historical resource usage data available
- [ ] HPA (Horizontal Pod Autoscaler) configured

---

## Step 1: Forecast Resource Demand

### Open the Predictive Scaling Notebook

1. Navigate to `notebooks/08-advanced-scenarios/`
2. Open `predictive-scaling-capacity-planning.ipynb`

### Train Forecasting Model

```python
from sklearn.ensemble import RandomForestRegressor
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

def train_demand_forecaster(historical_data):
    """
    Train model to forecast resource demand.

    Args:
        historical_data: DataFrame with historical CPU/memory usage

    Returns:
        Trained forecasting model
    """
    # Feature engineering
    historical_data['hour'] = historical_data['timestamp'].dt.hour
    historical_data['day_of_week'] = historical_data['timestamp'].dt.dayofweek
    historical_data['cpu_rolling_mean'] = historical_data['cpu_usage'].rolling(24).mean()
    historical_data['memory_rolling_mean'] = historical_data['memory_usage'].rolling(24).mean()

    # Features
    X = historical_data[['hour', 'day_of_week', 'cpu_rolling_mean', 'memory_rolling_mean']]
    y = historical_data[['cpu_usage', 'memory_usage']]  # Multi-output

    # Train model
    from sklearn.multioutput import MultiOutputRegressor

    model = Pipeline([
        ('scaler', StandardScaler()),
        ('regressor', MultiOutputRegressor(RandomForestRegressor(n_estimators=100)))
    ])

    model.fit(X, y)

    return model
```

### Generate Forecasts

```python
def forecast_demand(model, current_metrics, hours_ahead=24):
    """
    Forecast resource demand for next N hours.

    Args:
        model: Trained forecasting model
        current_metrics: Current CPU/memory usage
        hours_ahead: Hours to forecast

    Returns:
        Forecast DataFrame
    """
    forecasts = []

    for hour in range(hours_ahead):
        future_time = datetime.now() + timedelta(hours=hour)

        features = pd.DataFrame([{
            'hour': future_time.hour,
            'day_of_week': future_time.weekday(),
            'cpu_rolling_mean': current_metrics['cpu'],
            'memory_rolling_mean': current_metrics['memory']
        }])

        prediction = model.predict(features)[0]

        forecasts.append({
            'timestamp': future_time,
            'predicted_cpu': prediction[0],
            'predicted_memory': prediction[1]
        })

    return pd.DataFrame(forecasts)
```

---

## Step 2: Implement Predictive Scaling

### Scale Before Demand Spike

```python
def predictive_scale(deployment_name, namespace, forecast_df, threshold=0.80):
    """
    Scale deployment proactively based on forecast.

    Args:
        deployment_name: Deployment name
        namespace: Kubernetes namespace
        forecast_df: Forecast DataFrame
        threshold: Resource threshold to trigger scaling
    """
    # Check if forecast exceeds threshold
    max_cpu = forecast_df['predicted_cpu'].max()
    max_memory = forecast_df['predicted_memory'].max()

    if max_cpu > threshold or max_memory > threshold:
        # Calculate required replicas
        current_replicas = get_current_replicas(deployment_name, namespace)
        required_replicas = int(np.ceil(current_replicas * (max(max_cpu, max_memory) / threshold)))

        # Scale proactively
        scale_deployment(deployment_name, namespace, required_replicas)

        print(f"✅ Proactive scaling: {current_replicas} → {required_replicas} replicas")
        print(f"   Reason: Forecasted {max_cpu:.1%} CPU, {max_memory:.1%} memory")
```

---

## Step 3: Cost Optimization

### Right-Size Resources

```python
def optimize_resource_allocation(namespace):
    """
    Optimize resource requests/limits based on actual usage.

    Args:
        namespace: Kubernetes namespace
    """
    # Get actual usage vs requests
    pods = get_pod_metrics(namespace)

    for pod in pods:
        cpu_usage = pod['cpu_usage']
        cpu_request = pod['cpu_request']
        memory_usage = pod['memory_usage']
        memory_request = pod['memory_request']

        # Calculate utilization
        cpu_util = cpu_usage / cpu_request if cpu_request > 0 else 0
        memory_util = memory_usage / memory_request if memory_request > 0 else 0

        # Recommend optimization
        if cpu_util < 0.5:  # Using <50% of request
            recommended_cpu = cpu_request * 0.7  # Reduce by 30%
            print(f"💡 {pod['name']}: Reduce CPU request {cpu_request} → {recommended_cpu}")

        if memory_util < 0.5:
            recommended_memory = memory_request * 0.7
            print(f"💡 {pod['name']}: Reduce memory request {memory_request} → {recommended_memory}")
```

---

## What Just Happened?

You've implemented predictive scaling:

### 1. Demand Forecasting

- **Time series models**: Forecast future resource needs
- **Multi-output regression**: Predict CPU and memory simultaneously
- **Context-aware**: Considers time of day, day of week

### 2. Proactive Scaling

- **Pre-emptive action**: Scale before demand hits
- **Threshold-based**: Trigger when forecast exceeds limits
- **Replica calculation**: Determine optimal replica count

### 3. Cost Optimization

- **Right-sizing**: Adjust requests based on actual usage
- **Waste reduction**: Identify over-provisioned resources
- **Performance balance**: Maintain performance while reducing cost

---

## Next Steps

Explore security automation:

1. **Security Automation**: [Blog 15: Security Automation](15-security-incident-automation.md)

---

## Related Resources

- **Notebook**: `notebooks/08-advanced-scenarios/predictive-scaling-capacity-planning.ipynb`
- **ADRs**:
  - [ADR-010: OpenShift Data Foundation](docs/adrs/010-openshift-data-foundation-requirement.md)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/tosin2013/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/14-predictive-scaling-cost-optimization.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 14 of 15 in the OpenShift AI Ops Learning Series*
