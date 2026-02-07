# Security Recommendations for Multi-Cluster Observability

## ⚠️ Security Concerns with Direct LoadBalancer Exposure

Exposing Prometheus, Loki, and Tempo directly via LoadBalancer **without authentication** is a **security risk**.

### Risks

1. **No Authentication**: Anyone with the IP can:
   - Query all metrics from Prometheus
   - Read all logs from Loki
   - Access all traces from Tempo
   - Potentially scrape sensitive data

2. **Cost**: 3 LoadBalancers = 3x the cost (OCI charges per LoadBalancer)

3. **Attack Surface**: Three publicly accessible endpoints increase attack surface

4. **Data Exposure**: Observability data may contain sensitive information (API keys, user data, system internals)

---

## ✅ Recommended Approaches

### Option 1: Single LoadBalancer + Ingress with Authentication (Recommended)

Use a single LoadBalancer with NGINX Ingress Controller and authentication.

#### Benefits

- **Single LoadBalancer** (cost-effective)
- **Authentication** via basic auth or OAuth
- **TLS/HTTPS** support
- **Rate limiting** and access control
- **Path-based routing** (single IP for all services)

#### Implementation

1. **Expose Ingress Controller** (already done for Grafana)

2. **Create Ingress with Authentication**:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: observability-services
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: observability-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Observability Services - Authentication Required'
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - observability.canepro.me
      secretName: observability-tls
  rules:
    - host: observability.canepro.me
      http:
        paths:
          # Prometheus
          - path: /api/v1/write
            pathType: Prefix
            backend:
              service:
                name: prometheus-server
                port:
                  number: 80
          # Loki
          - path: /loki/api/v1/push
            pathType: Prefix
            backend:
              service:
                name: loki-gateway
                port:
                  number: 80
          # Tempo OTLP HTTP
          - path: /v1/traces
            pathType: Prefix
            backend:
              service:
                name: tempo
                port:
                  number: 4318
```

3. **Create Basic Auth Secret**:

```bash
# Create htpasswd file
htpasswd -c auth observability-user
# Enter password when prompted

# Create Kubernetes secret
kubectl create secret generic observability-auth \
  --from-file=auth \
  -n monitoring
```

4. **Update AKS Configuration**:

```yaml
# In AKS cluster, configure remote_write with authentication
remote_write:
  - url: https://observability.canepro.me/api/v1/write
    basic_auth:
      username: observability-user
      password: <password-from-secret>
```

#### Service-Specific Path Rewrites

You may need to add rewrite annotations for proper routing:

```yaml
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /$2
  nginx.ingress.kubernetes.io/use-regex: "true"
```

This repo's default is to avoid rewrites and use direct ingestion paths:
- `/api/v1/write` (Prometheus remote_write)
- `/loki/api/v1/push` (Loki push)
- `/v1/traces` (Tempo OTLP HTTP)

---

### Option 2: VPN/Private Network Connection

If OKE and AKS are in the same cloud provider or connected via VPN:

#### Benefits

- **No public exposure** (most secure)
- **No LoadBalancer costs**
- **Direct cluster-to-cluster communication**

#### Implementation

1. **Set up VPN/Peering** between OKE and AKS networks
2. **Use internal service names** directly:
   - `http://prometheus-server.monitoring.svc.cluster.local:80`
   - Requires DNS resolution between clusters (CoreDNS federation)

3. **Or use internal LoadBalancer IPs** (if available in your cloud setup)

---

### Option 3: Service Mesh with mTLS

Use a service mesh (Istio, Linkerd) for secure inter-cluster communication.

#### Benefits

- **Mutual TLS** (mTLS) encryption
- **Service-to-service authentication**
- **Fine-grained access control**

#### Drawbacks

- More complex setup
- Additional resource overhead

---

### Option 4: Authentication on Services (If LoadBalancer Required)

If you must use LoadBalancers, add authentication to each service.

#### Prometheus Authentication

Add authentication via reverse proxy or Prometheus configuration:

```yaml
# Use Prometheus Operator with authentication
prometheus:
  prometheusSpec:
    externalUrl: https://prometheus.canepro.me
    # Add authentication via ingress or service mesh
```

#### Loki Authentication

Loki already supports multi-tenancy. Add authentication gateway:

```yaml
# Use Loki Gateway with authentication
gateway:
  enabled: true
  auth:
    enabled: true
    # Configure OAuth or basic auth
```

#### Tempo Authentication

Add authentication via reverse proxy or OTLP collector with auth.

---

## 🔒 Security Best Practices

### 1. Network Security

- **Restrict Source IPs**: Use OCI Security Lists to allow only AKS cluster IPs
- **Firewall Rules**: Block all traffic except from known sources
- **Private Endpoints**: Prefer private network connections when possible

### 2. Authentication

- **Always use authentication** for exposed services
- **Use strong passwords** or OAuth tokens
- **Rotate credentials** regularly
- **Use TLS/HTTPS** for all external connections

### 3. Monitoring

- **Monitor access logs** for suspicious activity
- **Set up alerts** for unauthorized access attempts
- **Review access patterns** regularly

### 4. Data Protection

- **Encrypt data in transit** (TLS)
- **Encrypt data at rest** (OCI Block Volumes support this)
- **Limit data retention** (already configured: 7-15 days)

---

## 💰 Cost Comparison

| Approach | LoadBalancers | Monthly Cost (Est.) | Security Level |
|----------|---------------|---------------------|----------------|
| **3 Direct LoadBalancers** | 3 | ~$45-90 | ⚠️ Low (no auth) |
| **1 LoadBalancer + Ingress** | 1 | ~$15-30 | ✅ High (with auth) |
| **VPN/Private Network** | 0 | $0-20 (VPN) | ✅✅ Highest |
| **Service Mesh** | 0-1 | $0-30 | ✅✅ Highest |

*Costs are estimates and vary by cloud provider and region*

---

## 📋 Recommended Implementation Steps

### For Your Use Case (OKE → AKS)

**Recommended: Option 1 (Single LoadBalancer + Ingress)**

1. ✅ **You already have NGINX Ingress** (for Grafana)
2. ✅ **You already have cert-manager** (for TLS)
3. ⚠️ **Add authentication** to the ingress
4. ⚠️ **Create ingress rules** for Prometheus, Loki, Tempo
5. ⚠️ **Update AKS configuration** to use authenticated endpoints

### Quick Start

```bash
# 1. Create basic auth secret
htpasswd -c auth observability-user
kubectl create secret generic observability-auth \
  --from-file=auth -n monitoring

# 2. Create ingress (see YAML above)
kubectl apply -f k8s/observability-ingress.yaml

# 3. Get the external IP/domain
kubectl get ingress observability-services -n monitoring

# 4. Update AKS remote_write config with:
#    - URL: https://observability.canepro.me/api/v1/write
#    - Basic auth credentials
```

---

## 🚨 If You Must Use Direct LoadBalancers

If you absolutely need direct LoadBalancers (not recommended), at minimum:

1. **Restrict Source IPs** in OCI Security Lists (only allow AKS IPs)
2. **Use TLS/HTTPS** (add TLS to services)
3. **Monitor access logs** aggressively
4. **Set up alerts** for unauthorized access
5. **Consider IP whitelisting** at the service level

---

## Related Documentation

- [Configuration Guide](../docs/CONFIGURATION.md) - Detailed configuration
- [Hub Architecture](ARCHITECTURE.md) - System design

---

**Last Updated**: Based on current OKE deployment  
**Status**: ⚠️ Security recommendations for production use
