# Rocket.Chat Cluster Observability Setup

Use these instructions to configure the `rocketchat-k8s` cluster (AKS, `k8.canepro.me`) or any remote cluster to send telemetry to the central **Canepro Observability Hub**.

## 1. Credentials

**Hub URL**: `https://observability.canepro.me`
**Username**: `observability-user`
**Password**: use the approved operator credential path

### Rocket.Chat Logs Viewer app settings (read path)

If you install the Rocket.Chat marketplace app `Logs Viewer`, configure:
- `loki_base_url`: `https://observability.canepro.me`
- `loki_username`: `observability-user`
- `loki_token`: use the approved operator credential path

Important:
- The app is a **reader** and calls Loki query APIs (`/loki/api/v1/query_range`).
- Ingress must expose Loki query routes, not only `/loki/api/v1/push`.

---

## 2. Instructions for IDE Agent / Terminal

Run the following steps in the **remote cluster's environment** (e.g., `rocketchat-k8s` repo).

### Step 1: Clean up old configurations
Remove any existing Grafana Cloud secrets or old agents to avoid conflicts.

```bash
# Remove old credentials
kubectl delete secret grafana-cloud-credentials -n monitoring --ignore-not-found

# Remove old agent (if named prometheus-agent)
# Note: If installed via Helm, use helm uninstall. If via manifest:
kubectl delete deployment prometheus-agent -n monitoring --ignore-not-found
kubectl delete configmap prometheus-agent-config -n monitoring --ignore-not-found
```

### Step 2: Create Observability Namespace & Secret
Ensure the namespace exists and store the hub credentials through the approved
secret store or a private operator runbook.

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

kubectl get secret observability-credentials -n monitoring -o json |
  jq '{name:.metadata.name, data_keys:(.data|keys)}'
```

### Step 3: Deploy Prometheus Agent
Create `manifests/prometheus-agent-hub.yaml` with the following content and apply it.

*(Copy the content from `docs/external-config/prometheus-agent-canepro.yaml` in the central repo)*

```bash
# Apply the new agent
kubectl apply -f manifests/prometheus-agent-hub.yaml
```

### Step 4: Deploy Promtail (Logs)
If not already running, deploy Promtail to ship logs to Loki.

**Update `values-monitoring.yaml` or Promtail config:**

```yaml
promtail:
  config:
    clients:
      - url: https://observability.canepro.me/loki/api/v1/push
        basic_auth:
          username: observability-user
          password: <redacted>
```

**Apply via Helm:**
```bash
helm upgrade --install promtail grafana/promtail -f values-monitoring.yaml -n monitoring
```

---

## 3. Verification

1.  **Check Agent Logs**:
    ```bash
    kubectl logs -l app=prometheus-agent -n monitoring
    ```
    Look for `Remote write` success messages.

2.  **Check Central Grafana**:
    -   Go to https://grafana.canepro.me
    -   Explore -> Prometheus
    -   Query: `{cluster="aks-canepro"}` (or whatever `external_labels.cluster` you set)
