# ADR-001: OpenShift 4.18+ as Foundation Platform

## Status

Accepted

## Implementation Status
**Status:** ✅ IMPLEMENTED
**Verification Date:** 2026-01-25
**Implementation Score:** 10.0/10
**Verified On:** SNO + HA clusters
**Evidence:** OpenShift 4.18.21 deployed and operational. Platform selection validated across both topologies.

## Context

The Self-Healing Platform requires a robust, enterprise-grade container orchestration platform that can support:

- **Automated Infrastructure Management**: Built-in operators for managing cluster infrastructure
- **AI/ML Workload Support**: Native support for GPU resources and AI/ML frameworks
- **Enterprise Security**: Role-based access control, network policies, and security scanning
- **Observability**: Comprehensive monitoring, logging, and alerting capabilities
- **Hybrid Cloud Support**: Ability to run across multiple cloud providers and on-premises
- **Operator Ecosystem**: Rich ecosystem of operators for extending platform capabilities

### Current Environment Analysis

Our target cluster is running:
- **OpenShift Version**: 4.18.21
- **Kubernetes Version**: v1.31.10
- **Node Configuration**: 6 nodes (3 control-plane, 3 workers including 1 GPU-enabled)
- **Installed Operators**: GPU Operator, OpenShift AI, Serverless, Service Mesh, GitOps, Pipelines

## Decision

We will use **Red Hat OpenShift 4.18+** as the foundation platform for the Self-Healing Platform.

### Key Factors in Decision

1. **Operator-First Architecture**: OpenShift's operator-based approach aligns perfectly with our self-healing automation requirements
2. **Machine Config Operator**: Built-in MCO provides the deterministic self-healing loop for node-level infrastructure integrity
3. **AI/ML Ecosystem**: Native integration with OpenShift AI, GPU operators, and ML serving frameworks
4. **Enterprise Support**: Red Hat enterprise support and security compliance
5. **Existing Investment**: Current cluster already running OpenShift 4.18.21 with required operators

## Alternatives Considered

### Vanilla Kubernetes
- **Pros**: More flexibility, lower cost, broader ecosystem
- **Cons**: Requires manual setup of operators, monitoring, security; lacks enterprise support
- **Verdict**: Rejected due to operational complexity and lack of built-in self-healing capabilities

### Amazon EKS
- **Pros**: Managed service, AWS integration, cost-effective
- **Cons**: Vendor lock-in, limited operator ecosystem, requires additional tooling for self-healing
- **Verdict**: Rejected due to lack of comprehensive operator ecosystem

### Azure AKS
- **Pros**: Managed service, Azure integration, good AI/ML support
- **Cons**: Vendor lock-in, limited self-healing capabilities, different operator model
- **Verdict**: Rejected due to architectural differences and existing OpenShift investment

## Consequences

### Positive

- **Built-in Self-Healing**: Machine Config Operator provides foundation for node-level automation
- **Rich Operator Ecosystem**: Access to certified operators for AI/ML, monitoring, and automation
- **Enterprise Security**: Built-in security scanning, RBAC, and compliance features
- **Unified Management**: Single platform for both traditional and AI/ML workloads
- **Proven Scalability**: Battle-tested platform for enterprise workloads

### Negative

- **Cost**: Higher licensing costs compared to vanilla Kubernetes
- **Complexity**: More complex than managed cloud services
- **Learning Curve**: Requires OpenShift-specific knowledge and skills
- **Vendor Dependency**: Tied to Red Hat ecosystem and release cycles

### Neutral

- **Version Compatibility**: Current 4.18.21 version supports all required features
- **Upgrade Path**: Clear upgrade path to newer versions as they become available
- **Hybrid Deployment**: Can extend to other environments while maintaining consistency

## Implementation Notes

1. **Current State**: Cluster already running OpenShift 4.18.21 with required operators
2. **Required Operators**: All necessary operators (GPU, AI, Serverless) already installed
3. **Namespace Strategy**: Use dedicated namespaces for self-healing platform components
4. **Resource Management**: Leverage existing GPU-enabled worker node for AI/ML workloads

## Related ADRs

- [ADR-002: Hybrid Deterministic-AI Self-Healing Approach](002-hybrid-self-healing-approach.md)
- [ADR-005: Machine Config Operator for Node-Level Automation](005-machine-config-operator-automation.md)

## References

- [OpenShift 4.18 Release Notes](https://docs.openshift.com/container-platform/4.18/release_notes/ocp-4-18-release-notes.html)
- [Self-Healing Platform PRD](../../PRD.md)
- Current cluster analysis: OpenShift 4.18.21 with required operators installed
