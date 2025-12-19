# OKE Observability Hub

A centralized, production-ready observability platform deployed on Oracle Kubernetes Engine (OKE), designed to aggregate telemetry data (metrics, logs, traces) across multi-cluster and multi-cloud environments.

## 🎯 Overview
This stack serves as the **Central Brain** for your infrastructure. It is optimized for the **OCI Always Free Tier**, providing a high-performance "Single Pane of Glass" visualization layer with zero licensing costs.

- **Centralized Logs**: Loki (S3-backed)
- **Centralized Metrics**: Prometheus (Remote Write Receiver)
- **Centralized Traces**: Tempo (S3-backed)
- **Unified Visualization**: Grafana
- **GitOps Management**: ArgoCD (App-of-Apps)

## 🗺️ Documentation Roadmap

| Document | Purpose |
|----------|---------|
| **[hub-docs/README.md](hub-docs/README.md)** | **The Hub Map**: Component versions, roles, and architecture overview. |
| **[GITOPS-HANDOVER.md](GITOPS-HANDOVER.md)** | **Key to the Kingdom**: Operational guide for managing Hub and Spokes. |
| **[hub-docs/OPERATIONS-HUB.md](hub-docs/OPERATIONS-HUB.md)** | **Admin Guide**: Retention policies, OCI storage, and maintenance. |
| **[hub-docs/ARCHITECTURE.md](hub-docs/ARCHITECTURE.md)** | **System Design**: Deep dive into components and storage hybrid model. |
| **[hub-docs/ARGOCD-RUNBOOK.md](hub-docs/ARGOCD-RUNBOOK.md)** | **ArgoCD Ops**: Syncing, patching, and managing Hub apps. |
| **[docs/QUICKSTART.md](docs/QUICKSTART.md)** | **5-Minute Guide**: Accessing Grafana and importing dashboards. |
| **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)** | **Integration Guide**: Connecting external clusters and applications. |
| **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** | **Solutions**: Common issues and fixes. |

## 🏗️ Infrastructure at a Glance

- **Region**: Oracle Cloud (Ashburn)
- **Compute**: 2x ARM64 Worker Nodes (Always Free)
- **Storage**: Hybrid Model (50GB Block Volumes + Infinite S3 Object Storage)
- **Ingress**: NGINX Ingress Controller with Let's Encrypt SSL/TLS
- **Domains**:
  - `grafana.canepro.me` (Visualization)
  - `observability.canepro.me` (Secure Data Ingestion)
  - `argocd.canepro.me` (GitOps Control Plane)

## 🚀 Management (GitOps First)
This entire stack is managed declaratively via ArgoCD.

### How to apply changes:
1. **Modify**: Edit the values in `helm/` or application manifests in `argocd/applications/`.
2. **Commit & Push**: Push changes to the `main` branch.
3. **Sync**: ArgoCD automatically detects and applies changes using **Server-Side Apply**.

### Initial Access:
Retrieve the Grafana admin password from your cluster:
```bash
kubectl get secret grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d ; echo
```

**Forgot Password?** Reset it via CLI:
```bash
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n monitoring $POD_NAME -- grafana-cli admin reset-admin-password admin123
```

## 🤖 Automation & CI/CD
This repository includes a **DevOps Quality Gate** via GitHub Actions (`.github/workflows/devops-quality-gate.yml`):
- **YAML Linting**: Ensures all manifests follow standard formatting.
- **Security Scanning**: Uses `kube-linter` to check for K8s security best practices.
- **OCI Storage Audit**: Runs weekly to ensure the "Always Free" 200GB limit is not exceeded.
- **ArgoCD Validation**: Validates application manifests before they reach the cluster.

## 📁 Directory Structure
```text
├── argocd/               # ArgoCD Application manifests (The Control Plane)
├── hub-docs/             # Central Hub specific documentation
├── docs/                 # General integration and troubleshooting guides
├── helm/                 # Component-specific Helm values
├── k8s/                  # Raw Kubernetes manifests (Ingress, SSL, etc.)
├── scripts/              # Useful maintenance scripts
└── GITOPS-HANDOVER.md    # Multi-cluster operational roadmap
```

---
**Status**: ✅ Platform Fully Operational & Managed via GitOps
