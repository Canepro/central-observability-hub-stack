# OKE security posture follow-up

Date: 2026-06-17

This document is the public-safe, source-backed follow-up for the OKE security
posture issues opened after the Infisical migration.

Closing references: Closes #82, Closes #83, Closes #84, Closes #85.

## Scope and safety boundaries

This review is documentation-only. It does not mutate live infrastructure,
rotate or delete credentials, change DNS, change firewall rules, edit ingress
policy, rerun SignalForge, or inspect secret values.

Secret names, Kubernetes object names, Infisical store names, and public
hostnames are included where they are already present in issue text or repo
source. Secret values are intentionally omitted.

## Source evidence

| Evidence | Source |
|---|---|
| Post-Infisical findings and acceptance criteria | GitHub issues #82, #83, #84, #85 |
| App-of-apps sync and self-heal are enabled | `argocd/bootstrap-oke.yaml` |
| Argo CD RBAC policy is source-managed | `argocd/applications/argocd-rbac.yaml`, `k8s/argocd-rbac-config.yaml` |
| Canepro spoke AppProject is source-managed | `argocd/applications/canepro-spoke-project.yaml` |
| Public ingress controller is source-managed as an OCI NLB | `argocd/applications/nginx-ingress.yaml`, `helm/nginx-ingress-values.yaml` |
| Grafana, Jenkins, and observability ingress are source-managed | `k8s/grafana-ingress.yaml`, `helm/jenkins-values.yaml`, `k8s/jenkins/jenkins-canepro-ingress.yaml`, `k8s/observability-ingress-secure.yaml` |
| External Secrets Operator config is source-managed | `argocd/applications/external-secrets.yaml`, `argocd/applications/external-secrets-config.yaml`, `helm/external-secrets-values.yaml`, `k8s/external-secrets/*.yaml` |
| Grafana, Jenkins, Loki, Tempo, and observability consumers reference Kubernetes Secrets by name | `helm/grafana-values.yaml`, `helm/jenkins-values.yaml`, `helm/loki-values.yaml`, `helm/tempo-values.yaml`, `k8s/observability-ingress-secure.yaml` |

## RBAC posture review (#82)

The issue reports SignalForge RBAC findings for broad access held by
`argocd-application-controller`, `argocd-server`, `system:masters`, and default
`admin` impersonation. This repo proves the Argo CD policy layer and AppProject
layer. It does not prove the full live ClusterRole/ClusterRoleBinding set
installed by the Argo CD chart or bootstrap process.

| Finding | Current classification | Source-backed reason | Hardening or rollback note |
|---|---|---|---|
| `system:masters` broad access | Accepted platform/bootstrap finding | Issue #82 says not to remove `system:masters`; this repo does not source-manage that group. | Treat as OKE or bootstrap access outside this repo. Revisit only through a platform access review, not this GitOps repo. |
| Local `admin` mapped to Argo CD `role:admin` | Source-managed hardening candidate | `k8s/argocd-rbac-config.yaml` maps `g, admin, role:admin` and comments that it stays until SSO and break-glass recovery are proven. | Stage removal only after Entra SSO and a separate break-glass path are tested. Rollback is re-adding the mapping and syncing `argocd-rbac`. |
| Entra admin group mapped to Argo CD `role:admin` | Accepted with review cadence | `k8s/argocd-rbac-config.yaml` maps one Entra group id to `role:admin`. This is narrow at the identity group layer, but broad inside Argo CD. | Keep while admin operators need full GitOps control. Revisit by adding narrower roles for read-only, app sync, and project admin duties. |
| Argo CD `role:admin` wildcard permissions | Source-managed hardening candidate | `k8s/argocd-rbac-config.yaml` grants `role:admin` wildcard access over applications, clusters, projects, repositories, accounts, gpgkeys, and certificates. | Add least-privilege roles before reducing `role:admin`. Dry-run by applying RBAC config in a test branch and checking login, app view, app sync, repo access, and rollback admin access. |
| `argocd-application-controller` Kubernetes RBAC | Deferred | The controller reconciles all apps in this stack and likely needs broad Kubernetes permissions for cluster-scoped resources. This repo does not contain its chart RBAC manifests. | Do not narrow the controller ClusterRole live. First capture rendered Argo CD RBAC, map required API groups from all Applications, stage chart values or overlays in source, then verify Argo app health. |
| `argocd-server` Kubernetes RBAC | Deferred | Issue #82 reports the finding, but this repo only sources Argo CD policy config, not the live server ClusterRole. | Same staging path as the controller. Rollback must restore the previous chart or overlay RBAC in Git before sync. |
| All hub Applications use AppProject `default` | Source-managed hardening candidate | `argocd/bootstrap-oke.yaml` and the hub app manifests use `spec.project: default`. | Create a dedicated `oke-hub` AppProject with allowed source repos, namespaces, and cluster resource allowlist. Rollback is moving Applications back to `default`. |
| `canepro-spoke` AppProject permits all cluster resources | Source-managed hardening candidate | `argocd/applications/canepro-spoke-project.yaml` limits repos and destinations, but `clusterResourceWhitelist` is `*/*`. | Replace the wildcard with the exact cluster-scoped resources needed by the spoke apps after a rendered manifest review. Rollback is restoring `*/*`. |

### RBAC staging checklist

1. Render or export current Argo CD ClusterRoles, RoleBindings, and
   ClusterRoleBindings without secret values.
2. Build a required-resource matrix from the manifests under `argocd/`, `helm/`,
   `k8s/`, and `dashboards/`.
3. Stage AppProject narrowing first. It is lower risk than service account RBAC
   surgery and can be rolled back in source.
4. Stage Argo CD service account RBAC only after controller and server required
   verbs are proven.
5. Before merge, run dry-run or diff proof and document rollback.
6. After merge, verify Argo Applications are `Synced/Healthy` and keep Selene
   review as the gate before live mutation beyond source-only docs.

## Public ingress decision record (#83)

The source-backed architecture is a single public `ingress-nginx` controller
Service of type `LoadBalancer` using an OCI Network Load Balancer. That is an
accepted current architecture for services that intentionally receive traffic
from outside the OKE cluster. It is still a valid posture finding because admin
surfaces are exposed through the same public edge.

No DNS, firewall, ingress, or edge-auth change is approved by this document.
Those changes require explicit approval for the selected hostname and path.

| Hostname | Current source-backed posture | Decision | Hardening path | Approval gate and rollback |
|---|---|---|---|---|
| `argocd.canepro.me` | Referenced in docs and issue #83, but no matching Ingress manifest was found in this repo during this pass. | Deferred source gap. Treat as an admin surface until proven otherwise. | Bring its ingress or chart values under source if they are not already. Prefer Cloudflare Access, IP allowlist, VPN/private ingress, or split admin ingress. | Approval required before DNS, firewall, ingress, or auth changes. Rollback must preserve an admin access path. |
| `grafana.canepro.me` | `k8s/grafana-ingress.yaml` exposes Grafana through NGINX with TLS from cert-manager. `helm/grafana-values.yaml` sets the Grafana root URL and uses the `grafana` Secret for admin credentials. | Accepted temporarily as public with app auth. Hardening candidate because it is an admin/query UI. | Add identity-aware edge auth, source IP restrictions, or a private/admin ingress split. Keep Grafana auth intact. | Approval required before any allowlist or edge-auth change. Rollback is reverting the ingress annotations or edge policy and confirming Grafana login. |
| `jenkins.canepro.me` | `k8s/jenkins/jenkins-canepro-ingress.yaml` exposes Jenkins with TLS. `helm/jenkins-values.yaml` sets Jenkins URL and uses `jenkins-admin-credentials`. | Accepted temporarily as public with Jenkins auth. Strong hardening candidate because it is an admin/CI surface. | Prefer Cloudflare Access or IP allowlist for UI paths. Keep webhook and agent behavior in scope before blocking paths. | Approval required before DNS, firewall, ingress, or edge-auth change. Rollback is reverting ingress or edge policy and confirming UI, webhook, and agent access. |
| `observability.canepro.me` | `k8s/observability-ingress-secure.yaml` exposes remote write, Loki push/query, and OTLP traces with TLS plus NGINX basic auth from `observability-auth`. | Accepted public ingestion endpoint with compensating controls. Hardening path is narrower than admin UIs because external clusters need access. | Keep TLS and basic auth. Consider client IP allowlists only if source IPs are stable. Consider splitting ingestion paths from query paths if server-side readers can use a narrower route. | Approval required before path restrictions or firewall changes. Rollback is reverting ingress changes and confirming remote write, Loki push/query, and OTLP trace ingestion. |

Additional source-backed note: `helm/jenkins-values.yaml` also defines
`jenkins-oke.canepro.me`. If it still resolves publicly, treat it with the same
admin-surface posture as `jenkins.canepro.me` before removing or gating it.

### Public ingress hardening order

1. Confirm which hostnames resolve to the OKE NLB and which Ingress object owns
   each hostname.
2. Harden admin surfaces before ingestion surfaces: Argo CD, Jenkins, then
   Grafana.
3. Preserve external telemetry ingestion for `observability.canepro.me` unless
   a replacement route exists.
4. Make changes through GitOps source, not live-only patches.
5. Post-change proof must include Argo health, endpoint reachability, and
   expected auth behavior.
6. SignalForge rerun is outside this document and requires separate approval.

## Infisical cleanup and rotation plan (#84)

The repo currently sources four Infisical `ClusterSecretStore` objects and 11
ExternalSecrets:

- `infisical-oke`: `argocd/argocd-oidc-client-secret`
- `infisical-oke-monitoring`: `monitoring/grafana`,
  `monitoring/grafana-smtp-credentials`, `monitoring/loki-s3-credentials`,
  `monitoring/oci-s3-creds`, `monitoring/observability-auth`
- `infisical-oke-jenkins`: `jenkins/jenkins-admin-credentials`,
  `jenkins/github-token`, `jenkins/pipelinehealer-bridge-secret`,
  `jenkins/pipelinehealer-bridge-url`
- `infisical-oke-signalforge`: `signalforge/signalforge-agent-token`

Cleanup must stay separate from migration rollback. Delete or revoke only after
explicit approval, redacted proof, and a rollback path are recorded.

| Source class | Owner | Current consumer class | Risk | Decision gate | Rollback path |
|---|---|---|---|---|---|
| OCI Vault rollback values behind `oci-vault` | OCI Vault owner / platform operator | Former source for migrated OKE values; current source should be Infisical through ESO | Stale parallel source can be reused by mistake or drift from Infisical | Keep until each replacement ExternalSecret has runtime confidence and owner approval. Delete only through the cleanup gate. | Preserve value availability in the private control plane until replacement smoke proof passes. Restore by re-pointing ESO or manually recreating the prior Kubernetes Secret through the approved private path. |
| Manual or fallback Kubernetes Secrets for migrated consumers | Kubernetes platform owner | App credentials now expected from ESO-owned target Secrets | Manual objects can mask ESO failure or preserve old values | For each target, confirm `ExternalSecret Ready=True`, owner reference or ESO ownership, and live consumer success before deletion. | Recreate the prior Secret only from the approved private source. Do not recover from chat, reports, or Git. |
| Entra OIDC client secret copied into Kubernetes/Infisical | Entra app owner and Argo CD owner | Argo CD OIDC via `argocd-oidc-client-secret` | Copied provider value remains valid until rotated | Rotate during a planned Argo CD auth window after confirming break-glass access. | Keep the old provider credential active until OIDC login smoke passes with the new one. Roll back by reactivating the previous provider credential through Entra if still within the planned window. |
| Infisical ESO service tokens | Infisical project owner and Kubernetes platform owner | `ClusterSecretStore` auth Secrets: `infisical-oke-auth`, `infisical-oke-monitoring-auth`, `infisical-oke-jenkins-auth`, `infisical-oke-signalforge-auth` | Long-lived tokens become durable blast radius if copied or over-scoped | Rotate one store at a time. Verify store `Ready=True/Valid` and all dependent ExternalSecrets `Ready=True/SecretSynced` before moving to the next. | Keep the prior token available in the private control plane until all dependents resync, then revoke after approval. |
| Provider credentials now stored in Infisical | Credential owner for each provider | Grafana SMTP, object storage, Jenkins GitHub, PipelineHealer bridge, observability basic auth, SignalForge token | Provider-side value may predate migration and should not be treated as freshly rotated | Rotate by provider class with a consumer-specific smoke test. Do not batch unrelated providers. | Keep old provider credential active until the consumer smoke passes, then revoke only with owner approval. |
| Deferred/generated Secrets from issue #85 | Owning controller or platform owner | Control-plane internals, TLS, Helm metadata, non-consumer pull secret | Blind deletion can break controllers or remove audit history | Use the ownership map below. Delete-candidates still require the cleanup gate. | Restore from controller regeneration, Helm release history, or approved private source depending on class. |

### Cleanup execution checklist

1. Inventory source names only. Do not print values.
2. For each candidate, record owner, consumer, replacement source, smoke test,
   rollback source, and approval.
3. Rotate before deleting when the old value may still be valid at the provider.
4. Delete old rollback sources only after replacement proof survives the agreed
   confidence window.
5. Record deleted or revoked sources by namespace/name, store, and provider
   class only. Never record values.
6. Require Selene review before destructive cleanup.

## Deferred and generated Secret ownership map (#85)

This map exists to prevent future agents from migrating controller-owned or
unused Secrets into Infisical without checking ownership first.

| Namespace/name pattern | Owner/controller | Current consumer class | Deferral reason | Status | Prerequisite before Infisical candidacy |
|---|---|---|---|---|---|
| `signalforge/signalforge-agent-regcred` | Historical or manual image pull Secret | Issue #85 says the live `signalforge-agent` Deployment does not reference it through `imagePullSecrets` | Not referenced by the live consumer | `delete-candidate` | Reconfirm live Deployment and Helm values have no reference, then handle deletion through #84 cleanup gate. |
| `argocd/*` with Argo cluster or repo secret labels | Argo CD | Argo cluster and repository access | Argo-managed control-plane access material | `control-plane-defer` | Manage through Argo CD cluster/repository onboarding or offboarding, not generic Infisical migration. |
| `argocd/argocd-secret`, `argocd/argocd-initial-admin-secret`, session or server internals | Argo CD chart/runtime | Argo CD runtime | Bootstrap, session, signing, or runtime internals may be chart-generated or controller-managed | `generated-do-not-migrate` | Only change through the Argo CD chart/runtime procedure with tested break-glass access. |
| `argocd/argocd-oidc-client-secret` | External Secrets Operator from Infisical | Argo CD OIDC | Already migrated and source-managed by `k8s/external-secrets/argocd-oidc-client-secret-externalsecret.yaml` | `generated-do-not-migrate` for manual migration; current owner is ESO | Rotate through #84 Entra OIDC rotation path, not by manually editing the Kubernetes Secret. |
| `monitoring/grafana` | External Secrets Operator target plus Grafana chart interaction | Grafana admin credentials and secret key | Already migrated to ESO, while Argo ignores selected chart-generated drift | `generated-do-not-migrate` for manual migration; current owner is ESO | Change Infisical source and allow ESO to sync. Do not hand-edit live Secret values. |
| `jenkins/jenkins` | Jenkins chart/runtime | Legacy or chart-generated Jenkins material | `argocd/applications/jenkins.yaml` ignores this Secret data so live admin material is not overwritten by chart-generated desired state | `generated-do-not-migrate` | Confirm whether any live consumer still reads it before deletion. Preferred active admin source is `jenkins/jenkins-admin-credentials`. |
| `jenkins/jenkins-admin-credentials` | External Secrets Operator from Infisical | Jenkins admin login | Already migrated and consumed by `helm/jenkins-values.yaml` | `generated-do-not-migrate` for manual migration; current owner is ESO | Rotate through Infisical and Jenkins smoke proof. |
| `monitoring/*-tls`, `jenkins/*-tls`, and other cert-manager TLS Secrets | cert-manager | Ingress TLS termination | Generated certificates, not secret-manager payloads | `generated-do-not-migrate` | Change issuer or Ingress source if certificate behavior must change. Do not import cert-manager outputs into Infisical. |
| `*/sh.helm.release.v1.*` | Helm | Helm release metadata | Release state, not application credentials | `generated-do-not-migrate` | Manage through Helm or Argo CD lifecycle only. Do not migrate to Infisical. |
| `external-secrets/infisical-oke*-auth` | Platform owner / Infisical token issuer | ESO `ClusterSecretStore` auth | Bootstrap credentials for ESO itself, not ExternalSecret payloads | `future-candidate` for rotation governance, not migration | Rotate one store token at a time through #84. Do not print token values. |
| `monitoring/observability-auth` | External Secrets Operator from Infisical | NGINX basic auth for observability ingress | Already migrated and consumed by `k8s/observability-ingress-secure.yaml` | `generated-do-not-migrate` for manual migration; current owner is ESO | Rotate through Infisical, then smoke remote write, Loki push/query, and OTLP trace paths. |
| `monitoring/loki-s3-credentials` and `monitoring/oci-s3-creds` | External Secrets Operator from Infisical | Loki and Tempo object storage clients | Already migrated; used by `helm/loki-values.yaml` and `helm/tempo-values.yaml` | `generated-do-not-migrate` for manual migration; current owner is ESO | Rotate object storage credentials with read/write smoke proof before revocation. |
| `jenkins/github-token`, `jenkins/pipelinehealer-bridge-secret`, `jenkins/pipelinehealer-bridge-url` | External Secrets Operator from Infisical | Jenkins credentials provider | Already migrated and labeled/annotated for Jenkins credentials | `generated-do-not-migrate` for manual migration; current owner is ESO | Rotate provider-side values with Jenkins job or credential smoke proof. |
| `signalforge/signalforge-agent-token` | External Secrets Operator from Infisical | SignalForge agent token | Already migrated and owned by ESO | `generated-do-not-migrate` for manual migration; current owner is ESO | Rotate only with explicit approval. Do not run or scale SignalForge from this repo task. |

## Review gates

- RBAC narrowing: requires rendered RBAC proof, Argo diff or dry-run proof, a
  rollback commit path, and Selene review before live mutation.
- Public ingress changes: require explicit approval for DNS, firewall, ingress,
  or edge-auth changes by hostname.
- Cleanup or rotation: requires owner approval, private rollback source, redacted
  before/after smoke proof, and Selene review before destructive action.
- SignalForge: no rerun, scale-up, or agent changes are approved by this
  document.
