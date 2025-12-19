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

### Argo CD "Manifest generation error (cached)" / values not applying

**Symptoms**: Argo app shows `Progressing` / `ComparisonError` and logs mention:

`Manifest generation error (cached): helm template ... failed`

**Fix**:

1. Check the Application conditions for the real error:

```bash
kubectl -n argocd get application loki -o jsonpath='{.status.conditions[*].type}{"\n"}{.status.conditions[*].message}{"\n"}'
```

2. Force a hard refresh of the app cache and re-sync:

```bash
kubectl -n argocd annotate application loki argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd patch application loki --type merge -p '{"operation":{"sync":{"prune":true}}}'
```

### Argo CD error: "Helm test requires the Loki Canary to be enabled"

**Symptoms**: Argo fails to render Loki with:

`... validate.yaml ... Helm test requires the Loki Canary to be enabled`

**Fix**: Enable canary in `helm/loki-values.yaml`, commit/push, hard refresh, sync.

```yaml
lokiCanary:
  enabled: true
```

### Loki CrashLoop: "mkdir /var/loki: read-only file system"

**Symptoms**:

`init compactor: mkdir /var/loki: read-only file system`

**Root cause**: The Loki container runs with a read-only root filesystem. If you disable the PVC, Loki must write local state to a writable path (`/tmp`).

**Fix**: Use `/tmp` for Loki local paths (values example):

```yaml
loki:
  commonConfig:
    path_prefix: /tmp/loki
  compactor:
    working_directory: /tmp/loki/compactor
```

### Loki / Tempo S3 auth on OCI: "SignatureDoesNotMatch" or "region must be specified"

**Context**: OCI Object Storage is accessed via the **S3-compatible API**. Loki/Tempo use S3 clients internally.

**Fix pattern** (recommended):

- Put credentials in a K8s Secret as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- Inject the secret via `extraEnvFrom`
- Do **not** embed credentials in the Loki/Tempo config blocks; let the SDK read env vars.

```bash
kubectl -n monitoring create secret generic loki-s3-credentials \
  --from-literal=AWS_ACCESS_KEY_ID='...' \
  --from-literal=AWS_SECRET_ACCESS_KEY='...'
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

### Grafana stuck with 2 pods (one in Init:0/2 / PodInitializing)

**Symptoms**
- ArgoCD shows the `grafana` app as Degraded/Progressing
- `kubectl get pods -n monitoring | grep grafana` shows two Grafana pods
- The newer pod is stuck in `Init:0/2` with init containers waiting to mount `/var/lib/grafana`

**Root cause**
Grafana uses a single **ReadWriteOnce** PVC. With the default **RollingUpdate** strategy, Kubernetes may try to start a new pod before terminating the old pod, and the PVC cannot be mounted by both.

**Fix (recommended)**
Configure Grafana to use `deploymentStrategy: Recreate` in `helm/grafana-values.yaml` so the old pod is terminated before the new one starts (brief downtime during rollout).

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

### Argo CD SyncError: StatefulSet "Forbidden" (immutable spec) during upgrades

**Symptoms**: Argo shows:

`StatefulSet.apps "<name>" is invalid: spec: Forbidden: updates to statefulset spec ... are forbidden`

**Fix**: Delete the StatefulSet and any old PVCs, then re-sync the app.

Example for Loki:

```bash
kubectl -n monitoring delete sts loki --cascade=orphan
kubectl -n monitoring delete pvc storage-loki-0 --ignore-not-found
kubectl -n argocd patch application loki --type merge -p '{"operation":{"sync":{"prune":true}}}'
```

### PVC stuck Terminating (pvc-protection)

**Symptoms**: A pod is Pending and `describe` shows:

`persistentvolumeclaim "<name>" is being deleted`

**Fix**:

1. Scale the workload down (so nothing uses the PVC).
2. Remove the finalizer:

```bash
kubectl -n monitoring patch pvc grafana -p '{"metadata":{"finalizers":null}}' --type=merge
```

Then scale back up.
