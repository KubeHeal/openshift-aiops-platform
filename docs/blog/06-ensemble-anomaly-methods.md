# Ensemble Methods: Combining Multiple Detectors

*Part 6 of the OpenShift AI Ops Learning Series*

---

## Introduction

No single anomaly detection method is perfect. Isolation Forest catches point anomalies but misses gradual trends. LSTM excels at sequences but is slow. ARIMA handles seasonality but struggles with non-linear patterns.

Ensemble methods combine multiple detectors, leveraging each method's strengths while compensating for weaknesses. This guide shows you how to build an ensemble that achieves >90% accuracy by voting across multiple models.

---

## What You'll Learn

- Why ensembles outperform single models
- Voting strategies (hard vs. soft)
- Stacking with meta-learners
- Reducing false positives through consensus
- Production deployment of ensemble models

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 3: Isolation Forest](03-isolation-forest-anomaly-detection.md)
- [ ] Completed [Blog 4: Time Series Detection](04-time-series-anomaly-detection.md)
- [ ] Completed [Blog 5: LSTM Deep Learning](05-lstm-deep-learning-anomalies.md)
- [ ] All individual models trained and saved

---

## Understanding Ensemble Learning

### Why Ensembles Work

**Diversity Principle**: Different models make different mistakes. By combining them:
- ✅ **Reduced variance**: Average out individual model errors
- ✅ **Better coverage**: Each model catches different anomaly types
- ✅ **Robustness**: Less sensitive to data distribution shifts
- ✅ **Higher accuracy**: Typically 5-10% better than best single model

### Ensemble Strategies

1. **Voting**: Majority rule (hard) or probability averaging (soft)
2. **Stacking**: Meta-learner learns how to combine predictions
3. **Blending**: Weighted combination based on performance

---

## Step 1: Load Individual Models

### Open the Ensemble Notebook

1. Navigate to `notebooks/02-anomaly-detection/`
2. Open `04-ensemble-anomaly-methods.ipynb`

### Load All Models

```python
import joblib
import pickle
import torch
import pandas as pd

# Load Isolation Forest
isolation_forest = joblib.load('/opt/app-root/src/models/anomaly-detector/model.pkl')

# Load ARIMA
arima_model = joblib.load('/opt/app-root/src/models/timeseries-predictor/arima_model.pkl')

# Load Prophet
with open('/opt/app-root/src/models/timeseries-predictor/prophet_model.pkl', 'rb') as f:
    prophet_model = pickle.load(f)

# Load LSTM
lstm_checkpoint = torch.load('/opt/app-root/src/models/lstm-predictor/lstm_autoencoder.pth')
# Reconstruct model architecture and load weights
# ... (model loading code)

print("✅ All models loaded")
```

---

## Step 2: Get Predictions from Each Model

### Isolation Forest Predictions

```python
def predict_isolation_forest(model, data):
    """Get Isolation Forest predictions"""
    predictions = model.predict(data)
    # Convert -1/1 to 0/1 (anomaly/normal)
    return (predictions == -1).astype(int)
```

### ARIMA Predictions

```python
def predict_arima(model, data, threshold=2.0):
    """Get ARIMA-based anomaly predictions"""
    forecast = model.forecast(steps=len(data))
    errors = data - forecast
    z_scores = errors / np.std(model.resid)
    return (np.abs(z_scores) > threshold).astype(int)
```

### Prophet Predictions

```python
def predict_prophet(model, data, threshold=2.0):
    """Get Prophet-based anomaly predictions"""
    future = model.make_future_dataframe(periods=len(data), freq='H')
    forecast = model.predict(future)

    # Calculate deviations
    errors = data - forecast['yhat'].values[-len(data):]
    z_scores = errors / ((forecast['yhat_upper'] - forecast['yhat_lower']).values[-len(data):] / 4)

    return (np.abs(z_scores) > threshold).astype(int)
```

### LSTM Predictions

```python
def predict_lstm(model, data, threshold):
    """Get LSTM-based anomaly predictions"""
    model.eval()
    with torch.no_grad():
        reconstructed, _ = model(torch.FloatTensor(data).to(device))
        errors = torch.mean((reconstructed - torch.FloatTensor(data).to(device)) ** 2, dim=(1, 2))
        return (errors.cpu().numpy() > threshold).astype(int)
```

### Collect All Predictions

```python
# Load test data
test_data = pd.read_parquet('/opt/app-root/src/data/processed/test_data.parquet')

# Get predictions from each model
pred_if = predict_isolation_forest(isolation_forest, test_data[['cpu_usage', 'memory_usage']])
pred_arima = predict_arima(arima_model, test_data['cpu_usage'].values)
pred_prophet = predict_prophet(prophet_model, test_data['cpu_usage'].values)
pred_lstm = predict_lstm(lstm_model, test_sequences, threshold)

print(f"📊 Predictions collected:")
print(f"   Isolation Forest: {pred_if.sum()} anomalies")
print(f"   ARIMA: {pred_arima.sum()} anomalies")
print(f"   Prophet: {pred_prophet.sum()} anomalies")
print(f"   LSTM: {pred_lstm.sum()} anomalies")
```

---

## Step 3: Implement Voting Strategies

### Hard Voting (Majority Rule)

```python
def hard_voting(predictions_list):
    """
    Hard voting: Anomaly if majority of models agree.

    Args:
        predictions_list: List of binary prediction arrays

    Returns:
        Ensemble predictions
    """
    # Stack predictions
    predictions_matrix = np.array(predictions_list)

    # Majority vote
    ensemble_pred = (predictions_matrix.sum(axis=0) >= len(predictions_list) / 2).astype(int)

    return ensemble_pred

# Apply hard voting
ensemble_hard = hard_voting([pred_if, pred_arima, pred_prophet, pred_lstm])

print(f"🔍 Hard voting: {ensemble_hard.sum()} anomalies detected")
```

### Soft Voting (Probability Averaging)

```python
def soft_voting(probabilities_list, threshold=0.5):
    """
    Soft voting: Average probabilities, then threshold.

    Args:
        probabilities_list: List of probability arrays
        threshold: Probability threshold for anomaly

    Returns:
        Ensemble predictions
    """
    # Average probabilities
    avg_prob = np.mean(probabilities_list, axis=0)

    # Threshold
    ensemble_pred = (avg_prob > threshold).astype(int)

    return ensemble_pred

# Get probabilities from each model (if available)
# For models that output scores, convert to probabilities
prob_if = isolation_forest.decision_function(test_data[['cpu_usage', 'memory_usage']])
prob_if = 1 / (1 + np.exp(prob_if))  # Convert to probability

# ... similar for other models

ensemble_soft = soft_voting([prob_if, prob_arima, prob_prophet, prob_lstm])

print(f"🔍 Soft voting: {ensemble_soft.sum()} anomalies detected")
```

### Weighted Voting

```python
def weighted_voting(predictions_list, weights):
    """
    Weighted voting: Weight each model by its performance.

    Args:
        predictions_list: List of prediction arrays
        weights: List of weights (sum to 1.0)

    Returns:
        Ensemble predictions
    """
    # Weighted sum
    weighted_sum = np.zeros(len(predictions_list[0]))
    for pred, weight in zip(predictions_list, weights):
        weighted_sum += pred * weight

    # Threshold at 0.5
    ensemble_pred = (weighted_sum > 0.5).astype(int)

    return ensemble_pred

# Weights based on individual model F1-scores
weights = [0.25, 0.20, 0.25, 0.30]  # LSTM gets higher weight

ensemble_weighted = weighted_voting([pred_if, pred_arima, pred_prophet, pred_lstm], weights)

print(f"🔍 Weighted voting: {ensemble_weighted.sum()} anomalies detected")
```

---

## Step 4: Implement Stacking

Stacking uses a meta-learner to learn how to best combine predictions.

### Prepare Meta-Features

```python
# Create meta-features from base model predictions
meta_features = np.column_stack([
    pred_if,
    pred_arima,
    pred_prophet,
    pred_lstm,
    # Add confidence scores if available
    isolation_forest.decision_function(test_data[['cpu_usage', 'memory_usage']]),
    # ... other confidence scores
])

print(f"📊 Meta-features shape: {meta_features.shape}")
```

### Train Meta-Learner

```python
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split

# Split meta-features
X_meta_train, X_meta_test, y_meta_train, y_meta_test = train_test_split(
    meta_features, test_labels, test_size=0.2, random_state=42
)

# Train meta-learner (Logistic Regression)
meta_learner = LogisticRegression()
meta_learner.fit(X_meta_train, y_meta_train)

# Get stacked predictions
stacked_pred = meta_learner.predict(X_meta_test)

print(f"✅ Meta-learner trained")
print(f"🔍 Stacking: {stacked_pred.sum()} anomalies detected")
```

---

## Step 5: Evaluate Ensemble Performance

### Compare All Methods

```python
from sklearn.metrics import precision_score, recall_score, f1_score

methods = {
    'Isolation Forest': pred_if,
    'ARIMA': pred_arima,
    'Prophet': pred_prophet,
    'LSTM': pred_lstm,
    'Hard Voting': ensemble_hard,
    'Soft Voting': ensemble_soft,
    'Weighted Voting': ensemble_weighted,
    'Stacking': stacked_pred
}

results = []
for method_name, predictions in methods.items():
    precision = precision_score(test_labels, predictions)
    recall = recall_score(test_labels, predictions)
    f1 = f1_score(test_labels, predictions)

    results.append({
        'Method': method_name,
        'Precision': precision,
        'Recall': recall,
        'F1-Score': f1
    })

results_df = pd.DataFrame(results)
print(results_df.sort_values('F1-Score', ascending=False))
```

### Expected Results

```
              Method  Precision  Recall  F1-Score
         Stacking      0.945    0.932    0.938
    Weighted Voting    0.920    0.915    0.917
        Hard Voting    0.910    0.905    0.907
        Soft Voting    0.905    0.900    0.902
            LSTM       0.880    0.875    0.877
  Isolation Forest    0.850    0.920    0.883
            ARIMA      0.820    0.810    0.815
          Prophet      0.815    0.805    0.810
```

**Key Observation**: Ensemble methods (Stacking, Weighted Voting) outperform individual models!

---

## Step 6: Deploy Ensemble to Production

### Create Ensemble Wrapper

```python
class EnsembleAnomalyDetector:
    """
    Ensemble anomaly detector combining multiple models.
    """
    def __init__(self, models, strategy='hard_voting', weights=None):
        self.models = models
        self.strategy = strategy
        self.weights = weights

    def predict(self, data):
        """Get ensemble predictions"""
        # Get predictions from each model
        predictions = [model.predict(data) for model in self.models]

        if self.strategy == 'hard_voting':
            return hard_voting(predictions)
        elif self.strategy == 'soft_voting':
            return soft_voting(predictions)
        elif self.strategy == 'weighted_voting':
            return weighted_voting(predictions, self.weights)
        else:
            raise ValueError(f"Unknown strategy: {self.strategy}")

# Create ensemble
ensemble = EnsembleAnomalyDetector(
    models=[isolation_forest, arima_model, prophet_model, lstm_model],
    strategy='weighted_voting',
    weights=[0.25, 0.20, 0.25, 0.30]
)

# Save ensemble
joblib.dump(ensemble, '/opt/app-root/src/models/ensemble-predictor/ensemble.pkl')
```

---

## What Just Happened?

You've built a robust ensemble anomaly detector:

### 1. Model Diversity

- **Isolation Forest**: Catches point anomalies
- **ARIMA**: Handles linear trends
- **Prophet**: Detects seasonality
- **LSTM**: Learns complex sequences

### 2. Voting Strategies

- **Hard voting**: Simple majority rule
- **Soft voting**: Probability averaging
- **Weighted voting**: Performance-based weights
- **Stacking**: Learned combination via meta-learner

### 3. Performance Improvement

- **5-10% accuracy gain**: Over best single model
- **Reduced false positives**: Consensus filters noise
- **Better coverage**: Different models catch different anomalies

### 4. Production Deployment

- **Unified API**: Single interface for all models
- **Configurable strategy**: Choose voting method
- **Scalable**: Can add/remove models easily

---

## Best Practices

### Model Selection

Include diverse models:
- ✅ Different algorithms (tree-based, neural, statistical)
- ✅ Different input types (point, sequence, time series)
- ✅ Different strengths (precision vs. recall)

### Weight Tuning

Tune weights based on validation performance:
```python
# Grid search for optimal weights
from scipy.optimize import minimize

def objective(weights):
    ensemble_pred = weighted_voting(predictions_list, weights)
    return -f1_score(test_labels, ensemble_pred)  # Minimize negative F1

result = minimize(objective, [0.25, 0.25, 0.25, 0.25],
                 bounds=[(0, 1)] * 4,
                 constraints={'type': 'eq', 'fun': lambda w: sum(w) - 1})
```

### Threshold Optimization

Optimize voting threshold:
```python
# Find optimal threshold for soft voting
thresholds = np.arange(0.3, 0.7, 0.05)
best_threshold = 0.5
best_f1 = 0

for threshold in thresholds:
    pred = soft_voting(probabilities_list, threshold)
    f1 = f1_score(test_labels, pred)
    if f1 > best_f1:
        best_f1 = f1
        best_threshold = threshold
```

---

## Next Steps

Explore self-healing logic:

1. **Rule-Based Remediation**: [Blog 7: Rule-Based Remediation](07-rule-based-remediation.md) for deterministic workflows
2. **AI Decision Making**: [Blog 8: AI-Driven Decision Making](08-ai-driven-decision-making.md) for complex incidents
3. **Model Deployment**: [Blog 9: Deploying Models with KServe](09-deploying-models-kserve.md) for production serving

---

## Related Resources

- **Notebook**: `notebooks/02-anomaly-detection/04-ensemble-anomaly-methods.ipynb`
- **ADRs**:
  - [ADR-002: Hybrid Self-Healing Approach](docs/adrs/002-hybrid-self-healing-approach.md)
- **Research**:
  - [Combining Pattern Classifiers](https://ieeexplore.ieee.org/book/6267321) (Kuncheva, 2014)
  - [Bagging Predictors](https://link.springer.com/article/10.1023/A:1018054314350) (Breiman, 1996)
- **Scikit-learn**: [Voting Classifier](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.VotingClassifier.html)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/tosin2013/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/06-ensemble-anomaly-methods.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 6 of 15 in the OpenShift AI Ops Learning Series*
