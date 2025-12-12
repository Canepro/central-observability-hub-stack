# Grafana Observability Stack - Troubleshooting Guide

Common issues and solutions for the OKE observability stack deployment.

## Table of Contents

1. [Authentication Issues](#authentication-issues)
2. [Loki Issues](#loki-issues)
3. [Prometheus Issues](#prometheus-issues)
4. [Ingress & Network Issues](#ingress--network-issues)
5. [Pod Issues](#pod-issues)

---

## Authentication Issues

### 401 Unauthorized on Public Endpoints

**Symptoms**: `curl` returns `HTTP/2 401` even with correct password.

**Root Causes**:
1. **Secret Variable Expansion**: Creating secrets with `$apr1$` hashes in bash can trigger variable expansion, truncating the hash.
2. **Wrong Hash Format**: NGINX Ingress `auth-type: basic` requires `htpasswd` format (MD5/APR1/Bcrypt), but some generated hashes (like default `openssl passwd`) might be incompatible or truncated.

**Solution**:
Always use **single quotes** when creating secrets via CLI to prevent variable expansion.

```bash
# BAD (Bash expands $apr1)
kubectl create secret generic auth --from-literal=auth="user:$apr1$..."

# GOOD (Single quotes)
kubectl create secret generic auth --from-literal=auth='user:$apr1$...'
```

---

## Loki Issues

### Promtail 404 Not Found

**Symptoms**: Promtail logs show `server returned HTTP status 404 Not Found`.

**Root Cause 1: Path Mismatch**
- Ingress is rewriting `/loki/api/v1/push` to `/api/v1/push`.
- Backend (Loki Gateway) expects `/loki/api/v1/push`.

**Solution**:
Ensure Ingress uses regex capture groups to preserve the prefix.

```yaml
# Ingress Annotation
nginx.ingress.kubernetes.io/rewrite-target: /$1

# Rule
- path: /(loki/.*)  # Captures "loki/api/v1/push"
  backend: loki-gateway
```

**Root Cause 2: Auth Enabled in Loki**
- If `auth_enabled: true` in Loki values, it expects `X-Scope-OrgID`.
- Promtail must be configured to send this header.
- **Our Setup**: We set `auth_enabled: false` to simplify (Auth handled by NGINX).

### Loki Pod Crash "Invalid Config"

**Symptoms**: `invalid compactor config: compactor.delete-request-store should be configured`

**Solution**:
When retention is enabled in Loki, you MUST configure the delete store.

```yaml
compactor:
  retention_enabled: true
  delete_request_store: s3  # Set to match your object_store
```

---

## Prometheus Issues

### Remote Write 404 (Remote Agent)

**Symptoms**: Remote Prometheus Agent logs `server returned HTTP status 404 Not Found: remote write receiver needs to be enabled`.

**Root Cause**:
The destination Prometheus server has Remote Write Receiver **DISABLED** by default.

**Solution**:
Enable the feature flag in Prometheus values.

**For Standalone Prometheus Chart**:
```yaml
server:
  extraFlags:
    - web.enable-remote-write-receiver
```

**For Kube-Prometheus-Stack**:
```yaml
prometheus:
  prometheusSpec:
    enableRemoteWriteReceiver: true
```

---

## Ingress & Network Issues

### NGINX Default Backend Crash (ARM64)

**Symptoms**: `ingress-nginx-defaultbackend` pod in `CrashLoopBackOff`.
**Error**: `exec format error` (Logs).

**Root Cause**:
The default image `registry.k8s.io/defaultbackend-amd64:1.5` is AMD64 only. It fails on ARM Ampere nodes.

**Solution**:
Disable the default backend in Helm values (it's optional).

```yaml
defaultBackend:
  enabled: false
```

### 503 Service Unavailable

**Symptoms**: `HTTP/2 503` from Ingress.

**Root Causes**:
1. **Service Not Found**: Ingress points to wrong service name or port.
2. **Selector Mismatch**: Service selector doesn't match any pods.
3. **Network Policy**: Denying Ingress traffic.

**Debugging**:
```bash
# Check Endpoints (Should show IPs)
kubectl get endpoints -n monitoring <service-name>

# Check Logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

---

## Pod Issues

### Immutable Field Error (StatefulSet)

**Symptoms**: Helm upgrade fails with `Forbidden: updates to statefulset spec for fields other than...`

**Root Cause**:
StatefulSet storage configuration (volumeClaimTemplates) CANNOT be changed after creation.

**Solution**:
You must **delete** the StatefulSet (and usually the PVCs if re-sizing) before re-installing.

```bash
helm uninstall <release-name> -n monitoring
helm install <release-name> ...
```
