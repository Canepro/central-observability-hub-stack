# Tracing Rollout Checklist (GitOps)

This checklist is for rolling out useful distributed tracing across services in the OKE hub/spoke setup.
Use this as an operational gate, not just a reference.

## Scope

- Convert tracing from edge-only visibility (`user -> ingress-nginx`) to service-to-service visibility.
- Make Tempo Service Graph and Traces Drilldown actionable for incident response.
- Keep all changes GitOps-only (no direct `kubectl apply` hotfixes for permanent config).

Companion template:
- `hub-docs/TRACING-SERVICE-ONBOARDING-TEMPLATE.md`
- Example instance:
- `hub-docs/TRACING-ONBOARDING-argocd-server.md`

## Prerequisites (Hub)

- Tempo app synced in ArgoCD and healthy.
- Tempo metrics generator enabled with processors:
  - `service-graphs`
  - `span-metrics`
  - `local-blocks`
- Tempo metrics generator remote-writing to Prometheus `/api/v1/write`.
- Grafana Tempo datasource linked to Prometheus for Service Graph.

Quick checks:

```promql
sum(rate(traces_service_graph_request_total[5m]))
```

```promql
sum(rate(traces_spanmetrics_calls_total[5m]))
```

Both must return non-zero when traffic exists.

## GitOps Workflow (Required)

1. Make tracing config changes in Git.
2. Commit and push to `main` (or PR workflow if enforced).
3. Let ArgoCD reconcile.
4. Verify with queries and dashboard checks before declaring done.

Primary config locations in this repo:

- `helm/tempo-values.yaml`
- `helm/grafana-values.yaml`
- `helm/otel-collector-values.yaml`
- `docs/TROUBLESHOOTING.md`

## Service Onboarding Standard

Every onboarded service should include:

1. Resource attributes:
   - `service.name` (stable, human-readable)
   - `service.namespace`
   - `deployment.environment`
   - `cluster=oke-hub` (or relevant spoke label strategy)
2. Trace context propagation:
   - W3C Trace Context (`traceparent`, `tracestate`, `baggage`)
3. Server + client instrumentation:
   - inbound HTTP/gRPC spans
   - outbound HTTP/gRPC/DB/cache spans
4. Error semantics:
   - set span status for failures
   - attach protocol status attributes (HTTP/gRPC)
5. Low-cardinality span attributes:
   - route, operation, component
   - avoid high-cardinality IDs as labels/dimensions

## Rollout Phases and Gates

### Phase 0 - Baseline (Already in place)

- Ingress traces visible in Tempo.
- Service graph metrics present.

Gate:

```promql
sum by (client, server) (rate(traces_service_graph_request_total[5m]))
```

Should show at least one edge.

### Phase 1 - Edge API / Gateway

- Instrument first backend behind ingress.
- Ensure downstream calls carry context.

Gate:
- Service graph shows `ingress-nginx -> <gateway-service>`.
- Tempo search returns traces for gateway `service.name`.

### Phase 2 - Core Service Dependencies

- Instrument core downstream services (auth, orders, payments, etc.).
- Add outbound DB/cache client spans where used.

Gate:

```promql
topk(20, sum by (client, server) (rate(traces_service_graph_request_total[5m])))
```

Should show meaningful service-to-service edges, not only ingress.

### Phase 3 - Workers / Async Paths

- Instrument queue consumers, jobs, cron workers.
- Link async processing with trace context where feasible.

Gate:
- Trace samples include async spans with valid `service.name`.
- Drilldown spans list has useful operation names (not only `<name not yet available>`).

## Dashboard Validation Checklist

1. Grafana Explore -> Tempo -> Service Graph:
   - graph renders with multiple service nodes.
2. Grafana Drilldown -> Traces:
   - no `localblocks processor not found` errors.
   - span rate and trace list populate.
3. Prometheus:
   - service graph and spanmetrics queries return active series.

## Common Failure Patterns

1. Only `user -> ingress-nginx` edge:
   - app services are not instrumented or not propagating context.
2. Service Graph empty but traces exist:
   - metrics generator/remote_write path broken.
3. Drilldown error `localblocks processor not found`:
   - Tempo missing `local-blocks` processor.
4. Trace list full of `<name not yet available>`:
   - spans missing operation names in instrumentation.

## Done Criteria

Tracing rollout for a service/domain is done only when:

1. Service appears as a stable node in Service Graph.
2. At least one meaningful downstream edge exists.
3. Error and latency signals are visible in traces.
4. Runbook/debug workflow can find a failing request trace in under 5 minutes.

## Recommended Target Order (This Cluster)

1. `ingress-nginx` (already done)
2. Edge API / gateway service
3. Auth and shared platform services
4. Core business services
5. Datastore-heavy and async worker services
