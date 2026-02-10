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
| **Jenkins (Phase 1)** | Persistent | Block Volume | 50Gi (oci-bv) — uses freed E1 slot |

### The 200Gi Storage Calculation
OCI Always Free Tier provides 200GB of total storage. Our current usage:
- **Worker Node Boot Volumes**: 2 x 47GB = 94GB
- **Hub PVCs**: **100GB** (Prometheus 50Gi + Jenkins 50Gi after Phase 1; Grafana uses emptyDir per E1)
- **Total**: **194GB** (Buffer: 6GB)

*After E1, before Phase 1:* 1 x 50GB = 50GB (Prometheus only); total 144GB. The freed 50GB is used by Jenkins (Phase 1).

### OCI Block Volumes: minimum size and quota
OCI Block Volumes have a **minimum size of 50GB**. Even if we request 10GB in Helm, OCI provisions 50GB.

Because our Hub uses ~194GB (nodes + Prometheus + Jenkins when Phase 1 is enabled; Grafana is E1/emptyDir), we have effectively **exhausted our 200GB Always Free quota**.

Any new volume (e.g. Jenkins) will be a **paid resource** on our PAYG plan, costing approximately **$0.025 per GB** for the portion over 200GB.

### Phase 0 (E1) — After Grafana is on emptyDir: free the 50GB slot

Once Grafana is deployed with **persistence disabled** (E1), the **old Grafana PVC** (50Gi) may still exist and hold the 50GB. To free that slot for Jenkins on OKE:

1. Ensure the new Grafana pod (with emptyDir) is running and healthy.
2. Delete the old Grafana PVC: `kubectl -n monitoring delete pvc grafana` (or the exact PVC name from `kubectl -n monitoring get pvc`).
3. The 50GB Block Volume is released; total Block usage drops to ~144GB (Prometheus only). The freed 50GB is then available for a new Jenkins PVC on OKE (Phase 1).

### Grafana E1 — ArgoCD sync failures (volume / storage)

If ArgoCD sync fails with errors like **"volumeMounts[1].name: Not found: 'storage'"** or **"may not specify more than 1 volume type"**, the live Deployment may still reference the old PVC. The Helm chart with `persistence.enabled: false` is correct and renders a single `storage` volume as `emptyDir: {}`.

1. **Verify the manifest locally** (from repo root):
   ```bash
   helm repo add grafana https://grafana.github.io/helm-charts
   helm template grafana grafana/grafana --version 10.5.15 -f helm/grafana-values.yaml -n monitoring | grep -A 5 "name: storage"
   ```
   You should see `volumes` and `volumeMounts` with `name: storage` and `emptyDir: {}`.

2. **Sync with Replace** so the Deployment is recreated with the new spec: in ArgoCD UI, open the Grafana app → Sync → check **Replace** → Sync. (One-time; after that normal sync is fine.)

3. Once the new Grafana pod is Running, delete the old PVC if it is still `Terminating` or present: `kubectl -n monitoring delete pvc grafana`.

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
| **OTel Collector (gRPC/HTTP)** | 4317 / 4318 | Receives OTLP spans (e.g., from ingress-nginx) and forwards to Tempo |

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

**E1 (current):** Grafana uses **emptyDir** (`persistence.enabled: false`). There is no PVC; dashboards are provisioned from git. Skip PVC/PV and snapshot steps below. If you re-enable persistence later, use the full runbook.

**When persistence is enabled:** Grafana uses a 50Gi RWO PVC (`/var/lib/grafana`). Take a snapshot/backup before major upgrades.

#### 0) Pre-flight: identify the Grafana PVC + PV (skip when on E1 / emptyDir)

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

## 🔍 OOM diagnosis and remediation procedure

When **HubContainerOOMKilled** (or any container OOM) fires, follow this procedure before increasing the affected pod’s memory. Always check cluster headroom first so you don’t over-commit.

### 1. Identify the OOM’d workload

From the alert labels or manually:

```bash
kubectl -n argocd get pods
kubectl -n monitoring get pods
kubectl describe pod <pod-name> -n <namespace>
```

In the pod description, check **Last State: Terminated**, **Reason: OOMKilled**, and **Containers:** **Limits:** memory. Optionally check logs from the previous run:

```bash
kubectl logs <pod> -c <container> -n <namespace> --previous
```

### 2. Check node capacity and actual usage

See **hub-docs/CLUSTER-INFO.md** (section 6) for the snapshot and commands. Run:

```bash
kubectl get nodes -o wide
kubectl describe nodes | grep -A 5 "Allocated resources"
kubectl top nodes
```

Interpret:

- **Memory** is usually the constraint on small hubs (e.g. 2 × ~9.2 Gi allocatable). If both nodes are already at **>80% actual usage**, adding more limits without freeing elsewhere can cause more OOMs or node pressure.
- **CPU** limits are often overcommitted (200–300%); actual usage is what matters. Low actual CPU is fine.

### 3. Compare pod limits vs actual usage

List which workloads use a lot of memory vs their limits:

```bash
kubectl top pods -A --containers | head -60
kubectl get pods -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,MEM_REQ:.spec.containers[*].resources.requests.memory,MEM_LIM:.spec.containers[*].resources.limits.memory
```

Identify:

- **OOM’d pod**: needs more headroom (increase limit, or reduce load).
- **Others with high limit, low actual**: candidates to trim limits to free schedulable memory (e.g. Grafana 768Mi → 512Mi, Alertmanager 512Mi → 256Mi, Argo CD server 512Mi → 256Mi, nginx-ingress 512Mi → 256Mi).

### 4. Decide remediation

| Situation | Action |
|-----------|--------|
| Node memory &lt; ~80% and only one pod OOM’d | **Small bump**: increase the OOM’d container limit (e.g. 512Mi → 768Mi). Prefer 768Mi if headroom is tight. |
| Node memory already high (e.g. ≥80%) | **Trim first**: reduce limits on under-used workloads (in this repo: `helm/grafana-values.yaml`, `helm/prometheus-values.yaml` alertmanager, `helm/nginx-ingress-values.yaml`). Then increase the OOM’d workload (e.g. to 1Gi). |
| Argo CD application-controller OOM | Controller resources **are** defined in this repo via `terraform/argocd.tf` (`helm_release.argocd`, Helm values `controller.resources`). Increase `controller.resources.limits.memory` (e.g. `768Mi` or `1Gi`). |

### 5. Apply changes (GitOps)

- **This repo**: edit the relevant `helm/*-values.yaml`, commit, push. Argo CD will sync.
- **Argo CD install (this repo)**: change `controller.resources` (and/or `server.resources`) in `terraform/argocd.tf`, then run `terraform apply` so the Helm release updates.

After changes, re-check `kubectl top nodes` and that the previously OOM’d pod is stable. See **docs/TROUBLESHOOTING.md** (HubContainerOOMKilled) for alert details and verification queries.

## 💾 Live PVC usage (% full) in Grafana
The “Master Health Dashboard” includes a PVC usage panel. Live “% full” requires kubelet volume stats metrics:
- `kubelet_volume_stats_used_bytes`
- `kubelet_volume_stats_capacity_bytes`

In this repo those are enabled via `serverFiles.prometheus.yml.scrape_configs` in `helm/prometheus-values.yaml` (scraping kubelet via the API server proxy).
If the PVC panel shows `No data`, check whether these metrics exist in Prometheus Explore first.
Scrapes use the service account CA for TLS verification (no `insecure_skip_verify`).

## 🔐 Secrets Management (ESO + OCI Vault)
- External Secrets Operator (ESO) runs in `external-secrets` and syncs from OCI Vault.
- Grafana admin credentials and `secret_key` live in Vault and are synced to `monitoring/grafana`.
- Source manifests: `k8s/external-secrets/` (ClusterSecretStore + ExternalSecret).

## 🔑 Grafana Admin Password Reset
If you lose access to the Grafana UI, the preferred fix is to rotate the Vault secret (`admin_password`) so ESO refreshes the Kubernetes secret. If you must reset via CLI, update Vault afterward to avoid drift.

```bash
# 1. Get the pod name first
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath="{.items[0].metadata.name}")

# 2. Reset the 'admin' user password (e.g., to 'admin123')
kubectl exec -n monitoring $POD_NAME -- grafana-cli admin reset-admin-password admin123
```

## 🧩 Grafana Rollouts (E1 vs PVC)

**E1 (current default in this repo):** Grafana uses `emptyDir` (`persistence.enabled: false`). There is no PVC attach deadlock, but creating an extra Grafana pod during rollouts can still cause avoidable scheduling pressure on Always Free nodes.

**When persistence is enabled:** Grafana typically uses a single **ReadWriteOnce** (RWO) PVC for `/var/lib/grafana`. If the Deployment allows creating a *new* pod while the *old* one is still running (e.g., RollingUpdate with `maxSurge > 0`), the rollout can deadlock because the PVC can only be mounted by one pod.

**Symptoms**
- ArgoCD shows `grafana` as **Degraded/Progressing**
- You see 2 Grafana pods, with one stuck in `Init:0/2` / `PodInitializing`
- `kubectl describe pod <pending>` shows init containers waiting with `/var/lib/grafana from storage (rw)`

**Fix (recommended)**
- Keep `type: RollingUpdate`, but set `maxSurge: 0` (and `maxUnavailable: 1`) so Kubernetes terminates the old pod *before* creating the new one.
  - This is what this repo uses in `helm/grafana-values.yaml`.
