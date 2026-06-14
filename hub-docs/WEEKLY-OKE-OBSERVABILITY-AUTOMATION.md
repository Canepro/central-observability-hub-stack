# Weekly OKE Observability Automation

This runbook defines the weekly Codex automation for the OKE observability hub in
`/Users/canepro/src/GrafanaLocal`.

## Purpose

Once a week, check whether the OKE hub still works, identify updates or queued
repo work, handle safe source-only maintenance, and write a dark-first HTML
report under `reports/`.

The hub contains Grafana, Prometheus, Loki, Tempo, Argo CD, External Secrets,
and related GitOps manifests. AKS data appears in this Grafana view, but the AKS
cluster is cost-parked by default. Missing AKS metrics or Argo CD
`Healthy/Unknown` for `aks-*` apps is not an incident unless Azure or a current
runbook says AKS should be online.

## Weekly Check Order

1. Read `AGENTS.md`, this runbook, `hub-docs/GRAFANA-MCP-SRE.md`, and
   `VERSION-TRACKING.md`.
2. Run a clean-start check with `git status --short --branch`. Do not overwrite,
   revert, or stage unrelated dirty files.
3. Run the deterministic evidence collector:

   ```bash
   python3 scripts/weekly_oke_observability_check.py
   ```

   The script writes JSON evidence to
   `reports/YYYY-MM-DD-weekly-oke-observability-check.json`.
4. Use Grafana MCP as live observability evidence:
   - list datasources and confirm UIDs `prometheus`, `loki`, and `tempo`
   - inspect Grafana alert rules and current alert states
   - query Prometheus for scrape health, OKE nodes, Argo CD app state, workload
     readiness, restarts, PVC capacity, and Tempo span ingest
   - query Loki for recent high-signal errors in `monitoring`, `argocd`,
     `ingress-nginx`, and `external-secrets`
   - search dashboards only when a finding needs dashboard context
5. Escalate to `k8s-sre-triage` when the evidence shows a Kubernetes runtime
   issue, not just an observability symptom:
   - non-ready OKE nodes, unschedulable pods, `CrashLoopBackOff`, `Error`,
     repeated restarts, pending PVCs, mount failures, stuck rollouts, broken
     Services, broken Ingress, DNS/TLS failures, or non-AKS Argo CD apps that
     are unhealthy or blocked
   - use `k8s-sre-triage` to gather Kubernetes evidence, classify the failure
     bucket, choose a GitOps-safe fix path, and verify recovery
   - do not use it for Grafana-only alert logic, scrape-query mistakes, stale
     dashboards, or expected parked AKS visibility; keep those in
     `prometheus-grafana-triage`
6. Use specialist skills only when the weekly evidence points there:
   - `gitops-reconcile` for Argo CD convergence, drift, OutOfSync, prune, or
     self-heal problems
   - `alerting-irm` for alert routing, contact points, silences, notification
     policies, or SLO/IRM behavior
   - `promql` for suspicious PromQL, alert expressions, ratios, or panel query
     logic
   - `loki` for LogQL, log parsing, log pipeline behavior, or log-derived
     metrics
   - `loki-label-analyzer` for slow Loki queries or label strategy problems
   - `prometheus-cardinality-troubleshooter` for high series count, ingest
     pressure, memory pressure, or slow Prometheus queries
   - `infisical-secrets-management` for metadata-only External Secrets or
     Infisical inventory, staging, rotation planning, or source ownership work
   - `ci-pipeline-triage` or `jenkins-sre` for Jenkins, PipelineHealer, or
     GitHub Actions failures
   - `maintainer-orchestrator` for issue/PR prioritization and queue decisions
7. Classify AKS before escalating it:
   - default state: parked or on-demand for cost control
   - use Azure control-plane state as source of truth before calling AKS broken
   - do not start, stop, scale, upgrade, or deploy AKS resources without current
     explicit approval
8. Review open GitHub issues and PRs for
   `Canepro/central-observability-hub-stack`:
   - refresh PR details before deciding readiness
   - for version PRs, check whether they are still current, whether checks pass,
     and whether release notes suggest breaking changes
   - for issues, classify as fixed, actionable, blocked by approval, stale, or
     needs investigation
   - public GitHub actions on Vincent's personal repos are allowed when
     evidence-backed: comments, labels, issue closure, branch pushes, and PR
     merges
   - GitOps source changes that reconcile into OKE are allowed when they are
     evidence-backed, reviewed against this runbook, verified, and include a
     rollback path
   - do not use direct cluster changes as a shortcut around GitOps
9. Check update candidates:
   - compare current pins in `argocd/applications/*.yaml` and
     `VERSION-TRACKING.md` with official release sources or existing automated
     PRs
   - safe source-only updates can be drafted locally when the change is low
     risk and verified
   - chart, values, manifest, dashboard, and documentation updates can be made
     through GitOps when evidence-backed and verified
   - Terraform applies are allowed when the plan was reviewed, the backend and
     workspace are correct, no secret values are printed, the change does not
     cross a hard gate, and rollback is documented
   - Argo CD refresh, sync, and resync actions are allowed when the target app,
     source revision, rendered diff, and expected health result are understood;
     use prune only when the diff proves the deletion is intended
   - ingress changes, RBAC narrowing, secret rotations, and Azure cost-changing
     actions require explicit approval
10. Draft the weekly report as
   `reports/YYYY-MM-DD-weekly-oke-observability.html`.

## Grafana MCP Queries

Use these as the default query set. Adjust only when live labels prove the query
shape is stale.

```promql
count by (cluster, job) (up == 0)
count by (cluster, condition) (kube_node_status_condition{condition="Ready",status="true"})
count by (cluster, health_status, sync_status) (argocd_app_info)
ALERTS{alertstate=~"firing|pending"}
sum by (namespace, pod, phase) (kube_pod_status_phase{phase=~"Pending|Failed|Unknown"})
sum by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total{namespace=~"monitoring|argocd|ingress-nginx|external-secrets"}[24h])) > 0
sum(increase(tempo_distributor_spans_received_total[5m]))
```

```logql
{namespace=~"monitoring|argocd|ingress-nginx|external-secrets"} |~ "(?i)(error|fail|panic|fatal)"
sum(count_over_time({namespace="monitoring"} |~ "Error on ingesting samples with different value but same timestamp" [1h]))
```

## Report Contract

The weekly report must include:

- status: `ok`, `warning`, `fail`, or `blocked`
- OKE cluster health, including nodes, pods, Argo CD apps, External Secrets, and
  storage
- Grafana MCP evidence for Prometheus, Loki, and Tempo
- Kubernetes escalation decision: `k8s-sre-triage` not needed, or used with
  evidence and verification
- AKS expected-state classification and the source used for that classification
- GitHub issue and PR queue, with recommended next action per item
- update candidates, grouped into safe, approval-gated, and blocked
- changes made during the run, including local file paths and verification
- residual risks and explicit approval gates

## Hard Gates

The automation must stop and ask Vincent, or report the required approval in the
HTML report, before any of these actions:

- secret-value reads, exports, rotations, copies, or prints
- Azure AKS start, stop, scale, credential, deployment, or cost-changing action
- direct OCI, DNS, firewall changes, or live Kubernetes mutation that bypasses
  GitOps
- ingress changes, even when source-backed
- RBAC narrowing that could affect reconciliation
- SignalForge scale-up or rerun

Terraform `apply` is allowed when `terraform plan` has been reviewed, the
target backend/workspace is correct, no secret values are exposed, the change
does not cross one of the hard gates above, and rollback is documented.

Argo CD refresh, sync, and resync actions are allowed when the target
application, source revision, rendered diff, and expected health result are
clear. Use prune only when the diff proves the deletion is intended.

Public GitHub comments, labels, issue closure, branch pushes, and PR merges are
allowed on Vincent's personal repos when the automation has enough evidence and
the action does not cross one of the hard gates above. In this GitOps repo,
source-backed changes that Argo CD will reconcile into OKE are the preferred
mutation path, not a live-mutation bypass. Direct cluster changes remain gated.

Safe default work is read-only evidence collection, local report creation,
source-backed GitOps changes with verification, and a concrete recommendation.
