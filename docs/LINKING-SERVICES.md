# Linking Services, Clusters, and Deployments to Grafana

Quick reference guide for connecting various services and clusters to your Grafana observability stack.

## Table of Contents

1. [Same Cluster Services](#same-cluster-services)
2. [Other Kubernetes Clusters](#other-kubernetes-clusters)
3. [External Deployments (Non-K8s)](#external-deployments-non-k8s)
4. [Quick Reference](#quick-reference)

---

## Same Cluster Services

### Method 1: ServiceMonitor (Recommended for K8s Services)

For services already running in the same Kubernetes cluster, use ServiceMonitor CRD for automatic discovery.

#### Step 1: Ensure Your Service Exposes Metrics

Your service must expose a `/metrics` endpoint (typically on port 9090 or 8080).

**Example Service:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: my-namespace
  labels:
    app: my-app
spec:
  ports:
    - name: metrics
      port: 9090
      targetPort: 9090
  selector:
    app: my-app
```

#### Step 2: Create ServiceMonitor

Create a ServiceMonitor resource that tells Prometheus to scrape your service:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-metrics
  namespace: my-namespace  # Can be in any namespace
  labels:
    release: prometheus  # Important: matches Prometheus selector
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

#### Step 3: Apply and Verify

```bash
# Apply ServiceMonitor
kubectl apply -f servicemonitor.yaml

# Verify Prometheus discovered it
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
# Open http://localhost:9090/targets
# Look for your service in the targets list
```

**Note**: ServiceMonitor discovery is enabled in your Prometheus config (`serviceMonitorSelectorNilUsesHelmValues: false`).

---

## Other Kubernetes Clusters

> ⚠️ **Security Warning**: Exposing services directly via LoadBalancer without authentication is a security risk. See [Security Recommendations](SECURITY-RECOMMENDATIONS.md) for best practices.

### Method 1: Prometheus Remote Write (Recommended)

Configure external Prometheus instances to push metrics to your central Prometheus.

#### Step 1: Expose Central Prometheus (Securely)

> 💡 **Recommended**: Use Ingress with authentication (Option C) instead of direct LoadBalancer for production.

##### Option A: Port Forward (Testing)

```bash
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
# Access at http://localhost:9090
```

##### Option B: LoadBalancer (Production - Use Authentication!)

```bash
# Create external service
kubectl expose statefulset prometheus-prometheus-prometheus \
  --type=LoadBalancer \
  --name=prometheus-external \
  --port=9090 \
  --target-port=9090 \
  -n monitoring

# Get external IP
kubectl get svc prometheus-external -n monitoring
```

##### Option C: Ingress with Authentication (Most Secure) ⭐ Recommended

See [Security Recommendations](SECURITY-RECOMMENDATIONS.md) for detailed setup. Quick example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: observability-services
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: observability-auth
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts: [observability.canepro.me]
      secretName: observability-tls
  rules:
    - host: observability.canepro.me
      http:
        paths:
          - path: /api/v1/write
            pathType: Prefix
            backend:
              service:
                name: prometheus-server
                port: { number: 80 }
```

Create auth secret:
```bash
htpasswd -c auth observability-user
kubectl create secret generic observability-auth \
  --from-file=auth -n monitoring
```

#### Step 2: Configure External Prometheus

On the external cluster, edit Prometheus configuration:

```yaml
# prometheus.yml on external cluster
remote_write:
  - url: http://<CENTRAL-PROMETHEUS-IP>:9090/api/v1/write
    # Optional: Add authentication
    basic_auth:
      username: admin
      password: <password>
    # Add labels to identify source
    external_labels:
      cluster: rocket-chat-azure
      environment: production
      region: us-east
```

#### Step 3: Restart External Prometheus

```bash
# Restart Prometheus to apply config
kubectl rollout restart statefulset/prometheus -n monitoring
```

### Method 2: Prometheus Federation

Configure central Prometheus to pull metrics from external instances.

#### Step 1: Expose External Prometheus

On the external cluster, expose Prometheus:

```bash
kubectl expose statefulset prometheus \
  --type=LoadBalancer \
  --name=prometheus-external \
  --port=9090 \
  -n monitoring
```

#### Step 2: Configure Central Prometheus

Edit `helm/prometheus-values.yaml`:

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
            - '{__name__=~"up"}'
        static_configs:
          - targets:
              - '<EXTERNAL-PROMETHEUS-IP>:9090'
            labels:
              cluster: 'rocket-chat-azure'
              environment: 'production'
```

#### Step 3: Upgrade Prometheus

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -f helm/prometheus-values.yaml -n monitoring
```

---

## External Deployments (Non-K8s)

### Metrics: Direct Scraping

For services running outside Kubernetes (VMs, bare metal, Docker).

#### Step 1: Ensure Service Exposes Metrics

Your service must have a `/metrics` endpoint accessible.

#### Step 2: Configure Prometheus to Scrape

Edit `helm/prometheus-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'rocket-chat-external'
        static_configs:
          - targets:
              - 'rocketchat.example.com:3000'
              - 'rocketchat2.example.com:3000'
            labels:
              app: 'rocketchat'
              environment: 'production'
              deployment_type: 'external'
        metrics_path: '/metrics'
        scheme: https  # or http
        scrape_interval: 30s
```

#### Step 3: Upgrade Prometheus

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -f helm/prometheus-values.yaml -n monitoring
```

### Logs: Promtail Agent

Deploy Promtail on external systems to forward logs to Loki.

#### Step 1: Expose Loki Gateway

##### Option A: Port Forward (Testing)

```bash
kubectl port-forward -n monitoring svc/loki-gateway 3100:80
```

##### Option B: LoadBalancer (Production)

```bash
kubectl patch svc loki-gateway -n monitoring \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Get external IP
kubectl get svc loki-gateway -n monitoring
```

#### Step 2: Install Promtail on External System

```bash
# Download Promtail
curl -LO https://github.com/grafana/loki/releases/download/v3.5.1/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip
chmod +x promtail-linux-amd64
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
```

#### Step 3: Create Promtail Config

Create `/etc/promtail/config.yaml`:

```yaml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://<LOKI-GATEWAY-IP>:3100/loki/api/v1/push
    headers:
      X-Scope-OrgID: "1"  # Required for multi-tenancy

scrape_configs:
  - job_name: rocket-chat-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: rocket-chat
          environment: production
          cluster: external
          __path__: /var/log/rocketchat/*.log
```

#### Step 4: Run Promtail

**As systemd service (recommended):**

Create `/etc/systemd/system/promtail.service`:

```ini
[Unit]
Description=Promtail Log Collector
After=network.target

[Service]
Type=simple
User=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl start promtail
sudo systemctl status promtail
```

### Traces: OpenTelemetry Collector

For applications sending distributed traces.

#### Step 1: Expose Tempo

##### Option A: Port Forward (Testing)

```bash
kubectl port-forward -n monitoring svc/tempo 4318:4318
```

##### Option B: LoadBalancer (Production)

```bash
kubectl patch svc tempo -n monitoring \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Get external IP
kubectl get svc tempo -n monitoring
```

#### Step 2: Configure OTEL Collector

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
  resource:
    attributes:
      - key: cluster
        value: external
        action: insert

exporters:
  otlp:
    endpoint: <TEMPO-IP>:4317
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [otlp]
```

#### Step 3: Run OTEL Collector

```bash
docker run -d --name otel-collector \
  -p 4317:4317 -p 4318:4318 \
  -v $(pwd)/otel-collector-config.yaml:/etc/otel-collector-config.yaml \
  otel/opentelemetry-collector:latest \
  --config=/etc/otel-collector-config.yaml
```

---

## Quick Reference

### Service Endpoints

| Service | Internal URL | External Access |
|---------|-------------|-----------------|
| **Prometheus** | `http://prometheus-server.monitoring.svc.cluster.local:80` | Port-forward or LoadBalancer |
| **Loki Gateway** | `http://loki-gateway.monitoring.svc.cluster.local:80` | Port-forward or LoadBalancer |
| **Tempo** | `http://tempo.monitoring.svc.cluster.local:4318` | Port-forward or LoadBalancer (OTLP HTTP) |
| **Grafana** | `http://grafana.monitoring.svc.cluster.local:80` | <https://grafana.canepro.me> |

### Connection Methods Summary

| Source Type | Metrics | Logs | Traces |
|------------|---------|------|--------|
| **Same K8s Cluster** | ServiceMonitor | Promtail (DaemonSet) | ServiceMonitor + OTEL |
| **Other K8s Cluster** | Remote Write / Federation | Promtail agent | OTEL Collector |
| **External (VM/Bare Metal)** | Direct Scrape | Promtail agent | OTEL Collector |
| **Cloud Services** | Exporter + Scrape | Cloud Log Forwarder | Cloud Trace Forwarder |

### Verification Steps

1. **Check Prometheus Targets:**

   ```bash
   kubectl port-forward -n monitoring svc/prometheus-server 9090:80
   # Open http://localhost:9090/targets
   ```

2. **Check Loki Logs:**

   ```bash
   # In Grafana: Explore → Select Loki datasource
   # Query: {job="your-job-name"}
   ```

3. **Check Tempo Traces:**

   ```bash
   # In Grafana: Explore → Select Tempo datasource
   # Search for service name
   ```

### Common Labels

Use consistent labels across all sources for better filtering:

```yaml
labels:
  cluster: <cluster-name>
  environment: <prod|dev|staging>
  region: <region-name>
  app: <application-name>
```

---

## Next Steps

1. **Import Dashboards**: Use dashboard IDs from `docs/CONFIGURATION.md`
2. **Create Alerts**: Set up PrometheusRule resources for your services
3. **Configure Notifications**: Set up Alertmanager receivers (Slack, email, etc.)
4. **Multi-Tenancy**: Configure different `X-Scope-OrgID` values for different tenants

## Related Documentation

- [Security Recommendations](SECURITY-RECOMMENDATIONS.md) - **⚠️ Important: Read before exposing services**
- [Full Configuration Guide](CONFIGURATION.md) - Detailed configuration options
- [Architecture Documentation](ARCHITECTURE.md) - System architecture
- [Deployment Guide](DEPLOYMENT.md) - Initial deployment steps
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues and solutions
