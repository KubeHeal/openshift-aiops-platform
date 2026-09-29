# Notebook Quick Reference Card

## 🎯 30 Notebooks - Complete Self-Healing Platform

### Phase 1: Data Collection (5 notebooks)
```
1. prometheus-metrics-collection.ipynb          → prometheus_metrics.parquet
2. openshift-events-analysis.ipynb              → openshift_events.parquet
3. log-parsing-analysis.ipynb                   → container_logs.parquet
4. feature-store-demo.ipynb                     → feature_store_v1.parquet
5. synthetic-anomaly-generation.ipynb           → synthetic_anomalies.parquet
```
**Time**: 2-3h | **Output**: Training data ready

---

### Phase 2: Anomaly Detection (4 notebooks)
```
1. isolation-forest-implementation.ipynb        → isolation_forest_model.pkl
2. time-series-anomaly-detection.ipynb          → timeseries_model.pkl
3. lstm-based-prediction.ipynb ⚠️ GPU           → lstm_model.h5
4. ensemble-anomaly-methods.ipynb               → ensemble_model.pkl
```
**Time**: 3-4h | **Output**: 4 trained models

---

### Phase 3: Self-Healing Logic (4 notebooks)
```
1. coordination-engine-integration.ipynb        → Connection verified
2. rule-based-remediation.ipynb                 → remediation_rules.json
3. ai-driven-decision-making.ipynb              → Decision metrics
4. hybrid-healing-workflows.ipynb               → Workflow metrics
```
**Time**: 2-3h | **Output**: Healing logic ready

---

### Phase 4: Model Serving (3 notebooks)
```
1. kserve-model-deployment.ipynb                → KServe deployment
2. model-versioning-mlops.ipynb                 → Model registry
3. inference-pipeline-setup.ipynb               → Pipeline metrics
```
**Time**: 2-3h | **Output**: Production inference ready

---

### Phase 5: End-to-End Scenarios (4 notebooks)
```
1. pod-crash-loop-healing.ipynb                 → Healing metrics
2. resource-exhaustion-detection.ipynb          → Scaling metrics
3. network-anomaly-response.ipynb               → Network metrics
4. complete-platform-demo.ipynb                 → Platform demo report
```
**Time**: 2-3h | **Output**: Complete workflows validated

---

### Phase 6: MCP & Lightspeed Integration (3 notebooks)
```
1. mcp-server-integration.ipynb                 → MCP verified
2. openshift-lightspeed-integration.ipynb       → OLS verified
3. llamastack-integration.ipynb                 → LlamaStack verified
```
**Time**: 2h | **Output**: AI services integrated

---

### Phase 7: Monitoring & Operations (3 notebooks)
```
1. prometheus-metrics-monitoring.ipynb          → Monitoring setup
2. model-performance-monitoring.ipynb           → Performance metrics
3. healing-success-tracking.ipynb               → Success report
```
**Time**: 2h | **Output**: Monitoring operational

---

### Phase 8: Advanced Scenarios (4 notebooks)
```
1. multi-cluster-healing-coordination.ipynb     → Multi-cluster metrics
2. predictive-scaling-capacity-planning.ipynb   → Scaling recommendations
3. security-incident-response-automation.ipynb  → Security metrics
4. cost-optimization-resource-efficiency.ipynb  → Cost report
```
**Time**: 2-3h | **Output**: Advanced capabilities ready

---

## 📊 Execution Summary

| Metric | Value |
|--------|-------|
| **Total Notebooks** | 30 |
| **Total Lines of Code** | ~15,000+ |
| **Total Execution Time** | 18-24 hours |
| **Phases** | 8 |
| **Completion Status** | 100% ✅ |

---

## 🚀 Quick Start Commands

```bash
# 1. Access workbench
# https://rhods-dashboard.apps.cluster-dzqpc.dzqpc.sandbox29.opentlc.com/

# 2. Navigate to notebooks
cd /opt/app-root/src/openshift-aiops-platform/notebooks

# 3. Start Phase 1
# Open: 01-data-collection/prometheus-metrics-collection.ipynb

# 4. Run all cells (Shift+Enter or Run All)

# 5. Verify outputs
ls -la /opt/app-root/src/data/processed/

# 6. Move to next notebook
# Open: 01-data-collection/openshift-events-analysis.ipynb
```

---

## ✅ Success Criteria Per Notebook

Each notebook should:
- ✅ Execute without errors
- ✅ Generate expected `.parquet` or `.pkl` files
- ✅ Pass validation checks (printed at end)
- ✅ Complete within estimated time
- ✅ Show summary statistics

---

## 🔑 Key Outputs by Phase

| Phase | Key Output | Location |
|-------|-----------|----------|
| 1 | Training data | `/opt/app-root/src/data/processed/` |
| 2 | Trained models | `/opt/app-root/src/models/` |
| 3 | Healing rules | `remediation_rules.json` |
| 4 | KServe deployment | Kubernetes cluster |
| 5 | Workflow validation | Metrics in notebook |
| 6 | AI integration | Service connections |
| 7 | Monitoring setup | Prometheus + Grafana |
| 8 | Advanced metrics | Reports in `/data/reports/` |

---

## ⚠️ Important Notes

1. **GPU Required**: Phase 2 LSTM notebook needs GPU
2. **Sequential Execution**: Run phases in order (dependencies!)
3. **Storage**: Ensure 50GB+ available in `/opt/app-root/src/`
4. **Network**: Coordination engine must be accessible
5. **Time**: Budget 18-24 hours for complete execution

---

## 📞 Quick Help

**Notebook won't run?**
- Check prerequisites in NOTEBOOK-EXECUTION-GUIDE.md
- Verify environment: `python -c "import torch; print(torch.cuda.is_available())"`

**Missing outputs?**
- Check notebook logs for errors
- Verify storage space: `df -h /opt/app-root/src/`

**Slow execution?**
- Run notebooks sequentially (not parallel)
- Monitor resource usage: `top` or `nvidia-smi`

**Need more info?**
- See: `docs/NOTEBOOK-EXECUTION-GUIDE.md`
- See: `notebooks/README.md`
- See: `docs/adrs/` for architecture

---

**Status**: 🟢 Ready for Production Execution
**Last Updated**: 2025-10-17
**All 30 Notebooks**: ✅ Complete & Validated
