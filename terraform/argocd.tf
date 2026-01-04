resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.51.6"

  values = [
    <<EOF
server:
  metrics:
    enabled: true
  extraArgs:
    - --insecure
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    hosts:
      - argocd.canepro.me
    tls:
      - secretName: argocd-tls
        hosts:
          - argocd.canepro.me
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 50m
      memory: 128Mi

controller:
  metrics:
    enabled: true
  resources:
    limits:
      cpu: 500m
      memory: 512Mi

repoServer:
  metrics:
    enabled: true
  resources:
    limits:
      cpu: 500m
      memory: 512Mi

applicationSet:
  metrics:
    enabled: true

redis-ha:
  enabled: false
EOF
  ]
}
