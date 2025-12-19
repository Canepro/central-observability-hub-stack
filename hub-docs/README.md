# OKE Observability Hub - The Map

Welcome to the Central Observability Hub. This cluster serves as the "Brain" of the ecosystem, providing centralized storage, analysis, and visualization for all multi-cluster telemetry.

## 🎯 Role of the OKE Hub
The OKE Hub is designed to be a high-performance, cost-effective "Single Pane of Glass" for the entire infrastructure. It ingests metrics, logs, and traces from various spoke clusters (like K3s) and external applications.

### Key Responsibilities:
- **Master Health Dashboard**: A single "Single Pane of Glass" dashboard for Hub and Spoke health.
- **Centralized Storage**: Long-term persistence of telemetry data using OCI Object Storage.
- **Unified Visualization**: A single Grafana instance for querying data across all environments.
- **Declarative Management**: The entire stack is managed via GitOps (ArgoCD), ensuring consistency and easy recovery.

## 🛠️ The Backend Stack (Always Free Tier)
This stack is optimized to run within the Oracle Cloud "Always Free" tier constraints while maintaining production-grade capabilities.

| Component | Version | Role | Storage Type |
|-----------|---------|------|--------------|
| **Grafana** | 11.1.0 | Visualization & Dashboards | OCI Block Volume (50Gi) |
| **Loki** | 3.5.7 | Log Aggregation | OCI Object Storage (S3 API) |
| **Prometheus** | 25.8.0 | Metrics & Alerting | OCI Block Volume (50Gi) |
| **Tempo** | 1.24.0 | Distributed Tracing | OCI Object Storage (S3 API) |

## 🚀 ArgoCD Management
The OKE Hub manages its own observability stack using the "App-of-Apps" pattern. The bootstrap manifest `argocd/bootstrap-oke.yaml` points to the `argocd/applications/` directory, which contains individual Application manifests for each component.

### Key ArgoCD Settings:
- **Server-Side Apply (SSA)**: Enabled for all applications to handle large CRDs and objects that exceed standard annotation limits.
- **Self-Healing**: Automated pruning and self-healing are enabled to maintain the desired state defined in Git.

## 📚 Related Documentation
- [DIAGRAM.md](DIAGRAM.md) - Data Flow and Architecture Visualization
- [ARCHITECTURE.md](ARCHITECTURE.md) - Deep Dive into System Design and Storage
- [OPERATIONS-HUB.md](OPERATIONS-HUB.md) - Admin Guide for Retention, Storage, and Maintenance
- [ARGOCD-RUNBOOK.md](ARGOCD-RUNBOOK.md) - ArgoCD Operations and Troubleshooting for this Repo
- [INGRESS-SETUP.md](INGRESS-SETUP.md) - NGINX Ingress and SSL/TLS Configuration
- [SECURITY-RECOMMENDATIONS.md](SECURITY-RECOMMENDATIONS.md) - Best Practices for Secure Ingestion
- [GITOPS-HANDOVER.md](../GITOPS-HANDOVER.md) - Multi-Cluster Operational Map

