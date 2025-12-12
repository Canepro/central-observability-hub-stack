#!/bin/bash
# Setup cert-manager and SSL/TLS for Grafana
# Run this script after NGINX Ingress is installed

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "🔒 Setting up SSL/TLS with cert-manager..."

# Check if we're in the right cluster
echo "📋 Current context:"
kubectl config current-context
read -p "Is this the OKE cluster? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Please switch to OKE cluster first!"
    exit 1
fi

# Step 1: Install cert-manager
echo ""
echo "📦 Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager to be ready
echo "⏳ Waiting for cert-manager to be ready (this may take 2-3 minutes)..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager \
  --timeout=300s

echo "✅ cert-manager is ready!"

# Step 2: Get email for Let's Encrypt
echo ""
read -p "Enter your email for Let's Encrypt notifications: " EMAIL
if [ -z "$EMAIL" ]; then
    echo "❌ Email is required!"
    exit 1
fi

# Step 3: Create ClusterIssuer
echo ""
echo "🔧 Creating Let's Encrypt ClusterIssuer..."
# Update email in the ClusterIssuer
sed "s/admin@canepro.me/$EMAIL/g" "$PROJECT_ROOT/k8s/cert-manager-clusterissuer.yaml" | kubectl apply -f -

# Wait a moment for ClusterIssuer to be ready
sleep 5

# Verify ClusterIssuer
echo ""
echo "📋 Verifying ClusterIssuer..."
kubectl get clusterissuer letsencrypt-prod

# Step 4: Update Grafana Ingress to enable TLS
echo ""
echo "🌐 Updating Grafana Ingress to enable TLS..."
# Read the current ingress file
INGRESS_FILE="$PROJECT_ROOT/k8s/grafana-ingress.yaml"

# Create a temporary file with TLS enabled
TMP_FILE=$(mktemp)
cat "$INGRESS_FILE" | \
  sed 's/# nginx.ingress.kubernetes.io\/ssl-redirect: "true"/nginx.ingress.kubernetes.io\/ssl-redirect: "true"/' | \
  sed 's/# cert-manager.io\/cluster-issuer: "letsencrypt-prod"/cert-manager.io\/cluster-issuer: "letsencrypt-prod"/' | \
  sed '/# TLS configuration/,/#   secretName: grafana-tls/c\
  tls:\
  - hosts:\
    - grafana.canepro.me\
    secretName: grafana-tls' > "$TMP_FILE"

# Apply the updated ingress
kubectl apply -f "$TMP_FILE"
rm "$TMP_FILE"

echo ""
echo "⏳ Waiting for certificate to be issued (this may take 2-5 minutes)..."
echo "   You can check status with: kubectl get certificate -n monitoring"

# Wait for certificate
for i in {1..30}; do
    CERT_STATUS=$(kubectl get certificate grafana-tls -n monitoring -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$CERT_STATUS" == "True" ]; then
        echo "✅ Certificate is ready!"
        break
    fi
    echo "  Waiting... ($i/30) - Status: $CERT_STATUS"
    sleep 10
done

# Step 5: Verify
echo ""
echo "📋 Certificate status:"
kubectl get certificate -n monitoring grafana-tls

echo ""
echo "📋 Ingress status:"
kubectl get ingress -n monitoring grafana-ingress

echo ""
echo "✅ SSL/TLS setup complete!"
echo ""
echo "🌐 Access Grafana at: https://grafana.canepro.me"
echo ""
echo "💡 Note: It may take a few minutes for the certificate to fully propagate"
echo "   If you see certificate errors, wait 2-3 minutes and try again"

