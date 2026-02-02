# AI-Driven Decision Making for Complex Incidents

*Part 8 of the OpenShift AI Ops Learning Series*

---

## Introduction

Rules work for known patterns, but what about novel incidents? When multiple anomalies occur simultaneously, or when root causes are unclear, AI-driven decision making provides intelligent remediation choices based on learned patterns.

This guide shows you how to use ML models to recommend remediation actions, handle uncertainty with confidence thresholds, and optimize for success rates through outcome tracking.

---

## What You'll Learn

- Using ML models for remediation decisions
- Confidence-based decision making
- Handling uncertainty in predictions
- Optimizing remediation success rates
- Tracking decision accuracy and outcomes

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 6: Ensemble Methods](06-ensemble-anomaly-methods.md)
- [ ] Completed [Blog 7: Rule-Based Remediation](07-rule-based-remediation.md)
- [ ] Ensemble models trained and deployed
- [ ] Coordination Engine accessible

---

## Understanding AI-Driven Decisions

### When Rules Fail

Rules fail when:
- ❌ **Novel patterns**: Unknown anomaly types
- ❌ **Complex interactions**: Multiple simultaneous issues
- ❌ **Uncertain root cause**: Unclear what action to take
- ❌ **Context-dependent**: Same anomaly needs different actions

### AI Decision Making

ML models learn from historical incidents:
- ✅ **Pattern recognition**: "Similar incidents were fixed by scaling"
- ✅ **Confidence scoring**: "85% confident this will work"
- ✅ **Context awareness**: Considers deployment, namespace, time
- ✅ **Adaptive**: Improves with more data

---

## Step 1: Train Action Recommendation Model

### Open the AI Decision Making Notebook

1. Navigate to `notebooks/03-self-healing-logic/`
2. Open `ai-driven-decision-making.ipynb`

### Prepare Training Data

```python
import pandas as pd

# Load historical remediation outcomes
outcomes = pd.read_json('/opt/app-root/src/data/processed/remediation_outcomes.jsonl', lines=True)

# Features: anomaly characteristics
features = [
    'cpu_usage', 'memory_usage', 'restart_count',
    'anomaly_type', 'severity', 'namespace',
    'hour_of_day', 'day_of_week'
]

# Target: successful action type
target = 'action_type'  # scale_up, restart_pod, update_config, etc.

# Filter successful remediations
successful = outcomes[outcomes['success'] == True]

X = successful[features]
y = successful[target]

print(f"📊 Training data: {len(X)} successful remediations")
print(f"   Actions: {y.value_counts().to_dict()}")
```

### Train Recommendation Model

```python
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder
from sklearn.model_selection import train_test_split

# Encode categorical features
le_action = LabelEncoder()
y_encoded = le_action.fit_transform(y)

# Split data
X_train, X_test, y_train, y_test = train_test_split(X, y_encoded, test_size=0.2)

# Train model
recommendation_model = RandomForestClassifier(n_estimators=100, random_state=42)
recommendation_model.fit(X_train, y_train)

# Evaluate
accuracy = recommendation_model.score(X_test, y_test)
print(f"✅ Model trained: {accuracy:.3f} accuracy")
```

---

## Step 2: Get Action Recommendations

### Recommend Action for Anomaly

```python
def recommend_action(anomaly, model, confidence_threshold=0.75):
    """
    Recommend remediation action using ML model.

    Args:
        anomaly: Detected anomaly
        model: Trained recommendation model
        confidence_threshold: Minimum confidence for recommendation

    Returns:
        Recommended action with confidence score
    """
    # Prepare features
    features = pd.DataFrame([{
        'cpu_usage': anomaly['metrics'].get('cpu_usage', 0),
        'memory_usage': anomaly['metrics'].get('memory_usage', 0),
        'restart_count': anomaly['metrics'].get('restart_count', 0),
        'anomaly_type': anomaly['type'],
        'severity': anomaly['severity'],
        'namespace': anomaly['namespace'],
        'hour_of_day': datetime.now().hour,
        'day_of_week': datetime.now().weekday()
    }])

    # Get prediction probabilities
    probabilities = model.predict_proba(features)[0]
    predicted_class = model.predict(features)[0]
    confidence = probabilities.max()

    # Decode action
    action = le_action.inverse_transform([predicted_class])[0]

    if confidence >= confidence_threshold:
        return {
            'action': action,
            'confidence': confidence,
            'recommended': True
        }
    else:
        return {
            'action': action,
            'confidence': confidence,
            'recommended': False,
            'reason': f'Confidence {confidence:.2f} below threshold {confidence_threshold}'
        }
```

---

## Step 3: Handle Uncertainty

### Confidence-Based Decision Making

```python
CONFIDENCE_THRESHOLD = 0.75  # Minimum confidence for action
HIGH_CONFIDENCE_THRESHOLD = 0.90  # High confidence threshold

def make_decision(anomaly, recommendation):
    """
    Make remediation decision based on confidence.

    Args:
        anomaly: Detected anomaly
        recommendation: ML recommendation

    Returns:
        Decision with reasoning
    """
    confidence = recommendation['confidence']

    if confidence >= HIGH_CONFIDENCE_THRESHOLD:
        # High confidence: Execute immediately
        return {
            'decision': 'execute',
            'action': recommendation['action'],
            'reason': f'High confidence ({confidence:.2f})',
            'requires_approval': False
        }
    elif confidence >= CONFIDENCE_THRESHOLD:
        # Medium confidence: Execute with monitoring
        return {
            'decision': 'execute_monitored',
            'action': recommendation['action'],
            'reason': f'Medium confidence ({confidence:.2f})',
            'requires_approval': False,
            'monitor_closely': True
        }
    else:
        # Low confidence: Require human approval or fallback
        return {
            'decision': 'require_approval',
            'action': recommendation['action'],
            'reason': f'Low confidence ({confidence:.2f})',
            'requires_approval': True,
            'fallback_action': 'escalate_to_human'
        }
```

### Fallback Strategies

```python
def get_fallback_action(anomaly):
    """
    Get fallback action when ML confidence is low.

    Args:
        anomaly: Detected anomaly

    Returns:
        Safe fallback action
    """
    # Conservative fallback: restart pod (safest action)
    if anomaly['type'] == 'crash_loop':
        return 'restart_pod'

    # Scale up (usually safe)
    elif anomaly['type'] == 'resource_exhaustion':
        return 'scale_up'

    # Default: escalate to human
    else:
        return 'escalate_to_human'
```

---

## Step 4: Execute with Monitoring

> **💡 Architecture Note**: The Coordination Engine is a **Go service**. Your Python notebooks call it via REST API to execute remediations.

### Execute High-Confidence Actions

```python
def execute_ai_remediation(anomaly, decision):
    """
    Execute AI-recommended remediation.

    Args:
        anomaly: Detected anomaly
        decision: Decision from make_decision()
    """
    from coordination_engine_client import get_client

    client = get_client()  # Python client → Go Coordination Engine service

    # Create incident
    incident = client.create_incident({
        'title': f"AI-Detected: {anomaly['type']}",
        'description': f"ML model recommended {decision['action']}",
        'severity': anomaly['severity'],
        'source': 'ai-driven',
        'confidence': decision.get('confidence', 0.0)
    })

    # Trigger remediation
    remediation = client.trigger_remediation({
        'incident_id': incident.incident_id,
        'action': decision['action'],
        'target': anomaly['target'],
        'namespace': anomaly['namespace'],
        'confidence': decision.get('confidence', 0.0),
        'dry_run': decision.get('requires_approval', False)
    })

    return remediation
```

---

## Step 5: Track and Learn

### Record Decision Outcomes

```python
def track_decision_outcome(anomaly, decision, action_id, success):
    """
    Track decision outcome for model improvement.

    Args:
        anomaly: Original anomaly
        decision: Decision made
        action_id: Action ID
        success: Whether action succeeded
    """
    outcome = {
        'timestamp': datetime.now().isoformat(),
        'anomaly_id': anomaly.get('id'),
        'recommended_action': decision['action'],
        'confidence': decision.get('confidence', 0.0),
        'action_id': action_id,
        'success': success,
        'features': {
            'cpu_usage': anomaly['metrics'].get('cpu_usage'),
            'memory_usage': anomaly['metrics'].get('memory_usage'),
            'anomaly_type': anomaly['type']
        }
    }

    # Save for retraining
    outcomes_file = '/opt/app-root/src/data/processed/ai_decisions.jsonl'
    with open(outcomes_file, 'a') as f:
        f.write(json.dumps(outcome) + '\n')

    print(f"📊 Decision tracked: {decision['action']} - {'Success' if success else 'Failed'}")
```

### Retrain Model Periodically

```python
def retrain_recommendation_model():
    """Retrain model with new outcomes"""
    # Load all outcomes
    outcomes = pd.read_json('/opt/app-root/src/data/processed/ai_decisions.jsonl', lines=True)

    # Filter successful
    successful = outcomes[outcomes['success'] == True]

    # Retrain
    X = successful[['cpu_usage', 'memory_usage', 'anomaly_type', 'severity']]
    y = successful['recommended_action']

    model.fit(X, y)

    # Save updated model
    joblib.dump(model, '/opt/app-root/src/models/action_recommender.pkl')

    print("✅ Model retrained with latest outcomes")
```

---

## What Just Happened?

You've implemented AI-driven decision making:

### 1. Recommendation Model

- **Training data**: Historical successful remediations
- **Features**: Anomaly characteristics + context
- **Target**: Action type that worked

### 2. Confidence Scoring

- **High confidence (≥90%)**: Execute immediately
- **Medium confidence (75-90%)**: Execute with monitoring
- **Low confidence (<75%)**: Require approval or fallback

### 3. Uncertainty Handling

- **Fallback actions**: Safe defaults when confidence low
- **Human escalation**: Complex cases need human judgment
- **Monitoring**: Track medium-confidence actions closely

### 4. Continuous Learning

- **Outcome tracking**: Record successes/failures
- **Periodic retraining**: Improve with more data
- **Adaptive**: Gets better over time

---

## Hybrid Approach: Rules + AI

Combine both approaches:

```python
def hybrid_remediation(anomaly):
    """Try rules first, fall back to AI"""
    # Try rule-based first
    matching_rules = evaluate_rules(anomaly, REMEDIATION_RULES)

    if matching_rules:
        # Use rule (deterministic, fast)
        return execute_remediation(anomaly, matching_rules[0])
    else:
        # Fall back to AI (handles novel cases)
        recommendation = recommend_action(anomaly, recommendation_model)
        decision = make_decision(anomaly, recommendation)
        return execute_ai_remediation(anomaly, decision)
```

---

## Next Steps

Explore production deployment:

1. **KServe Deployment**: [Blog 9: Deploying Models with KServe](09-deploying-models-kserve.md) for production serving
2. **Hybrid Workflows**: See `hybrid-healing-workflows.ipynb` notebook
3. **Monitoring**: [Blog 13: Monitoring the Platform](13-monitoring-self-healing-platform.md)

---

## Related Resources

- **Notebook**: `notebooks/03-self-healing-logic/ai-driven-decision-making.ipynb`
- **ADRs**:
  - [ADR-002: Hybrid Self-Healing Approach](docs/adrs/002-hybrid-self-healing-approach.md)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/KubeHeal/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/08-ai-driven-decision-making.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 8 of 15 in the OpenShift AI Ops Learning Series*
