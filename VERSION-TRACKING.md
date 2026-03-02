# Software Versions Tracking

This document tracks all software versions used in the OKE Observability Hub deployment. Update this file when upgrading any component.

**Last Updated**: 2026-03-02

## Upgrade Status Legend

- ✅ **Up to date**: Already at latest version (updated on date shown)
- ⚠️ **Can upgrade**: Has newer version available, can be upgraded with testing
- ⚠️ **Check latest**: Version not verified, check official source for latest
- 🔄 **Just updated**: Version recently updated (see date in status column)
- ⚠️ **Deprecated**: Component is deprecated, consider migration path
- 🔍 **Needs investigation**: Version discrepancy or unclear status

## Dashboard Provisioning Policy

Grafana dashboards are provisioned via Helm values in `helm/grafana-values.yaml` plus in-repo JSONs under `dashboards/`:
- In-repo JSONs are packaged by ArgoCD app `grafana-dashboards` into ConfigMap `grafana-dashboards-repo` (`dashboards/kustomization.yaml`) and mounted into Grafana via `extraConfigmapMounts`.
- Public Grafana.com dashboards (gnet) are downloaded at startup via `helm/grafana-values.yaml` `dashboards:` entries.
- Some upstream dashboards require patching for GitOps file provisioning (UID collisions, datasource UID placeholders, Loki variable query semantics). This repo applies those patches on startup via an initContainer in `helm/grafana-values.yaml`.

**Grafana.com (gnet) revision policy**: the Grafana Helm chart defaults to downloading **revision 1** unless `revision:` is explicitly set. Use `revision: latest` for latest-first behavior, and pin a numeric revision only when you have a specific reason (document why and update it during regular version reviews).

## Quick Upgrade Reference

**Just updated (2026-02-05)**:
- Loki 6.51.0 → 6.52.0 (patch)
- Prometheus 28.8.0 → 28.8.1 (patch)
- NGINX Ingress 4.14.2 → 4.14.3 (patch)

**Just updated (2026-02-07)**:
- OpenTelemetry Collector added (chart 0.145.0)
- Prometheus 28.8.1 → 28.9.0 (patch; chart dependency updates)

**Previously updated (2026-02-02)**:
- Prometheus 28.7.0 → 28.8.0 (patch)

**Just updated (2026-02-01)**:
- Grafana 10.4.0 → 10.5.15
- Loki 6.46.0 → 6.51.0
- Tempo 1.24.0 → 1.24.4
- NGINX Ingress 4.14.1 → 4.14.2
- Prometheus 25.8.0 → 28.7.0 (app v2.48.0 → v3.x) 🔄

**Previously updated (2026-01-19)**:
- ArgoCD 5.51.6 → 9.3.4 (app v2.9.3 → v3.2.5)
- Promtail 6.15.3 → 6.17.1 (deprecated, EOL March 2, 2026)
- Metrics Server 3.12.1 → 3.13.0
- RocketChat 6.27.1 → 6.29.0

## How to Update Versions

1. **Check for latest versions**: See "Update Source" links below or check official repositories
2. **Update the ArgoCD application manifest**: Change the `targetRevision:` in the corresponding manifest
3. **Test in dev/staging** (if available) before production
4. **Update this file**: Update the version and date in the table below
5. **Commit and let ArgoCD sync**: ArgoCD will automatically deploy the updated version

---

## ArgoCD Core Infrastructure

| Component | Current Version | Latest Version | Upgrade Status | Location | Update Source |
|-----------|----------------|----------------|----------------|----------|---------------|
| **ArgoCD Helm Chart** | `9.3.4` | `9.3.4` | ✅ **Upgraded** (2026-01-19) | `terraform/argocd.tf` | [ArgoCD Helm Releases](https://github.com/argoproj/argo-helm/releases) |
| **ArgoCD Application** | `v3.2.5` | `v3.2.5` | ✅ **Upgraded** (2026-01-19) | Bundled with Helm chart | [ArgoCD Releases](https://github.com/argoproj/argo-cd/releases) |

**✅ Upgrade Complete** (2026-01-19): 
- **Helm Chart**: Upgraded 5.51.6 → 9.3.4
- **Application**: Upgraded v2.9.3 (Dec 2023) → v3.2.5 (Jan 2026)
- **Ingress**: Fixed for chart 9.3.4 (uses `global.domain` + `hostname` format)
- **RBAC**: Created config file at `k8s/argocd-rbac-config.yaml` for log access
- **Pending**: Apply RBAC config, verify app syncs
- **Breaking Changes from v2.9.x**: ArgoCD v3.x has significant changes:
  - API endpoint deprecations (`/api/v1/applications/{name}/resource/actions` → `v2`)
  - Helm upgraded to v3.18.4, Kustomize to v5.7.0
  - Kubernetes 1.20+ required
  - OIDC auth flow changes (server-side PKCE)
  - Security improvements (symlink protection, sanitized API responses)
- **Review Required**: [ArgoCD v3.0 upgrade guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/) and [v3.2.5 release notes](https://github.com/argoproj/argo-cd/releases/tag/v3.2.5)

---

## Monitoring & Observability Stack

| Component | Current Version | Latest Version | Upgrade Status | Location | Update Source |
|-----------|----------------|----------------|----------------|----------|---------------|
| **Grafana** | `10.5.15` | `10.5.15` | 🔄 **Just updated** (2026-02-01) | `argocd/applications/grafana.yaml` | [Grafana Helm Releases](https://github.com/grafana/helm-charts/releases) |
| **Loki** | `6.52.0` | `6.52.0` | 🔄 **Just updated** (2026-02-05) | `argocd/applications/loki.yaml` | [Loki Helm Releases](https://github.com/grafana/helm-charts/releases) |
| **Promtail** | `6.17.1` | `6.17.1` | 🔄 **Just updated** (2026-01-19) ⚠️ **Deprecated** | `argocd/applications/promtail.yaml` | [Promtail Helm Releases](https://github.com/grafana/helm-charts/releases) |
| **Tempo** | `1.24.4` | `1.24.4` | 🔄 **Just updated** (2026-02-01) | `argocd/applications/tempo.yaml` | [Tempo Helm Releases](https://github.com/grafana/helm-charts/releases) |
| **Prometheus** | `28.9.0` | `28.9.0` | 🔄 **Just updated** (2026-02-07) | `argocd/applications/prometheus.yaml` | [Prometheus Community Charts](https://github.com/prometheus-community/helm-charts/releases) |
| **OpenTelemetry Collector** | `0.145.0` | ⚠️ **Check latest** | 🔄 **Just added** (2026-02-07) | `argocd/applications/otel-collector.yaml` | [OTel Helm Charts](https://github.com/open-telemetry/opentelemetry-helm-charts/releases) |

**⚠️ Important Note on Promtail**: Promtail is deprecated in favor of Grafana Alloy. Promtail entered LTS (Long-Term Support) on February 13, 2025, and will reach **End of Life (EOL) on March 2, 2026**. Consider migrating to Grafana Alloy for long-term support. See [Promtail Deprecation Notice](https://grafana.com/blog/2025/02/13/grafana-loki-3.4-standardized-storage-config-sizing-guidance-and-promtail-merging-into-alloy/) for details.

**🔄 Prometheus Upgrade (2026-01-31; patch bump 2026-02-01)**: Upgraded from chart 25.8.0 (Prometheus v2.48.0) → 28.7.0 (Prometheus v3.x)
- Major version upgrade: Prometheus v2 → v3 (first major release in 7 years)
- Breaking changes: UTF-8 support enabled by default, stricter scraping behavior
- New features: New web UI with tree view and metrics explorer
- Config compatibility: All existing settings in `helm/prometheus-values.yaml` remain valid
- See GitHub issue #2 for detailed analysis and migration notes

**💡 Tempo Note**: Currently using single binary mode (v1.24.4). The `tempo-distributed` chart has v1.57.0 available if you want to migrate to microservices architecture.

---

## Infrastructure Components

| Component | Current Version | Latest Version | Upgrade Status | Location | Update Source |
|-----------|----------------|----------------|----------------|----------|---------------|
| **NGINX Ingress Controller** | `4.14.3` | `4.14.3` | 🔄 **Just updated** (2026-02-05) | `argocd/applications/nginx-ingress.yaml` | [Ingress-NGINX Releases](https://github.com/kubernetes/ingress-nginx/releases) |
| **Metrics Server** | `3.13.0` | `3.13.0` | 🔄 **Just updated** (2026-01-19) | `argocd/applications/metrics-server.yaml` | [Metrics Server Releases](https://github.com/kubernetes-sigs/metrics-server/releases) |

---

## External Spoke Cluster Applications (AKS RocketChat Cluster)

| Component | Current Version | Latest Version | Upgrade Status | Location | Update Source |
|-----------|----------------|----------------|----------------|----------|---------------|
| **RocketChat Helm Chart** | `6.29.0` | `6.29.0` | 🔄 **Just updated** (2026-01-19) | `argocd/applications/aks-rocketchat-helm` (ArgoCD app) | [RocketChat Helm Charts](https://github.com/RocketChat/helm-charts/releases) |
| **RocketChat App Version** | `Check values` | `8.0.0` | ⚠️ **Check latest** (Jan 12, 2026 release) | Controlled by chart values | [RocketChat Releases](https://github.com/RocketChat/Rocket.Chat/releases) |

**Note**: RocketChat app version (image tag) is controlled separately from the Helm chart version. Chart v6.29.0 supports RocketChat v8.x images.

---

## Version Update Procedure

### Quick Update Steps

1. **Identify the component** to update from the table above
2. **Check latest version** from the Update Source
3. **Edit the ArgoCD application manifest** listed in the Location column
4. **Change the `targetRevision:` value** to the new version
5. **Update VERSION-TRACKING.md** with new version and date
6. **Commit and push** - ArgoCD will auto-sync the change

### Example: Updating Grafana

```bash
# 1. Check current version in manifest
grep "targetRevision:" argocd/applications/grafana.yaml
# Current output: targetRevision: 10.5.15

# 2. Check latest version at https://github.com/grafana/helm-charts/releases
# Example: Latest is 10.5.15

# 3. Update the manifest file
# Edit: argocd/applications/grafana.yaml
# Change: targetRevision: 10.5.0
# To:     targetRevision: 10.5.15

# 4. Update this file (VERSION-TRACKING.md)
# Edit the "Current Version" column in the Monitoring & Observability Stack table above
# Change: 10.5.0 → 10.5.15
# Update status to: 🔄 **Just updated** (2026-MM-DD)

# 5. Commit the changes
git add argocd/applications/grafana.yaml VERSION-TRACKING.md
git commit -m "chore: Upgrade Grafana Helm chart to 10.5.0"

# 6. Push and ArgoCD will auto-sync the change to the cluster
git push
```

### Example: Updating ArgoCD (Terraform-managed)

```bash
# 1. Check current version
grep 'version' terraform/argocd.tf
# Current output: version = "9.3.4"

# 2. Update the Terraform file
# Edit: terraform/argocd.tf
# Change: version = "9.3.4"
# To:     version = "9.5.0"

# 3. Plan and apply
cd terraform
terraform plan
terraform apply

# 4. Update VERSION-TRACKING.md
git add terraform/argocd.tf VERSION-TRACKING.md
git commit -m "chore: Upgrade ArgoCD to 9.5.0"
git push
```

### Verifying Updates

After ArgoCD syncs:

```bash
# Check application sync status
kubectl get applications -n argocd

# Check specific application status
kubectl describe application grafana -n argocd

# Check pod status in monitoring namespace
kubectl get pods -n monitoring

# Check specific deployment for image version
kubectl get deployment grafana -n monitoring -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check logs for any errors
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=50
```

### Rollback Procedure

If an update causes issues:

```bash
# Option 1: Revert via Git
git revert HEAD
git push

# Option 2: Manual edit in ArgoCD UI
# 1. Navigate to Application in ArgoCD UI
# 2. Click "App Details" → "Parameters"
# 3. Change targetRevision to previous version
# 4. Click "Sync"

# Option 3: Direct manifest edit for emergency rollback
kubectl edit application grafana -n argocd
# Change spec.sources[0].targetRevision to previous version
```

---

## Update Priority & Recommendations

### 🚨 Urgent (Complete by March 2, 2026)
**Promtail Migration**: Plan and execute migration from Promtail to Grafana Alloy or alternative before EOL date.

### ✅ Recently Completed (2026-01-19)
- ArgoCD: 5.51.6 → 9.3.4 (major version upgrade)
- Promtail: 6.15.3 → 6.17.1 (minor update, but plan migration)
- Metrics Server: 3.12.1 → 3.13.0 (minor update)
- RocketChat: 6.27.1 → 6.29.0 (minor update)

### ✅ Verification (Optional)
**Prometheus Chart Version**: Confirm the chart in ArgoCD and the running release match.

```bash
# Check the actual chart being used
helm list -n monitoring
helm get values prometheus -n monitoring

# Compare against current chart versions from helm search (see repository references below)
```

### 📅 Next Review Date: 2026-02-18

---

## Security Considerations

- **Regular Updates**: Check for updates monthly or when security advisories are published
- **Breaking Changes**: Always review release notes before upgrading
- **Testing**: Test updates in non-production environment when possible
- **Backup**: Ensure backups are current before major version upgrades
- **CVE Monitoring**: Subscribe to security advisories for critical components

### Security Update Process

For security updates:
1. **Immediate**: Apply security patches within 24-48 hours
2. **High Priority**: Review and apply within 1 week
3. **Medium Priority**: Apply within 2 weeks
4. **Low Priority**: Include in next scheduled maintenance

---

## Version Compatibility Notes

### ArgoCD v9.3.4 (Helm Chart) / v3.2.5 (Application)
**Current Status**: ✅ Upgraded on 2026-01-19 from v2.9.3 → v3.2.5

**Helm Chart Changes**:
- Major version jump from chart 5.51.6 → 9.3.4
- Configuration values may have changed - review your `values` section

**ArgoCD Application Changes** (v2.9.3 → v3.2.5):
- **Bundled Tools**: Helm 3.18.4, Kustomize 5.7.0, Redis 7.4.1, HAProxy 2.9.4
- **API Breaking Changes**:
  - Old: `/api/v1/applications/{name}/resource/actions` (deprecated)
  - New: `/api/v1/applications/{name}/resource/actions/v2`
- **Security Enhancements**:
  - Symlink protection for static assets
  - Sanitized Project API responses (no credential leakage)
  - Server-side OIDC auth with PKCE
- **Requirements**: Kubernetes 1.20+ (verify your cluster version)
- **RBAC**: Improved multi-tenant isolation and project-level security

**Testing Checklist After Upgrade**:
- [ ] Verify UI access at https://argocd.canepro.me
- [ ] Test authentication (SSO/OIDC if configured)
- [ ] Check all applications sync successfully
- [ ] Verify Helm and Kustomize apps render correctly
- [ ] Test API integrations (if any external tools use ArgoCD API)
- [ ] Verify RBAC policies still work as expected
- [ ] Check metrics and monitoring dashboards

### Promtail v6.17.1
- Compatible with Loki v6.51.0
- **Deprecated**: EOL March 2, 2026
- Plan migration to Grafana Alloy before EOL

### NGINX Ingress v4.14.2
- Controller version: v1.14.1
- Check for any ingress annotation changes
- Verify TLS certificate handling

### Tempo v1.24.4 (Single Binary)
- Alternative: tempo-distributed v1.57.0 for microservices mode
- Current mode suitable for moderate workloads
- Consider distributed mode for high-scale tracing

---

## Component Repository References

### Helm Chart Repositories

```bash
# Add/update Helm repositories
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo add rocketchat https://rocketchat.github.io/helm-charts
helm repo update

# Search for latest versions
helm search repo argo/argo-cd --versions | head -5
helm search repo grafana/grafana --versions | head -5
helm search repo grafana/loki --versions | head -5
helm search repo grafana/promtail --versions | head -5
helm search repo grafana/tempo --versions | head -5
helm search repo prometheus-community/prometheus --versions | head -5
helm search repo ingress-nginx/ingress-nginx --versions | head -5
helm search repo metrics-server/metrics-server --versions | head -5
helm search repo rocketchat/rocketchat --versions | head -5
```

### Official Documentation Links

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/) (Promtail replacement)
- [Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [NGINX Ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Metrics Server Documentation](https://github.com/kubernetes-sigs/metrics-server)
- [RocketChat Documentation](https://docs.rocket.chat/)

---

## Maintenance Windows

### Recommended Schedule
- **Monthly Version Check**: First Monday of each month
- **Quarterly Major Updates**: Review major version upgrades
- **Security Patches**: Apply immediately upon release
- **Maintenance Window**: Sundays 02:00-04:00 UTC (if disruptive changes needed)

### Pre-Maintenance Checklist
- [ ] Review all pending updates
- [ ] Check release notes for breaking changes
- [ ] Verify backup status
- [ ] Plan rollback strategy
- [ ] Test in non-production (if available)
- [ ] Schedule maintenance notification
- [ ] Prepare rollback procedures

### Post-Maintenance Checklist
- [ ] Verify all applications synced successfully
- [ ] Check pod status across all namespaces
- [ ] Verify ingress accessibility
- [ ] Test Grafana dashboards
- [ ] Verify Prometheus targets
- [ ] Check Loki log ingestion
- [ ] Test alerting functionality
- [ ] Update VERSION-TRACKING.md
- [ ] Document any issues encountered

---

**Document Last Updated**: 2026-03-02  
**Next Scheduled Review**: 2026-02-18  
**Maintained By**: Infrastructure Team
