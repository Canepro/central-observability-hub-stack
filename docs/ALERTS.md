# 🚨 Multi-Cluster Alerting & Infrastructure Health

## 1. Overview

This document defines the alerting strategy for this repo (OKE hub + connected spokes).

**Source of truth**: `helm/prometheus-values.yaml` (`serverFiles.alerting_rules.yml`).
Docs summarize intent and best practices, but the YAML is authoritative.

### How To See What Alerts Exist (Fast)

- **Prometheus rules** (source of truth): `helm/prometheus-values.yaml` under `serverFiles.alerting_rules.yml`.
- **In Grafana**: *Alerting* -> *Alert rules* shows what Prometheus has loaded (data source-managed rules).
- **In Prometheus**: query `ALERTS` (only exists when alerts are pending/firing).

## 2. Notification Channel: Secure SMTP

All critical alerts are routed via Gmail SMTP.

- **Security**: Credentials are never committed to Git.
- **Injection**: The password is pulled from the Kubernetes Secret `grafana-smtp-credentials` at runtime.
- **Verification**: SMTP connectivity is verified; Grafana uses the `GF_SMTP_PASSWORD` environment variable.

## 3. Tier 1: Spoke Cluster (Kind Lab)

**Goal**: Monitor the bridge between the public internet and the localized lab environment.

| Alert Name          | Logic (PromQL)                          | Severity | Description                                                                 |
|---------------------|-----------------------------------------|----------|-----------------------------------------------------------------------------|
| Kind Spoke Offline | `up{job="kind-kind-cluster"} == 0`      | Critical | Triggered if the L4 proxy on port 6443 fails or the Lab Server goes offline. |

## 4. Tier 2: Hub Cluster (OKE)

**Goal**: Monitor the stability of the management plane where Argo CD and Grafana reside.

| Alert Name          | Logic (PromQL)                                                     | Severity | Description                                                                 |
|---------------------|--------------------------------------------------------------------|----------|-----------------------------------------------------------------------------|
| OKE Storage Warning | `(kubelet_volume_stats_available_bytes{cluster="oke-hub"} / kubelet_volume_stats_capacity_bytes{cluster="oke-hub"}) * 100 < 15` | Warning  | Alerting on OCI Block Volume usage. Critical for staying under the 200GB Always Free limit. |

### Hub Node / Workload Health (Implemented)

This repo includes hub health alerts for:
- node CPU/memory/disk and NotReady state
- crashloops/OOM/pending pods in `monitoring` + `argocd`
- workload replicas mismatch (Deployment/StatefulSet/DaemonSet)
- core observability components down (Prometheus/Grafana/Loki/Tempo/Alertmanager)
- scrape health for a few high-signal targets (cAdvisor and kubelet volume stats)

The alert rules are grouped (in `helm/prometheus-values.yaml`) as:
- `HubNodeAlerts`
- `HubPodAlerts`
- `HubWorkloadAlerts`
- `HubMonitoringStackHealth`
- `HubPrometheusScrapeHealth`

#### HubNodeAlerts (oke-hub)

| Alert | Severity | `for:` | When it fires |
|---|---|---|---|
| `HubNodeHighCPU` | warning | 10m | Node CPU usage > 85% sustained. |
| `HubNodeHighMemory` | warning | 10m | Node memory usage > 85% sustained. |
| `HubNodeDiskPressure` | warning | 10m | Root filesystem usage > 85% sustained (mountpoint `/`). |
| `HubNodeNotReady` | critical | 5m | Node Ready condition is not true. |

#### HubPodAlerts (monitoring/argocd, oke-hub)

| Alert | Severity | `for:` | When it fires |
|---|---|---|---|
| `HubPodCrashLooping` | warning | 10m | > 3 restarts in 15m (CrashLoop pattern) in `monitoring|argocd`. |
| `HubContainerOOMKilled` | warning | 0m | A container was last terminated due to `OOMKilled`. |
| `HubPodStuckPending` | warning | 15m | Pod phase `Pending` for > 15m. |

#### HubWorkloadAlerts (monitoring/argocd and a few core namespaces, oke-hub)

| Alert | Severity | `for:` | When it fires |
|---|---|---|---|
| `HubDeploymentReplicasMismatch` | warning | 15m | `available != desired` for Deployments in `monitoring|argocd`. |
| `HubStatefulSetReplicasMismatch` | warning | 15m | `ready != desired` for StatefulSets in `monitoring|argocd`. |
| `HubDaemonSetMissScheduled` | warning | 10m | DaemonSet desired > current scheduled in `monitoring|argocd|ingress-nginx|kube-system`. |

#### HubMonitoringStackHealth (oke-hub)

| Alert | Severity | `for:` | When it fires |
|---|---|---|---|
| `PrometheusServerUnavailable` | critical | 5m | `monitoring/prometheus-server` has 0 available replicas. |
| `GrafanaUnavailable` | critical | 5m | `monitoring/grafana` has 0 available replicas. |
| `LokiUnavailable` | critical | 10m | `monitoring/loki` StatefulSet has 0 ready replicas. |
| `TempoUnavailable` | critical | 10m | `monitoring/tempo` StatefulSet has 0 ready replicas. |
| `AlertmanagerUnavailable` | critical | 10m | `monitoring/prometheus-alertmanager` StatefulSet has 0 ready replicas. |

#### HubPrometheusScrapeHealth (oke-hub)

| Alert | Severity | `for:` | When it fires |
|---|---|---|---|
| `HubCadvisorScrapeDown` | critical | 5m | `up{job="kubernetes-nodes-cadvisor",cluster="oke-hub"} == 0` (any node). |
| `HubKubeletVolumeStatsScrapeDown` | warning | 5m | `up{job="kubelet-volume-stats",cluster="oke-hub"} == 0` (any node). |

## 5. Tier 3: GitOps & World Tree (Logical Infrastructure)

**Goal**: Monitor the health of the management tools (Argo CD) and the applications they deploy.

| Alert Name               | Logic (PromQL)                                      | Severity | Description                                                                 |
|--------------------------|-----------------------------------------------------|----------|-----------------------------------------------------------------------------|
| Argo CD Controller Down  | `kube_statefulset_status_replicas_ready{namespace="argocd",statefulset="argocd-application-controller"} < 1` | Critical | Triggered if the ArgoCD application-controller becomes NotReady. |
| Argo CD App Degraded     | `argocd_app_info{health_status="Degraded"} == 1`    | Critical | Notifies if a GitOps application is Degraded (requires ArgoCD metrics scraping). |

## 6. Tier 4: AKS Spoke Cluster (aks-canepro)

**Goal**: Monitor the production Rocket.Chat workloads running on AKS. Metrics arrive at the hub via remote-write and are filtered by `cluster="aks-canepro"`.

### Scheduled Shutdown Window

The AKS cluster is scheduled to run on weekdays from **16:00 to 23:00** and is shut down outside that window (and on weekends). To avoid false positives, Alertmanager mutes notifications for `cluster="aks-canepro"` during the expected downtime window.

This is implemented via `alertmanager.config.time_intervals` + `mute_time_intervals` in `helm/prometheus-values.yaml`. The config currently assumes `UTC`; if your shutdown schedule is in a different time zone, update the `location` field there.

### What is actually implemented

AKS alert rules are implemented under groups in `helm/prometheus-values.yaml` (for example `AKSSpokeNodeAlerts`, `AKSSpokePodAlerts`, `AKSSpokeWorkloadAlerts`). The patterns follow best practices:
- Filter by `cluster="aks-canepro"` to avoid mixing hub and spoke metrics.
- Use `for:` on noisy conditions (CPU/mem/disk/replicas mismatch) to avoid flapping.

### Node Health (examples)

| Alert Name | Logic (PromQL) | Severity | Description |
|---|---|---|---|
| AKS Node High CPU | `avg(rate(node_cpu_seconds_total{mode="idle"})) > 85%` | Warning | Node CPU sustained above 85% for 10m |
| AKS Node High Memory | `node_memory_MemAvailable / Total < 15%` | Warning | Node memory above 85% for 10m |
| AKS Node Disk Pressure | `node_filesystem_avail / size < 15%` | Warning | Root disk above 85% for 10m |
| AKS Node Not Ready | `kube_node_status_condition{Ready} == 0` | Critical | Node NotReady for 5m |

### Pod Health

| Alert Name | Logic (PromQL) | Severity | Description |
|---|---|---|---|
| AKS Pod Crash Looping | `rate(restarts_total[15m]) > 3` | Warning | Pod restarted >3 times in 15m |
| AKS Container OOM Killed | `last_terminated_reason=OOMKilled` | Warning | Container killed by OOM |
| AKS Pod Stuck Pending | `phase=Pending for 15m` | Warning | Pod cannot be scheduled |
| AKS Many Stale Pods | `Failed+Unknown+Succeeded > 15` | Warning | Cleanup CronJob may not be working |

### Workload Availability

| Alert Name | Logic (PromQL) | Severity | Description |
|---|---|---|---|
| AKS Deployment Replicas Mismatch | `available != desired` | Warning | Deployment under-replicated for 15m |
| AKS StatefulSet Replicas Mismatch | `ready != desired` | Warning | StatefulSet under-replicated for 15m |
| AKS DaemonSet Miss Scheduled | `desired - scheduled > 0` | Warning | DaemonSet missing pods on nodes |

## 7. Grafana dashboards for alerting

Grafana provisions an Alerts dashboard (gnet **9578**) via `helm/grafana-values.yaml`. Note that many alerting dashboards show `No data` when there are **no active alerts**, because Prometheus only emits `ALERTS` time series when an alert is pending/firing.

### 9578 dashboard: what “No data” means

- **Expected**: If nothing is `pending` or `firing`, the 9578 dashboard can look empty.
- **Verify quickly** (Grafana Explore, Prometheus):
  - `ALERTS{alertstate="firing"}`
  - `ALERTS{alertstate="pending"}`
- If those return nothing, the dashboard is behaving normally (no active alerts to display).

### Runbooks for common firing alerts

When you see an alert firing in Grafana (*Alerting* -> *Alert rules*), use `docs/TROUBLESHOOTING.md` under **Alerting (Runbooks)** for the actionable checks and next steps.

## 8. Maintenance & Secret Restoration

In the event of a cluster rebuild, the SMTP secret must be restored manually to re-enable notifications:

```bash
# Run on the OKE Cluster
kubectl create secret generic grafana-smtp-credentials \
  --from-literal=password='your-app-password' \
  --from-literal=user='your-email@gmail.com' \
  --from-literal=from_address='your-email@gmail.com' \
  --from-literal=to_address='your-email@gmail.com' \
  -n monitoring
```

**Note**: All SMTP credentials (password, user, from_address, to_address) are stored in the secret to avoid exposing PII in the public repository.

### Required keys (Grafana + Alertmanager)

This repo config injects SMTP config via env vars from `grafana-smtp-credentials`. The secret **must** contain:

- `password` (SMTP password / Gmail App Password)
- `user` (SMTP username, often the email)
- `from_address` (email used in the `From:` header)
- `to_address` (recipient address for Alertmanager notifications)

If `from_address` / `user` are missing, Grafana may fail to start with `CreateContainerConfigError` like:
`couldn't find key from_address in Secret monitoring/grafana-smtp-credentials`.

### Safe update / rotation (no delete)

Use `apply` to upsert values (recommended when rotating passwords):

```bash
# Run on the OKE Cluster
kubectl -n monitoring create secret generic grafana-smtp-credentials \
  --from-literal=password='NEW_APP_PASSWORD' \
  --from-literal=user='your-email@gmail.com' \
  --from-literal=from_address='your-email@gmail.com' \
  --from-literal=to_address='your-email@gmail.com' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Verify the keys:

```bash
kubectl -n monitoring get secret grafana-smtp-credentials -o json | jq -r '.data | keys[]'
```

Restart Grafana to re-read env vars:

```bash
kubectl -n monitoring rollout restart deploy/grafana
```

## 9. Benefits and Achievements

1. Infrastructure as Code (IaC): Alerts are version-controlled in prometheus-values.yaml.
2. Automated Discovery: Metrics services are automatically managed via Terraform argocd.tf.
3. Proactive Guardrails: Real-time monitoring of the 200GB OCI storage limit and the Kind-to-OKE bridge.
