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
6. Classify AKS before escalating it:
   - default state: parked or on-demand for cost control
   - use Azure control-plane state as source of truth before calling AKS broken
   - do not start, stop, scale, upgrade, or deploy AKS resources without current
     explicit approval
7. Review open GitHub issues and PRs for
   `Canepro/central-observability-hub-stack`:
   - refresh PR details before deciding readiness
   - for version PRs, check whether they are still current, whether checks pass,
     and whether release notes suggest breaking changes
   - for issues, classify as fixed, actionable, blocked by approval, stale, or
     needs investigation
   - public GitHub actions on Vincent's personal repos are allowed when
     evidence-backed: comments, labels, issue closure, branch pushes, and PR
     merges
   - treat GitHub actions that change GitOps-managed live state as live
     mutation; those still require explicit approval
8. Check update candidates:
   - compare current pins in `argocd/applications/*.yaml` and
     `VERSION-TRACKING.md` with official release sources or existing automated
     PRs
   - safe source-only updates can be drafted locally when the change is low
     risk and verified
   - major chart upgrades, RBAC narrowing, ingress changes, secret rotations,
     Azure changes, Terraform applies, and Argo CD force syncs require explicit
     approval when they would affect live state
9. Draft the weekly report as
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
- OCI, DNS, firewall, ingress, Terraform apply, or live Kubernetes mutation
- Argo CD force sync or prune beyond read-only observation
- RBAC narrowing that could affect reconciliation
- SignalForge scale-up or rerun

Public GitHub comments, labels, issue closure, branch pushes, and PR merges are
allowed on Vincent's personal repos when the automation has enough evidence and
the action does not cross one of the hard gates above. In this GitOps repo,
merging or pushing a change that Argo CD will reconcile into the cluster counts
as live mutation and remains approval-gated.

Safe default work is read-only evidence collection, local report creation,
source-only draft changes, and a concrete recommendation.
