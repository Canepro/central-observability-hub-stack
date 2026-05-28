# OKE Infisical Secrets Migration

This public repo records the GitOps contract only. Do not commit secret values,
private paths, kubeconfigs, OAuth state, token IDs, screenshots of credentials,
or operator-specific Infisical metadata here.

## Current Secret Delivery

The OKE hub currently uses a mixed model:

| Class | Current delivery | GitOps consumer | Migration posture |
| --- | --- | --- | --- |
| Grafana admin and `secret_key` | External Secrets Operator from OCI Vault | `monitoring/grafana` and `helm/grafana-values.yaml` | Keep live path until an Infisical-backed ESO store is proven |
| Jenkins admin | External Secrets Operator from OCI Vault | `jenkins/jenkins-admin-credentials` and `helm/jenkins-values.yaml` | Candidate for staged Infisical mirror, then source cutover |
| Jenkins GitHub token | External Secrets Operator from OCI Vault | `jenkins/github-token` and Jenkins credentials provider | Candidate after token owner, scope, and rotation path are confirmed |
| PipelineHealer Jenkins bridge values | External Secrets Operator from OCI Vault | `jenkins/pipelinehealer-bridge-*` | Candidate after PipelineHealer consumer smoke is defined |
| Argo CD OIDC client secret | Manual Kubernetes Secret referenced by Argo CD | `argocd/argocd-oidc-client-secret` and `terraform/argocd-auth.tf` | Good first OKE cutover candidate; low shape complexity, clear rollback |
| Grafana SMTP credentials | Manual Kubernetes Secret | `monitoring/grafana-smtp-credentials`, Grafana, Alertmanager | Candidate after mail owner and app-password rotation path are confirmed |
| Loki/Tempo S3 credentials | Manual Kubernetes Secret | `monitoring/loki-s3-credentials`, Loki, Tempo | Candidate after object-storage access key scope and rollback are confirmed |
| Observability basic auth | Manual Kubernetes Secret | `monitoring/observability-auth`, remote-write clients | Higher blast radius; migrate after spoke cutover plan exists |
| TLS and cert-manager secrets | Controller-managed Kubernetes Secrets | cert-manager, ingress controllers | Leave controller-owned; do not migrate values to Infisical |
| Helm release secrets | Helm internal state | Helm/Argo CD | Leave unmanaged by Infisical |
| Argo repo and cluster credentials | Argo-managed Kubernetes Secrets | Argo CD | Handle separately; may include stale or cross-cluster credentials |
| SignalForge agent token and pull secret | Helm/manual Kubernetes Secrets | `signalforge-agent` | Coordinate through SignalForge/Selene runbook before value movement |

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
- current source class such as OCI Vault, manual Kubernetes Secret, Helm, or cert-manager
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
   - Cutover method: sync from Infisical, restart Grafana and Alertmanager,
     prove alert notification config loads without printing values.
   - Rollback: restore the previous Kubernetes Secret shape.

3. **Jenkins OCI Vault-backed secrets**
   - Target shape: keep existing Kubernetes Secret names and Jenkins credential
     IDs.
   - Cutover method: mirror one Jenkins credential family at a time, then switch
     ESO source after Jenkins can still scan and run non-destructive jobs. The
     first source-backed cutover uses the scoped
     `ClusterSecretStore/infisical-oke-jenkins` and preserves existing target
     Secrets.
   - Rollback: switch the ExternalSecret back to OCI Vault.

4. **Loki/Tempo S3 credentials**
   - Target shape: keep `monitoring/loki-s3-credentials` with the current AWS
     SDK-compatible keys.
   - Cutover method: sync from Infisical, restart Loki and Tempo, prove write
     and read paths with status/health checks only.
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

After the Argo OIDC pilot, the next reviewed GitOps cutover moves existing OCI
Vault-backed ESO consumers to Infisical while preserving their live Kubernetes
Secret names and keys:

- `monitoring/grafana`
- `jenkins/jenkins-admin-credentials`
- `jenkins/github-token`
- `jenkins/pipelinehealer-bridge-secret`
- `jenkins/pipelinehealer-bridge-url`

The public repo contains only non-secret store names, folder paths, and remote
key names. Private operator proof owns value staging, service-token creation,
and rollback notes.
