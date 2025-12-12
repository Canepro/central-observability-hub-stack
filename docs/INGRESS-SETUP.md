# NGINX Ingress Setup Guide

This guide covers setting up NGINX Ingress Controller with LoadBalancer and configuring Grafana Ingress for domain access.

## Prerequisites

- OKE cluster running
- Grafana deployed in `monitoring` namespace
- Domain `canepro.me` with DNS access
- **No existing LoadBalancer conflicts** (check with `./scripts/check-lb-status.sh`)

## Pre-Setup: Check LoadBalancer Status

**IMPORTANT**: Before setting up NGINX Ingress, check for existing LoadBalancers:

```bash
# Check existing LoadBalancer services
./scripts/check-lb-status.sh

# If you have a stuck/problematic LoadBalancer, clean it up:
./scripts/cleanup-old-lb.sh
```

**Note**: OCI Always Free tier allows **1 LoadBalancer**. If you have a stuck LoadBalancer from previous attempts, you may need to:
1. Wait 24 hours for token expiration, OR
2. Delete the problematic service and recreate as ClusterIP

## Quick Setup

### Option 1: Automated Script

```bash
# Switch to OKE cluster
kubectl config use-context <oke-context-name>

# Run setup script
./scripts/setup-ingress.sh
```

### Option 2: Manual Steps

#### Step 1: Install NGINX Ingress Controller

```bash
# Add Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install with LoadBalancer
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values helm/nginx-ingress-values.yaml \
  --wait
```

#### Step 2: Get LoadBalancer IP

```bash
# Wait for IP assignment (may take 2-5 minutes)
kubectl get svc -n ingress-nginx ingress-nginx-controller -w

# Once IP is assigned, note it down
LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "LoadBalancer IP: $LB_IP"
```

#### Step 3: Configure DNS

In your domain registrar (where `canepro.me` is managed):

**Option A: Specific subdomain**
```
Type: A
Name: grafana
Value: <LB_IP>
TTL: 300 (or default)
```

**Option B: Wildcard (Recommended)**
```
Type: A
Name: *
Value: <LB_IP>
TTL: 300 (or default)
```

This allows all subdomains (`*.canepro.me`) to work automatically.

#### Step 4: Create Grafana Ingress

```bash
# Apply Ingress resource
kubectl apply -f k8s/grafana-ingress.yaml

# Verify Ingress
kubectl get ingress -n monitoring
```

#### Step 5: Test Access

Wait 5-30 minutes for DNS propagation, then:

```bash
# Test DNS resolution
nslookup grafana.canepro.me

# Test HTTP access
curl -I http://grafana.canepro.me

# Access in browser
# http://grafana.canepro.me
```

## SSL/TLS Setup (Optional)

### Install cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager \
  --timeout=300s
```

### Create Let's Encrypt ClusterIssuer

```bash
# Create ClusterIssuer (replace email)
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com  # CHANGE THIS
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### Enable TLS in Grafana Ingress

1. Edit `k8s/grafana-ingress.yaml`
2. Uncomment the TLS section
3. Uncomment the cert-manager annotation
4. Apply: `kubectl apply -f k8s/grafana-ingress.yaml`

Wait 2-5 minutes for certificate issuance, then access: `https://grafana.canepro.me`

## Verification

```bash
# Check Ingress Controller
kubectl get pods -n ingress-nginx

# Check LoadBalancer service
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Check Grafana Ingress
kubectl get ingress -n monitoring grafana-ingress

# Check Ingress events
kubectl describe ingress -n monitoring grafana-ingress

# Test from inside cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -H "Host: grafana.canepro.me" http://ingress-nginx-controller.ingress-nginx.svc.cluster.local
```

## Troubleshooting

### LoadBalancer Token Collision Error (409 Conflict)

**Symptoms**: 
```
Error syncing load balancer: failed to ensure load balancer: creating load balancer: 
Error returned by LoadBalancer Service. Http Status Code: 409. Error Code: Conflict.
Message: Token Collision...
```

**Root Cause**: OCI sees conflicting LoadBalancer creation requests (often from multiple service updates/restarts).

**Solutions**:

1. **Wait 24 hours** - OCI tokens expire after 24 hours
2. **Delete and recreate service**:
   ```bash
   # Delete the problematic service
   kubectl delete svc <service-name> -n <namespace>
   
   # Wait 5 minutes for OCI cleanup
   # Then recreate with Helm or kubectl
   ```
3. **Check OCI Console** for stuck LoadBalancer operations:
   - OCI Console > Networking > Load Balancers
   - Look for stuck "Creating" or "Updating" states
   - Delete if stuck for >30 minutes

4. **Use a different service name** to get a fresh token

### LoadBalancer IP Stuck in Pending

- Check OCI Load Balancer quotas (Always Free: 1 LB allowed)
- Verify security list rules allow traffic
- Wait 5-10 minutes for OCI provisioning
- Check for token collision errors (see above)

### DNS Not Resolving

- Verify DNS records are correct
- Wait for DNS propagation (can take up to 48 hours, usually 5-30 min)
- Check with: `nslookup grafana.canepro.me`

### 502 Bad Gateway

- Check Grafana pod is running: `kubectl get pods -n monitoring | grep grafana`
- Check Ingress backend: `kubectl describe ingress -n monitoring grafana-ingress`
- Check Ingress Controller logs: `kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller`

### Certificate Not Issuing

- Check cert-manager pods: `kubectl get pods -n cert-manager`
- Check certificate status: `kubectl get certificate -n monitoring`
- Check cert-manager logs: `kubectl logs -n cert-manager -l app=cert-manager`

## Adding More Services

To add more services (e.g., Rocket.Chat):

1. Create new Ingress resource in `k8s/` directory
2. Use different `host` (e.g., `rocketchat-prod.canepro.me`)
3. Point to appropriate service
4. Apply: `kubectl apply -f k8s/<service>-ingress.yaml`

All services share the same LoadBalancer IP!

## Cost Considerations

- **1 LoadBalancer**: ~$10-15/month (or free if within Always Free tier)
- **NGINX Ingress**: Minimal resource usage (~100m CPU, 128Mi memory)
- **cert-manager**: Minimal resource usage
- **Total**: Very cost-effective for multiple services

## Next Steps

After Ingress is working:

1. Update Grafana root URL in `helm/prometheus-values.yaml`:
   ```yaml
   grafana.ini:
     server:
       root_url: https://grafana.canepro.me
   ```

2. Upgrade Grafana: `helm upgrade prometheus ... -f helm/prometheus-values.yaml`

3. Configure additional services as needed

