# Architecture Diagrams Index

## Overview

This directory contains architecture diagrams for the OpenShift AI Ops Self-Healing Platform. All diagrams use Mermaid syntax and render natively on GitHub.

## Diagram Catalog

| Diagram | File | Description | Primary Audience |
|---------|------|-------------|-----------------|
| **C4 System Context** | [c4-system-context.md](c4-system-context.md) | C4 Level 1 diagram showing the platform boundary, external actors (Platform Engineer, Developer, Data Scientist), and external systems (OpenShift, Prometheus, GitHub, Container Registry, Lightspeed). | Stakeholders, architects |
| **C4 Container** | [c4-container.md](c4-container.md) | C4 Level 2 diagram showing all deployable containers within the platform: Coordination Engine, MCP Server, Jupyter Workbench, KServe InferenceServices, ArgoCD, Tekton, S3 storage, and External Secrets Operator. | Architects, senior developers |
| **Deployment Topology** | [deployment-topology.md](deployment-topology.md) | Deployment diagrams for three supported topologies: ROSA HA (primary), ROSA Single-Worker, and SNO. Shows node layout, namespace distribution, and storage backends per topology. | Platform engineers, operations |
| **Data Flow** | [data-flow.md](data-flow.md) | End-to-end data flow from Prometheus metrics collection through feature engineering, model training, real-time inference, and the self-healing feedback loop. Includes notebook wave dependencies. | Data scientists, ML engineers |
| **GitOps Workflow** | [gitops-workflow.md](gitops-workflow.md) | GitOps deployment flow from developer commit through pre-commit hooks, Validated Patterns Operator, ArgoCD sync waves, and Tekton validation. Includes sync wave details and ArgoCD application hierarchy. | DevOps, platform engineers |
| **Self-Healing Sequences** | [self-healing-sequence.md](self-healing-sequence.md) | Sequence diagrams for anomaly detection and remediation, model training pipeline, incident response via Lightspeed/MCP, and OOM kill auto-remediation. | Developers, SREs, ML engineers |
| **Component Dependencies** | [component-dependencies.md](component-dependencies.md) | Operator and component dependency graph showing installation order (7 tiers), health check chains, and failure impact analysis. | Platform engineers, troubleshooting |
| **Bootstrap Architecture** | [bootstrap-architecture.md](bootstrap-architecture.md) | Legacy bootstrap diagrams from ADR-009 showing Kustomize-based deployment (pre-Helm migration). Retained for historical reference. | Historical reference |

## Audience Guide

| Role | Start With | Then Read |
|------|-----------|-----------|
| **Executive / Stakeholder** | [C4 System Context](c4-system-context.md) | [Deployment Topology](deployment-topology.md) |
| **Architect** | [C4 System Context](c4-system-context.md) | [C4 Container](c4-container.md), [Component Dependencies](component-dependencies.md) |
| **Platform Engineer** | [Deployment Topology](deployment-topology.md) | [GitOps Workflow](gitops-workflow.md), [Component Dependencies](component-dependencies.md) |
| **Developer** | [C4 Container](c4-container.md) | [Self-Healing Sequences](self-healing-sequence.md), [GitOps Workflow](gitops-workflow.md) |
| **Data Scientist** | [Data Flow](data-flow.md) | [Self-Healing Sequences](self-healing-sequence.md), [C4 Container](c4-container.md) |
| **SRE / Operations** | [Self-Healing Sequences](self-healing-sequence.md) | [Component Dependencies](component-dependencies.md), [Deployment Topology](deployment-topology.md) |

## Diagram Standards

All diagrams in this directory follow these conventions:

- **Syntax**: Mermaid (GitHub-renderable). No PlantUML unless for UI wireframes.
- **Node cap**: About 16 nodes per diagram. Larger systems are split into sub-diagrams.
- **Color coding**: Blue for platform components, green for ML/AI, orange for infrastructure, grey for external systems.
- **Structure**: Each file contains a title, description, one or more Mermaid diagrams, and a notes section with context.

## Related Documentation

| Document | Purpose |
|----------|---------|
| [ADR-002: Hybrid Self-Healing Approach](../adrs/002-hybrid-self-healing-approach.md) | Core architecture decision |
| [ADR-038: Go Coordination Engine](../adrs/038-go-coordination-engine-migration.md) | Coordination engine design |
| [ADR-042: ArgoCD Deployment Lessons](../adrs/042-argocd-deployment-lessons-learned.md) | GitOps deployment patterns |
| [ADR-053: Tekton Model Training](../adrs/053-tekton-model-training-pipelines.md) | Training pipeline architecture |
| [ADR-062: ROSA as Primary Target](../adrs/062-rosa-primary-deployment-target.md) | Deployment topology rationale |
| [CLAUDE.md](../../CLAUDE.md) | Comprehensive platform reference |
| [AI Agent Development Guide](../explanation/ai-agent-development-guide.md) | Developer guide |
