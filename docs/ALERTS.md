# 🚨 Multi-Cluster Alerting & Infrastructure Health

## 1. Overview

This document defines the alerting strategy for the Project. We monitor three distinct layers of the infrastructure to ensure high availability and rapid disaster recovery.

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
| OKE Storage Warning | `(kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes) * 100 < 15` | Warning  | Alerting on OCI Block Volume usage. Critical for staying under the 200GB Always Free limit. |

## 5. Tier 3: GitOps & World Tree (Logical Infrastructure)

**Goal**: Monitor the health of the management tools (Argo CD) and the applications they deploy.

| Alert Name               | Logic (PromQL)                                      | Severity | Description                                                                 |
|--------------------------|-----------------------------------------------------|----------|-----------------------------------------------------------------------------|
| Argo CD Controller Down  | `up{job="argocd-application-controller-metrics"} == 0` | Critical | Triggered if the Argo CD metrics service (enabled via Terraform) stops reporting. |
| Argo CD App Degraded     | `argocd_app_info{health_status="Degraded"} == 1`    | Critical | Notifies if a GitOps application (e.g., RocketChat) fails its health check or crashes. |

## 6. Tier 4: AKS Spoke Cluster (aks-canepro)

**Goal**: Monitor the production Rocket.Chat workloads running on AKS. Metrics arrive at the hub via remote-write and are filtered by `cluster="aks-canepro"`.

### Node Health

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

### Application Health

| Alert Name | Logic (PromQL) | Severity | Description |
|---|---|---|---|
| AKS Rocket.Chat Down | `rocketchat-rocketchat available == 0` | Critical | No Rocket.Chat replicas |
| AKS MongoDB Down | `mongodb ready == 0` | Critical | MongoDB StatefulSet down |
| AKS NATS Down | `rocketchat-nats ready == 0` | Critical | NATS messaging down |
| AKS Jenkins Down | `jenkins ready == 0` | Warning | Jenkins CI down |

### Storage

| Alert Name | Logic (PromQL) | Severity | Description |
|---|---|---|---|
| AKS PVC Usage High | `used / capacity > 85%` | Warning | PVC nearing capacity |
| AKS PVC Usage Critical | `used / capacity > 95%` | Critical | PVC almost full |

### Observability Pipeline

| Alert Name | Logic (PromQL) | Severity | Description |
|---|---|---|---|
| AKS Prometheus Remote Write Failing | `rate(failed_samples) > 0` | Warning | Metrics not reaching hub |
| AKS Promtail Down | `ready < desired` | Warning | Log collection incomplete |
| AKS Kube State Metrics Down | `available == 0` | Critical | All cluster alerts will stop firing |

### Network

| Alert Name | Logic (PromQL) | Severity | Description |
|---|---|---|---|
| AKS CoreDNS Down | `coredns available == 0` | Critical | Cluster-wide DNS failure |

## 7. Maintenance & Secret Restoration

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

## 8. Benefits and Achievements

1. Infrastructure as Code (IaC): Alerts are version-controlled in prometheus-values.yaml.
2. Automated Discovery: Metrics services are automatically managed via Terraform argocd.tf.
3. Proactive Guardrails: Real-time monitoring of the 200GB OCI storage limit and the Kind-to-OKE bridge.
