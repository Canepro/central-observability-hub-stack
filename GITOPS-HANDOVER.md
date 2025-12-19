# Multi-Cluster GitOps Handover

This document serves as the final operational map for the entire Multi-Cluster ecosystem. It consolidates the management of the OKE Hub, the K3s Spoke, and the application stacks into a single source of truth.

## 🗺️ 1. Core Infrastructure Map

| Component | Cluster Type | Role | Environment |
|-----------|--------------|------|-------------|
| **OKE Hub** | Oracle Cloud (Managed) | The "Brain": Hosts ArgoCD & Central Observability | Always Free Tier |
| **K3s Spoke** | Ubuntu VM (Self-managed) | The "Muscle": Hosts RocketChat microservices | Lab / Production |

## 🌐 2. Access Points & External URLs

| Service | URL | Purpose |
|---------|-----|---------|
| **ArgoCD UI** | https://argocd.canepro.me | Single Source of Truth & Deployment Control |
| **Grafana** | https://grafana.canepro.me | Centralized Logs (Loki) & Metrics (Prometheus) |
| **RocketChat** | https://k8.canepro.me | The Main Application Front-End |
| **K8s API** | https://k8.canepro.me:6443 | Direct kubectl access to the Spoke cluster |

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

## 🛠️ 4. Maintenance & "Day 2" Operations

### 🔄 How to Perform an Upgrade
1. **Modify**: Open the relevant YAML in the manifests/ folder of the Git repo.
2. **Commit**: Update the image tag or version (e.g., from `7.12.2` to `7.13.0`).
3. **Push**: `git push origin master`.
4. **Verify**: Watch the Rolling Update in the ArgoCD UI.

### 🛡️ Automated Guardrails
- **Self-Healing Storage**: A CronJob runs periodically to prune unused images and prevent disk pressure on the Spoke.
- **Retention**: Logs and Traces are kept for 7 days (168h) to stay within OKE free-tier storage limits.
- **Server-Side Apply (SSA)**: Enabled for all applications to handle large Kubernetes manifests automatically.

## 🔍 5. Troubleshooting Cheat Sheet

| Symptom | Primary Cause | First Action |
|---------|---------------|--------------|
| **App is "OutOfSync"** | Manual change on cluster or new Git push | Check Diff in ArgoCD UI, then click Sync. |
| **Pods stuck "Creating"** | Potential Disk Pressure (>85%) | Run `sudo k3s crictl rmi --prune` on the Spoke node. |
| **"Handshake Error" in logs** | Prometheus Agent protocol mismatch | Verify `scheme: https` in the agent config. |
| **DNS Resolution Failure** | Missing A-Record or restart delay | Check `nslookup k8.canepro.me` or update `/etc/hosts`. |

---
**Status**: ✅ Platform Fully Operational & Managed via GitOps

