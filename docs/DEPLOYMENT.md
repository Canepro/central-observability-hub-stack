# Grafana Observability Stack - Deployment Guide

Complete step-by-step guide to deploy the observability stack on Oracle Kubernetes Engine (OKE).

## Prerequisites

- OKE cluster running with 2+ worker nodes (ARM/AMD64 supported)
- `kubectl` configured to access the cluster
- `helm` v3.x installed
- OCI Block Volume storage class available (`oci-bv`)
- OCI Object Storage bucket credentials (for Loki/Tempo)

## Infrastructure Details

- **Cluster**: Oracle Kubernetes Engine (OKE)
- **Kubernetes**: v1.34.1+
- **Domain**: canepro.me
- **Tenancy**: Always Free tier

## Deployment Steps

### Step 1: Add Helm Repositories

```bash
# Add Grafana and Prometheus Community Helm repositories
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

### Step 2: Create Monitoring Namespace

```bash
kubectl create namespace monitoring
```

### Step 3: Create Secrets

**1. OCI Object Storage Credentials (for Loki & Tempo):**

```bash
# We use OCI Object Storage S3-compat keys, but most S3 clients expect AWS_* env vars.
# Store them in a Kubernetes secret that can be env-injected into Loki/Tempo pods.
kubectl -n monitoring create secret generic loki-s3-credentials \
  --from-literal=AWS_ACCESS_KEY_ID='YOUR_OCI_S3_ACCESS_KEY' \
  --from-literal=AWS_SECRET_ACCESS_KEY='YOUR_OCI_S3_SECRET_KEY'
```

**2. Data Ingestion Authentication (for Remote Agents):**

```bash
# Generate APR1 hash (e.g., using openssl or htpasswd)
# Example user: observability-user
# Example hash: $apr1$th5J7vrc$tL8FiO7Kq6pT60qctEYZs/

kubectl create secret generic observability-auth -n monitoring \
  --from-literal=auth='observability-user:$apr1$th5J7vrc$tL8FiO7Kq6pT60qctEYZs/'
```

### Step 4: Deploy Loki (Logs)

```bash
# Install with S3 configuration (credentials are injected via secret; do not pass on CLI)
helm install loki grafana/loki \
  --version 6.46.0 \
  -n monitoring \
  -f helm/loki-values.yaml
```

### Step 5: Deploy Prometheus (Metrics)

```bash
helm install prometheus prometheus-community/prometheus \
  --version 27.47.0 \
  -f helm/prometheus-values.yaml \
  -n monitoring
```

### Step 6: Deploy Grafana (Visualization)

```bash
helm install grafana grafana/grafana \
  --version 7.3.0 \
  -f helm/grafana-values.yaml \
  -n monitoring
```

### Step 7: Deploy Tempo (Traces)

```bash
# Install with S3 configuration (credentials are injected via secret; do not pass on CLI)
helm install tempo grafana/tempo \
  --version 1.24.0 \
  -n monitoring \
  -f helm/tempo-values.yaml
```

### Step 8: Deploy Promtail (Log Collection)

```bash
helm install promtail grafana/promtail \
  --version 6.17.1 \
  -f helm/promtail-values.yaml \
  -n monitoring
```

### Step 9: Set Up NGINX Ingress Controller

```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -f helm/nginx-ingress-values.yaml \
  -n monitoring
```

### Step 10: Configure Ingress Routes & SSL

```bash
# 1. Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# 2. Configure Let's Encrypt Issuer
kubectl apply -f k8s/cert-manager-clusterissuer.yaml

# 3. Apply Grafana Ingress (UI)
kubectl apply -f k8s/grafana-ingress.yaml

# 4. Apply Observability Ingress (Data Ingestion)
kubectl apply -f k8s/observability-ingress-secure.yaml
```

### Step 11: Retrieve Grafana Credentials

```bash
kubectl get secret grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 -d ; echo
```

### Step 12: Access Services

- **UI**: `https://grafana.canepro.me`
- **Metrics Endpoint**: `https://observability.canepro.me/api/v1/write`
- **Logs Endpoint**: `https://observability.canepro.me/loki/api/v1/push`

## Verification

```bash
# Check Pods
kubectl get pods -n monitoring

# Check Ingress
kubectl get ingress -n monitoring

# Check PVCs
kubectl get pvc -n monitoring
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for solutions to common issues (e.g., 404 errors, 401 Unauthorized, ARM64 crashes).
