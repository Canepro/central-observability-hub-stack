#!/bin/bash
# Check existing LoadBalancer services and OCI status
# Run this BEFORE setting up NGINX Ingress to avoid conflicts

echo "🔍 Checking existing LoadBalancer services..."

# Check all LoadBalancer services
echo ""
echo "📋 Current LoadBalancer services:"
kubectl get svc -A -o wide | grep LoadBalancer || echo "  No LoadBalancer services found"

# Check for pending LoadBalancers
echo ""
echo "⏳ Checking for pending LoadBalancers..."
kubectl get svc -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | select(.status.loadBalancer.ingress==null or .status.loadBalancer.ingress==[]) | "\(.metadata.namespace)/\(.metadata.name) - PENDING"' 2>/dev/null || \
kubectl get svc -A -o wide | grep LoadBalancer | grep -v "EXTERNAL-IP.*[0-9]" || echo "  No pending LoadBalancers"

# Check for events related to LoadBalancer
echo ""
echo "📝 Recent LoadBalancer events (last 10):"
kubectl get events -A --sort-by='.lastTimestamp' | grep -i "loadbalancer\|service" | tail -10 || echo "  No recent LoadBalancer events"

# Check for the problematic Grafana service
echo ""
echo "🔍 Checking Grafana service status:"
kubectl get svc grafana -n monitoring 2>/dev/null || echo "  Grafana service not found in monitoring namespace"

echo ""
echo "💡 Recommendations:"
echo "  - If you see a pending LoadBalancer, wait for it to resolve or delete it"
echo "  - If you see token collision errors, wait 24 hours or delete the service"
echo "  - OCI Always Free tier allows 1 LoadBalancer - make sure you're not exceeding quota"
echo ""
echo "✅ If all clear, proceed with NGINX Ingress setup"

