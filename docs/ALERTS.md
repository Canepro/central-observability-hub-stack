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

## 6. Maintenance & Secret Restoration

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

## 7. Benefits and Achievements

1. Infrastructure as Code (IaC): Alerts are version-controlled in prometheus-values.yaml.
2. Automated Discovery: Metrics services are automatically managed via Terraform argocd.tf.
3. Proactive Guardrails: Real-time monitoring of the 200GB OCI storage limit and the Kind-to-OKE bridge.
