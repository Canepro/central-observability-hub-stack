# Multi-Cluster GitOps Handover

This document serves as the final operational map for the entire Multi-Cluster ecosystem. It consolidates the management of the OKE Hub, the AKS app cluster (`k8.canepro.me`), and the application stacks into a single source of truth.

## 🗺️ 1. Core Infrastructure Map

| Component | Cluster Type | Role | Environment |
|-----------|--------------|------|-------------|
| **OKE Hub** | Oracle Cloud (Managed) | The "Brain": Hosts ArgoCD & Central Observability | Always Free Tier |
| **AKS App Cluster** | Azure Kubernetes Service (Managed) | Hosts Rocket.Chat | Auto-shutdown on schedule |

## 🌐 2. Access Points & External URLs

| Service | URL | Purpose |
|---------|-----|---------|
| **ArgoCD UI** | https://argocd.canepro.me | Single Source of Truth & Deployment Control |
| **Grafana** | https://grafana.canepro.me | Centralized Logs (Loki) & Metrics (Prometheus) |
| **RocketChat** | https://k8.canepro.me | Rocket.Chat Front-End |
| **K8s API** | https://k8.canepro.me:6443 | Direct kubectl access to the AKS cluster (may be offline during auto-shutdown windows) |

Notes:
- `k8.canepro.me` is the current AKS Rocket.Chat cluster and may be offline weekdays 4pm-11pm due to auto-shutdown.
- The old cluster `k8-canepro-rocketchat` has been retired/deleted.

### 🔑 ArgoCD Initial Access
To retrieve the initial `admin` password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d ; echo
```

## 📂 3. GitOps Configuration (Sources of Truth)

| Repository | Branch | Path | Managed By |
|------------|--------|------|------------|
| `central-hub-stack` | `main` | `./argocd/` | Hub Infrastructure & Project Rules |
| `rocketchat-k8s` | `master` | `./` | Spoke Application Stack |

> Note: In this environment ArgoCD is configured to follow `main`. That’s intentional for a lab/test setup, but it means **any push to GitHub can trigger reconciliation**. Use tags as a safety net and validate after sync.

## 🛠️ 4. Maintenance & "Day 2" Operations

### 🔄 How to Perform an Upgrade
1. **Plan**: Identify whether the component is stateless or uses a PVC.
   - **Prometheus** is PVC-backed (snapshot/backup before risky upgrades).
   - **Grafana** is **E1/emptyDir** in this repo by default (no PVC). If you re-enable persistence later, treat it as PVC-backed and snapshot first.
2. **Modify**: Update the pinned chart version (`argocd/applications/*.yaml` → `targetRevision`) and/or image tag (`helm/*.yaml`).
3. **Commit**: Commit the change in Git.
4. **Push**: `git push origin main` (ArgoCD follows `main` in this environment).
5. **Sync/Verify**:
   - Check the app in ArgoCD UI (Healthy + Synced)
   - Validate pods/services: `./scripts/validate-deployment.sh`

### 🧰 Operational Commands (Hub)
- **Validate the stack**:
  ```bash
  chmod +x scripts/validate-deployment.sh
  ./scripts/validate-deployment.sh
  ```
- **Force ArgoCD refresh** (useful when adding a new `argocd/applications/*.yaml` app, or if ArgoCD shows cached manifest errors):
  ```bash
  kubectl -n argocd patch application oke-observability-stack --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
  ```
- **Resource usage** (requires `metrics-server`):
  ```bash
  kubectl top nodes
  kubectl top pods -n monitoring
  ```

### 🔐 Secrets Management (Hub)
- Grafana admin credentials and `secret_key` are stored in **OCI Vault** and synced into Kubernetes via **External Secrets Operator (ESO)**.
- Source manifests: `k8s/external-secrets/` (ClusterSecretStore + ExternalSecret).
- Grafana secret name: `grafana` (keys: `admin-user`, `admin-password`, `secret_key`).
- After rotating secrets in OCI Vault, ESO refreshes the Kubernetes secret automatically (default refresh: 1h).

### 🛡️ Automated Guardrails
- **OCI Storage Audit**: Use `./scripts/check-oci-storage.sh` to verify we are under the 200GB Always Free limit (currently at 194GB).
- **Self-Healing Storage**: A CronJob runs periodically to prune unused images and prevent disk pressure on the Spoke.
- **Retention**: Logs and Traces are kept for 7 days (168h) to stay within OKE free-tier storage limits.
- **Server-Side Apply (SSA)**: Enabled for all applications to handle large Kubernetes manifests automatically.

## 🔍 5. Troubleshooting Cheat Sheet

| Symptom | Primary Cause | First Action |
|---------|---------------|--------------|
| **App is "OutOfSync"** | Manual change on cluster or new Git push | Check Diff in ArgoCD UI, then click Sync. |
| **Pods stuck "Creating"** | Disk pressure or image pull / registry issues | `kubectl describe pod <pod> -n <ns>` and check Events for `DiskPressure`, `ImagePullBackOff`, or CNI/storage errors. On managed clusters (AKS/OKE), recycle/replace nodes if disk pressure persists. |
| **"Handshake Error" in logs** | Prometheus Agent protocol mismatch | Verify `scheme: https` in the agent config. |
| **DNS Resolution Failure** | Missing A-Record or restart delay | Check `nslookup k8.canepro.me` or update `/etc/hosts`. |

---
**Status**: ✅ Platform Fully Operational & Managed via GitOps
