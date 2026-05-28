# Argo CD Entra OIDC Cutover Runbook

This public-safe runbook captures the repeatable path used to move Argo CD from
local admin-only access to Microsoft Entra OIDC, prove SSO, and then disable the
local admin account in a separate change.

Because this repository is public, keep secret values and private operational
metadata out of this file. The source manifests necessarily contain non-secret
deployment identifiers such as OIDC issuer/client ID and RBAC group object ID.
Do not add extra credential paths, screenshots, raw token output, secret IDs, or
human-account details here.

## Current Configuration

| Item | Location |
| --- | --- |
| Argo CD URL and callback | `terraform/argocd-auth.tf` |
| Entra issuer and client ID | `terraform/argocd-auth.tf` |
| Admin group mapping | `k8s/argocd-rbac-config.yaml` |
| Kubernetes secret reference | `terraform/argocd-auth.tf` |
| Private secret storage path | private operator notes / Infisical metadata, not this public repo |

## Safety Boundary

- Keep `argocd_local_admin_enabled=true` only until SSO login and admin access
  are proven in the browser.
- Do not print, commit, paste, screenshot, or log the Entra client secret value.
- Store the client secret in the approved secret manager and inject it into
  Kubernetes without exposing the value.
- Do not change DNS, firewall, ingress, or local admin disablement in the same
  change as initial SSO enablement.
- Treat disabling local admin as a separate PR after rollback access is clear.

## Source Files

- `terraform/argocd-auth.tf`: Argo OIDC knobs and current Entra defaults.
- `terraform/argocd.tf`: Helm `configs.cm` wiring for `argocd-cm`.
- `k8s/argocd-rbac-config.yaml`: Argo RBAC group mapping.
- `hub-docs/ARGOCD-RUNBOOK.md`: steady-state access notes.
- `GITOPS-HANDOVER.md`: high-level GitOps access posture.

## Entra App Requirements

The app registration must have:

- `signInAudience=AzureADMyOrg`
- redirect URI `https://argocd.canepro.me/auth/callback`
- `groupMembershipClaims=SecurityGroup`
- ID token issuance enabled
- access token implicit grant disabled
- admin group membership for the operator account

Metadata checks. Fill placeholders from the current source/private operator
notes:

```bash
az ad app show \
  --id <argocd-entra-client-id> \
  --query '{displayName:displayName,appId:appId,signInAudience:signInAudience,groupMembershipClaims:groupMembershipClaims,redirectUris:web.redirectUris,implicitGrant:web.implicitGrantSettings}' \
  -o json

az ad group member check \
  --group <argocd-admin-group-object-id> \
  --member-id <operator-user-object-id> \
  -o json
```

## Client Secret Rotation And Staging

The value must be the client secret value, not the secret ID. Write it without a
trailing newline.

```bash
PROJECT_ID="<infisical-project-id>"
SECRET_FILE="$(mktemp)"
trap 'rm -f "$SECRET_FILE"' EXIT
umask 077

az ad app credential reset \
  --id <argocd-entra-client-id> \
  --append \
  --display-name "argocd-oke-oidc-$(date +%Y-%m-%d)" \
  --years 1 \
  --query password -o tsv | tr -d '\r\n' > "$SECRET_FILE"

infisical secrets set "ARGOCD_OIDC_CLIENT_SECRET=@${SECRET_FILE}" \
  --env <env> \
  --path <private-argocd-secret-path> \
  --projectId "$PROJECT_ID" \
  --silent >/dev/null

SECRET_VALUE="$(cat "$SECRET_FILE")"
kubectl -n argocd create secret generic argocd-oidc-client-secret \
  --from-literal=clientSecret="$SECRET_VALUE" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n argocd label secret argocd-oidc-client-secret \
  app.kubernetes.io/part-of=argocd \
  --overwrite
```

Verify shape only, not value:

```bash
kubectl -n argocd get secret argocd-oidc-client-secret -o json |
  jq -r '{name:.metadata.name,labels:.metadata.labels,has_clientSecret:(.data|has("clientSecret")),clientSecret_b64_len:(.data.clientSecret|length)}'
```

The label is required. Argo resolves `$argocd-oidc-client-secret:clientSecret`
only for Argo-managed secrets labelled `app.kubernetes.io/part-of=argocd`.

## Terraform And GitOps Apply

Validate source first:

```bash
terraform -chdir=terraform fmt -check
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
kubectl apply --dry-run=client -f k8s/argocd-rbac-config.yaml
```

Plan with the live backend:

```bash
AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
terraform -chdir=terraform plan -out=/tmp/argocd-entra-sso.tfplan
```

Apply only when the plan is limited to the Argo CD Helm release OIDC config:

```bash
AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
terraform -chdir=terraform apply -auto-approve /tmp/argocd-entra-sso.tfplan
```

If Terraform applies but fails to save state because OCI Object Storage rejects
AWS chunked encoding, do not run apply again. Push the generated state:

```bash
AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
terraform -chdir=terraform state push errored.tfstate
```

Then verify `terraform plan -detailed-exitcode` returns no changes.

## Live Verification

```bash
kubectl -n argocd rollout status deployment/argocd-server --timeout=120s

kubectl -n argocd get cm argocd-cm argocd-rbac-cm -o json |
  jq -r '.items[] | {name:.metadata.name,admin_enabled:.data["admin.enabled"],has_oidc:(.data|has("oidc.config")),has_expected_group:((.data["policy.csv"] // "") | contains("<argocd-admin-group-object-id>")),scopes:.data.scopes}'

curl -fsSL https://argocd.canepro.me/auth/login |
  perl -0777 -ne 'if (/scope=([^&\"\\]+)/) { print "$1\n" }' |
  head -5
```

Expected:

- `argocd-cm` has OIDC config.
- `admin.enabled` is still `"true"`.
- OIDC requested scopes are `openid`, `profile`, `email`.
- Login URL includes `openid+profile+email+offline_access`, not `groups`.
- `argocd-rbac-cm` has the expected admin group object ID from source.
- Browser login through Entra succeeds and shows admin access.

## Troubleshooting

### `AADSTS650053`: scope `groups` does not exist

Cause: Argo requested `groups` as an OAuth scope. For this Entra app, groups are
emitted as token claims by `groupMembershipClaims=SecurityGroup`; `groups` is
not requested as a Microsoft Graph OAuth scope.

Fix:

- set `argocd_oidc_requested_scopes = ["openid", "profile", "email"]`
- keep `argocd-rbac-cm` `scopes: '[groups]'`
- restart or roll the Argo server after Terraform applies

### `AADSTS7000215`: invalid client secret

Cause: Argo sent a value Entra does not accept. The repeat causes here were:

- Kubernetes secret missing `app.kubernetes.io/part-of=argocd`
- secret value written with a trailing newline
- secret ID used instead of secret value

Fix:

- rotate the client secret value
- store it in Infisical
- write the Kubernetes key with `--from-literal`, not `--from-file`
- label the secret with `app.kubernetes.io/part-of=argocd`
- restart `argocd-server`

### Terraform state upload fails after apply

Cause: OCI Object Storage S3 compatibility rejects AWS chunked encoding.

Fix:

- do not rerun apply
- run `terraform state push errored.tfstate` with
  `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` and
  `AWS_RESPONSE_CHECKSUM_VALIDATION=when_required`
- verify a follow-up plan is clean

## Disable Local Admin

Only after successful SSO login and admin access are proven:

1. Create a separate PR that sets `argocd_local_admin_enabled=false`.
2. Run Terraform validation and plan.
3. Confirm at least one SSO admin can still access Argo.
4. Apply and verify local admin is disabled.

Do not bundle local admin disablement with secret rotation, Entra app changes,
DNS, ingress, firewall, or unrelated GitOps changes. After apply, verify
`argocd-cm` has `admin.enabled=false` and browser SSO still works.
