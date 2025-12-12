#!/bin/bash
# Cleanup old/problematic LoadBalancer services
# Use this if you need to remove stuck LoadBalancers

set -e

echo "🧹 Cleaning up old LoadBalancer services..."

# List all LoadBalancer services
echo ""
echo "📋 Current LoadBalancer services:"
kubectl get svc -A -o wide | grep LoadBalancer

echo ""
read -p "⚠️  Do you want to delete the Grafana LoadBalancer service? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Deleting Grafana LoadBalancer service..."
    kubectl delete svc prometheus-grafana -n monitoring 2>/dev/null || echo "  Service not found or already deleted"
    
    # Wait a moment
    sleep 5
    
    # Recreate as ClusterIP
    echo "🔄 Recreating Grafana service as ClusterIP..."
    kubectl patch svc prometheus-grafana -n monitoring -p '{"spec":{"type":"ClusterIP"}}' 2>/dev/null || \
    echo "  Service will be recreated by Helm on next upgrade"
    
    echo "✅ Cleanup complete!"
else
    echo "⏭️  Skipped"
fi

echo ""
echo "💡 Note: If LoadBalancer was stuck in OCI, it may take a few minutes to fully delete"
echo "   Check OCI Console > Networking > Load Balancers if needed"

