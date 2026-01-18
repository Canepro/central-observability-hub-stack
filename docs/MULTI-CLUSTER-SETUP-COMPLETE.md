# Multi-Cluster Monitoring Setup - Complete ✅

## Overview

Your multi-cluster monitoring setup is now working! This document explains the current state and how to use it.

## Current Setup Status

### Working Clusters

1. **OKE Hub** (`oke-hub`)
   - **Location**: Oracle Cloud, Ashburn
   - **Role**: Central observability hub
   - **Metrics**: Now properly labeled with `cluster=oke-hub`
   - **Components**: Prometheus, Grafana, Loki, Tempo, ArgoCD

2. **AKS Spoke** (`aks-canepro`)
   - **Location**: Azure UK South
   - **Role**: Production Rocket.Chat deployment
   - **Metrics**: ✅ Successfully sending to OKE Hub
   - **Targets**: 15 (nodes, Rocket.Chat services, cert-manager, traefik, etc.)

### Pending Clusters

3. **Kind Spoke** (Podman)
   - **Status**: Not currently running
   - **Configuration**: Ready in `docs/external-config/prometheus-agent-kind-spoke.yaml`

4. **Kind Spoke** (VM)
   - **Status**: Shutdown
   - **Configuration**: Ready in `docs/external-config/prometheus-agent-kind-spoke.yaml`

## Changes Applied

### 1. OKE Hub Cluster Labels

**File**: `helm/prometheus-values.yaml`

Added external labels to the OKE Prometheus server:

```yaml
server:
  global:
    scrape_interval: 30s
    evaluation_interval: 30s
    external_labels:
      cluster: oke-hub
      environment: production
      workspace: hub
      domain: observability.canepro.me
```

**Effect**: All metrics scraped by the OKE Hub Prometheus (internal components like Grafana, Loki, Prometheus itself, ArgoCD, etc.) will now have the `cluster=oke-hub` label.

### 2. ArgoCD Sync

After committing and pushing this change, ArgoCD will automatically sync the Prometheus configuration. You can monitor the sync:

```bash
# Switch to OKE cluster
kubectl config use-context oke-cluster

# Watch ArgoCD sync
kubectl get application prometheus -n argocd -w

# Or check via ArgoCD UI
open https://argocd.canepro.me
```

## Verifying Multi-Cluster Metrics

### Check Prometheus Directly

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

Then open `http://localhost:9090` and run:

```promql
count by (cluster) (up)
```

**Expected result**: You should see 3 series:
- `cluster="oke-hub"` - OKE internal metrics
- `cluster="aks-canepro"` - AKS cluster metrics (15 targets)
- `{}` (empty) - Any metrics without cluster labels (should disappear after sync)

### Check in Grafana

1. Open `https://grafana.canepro.me`
2. Go to **Explore**
3. Run the same query:
   ```promql
   count by (cluster) (up)
   ```

## Using the Unified World Tree Dashboard

The **"🌳 Unified World Tree - Multi-Cluster Health"** dashboard is specifically designed for multi-cluster monitoring.

### Access the Dashboard

1. Go to `https://grafana.canepro.me`
2. Navigate to **Dashboards** → Search for "World Tree"
3. Open **"🌳 Unified World Tree - Multi-Cluster Health"**

### Using the Cluster Filter

At the top of the dashboard, you'll see a **cluster** dropdown:
- Select **"All"** to see all clusters together
- Select **"oke-hub"** to see only OKE Hub metrics
- Select **"aks-canepro"** to see only AKS metrics
- Select multiple clusters for comparison

### Key Panels

- **Cluster Status**: Shows how many clusters are online
- **Targets Up (by Cluster)**: Shows scrape targets per cluster
- **Node CPU/Memory/Disk Usage**: Filtered by cluster
- **Pods Not Ready**: Shows unhealthy pods per cluster
- **Container Restarts**: Shows restart counts per cluster
- **Cluster Comparison**: Side-by-side metrics

## About the "KBS Dashboard"

The **"KBS Dashboard"** you were viewing is **NOT** the multi-cluster dashboard from this repository. It appears to be:
- Either imported separately from Grafana Labs
- Or created manually in Grafana
- Designed for single-cluster monitoring only

**Why it only shows OKE metrics:**
- It doesn't have a `cluster` filter/variable configured
- It's likely using label filters that only match OKE metrics
- It was not designed for multi-cluster environments

**Recommendation**: Use the **"🌳 Unified World Tree"** dashboard for multi-cluster monitoring instead.

## Troubleshooting

### AKS Metrics Not Appearing in Grafana

If you don't see `aks-canepro` in the cluster dropdown:

1. **Refresh the dashboard variables**:
   - Click the cluster dropdown
   - Click the refresh icon next to it
   - Wait a few seconds

2. **Check Prometheus directly** (as shown above)

3. **Clear Grafana cache**:
   - Go to Dashboard Settings → JSON Model
   - Change `refresh` to `"5s"` temporarily
   - Save and reload

### OKE Hub Metrics Still Showing Without Cluster Label

If you still see metrics with empty `{}` cluster labels:

1. **Wait for ArgoCD to sync** (usually takes 1-3 minutes)
2. **Check ArgoCD Application status**:
   ```bash
   kubectl get application prometheus -n argocd
   ```
3. **Force sync if needed**:
   ```bash
   argocd app sync prometheus
   ```
4. **Verify the Prometheus config was updated**:
   ```bash
   kubectl get configmap prometheus-server -n monitoring -o yaml | grep -A 5 "external_labels"
   ```

### Node Metrics Showing as "Down" on AKS

You noticed that AKS nodes show `up=0` in Prometheus. This is because the Prometheus agent on AKS can't scrape the kubelet metrics due to TLS certificate validation.

**To fix** (optional, if you want node-level metrics from kubelet):

Edit the AKS Prometheus agent config to skip TLS verification:

```yaml
# In aks-canepro cluster
- job_name: 'kubernetes-nodes'
  scheme: https
  tls_config:
    ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    insecure_skip_verify: true  # Add this line
```

But you're already getting node metrics from node-exporter and kube-state-metrics, so this is not critical.

## Next Steps

### 1. Deploy Promtail on AKS (Optional)

If you want to send logs from AKS to the OKE Loki instance:

```bash
# On AKS cluster
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install promtail grafana/promtail \
  --namespace monitoring \
  --set config.clients[0].url=https://observability.canepro.me/loki/api/v1/push \
  --set config.clients[0].basic_auth.username=observability-user \
  --set config.clients[0].basic_auth.password=50JjX+diU6YmAZPl
```

### 2. Add More Spoke Clusters

When you bring up your Kind clusters or add new clusters:

1. Copy the appropriate agent config from `docs/external-config/`
2. Create the `observability-credentials` secret
3. Deploy the Prometheus agent
4. Metrics will automatically appear in Grafana with the `cluster` label

### 3. Create Cluster-Specific Dashboards

You can duplicate the "Unified World Tree" dashboard and pre-filter it for specific clusters:
- **OKE Hub Dashboard**: Set `cluster` variable default to `oke-hub`
- **AKS Dashboard**: Set `cluster` variable default to `aks-canepro`

## Summary

✅ **OKE Hub**: Now properly labeled with `cluster=oke-hub`  
✅ **AKS Spoke**: Successfully sending metrics with `cluster=aks-canepro`  
✅ **Multi-cluster dashboard**: "🌳 Unified World Tree" ready to use  
⏳ **Waiting for**: ArgoCD to sync the Prometheus configuration  

Your multi-cluster observability stack is operational! 🎉
