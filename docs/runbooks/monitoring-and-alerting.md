# Runbook: Monitoring and Alerting

**Owner**: Platform Engineering Team / SRE
**Risk Level**: Low
**Last Updated**: 2026-09-29
**Last Tested**: 2026-09-29
**Approved By**: Platform Architect
**Version**: 1.0.0

---

## Quick Reference

| Attribute | Value |
|-----------|-------|
| **Execution Time** | Setup: 30-60 minutes. Ongoing: daily review |
| **Impact Window** | No downtime (monitoring-only changes) |
| **Rollback Time** | ~5 minutes (revert PrometheusRule or dashboard) |
| **Prerequisites** | Platform deployed, Prometheus accessible |

---

## Scope and Use Case

### When to Use This Runbook

Use this runbook to configure, maintain, and use the platform monitoring stack. It covers key metrics, alert thresholds, log analysis, dashboard management, capacity planning, and performance benchmarking.

**Triggers**:
- Initial platform deployment (monitoring setup)
- Alert rule creation or modification
- Capacity review (monthly or quarterly)
- Performance investigation

### Expected Outcome

A fully operational monitoring stack providing visibility into cluster health, platform component health, and ML model performance.

### What This Does NOT Cover

- Alert-triggered incident response procedures (see [incident-response.md](incident-response.md))
- Model retraining triggered by drift detection (see [model-training-operations.md](model-training-operations.md))

---

## Prerequisites

### Required Access

- [ ] `oc` CLI logged in with cluster-admin
- [ ] Access to OpenShift web console
- [ ] (Optional) `tkn` CLI for pipeline monitoring

### Required Tools

- [ ] `oc` 4.18+
- [ ] Web browser (for Prometheus and Grafana UI)

---

## Section 1: Key Metrics to Monitor

### Cluster Health Metrics

| Metric | PromQL Query | Healthy Range | Alert Threshold |
|--------|-------------|---------------|-----------------|
| Node CPU utilization | `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` | <70% | >85% for 10 min |
| Node memory utilization | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` | <80% | >90% for 10 min |
| Node disk utilization | `(node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes * 100` | <75% | >85% |
| Pod restart rate | `increase(kube_pod_container_status_restarts_total{namespace="self-healing-platform"}[1h])` | 0 | >3 per hour |
| API server latency (P99) | `histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket[5m]))` | <1s | >5s for 5 min |

### Platform Component Metrics

| Component | Metric | PromQL Query | Alert Threshold |
|-----------|--------|-------------|-----------------|
| Coordination Engine | Health status | `up{job="coordination-engine"}` | Value = 0 for 2 min |
| Coordination Engine | Request latency | `rate(coordination_engine_request_duration_seconds_sum[5m]) / rate(coordination_engine_request_duration_seconds_count[5m])` | >2s average |
| MCP Server | Health status | `up{job="mcp-server"}` | Value = 0 for 2 min |
| Workbench | Pod status | `kube_pod_status_ready{namespace="self-healing-platform",pod=~"self-healing-workbench.*"}` | Value = 0 for 5 min |
| ArgoCD | Sync status | `argocd_app_info{sync_status!="Synced",namespace="self-healing-platform-hub"}` | Any app not synced for 15 min |

### ML Model Metrics

| Metric | PromQL Query | Healthy Range | Alert Threshold |
|--------|-------------|---------------|-----------------|
| Inference request rate | `sum(rate(kserve_request_count_total{namespace="self-healing-platform"}[5m]))` | >0 | Rate = 0 for 10 min |
| Inference latency (P95) | `histogram_quantile(0.95, rate(kserve_request_latency_bucket{namespace="self-healing-platform"}[5m]))` | <500ms | >2s for 5 min |
| Inference error rate | `sum(rate(kserve_request_count_total{response_code!="200",namespace="self-healing-platform"}[5m])) / sum(rate(kserve_request_count_total{namespace="self-healing-platform"}[5m]))` | <1% | >5% for 5 min |
| Model ready status | `kserve_inferenceservice_ready{namespace="self-healing-platform"}` | 1 (all models ready) | Any model = 0 for 5 min |

### GPU Metrics (If Applicable)

| Metric | PromQL Query | Alert Threshold |
|--------|-------------|-----------------|
| GPU utilization | `DCGM_FI_DEV_GPU_UTIL` | Sustained >95% for 30 min |
| GPU memory utilization | `DCGM_FI_DEV_MEM_COPY_UTIL` | >90% |
| GPU temperature | `DCGM_FI_DEV_GPU_TEMP` | >85 Celsius |

---

## Section 2: Alert Configuration

### Access Existing Alert Rules

```bash
oc get prometheusrule -n self-healing-platform
oc get prometheusrule -n self-healing-platform -o yaml
```

### Create Platform Alert Rules

Apply the following PrometheusRule to configure alerts for all platform components:

```bash
cat <<'EOF' | oc apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: self-healing-platform-alerts
  namespace: self-healing-platform
  labels:
    app.kubernetes.io/name: self-healing-platform
spec:
  groups:
  - name: platform_health
    rules:
    - alert: CoordinationEngineDown
      expr: up{job="coordination-engine"} == 0
      for: 2m
      labels:
        severity: critical
        runbook: incident-response.md#procedure-1
      annotations:
        summary: "Coordination engine is down"
        description: "The coordination engine has been unreachable for more than 2 minutes."

    - alert: InferenceServiceNotReady
      expr: kserve_inferenceservice_ready{namespace="self-healing-platform"} == 0
      for: 5m
      labels:
        severity: critical
        runbook: incident-response.md#procedure-2
      annotations:
        summary: "InferenceService {{ $labels.name }} is not ready"
        description: "Model {{ $labels.name }} has been not ready for more than 5 minutes."

    - alert: HighPodRestartRate
      expr: increase(kube_pod_container_status_restarts_total{namespace="self-healing-platform"}[1h]) > 3
      for: 5m
      labels:
        severity: warning
        runbook: incident-response.md#procedure-0
      annotations:
        summary: "Pod {{ $labels.pod }} restarting frequently"
        description: "Pod {{ $labels.pod }} has restarted {{ $value }} times in the last hour."

    - alert: HighInferenceErrorRate
      expr: |
        sum(rate(kserve_request_count_total{response_code!="200",namespace="self-healing-platform"}[5m]))
        / sum(rate(kserve_request_count_total{namespace="self-healing-platform"}[5m])) > 0.05
      for: 5m
      labels:
        severity: warning
        runbook: incident-response.md#procedure-2
      annotations:
        summary: "High inference error rate"
        description: "Inference error rate is {{ $value | humanizePercentage }}."

  - name: resource_utilization
    rules:
    - alert: HighNodeCPU
      expr: |
        100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
      for: 10m
      labels:
        severity: warning
        runbook: incident-response.md#procedure-7
      annotations:
        summary: "Node {{ $labels.instance }} CPU usage is high"
        description: "CPU usage is {{ $value | printf \"%.1f\" }}%."

    - alert: HighNodeMemory
      expr: |
        (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
      for: 10m
      labels:
        severity: warning
        runbook: incident-response.md#procedure-7
      annotations:
        summary: "Node {{ $labels.instance }} memory usage is high"
        description: "Memory usage is {{ $value | printf \"%.1f\" }}%."

    - alert: PVCNearlyFull
      expr: |
        kubelet_volume_stats_used_bytes{namespace="self-healing-platform"}
        / kubelet_volume_stats_capacity_bytes{namespace="self-healing-platform"} > 0.85
      for: 15m
      labels:
        severity: warning
        runbook: incident-response.md#procedure-4
      annotations:
        summary: "PVC {{ $labels.persistentvolumeclaim }} is nearly full"
        description: "PVC is {{ $value | humanizePercentage }} utilized."
EOF
```

### Verify Alert Rules

```bash
oc get prometheusrule self-healing-platform-alerts -n self-healing-platform
```

### Check Firing Alerts

```bash
oc exec -n openshift-monitoring alertmanager-main-0 -- \
  amtool alert query --alertmanager.url=http://localhost:9093
```

Or access the AlertManager UI:

```bash
oc port-forward -n openshift-monitoring alertmanager-main-0 9093:9093
```

Open `http://localhost:9093` in a browser.

---

## Section 3: Log Aggregation and Analysis

### View Component Logs

#### Coordination Engine

```bash
oc logs -n self-healing-platform deployment/self-healing-coordination-engine --tail=100 -f
```

#### MCP Server

```bash
oc logs -n self-healing-platform deployment/mcp-server --tail=100 -f
```

#### ArgoCD Application Controller

```bash
oc logs -n self-healing-platform-hub deployment/hub-gitops-application-controller --tail=100 -f
```

#### KServe Predictor

```bash
oc logs -n self-healing-platform \
  -l serving.kserve.io/inferenceservice=anomaly-detector \
  -c kserve-container --tail=100 -f
```

### Search Logs for Errors

```bash
oc logs -n self-healing-platform deployment/self-healing-coordination-engine --since=1h | \
  grep -i -E "error|fatal|panic"
```

### Aggregate Events

```bash
oc get events -n self-healing-platform \
  --sort-by='.lastTimestamp' \
  --field-selector type=Warning | tail -20
```

### Log Retention

OpenShift stores container logs until the pod is deleted or the node disk fills. For long-term retention, configure cluster logging:

```bash
oc get clusterlogging -n openshift-logging
```

If cluster logging is not installed, logs are available only for running pods.

---

## Section 4: Dashboard Setup

### Access Prometheus UI

```bash
oc port-forward -n openshift-monitoring prometheus-k8s-0 9090:9090
```

Open `http://localhost:9090` in a browser.

### Access Grafana (If Deployed)

```bash
oc get route grafana -n self-healing-platform -o jsonpath='{.spec.host}'
```

### Create a Platform Overview Dashboard

Apply the Grafana dashboard ConfigMap:

```bash
oc get configmap grafana-dashboard-self-healing -n self-healing-platform
```

If the dashboard does not exist, the Helm chart creates it automatically from `charts/hub/templates/grafana-dashboards.yaml`.

### Essential Dashboard Panels

#### Panel 1: Platform Component Status

```promql
# All components UP
up{namespace="self-healing-platform"}
```

#### Panel 2: Inference Request Rate

```promql
sum by (model_name) (rate(kserve_request_count_total{namespace="self-healing-platform"}[5m]))
```

#### Panel 3: Container Resource Utilization

```promql
# CPU usage by container
sum by (container) (rate(container_cpu_usage_seconds_total{namespace="self-healing-platform"}[5m]))

# Memory usage by container
sum by (container) (container_memory_working_set_bytes{namespace="self-healing-platform"})
```

#### Panel 4: Pod Restart Count

```promql
sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace="self-healing-platform"}[24h]))
```

---

## Section 5: Capacity Planning

### Current Resource Utilization

```bash
oc adm top nodes
oc adm top pods -n self-healing-platform --sort-by=cpu
oc adm top pods -n self-healing-platform --sort-by=memory
```

### Storage Utilization

```bash
oc get pvc -n self-healing-platform -o custom-columns=NAME:.metadata.name,CAPACITY:.status.capacity.storage,STATUS:.status.phase
```

Check actual utilization:

```promql
kubelet_volume_stats_used_bytes{namespace="self-healing-platform"}
/ kubelet_volume_stats_capacity_bytes{namespace="self-healing-platform"}
```

### Capacity Thresholds

| Resource | Warning | Critical | Action |
|----------|---------|----------|--------|
| Node CPU | >70% sustained | >85% sustained | Add worker nodes |
| Node Memory | >75% sustained | >90% sustained | Add worker nodes |
| PVC Storage | >75% used | >85% used | Expand PVC or clean old data |
| S3 Storage | >80% used | >90% used | Clean old model artifacts |
| GPU Memory | >80% | >90% | Schedule fewer concurrent training jobs |

### Capacity Growth Estimation

Run the predictive scaling notebook for data-driven capacity planning:

```bash
oc port-forward self-healing-workbench-0 8888:8888 -n self-healing-platform
```

Open `notebooks/08-advanced-scenarios/predictive-scaling-capacity-planning.ipynb`.

### Scale Resources

#### Add Worker Nodes (ROSA)

```bash
rosa edit machinepool workers --cluster=<NAME> --replicas=<NEW_COUNT>
```

#### Add Worker Nodes (IPI)

```bash
oc scale machineset <NAME> -n openshift-machine-api --replicas=<NEW_COUNT>
```

#### Expand PVC

```bash
oc patch pvc <PVC_NAME> -n self-healing-platform \
  -p '{"spec":{"resources":{"requests":{"storage":"30Gi"}}}}'
```

Verify expansion:

```bash
oc get pvc <PVC_NAME> -n self-healing-platform
```

---

## Section 6: Performance Benchmarking

### Inference Latency Benchmark

Test model inference performance:

```bash
for i in $(seq 1 100); do
  START=$(date +%s%N)
  oc exec -n self-healing-platform deployment/self-healing-coordination-engine -- \
    curl -s -o /dev/null -w "%{http_code}" \
    -X POST http://anomaly-detector-stable:8080/v1/models/anomaly-detector:predict \
    -H "Content-Type: application/json" \
    -d '{"instances": [[0.5, 0.3, 0.8, 0.2, 0.6]]}'
  END=$(date +%s%N)
  echo "Request $i: $((($END-$START)/1000000))ms"
done
```

### Coordination Engine Benchmark

```bash
oc exec -n self-healing-platform deployment/self-healing-coordination-engine -- \
  curl -s -w "\n%{time_total}s\n" http://localhost:8080/health
```

### Resource Baseline

Record the current resource baseline for future comparison:

```bash
echo "=== Resource Baseline $(date) ==="
echo "--- Nodes ---"
oc adm top nodes
echo "--- Platform Pods ---"
oc adm top pods -n self-healing-platform
echo "--- PVCs ---"
oc get pvc -n self-healing-platform
```

Save this output to a file for monthly comparison.

---

## Monitoring Checklist

### Daily Review

- [ ] Check Prometheus alerts dashboard for new or firing alerts
- [ ] Review pod status: `oc get pods -n self-healing-platform | grep -v Running`
- [ ] Verify InferenceServices are ready: `oc get inferenceservices -n self-healing-platform`

### Weekly Review

- [ ] Review resource utilization trends
- [ ] Check training pipeline success rate: `./scripts/check-training-status.sh`
- [ ] Review coordination engine request metrics

### Monthly Review

- [ ] Run capacity planning analysis
- [ ] Compare resource utilization against baseline
- [ ] Review and clean up old PipelineRuns and completed jobs
- [ ] Verify alert rules are current and firing correctly

### Quarterly Review

- [ ] Run full platform benchmark
- [ ] Review alert thresholds against actual incident data
- [ ] Update dashboards for new components or metrics
- [ ] Test alert notification channels

---

## Escalation Path

| Severity | First Contact | Response Time | Next Escalation |
|----------|---------------|---------------|-----------------|
| **P1 (Critical)** | On-call engineer | Immediate | Engineering Manager (15 min) |
| **P2 (High)** | Team Slack #aiops-platform | 30 minutes | Team Lead (1 hour) |
| **P3 (Medium)** | Team Slack #aiops-platform | 2 hours | N/A |

---

## Appendix

### Related Runbooks

- [Incident Response](incident-response.md) (alert-triggered procedures)
- [Model Training Operations](model-training-operations.md) (model drift monitoring)
- [Upgrade and Maintenance](upgrade-and-maintenance.md) (Prometheus storage maintenance)

### Reference Documentation

- [ADR-007: Prometheus Monitoring Integration](../adrs/007-prometheus-monitoring-integration.md)
- [Operator Training Guide](../guides/OPERATOR-TRAINING-GUIDE.md) (PromQL training, Week 2)
- Grafana dashboards template: `charts/hub/templates/grafana-dashboards.yaml`
- PrometheusRule template: `charts/hub/templates/prometheusrule.yaml`

### Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-29 | Platform Engineering | Initial version |

---

**Last Reviewed**: 2026-09-29
**Next Review**: 2026-12-29
**Feedback**: Report issues at https://github.com/KubeHeal/openshift-aiops-platform/issues
