# Grafana Observability Stack on OKE

Centralized observability hub for monitoring and aggregating metrics, logs, and traces from multiple Rocket.Chat deployments and other applications across environments.

## 🎯 Overview

This stack provides a production-ready, centralized observability platform deployed on Oracle Kubernetes Engine (OKE). It aggregates telemetry data from multiple sources, enabling unified monitoring, alerting, and visualization across your infrastructure.

## 🏗️ Infrastructure

- **Cluster**: Oracle Kubernetes Engine (OKE) in Ashburn
- **Nodes**: 2 worker nodes (VM.Standard.A1.Flex, 2 OCPU, 12GB RAM each)
- **Kubernetes**: v1.34.1
- **Domain**: 
  - `grafana.canepro.me` (Dashboards)
  - `observability.canepro.me` (Data Ingestion)
- **Tenancy**: Always Free tier
- **Ingress**: NGINX Ingress Controller with Let's Encrypt SSL/TLS

## 📦 Stack Components

| Component | Purpose | Deployment Mode | Storage |
|-----------|---------|----------------|---------|
| **Grafana** | Visualization & dashboards | Deployment | 50 GiB PVC |
| **Prometheus** | Metrics collection & alerting | Standalone | 50 GiB PVC |
| **Loki** | Log aggregation | Single Binary | **S3 (OCI)** |
| **Tempo** | Distributed tracing | Monolithic | **S3 (OCI)** |
| **Alertmanager** | Alert routing | StatefulSet | 5 GiB PVC |
| **Promtail** | Log collection agent | DaemonSet | N/A |
| **NGINX Ingress** | Load balancer & SSL termination | Deployment | N/A |

## 🔐 Access

### Grafana Dashboard

- **URL**: https://grafana.canepro.me
- **Username**: `admin`
- **Password**: Retrieve with:
  ```bash
  kubectl get secret grafana -n monitoring \
    -o jsonpath="{.data.admin-password}" | base64 -d ; echo
  ```

### Data Ingestion (Secure)

All external telemetry is sent to `https://observability.canepro.me` using **Basic Auth**.

- **Metrics (Remote Write)**: `/api/v1/write`
- **Logs (Loki Push)**: `/loki/api/v1/push`
- **Traces (OTLP HTTP)**: `/v1/traces`

**Credentials**: Stored in `observability-auth` secret (monitoring namespace).

## 📋 Helm Chart Versions

| Component | Chart | Version | App Version |
|-----------|-------|---------|-------------|
| Prometheus | prometheus-community/prometheus | 27.47.0 | v3.x |
| Loki | grafana/loki | 6.46.0 | 3.x |
| Tempo | grafana/tempo | 1.24.0 | 2.x |
| Promtail | grafana/promtail | 6.17.1 | 3.x |
| NGINX Ingress | ingress-nginx/ingress-nginx | Latest | Latest |
| cert-manager | cert-manager/cert-manager | v1.13.3 | v1.13.3 |

## 🚀 Quick Start

### Prerequisites

- OKE cluster running
- `kubectl` configured to access the cluster
- `helm` v3.x installed
- Domain `canepro.me` with DNS access

### Deployment

```bash
# 1. Add Helm repositories
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# 2. Create monitoring namespace
kubectl create namespace monitoring

# 3. Create Secrets (S3 & Auth)
# See docs/DEPLOYMENT.md for secret creation steps

# 4. Deploy components
helm install loki grafana/loki -f helm/loki-values.yaml -n monitoring
helm install prometheus prometheus-community/prometheus \
  -f helm/prometheus-values.yaml -n monitoring
helm install tempo grafana/tempo -f helm/tempo-values.yaml -n monitoring
helm install promtail grafana/promtail -f helm/promtail-values.yaml -n monitoring

# 5. Set up Ingress and SSL
kubectl apply -f k8s/observability-ingress-secure.yaml
```

## 📚 Documentation

- **[QUICKSTART.md](docs/QUICKSTART.md)** - Get started in 5 minutes! 🚀
- **[DEPLOYMENT-STATUS.md](docs/DEPLOYMENT-STATUS.md)** - Current deployment status and configuration summary
- **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** - Complete step-by-step deployment guide
- **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)** - **Integration Guide for Remote Clusters** 🔗
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## 📁 Directory Structure

```
├── helm/              # Helm values files for each component
│   ├── loki-values.yaml
│   ├── prometheus-values.yaml
│   ├── promtail-values.yaml
│   ├── tempo-values.yaml
│   └── nginx-ingress-values.yaml
├── k8s/               # Kubernetes manifests
│   ├── grafana-ingress.yaml
│   ├── observability-ingress-secure.yaml  # Public Data Ingestion Ingress
│   └── cert-manager-clusterissuer.yaml
├── docs/              # Documentation
│   ├── external-config/  # Config templates for remote agents
└── README.md          # This file
```

## 🔒 Security Features

- **HTTPS/TLS**: Let's Encrypt SSL certificates via cert-manager
- **Data Ingestion Auth**: Basic Authentication for all ingestion endpoints
- **S3 Encrypted Storage**: Logs and Traces stored securely in OCI Object Storage
- **Network Policies**: Internal services use ClusterIP (no external exposure without Auth)

## 🔄 Maintenance

### Update Components

```bash
# Update Helm repositories
helm repo update

# Upgrade components
helm upgrade loki grafana/loki -f helm/loki-values.yaml -n monitoring
helm upgrade prometheus prometheus-community/prometheus \
  -f helm/prometheus-values.yaml -n monitoring
```

## 🆘 Support

For issues and troubleshooting:

1. Check [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
2. Review pod logs: `kubectl logs <pod-name> -n monitoring`
3. Check component status: `kubectl get pods -n monitoring`

---

**Status**: ✅ Production Ready
