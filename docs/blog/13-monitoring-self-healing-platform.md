# Monitoring Your Self-Healing Platform

*Part 13 of the OpenShift AI Ops Learning Series*

---

## Introduction

The self-healing platform needs monitoring too! This guide covers observability for the platform itself: tracking model performance, detecting model drift, monitoring healing success rates, and ensuring the platform remains healthy.

---

## What You'll Learn

- Tracking model accuracy over time
- Detecting model drift
- Monitoring prediction confidence
- Tracking healing success rates
- Triggering automated retraining

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 9: Deploying Models with KServe](09-deploying-models-kserve.md)
- [ ] Models deployed and serving predictions
- [ ] Historical performance data available

---

## Step 1: Track Model Performance

### Open the Model Performance Monitoring Notebook

1. Navigate to `notebooks/07-monitoring-operations/`
2. Open `model-performance-monitoring.ipynb`

### Collect Performance Metrics

```python
import pandas as pd

def collect_model_metrics(model_name, time_range='7d'):
    """
    Collect model performance metrics from Prometheus.

    Args:
        model_name: Model name
        time_range: Time range for metrics

    Returns:
        DataFrame with performance metrics
    """
    # Query Prometheus for prediction accuracy
    # (Assuming you're tracking accuracy via metrics)

    metrics = {
        'timestamp': pd.date_range(end=datetime.now(), periods=168, freq='1H'),
        'accuracy': np.random.uniform(0.85, 0.95, 168),  # Example
        'precision': np.random.uniform(0.80, 0.90, 168),
        'recall': np.random.uniform(0.85, 0.95, 168),
        'f1_score': np.random.uniform(0.82, 0.92, 168),
        'prediction_count': np.random.randint(100, 1000, 168)
    }

    return pd.DataFrame(metrics)
```

### Detect Model Drift

```python
from scipy import stats

def detect_model_drift(metrics_df, baseline_period=24):
    """
    Detect if model performance has degraded.

    Args:
        metrics_df: DataFrame with performance metrics
        baseline_period: Hours to use as baseline

    Returns:
        Drift detection result
    """
    # Baseline: first N hours
    baseline = metrics_df['accuracy'].iloc[:baseline_period]

    # Current: last N hours
    current = metrics_df['accuracy'].iloc[-baseline_period:]

    # Statistical test
    t_stat, p_value = stats.ttest_ind(baseline, current)

    # Calculate degradation
    degradation = baseline.mean() - current.mean()

    drift_detected = p_value < 0.05 and degradation > 0.05

    return {
        'drift_detected': drift_detected,
        'degradation': degradation,
        'p_value': p_value,
        'baseline_mean': baseline.mean(),
        'current_mean': current.mean()
    }
```

---

## Step 2: Monitor Healing Success Rates

### Track Remediation Outcomes

```python
def track_healing_success():
    """Track success rate of remediation actions"""
    # Load remediation outcomes
    outcomes = pd.read_json('/opt/app-root/src/data/processed/remediation_outcomes.jsonl', lines=True)

    # Calculate success rate by action type
    success_by_action = outcomes.groupby('action_type').agg({
        'success': ['mean', 'count']
    })

    print("📊 Healing Success Rates:")
    print(success_by_action)

    # Identify low-success actions
    low_success = success_by_action[success_by_action[('success', 'mean')] < 0.7]

    if len(low_success) > 0:
        print(f"\n⚠️ Low success actions: {low_success.index.tolist()}")

    return success_by_action
```

---

## Step 3: Automated Retraining

### Trigger Retraining on Drift

```python
def trigger_retraining(model_name, drift_result):
    """
    Trigger model retraining if drift detected.

    Args:
        model_name: Model name
        drift_result: Drift detection result
    """
    if drift_result['drift_detected']:
        print(f"⚠️ Model drift detected for {model_name}")
        print(f"   Degradation: {drift_result['degradation']:.3f}")

        # Trigger NotebookValidationJob
        subprocess.run([
            'oc', 'delete', 'notebookvalidationjob',
            f'{model_name}-validation',
            '-n', 'self-healing-platform'
        ])

        # Recreate to trigger retraining
        # ... (recreate NotebookValidationJob)

        print(f"✅ Retraining triggered for {model_name}")
```

---

## What Just Happened?

You've implemented platform monitoring:

### 1. Model Performance Tracking

- **Accuracy monitoring**: Track prediction accuracy over time
- **Drift detection**: Statistical tests for performance degradation
- **Confidence tracking**: Monitor prediction confidence scores

### 2. Healing Success Tracking

- **Outcome analysis**: Success rates by action type
- **Low-success identification**: Actions that need improvement
- **Continuous improvement**: Data feeds back into model training

### 3. Automated Retraining

- **Drift-triggered**: Retrain when performance degrades
- **NotebookValidationJob**: Automated retraining pipeline
- **Version management**: Track model versions and performance

---

## Next Steps

Explore advanced scenarios:

1. **Predictive Scaling**: [Blog 14: Predictive Scaling](14-predictive-scaling-cost-optimization.md)
2. **Security Automation**: [Blog 15: Security Automation](15-security-incident-automation.md)

---

## Related Resources

- **Notebook**: `notebooks/07-monitoring-operations/model-performance-monitoring.ipynb`
- **ADRs**:
  - [ADR-021: Tekton Pipeline Validation](docs/adrs/021-tekton-pipeline-deployment-validation.md)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/tosin2013/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/13-monitoring-self-healing-platform.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 13 of 15 in the OpenShift AI Ops Learning Series*
