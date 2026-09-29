# Data Flow and ML Pipeline Diagram

## Overview

This diagram traces the flow of data through the Self-Healing Platform, from raw metrics collection through model training and inference, to automated remediation. It covers four primary flows: metrics collection, model training, real-time inference, and the self-healing feedback loop.

**Audience**: Data scientists, ML engineers, and platform developers who need to understand how data moves through the system.

## End-to-End Data Flow

```mermaid
flowchart TD
    subgraph collection["1. Data Collection"]
        PROM["Prometheus
        Cluster metrics
        (CPU, memory, disk,
        network, pod events)"]

        AM["AlertManager
        Firing alerts and
        incident correlation"]

        K8S_EV["Kubernetes Events
        Pod lifecycle, node
        conditions, OOM kills"]

        PROM --> RAW["Raw Metrics
        (time series data)"]
        AM --> ALERTS["Alert Events
        (severity, labels)"]
        K8S_EV --> EVENTS["Cluster Events
        (structured JSON)"]
    end

    subgraph processing["2. Feature Engineering"]
        RAW --> NB_DC["Notebook:
        prometheus-metrics-collection
        (Wave 1)"]

        ALERTS --> NB_EV["Notebook:
        openshift-events-analysis
        (Wave 1)"]

        EVENTS --> NB_LOG["Notebook:
        log-parsing-analysis
        (Wave 1)"]

        NB_DC --> FEAT["Feature Store
        (Parquet files)
        Engineered features:
        rolling means, std dev,
        rate of change"]

        NB_EV --> FEAT
        NB_LOG --> FEAT

        FEAT --> NB_SYN["Notebook:
        synthetic-anomaly-generation
        (Wave 2)"]

        NB_SYN --> TRAIN_DATA["Training Dataset
        (real + synthetic data)"]
    end

    subgraph training["3. Model Training"]
        TRAIN_DATA --> TEK_CPU["Tekton Pipeline (CPU)
        model-training-pipeline"]

        TRAIN_DATA --> TEK_GPU["Tekton Pipeline (GPU)
        model-training-pipeline-gpu"]

        TEK_CPU --> NB_IF["Notebook:
        isolation-forest
        (Wave 3)"]

        TEK_GPU --> NB_PA["Notebook:
        predictive-analytics-kserve
        (Wave 3, GPU node)"]

        NB_IF --> MODEL_AD["anomaly-detector
        model.pkl (sklearn)"]

        NB_PA --> MODEL_PA["predictive-analytics
        model.pkl (LSTM+sklearn)"]

        MODEL_AD --> HEALTH["Health Check Task
        File exists? Loadable?
        Predictions valid?"]

        MODEL_PA --> HEALTH

        HEALTH -->|"Pass"| S3["S3 Object Storage
        model-storage bucket"]

        HEALTH -->|"Fail"| ROLLBACK["Keep previous model.
        Alert operations."]
    end

    subgraph serving["4. Model Serving"]
        S3 --> KS_AD["KServe:
        anomaly-detector
        InferenceService"]

        S3 --> KS_PA["KServe:
        predictive-analytics
        InferenceService"]
    end

    subgraph inference["5. Real-Time Inference"]
        PROM_RT["Prometheus
        (live metrics)"] --> CE

        CE["Coordination Engine
        Receives alerts, queries
        models, orchestrates
        remediation"]

        CE -->|"POST /v1/models/
        anomaly-detector:predict"| KS_AD

        CE -->|"POST /v1/models/
        predictive-analytics:predict"| KS_PA

        KS_AD -->|"Anomaly score
        + classification"| CE

        KS_PA -->|"Failure probability
        + time horizon"| CE
    end

    subgraph healing["6. Self-Healing Loop"]
        CE --> DECIDE{"Decision Engine
        Known issue?"}

        DECIDE -->|"Known pattern"| DET["Deterministic Layer
        Rule-based remediation
        (restart, scale, patch)"]

        DECIDE -->|"Novel anomaly
        score > 0.8"| AI["AI-Driven Layer
        Adaptive response
        (resource adjustment,
        workload migration)"]

        DET --> EXEC["Execute Remediation
        via Kubernetes API"]

        AI --> EXEC

        EXEC --> VERIFY["Verify Resolution
        Check metrics improve
        within timeout"]

        VERIFY -->|"Resolved"| LOG["Log incident.
        Update model
        training data."]

        VERIFY -->|"Not resolved"| ESCALATE["Escalate to
        human operator
        via Lightspeed"]

        LOG --> PROM
    end

    classDef collect fill:#E3F2FD,color:#0D47A1,stroke:#1565C0
    classDef process fill:#F3E5F5,color:#4A148C,stroke:#7B1FA2
    classDef train fill:#E8F5E9,color:#1B5E20,stroke:#2E7D32
    classDef serve fill:#FFF3E0,color:#E65100,stroke:#F57C00
    classDef infer fill:#FCE4EC,color:#880E4F,stroke:#C2185B
    classDef heal fill:#FFEBEE,color:#B71C1C,stroke:#D32F2F

    class PROM,AM,K8S_EV,RAW,ALERTS,EVENTS collect
    class NB_DC,NB_EV,NB_LOG,NB_SYN,FEAT,TRAIN_DATA process
    class TEK_CPU,TEK_GPU,NB_IF,NB_PA,MODEL_AD,MODEL_PA,HEALTH,S3,ROLLBACK train
    class KS_AD,KS_PA serve
    class PROM_RT,CE infer
    class DECIDE,DET,AI,EXEC,VERIFY,LOG,ESCALATE heal
```

## Self-Healing Decision Loop (Detailed)

```mermaid
flowchart LR
    DETECT["🔍 DETECT
    Prometheus alert fires
    or anomaly score
    exceeds threshold"]

    ANALYZE["🧪 ANALYZE
    Coordination Engine
    queries ML models
    for classification"]

    DECIDE2["⚖️ DECIDE
    Known issue: deterministic
    Novel issue: AI-driven
    Confidence > 80% required"]

    ACT["🔧 ACT
    Execute remediation
    via Kubernetes API
    (restart, scale, patch)"]

    VERIFY2["✅ VERIFY
    Monitor metrics for
    improvement within
    timeout window"]

    LEARN["📚 LEARN
    Log resolution data.
    Feed back to training
    pipeline for model
    improvement."]

    DETECT --> ANALYZE --> DECIDE2 --> ACT --> VERIFY2 --> LEARN
    LEARN -.->|"Training data
    enrichment"| DETECT

    classDef step fill:#1565C0,color:#fff,stroke:#0D47A1

    class DETECT,ANALYZE,DECIDE2,ACT,VERIFY2,LEARN step
```

## Training Pipeline Data Flow

```mermaid
flowchart LR
    subgraph trigger["Trigger Sources"]
        CRON["⏰ CronJob
        Weekly schedule
        (Sun 2 AM / 3 AM)"]

        MANUAL["👤 Manual
        tkn pipeline start
        or oc create"]

        DRIFT["📉 Model Drift
        Alert from
        monitoring"]
    end

    subgraph pipeline["Tekton Pipeline"]
        T1["Task 1:
        Execute training
        notebook via
        NotebookValidationJob"]

        T2["Task 2:
        Health check
        (file, load,
        prediction tests)"]

        T3["Task 3:
        Restart
        InferenceService
        predictor pods"]

        T4["Task 4:
        Post-deployment
        endpoint validation"]
    end

    CRON --> T1
    MANUAL --> T1
    DRIFT --> T1

    T1 --> T2 --> T3 --> T4

    T1 -->|"model.pkl"| PVC["Model PVC
    (gp3-csi or CephFS)"]
    PVC --> T2
    PVC -->|"Copy to S3"| S3B["S3 Bucket"]
    S3B --> T3

    classDef trigger fill:#FFF3E0,color:#E65100,stroke:#F57C00
    classDef task fill:#E8F5E9,color:#1B5E20,stroke:#2E7D32
    classDef storage fill:#E3F2FD,color:#0D47A1,stroke:#1565C0

    class CRON,MANUAL,DRIFT trigger
    class T1,T2,T3,T4 task
    class PVC,S3B storage
```

## Notebook Wave Dependencies

Training notebooks execute in a strict order defined by ArgoCD sync waves. Each wave depends on the outputs of the previous wave.

```mermaid
flowchart TD
    W0["Wave 0: Setup
    platform-readiness-validation
    environment-setup
    kserve-model-onboarding"]

    W1["Wave 1: Data Collection
    prometheus-metrics-collection
    openshift-events-analysis
    log-parsing-analysis"]

    W2["Wave 2: Feature Engineering
    feature-store-demo
    synthetic-anomaly-generation"]

    W3["Wave 3: Model Training
    isolation-forest (CPU)
    time-series-anomaly
    lstm-based-prediction (GPU)
    predictive-analytics (GPU)"]

    W4["Wave 4: Ensemble
    ensemble-anomaly-methods"]

    W5["Wave 5: Self-Healing
    rule-based-remediation
    ai-driven-decision-making
    hybrid-healing-workflows"]

    W6["Wave 6: Serving
    kserve-model-deployment
    model-versioning-mlops
    inference-pipeline-setup"]

    W7["Wave 7: E2E Scenarios
    pod-crash-loop-healing
    network-anomaly-response
    resource-exhaustion-detection"]

    W0 --> W1 --> W2 --> W3 --> W4 --> W5 --> W6 --> W7

    classDef wave fill:#1565C0,color:#fff,stroke:#0D47A1

    class W0,W1,W2,W3,W4,W5,W6,W7 wave
```

## Notes

- **Prometheus is the primary data source** for all ML models. Metrics are scraped every 30 seconds and retained for 30 days.
- **Synthetic data augmentation** (Wave 2) supplements real cluster metrics during initial deployment when historical data is limited.
- **Health checks are mandatory** before deploying a new model. If validation fails, the previous model remains active and operations staff receive an alert.
- **The self-healing loop is closed**: resolution data feeds back into the training pipeline, enabling the models to improve their accuracy over time.
- **GPU training uses a separate PVC** (`model-storage-gpu-pvc` on gp3-csi) because GPU nodes may lack CephFS drivers. A copy task moves artifacts to the shared storage after training completes.
- **Feature engineering** can produce up to 3,264 features (24 hours x 136 metrics) for the predictive-analytics model when `featureEngineering.enabled: true`.
