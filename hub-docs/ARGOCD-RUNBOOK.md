# Argo CD Runbook (This Repo / OKE Observability Stack)

This repo uses an **App-of-Apps** pattern:

- Parent app: `oke-observability-stack` (in `argocd` namespace)
- Child apps (in `argocd/applications/`): `grafana`, `prometheus`, `loki`, `tempo`, `promtail`, `nginx-ingress`

All applications are managed by Argo CD with `prune: true` and `selfHeal: true`.

## Initial Setup & Access

### Retrieve Admin Password
If you need the initial admin password for the ArgoCD UI:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d ; echo
```

## How to think about updates

- **Edit repo files** (`helm/*.yaml`, `k8s/*.yaml`, `argocd/applications/*.yaml`)
- **Commit + push**
- **Sync** the appropriate Argo CD Application

Because `selfHeal` is enabled, manual “hotfixes” done directly in the cluster may be overwritten unless they are also committed to Git.

## ⚠️ Public repo + Auto-Sync on `main` (risk & mitigations)
If ArgoCD tracks the `main` branch with auto-sync enabled, then **every push to GitHub can trigger reconciliation**.
That’s convenient for a lab/test cluster, but it can surprise you when you do “portfolio cleanup” commits.

**Mitigations (choose one)**
- **Prefer**: use tags as a rollback safety net (`v1.0.0-stable`, `v1.0.1`, etc.) and sync an app to a known-good tag when needed.
- **UI safety switch**: temporarily disable Auto-Sync for an app before making risky edits (ArgoCD UI → Application → toggle **Auto-Sync** off).
- **Operational discipline**: treat changes under `argocd/` and `helm/` as “deploy changes” and validate after sync with `./scripts/validate-deployment.sh`.

## Common operations

### Sync (apply latest Git state)

Sync the parent app (updates all child apps):

```bash
kubectl -n argocd patch application oke-observability-stack --type merge \
  -p '{"operation":{"sync":{"prune":true}}}'
```

### Sync a specific app to a git tag / revision
Useful for “get me back to a known good state” without changing ArgoCD’s tracked branch:

```bash
argocd app sync <app-name> --revision v1.0.0-stable
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

### ArgoCD CLI flag differences (version gotchas)

Depending on your `argocd` CLI version, some flags may not exist (for example `argocd app sync --server-side-apply` or `argocd app diff --resource`).

- Prefer **manifest-driven** behavior (e.g., `syncOptions: [ServerSideApply=true]`) rather than CLI flags.
- If a flag errors as “unknown flag”, use the UI or a plain `argocd app sync <app> --grpc-web`.

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

#### Pattern A: Orphan-delete (safe for keeping data)

Use this when you want to delete the controller object but **keep Pods and PVCs** intact, then let ArgoCD recreate/adopt.

Example (Prometheus Alertmanager):

```bash
# Run against the HUB cluster (OKE) where Prometheus lives
kubectl -n monitoring delete sts prometheus-alertmanager --cascade=orphan

# Force ArgoCD to re-read Git and reconcile
kubectl -n argocd annotate application prometheus argocd.argoproj.io/refresh=hard --overwrite
argocd app sync prometheus --grpc-web
```

If ArgoCD still shows “OutOfSync” but the resource is Healthy, it’s usually a **diff-noise** issue (defaults / null fields).

#### Pattern B: Delete + (optionally) delete PVCs (destructive)

Delete the StatefulSet (and PVCs, if you intentionally want to discard that state):

```bash
kubectl -n monitoring delete sts loki --cascade=orphan
kubectl -n monitoring delete pvc storage-loki-0 --ignore-not-found
```

Sync the Argo app again:

```bash
kubectl -n argocd patch application loki --type merge -p '{"operation":{"sync":{"prune":true}}}'
```

#### Preventing recurring “OutOfSync” noise for a specific StatefulSet

If a StatefulSet remains Healthy but ArgoCD reports OutOfSync due to Kubernetes defaulted fields in `volumeClaimTemplates`, add a targeted `ignoreDifferences` rule to the Argo Application manifest.

Example (only ignore the problematic field for Alertmanager):

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: StatefulSet
      name: prometheus-alertmanager
      jsonPointers:
        - /spec/volumeClaimTemplates
```

### Grafana can look Degraded during rollouts (RWO PVC attach contention)

If Grafana uses a **ReadWriteOnce** PVC, the default **RollingUpdate** strategy can lead to a second Grafana pod getting stuck in `Init:0/2` / `PodInitializing` because the PVC is still mounted by the old pod.

**Preferred fix**: keep `type: RollingUpdate` but set `maxSurge: 0` (and `maxUnavailable: 1`). This forces “delete old → create new” behavior while staying compatible with the chart/template and avoids a stuck “extra” pod (brief downtime during rollout).

### Suppress harmless “OutOfSync” drift on Grafana Secret metadata
After Helm/chart upgrades, ArgoCD may show `OutOfSync` for `Secret/monitoring/grafana` due to controller-managed metadata labels like:
- `app.kubernetes.io/managed-by: Helm`

This label is **informational** and does not change Grafana behavior. If ArgoCD keeps reporting drift but the app is Healthy, use a *targeted* ignore rule in `argocd/applications/grafana.yaml`:
- Only ignore `.metadata.labels."app.kubernetes.io/managed-by"`
- Do **not** ignore secret `data` fields (that could hide real drift)

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


