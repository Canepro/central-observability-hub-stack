# Grafana Observability Stack - Quick Start Guide

## 🚀 Access Your Stack (Right Now!)

### Grafana Dashboard

**URL:** https://grafana.canepro.me (HTTPS enabled)

**Login:**
```bash
Username: admin
Password: (run command below)

kubectl -n monitoring get secret grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d ; echo
```

**Note**: Admin credentials and Grafana `secret_key` are sourced from OCI Vault via External Secrets Operator into the `grafana` secret.

**Note**: If HTTPS certificate errors occur, wait 2-3 minutes for certificate propagation or use HTTP fallback: http://grafana.canepro.me

---

## ✅ Datasource Configuration (Already Configured!)

### All Datasources Pre-Configured

All datasources are pre-configured via Helm values:

1. **Prometheus** - Auto-configured ✅
2. **Loki** - Pre-configured ✅
3. **Tempo** - Pre-configured ✅

**To Verify Datasources:**

1. Navigate to **Configuration** → **Data Sources**
2. Click on each datasource
3. Click **Save & Test** - All should show "✓ Data source is working"

**Note**: Loki is configured in **single-tenant** mode in this repo (`auth_enabled: false`), and ingestion auth is handled at the Ingress layer.

---

## 📊 Dashboards (auto-provisioned)

Dashboards are provisioned automatically on startup via the Grafana Helm chart values (no manual import needed).

**Default dashboard set**: See `hub-docs/GRAFANA-E1-DEFAULT-DASHBOARDS.md`.

**Latest-first policy (gnet)**: Set `revision: latest` for Grafana.com dashboards in `helm/grafana-values.yaml`. The Grafana Helm chart otherwise defaults to downloading revision `1`.

### Manual import (optional)

Use this only for ad-hoc testing or one-off dashboards.

1. Click **+** (sidebar) → **Import**
2. Enter Dashboard ID or paste JSON
3. Select datasources (Prometheus, Loki, etc.)
4. Click **Import**

**Note**: The **🌳 Unified World Tree** dashboard provides a multi-cluster view with a `cluster` variable dropdown. It is provisioned from this repo (source JSON: `dashboards/unified-world-tree.json`); import manually only for ad-hoc testing.

---

## 🔍 Test Your Stack (5 minutes)

### Test 1: Verify Multi-Cluster Visibility

1. **Explore** (compass icon in sidebar)
2. Select **Prometheus** datasource
3. Enter query:
   ```promql
   count by (cluster) (up)
   ```
4. Click **Run query**
5. Should see counts for multiple clusters:
   - `oke-hub` (OKE Hub cluster itself)
   - `aks-canepro` (AKS spoke cluster)
   - Additional spoke clusters (if configured)

### Test 2: View Cluster Metrics

1. **Explore** (compass icon in sidebar)
2. Select **Prometheus** datasource
3. Enter query:
   ```promql
   rate(container_cpu_usage_seconds_total{cluster=~"oke-hub|aks-canepro",container!=""}[5m])
   ```
4. Click **Run query**
5. Should see CPU usage graphs for containers across all clusters

### Test 0: Validate Deployment (Recommended)
Run the validation script to confirm pods, services, PVCs, ArgoCD app health, and (if available) resource usage:

```bash
chmod +x scripts/validate-deployment.sh
./scripts/validate-deployment.sh
```

If the script shows `metrics-server not available`, deploy it via ArgoCD (see `argocd/applications/metrics-server.yaml`) to enable:
```bash
kubectl top nodes
kubectl top pods -n monitoring
```

### Note: Live PVC usage panel
If the “Master Health Dashboard” shows `No data` for PVC usage, Prometheus may not be scraping kubelet volume stats.
This repo enables them via `helm/prometheus-values.yaml` (`extraScrapeConfigs`).

### Test 3: View Logs (Multi-Cluster)

1. **Explore**
2. Select **Loki** datasource
3. Enter query:
   ```logql
   {cluster="oke-hub",namespace="monitoring"}
   ```
4. Or query across all clusters:
   ```logql
   {namespace="monitoring"}
   ```
5. Click **Run query**
6. Should see logs from monitoring namespace across all clusters

### Test 4: Send Test Log

```bash
# Port-forward to Loki
kubectl port-forward -n monitoring svc/loki-gateway 3100:80 &

# Send test log
curl -H "Content-Type: application/json" \
  -XPOST "http://127.0.0.1:3100/loki/api/v1/push" \
  --data-raw "{\"streams\": [{\"stream\": {\"job\": \"quickstart-test\"}, \"values\": [[\"$(date +%s)000000000\", \"Hello from Grafana Stack!\"]]}]}"

# Query in Grafana Explore:
{job="quickstart-test"}

# Kill port-forward
kill %1
```

---

## 🔗 Connect External Clusters & Applications

### Multi-Cluster Setup

This hub is designed to aggregate telemetry from multiple clusters (spoke clusters). See **[MULTI-CLUSTER-SETUP-COMPLETE.md](MULTI-CLUSTER-SETUP-COMPLETE.md)** for:

- Current connected clusters and their status
- How to add new spoke clusters
- Troubleshooting cluster visibility

### For Application-Level Integration

See **[CONFIGURATION.md](CONFIGURATION.md)** for detailed guides on:

- **Metrics**: Configure Prometheus remote_write or federation
- **Logs**: Deploy Promtail agents on external hosts
- **Traces**: Set up OTLP collectors for distributed tracing

---

## 🚨 Set Up Alerting (10 minutes)

### Quick Alert Example

Create `k8s/example-alert.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: example-alerts
  namespace: monitoring
  labels:
    release: prometheus
spec:
  groups:
    - name: node-alerts
      interval: 30s
      rules:
        - alert: HighCPUUsage
          expr: |
            100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High CPU usage detected"
            description: "Node {{ $labels.instance }} has CPU usage above 80%"
```

Apply:
```bash
kubectl apply -f k8s/example-alert.yaml
```

View alerts in Grafana:
1. **Alerting** (bell icon) → **Alert rules**
2. Should see "HighCPUUsage" rule

---

## 📱 Configure Notifications (Optional)

### Slack Example

1. Get Slack incoming webhook URL from https://api.slack.com/messaging/webhooks
2. Edit Alertmanager config:

```bash
kubectl edit secret alertmanager-prometheus-alertmanager -n monitoring
```

Add under `receivers`:
```yaml
  - name: 'slack'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
        channel: '#alerts'
        title: 'Grafana Alert'
```

3. Restart Alertmanager:
```bash
kubectl delete pod alertmanager-prometheus-alertmanager-0 -n monitoring
```

---

## 📚 Next Steps

1. ✅ **Access Grafana** and configure Loki datasource
2. ✅ **Import dashboards** for cluster monitoring
3. ✅ **Test queries** in Explore
4. 📖 **Read [CONFIGURATION.md](CONFIGURATION.md)** to connect external apps
5. 🎨 **Create custom dashboards** for your Rocket.Chat deployments
6. 🚨 **Set up alerting** for critical metrics

---

## 🆘 Troubleshooting

### Grafana Login Issues
```bash
# Reset admin password
kubectl exec -n monitoring deployment/grafana -- \
  grafana-cli admin reset-admin-password newpassword
```

### Can't Access Grafana
```bash
# Check Ingress status
kubectl get ingress -n monitoring grafana-ingress

# Check NGINX Ingress LoadBalancer
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Check pod status
kubectl get pods -n monitoring | grep grafana
```

### More Issues
See **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** for comprehensive troubleshooting.

---

## 🎯 What You've Built

A **production-ready centralized observability hub** with:

- ✅ **Grafana** - Unified visualization for metrics, logs, and traces
- ✅ **Prometheus** - 15-day metric retention, auto-discovery
- ✅ **Loki** - 7-day log retention, S3-backed storage (OCI Object Storage)
- ✅ **Tempo** - 7-day trace retention, OTLP support
- ✅ **Alertmanager** - Alert routing and notifications
- ✅ **NGINX Ingress** - Load balancer with SSL/TLS termination
- ✅ **cert-manager** - Automatic SSL certificate management
- ✅ **Auto-collection** - Promtail, Node Exporter, Kube State Metrics

**Total deployment time:** ~30 minutes  
**Storage used:** Free-tier optimized hybrid storage (PVC only where needed; Loki/Tempo use OCI Object Storage)  
**Cost:** $0 (Always Free resources)  
**Access:** https://grafana.canepro.me (HTTPS enabled)

---

**Ready to monitor your Rocket.Chat empire! 🚀📊**
