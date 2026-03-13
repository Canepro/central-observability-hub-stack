# Tracing Onboarding - argocd-server

This is a pre-filled instance of `TRACING-SERVICE-ONBOARDING-TEMPLATE.md` for the first practical target in this cluster.

## Service Identity

- Service name: `argocd-server`
- Namespace: `argocd`
- Environment: `prod`
- Cluster label strategy: `cluster=oke-hub`
- Owner: `platform` (update with actual owner)
- Rollout date: `2026-02-22`

## Instrumentation Scope

- Runtime/framework: `third-party app (ArgoCD)`
- Inbound spans enabled:
  - [ ] HTTP server
  - [ ] gRPC server
- Outbound spans enabled:
  - [ ] HTTP client
  - [ ] gRPC client
  - [ ] DB client
  - [ ] Cache client
  - [ ] Queue client/consumer
- Background jobs instrumented:
  - [ ] Cron
  - [ ] Worker

Note:
- `argocd-server` is not your custom app, so deep app-level instrumentation may be limited.
- Treat this as a validation target for edge-to-service visibility and trace hygiene.

## Required Attributes

- [ ] `service.name` is set and stable (not pod/container name).
- [ ] `service.namespace` is set.
- [ ] `deployment.environment` is set.
- [ ] Route/operation attributes are present and low-cardinality.
- [ ] No high-cardinality IDs in metric/span dimensions.

## Trace Context Propagation

- [ ] W3C context extracted on inbound (`traceparent`, `tracestate`, `baggage`).
- [ ] W3C context injected on outbound calls.
- [ ] Async propagation handled (queue/job metadata) where applicable.

## Error and Status Semantics

- [ ] Span status is set for failures.
- [ ] HTTP/gRPC status attributes are recorded.
- [ ] Exception/error events are attached to spans.

## GitOps Change Record

- Repo paths changed:
  - `helm/tempo-values.yaml`
  - `helm/grafana-values.yaml`
  - `docs/TROUBLESHOOTING.md`
  - `hub-docs/TRACING-ROLLOUT-CHECKLIST.md`
  - `hub-docs/TRACING-SERVICE-ONBOARDING-TEMPLATE.md`
- Argo apps expected to reconcile:
  - `tempo`
  - `grafana`
- PR/commit references:
  - `87cb210` (service graph metrics + Grafana serviceMap)
  - `dcd9016` (chart key fix: `metricsGenerator`)
  - `b35f565` (`local-blocks` for Drilldown)

## Verification Gates

Run these and attach results/screenshots.

1. Prometheus service graph metrics:

```promql
sum by (client, server) (rate(traces_service_graph_request_total[5m]))
```

Expected:
- [x] Edge exists (`user -> ingress-nginx` confirmed)
- [ ] Edge includes `argocd-server`

2. Prometheus spanmetrics:

```promql
sum(rate(traces_spanmetrics_calls_total[5m]))
```

Expected:
- [x] Non-zero during traffic window.

3. Tempo trace presence (Explore / TraceQL):

```traceql
{ resource.service.name = "argocd-server" }
```

Expected:
- [ ] Recent traces for `argocd-server`.

4. Grafana Service Graph:
- [x] Graph renders.
- [ ] Node for `argocd-server` visible.
- [ ] Inbound/outbound edges for `argocd-server`.

5. Grafana Traces Drilldown:
- [x] No `localblocks processor not found` errors after latest sync.
- [ ] Span names meaningful for `argocd-server`.

## Traffic Generation Plan

Use controlled requests to create trace volume for this service.

1. Open ArgoCD UI via ingress (`argocd.canepro.me`) and navigate:
   - applications list
   - one application details page
2. If CLI route is available, run several API reads against ArgoCD.
3. Re-check the Verification Gates for a 15-30 minute window.

## Operational Acceptance

- [ ] Can find a failed request trace for `argocd-server` in under 5 minutes.
- [ ] Dependency/root-cause context is visible.
- [ ] Dashboard/cardinality impact reviewed.

## Rollback Plan

- [ ] Revert related tracing commits in Git if needed.
- [ ] Let ArgoCD reconcile rollback revisions.

## Next Target Recommendation

After `argocd-server`, move to your first custom edge API/workload so you can control instrumentation depth and get better than edge-only traces.
