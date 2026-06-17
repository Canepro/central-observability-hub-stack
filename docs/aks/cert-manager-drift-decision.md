# AKS cert-manager drift decision

Status: Routed out of this repo; needs live diff in the owner repo

Issue: [#88](https://github.com/Canepro/central-observability-hub-stack/issues/88)

Closing reference: Closes #88 for the GrafanaLocal tracker.

## Classification

`aks-cert-manager` is a live AKS GitOps drift, but this repo is not the source
owner for the `aks-cert-manager` Argo CD Application manifest.

Current classification: needs live diff before a source fix. Do not add an
`ignoreDifferences` rule or force-sync from this repo based only on the app
summary. The known drifted resource is cluster-scoped:
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

## Decision

Do not edit `argocd/applications/*` in this repo for this drift. This repo owns
the OKE observability hub and the AppProject permission boundary for the AKS
spoke. It does not own the `aks-cert-manager` Application desired state.

Do not classify the drift as harmless controller-managed/defaulted noise yet.
The current evidence identifies the drifted resource, but it does not include
the desired-vs-live field diff. Without that field-level diff, a narrow
`ignoreDifferences` rule would be a guess.

## Gated next step

Run the next investigation from the owner repo, read-only first:

```bash
cd /Users/canepro/src/rocketchat-k8s
argocd app diff aks-cert-manager --resource admissionregistration.k8s.io:ValidatingWebhookConfiguration:cert-manager-webhook
argocd app get aks-cert-manager -o json
```

If the diff is limited to controller-managed or Kubernetes-defaulted fields,
add a narrow `ignoreDifferences` rule in
`GrafanaLocal/argocd/applications/aks-cert-manager.yaml` in the
`rocketchat-k8s` repo. Ignore only the exact diffed fields.

If the diff changes webhook semantics, CA injection, service reference, failure
policy, namespace/object selectors, or admission rules, treat it as a real
source-fix candidate in `rocketchat-k8s` and reconcile the chart values or
manifest source there.

Do not run prune, force sync, delete, rollback, chart upgrades, Azure cluster
changes, or Kubernetes writes as part of the weekly OKE observability pass.
