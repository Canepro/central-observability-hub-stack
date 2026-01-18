# Quick Upgrade Summary - 2026-01-18

## 🚨 CRITICAL: ArgoCD Major Upgrade

**Current**: ArgoCD v2.9.3 (Dec 2023)  
**Target**: ArgoCD v3.1.8+ (via Helm chart 9.3.4)  
**Risk Level**: **HIGH** - Major version with breaking changes

### Before You Start

1. **Check Kubernetes version**: Must be 1.20+
   ```bash
   kubectl version --short
   ```

2. **Backup ArgoCD**:
   ```bash
   kubectl get -n argocd applications,appprojects -o yaml > argocd-backup-$(date +%Y%m%d).yaml
   terraform state pull > terraform-state-backup-$(date +%Y%m%d).json
   ```

3. **Read Breaking Changes**:
   - API endpoints changed (v1 → v2)
   - Helm 3.13.2 → 3.18.4
   - Kustomize updated
   - OIDC auth flow changed
   - Review: https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/

---

## What's Being Updated

| Component | Current | → | New | Risk |
|-----------|---------|---|-----|------|
| **ArgoCD Helm** | 5.51.6 | → | 9.3.4 | 🔴 HIGH |
| **ArgoCD App** | v2.9.3 | → | v3.1.8+ | 🔴 HIGH |
| NGINX Ingress | 4.9.0 | → | 4.14.1 | 🟡 MEDIUM |
| Promtail | 6.15.3 | → | 6.17.1 | 🟢 LOW (EOL soon) |
| Metrics Server | 3.12.1 | → | 3.13.0 | 🟢 LOW |
| RocketChat | 6.27.1 | → | 6.29.0 | 🟢 LOW |
| Loki | 6.46.0 | - | 6.46.0 | ✅ Current |
| Tempo | 1.24.0 | - | 1.24.0 | ✅ Current |
| Grafana | 10.4.0 | - | 10.4.0 | ✅ Current |

---

## Deployment Order (IMPORTANT)

### Phase 1: ArgoCD (Allow 30-60 minutes)

```bash
cd terraform
terraform plan    # Review CAREFULLY
terraform apply   # ArgoCD will restart
kubectl get pods -n argocd -w   # Wait for all Running
```

**Verify ArgoCD works** before proceeding:
- Access https://argocd.canepro.me
- Check all apps are Healthy & Synced
- Test manual sync on one app

### Phase 2: Infrastructure (Low risk, can do together)

```bash
git add argocd/applications/nginx-ingress.yaml
git add argocd/applications/metrics-server.yaml
git commit -m "Update infrastructure components"
git push
# Watch ArgoCD UI for sync
```

### Phase 3: Monitoring (Can do together)

```bash
git add argocd/applications/promtail.yaml
git commit -m "Update Promtail to 6.17.1 (note: EOL March 2)"
git push
```

### Phase 4: RocketChat (External cluster)

```bash
git add argocd/applications/k8-canepro-rocketchat.yaml
git commit -m "Update RocketChat to 6.29.0"
git push
```

---

## Emergency Rollback

### If ArgoCD fails:
```bash
cd terraform
git checkout HEAD~1 -- argocd.tf
terraform apply
```

### If apps fail to sync:
```bash
# In ArgoCD UI:
# Application → App Details → History → Rollback to previous version
```

---

## Post-Upgrade Checklist

- [ ] ArgoCD UI accessible at https://argocd.canepro.me
- [ ] All applications show "Healthy" + "Synced"
- [ ] Grafana accessible and showing data
- [ ] Prometheus targets are up
- [ ] Loki receiving logs
- [ ] NGINX Ingress responding
- [ ] No unusual errors in pod logs
- [ ] Update VERSION-TRACKING.md with deployment date

---

## Key Commands

```bash
# Check ArgoCD version
kubectl exec -n argocd deployment/argocd-server -- argocd version

# Check all apps
kubectl get applications -n argocd

# Check pods in monitoring
kubectl get pods -n monitoring

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50

# Check application logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

---

## Documentation

- **Full Details**: `UPGRADE-SUMMARY.md`
- **Version Tracking**: `VERSION-TRACKING.md`
- **ArgoCD Upgrade Guide**: https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/

---

## Important Dates

- **Today**: 2026-01-18 (Updates prepared)
- **Promtail EOL**: 2026-03-02 (6 weeks - plan migration!)
- **Next Review**: 2026-02-18

---

## Questions?

1. Check `TROUBLESHOOTING.md`
2. Review ArgoCD application logs
3. Check pod events: `kubectl describe pod <name> -n <namespace>`
4. Review official documentation linked above
