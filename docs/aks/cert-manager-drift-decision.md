# AKS cert-manager drift decision

Status: Routed out of this repo; field-level diff identified

Issue: [#88](https://github.com/Canepro/central-observability-hub-stack/issues/88)

Closing reference: Closes #88 for the GrafanaLocal tracker.

## Classification

`aks-cert-manager` is a live AKS GitOps drift, but this repo is not the source
owner for the `aks-cert-manager` Argo CD Application manifest.

Current classification: needs source-backed handling in the owner repo. Do not
add an `ignoreDifferences` rule in this repo. The known drifted resource is
cluster-scoped:
`admissionregistration.k8s.io/ValidatingWebhookConfiguration/cert-manager-webhook`.

## Evidence

- Issue #88 says the 2026-06-15 OKE observability run found
  `aks-cert-manager` as `Healthy/OutOfSync` while AKS was `Running`.
- `reports/2026-06-15-weekly-oke-observability.html` records the same
  classification: AKS was online, only `aks-cert-manager` was drifted, and the
  drift is not the parked-cluster blind spot.
- `reports/2026-06-15-weekly-oke-observability.html` also records the ownership
  boundary: the AKS app manifests do not live in this repo; the active source is
  `/Users/canepro/src/rocketchat-k8s`.
- `reports/2026-06-17-weekly-oke-observability.html` kept issue #88 open until
  this ownership decision existed, and warned not to force-sync or prune until
  cluster-scoped cert-manager ownership and the failed sync task were reviewed.
- `argocd/applications/canepro-spoke-project.yaml` in this repo only grants the
  `canepro-spoke` AppProject access to `https://github.com/Canepro/rocketchat-k8s.git`
  and the AKS `cert-manager` destination. It does not define
  `aks-cert-manager`.
- The owner manifest is
  `/Users/canepro/src/rocketchat-k8s/GrafanaLocal/argocd/applications/aks-cert-manager.yaml`.
  It deploys Jetstack `cert-manager` chart `v1.20.0` to the AKS API server with
  automated prune and self-heal enabled.
- `/Users/canepro/src/rocketchat-k8s/reports/2026-06-17-weekly-aks-maintenance.html`
  says the app was not force-synced because it includes cluster-scoped
  cert-manager resources and has prune-capable policy.
- The 2026-06-29 OKE maintenance run verified Azure MCP state:
  `rg-canepro-aks/aks-canepro` was `Running`, provisioning `Succeeded`, with
  node pool `system2` running 2 nodes.
- A hard Argo refresh plus a non-prune Argo sync against `v1.20.0` cleared the
  stale March DNS sync failure, but the app remained `Healthy/OutOfSync`.
- Read-only AKS live evidence showed the live webhook matches desired webhook
  behavior: service `cert-manager-webhook`, path `/validate`, `failurePolicy:
  Fail`, `matchPolicy: Equivalent`, `sideEffects: None`, and `timeoutSeconds:
  30`.
- The remaining known diff is the injected `webhooks[].clientConfig.caBundle`
  on the live webhook. That field is populated by cert-manager CA injection and
  is absent from the rendered Helm desired state.

## Decision

Do not edit `argocd/applications/*` in this repo for this drift. This repo owns
the OKE observability hub and the AppProject permission boundary for the AKS
spoke. It does not own the `aks-cert-manager` Application desired state.

The current evidence supports treating the remaining diff as cert-manager
CA-injection drift, not webhook behavior drift. The source-backed fix still
belongs in the owner repo, because this repo does not own the
`aks-cert-manager` Application manifest.

## Gated next step

Run the next fix from the owner repo:

```bash
cd /Users/canepro/src/rocketchat-k8s
argocd app diff aks-cert-manager --resource admissionregistration.k8s.io:ValidatingWebhookConfiguration:cert-manager-webhook
```

If the diff is still limited to `webhooks[].clientConfig.caBundle`, add a
narrow `ignoreDifferences` rule in
`GrafanaLocal/argocd/applications/aks-cert-manager.yaml` in the
`rocketchat-k8s` repo. Ignore only that field on
`admissionregistration.k8s.io/ValidatingWebhookConfiguration/cert-manager-webhook`.

If the diff changes webhook semantics, CA injection, service reference, failure
policy, namespace/object selectors, or admission rules, treat it as a real
source-fix candidate in `rocketchat-k8s` and reconcile the chart values or
manifest source there.

Do not run prune, force sync, delete, rollback, chart upgrades, Azure cluster
changes, or Kubernetes writes as part of the weekly OKE observability pass.
