# Hub Admin & Operations Guide

This guide focuses on the specific maintenance and operational requirements of the OKE Hub stack.

## 🛡️ Retention Policies (Always Free Tier Optimization)
To stay within the **200Gi Total Storage limit** (Boot Volumes + Block Volumes) and manage Object Storage costs, the following retention policies are enforced:

| Component | Policy | Storage Type | Size |
|-----------|--------|--------------|------|
| **Loki** | 168h (7 days) | Object Storage | N/A |
| **Tempo** | 168h (7 days) | Object Storage | N/A |
| **Prometheus** | 15 days | Block Volume | 50Gi |
| **Grafana** | Ephemeral (E1) | emptyDir | N/A — dashboards provisioned from git |
| **Alertmanager** | Ephemeral | emptyDir | N/A |

### The 200Gi Storage Calculation
OCI Always Free Tier provides 200GB of total storage. Our current usage (after **E1 — Grafana on emptyDir**):
- **Worker Node Boot Volumes**: 2 x 47GB = 94GB
- **Observability Hub PVCs**: 1 x 50GB = **50GB** (Prometheus only; Grafana uses emptyDir per E1)
- **Total**: **144GB** (Buffer: 56GB — freed 50GB slot reserved for Jenkins on OKE)

*Before E1:* 2 x 50GB = 100GB (Prometheus + Grafana); total 194GB.

### OCI Block Volumes: minimum size and quota
OCI Block Volumes have a **minimum size of 50GB**. Even if we request 10GB in Helm, OCI provisions 50GB.

Because our Hub uses 194GB (nodes + Prometheus + Grafana), we have **exhausted our 200GB Always Free quota**.

Any new volume (e.g. Jenkins) will be a **paid resource** on our PAYG plan, costing approximately **$0.025 per GB** for the portion over 200GB.

### Phase 0 (E1) — After Grafana is on emptyDir: free the 50GB slot

Once Grafana is deployed with **persistence disabled** (E1), the **old Grafana PVC** (50Gi) may still exist and hold the 50GB. To free that slot for Jenkins on OKE:

1. Ensure the new Grafana pod (with emptyDir) is running and healthy.
2. Delete the old Grafana PVC: `kubectl -n monitoring delete pvc grafana` (or the exact PVC name from `kubectl -n monitoring get pvc`).
3. The 50GB Block Volume is released; total Block usage drops to ~144GB (Prometheus only). The freed 50GB is then available for a new Jenkins PVC on OKE (Phase 1).

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

### ✅ Grafana upgrade runbook (Helm chart + Grafana OSS)
Grafana is deployed by ArgoCD as a Helm chart:
- Chart pin: `argocd/applications/grafana.yaml` → `spec.sources[0].targetRevision`
- Grafana image pin: `helm/grafana-values.yaml` → `image.tag`

Because Grafana uses a **50Gi RWO PVC** (`/var/lib/grafana`), always take a snapshot/backup before major upgrades.

#### 0) Pre-flight: identify the Grafana PVC + PV

```bash
kubectl -n monitoring get pvc grafana
kubectl -n monitoring get pv | grep -i grafana
kubectl -n monitoring describe pv <pv-name>
```

From the PV output, capture the **OCI Block Volume OCID** (`ocid1.volume...`).

#### 1) Snapshot (OCI Block Volume “snapshot” = volume backup)
Create a **FULL** manual backup:

```bash
oci bv backup create \
  --volume-id <VOLUME_OCID> \
  --type FULL \
  --display-name grafana-pre-upgrade-$(date +%F)
```

Wait until it is `AVAILABLE`:

```bash
oci bv backup get --backup-id <VOLUME_BACKUP_OCID> \
  --query "data.{name:\"display-name\",state:\"lifecycle-state\",time:\"time-created\"}" \
  --output table
```

#### 2) Update Git pins (chart + image)
Edit:
- `argocd/applications/grafana.yaml` → bump `targetRevision` (chart version)
- `helm/grafana-values.yaml` → bump `image.tag` (Grafana OSS version)

Commit + push:

```bash
git add argocd/applications/grafana.yaml helm/grafana-values.yaml
git commit -m "Upgrade Grafana: chart <chart>, image <grafana>"
git push origin main
```

#### 3) Sync + watch rollout
Force Argo to refresh, then let Auto-Sync apply (or click Sync in UI):

```bash
kubectl -n argocd annotate application grafana argocd.argoproj.io/refresh=hard --overwrite
```

Watch rollout:

```bash
kubectl -n monitoring rollout status deploy/grafana --timeout=10m
kubectl -n monitoring get pods -l app.kubernetes.io/name=grafana -o wide
kubectl -n monitoring logs deploy/grafana --tail=200
```

Verify version via ingress:

```bash
curl -s https://grafana.canepro.me/api/health
```

#### 4) Rollback options
**Fast rollback (GitOps revert)**:

```bash
git revert HEAD
git push origin main
kubectl -n argocd annotate application grafana argocd.argoproj.io/refresh=hard --overwrite
```

**Data rollback (restore from OCI backup)**:
Use the OCI Console to restore the backup into a new volume, then re-attach by recreating the PV/PVC binding (cluster-specific). Only needed if the Grafana DB itself is corrupted.

#### 5) ArgoCD “OutOfSync” noise after upgrades (safe suppression)
Some resources (commonly the `Secret/monitoring/grafana`) can pick up controller-managed metadata (e.g., `app.kubernetes.io/managed-by: Helm`) that causes ArgoCD to report OutOfSync even when the app is Healthy.

If this happens, prefer a **narrow** ArgoCD `ignoreDifferences` rule that ignores only that metadata label on that one resource (do **not** ignore `data` / `stringData`).

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

