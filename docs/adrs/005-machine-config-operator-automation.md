# ADR-005: Machine Config Operator for Node-Level Automation

## Status

accepted

## Context

The Self-Healing Platform requires deterministic automation for node-level infrastructure management, specifically:

- **Configuration Drift Detection**: Identify deviations from desired node configurations
- **Automated Remediation**: Automatically restore nodes to compliant state
- **Node Lifecycle Management**: Handle node cordoning, draining, and reconfiguration
- **Audit Trail**: Maintain logs of all remediation actions for compliance
- **Zero-Downtime Operations**: Perform node maintenance without service disruption

### Current Environment Analysis

Our OpenShift 4.18.21 cluster includes:
- **Machine Config Operator**: Built-in component managing node configurations
- **MachineConfig Objects**: Define desired node state configurations
- **Node Configuration**: 6 nodes with consistent RHEL CoreOS configuration
- **Existing MCO Functionality**: Already managing node updates and configurations

### Requirements from PRD

- Detect deviations from desired node configuration defined in MachineConfig objects
- Automatically cordon, drain, and reconfigure non-compliant nodes
- Log all remediation actions for auditing and traceability
- Integrate with the hybrid self-healing approach as the deterministic layer

## Decision

We will leverage the **Machine Config Operator (MCO)** as the primary deterministic automation engine for node-level self-healing in the Self-Healing Platform.

### Key MCO Capabilities Utilized

1. **Configuration Management**
   - Declarative node configuration via MachineConfig CRDs
   - Automatic detection of configuration drift
   - Immutable infrastructure patterns

2. **Automated Remediation**
   - Built-in node cordoning and draining
   - Automatic node reconfiguration and reboot
   - Rolling updates with configurable disruption budgets

3. **Observability**
   - Configuration status reporting
   - Event logging for all configuration changes
   - Integration with cluster monitoring

4. **Safety Mechanisms**
   - Gradual rollout of configuration changes
   - Automatic rollback on failure detection
   - Node health validation before proceeding

## Alternatives Considered

### Custom Node Management Controller
- **Pros**: Full control over remediation logic, custom business rules
- **Cons**: Significant development effort, reinventing existing functionality
- **Verdict**: Rejected - MCO provides proven, battle-tested functionality

### Ansible-based Automation
- **Pros**: Familiar tooling, flexible automation, good for complex workflows
- **Cons**: External dependency, not Kubernetes-native, manual scaling
- **Verdict**: Rejected - not cloud-native, adds operational complexity

### Node Problem Detector + Custom Remediation
- **Pros**: Good problem detection, flexible remediation options
- **Cons**: Requires custom remediation logic, limited to problem detection
- **Verdict**: Rejected - insufficient for comprehensive node management

### Cluster API Machine Management
- **Pros**: Standardized machine lifecycle management, multi-cloud support
- **Cons**: More complex than needed, focused on machine provisioning
- **Verdict**: Rejected - overkill for configuration management needs

## Consequences

### Positive

- **Battle-Tested**: MCO is proven in production OpenShift environments
- **Zero Development**: No custom controller development required
- **Integrated Observability**: Built-in monitoring and alerting capabilities
- **Safety First**: Built-in safety mechanisms prevent cluster-wide failures
- **Kubernetes Native**: Fully integrated with OpenShift/Kubernetes ecosystem
- **Audit Trail**: Comprehensive logging of all configuration changes

### Negative

- **Limited Customization**: Constrained to MCO's built-in remediation logic
- **OpenShift Dependency**: Tied to OpenShift platform and MCO capabilities
- **Configuration Complexity**: MachineConfig objects can be complex to manage
- **Reboot Requirements**: Many configuration changes require node reboots

### Neutral

- **Learning Curve**: Team needs to understand MachineConfig patterns
- **Integration Points**: Need to integrate MCO events with AI layer
- **Monitoring Setup**: Requires proper monitoring of MCO operations

## Implementation Strategy

### Phase 1: MCO Integration Setup

1. **Monitoring Integration**
   ```yaml
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: machine-config-operator
     namespace: self-healing-platform
   spec:
     selector:
       matchLabels:
         app: machine-config-operator
     endpoints:
     - port: metrics
   ```

2. **Alert Rules**
   ```yaml
   apiVersion: monitoring.coreos.com/v1
   kind: PrometheusRule
   metadata:
     name: mco-self-healing-alerts
   spec:
     groups:
     - name: mco.rules
       rules:
       - alert: NodeConfigurationDrift
         expr: mco_node_config_drift_detected > 0
         for: 5m
         labels:
           severity: warning
         annotations:
           summary: "Node configuration drift detected"
   ```

### Phase 2: Custom MachineConfigs

1. **Self-Healing Node Configuration**
   ```yaml
   apiVersion: machineconfiguration.openshift.io/v1
   kind: MachineConfig
   metadata:
     name: 99-self-healing-config
     labels:
       machineconfiguration.openshift.io/role: worker
   spec:
     config:
       ignition:
         version: 3.2.0
       systemd:
         units:
         - name: self-healing-agent.service
           enabled: true
           contents: |
             [Unit]
             Description=Self-Healing Platform Agent
             [Service]
             ExecStart=/usr/local/bin/self-healing-agent
             [Install]
             WantedBy=multi-user.target
   ```

### Phase 3: Integration with AI Layer

1. **Event Processing**: Forward MCO events to AI analysis layer
2. **Feedback Loop**: Use AI insights to refine MachineConfig definitions
3. **Escalation**: Route complex issues to AI layer when MCO remediation fails

## Monitoring and Alerting

### Key Metrics to Monitor

- `mco_node_config_drift_count`: Number of nodes with configuration drift
- `mco_remediation_duration_seconds`: Time taken for node remediation
- `mco_remediation_success_rate`: Success rate of automated remediation
- `mco_node_reboot_frequency`: Frequency of node reboots due to configuration changes

### Alert Conditions

- Configuration drift detected on multiple nodes simultaneously
- Remediation failures exceeding threshold (>5% failure rate)
- Excessive node reboot frequency (>1 reboot per node per day)
- MCO controller unavailability

## Success Metrics

- **Drift Detection Time**: <5 minutes to detect configuration drift
- **Remediation Time**: <15 minutes for automated node remediation
- **Success Rate**: >95% successful automated remediation
- **Availability Impact**: <1% service availability impact during remediation

## Related ADRs

- [ADR-001: OpenShift 4.18+ as Foundation Platform](001-openshift-platform-selection.md)
- [ADR-002: Hybrid Deterministic-AI Self-Healing Approach](002-hybrid-self-healing-approach.md)
- [ADR-007: Prometheus-Based Monitoring and Data Collection](007-prometheus-monitoring-integration.md)

## References

- [Machine Config Operator Documentation](https://docs.openshift.com/container-platform/4.18/post_installation_configuration/machine-configuration-tasks.html)
- [Self-Healing Platform PRD](../../PRD.md) - Section 4.1: Automated Configuration Drift Remediation
- Current cluster: MCO managing 6 nodes in OpenShift 4.18.21
