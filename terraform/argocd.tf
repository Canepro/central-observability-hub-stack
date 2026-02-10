resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "9.3.4"

  # yamlencode gives deterministic output that matches how the Helm provider stores state — avoids perpetual diff
  values = [
    yamlencode({
      global = {
        domain = "argocd.canepro.me"
      }
      server = {
        metrics   = { enabled = true }
        extraArgs = ["--insecure"]
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          hostname         = "argocd.canepro.me"
          tls              = true
          annotations = {
            "cert-manager.io/cluster-issuer"               = "letsencrypt-prod"
            "nginx.ingress.kubernetes.io/ssl-redirect"     = "true"
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
          }
          extraTls = [
            {
              secretName = "argocd-server-tls"
              hosts      = ["argocd.canepro.me"]
            }
          ]
        }
        resources = {
          limits   = { cpu = "500m", memory = "512Mi" }
          requests = { cpu = "50m", memory = "128Mi" }
        }
      }
      controller = {
        metrics   = { enabled = true }
        resources = {
          limits   = { cpu = "500m", memory = "768Mi" }
          requests = { cpu = "500m", memory = "512Mi" }
        }
      }
      repoServer = {
        metrics   = { enabled = true }
        resources = { limits = { cpu = "500m", memory = "512Mi" } }
      }
      applicationSet = {
        metrics = { enabled = true }
      }
      "redis-ha" = {
        enabled = false
      }
    })
  ]
}
