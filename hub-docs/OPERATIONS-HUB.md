# Hub Admin & Operations Guide

This guide focuses on the specific maintenance and operational requirements of the OKE Hub stack.

## 🛡️ Retention Policies (Always Free Tier Optimization)
To stay within the 200Gi Block Volume limit and manage Object Storage costs, the following retention policies are enforced:

| Component | Policy | Target |
|-----------|--------|--------|
| **Loki** | 168h (7 days) | Object Storage |
| **Tempo** | 168h (7 days) | Object Storage |
| **Prometheus** | 15 days | Block Volume |
| **Grafana** | Indefinite | Block Volume |

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

## 🔑 Grafana Admin Password Reset
If you lose access to the Grafana UI, you can reset the admin password directly from the cluster:

```bash
# 1. Get the pod name first
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath="{.items[0].metadata.name}")

# 2. Reset the 'admin' user password (e.g., to 'admin123')
kubectl exec -n monitoring $POD_NAME -- grafana-cli admin reset-admin-password admin123
```

## 🧩 Grafana Rollouts (RWO PVC + RollingUpdate Pitfall)
Grafana uses a single **ReadWriteOnce** (RWO) PVC for `/var/lib/grafana`. If the Deployment uses the default **RollingUpdate** strategy, Kubernetes may try to start a *new* Grafana pod while the *old* one is still running, which can block the PVC attach/mount.

**Symptoms**
- ArgoCD shows `grafana` as **Degraded/Progressing**
- You see 2 Grafana pods, with one stuck in `Init:0/2` / `PodInitializing`
- `kubectl describe pod <pending>` shows init containers waiting with `/var/lib/grafana from storage (rw)`

**Fix (recommended)**
- Use `deploymentStrategy: Recreate` for Grafana so Kubernetes terminates the old pod *before* starting the new one (brief downtime during rollout, but no deadlock).

**One-time remediation**
If you’re already stuck mid-rollout, once `Recreate` is applied, the pending pod should be cleaned up and the new pod will mount the PVC cleanly.

