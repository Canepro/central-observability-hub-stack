# Agent Notes (GrafanaLocal / central-observability-hub-stack)

These notes are local instructions for coding agents working in this repo.

## Principles

- **GitOps first**: Treat this repo as the source of truth. Avoid in-cluster hotfixes that will drift and be reverted by ArgoCD self-heal.
- **Small, reviewable diffs**: Prefer focused PRs with clear intent and post-merge verification steps.
- **Docs must match reality**: If you change any operational behavior, update the relevant docs in the same PR.

## Where Things Live

- ArgoCD applications: `argocd/applications/*.yaml`
- Helm values: `helm/*.yaml`
- In-repo dashboards: `dashboards/*.json` (mounted via ConfigMap from `dashboards/kustomization.yaml`)
- Grafana provisioning (datasources + gnet dashboards + init patches): `helm/grafana-values.yaml`
- Prometheus config + alert rules: `helm/prometheus-values.yaml` (`serverFiles.prometheus.yml`, `serverFiles.alerting_rules.yml`)

## Grafana Dashboard Provisioning Gotchas

- Datasource UIDs are fixed to avoid import prompts:
  - Prometheus: `uid: prometheus`
  - Loki: `uid: loki`
  - Tempo: `uid: tempo`
- Some upstream gnet dashboards require patching for file provisioning:
  - duplicate dashboard UID collisions (Grafana rejects duplicates)
  - Prometheus placeholders like `${DS_PROMETHEUS}` (file provisioning does not resolve `__inputs`)
  - Loki dashboards shipping PromQL-like variable queries that get sent to Loki (LogQL parse error)
  - These are patched in an initContainer in `helm/grafana-values.yaml`

## Prometheus Scraping (OKE)

- kubelet/cAdvisor scraping uses the apiserver proxy path (`/api/v1/nodes/<node>/proxy/...`) and requires RBAC `nodes/proxy`.
- This repo adds `nodes/proxy` RBAC via `extraManifests` in `helm/prometheus-values.yaml`.

## Tracing (Real Data)

- `ingress-nginx` OpenTelemetry is enabled in `helm/nginx-ingress-values.yaml`.
- The collector is deployed via ArgoCD app `argocd/applications/otel-collector.yaml` with values `helm/otel-collector-values.yaml`.
- Collector image must be fully-qualified on OKE/CRI-O (short-name enforcement).

## Alerting

- Prometheus alert rules are defined in `helm/prometheus-values.yaml` under `serverFiles.alerting_rules.yml`.
- Prefer stable metric sources:
  - use kube-state-metrics for workload/pod readiness
  - avoid alerts that depend on scrape-target `job=` names unless the scrape config guarantees them
- For multi-cluster rules, always filter by `cluster="..."` to avoid mixing hub vs spokes.

## PR Process (Repo Convention)

- Always leave a PR comment before merging that includes:
  - what caused the issue/change request
  - root cause
  - what was changed and why
  - post-merge verification steps
- If a PR fixes a GitHub issue, include `Closes #NN` in the PR description (or commit message) so it auto-closes on merge.

## Quick Verification Checklist (Post-Change)

- `kubectl -n argocd get applications` shows expected apps Healthy/Synced (or known/acceptable drift only).
- Grafana dashboards load (especially provisioned Loki/Tempo dashboards if touched).
- Prometheus targets:
  - `kubernetes-nodes-cadvisor` is `UP`
  - alert rules are loaded and evaluating
- Tempo spans increment after ingress requests (PromQL): `sum(increase(tempo_distributor_spans_received_total[5m]))`

