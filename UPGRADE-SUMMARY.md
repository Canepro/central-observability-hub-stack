# Upgrade Summary - 2026-01-18

## Changes Applied

### ArgoCD Core
**File**: `terraform/argocd.tf`
- **Helm Chart Updated**: 5.51.6 → 9.3.4
- **Application Updated**: v2.9.3 (Dec 2023) → v3.1.8+ 
- **Change Type**: **Major version upgrade** (both chart and application)
- **⚠️ Critical**: This is a significant upgrade spanning 1+ year of development
- **Action Required**: 
  - **MUST READ**: [ArgoCD v3.0 upgrade guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/)
  - **MUST READ**: [ArgoCD v3.1.8 release notes](https://github.com/argoproj/argo-cd/releases/tag/v3.1.8)
  - Verify Kubernetes version (requires 1.20+)
  - Review API endpoint changes (v1 → v2 for some endpoints)
  - Test authentication flow (OIDC changes)
  - Run `terraform plan` and carefully review changes
  - **Recommendation**: Test in non-production first if possible
  - Plan for 15-30 minutes of potential ArgoCD unavailability during upgrade

### Application Updates

#### 1. Promtail
**File**: `argocd/applications/promtail.yaml`
- **Updated**: 6.15.3 → 6.17.1
- **Change Type**: Minor version upgrade
- ⚠️ **CRITICAL WARNING**: Promtail is deprecated and reaches **EOL on March 2, 2026** (6 weeks away)

#### 2. NGINX Ingress Controller
**File**: `argocd/applications/nginx-ingress.yaml`
- **Updated**: 4.9.0 → 4.14.1
- **Change Type**: Minor version upgrade
- **Includes**: Controller version v1.14.1

#### 3. Metrics Server
**File**: `argocd/applications/metrics-server.yaml`
- **Updated**: 3.12.1 → 3.13.0
- **Change Type**: Minor version upgrade
- **Includes**: App version 0.8.0

#### 4. RocketChat
**File**: `argocd/applications/k8-canepro-rocketchat.yaml`
- **Updated**: 6.27.1 → 6.29.0
- **Change Type**: Minor version upgrade
- **Supports**: RocketChat app version 8.0.0

---

## No Updates Required

### Loki
- **Current**: 6.46.0
- **Status**: ✅ Already at latest version

### Tempo
- **Current**: 1.24.0
- **Status**: ✅ Already at latest version (single binary mode)
- **Note**: Distributed mode has v1.57.0 if you want to migrate to microservices architecture

### Grafana
- **Current**: 10.4.0
- **Status**: ✅ Current version is newer than latest found (10.1.5)

---

## Needs Investigation

### Prometheus
- **Current**: 25.8.0
- **Latest Found**: 15.8.5
- **Issue**: Version discrepancy suggests possible chart migration or different variant
- **Action**: Verify which Prometheus chart is being used:
  - `prometheus-community/prometheus` (latest: 15.8.5)
  - `prometheus-community/kube-prometheus-stack` (latest: 80.13.3)

---

## Deployment Instructions

### ⚠️ IMPORTANT: Read Before Deploying

**ArgoCD Upgrade is Major** - You are upgrading from:
- ArgoCD v2.9.3 (Dec 2023) → v3.1.8+ (Sept 2025+)
- This spans over 1 year of development with breaking changes

**Key Breaking Changes in ArgoCD v3.x**:
1. API endpoint migrations (some `/api/v1/` → `/api/v2/`)
2. Kubernetes 1.20+ required
3. OIDC authentication flow changed to server-side
4. Helm version updated from 3.13.2 → 3.18.4
5. Kustomize version updated
6. Configuration values in Helm chart may have changed

**Recommendation**: Deploy incrementally, starting with ArgoCD.

---

### Option 1: Deploy All Changes at Once (Not Recommended)

```bash
# ⚠️ Not recommended due to major ArgoCD upgrade
# Use Option 2 instead for safer deployment
```

### Option 2: Deploy Incrementally (STRONGLY Recommended)

#### Step 1: Update ArgoCD First (CRITICAL - PLAN DOWNTIME)
```bash
#### Step 1: Update ArgoCD First (CRITICAL - PLAN DOWNTIME)

**⚠️ Pre-Upgrade Checklist**:
- [ ] Verify Kubernetes version is 1.20 or higher
- [ ] Backup ArgoCD configuration: `kubectl get -n argocd applications,appprojects -o yaml > argocd-backup.yaml`
- [ ] Note current admin password: `kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
- [ ] Review your Terraform values against [new chart values](https://github.com/argoproj/argo-helm/blob/main/charts/argo-cd/values.yaml)
- [ ] Plan 15-30 minute maintenance window
- [ ] Notify team of ArgoCD downtime

**Deployment**:
```bash
cd terraform

# Review your argocd.tf values against chart 9.3.4 defaults
# Compare: https://github.com/argoproj/argo-helm/blob/main/charts/argo-cd/values.yaml

# Backup current state
terraform state pull > terraform-state-backup.json

# Review the plan VERY carefully
terraform plan

# Apply (ArgoCD will be unavailable during upgrade)
terraform apply

# Monitor the upgrade
kubectl get pods -n argocd -w
```

**Post-Upgrade Verification** (CRITICAL):
```bash
# Wait for all pods to be running
kubectl get pods -n argocd

# Check ArgoCD version
kubectl exec -n argocd deployment/argocd-server -- argocd version

# Access ArgoCD UI
# URL: https://argocd.canepro.me
# Login and verify UI works

# Check all applications
kubectl get applications -n argocd
# All should show "Healthy" and "Synced"

# If any apps are OutOfSync, check why:
kubectl describe application <app-name> -n argocd

# Test sync operation on a low-risk app
# In ArgoCD UI: Select an app → Sync → Synchronize

# Check logs for errors
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

**If ArgoCD Upgrade Fails**:
```bash
# Rollback immediately
cd terraform
git checkout HEAD~1 -- argocd.tf
terraform apply

# Or restore from backup
terraform state push terraform-state-backup.json
terraform apply
```

#### Step 2: Update Infrastructure Components
```bash
git add argocd/applications/nginx-ingress.yaml
git add argocd/applications/metrics-server.yaml
git commit -m "Update infrastructure components: NGINX Ingress 4.14.1, Metrics Server 3.13.0"
git push
```

Monitor ArgoCD UI for sync status.

#### Step 3: Update Monitoring Components
```bash
git add argocd/applications/promtail.yaml
git commit -m "Update Promtail to 6.17.1"
git push
```

#### Step 4: Update RocketChat
```bash
git add argocd/applications/k8-canepro-rocketchat.yaml
git commit -m "Update RocketChat to 6.29.0"
git push
```

---

## Post-Upgrade Verification

### ArgoCD
```bash
# Check ArgoCD version
kubectl get pods -n argocd
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50

# Access ArgoCD UI
# URL: https://argocd.canepro.me
```

### Application Health Checks
```bash
# Check all applications
kubectl get applications -n argocd

# Check specific application details
kubectl describe application <app-name> -n argocd

# Check pod status in monitoring namespace
kubectl get pods -n monitoring

# Check ingress-nginx
kubectl get pods -n ingress-nginx
```

### Monitoring Stack
```bash
# Test Grafana access
curl -k https://grafana.canepro.me

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
# Open http://localhost:9090/targets

# Check Loki
kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=50
```

---

## Rollback Procedures

### If ArgoCD Update Fails
```bash
cd terraform
# Revert argocd.tf to previous version
git checkout HEAD~1 -- argocd.tf
terraform apply
```

### If Application Updates Fail
```bash
# Revert specific application file
git checkout HEAD~1 -- argocd/applications/<app-name>.yaml
git commit -m "Rollback <app-name> to previous version"
git push
```

Or manually edit in ArgoCD UI:
1. Navigate to Application
2. Edit -> Parameters
3. Change `targetRevision` to previous version
4. Sync

---

## Critical Action Items

### 🚨 URGENT: Promtail Migration (Deadline: March 2, 2026)

Promtail will reach End-of-Life in approximately 6 weeks. You need to plan a migration strategy.

#### Recommended Migration Path: Grafana Alloy

**Why Grafana Alloy?**
- Official replacement recommended by Grafana
- Unified agent for logs, metrics, and traces
- Better performance and resource efficiency
- Active development and support

**Migration Steps** (High-level):
1. Deploy Grafana Alloy alongside Promtail (parallel operation)
2. Configure Alloy to send logs to Loki
3. Test and verify log collection
4. Gradually shift workloads to Alloy
5. Decommission Promtail before March 2, 2026

**Alternative Options**:
- Fluent Bit (lightweight, widely used)
- Vector (performant, Rust-based)
- Filebeat (if using Elastic ecosystem)

#### Action Items:
- [ ] Research Grafana Alloy capabilities
- [ ] Create migration plan document
- [ ] Set up test environment
- [ ] Schedule migration window
- [ ] Update monitoring dashboards
- [ ] Document new configuration

---

## Version Tracking

A comprehensive version tracking document has been created at `VERSION-TRACKING.md`.

This document includes:
- Current and latest versions of all components
- Update priority recommendations
- Maintenance schedule
- References to official documentation

**Recommendation**: Review and update `VERSION-TRACKING.md` monthly.

---

## Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Grafana Alloy Migration Guide](https://grafana.com/docs/alloy/latest/get-started/migrating-from-promtail/)
- [Ingress-NGINX Upgrade Notes](https://github.com/kubernetes/ingress-nginx/blob/main/docs/deploy/upgrade.md)
- [Prometheus Operator Documentation](https://prometheus-operator.dev/)

---

## Questions or Issues?

If you encounter any issues during the upgrade:
1. Check ArgoCD application logs
2. Review pod events: `kubectl describe pod <pod-name> -n <namespace>`
3. Check application-specific logs
4. Consult the TROUBLESHOOTING.md document
5. Review official release notes for breaking changes

---

**Document Created**: 2026-01-18  
**Next Review Date**: 2026-02-18  
**Promtail EOL Reminder**: 2026-03-02
