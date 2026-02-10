# OKE Observability Hub

A centralized observability platform deployed on Oracle Kubernetes Engine (OKE), designed to aggregate metrics, logs, and traces across multi-cluster environments. Optimized for the OCI Always Free Tier.

## Overview

This repository is the GitOps source of truth for a production-ready observability stack:

| Component | Purpose | Storage |
|-----------|---------|---------|
| **Grafana** | Unified visualization and dashboards | Ephemeral (emptyDir); dashboards provisioned from git |
| **Prometheus** | Metrics collection and alerting | Block Volume (50Gi) |
| **Loki** | Log aggregation | OCI Object Storage (S3) |
| **Tempo** | Distributed tracing | OCI Object Storage (S3) |
| **OpenTelemetry Collector** | Receives OTLP traces and forwards to Tempo | Ephemeral (deployment) |
| **NGINX Ingress** | Single LoadBalancer + HTTPS routing | OCI NLB (Always Free tier limits apply) |
| **ArgoCD** | GitOps continuous delivery | - |

## Architecture

```mermaid
flowchart LR
  subgraph Spokes[Spoke Clusters]
    S1[AKS Spoke (k8.canepro.me)] -->|remote_write| P
    S2[Dev Spoke (kind)] -->|remote_write| P
    SN[Other Spokes] -->|remote_write| P
    S1 -->|logs| L
    S2 -->|logs| L
    SN -->|logs| L
    S1 -->|traces| T
    S2 -->|traces| T
    SN -->|traces| T
  end

  subgraph Hub[OKE Hub Cluster]
    A[ArgoCD] -->|GitOps sync| G[Grafana]
    A -->|GitOps sync| P[Prometheus]
    A -->|GitOps sync| L[Loki]
    A -->|GitOps sync| T[Tempo]
    A -->|GitOps sync| O[OTel Collector]
    A -->|GitOps sync| I[ingress-nginx]
    G -->|queries| P
    G -->|queries| L
    G -->|queries| T
    I -->|OTLP spans| O
    O -->|OTLP spans| T
  end

  Git[(Git repo)] -->|manifests/values| A
```

### Endpoints

| Service | URL |
|---------|-----|
| Grafana | https://grafana.canepro.me |
| ArgoCD | https://argocd.canepro.me |
| Jenkins | https://jenkins.canepro.me |
| Data Ingestion | https://observability.canepro.me |

## Quick Start

See [docs/QUICKSTART.md](docs/QUICKSTART.md) for a fast, end-to-end checklist.

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
- Grafana admin credentials and `secret_key` are sourced from OCI Vault via External Secrets Operator (`k8s/external-secrets/`)
- Run `./scripts/validate-deployment.sh` after changes to verify health

## Documentation

| Document | Description |
|----------|-------------|
| [hub-docs/README.md](hub-docs/README.md) | Component versions and architecture overview |
| [hub-docs/OPERATIONS-HUB.md](hub-docs/OPERATIONS-HUB.md) | Retention policies, storage management |
| [hub-docs/ARGOCD-RUNBOOK.md](hub-docs/ARGOCD-RUNBOOK.md) | ArgoCD operations and troubleshooting |
| [docs/JENKINS-MIGRATION-SUMMARY.md](docs/JENKINS-MIGRATION-SUMMARY.md) | Jenkins migration to OKE and split-agent summary |
| [docs/JENKINS-503-TROUBLESHOOTING.md](docs/JENKINS-503-TROUBLESHOOTING.md) | Jenkins (OKE) operational troubleshooting |
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

**Troubleshooting CI Failures:**
If workflows fail with "no steps executed" or jobs sit in queue for extended periods:
1. Check [GitHub Status](https://www.githubstatus.com/) for Actions outages
2. Verify runner availability issues are not widespread
3. Re-run failed workflows once service is restored

All jobs have timeout limits (5-15 minutes) to fail fast when runners are unavailable.

### Jenkins

Jenkins runs on OKE at **https://jenkins.canepro.me** (split-agent hybrid: controller on OKE, optional static agent on AKS). Pipelines in `.jenkins/` provide:
- Terraform format, validate, and (when OCI parameters are set) plan
- Kubernetes manifest validation
- Security scanning and version checking

PR and branch builds run format/validate only unless OCI job parameters are configured. See [.jenkins/README.md](.jenkins/README.md) for OCI credentials and [docs/JENKINS-MIGRATION-SUMMARY.md](docs/JENKINS-MIGRATION-SUMMARY.md) for migration and troubleshooting.

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
