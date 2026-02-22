# OKE Observability Hub

Central observability hub for storage, analysis, and visualization of multi-cluster telemetry.

## Role

The OKE Hub serves as the centralized monitoring platform, ingesting metrics, logs, and traces from spoke clusters and external applications.

### Capabilities

- **Unified Dashboard**: Multi-cluster health visualization with cluster-based filtering
- **Centralized Storage**: Telemetry persistence using OCI Object Storage
- **Single Pane of Glass**: One Grafana instance for querying all environments
- **GitOps Management**: Declarative configuration via ArgoCD

### Cluster Labels

All metrics include a `cluster` label for filtering:
- Hub: `cluster="oke-hub"`
- Spokes: `cluster="aks-canepro"`, etc.

## Stack Components

Optimized for OCI Always Free Tier.  
Current versions are tracked in [VERSION-TRACKING.md](../VERSION-TRACKING.md).

## ArgoCD Configuration

The stack uses the App-of-Apps pattern. The bootstrap manifest (`argocd/bootstrap-oke.yaml`) references individual application manifests in `argocd/applications/`.

### Settings

- **Server-Side Apply**: Enabled for large CRDs and manifests
- **Self-Healing**: Automated pruning and drift correction

## Secrets Management

- **External Secrets Operator (ESO)** runs in `external-secrets` and syncs secrets from **OCI Vault**.
- Grafana admin credentials and `secret_key` are stored in Vault and materialized as `monitoring/grafana`.
- ESO config manifests live in `k8s/external-secrets/`.
- ESO CRDs are installed out-of-band via server-side apply; Helm values set `installCRDs: false`.

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - System design and storage architecture
- [CLUSTER-INFO.md](CLUSTER-INFO.md) - OKE cluster details and access commands
- [OPERATIONS-HUB.md](OPERATIONS-HUB.md) - Retention policies and maintenance
- [TRACING-ROLLOUT-CHECKLIST.md](TRACING-ROLLOUT-CHECKLIST.md) - Phased tracing rollout gates for useful service graphs and drilldown
- [TRACING-SERVICE-ONBOARDING-TEMPLATE.md](TRACING-SERVICE-ONBOARDING-TEMPLATE.md) - Copy/paste checklist for onboarding one service to tracing
- [TRACING-ONBOARDING-argocd-server.md](TRACING-ONBOARDING-argocd-server.md) - Pre-filled onboarding example for `argocd-server`
- [ARGOCD-RUNBOOK.md](ARGOCD-RUNBOOK.md) - ArgoCD operations and troubleshooting
- [INGRESS-SETUP.md](INGRESS-SETUP.md) - NGINX Ingress and SSL/TLS configuration
- [SECURITY-RECOMMENDATIONS.md](SECURITY-RECOMMENDATIONS.md) - Security best practices
- [DIAGRAM.md](DIAGRAM.md) - Data flow visualization
- [../GITOPS-HANDOVER.md](../GITOPS-HANDOVER.md) - Multi-cluster operational handover
- [../docs/MULTI-CLUSTER-SETUP-COMPLETE.md](../docs/MULTI-CLUSTER-SETUP-COMPLETE.md) - Hub-and-spoke setup guide
