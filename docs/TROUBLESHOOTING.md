# Grafana Observability Stack - Troubleshooting Guide

Common issues and solutions for the OKE observability stack deployment.

## Table of Contents

1. [Authentication Issues](#authentication-issues)
2. [Loki Issues](#loki-issues)
3. [Tempo Issues](#tempo-issues)
4. [Prometheus Issues](#prometheus-issues)
5. [Ingress & Network Issues](#ingress--network-issues)
6. [Pod Issues](#pod-issues)

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

### Grafana Loki dashboard error: `parse error ... unexpected IDENTIFIER`

**Symptoms**
- Loki dashboard panels/variables error with: `parse error at line 1, col 1: syntax error: unexpected IDENTIFIER`

**Root cause**
The dashboard is trying to run a **Prometheus-style** templating query (e.g. `label_values(kube_pod_info, namespace)`) against the **Loki** datasource. Grafana sends that query to Loki as LogQL and Loki rejects it.

**Fix (this repo)**
This repo patches the affected upstream Loki dashboards at startup via an initContainer in `helm/grafana-values.yaml`:
- variable queries rewritten to Loki `label_values(...)` semantics
- filters rewritten to use `pod=...` (our promtail labels) instead of `instance=...`

If you imported a Loki dashboard manually, re-import from the provisioned set (or patch the dashboard JSON to match Loki templating semantics).

---

## Tempo Issues

### Tempo dashboard shows metrics but no traces

**Symptoms**
- Tempo datasource tests fine, Tempo dashboards render some panels, but Trace search returns nothing.

**Root cause**
Tempo only shows traces if something is actually sending spans. Metrics being present does not guarantee traces are being ingested.

**This repo behavior**
- Tempo OTLP ingest is enabled (service ports 4317/4318).
- Real tracing is enabled for ingress traffic:
  - `ingress-nginx` exports spans via OTLP gRPC to the in-cluster collector
  - `otel-collector` forwards spans to Tempo

**How to verify ingestion**
1. Generate a few requests through ingress (from inside the cluster):
   ```bash
   kubectl run -it --rm curl --image=curlimages/curl --restart=Never -- \
     curl -sS -H "Host: grafana.canepro.me" http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/ >/dev/null
   ```
2. In Grafana Explore (Prometheus), run:
   ```promql
   sum(increase(tempo_distributor_spans_received_total[5m]))
   ```
   If this is > 0, Tempo is receiving spans.
3. In Grafana Explore (Tempo), search for service `ingress-nginx`.

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

### Grafana dashboard shows "No data" for PVC usage

#### Symptoms

- “PVC Usage %” panel shows `No data` while PVCs are bound and workloads are running.

#### Root cause

The PVC usage panel relies on kubelet volume metrics:

- `kubelet_volume_stats_used_bytes`
- `kubelet_volume_stats_capacity_bytes`

These metrics are only present if Prometheus scrapes kubelet `/metrics` (often via the API server proxy).

#### Fix (this repo)

Ensure `helm/prometheus-values.yaml` includes the `kubelet-volume-stats` scrape job under `serverFiles.prometheus.yml.scrape_configs`.
Then verify in Prometheus (Grafana Explore → Prometheus):

```promql
kubelet_volume_stats_used_bytes
```

**For Kube-Prometheus-Stack**:

```yaml
prometheus:
  prometheusSpec:
    enableRemoteWriteReceiver: true
```

### Prometheus targets `kubernetes-nodes-cadvisor` / `kubernetes-nodes` are DOWN with `403 Forbidden`

**Symptoms**
- Kubernetes dashboards show `No data` for container metrics (`container_*`, cAdvisor panels, CPU/memory by container, etc.)
- Prometheus targets show `kubernetes-nodes` or `kubernetes-nodes-cadvisor` as `DOWN`
- Target error includes `403 Forbidden`

**Root cause**
This repo scrapes kubelet/cAdvisor via the apiserver proxy path:
- `/api/v1/nodes/<node>/proxy/metrics`
- `/api/v1/nodes/<node>/proxy/metrics/cadvisor`

Prometheus needs RBAC permission for `nodes/proxy`. Prometheus chart v28+ no longer includes that permission by default.

**Fix (this repo)**
`helm/prometheus-values.yaml` adds an `extraManifests` ClusterRole/Binding granting `nodes/proxy` to the `prometheus-server` ServiceAccount.

**Fast verification**
In Grafana Explore (Prometheus):
```promql
up{job="kubernetes-nodes-cadvisor"}
```
Should be `1` for each node.

---

## Alertmanager Issues

### Grafana Alertmanager dashboard shows `N/A` for all stats

**Symptoms**
- The Alertmanager dashboard panels show `N/A` for instance count, cluster size, active alerts, silences, etc.

**Root cause**
Prometheus is not scraping Alertmanager's own `/metrics`. This repo relies on service annotations for `kubernetes-service-endpoints` discovery. If the `prometheus-alertmanager` service is missing `prometheus.io/scrape=true`, the series `alertmanager_*` will not exist, and the dashboard has nothing to render.

**Fix (this repo)**
`helm/prometheus-values.yaml` adds scrape annotations on the Alertmanager service:
- `prometheus.io/scrape: "true"`
- `prometheus.io/port: "9093"`
- `prometheus.io/path: /metrics`

**Quick verification**
In Grafana Explore (Prometheus), run:
```promql
count(alertmanager_build_info)
```
It should be > 0.

### Alertmanager email notifications fail with Gmail `535 5.7.8 Username and Password not accepted`

**Symptoms**
- Alertmanager logs show repeated retries and eventual failure, for example:
  - `*email.loginAuth auth: 535 5.7.8 Username and Password not accepted ... BadCredentials`
- You have firing alerts, but no email arrives.

**Root cause**
- The Kubernetes Secret `monitoring/grafana-smtp-credentials` exists, but the values are not accepted by Gmail SMTP.
  - Most commonly: the `password` is not a **Gmail App Password** (required when 2FA is enabled), or the password was rotated/invalidated.
  - Less commonly: the `user` is not the full email address.

**Fix**
1. Generate a new **Gmail App Password** for the account used to send alerts.
2. Update the Secret (safe upsert, no delete):
```bash
kubectl -n monitoring create secret generic grafana-smtp-credentials \
  --from-literal=password='NEW_GMAIL_APP_PASSWORD' \
  --from-literal=user='your-email@gmail.com' \
  --from-literal=from_address='your-email@gmail.com' \
  --from-literal=to_address='alerts-recipient@gmail.com' \
  --dry-run=client -o yaml | kubectl apply -f -
```
3. Restart Alertmanager (pods do not reload env vars automatically):
```bash
kubectl -n monitoring rollout restart statefulset/prometheus-alertmanager
```
4. If you also use Grafana email (Grafana-managed alerting/contact points), restart Grafana too:
```bash
kubectl -n monitoring rollout restart deploy/grafana
```

**Verification**
- In Alertmanager logs, you should stop seeing the 535 retries:
```bash
kubectl -n monitoring logs statefulset/prometheus-alertmanager | rg -i \"smtp|email|notify|error|fail\"
```
- In Prometheus (Grafana Explore):
```promql
sum(increase(alertmanager_notifications_total{integration=\"email\"}[30m]))
```

---

## Alerting (Runbooks)

This repo defines Prometheus alert rules in `helm/prometheus-values.yaml` under `serverFiles.alerting_rules.yml`.

### `ArgoCDApplicationDegraded` is firing

**Meaning**
- Argo CD is reporting one or more Applications with `health_status="Degraded"` on the hub cluster (`cluster="oke-hub"`).
- The rule uses a `for: 5m` hold-down, so it must stay degraded for 5 minutes to fire.

**Common causes**
- A workload is unhealthy (CrashLoopBackOff, image pull error, failing readiness probe).
- Argo CD can sync, but the resulting resources are unhealthy.
- Argo CD can't reach a repo or chart registry, so an Application is stuck in a bad state (often shows up as Degraded/Unknown depending on the case).

**Fast verification**
In Grafana Explore (Prometheus):
```promql
argocd_app_info{health_status="Degraded",cluster="oke-hub"}
```
Look at the returned labels (especially `name` and `project`) to identify the affected application.

**What to check next (GitOps-first)**
```bash
# (Hub cluster) list degraded apps and the status fields
kubectl -n argocd get applications.argoproj.io

# describe a specific app for health/sync details
kubectl -n argocd describe application <app-name>
```
Then fix by changing Git (values/manifest) and letting ArgoCD reconcile.

### `HubContainerOOMKilled` is firing

**Meaning**
- A container in `monitoring` or `argocd` on the hub cluster has `last_terminated_reason=OOMKilled`.
- The rule has `for: 0m` (it fires immediately).

**Important behavior note**
- This alert is based on `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` which can remain `1` until the container terminates again for a different reason. If you only want "recent OOMKills", change the rule to a time-window based expression.

**Fast verification**
In Grafana Explore (Prometheus):
```promql
kube_pod_container_status_last_terminated_reason{reason="OOMKilled",cluster="oke-hub",namespace=~"monitoring|argocd"} == 1
```

**What to check next**
```bash
kubectl -n monitoring get pods
kubectl -n monitoring describe pod <pod>
kubectl -n monitoring logs <pod> -c <container> --previous
```
Then adjust resources (requests/limits) in Git, or fix the workload's memory leak/peak usage.

### `AKSManyStalePods` is firing

**Meaning**
- On the AKS cluster (`cluster="aks-canepro"`), the count of pods in terminal phases is > 15 for 30 minutes:
  - `Failed` + `Unknown` + `Succeeded`

**Why this happens**
- CronJobs/Jobs create lots of `Succeeded` pods and keep history.
- `Failed` pods accumulate when workloads repeatedly fail and aren’t cleaned up.
- `Unknown` often indicates node/agent issues or API reporting problems.

**Fast verification**
In Grafana Explore (Prometheus):
```promql
count(kube_pod_status_phase{phase="Failed",cluster="aks-canepro"}) or vector(0)
```
```promql
count(kube_pod_status_phase{phase="Unknown",cluster="aks-canepro"}) or vector(0)
```
```promql
count(kube_pod_status_phase{phase="Succeeded",cluster="aks-canepro"}) or vector(0)
```

**What to check next**
```bash
# (AKS cluster context) identify which namespaces/pods are piling up
kubectl get pods -A --field-selector=status.phase=Succeeded
kubectl get pods -A --field-selector=status.phase=Failed
kubectl get pods -A --field-selector=status.phase=Unknown
```

**Mitigations (best practice)**
- Set `successfulJobsHistoryLimit` / `failedJobsHistoryLimit` on CronJobs.
- Prefer `ttlSecondsAfterFinished` on Jobs where supported/appropriate.
- If you intentionally rely on a cleanup job (for example a `aks-stale-pod-cleanup` CronJob), ensure it is deployed via GitOps and is running successfully.

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

### Certificate / ACME challenge stuck (no such host)

**Symptoms**: `kubectl get certificate -n <ns>` shows `Ready: False`; `kubectl describe challenge -n <ns>` shows:

`Waiting for HTTP-01 challenge propagation: ... lookup <hostname> on 10.96.5.5:53: no such host`

**Root cause**: cert-manager runs a self-check from inside the cluster. It resolves the hostname using **cluster DNS** (CoreDNS). If the hostname (e.g. `jenkins-oke.canepro.me`) is not resolvable from cluster DNS—e.g. nodes use an internal resolver that doesn’t have public DNS, or the name isn’t in public DNS yet—the self-check fails and the challenge stays pending.

**Fix**:

1. **Public DNS**: Ensure the hostname has an **A record** pointing to your ingress LB IP (e.g. `jenkins-oke.canepro.me` → `141.148.16.227`). Check from outside the cluster:
   ```bash
   nslookup jenkins-oke.canepro.me 8.8.8.8
   ```

2. **Resolve from inside the cluster**: If nodes’ `/etc/resolv.conf` doesn’t use a resolver that has public DNS, make the hostname resolvable from CoreDNS by forwarding the zone to a public resolver. Edit the CoreDNS ConfigMap in `kube-system` and add a block **before** the fallback `.:53` block (replace `canepro.me` with your domain if different):
   ```yaml
   canepro.me:53 {
     errors
     cache 30
     forward . 8.8.8.8 1.1.1.1
   }
   ```
   Then reload CoreDNS (or restart the CoreDNS pods). After that, cert-manager’s self-check can resolve the hostname and the HTTP-01 challenge can complete.

3. **Retry**: Delete the stuck challenge so cert-manager creates a new one (optional):
   ```bash
   kubectl delete challenge -n <namespace> <challenge-name>
   ```

### kubectl: TLS handshake timeout (OKE specific)

**Symptoms**: The first `kubectl` command fails with `Unable to connect to the server: net/http: TLS handshake timeout`, but the second try works perfectly.

**Root cause**:
This is usually caused by the latency of the OCI CLI exec-plugin (`oci ce cluster generate-token`) generating a fresh authentication token. The process can sometimes exceed the default client timeout on the first run.

**Solution**:
- Simply retry the command.
- Ensure your OCI CLI is up to date: `oci setup repair-file-permissions`.
- If it persists, you can increase the timeout by setting an environment variable: `export KUBECTL_EXTERNAL_TOKEN_TIMEOUT=30`.

---

## Pod Issues

### Grafana Readiness probe failed: "connect: connection refused"

**Symptoms**
- Grafana Deployment keeps rolling pods (new ReplicaSet every few minutes)
- Events show:
  - `Readiness probe failed: Get "http://<pod-ip>:3000/api/health": ... connect: connection refused`
- ArgoCD may show `grafana` as `Progressing` while it continually restarts

**Root cause**
Grafana can be **slow to start** on OCI Always Free ARM nodes (DB migrations, plugin init, dashboard provisioning). If CPU/memory is too tight or the probes are too aggressive, the pod is marked unready and/or restarted before it finishes booting.

**Fix (GitOps)**
Tune resources and probes in `helm/grafana-values.yaml`:
- Increase `resources.requests` (CPU/memory)
- Add/extend `readinessProbe` and `livenessProbe` delays so Grafana has time to come up

After committing/pushing, let ArgoCD apply changes. If ArgoCD seems stuck on stale state, force refresh:

```bash
kubectl -n argocd annotate application grafana argocd.argoproj.io/refresh=hard --overwrite
```

### Grafana stuck with 2 pods (one in Init:0/2 / PodInitializing)

**Symptoms**
- ArgoCD shows the `grafana` app as Degraded/Progressing
- `kubectl get pods -n monitoring | grep grafana` shows two Grafana pods
- The newer pod is stuck in `Init:0/2` with init containers waiting to mount `/var/lib/grafana`

**Root cause**
This depends on whether Grafana persistence is enabled:
- **E1 (this repo default)**: Grafana uses `emptyDir` (`persistence.enabled: false`). A second pod is usually just a rollout/scheduling pressure issue on small nodes, not a PVC deadlock.
- **When persistence is enabled**: Grafana typically uses a single **ReadWriteOnce** PVC. With a RollingUpdate and `maxSurge > 0`, Kubernetes may try to start a new pod before terminating the old pod, and the PVC cannot be mounted by both.

**Fix (recommended)**
Keep `maxSurge: 0` in `helm/grafana-values.yaml` so rollouts do not create an extra Grafana pod:
- avoids PVC attach contention if you later enable persistence
- reduces resource spikes on Always Free nodes

### Image pull error: "short-name mode enforcing" / ImageInspectError

**Symptoms**
- Pod fails to start with errors mentioning short-name enforcement or image inspection failures.

**Root cause**
Some container runtimes enforce fully-qualified image names (registry required). Charts that default to `image: otel/opentelemetry-collector-contrib:...` (no registry) can fail.

**Fix**
Use fully-qualified image names, for example:
- `docker.io/otel/opentelemetry-collector-contrib:0.145.0`

This repo already does this for the OTEL collector in `helm/otel-collector-values.yaml`.

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
