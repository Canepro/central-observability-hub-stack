# Grafana Observability Stack - Configuration Guide

Guide for configuring external applications to send metrics, logs, and traces to the centralized observability stack.

## Quick Start

This guide provides step-by-step instructions for connecting your applications to the central observability hub.

## Table of Contents

1. [Grafana Configuration](#grafana-configuration)
2. [Connecting External Metrics Sources](#connecting-external-metrics-sources)
3. [Connecting External Log Sources](#connecting-external-log-sources)
4. [Connecting External Trace Sources](#connecting-external-trace-sources)
5. [Alerting Configuration](#alerting-configuration)
6. [Dashboard Configuration](#dashboard-configuration)
7. [User Management](#user-management)

---

## Grafana Configuration

### Initial Access

1. **URL**: https://grafana.canepro.me (HTTPS enabled)
2. **Username**: `admin`
3. **Password**: Run to retrieve:
   ```bash
   kubectl -n monitoring get secret grafana \
     -o jsonpath="{.data.admin-password}" | base64 -d ; echo
   ```
   (Source: External Secrets Operator syncs from OCI Vault into `grafana`)

### Change Admin Password

**Important**: Change the default password immediately after first login.

1. Log in to Grafana
2. Click on the profile icon (bottom left)
3. Go to "Change Password"
4. Enter current and new password

**Or via CLI**:
```bash
kubectl exec -n monitoring deployment/grafana -- \
  grafana-cli admin reset-admin-password <new-password>
```

**Credential source of truth**: Update the JSON secret in OCI Vault (keys: `admin_password`, `secret_key`). ESO refreshes the Kubernetes secret automatically.

### Configure Loki Datasource

**Note**: Loki is running in single-tenant mode with S3 backend. No special headers are required.

1. Navigate to **Configuration** → **Data Sources** → **Loki**
2. **URL**: `http://loki-gateway.monitoring.svc.cluster.local`
3. **Authentication**: Ensure Basic Auth / Custom Headers are **DISABLED**
4. Click **Save & Test**

### Update Grafana Root URL

**Important**: Update Grafana root URL to match your domain for proper redirects and OAuth callbacks.

1. Edit `helm/grafana-values.yaml`:
   ```yaml
   grafana:
     grafana.ini:
       server:
         root_url: https://grafana.canepro.me
   ```
2. **This repo deploys Grafana as its own ArgoCD Application** (see `argocd/applications/grafana.yaml`).
   Update `helm/grafana-values.yaml` and commit/push; ArgoCD will apply automatically.

---

## Connecting External Metrics Sources

### Option 1: Remote Write (Recommended)

Configure external Prometheus instances to `remote_write` to the central Prometheus.

#### Recommended for external clusters (secure ingress)

Use the authenticated ingestion endpoint exposed via Ingress:

```yaml
remote_write:
  - url: https://observability.canepro.me/api/v1/write
    basic_auth:
      username: observability-user
      password: <password>
    external_labels:
      cluster: rocket-chat-azure
      environment: production
      workspace: production
      domain: rocketchat.azure.example.com
```

#### If Prometheus can reach the cluster service (in-cluster / private network)

If the Prometheus instance is running inside the hub cluster (or has private network access to `*.svc.cluster.local`), you can remote_write directly to the ClusterIP service:

```yaml
remote_write:
  - url: http://prometheus-server.monitoring.svc.cluster.local:80/api/v1/write
    # Optional: external labels to identify source
    external_labels:
      cluster: rocket-chat-azure
      environment: production
      workspace: production
      domain: rocketchat.azure.example.com
```

#### Expose Prometheus (if needed)
```bash
# Create LoadBalancer for Prometheus (use with authentication!)
# This repo's service name is `prometheus-server`.
kubectl patch svc prometheus-server -n monitoring -p '{"spec": {"type": "LoadBalancer"}}'
```

### Option 2: Federation

Configure central Prometheus to federate metrics from external instances.

#### On Central Prometheus
Add to `helm/prometheus-values.yaml`:
```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'federate-rocket-chat-azure'
        scrape_interval: 60s
        honor_labels: true
        metrics_path: '/federate'
        params:
          'match[]':
            - '{job="rocketchat"}'
            - '{__name__=~"job:.*"}'
        static_configs:
          - targets:
              - '<external-prometheus-ip>:9090'
            labels:
              cluster: 'rocket-chat-azure'
```

### Option 3: Direct Scraping (for External Endpoints)
Scrape metrics directly from external applications with `/metrics` endpoints.

```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'rocket-chat-external'
        static_configs:
          - targets:
              - 'rocketchat.example.com:3000'
            labels:
              app: 'rocketchat'
              environment: 'production'
              workspace: 'production'
              domain: 'rocketchat.example.com'
        metrics_path: '/metrics'
        scheme: https
```

### Rocket.Chat Metrics Configuration
1. **Admin Panel** → **General** → **Prometheus**
2. Enable **Prometheus Exporter**
3. Set **Prometheus Port**: 9458 (default)
4. Restart Rocket.Chat

Metrics endpoint: `http://<rocketchat-ip>:9458/metrics`

---

## Connecting External Log Sources

### Option 1: Promtail Agent (Recommended)

Deploy Promtail on external systems to forward logs to Loki.

#### Recommended for external systems (secure ingress)

Point Promtail at the authenticated ingestion endpoint:
- Push URL: `https://observability.canepro.me/loki/api/v1/push`
- Auth: use the same basic auth credentials as the ingress

#### Loki query endpoints for server-side readers

If you use server-side tools that read logs directly from Loki (for example Rocket.Chat Logs Viewer app), use:
- Base URL: `https://observability.canepro.me`
- Query path used by clients: `/loki/api/v1/query_range` (and optionally `/loki/api/v1/query`)
- Auth: same Basic Auth credentials used for ingress

Example validation from a workstation:

```bash
curl -sS -u 'observability-user:YOUR_PASSWORD_HERE' -G \
  'https://observability.canepro.me/loki/api/v1/query_range' \
  --data-urlencode 'query={job="rocketchat"}' \
  --data-urlencode 'limit=1'
```

For Rocket.Chat Logs Viewer app settings:
- `loki_base_url`: `https://observability.canepro.me`
- `loki_username`: `observability-user`
- `loki_token`: ingress password

#### Expose Loki Gateway (Securely)
**Option A**: Use port-forward for testing:
```bash
kubectl port-forward -n monitoring svc/loki-gateway 3100:80
```
**Option B**: Expose via LoadBalancer (production - use with authentication):
```bash
kubectl patch svc loki-gateway -n monitoring -p '{"spec": {"type": "LoadBalancer"}}'
```

#### Install Promtail on External System
Download and configure Promtail:
```bash
curl -LO https://github.com/grafana/loki/releases/download/v3.5.1/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip
chmod +x promtail-linux-amd64
```

Create `promtail-config.yaml`:
```yaml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://<LOKI-GATEWAY-IP>:3100/loki/api/v1/push
    # No tenant_id needed for single-tenant mode

scrape_configs:
  - job_name: rocket-chat-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: rocket-chat
          environment: production
          __path__: /var/log/rocketchat/*.log
```

Run Promtail:
```bash
./promtail-linux-amd64 -config.file=promtail-config.yaml
```

### Option 2: Fluent Bit

Configure Fluent Bit to forward to Loki:
```ini
[OUTPUT]
    Name loki
    Match *
    Host <LOKI-GATEWAY-IP>
    Port 3100
    Labels job=rocket-chat, environment=production
    # No headers needed
```

---

## Connecting External Trace Sources

### Option 1: OpenTelemetry Collector

Deploy OTEL Collector to forward traces to Tempo.

#### In-cluster collector (this repo)

This repo deploys an OpenTelemetry Collector in the hub cluster via ArgoCD:
- App: `argocd/applications/otel-collector.yaml`
- Values: `helm/otel-collector-values.yaml`

It receives OTLP (gRPC/HTTP) and exports to the in-cluster Tempo service. This is used for **real traces** from `ingress-nginx` (see `helm/nginx-ingress-values.yaml`).

#### Expose Tempo (Securely)
**For testing** (port-forward):
```bash
kubectl port-forward -n monitoring svc/tempo 4318:4318
```

#### OTEL Collector Configuration

**Using Secure Ingress** (Recommended for production):
Create `otel-collector-config.yaml`:
```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:

exporters:
  otlphttp:
    endpoint: https://observability.canepro.me
    headers:
      Authorization: "Basic <base64-encoded-credentials>"
    # Note: Path /v1/traces is standard OTLP HTTP path

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlphttp]
```

### Option 2: Direct Application Instrumentation

Instrument applications to send traces directly to Tempo.

**Node.js example** (Rocket.Chat) - **Using Secure Ingress**:
```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: 'https://observability.canepro.me/v1/traces',
    headers: {
      'Authorization': 'Basic ' + Buffer.from('observability-user:YOUR_PASSWORD').toString('base64')
    }
    // Note: Path /v1/traces corresponds to the Ingress rule
  }),
});
sdk.start();
```

---

## Alerting Configuration

### Create Alerting Rules in Prometheus

Create `k8s/alerting-rules.yaml`:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: custom-alerts
  namespace: monitoring
  labels:
    release: prometheus
spec:
  groups:
    - name: rocket-chat-alerts
      interval: 30s
      rules:
        - alert: HighErrorRate
          expr: |
            rate(http_requests_total{status=~"5.."}[5m]) > 0.1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High error rate detected"
            description: "Error rate is {{ $value }} requests/sec"
```
Apply: `kubectl apply -f k8s/alerting-rules.yaml`

### Configure Alertmanager Notifications

Do not hand-edit Alertmanager configs in-cluster.

This repo manages Alertmanager configuration via Helm values:
- Alertmanager routing + email receiver: `helm/prometheus-values.yaml` under `alertmanager.config`
- SMTP credentials (kept out of Git): Kubernetes Secret `monitoring/grafana-smtp-credentials`

If you need to change routing/receivers, change Git and let ArgoCD reconcile.

---

## Dashboard Configuration

### Import Pre-built Dashboards

1. **Navigate to Grafana** → **Dashboards** → **Import**
2. **Enter dashboard ID**:
   - **315**: Kubernetes Cluster Monitoring
   - **1860**: Node Exporter Full
   - **13186** / **12019**: Loki dashboards (this repo provisions both by default)
   - **23242**: OpenTelemetry + Tempo (this repo provisions by default)

---

## User Management

### Create Additional Grafana Users
1. **Configuration** → **Users** → **Invite**
2. Enter email and assign role (Admin, Editor, Viewer)

---

## Related Documentation
- [Hub Architecture](../hub-docs/ARCHITECTURE.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
