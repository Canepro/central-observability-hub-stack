# Tracing Service Onboarding Template

Use this template per service (or workload group).  
Copy the section below into an issue/PR description and fill it before merging.

## Template

### Service Identity

- Service name: `<service-name>`
- Namespace: `<namespace>`
- Environment: `<prod|staging|dev>`
- Cluster label strategy: `<oke-hub|spoke-label>`
- Owner: `<name>`
- Rollout date: `<YYYY-MM-DD>`

### Instrumentation Scope

- Runtime/framework: `<go|java|node|python|dotnet|other>`
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

### Required Attributes

- [ ] `service.name` is set and stable (not pod/container name).
- [ ] `service.namespace` is set.
- [ ] `deployment.environment` is set.
- [ ] Route/operation attributes are present and low-cardinality.
- [ ] No high-cardinality IDs in metric/span dimensions.

### Trace Context Propagation

- [ ] W3C context extracted on inbound (`traceparent`, `tracestate`, `baggage`).
- [ ] W3C context injected on outbound calls.
- [ ] Async propagation handled (queue/job metadata) where applicable.

### Error and Status Semantics

- [ ] Span status is set for failures.
- [ ] HTTP/gRPC status attributes are recorded.
- [ ] Exception/error events are attached to spans.

### GitOps Change Record

- Repo paths changed:
  - `<path-1>`
  - `<path-2>`
- Argo apps expected to reconcile:
  - `<app-name>`
- PR/commit references:
  - `<link-or-sha>`

### Verification Gates

Run these after rollout and attach results/screenshots.

1. Prometheus service graph metrics:

```promql
sum by (client, server) (rate(traces_service_graph_request_total[5m]))
```

Expected:
- [ ] Edge including `<service-name>` appears.

2. Prometheus spanmetrics:

```promql
sum(rate(traces_spanmetrics_calls_total[5m]))
```

Expected:
- [ ] Non-zero during traffic window.

3. Tempo trace presence (Explore / TraceQL):

```traceql
{ resource.service.name = "<service-name>" }
```

Expected:
- [ ] Recent traces returned.

4. Grafana Service Graph:
- [ ] Node for `<service-name>` visible.
- [ ] At least one meaningful inbound/outbound edge.

5. Grafana Traces Drilldown:
- [ ] No `localblocks processor not found` errors.
- [ ] Span names are meaningful (not mostly `<name not yet available>`).

### Operational Acceptance

- [ ] On-call can locate a failed request trace for `<service-name>` in under 5 minutes.
- [ ] Failure path shows enough context to identify dependency/root cause.
- [ ] Dashboard noise/cardinality impact reviewed and acceptable.

### Rollback Plan

- [ ] Feature flags/env vars to disable instrumentation documented.
- [ ] Safe rollback steps documented (GitOps revert commit/PR).

## Suggested Starter Targets (Current Cluster)

1. `ingress-nginx` (baseline already present)
2. Edge API/gateway service
3. Auth/shared platform service
4. Core business service
5. Worker/cron service
