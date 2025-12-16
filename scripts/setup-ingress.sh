#!/bin/bash
# Setup NGINX Ingress Controller and Grafana Ingress for OKE Cluster
# Run this script after switching to OKE cluster context

set -e

# Get script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "🚀 Setting up NGINX Ingress Controller and Grafana Ingress..."

# Check if we're in the right cluster
echo "📋 Current context:"
kubectl config current-context
read -p "Is this the OKE cluster? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Please switch to OKE cluster first!"
    exit 1
fi

# Check for existing LoadBalancers
echo ""
echo "🔍 Checking for existing LoadBalancers..."
EXISTING_LB=$(kubectl get svc -A -o wide | grep LoadBalancer | grep -v "EXTERNAL-IP.*<pending>" | wc -l || echo "0")
if [ "$EXISTING_LB" -gt "0" ]; then
    echo "⚠️  Found existing LoadBalancer(s). OCI Always Free tier allows 1 LoadBalancer."
    kubectl get svc -A -o wide | grep LoadBalancer
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Aborted. Please clean up existing LoadBalancers first."
        exit 1
    fi
fi

# Step 1: Add NGINX Ingress Helm repo
echo "📦 Adding NGINX Ingress Helm repository..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Step 2: Install NGINX Ingress Controller
echo "🔧 Installing NGINX Ingress Controller..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values "$PROJECT_ROOT/helm/nginx-ingress-values.yaml" \
  --wait

# Step 3: Get LoadBalancer IP
echo "⏳ Waiting for LoadBalancer IP..."
echo "This may take 2-5 minutes..."
LB_IP=""
for i in {1..30}; do
    LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$LB_IP" ]; then
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 10
done

if [ -z "$LB_IP" ]; then
    echo "⚠️  LoadBalancer IP not assigned yet. Check with:"
    echo "   kubectl get svc -n ingress-nginx ingress-nginx-controller"
    exit 1
fi

echo "✅ LoadBalancer IP: $LB_IP"

# Step 4: Wait for admission webhook to be ready
echo "⏳ Waiting for NGINX Ingress admission webhook to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s 2>/dev/null || true

# Wait a bit more for webhook service to be ready
echo "  Waiting for webhook service..."
sleep 10

# Step 5: Create Grafana Ingress
echo "🌐 Creating Grafana Ingress..."
kubectl apply -f "$PROJECT_ROOT/k8s/grafana-ingress.yaml" || {
    echo "⚠️  First attempt failed, retrying in 10 seconds..."
    sleep 10
    kubectl apply -f "$PROJECT_ROOT/k8s/grafana-ingress.yaml"
}

# Step 6: Instructions for DNS
echo ""
echo "📝 Next Steps:"
echo "=============="
echo "1. Update DNS for grafana.canepro.me:"
echo "   A record: grafana.canepro.me → $LB_IP"
echo ""
echo "2. Or use wildcard DNS:"
echo "   A record: *.canepro.me → $LB_IP"
echo ""
echo "3. Wait for DNS propagation (5-30 minutes)"
echo ""
echo "4. Test access:"
echo "   http://grafana.canepro.me"
echo ""
echo "5. (Optional) Set up SSL with cert-manager:"
echo "   See $PROJECT_ROOT/k8s/cert-manager-setup.yaml for instructions"
echo ""
echo "✅ Setup complete!"

