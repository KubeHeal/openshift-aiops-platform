# Deployment Topology Diagrams

## Overview

These diagrams show how the Self-Healing Platform is deployed across different OpenShift cluster topologies. Each topology has different node configurations, storage backends, and resource constraints.

**Audience**: Platform engineers, operations teams, and architects planning cluster provisioning and capacity.

## Topology 1: ROSA HA (Primary Target)

ROSA Classic with 3 or more worker nodes and an optional GPU machine pool. This is the recommended production deployment (ADR-062).

```mermaid
flowchart LR
    subgraph rosa["ROSA Classic HA Cluster"]
        direction TB

        subgraph cp["Managed Control Plane (ROSA)"]
            API["API Server"]
            ETCD["etcd"]
            CTRL["Controllers"]
        end

        subgraph workers["Worker Machine Pool (3x m5.2xlarge)"]
            subgraph ns_shp["Namespace: self-healing-platform"]
                CE["Coordination
                Engine"]
                MCP_S["MCP Server"]
                WB["Jupyter
                Workbench"]
                AD_P["anomaly-detector
                (predictor)"]
                PA_P["predictive-analytics
                (predictor)"]
                TEK_P["Tekton
                PipelineRuns"]
            end

            subgraph ns_hub["Namespace: self-healing-platform-hub"]
                ARGO_C["ArgoCD
                Controller"]
                ARGO_S["ArgoCD
                Server"]
            end

            subgraph ns_ops["Namespace: openshift-operators"]
                VP_OP["Validated Patterns
                Operator"]
                ESO_OP["External Secrets
                Operator"]
                PIPE_OP["OpenShift
                Pipelines"]
                RHOAI_OP["OpenShift AI
                Operator"]
                JNV_OP["Notebook Validator
                Operator"]
            end

            subgraph ns_mon["Namespace: openshift-monitoring"]
                PROM["Prometheus"]
                AM["AlertManager"]
            end
        end

        subgraph gpu["GPU Machine Pool (1x g5.2xlarge)"]
            subgraph ns_gpu_ops["Namespace: nvidia-gpu-operator"]
                GPU_D["GPU Device
                Plugin"]
                GPU_DRV["NVIDIA
                Driver"]
            end
            GPU_TRAIN["GPU Training
            Jobs (Tekton)"]
        end

        subgraph aws["AWS Services"]
            S3["S3 Bucket
            (model-storage)"]
            IAM["IAM / IRSA
            Credentials"]
        end
    end

    CE --> AD_P
    CE --> PA_P
    CE --> PROM
    WB --> S3
    TEK_P --> S3
    AD_P --> S3
    PA_P --> S3
    ARGO_C --> ns_shp
    ESO_OP --> IAM
    GPU_TRAIN --> S3

    classDef managed fill:#E8EAF6,color:#1A237E,stroke:#3F51B5
    classDef worker fill:#E3F2FD,color:#0D47A1,stroke:#1565C0
    classDef gpu fill:#FFF3E0,color:#E65100,stroke:#F57C00
    classDef aws fill:#FFF8E1,color:#F57F17,stroke:#FBC02D

    class cp managed
    class workers worker
    class gpu gpu
    class aws aws
```

### ROSA HA Key Characteristics

| Property | Value |
|----------|-------|
| **Worker Nodes** | 3+ (m5.2xlarge or larger) |
| **GPU Nodes** | 1+ g5.2xlarge (optional machine pool) |
| **Storage Backend** | AWS S3 (native, `objectStore.backend: aws-s3`) |
| **PVC Storage Class** | gp3-csi (EBS) |
| **Node Scaling** | `rosa create machinepool` (Machine Pools, not MachineSets) |
| **Namespaces** | self-healing-platform, self-healing-platform-hub, openshift-operators, openshift-monitoring, nvidia-gpu-operator |
| **ODF Required** | No (uses native AWS S3) |

---

## Topology 2: ROSA Single-Worker

ROSA Classic with a single worker node, suitable for development, testing, and demos.

```mermaid
flowchart TD
    subgraph rosa_sw["ROSA Classic Single-Worker"]
        direction TB

        subgraph cp2["Managed Control Plane (ROSA)"]
            API2["API Server + etcd + Controllers"]
        end

        subgraph single["Single Worker Node (m5.2xlarge)"]
            subgraph ns_shp2["self-healing-platform"]
                CE2["Coordination Engine"]
                MCP2["MCP Server"]
                WB2["Jupyter Workbench"]
                AD2["anomaly-detector"]
                PA2["predictive-analytics"]
            end

            subgraph ns_hub2["self-healing-platform-hub"]
                ARGO2["ArgoCD Controller + Server"]
            end

            subgraph ns_ops2["openshift-operators"]
                OPS2["VP + ESO + Pipelines
                + RHOAI + Notebook Validator"]
            end

            subgraph ns_mon2["openshift-monitoring"]
                PROM2["Prometheus + AlertManager"]
            end
        end

        S3_2["AWS S3 Bucket"]
    end

    CE2 --> AD2
    CE2 --> PA2
    CE2 --> PROM2
    WB2 --> S3_2
    AD2 --> S3_2
    PA2 --> S3_2

    classDef singlenode fill:#E3F2FD,color:#0D47A1,stroke:#1565C0
    classDef cpmanaged fill:#E8EAF6,color:#1A237E,stroke:#3F51B5

    class single singlenode
    class cp2 cpmanaged
```

### ROSA Single-Worker Key Characteristics

| Property | Value |
|----------|-------|
| **Worker Nodes** | 1 (m5.2xlarge or larger) |
| **GPU** | Limited (single node) |
| **Storage Backend** | AWS S3 (native) |
| **PVC Storage Class** | gp3-csi (EBS) |
| **Use Case** | Development, testing, demos |
| **ODF Required** | No |

---

## Topology 3: SNO (Single Node OpenShift)

All roles (control-plane, worker, infrastructure) run on a single physical or virtual machine. Uses MCG-only ODF for S3 object storage when not on AWS.

```mermaid
flowchart TD
    subgraph sno["Single Node OpenShift"]
        direction TB

        subgraph node["Single Node (all roles)"]
            subgraph ctrl["Control Plane Components"]
                API3["API Server"]
                ETCD3["etcd"]
                CTRL3["Controllers"]
            end

            subgraph ns_shp3["self-healing-platform"]
                CE3["Coordination
                Engine"]
                MCP3["MCP Server"]
                WB3["Jupyter Workbench
                (reduced resources)"]
                AD3["anomaly-detector"]
                PA3["predictive-analytics"]
                TEK3["Tekton Pipelines"]
            end

            subgraph ns_hub3["self-healing-platform-hub"]
                ARGO3["ArgoCD"]
            end

            subgraph ns_ops3["openshift-operators"]
                OPS3["All Operators"]
            end

            subgraph ns_stor3["openshift-storage"]
                NOO["NooBaa
                (MCG-only ODF)"]
                NOO_EP["NooBaa S3
                Endpoint"]
            end

            subgraph ns_mon3["openshift-monitoring"]
                PROM3["Prometheus +
                AlertManager"]
            end
        end
    end

    CE3 --> AD3
    CE3 --> PA3
    CE3 --> PROM3
    WB3 --> NOO_EP
    AD3 --> NOO_EP
    PA3 --> NOO_EP
    TEK3 --> NOO_EP

    classDef snonode fill:#E8F5E9,color:#1B5E20,stroke:#43A047

    class node snonode
```

### SNO Key Characteristics

| Property | Value |
|----------|-------|
| **Nodes** | 1 (all roles: control-plane, worker) |
| **CPU** | 8+ cores (16+ recommended) |
| **RAM** | 32+ GB (64+ recommended) |
| **Storage Backend** | NooBaa S3 via MCG-only ODF (`objectStore.backend: noobaa`) |
| **PVC Storage Class** | gp3-csi (no CephFS available) |
| **ODF Mode** | MCG-only (NooBaa without Ceph daemons) |
| **Use Case** | Edge, development, testing |
| **Configuration** | `cluster.topology: sno` in `values-hub.yaml` |

---

## Namespace Layout (All Topologies)

```mermaid
flowchart TD
    subgraph cluster["OpenShift Cluster"]
        subgraph ns1["self-healing-platform"]
            C1["Coordination Engine"]
            C2["MCP Server"]
            C3["Jupyter Workbench"]
            C4["KServe InferenceServices"]
            C5["Tekton PipelineRuns"]
            C6["ExternalSecrets"]
            C7["PVCs + ConfigMaps"]
        end

        subgraph ns2["self-healing-platform-hub"]
            H1["ArgoCD Application Controller"]
            H2["ArgoCD Server"]
            H3["ArgoCD Repo Server"]
            H4["Pattern CR"]
        end

        subgraph ns3["openshift-operators"]
            O1["Validated Patterns Operator"]
            O2["External Secrets Operator"]
            O3["OpenShift Pipelines Operator"]
            O4["Red Hat OpenShift AI"]
            O5["Notebook Validator Operator"]
        end

        subgraph ns4["openshift-storage"]
            S1["NooBaa (SNO only)"]
            S2["ODF Operator"]
        end

        subgraph ns5["nvidia-gpu-operator"]
            G1["GPU Device Plugin"]
            G2["NVIDIA Drivers"]
        end

        subgraph ns6["openshift-monitoring"]
            M1["Prometheus"]
            M2["AlertManager"]
            M3["Grafana"]
        end
    end

    ns2 -->|"Manages resources in"| ns1
    O1 -->|"Creates ArgoCD app"| ns2
    O4 -->|"Manages KServe"| ns1

    classDef platform fill:#1565C0,color:#fff,stroke:#0D47A1
    classDef hub fill:#6A1B9A,color:#fff,stroke:#4A148C
    classDef operators fill:#E65100,color:#fff,stroke:#BF360C
    classDef storage fill:#2E7D32,color:#fff,stroke:#1B5E20
    classDef gpu fill:#F57F17,color:#fff,stroke:#F57F17
    classDef monitoring fill:#00838F,color:#fff,stroke:#006064

    class ns1 platform
    class ns2 hub
    class ns3 operators
    class ns4 storage
    class ns5 gpu
    class ns6 monitoring
```

## Topology Comparison

| Feature | ROSA HA | ROSA Single-Worker | SNO |
|---------|---------|-------------------|-----|
| **Nodes** | 3+ workers (managed) | 1 worker (managed) | 1 (all roles) |
| **Control Plane** | ROSA-managed | ROSA-managed | Co-located |
| **Storage Backend** | AWS S3 | AWS S3 | NooBaa (MCG) |
| **PVC Class** | gp3-csi | gp3-csi | gp3-csi |
| **GPU Support** | Dedicated machine pool | Limited | Single node |
| **Node Scaling** | Machine Pools | Machine Pools | N/A |
| **ODF Required** | No | No | MCG-only |
| **Production Ready** | Yes | Dev/test | Edge/dev |

## Notes

- **ROSA is the primary deployment target** (ADR-062). IPI, baremetal, and other platforms are community-supported.
- On ROSA clusters, the platform auto-detects the managed environment and skips MachineSet operations. Use `rosa create machinepool` for GPU nodes.
- SNO deployments require explicit `cluster.topology: sno` in `values-hub.yaml` and use gp3-csi for all PVCs (no CephFS available).
- The `self-healing-platform-hub` namespace contains a namespaced ArgoCD instance with cluster-admin permissions (ADR-030). This is separate from the default `openshift-gitops` namespace.
