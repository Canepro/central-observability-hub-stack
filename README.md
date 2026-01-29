# OKE Observability Hub

A centralized observability platform deployed on Oracle Kubernetes Engine (OKE), designed to aggregate metrics, logs, and traces across multi-cluster environments. Optimized for the OCI Always Free Tier.

## Overview

This repository serves as the GitOps source of truth for a production-ready observability stack:

| Component | Purpose | Storage |
|-----------|---------|---------|
| **Grafana** | Unified visualization and dashboards | Block Volume (50Gi) |
| **Prometheus** | Metrics collection and alerting | Block Volume (50Gi) |
| **Loki** | Log aggregation | OCI Object Storage (S3) |
| **Tempo** | Distributed tracing | OCI Object Storage (S3) |
| **ArgoCD** | GitOps continuous delivery | - |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        OKE Hub Cluster                          │
│  ┌─────────┐  ┌────────────┐  ┌──────┐  ┌───────┐  ┌─────────┐ │
│  │ Grafana │  │ Prometheus │  │ Loki │  │ Tempo │  │ ArgoCD  │ │
│  └─────────┘  └────────────┘  └──────┘  └───────┘  └─────────┘ │
└─────────────────────────────────────────────────────────────────┘
        ▲               ▲              ▲           ▲
        │               │              │           │
   ┌────┴────┐    ┌─────┴─────┐   ┌────┴────┐  ┌───┴───┐
   │ Spoke 1 │    │  Spoke 2  │   │ Spoke N │  │ Agents│
   │  (AKS)  │    │   (K3s)   │   │   ...   │  │       │
   └─────────┘    └───────────┘   └─────────┘  └───────┘
```

### Endpoints

| Service | URL |
|---------|-----|
| Grafana | https://grafana.canepro.me |
| ArgoCD | https://argocd.canepro.me |
| Data Ingestion | https://observability.canepro.me |

## Quick Start

### Access Grafana

```bash
# Retrieve admin password
kubectl get secret grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

### Validate Deployment

```bash
./scripts/validate-deployment.sh
```

## Repository Structure

```
├── argocd/              # ArgoCD application manifests
│   ├── applications/    # Individual component definitions
│   └── bootstrap-oke.yaml
├── helm/                # Helm values for each component
├── k8s/                 # Raw Kubernetes manifests
├── terraform/           # OKE infrastructure as code
├── scripts/             # Operational scripts
├── docs/                # Integration and troubleshooting guides
└── hub-docs/            # Hub-specific documentation
```

## GitOps Workflow

This stack is managed declaratively via ArgoCD. All changes flow through Git:

1. **Modify** - Edit manifests in `argocd/applications/` or values in `helm/`
2. **Commit** - Push changes to `main` branch
3. **Sync** - ArgoCD automatically detects and applies changes

### Important Notes

- ArgoCD watches the `main` branch - every push triggers reconciliation
- For PVC-backed components (Grafana, Prometheus), take snapshots before upgrades
- Run `./scripts/validate-deployment.sh` after changes to verify health

## Documentation

| Document | Description |
|----------|-------------|
| [hub-docs/README.md](hub-docs/README.md) | Component versions and architecture overview |
| [hub-docs/OPERATIONS-HUB.md](hub-docs/OPERATIONS-HUB.md) | Retention policies, storage management |
| [hub-docs/ARGOCD-RUNBOOK.md](hub-docs/ARGOCD-RUNBOOK.md) | ArgoCD operations and troubleshooting |
| [docs/QUICKSTART.md](docs/QUICKSTART.md) | Getting started guide |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Integration guide for external clusters |
| [docs/MULTI-CLUSTER-SETUP-COMPLETE.md](docs/MULTI-CLUSTER-SETUP-COMPLETE.md) | Hub-and-spoke setup guide |
| [GITOPS-HANDOVER.md](GITOPS-HANDOVER.md) | Operational handover document |
| [VERSION-TRACKING.md](VERSION-TRACKING.md) | Software version tracking |

## CI/CD

### GitHub Actions

The repository includes automated quality gates (`.github/workflows/devops-quality-gate.yml`):
- YAML linting
- Kubernetes manifest security scanning (kube-linter)
- ArgoCD application validation

### Jenkins

Jenkins pipelines for infrastructure validation (`.jenkins/`):
- Terraform format, validate, and (when OCI parameters are set) plan
- Kubernetes manifest validation
- Security scanning

PR and branch builds run Terraform format and validate only unless OCI job parameters are configured. See [.jenkins/README.md](.jenkins/README.md) for OCI credentials and parameters.

## Infrastructure

| Resource | Specification |
|----------|---------------|
| Cluster | OKE Basic (Always Free) |
| Region | us-ashburn-1 |
| Nodes | 2x VM.Standard.A1.Flex (ARM64) |
| Compute | 2 OCPU / 12GB RAM per node |
| Storage | Block Volumes + Object Storage |

## License

This project is maintained for educational and portfolio purposes.
