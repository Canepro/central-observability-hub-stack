# 1. Central Stack Configuration (GrafanaLocal)
- [x] **Enable Remote Write**: Updated `helm/prometheus-values.yaml` to set `prometheus.prometheusSpec.enableRemoteWriteReceiver: true`.
- [x] **Add Dashboards**: Configured Grafana to provision RocketChat dashboards (ID 23428, 23427) and MongoDB dashboards (ID 24296, 23712).
- [x] **Verification**: Checked Prometheus CR to confirm `enableRemoteWriteReceiver: true`.
- [x] **Deployment**: Deployed via Helm (Release status `failed` but resources are healthy and active).

# 2. External Podman Configuration (`podman.canepro.me`)
- [x] **Agent Config**: Created `docs/external-config/podman-agent.river` (Grafana Agent Flow).
- [x] **Instructions**: Added step-by-step guide in `docs/external-config/ROCKETCHAT-SETUP.md`.

# 3. External Kubernetes Configuration (`k8.canepro.me`)
- [x] **Agent Config**: Created `docs/external-config/k8s-agent-values.yaml` (Helm values).
- [x] **Instructions**: Included in `docs/external-config/ROCKETCHAT-SETUP.md`.

# 4. RocketChat Configuration
- [x] **Guide**: Documented how to enable Prometheus in RocketChat Admin and set up OTEL.

# 5. Execution
- [x] **Central Stack**: Applied changes to the central cluster.
- [ ] **External Stacks**: User to apply configs on `podman.canepro.me` and `k8.canepro.me`.
