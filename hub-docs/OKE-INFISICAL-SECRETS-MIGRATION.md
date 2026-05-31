# OKE Infisical Secrets Migration

This public repo records the GitOps contract only. Do not commit secret values,
private paths, kubeconfigs, OAuth state, token IDs, screenshots of credentials,
or operator-specific Infisical metadata here.

## Current Secret Delivery

After the May 28 cutovers, approved live OKE/GitOps consumers sync from
Infisical through External Secrets Operator while keeping their Kubernetes
Secret names and key shapes stable:

| Class | Current delivery | GitOps consumer | Migration posture |
| --- | --- | --- | --- |
| Grafana admin and `secret_key` | External Secrets Operator from Infisical | `monitoring/grafana` and `helm/grafana-values.yaml` | Live, proved by store readiness, ExternalSecret sync, and Grafana health |
| Jenkins admin | External Secrets Operator from Infisical | `jenkins/jenkins-admin-credentials` and `helm/jenkins-values.yaml` | Live, with the Jenkins chart consuming the existing Secret |
| Jenkins GitHub token | External Secrets Operator from Infisical | `jenkins/github-token` and Jenkins credentials provider | Live, with Jenkins credential ID preserved |
| PipelineHealer Jenkins bridge values | External Secrets Operator from Infisical | `jenkins/pipelinehealer-bridge-*` | Live, with Jenkins credential IDs preserved |
| Argo CD OIDC client secret | External Secrets Operator from Infisical | `argocd/argocd-oidc-client-secret` and `terraform/argocd-auth.tf` | Live, with the Argo CD Secret shape preserved |
| Grafana SMTP credentials | External Secrets Operator from Infisical | `monitoring/grafana-smtp-credentials`, Grafana, Alertmanager | Live, with alerting key shape preserved |
| Loki/Tempo S3 credentials | External Secrets Operator from Infisical | `monitoring/loki-s3-credentials`, Loki, Tempo | Live, with object-storage key shape preserved |
| Observability basic auth | External Secrets Operator from Infisical | `monitoring/observability-auth`, remote-write clients | Live, with ingress auth Secret name preserved |
| TLS and cert-manager secrets | Controller-managed Kubernetes Secrets | cert-manager, ingress controllers | Leave controller-owned; do not migrate values to Infisical |
| Helm release secrets | Helm internal state | Helm/Argo CD | Leave unmanaged by Infisical |
| Argo repo and cluster credentials | Argo-managed Kubernetes Secrets | Argo CD | Handle separately; may include stale or cross-cluster credentials |
| SignalForge agent token | External Secrets Operator from Infisical with `creationPolicy: Merge` | `signalforge-agent` | Live transitional cutover; hold chart ownership cleanup for `existingSecret` follow-up |
| SignalForge pull secret | Not referenced by the live Deployment imagePullSecrets | `signalforge-agent-regcred` | Guarded holdout until a source manifest uses it or deletion is explicitly approved |

## Target Model

Use Infisical as the durable source for project/runtime/API/CI/service
credentials. Keep Apple Passwords for human logins. Keep SOPS or controller
ownership where an existing runtime contract depends on it.

For OKE, the preferred live shape is:

1. Store approved secret values in an Infisical project/environment/folder
   selected in private operator notes.
2. Sync those values into Kubernetes through a reviewed External Secrets path.
3. Keep Kubernetes Secret names and keys stable so Helm, Terraform, and Argo CD
   consumers do not need unrelated changes.
4. Cut over one consumer class at a time.
5. Keep the previous source available until rollback is proven.

## Public-Safe Inventory Fields

Public docs and PRs may include:

- Kubernetes namespace and Secret name
- expected key names
- owning controller or consumer
- current source class such as Infisical, Helm, cert-manager, or a retained rollback source
- target store class such as Infisical via ESO
- rollout and rollback steps
- redacted proof shape

Public docs and PRs must not include:

- secret values or base64-decoded payloads
- kubeconfig contents
- private keys
- token IDs or OAuth state
- personal account details
- private Infisical project IDs, service-token values, or local filesystem paths

## Migration Order

1. **Argo CD OIDC client secret**
   - Target shape: keep `argocd/argocd-oidc-client-secret` with key
     `clientSecret` and label `app.kubernetes.io/part-of=argocd`.
   - Cutover method: make an ExternalSecret write the same Secret shape from
     Infisical, restart `argocd-server`, prove Entra login and admin group
     access, then remove the manual source.
   - Rollback: restore the previous Kubernetes Secret shape and restart
     `argocd-server`.

2. **Grafana SMTP credentials**
   - Target shape: keep `monitoring/grafana-smtp-credentials` with keys
     `password`, `user`, `from_address`, and `to_address`.
   - Cutover method: sync from Infisical through
     `ClusterSecretStore/infisical-oke-monitoring`, restart Grafana and
     Alertmanager, prove alert notification config loads without printing
     values.
   - Rollback: restore the previous Kubernetes Secret shape.

3. **Jenkins secrets**
   - Target shape: keep existing Kubernetes Secret names and Jenkins credential
     IDs.
   - Cutover method: mirror one Jenkins credential family at a time, then switch
     ESO source after Jenkins can still scan and run non-destructive jobs. The
     first source-backed cutover uses the scoped
     `ClusterSecretStore/infisical-oke-jenkins` and preserves existing target
     Secrets.
   - Rollback: restore the previous Kubernetes Secret shape or switch the
     ExternalSecret back to the retained rollback source if that rollback source
     still exists.

4. **Loki/Tempo S3 credentials**
   - Target shape: keep `monitoring/loki-s3-credentials` with the current AWS
     SDK-compatible keys.
   - Cutover method: sync from Infisical through
     `ClusterSecretStore/infisical-oke-monitoring`, restart Loki and Tempo,
     prove write and read paths with status/health checks only.
   - Rollback: restore previous Secret source.

5. **Observability remote-write auth and SignalForge agent credentials**
   - Target shape: keep current Secret names until all external consumers have a
     matching cutover plan.
   - Cutover method: coordinate through private operator notes because these
     values affect cross-cluster and Selene/SignalForge workflows.

## Redacted Verification

Acceptable proof:

```bash
kubectl get externalsecrets -A
kubectl get secret -n <namespace> <name> -o json |
  jq '{name:.metadata.name, labels:.metadata.labels, data_keys:(.data|keys)}'
kubectl rollout status deployment/<deployment> -n <namespace>
```

Do not use commands that decode or print secret payloads in PRs, tickets,
handoffs, reports, or shared chat.

## Approval Gates

Metadata inventory, repo docs, and ExternalSecret shape reviews are safe.

These actions need explicit current-task approval:

- reading or copying a secret value from Kubernetes, OCI Vault, SOPS, local
  files, or Infisical
- creating or exporting Infisical service tokens
- rotating provider-side credentials
- making Infisical authoritative for a live consumer
- deleting old secret sources
- changing cross-cluster, SignalForge, or break-glass credential paths

## Argo OIDC Pilot

The first live pilot keeps the existing Argo CD consumer contract and moves the
source of `argocd/argocd-oidc-client-secret` to External Secrets Operator backed
by Infisical:

- store: `ClusterSecretStore/infisical-oke`
- target: `argocd/argocd-oidc-client-secret`
- key: `clientSecret`
- required label: `app.kubernetes.io/part-of=argocd`

Private operator notes own the Infisical auth material and any rollback value.
Public proof should stay limited to store readiness, ExternalSecret readiness,
target Secret key shape, Argo rollout status, and SSO/admin success.

## Existing ESO Consumer Cutover

After the Argo OIDC pilot, the next reviewed GitOps cutover moved existing ESO
consumers to Infisical while preserving their live Kubernetes Secret names and
keys:

- `monitoring/grafana`
- `jenkins/jenkins-admin-credentials`
- `jenkins/github-token`
- `jenkins/pipelinehealer-bridge-secret`
- `jenkins/pipelinehealer-bridge-url`

The public repo contains only non-secret store names, folder paths, and remote
key names. Private operator proof owns value staging, service-token creation,
and rollback notes.

## Manual Monitoring Secret Cutover

The manual monitoring batch moves existing Kubernetes Secrets to Infisical while
preserving their live names and keys:

- `monitoring/grafana-smtp-credentials`
- `monitoring/loki-s3-credentials`
- `monitoring/oci-s3-creds`
- `monitoring/observability-auth`

These are still mounted or referenced by existing Helm values and ingress
annotations. The ExternalSecret manifests intentionally keep the same Secret
names so the application manifests do not need credential reference changes.

## SignalForge Agent Token Cutover

`signalforge/signalforge-agent-token` is managed as a transitional
ExternalSecret from `ClusterSecretStore/infisical-oke-signalforge`.

The target uses `creationPolicy: Merge` because the `signalforge-agent` Helm
release still owns the Secret object contract. This keeps the token key in
Infisical without forcing a Helm chart ownership change in the observability
repo. A later SignalForge-agent chart/source change should switch the release
to `agent.token.existingSecret` so Helm stops rendering token data entirely.

`signalforge/signalforge-agent-regcred` is not referenced by the live
`signalforge-agent` Deployment imagePullSecrets. It is not treated as a live
consumer until a source manifest uses it.
