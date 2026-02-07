# Grafana Observability Stack - Architecture

Comprehensive architecture documentation for the centralized observability hub on OKE.

## System Overview

This observability stack serves as a **centralized monitoring hub** that aggregates metrics, logs, and traces from multiple Rocket.Chat deployments and other applications across different environments (OKE, Azure, AWS, etc.).

```text
┌─────────────────────────────────────────────────────────────────┐
│                     External Applications                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Rocket.Chat  │  │ Rocket.Chat  │  │    Other     │          │
│  │   (OKE)      │  │  (Azure)     │  │    Apps      │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                  │                  │                  │
│         │ HTTPS (Basic Auth)                  │                  │
│         │ Metrics/Logs/Traces                 │                  │
│         │ (Ingress)                           │                  │
└─────────┼──────────────────┼──────────────────┼──────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│              OKE Observability Cluster (Ashburn)                │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  NGINX Ingress Controller                │  │
│  │             (SSL Termination + Basic Auth)               │  │
│  └────────┬──────────────────────────────┬──────────────────┘  │
│           │                              │                     │
│           ▼                              ▼                     │
│  ┌──────────────────┐           ┌─────────────────┐            │
│  │     Grafana      │           │ Data Ingestion  │            │
│  │ (Visualization)  │           │ (Secure Routes) │            │
│  └────────┬─────────┘           └────────┬────────┘            │
│           │                              │                     │
│           ▼                              ▼                     │
│  ┌───────────┐ ┌─────────┐ ┌────────┐    │                     │
│  │Prometheus │ │  Loki   │ │ Tempo  │◄───┘                     │
│  │ (Metrics) │ │ (Logs)  │ │(Traces)│                          │
│  └─────┬─────┘ └────┬────┘ └───┬────┘                          │
│        │            │           │                                │
│        │            │           │                                │
│  ┌─────▼────────────▼───────────▼────────┐                     │
│  │     Persistent Storage (Hybrid)        │                     │
│  │  Prometheus: 50Gi PVC                  │                     │
│  │  Loki: OCI Object Storage (S3)         │                     │
│  │  Tempo: OCI Object Storage (S3)        │                     │
│  └────────────────────────────────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Grafana (Visualization Layer)

**Role**: Central visualization hub and unified interface for all observability data.

**Configuration**:

- **Deployment**: 1 replica
- **Storage (E1 default in this repo)**: Ephemeral `emptyDir` (dashboards provisioned from git on startup)
- **Access**: `https://grafana.canepro.me`

### 2. Prometheus (Metrics Layer)

**Role**: Time-series database for metrics collection, storage, and alerting.

**Configuration**:

- **Deployment**: Standalone (Community Chart)
- **Storage**: 50 GiB PVC (OCI Block Volume)
- **Retention**: 15 days
- **Ingestion**: Remote Write Receiver Enabled
- **Access**: `https://observability.canepro.me/api/v1/write` (Basic Auth)

### 3. Loki (Logs Layer)

**Role**: Log aggregation system optimized for Kubernetes workloads.

**Configuration**:

- **Deployment**: Single Binary
- **Storage**: **OCI Object Storage (S3 Compatible)**
  - Bucket: `loki-data`
- **Retention**: 168 hours (7 days)
- **Auth**: Disabled (Handled by Ingress)
- **Access**: `https://observability.canepro.me/loki/api/v1/push` (Basic Auth)

### 4. Tempo (Traces Layer)

**Role**: Distributed tracing backend.

**Configuration**:

- **Deployment**: Monolithic
- **Storage**: **OCI Object Storage (S3 Compatible)**
  - Bucket: `tempo-data`
- **Access (external ingest)**: `https://observability.canepro.me/v1/traces` (OTLP HTTP, Basic Auth)
- **Access (in-cluster OTLP gRPC)**: `tempo.monitoring.svc.cluster.local:4317`

**Note on "real traces" in this repo**
- `ingress-nginx` exports spans via OTLP gRPC to the in-cluster `otel-collector`
- `otel-collector` forwards those spans to Tempo
- External apps/clusters can send OTLP HTTP to the secure ingress endpoint above

### 5. NGINX Ingress (The Gatekeeper)

**Role**: Secure entry point for both UI and Data Ingestion.

**Configuration**:

- **SSL**: Let's Encrypt (cert-manager)
- **Authentication**: Basic Auth (`observability-auth` secret)
- **Path Routing**:
  - `/api/v1/write` -> Prometheus remote_write receiver
  - `/loki/api/v1/push` -> Loki push endpoint
  - `/v1/traces` -> Tempo OTLP HTTP ingest

**Tracing**
- Ingress request traces are enabled and exported to Tempo via `otel-collector` (see `helm/nginx-ingress-values.yaml` and `argocd/applications/otel-collector.yaml`).

## Storage Architecture

### Hybrid Storage Model (Free Tier Optimized)

1. **Block Volumes (PVC)**: Used for high-performance, random-access workloads.
   - Prometheus TSDB (50Gi)
   - (Optional) Grafana database (only if you re-enable persistence; E1 uses `emptyDir`)

2. **Ephemeral Storage (emptyDir)**: Used for non-critical transient state to save on OCI quotas.
   - Alertmanager State (Silence/Alert history)
   - Grafana (E1: dashboards provisioned from git)

3. **Object Storage (S3)**: Used for bulk, long-term data storage (Lower Cost).
   - Loki Chunks & Indexes
   - Tempo Traces

## Network Architecture

### External Access (LoadBalancer)

Single LoadBalancer IP exposes two domains via SNI:

1. **`grafana.canepro.me`**: Public UI (Grafana Login)
2. **`observability.canepro.me`**: Data Ingestion API (Basic Auth)

### Internal Communication

All inter-service communication happens via ClusterIP services within the `monitoring` namespace.

## Security

- **Transport**: HTTPS/TLS 1.3 enforced.
- **Ingestion Auth**: HTTP Basic Authentication required for all push endpoints.
- **Data Isolation**: Loki configured for single-tenant mode (simplified).

## GitOps (Argo CD)

Argo CD is installed into the cluster using Terraform + the Helm provider:

- **Terraform**: `terraform/argocd.tf` defines `helm_release.argocd` (chart `argo-cd`; version is pinned in code and tracked in `VERSION-TRACKING.md`).
- **Ingress**: `argocd.canepro.me` via NGINX Ingress (`ingressClassName: nginx`).
- **TLS**: cert-manager issues `Certificate/argocd-tls` using `ClusterIssuer/letsencrypt-prod` (created via ingress-shim).
- **Server mode**: Argo CD server runs with `--insecure` and the ingress terminates TLS.

### Helm provider authentication (OKE)

Terraform’s Helm provider connects to the Kubernetes API server using:

- Cluster API endpoint: `oci_containerengine_cluster.k8s_cluster.endpoints[0].public_endpoint`
- Cluster CA: extracted from `data.oci_containerengine_cluster_kube_config.k8s_kube_config.content`
- Auth: OCI CLI exec token generation via `oci ce cluster generate-token --cluster-id <id>`

This requires the `oci` CLI to be installed and authenticated wherever Terraform runs.

### Node pool image drift (blast radius control)

The node pool is configured to ignore changes to `node_source_details[0].image_id` to prevent Terraform from proposing node pool updates whenever the “latest” Oracle Linux image changes:

- This keeps routine `terraform plan` output focused on intentional changes (like Helm releases).
- It reduces the risk of accidental node rotation due to image drift.
