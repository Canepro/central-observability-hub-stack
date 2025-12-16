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
- **Storage**: 50 GiB PVC (OCI Block Volume)
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
- **Access**: `https://observability.canepro.me/tempo` (Basic Auth)

### 5. NGINX Ingress (The Gatekeeper)

**Role**: Secure entry point for both UI and Data Ingestion.

**Configuration**:

- **SSL**: Let's Encrypt (cert-manager)
- **Authentication**: Basic Auth (`observability-auth` secret)
- **Path Routing**:
  - `/prometheus` -> Prometheus Server
  - `/loki` -> Loki Gateway
  - `/tempo` -> Tempo Distributor

## Storage Architecture

### Hybrid Storage Model (Free Tier Optimized)

1. **Block Volumes (PVC)**: Used for high-performance, random-access workloads.
   - Prometheus TSDB
   - Grafana Database
   - Alertmanager State

2. **Object Storage (S3)**: Used for bulk, long-term data storage (Lower Cost).
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
