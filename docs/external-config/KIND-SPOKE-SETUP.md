# Kind Spoke - Prometheus Remote Write Setup

This guide explains how to configure the Kind Spoke cluster to push metrics to the OKE Hub via Prometheus Remote Write.

## Overview

The Kind Spoke cluster runs a Prometheus Agent that:
- Scrapes Node Exporter metrics (if available)
- Scrapes Kube-State-Metrics (if available)
- Scrapes Kubelet metrics (cAdvisor, node metrics)
- Scrapes pods with `prometheus.io/scrape` annotation
- Pushes all metrics to the OKE Hub via Remote Write

## Prerequisites

1. **Kind Spoke Cluster**: Running and accessible
2. **L4 Proxy**: socat proxy running on port 6443 (bridging Kind to Hub)
3. **Hub Ingress**: NGINX Ingress configured with `/api/v1/write` endpoint
4. **Credentials**: Basic auth credentials for `observability.canepro.me`

## Step 1: Create Monitoring Namespace

```bash
# Switch to Kind cluster context
kubectl config use-context kind-kind  # or your Kind context name

# Create namespace
kubectl create namespace monitoring
```

## Step 2: Create Credentials Secret

You need the same credentials used in the Hub's `observability-auth` secret.

```bash
# Create the secret with Basic Auth credentials
kubectl create secret generic observability-credentials \
  --from-literal=username="observability-user" \
  --from-literal=password="YOUR_PASSWORD_HERE" \
  -n monitoring
```

**Note**: Replace `YOUR_PASSWORD_HERE` with the actual password from your Hub's `observability-auth` secret.

To retrieve the password from the Hub:
```bash
# Switch to Hub context
kubectl config use-context <oke-context>

# Get the password (if stored as plain text)
kubectl get secret observability-auth -n monitoring -o jsonpath='{.data.auth}' | base64 -d
```

## Step 3: Deploy Node Exporter (Optional but Recommended)

If Node Exporter is not already deployed, you can deploy it:

```bash
# Using Helm (recommended)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter \
  --namespace monitoring \
  --set serviceAccount.create=true \
  --set rbac.create=true
```

Or using a simple DaemonSet:
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.6.1
        ports:
        - containerPort: 9100
        args:
        - --path.procfs=/host/proc
        - --path.sysfs=/host/sys
        - --path.rootfs=/rootfs
        - --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($|/)
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
        - name: rootfs
          mountPath: /rootfs
          readOnly: true
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
      - name: rootfs
        hostPath:
          path: /
      hostNetwork: true
      hostPID: true
```

## Step 4: Deploy Kube-State-Metrics (Optional but Recommended)

```bash
# Using Helm
helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics \
  --namespace monitoring \
  --set serviceAccount.create=true \
  --set rbac.create=true
```

## Step 5: Deploy Prometheus Agent

Apply the Prometheus Agent configuration:

```bash
# Apply the configuration
kubectl apply -f docs/external-config/prometheus-agent-kind-spoke.yaml

# Verify deployment
kubectl get pods -n monitoring -l app=prometheus-agent-kind-spoke

# Check logs
kubectl logs -n monitoring -l app=prometheus-agent-kind-spoke --tail=50
```

## Step 6: Verify Remote Write

### Check Agent Logs

```bash
# Watch logs for remote write activity
kubectl logs -n monitoring -l app=prometheus-agent-kind-spoke -f
```

Look for:
- No errors about authentication
- Successful remote write messages
- Metrics being scraped

### Verify on Hub

On the Hub cluster, check if metrics are arriving:

```bash
# Switch to Hub context
kubectl config use-context <oke-context>

# Query Prometheus for Kind cluster metrics
# In Grafana Explore or via port-forward:
kubectl port-forward -n monitoring svc/prometheus-server 9090:80

# Then query:
# up{cluster="kind-kind-cluster"}
# node_cpu_seconds_total{cluster="kind-kind-cluster"}
# kube_pod_info{cluster="kind-kind-cluster"}
```

## Troubleshooting

### Agent Pod Not Starting

```bash
# Check pod status
kubectl describe pod -n monitoring -l app=prometheus-agent-kind-spoke

# Check logs
kubectl logs -n monitoring -l app=prometheus-agent-kind-spoke
```

### Authentication Errors

If you see `401 Unauthorized`:
1. Verify the secret exists: `kubectl get secret observability-credentials -n monitoring`
2. Check username/password match the Hub's `observability-auth` secret
3. Verify the Hub ingress is accessible: `curl -u user:pass https://observability.canepro.me/api/v1/write`

### No Metrics Appearing on Hub

1. **Check Agent Logs**: Look for remote write errors
2. **Verify Network**: Ensure Kind cluster can reach `observability.canepro.me`
3. **Check Scrape Targets**: Verify Node Exporter/Kube-State-Metrics are running
4. **Verify Labels**: Check that metrics have `cluster="kind-kind-cluster"` label

### Node Exporter Not Found

If the agent can't find Node Exporter:
1. Verify Node Exporter is deployed: `kubectl get pods -n monitoring -l app=node-exporter`
2. Check service exists: `kubectl get svc -n monitoring -l app=node-exporter`
3. Verify labels match the scrape config (should have `app=node-exporter` or similar)

### Kube-State-Metrics Not Found

1. Verify Kube-State-Metrics is deployed: `kubectl get pods -n monitoring -l app=kube-state-metrics`
2. Check service port (should be 8080): `kubectl get svc -n monitoring -l app=kube-state-metrics`
3. Verify labels match the scrape config

## Expected Metrics

Once configured, you should see these metrics on the Hub with `cluster="kind-kind-cluster"`:

- **Node Metrics**: `node_cpu_seconds_total`, `node_memory_*`, `node_filesystem_*`
- **Kubelet Metrics**: `container_*`, `machine_*`
- **Kube-State-Metrics**: `kube_pod_*`, `kube_node_*`, `kube_deployment_*`
- **Custom Pod Metrics**: Any pods with `prometheus.io/scrape=true` annotation

## Next Steps

1. **View in Grafana**: Open the "🌳 Unified World Tree" dashboard
2. **Set Up Alerts**: Configure alerts for Kind Spoke health
3. **Monitor Remote Write**: Watch the "Remote Write Metrics Received" panel

## Related Documentation

- [Main Configuration Guide](../CONFIGURATION.md)
- [Troubleshooting Guide](../TROUBLESHOOTING.md)
- [Hub Architecture](../../hub-docs/ARCHITECTURE.md)
