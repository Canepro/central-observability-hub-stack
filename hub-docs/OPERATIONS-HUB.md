# Hub Admin & Operations Guide

This guide focuses on the specific maintenance and operational requirements of the OKE Hub stack.

## 🛡️ Retention Policies (Always Free Tier Optimization)
To stay within the **200Gi Total Storage limit** (Boot Volumes + Block Volumes) and manage Object Storage costs, the following retention policies are enforced:

| Component | Policy | Storage Type | Size |
|-----------|--------|--------------|------|
| **Loki** | 168h (7 days) | Object Storage | N/A |
| **Tempo** | 168h (7 days) | Object Storage | N/A |
| **Prometheus** | 15 days | Block Volume | 50Gi |
| **Grafana** | Indefinite | Block Volume | 50Gi |
| **Alertmanager** | Ephemeral | emptyDir | N/A |

### The 200Gi Storage Calculation
OCI Always Free Tier provides 200GB of total storage. Our current usage:
- **Worker Node Boot Volumes**: 2 x 47GB = 94GB
- **Observability Hub PVCs**: 2 x 50GB = 100GB
- **Total**: **194GB** (Buffer: 6GB)

### Why Alertmanager is Ephemeral?
To fit within the 200GB limit, Alertmanager's persistent volume (previously 50Gi) was sacrificed for `emptyDir`. This means alert silences and notification history are lost on pod restart, but metrics and long-term dashboards remain safe.

### Why 7 Days?
The 7-day (168h) window is the "Goldilocks" setting: long enough to troubleshoot issues from the previous week, but short enough to prevent storage saturation on the Always Free Tier.

## 📦 OCI Storage Integration
The Hub uses OCI Object Storage for long-term data persistence (Loki and Tempo).

### S3-Compatible Configuration
Both Loki and Tempo use the S3-compatible API to communicate with OCI.
- **Endpoint**: `iducrocaj9h2.compat.objectstorage.us-ashburn-1.oraclecloud.com`
- **Region**: `us-ashburn-1`
- **Buckets**: `loki-data`, `tempo-data`

### 🔑 Customer Secret Keys
**Important**: Do not use standard OCI API Signing Keys. You must use **Customer Secret Keys**:
1. Go to the OCI Console.
2. User Settings -> Resources -> **Customer Secret Keys**.
3. Generate a new key and copy the `Access Key` and `Secret Key`.
4. Store these in the `loki-s3-credentials` Kubernetes secret.

### 🧹 Bucket Lifecycle Policy
While Loki and Tempo handle their own retention, it is a best practice to configure a **Bucket Lifecycle Policy** in the OCI Console as a secondary safety net to purge orphaned chunks after 14 days.

## 🚀 Port References
| Service | Internal Port | Purpose |
|---------|---------------|---------|
| **Loki Gateway** | 80 | External Ingestion & Internal Query |
| **Prometheus** | 80 / 9090 | Internal Query & Ingestion |
| **Tempo Query** | 3200 | Grafana Datasource |
| **Tempo OTLP (gRPC)** | 4317 | High-performance trace ingestion |
| **Tempo OTLP (HTTP)** | 4318 | Standard web trace ingestion |

## 🤖 "Who Monitors the Monitor?"
While this Hub monitors the Spokes, ArgoCD's own health is tracked via:
1. **K8s Internal Events**: Use `kubectl get events -n argocd`.
2. **Alertmanager**: Configured to alert if ArgoCD synchronization fails for more than 1 hour.

## 🔄 Updating the Stack
1. **Update Versions**: Modify the `targetRevision` or `image.tag` in `argocd/applications/*.yaml`.
2. **Commit & Push**: Git push to `main`.
3. **ArgoCD Sync**: ArgoCD will detect the change. Ensure **Server-Side Apply** is enabled to handle large manifest updates safely.

### ⚠️ Public repo / test environment note
This repository is public and (by design) can be connected to ArgoCD in “auto-sync from `main`” mode.
That’s great for a lab/test environment, but it means **any push** can cause reconciliation.
If you’re doing portfolio-only changes, prefer doc-only commits and validate after sync.

## 📈 Resource Usage (Metrics Server)
The cluster uses **metrics-server** (deployed via ArgoCD) to enable real-time resource visibility:
- `kubectl top nodes`
- `kubectl top pods -n monitoring`

**Notes**
- metrics-server is **stateless** and does **not** require a PVC.
- If it is missing, `kubectl top ...` will fail and the validation script will skip resource usage.

**Verify**
```bash
kubectl get application -n argocd metrics-server
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server
kubectl top nodes
```

## 💾 Live PVC usage (% full) in Grafana
The “Master Health Dashboard” includes a PVC usage panel. Live “% full” requires kubelet volume stats metrics:
- `kubelet_volume_stats_used_bytes`
- `kubelet_volume_stats_capacity_bytes`

In this repo those are enabled via `extraScrapeConfigs` in `helm/prometheus-values.yaml` (scraping kubelet via the API server proxy).
If the PVC panel shows `No data`, check whether these metrics exist in Prometheus Explore first.

## 🔑 Grafana Admin Password Reset
If you lose access to the Grafana UI, you can reset the admin password directly from the cluster:

```bash
# 1. Get the pod name first
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath="{.items[0].metadata.name}")

# 2. Reset the 'admin' user password (e.g., to 'admin123')
kubectl exec -n monitoring $POD_NAME -- grafana-cli admin reset-admin-password admin123
```

## 🧩 Grafana Rollouts (RWO PVC Pitfall)
Grafana uses a single **ReadWriteOnce** (RWO) PVC for `/var/lib/grafana`. If the Deployment allows creating a *new* pod while the *old* one is still running (e.g., RollingUpdate with `maxSurge > 0`), the rollout can deadlock because the PVC can only be mounted by one pod.

**Symptoms**
- ArgoCD shows `grafana` as **Degraded/Progressing**
- You see 2 Grafana pods, with one stuck in `Init:0/2` / `PodInitializing`
- `kubectl describe pod <pending>` shows init containers waiting with `/var/lib/grafana from storage (rw)`

**Fix (recommended)**
- Keep `type: RollingUpdate`, but set `maxSurge: 0` (and `maxUnavailable: 1`) so Kubernetes terminates the old pod *before* creating the new one (brief downtime during rollout, but no deadlock).

**One-time remediation**
If you’re already stuck mid-rollout, once `Recreate` is applied, the pending pod should be cleaned up and the new pod will mount the PVC cleanly.

