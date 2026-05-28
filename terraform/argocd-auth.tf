# Argo CD authentication hardening controls.
#
# Defaults preserve the current live bootstrap posture. The safe cutover is:
# 1. choose the identity provider and exact admin group;
# 2. provision Secret argocd/${var.argocd_oidc_client_secret_name} key clientSecret;
# 3. add the approved group mapping to k8s/argocd-rbac-config.yaml;
# 4. enable OIDC and verify login/admin access;
# 5. disable the local admin account in a separate approved change.

variable "argocd_local_admin_enabled" {
  description = "Whether the built-in Argo CD local admin account is enabled. Keep true until SSO login and break-glass recovery are proven."
  type        = bool
  default     = true
}

variable "argocd_oidc_enabled" {
  description = "Enable Argo CD OIDC SSO config. Requires the client secret to already exist in the argocd namespace."
  type        = bool
  default     = true
}

variable "argocd_oidc_name" {
  description = "Display name for the Argo CD OIDC connector."
  type        = string
  default     = "Microsoft Entra ID"
}

variable "argocd_oidc_issuer_url" {
  description = "OIDC issuer URL for Argo CD SSO."
  type        = string
  default     = "https://login.microsoftonline.com/040f4d47-c5be-488d-a48b-4b43fe04cac4/v2.0"

  validation {
    condition     = !var.argocd_oidc_enabled || length(trimspace(var.argocd_oidc_issuer_url)) > 0
    error_message = "argocd_oidc_issuer_url must be set when argocd_oidc_enabled is true."
  }
}

variable "argocd_oidc_client_id" {
  description = "OIDC client ID for Argo CD SSO. This is not a secret."
  type        = string
  default     = "e1b5f345-dbd8-4e1e-a138-1c8fdb91fed9"

  validation {
    condition     = !var.argocd_oidc_enabled || length(trimspace(var.argocd_oidc_client_id)) > 0
    error_message = "argocd_oidc_client_id must be set when argocd_oidc_enabled is true."
  }
}

variable "argocd_oidc_client_secret_name" {
  description = "Kubernetes Secret name in namespace argocd containing key clientSecret for the Argo CD OIDC client."
  type        = string
  default     = "argocd-oidc-client-secret"
}

variable "argocd_oidc_requested_scopes" {
  description = "OIDC scopes requested by Argo CD. Keep groups when RBAC maps provider groups."
  type        = list(string)
  default     = ["openid", "profile", "email", "groups"]
}

locals {
  argocd_cm_base = {
    "admin.enabled" = tostring(var.argocd_local_admin_enabled)
    "url"           = "https://argocd.canepro.me"
  }

  argocd_cm_oidc = var.argocd_oidc_enabled ? {
    "oidc.config" = yamlencode({
      name            = var.argocd_oidc_name
      issuer          = var.argocd_oidc_issuer_url
      clientID        = var.argocd_oidc_client_id
      clientSecret    = format("$%s:clientSecret", var.argocd_oidc_client_secret_name)
      requestedScopes = var.argocd_oidc_requested_scopes
    })
  } : {}
}
