# Argo CD Runbook (This Repo / OKE Observability Stack)

This repo uses an **App-of-Apps** pattern:

- Parent app: `oke-observability-stack` (in `argocd` namespace)
- Child apps (in `argocd/applications/`): `grafana`, `prometheus`, `loki`, `tempo`, `promtail`, `nginx-ingress`

All applications are managed by Argo CD with `prune: true` and `selfHeal: true`.

## How to think about updates

- **Edit repo files** (`helm/*.yaml`, `k8s/*.yaml`, `argocd/applications/*.yaml`)
- **Commit + push**
- **Sync** the appropriate Argo CD Application

Because `selfHeal` is enabled, manual “hotfixes” done directly in the cluster may be overwritten unless they are also committed to Git.

## Common operations

### Sync (apply latest Git state)

Sync the parent app (updates all child apps):

```bash
kubectl -n argocd patch application oke-observability-stack --type merge \
  -p '{"operation":{"sync":{"prune":true}}}'
```

Sync a single child app (recommended for isolated changes):

```bash
kubectl -n argocd patch application loki --type merge \
  -p '{"operation":{"sync":{"prune":true}}}'
```

### Hard refresh (clear “cached manifest” issues)

If Argo shows errors like “Manifest generation error (cached) …”, force a hard refresh:

```bash
kubectl -n argocd annotate application loki argocd.argoproj.io/refresh=hard --overwrite
```

Then sync again.

### Check status and error reasons

Quick status:

```bash
kubectl -n argocd get application loki -o jsonpath='{.status.sync.status}{"\n"}{.status.health.status}{"\n"}'
```

Detailed conditions (this is where the real root cause usually is):

```bash
kubectl -n argocd get application loki -o jsonpath='{.status.conditions[*].type}{"\n"}{.status.conditions[*].message}{"\n"}'
```

### Update a Helm chart version

Change `targetRevision` in the appropriate Argo Application file, commit, push, then sync that app.

Example:

- `argocd/applications/loki.yaml` → bump `spec.sources[0].targetRevision`

Then:

```bash
kubectl -n argocd patch application loki --type merge -p '{"operation":{"sync":{"prune":true}}}'
```

### Delete and recreate an app (rare)

This removes the Argo Application object. With app-of-apps, it will come back on the next parent sync unless you also delete/remove the YAML under `argocd/applications/`.

```bash
kubectl -n argocd delete application loki
```

### Handling immutable resource upgrades (StatefulSet “Forbidden”)

Kubernetes forbids changing certain StatefulSet fields (like `volumeClaimTemplates`).
Argo will fail with:

`StatefulSet.apps "<name>" is invalid: spec: Forbidden: updates to statefulset spec ... are forbidden`

Fix pattern:

1. Delete the StatefulSet (and PVCs, if you intentionally want to discard that state):

```bash
kubectl -n monitoring delete sts loki --cascade=orphan
kubectl -n monitoring delete pvc storage-loki-0 --ignore-not-found
```

2. Sync the Argo app again:

```bash
kubectl -n argocd patch application loki --type merge -p '{"operation":{"sync":{"prune":true}}}'
```

### “Helm template requires canary enabled”

Some Loki chart versions enforce a validation rule that requires Loki Canary to be enabled.
If Argo shows:

`Error: ... validate.yaml ... Helm test requires the Loki Canary to be enabled`

Set in `helm/loki-values.yaml`:

```yaml
lokiCanary:
  enabled: true
```

Commit, push, hard refresh, sync again.

## OCI / OKE authentication gotchas

### OCI CLI auth mode can break kubectl (security_token_file)

If you see:

`ERROR: Config value for 'security_token_file' must be specified when using --auth security_token`

Your environment variables are forcing OCI session auth. Unset them:

```bash
unset OCI_CLI_AUTH OCI_CLI_SECURITY_TOKEN_FILE OCI_CLI_SESSION_EXPIRATION
```

Then retry `kubectl`.

### Kubeconfig moved out of ~/.kube

If your kubeconfig is stored elsewhere (example: `/mnt/d/secrets/kube/config`):

```bash
export KUBECONFIG=/mnt/d/secrets/kube/config
```

## Recommended workflow for this repo

- **Small change** (values, ingress tweaks): edit → commit → sync that app.
- **Wide change** (multiple apps): edit → commit → sync parent app (`oke-observability-stack`).
- If Argo “looks stuck”: check `.status.conditions` and use hard refresh.


