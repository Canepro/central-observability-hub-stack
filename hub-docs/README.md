# OKE Observability Hub

Central observability hub providing storage, analysis, and visualization for multi-cluster telemetry.

## Role

The OKE Hub serves as the centralized monitoring platform, ingesting metrics, logs, and traces from spoke clusters and external applications.

### Capabilities

- **Unified Dashboard**: Multi-cluster health visualization with cluster-based filtering
- **Centralized Storage**: Long-term telemetry persistence using OCI Object Storage
- **Single Pane of Glass**: One Grafana instance for querying all environments
- **GitOps Management**: Declarative configuration via ArgoCD

### Cluster Labels

All metrics include a `cluster` label for filtering:
- Hub: `cluster="oke-hub"`
- Spokes: `cluster="aks-canepro"`, etc.

## Stack Components

Optimized for OCI Always Free Tier:

| Component | Version | Role | Storage |
|-----------|---------|------|---------|
| Grafana | 12.3.0 | Visualization | Block Volume (50Gi) |
| Prometheus | 25.8.0 | Metrics & Alerting | Block Volume (50Gi) |
| Loki | 3.5.7 | Log Aggregation | Object Storage (S3) |
| Tempo | 1.24.0 | Distributed Tracing | Object Storage (S3) |

## ArgoCD Configuration

The stack uses the App-of-Apps pattern. The bootstrap manifest (`argocd/bootstrap-oke.yaml`) references individual application manifests in `argocd/applications/`.

### Settings

- **Server-Side Apply**: Enabled for large CRDs and manifests
- **Self-Healing**: Automated pruning and drift correction

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - System design and storage architecture
- [CLUSTER-INFO.md](CLUSTER-INFO.md) - OKE cluster details and access commands
- [OPERATIONS-HUB.md](OPERATIONS-HUB.md) - Retention policies and maintenance
- [ARGOCD-RUNBOOK.md](ARGOCD-RUNBOOK.md) - ArgoCD operations and troubleshooting
- [INGRESS-SETUP.md](INGRESS-SETUP.md) - NGINX Ingress and SSL/TLS configuration
- [SECURITY-RECOMMENDATIONS.md](SECURITY-RECOMMENDATIONS.md) - Security best practices
- [DIAGRAM.md](DIAGRAM.md) - Data flow visualization
- [../GITOPS-HANDOVER.md](../GITOPS-HANDOVER.md) - Multi-cluster operational handover
- [../docs/MULTI-CLUSTER-SETUP-COMPLETE.md](../docs/MULTI-CLUSTER-SETUP-COMPLETE.md) - Hub-and-spoke setup guide

