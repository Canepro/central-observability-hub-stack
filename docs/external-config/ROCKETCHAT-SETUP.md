# Rocket.Chat Cluster Observability Setup

Use these instructions to configure the `rocketchat-k8s` cluster (or any remote cluster) to send telemetry to the central **Canepro Observability Hub**.

## 1. Credentials

**Hub URL**: `https://observability.canepro.me`
**Username**: `observability-user`
**Password**: `50JjX+diU6YmAZPl`

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
Ensure the namespace exists and store the hub credentials.

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic observability-credentials -n monitoring \
  --from-literal=username="observability-user" \
  --from-literal=password="50JjX+diU6YmAZPl" \
  --dry-run=client -o yaml | kubectl apply -f -
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
          password: 50JjX+diU6YmAZPl
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
    -   Query: `{cluster="rocketchat-k3s"}` (or whatever `external_labels.cluster` you set)
