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
  -n monitoring
```

## 7. Benefits and Achievements

1. Infrastructure as Code (IaC): Alerts are version-controlled in prometheus-values.yaml.
2. Automated Discovery: Metrics services are automatically managed via Terraform argocd.tf.
3. Proactive Guardrails: Real-time monitoring of the 200GB OCI storage limit and the Kind-to-OKE bridge.
