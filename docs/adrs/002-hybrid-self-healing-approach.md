# ADR-002: Hybrid Deterministic-AI Self-Healing Approach

## Status

Accepted

## Context

The Self-Healing Platform needs to handle two distinct types of operational scenarios:

1. **Known Failure States**: Well-understood issues with established remediation procedures
2. **Novel/Complex Anomalies**: Unexpected issues requiring analysis and adaptive responses

Traditional approaches typically focus on either deterministic automation OR AI-driven analysis, but not both in a coordinated manner.

### Requirements from PRD

- **Reduce MTTR**: Automate the entire incident lifecycle from detection to resolution
- **Minimize Human Error**: Reduce risk through automation of routine tasks
- **Enable Proactive Management**: Transition from reactive to proactive operations
- **Handle Edge Cases**: Gracefully manage conflicting actions and AI model inaccuracy

## Decision

We will implement a **Hybrid Deterministic-AI Self-Healing Approach** that combines:

1. **Deterministic Automation Layer**: For known failure states and established procedures
2. **AI-Driven Analysis Layer**: For novel anomalies and complex pattern recognition
3. **Coordination Engine**: To manage interaction between the two layers

### Architecture Components

```
┌─────────────────────────────────────────────────────────────┐
│                 Self-Healing Platform                        │
├─────────────────────────────────────────────────────────────┤
│  Coordination Engine                                        │
│  ├─ Conflict Resolution                                     │
│  ├─ Priority Management                                     │
│  └─ Action Orchestration                                    │
├─────────────────────────────────────────────────────────────┤
│  Deterministic Layer    │    AI-Driven Layer               │
│  ├─ Machine Config      │    ├─ Anomaly Detection          │
│  │  Operator            │    ├─ Root Cause Analysis        │
│  ├─ Known Remediation   │    ├─ Predictive Analytics       │
│  │  Procedures          │    └─ Adaptive Responses         │
│  └─ Rule-Based Actions  │                                  │
├─────────────────────────────────────────────────────────────┤
│  Shared Observability Layer                                │
│  ├─ Prometheus Metrics                                     │
│  ├─ Alert Manager                                          │
│  └─ Incident Correlation                                   │
└─────────────────────────────────────────────────────────────┘
```

## Alternatives Considered

### Pure Deterministic Approach
- **Pros**: Predictable, fast response, easy to debug
- **Cons**: Cannot handle novel issues, requires extensive rule maintenance
- **Verdict**: Rejected - insufficient for complex, evolving environments

### Pure AI-Driven Approach
- **Pros**: Adaptive, can handle novel scenarios, learns over time
- **Cons**: Unpredictable, potential for false positives, slower response for known issues
- **Verdict**: Rejected - too risky for critical infrastructure

### Sequential Approach (Deterministic → AI)
- **Pros**: Clear escalation path, combines benefits of both
- **Cons**: Delays AI intervention, misses opportunities for parallel processing
- **Verdict**: Rejected - suboptimal performance for time-critical scenarios

## Coordination Engine API (Implemented)

The coordination engine orchestrates the hybrid approach and exposes a REST API for integration with notebooks, ML models, and external systems.

**Base URL**: `http://coordination-engine.self-healing-platform.svc.cluster.local:8080`

**Endpoints**:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Health check and readiness probe |
| `/api/v1/anomalies` | POST | Submit anomaly for processing |
| `/api/v1/anomalies/<id>` | GET | Get anomaly status and resolution |
| `/api/v1/remediate` | POST | Trigger remediation action |
| `/api/v1/status` | GET | Engine status and metrics |
| `/metrics` | GET | Prometheus metrics endpoint |

**Example Usage** (from notebooks):
```python
import requests

# Submit anomaly
response = requests.post(
    'http://coordination-engine:8080/api/v1/anomalies',
    json={
        'timestamp': '2025-12-09T12:00:00Z',
        'type': 'resource_exhaustion',
        'severity': 'critical',
        'confidence_score': 0.92,
        'recommended_action': 'scale_down_pods'
    }
)
```

**Coordination Rules**:
1. Deterministic layer has priority for known issue types
2. Novel issues automatically route to AI layer
3. Conflict resolution prevents simultaneous contradictory actions
4. AI actions require minimum 80% confidence score
5. Human override available via OpenShift Lightspeed

## Consequences

### Positive

- **Optimal Response Time**: Fast deterministic responses for known issues
- **Adaptive Capability**: AI handles novel and complex scenarios
- **Reduced False Positives**: Deterministic layer provides high-confidence actions
- **Continuous Learning**: AI layer improves over time while deterministic layer provides stability
- **Risk Mitigation**: Coordination engine prevents conflicting actions

### Negative

- **Increased Complexity**: More complex architecture requiring careful coordination
- **Integration Challenges**: Need to ensure seamless interaction between layers
- **Resource Overhead**: Both layers require computational resources
- **Debugging Complexity**: More difficult to troubleshoot multi-layer decisions

### Neutral

- **Gradual Migration**: Can start with deterministic rules and gradually add AI capabilities
- **Operator Training**: Teams need to understand both deterministic and AI-driven approaches

## Implementation Strategy

### Phase 1: Deterministic Foundation
1. Implement Machine Config Operator-based automation
2. Establish known remediation procedures
3. Set up basic observability and alerting

### Phase 2: AI Layer Integration
1. Deploy anomaly detection models
2. Implement root cause analysis capabilities
3. Add predictive analytics for hardware failures

### Phase 3: Coordination Engine
1. Implement conflict resolution mechanisms
2. Add priority-based action orchestration
3. Establish feedback loops between layers

### Coordination Rules

1. **Deterministic Priority**: Known issues handled by deterministic layer first
2. **AI Escalation**: Novel issues automatically routed to AI layer
3. **Conflict Resolution**: Coordination engine prevents simultaneous conflicting actions
4. **Confidence Thresholds**: AI actions require minimum confidence levels
5. **Human Override**: Operators can override both layers when necessary

## Success Metrics

- **MTTR Reduction**: Target 50% reduction in mean time to resolution
- **False Positive Rate**: <5% for automated actions
- **Coverage**: 80% of incidents handled automatically within 6 months
- **Conflict Rate**: <1% of actions result in conflicts requiring resolution

## Related ADRs

- [ADR-001: OpenShift 4.18+ as Foundation Platform](001-openshift-platform-selection.md)
- [ADR-003: Red Hat OpenShift AI for ML Platform](003-openshift-ai-ml-platform.md)
- [ADR-005: Machine Config Operator for Node-Level Automation](005-machine-config-operator-automation.md)
- [ADR-038: Go Coordination Engine Migration](038-go-coordination-engine-migration.md) - Coordination engine implementation

## References

- [Self-Healing Platform PRD](../../PRD.md) - Section 1: Introduction/Overview
- [Edge Cases & Error Handling](../../PRD.md) - Section 6
- Machine Config Operator Documentation
