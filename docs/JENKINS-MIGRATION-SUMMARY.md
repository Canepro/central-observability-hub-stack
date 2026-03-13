# Jenkins Migration and OKE Split-Agent Summary

**Purpose:** Single source of truth for the Jenkins migration from AKS to OKE and the split-agent hybrid architecture. Use this document for onboarding, handover, and troubleshooting context.

**Related documents:** [JENKINS-SPLIT-AGENT-PLAN.md](../hub-docs/JENKINS-SPLIT-AGENT-PLAN.md) (phases and architecture), [JENKINS-503-TROUBLESHOOTING.md](JENKINS-503-TROUBLESHOOTING.md) (operational troubleshooting), [.jenkins/README.md](../.jenkins/README.md) (pipelines and credentials).

---

## 1. Executive Summary

Jenkins was migrated from a single-controller deployment on AKS to a **split-agent hybrid** model:

- **Controller:** Runs 24/7 on OKE (Oracle Kubernetes Engine), exposed at `https://jenkins.canepro.me`.
- **Agents:** OKE jobs use dynamic Kubernetes pods (labels: `terraform-oci`, `version-checker`, `helm`, `security`). Azure-specific jobs use a static agent on AKS (label `aks-agent`) when that cluster is up.

This keeps webhooks and controller availability independent of AKS schedule, while Azure Terraform and Key Vault–dependent jobs still run on AKS with Workload Identity when the cluster is running.

---

## 2. What Was Done

### 2.1 Migration Phases (Status)

| Phase | Description | Outcome |
|-------|-------------|---------|
| **0. E1 — Free 50GB for Jenkins** | Grafana moved to emptyDir; dashboards provisioned from git; one 50GB PVC freed. | Jenkins controller can use the freed PVC on OKE. |
| **1. OKE — Jenkins Controller** | Jenkins deployed on OKE via ArgoCD/Helm; JCasC; Kubernetes cloud for dynamic agents; exposed at jenkins-oke.canepro.me, then jenkins.canepro.me. | Controller 24/7 on OKE; TLS via cert-manager. |
| **2. AKS — Static Agent** | Static agent manifest and RBAC in ops repo; agent connects to OKE via WebSocket. | Agent runs on AKS when cluster is up; label `aks-agent`. |
| **3. Job routing** | Jenkinsfiles in this repo use OKE agent labels (`terraform-oci`, `version-checker`, `helm`, `security`); Azure jobs (in other repos) use `aks-agent`. | Correct agent selection per pipeline. |
| **4. Graceful disconnect** | Before AKS stop: runbook (or automation) puts `aks-agent` offline, then stops AKS. | No stuck builds or Terraform state lock. |
| **5a. DNS cutover** | DNS `jenkins.canepro.me` pointed to OKE; Jenkins URL set to `https://jenkins.canepro.me`; ingress and ArgoCD app for production hostname. | Production URL on OKE. |
| **5b. AKS controller retirement** | Retire Jenkins controller on AKS (remove ArgoCD app, clean resources); keep AKS static agent only. | **Pending** (AKS auto-shutdown overnight/weekend). |

### 2.2 Agent Image and CRI-O Fixes (OKE)

On OKE, the container runtime (CRI-O) requires **fully qualified** image names. Pipelines and cloud defaults were updated as follows:

- **Fully qualified images:** All `jenkins/inbound-agent` references use `docker.io/jenkins/inbound-agent:<tag>`. Other pod images (e.g. Terraform) use `docker.io/` where required.
- **Valid image tag:** The tag `3302.v1cfe4e081049-1-jdk21` does **not** exist on Docker Hub (manifest unknown). All Jenkinsfiles and the Helm default now use a **valid** tag: `3355.v388858a_47b_33-8-jdk21`.
- **Explicit jnlp in pod YAML:** Each pipeline that uses `agent { kubernetes { ... yaml } }` defines an explicit `jnlp` container with `docker.io/jenkins/inbound-agent:3355.v388858a_47b_33-8-jdk21` so agent pods pull successfully.

**Files updated:** `.jenkins/terraform-validation.Jenkinsfile`, `.jenkins/version-check.Jenkinsfile`, `.jenkins/k8s-manifest-validation.Jenkinsfile`, `.jenkins/security-validation.Jenkinsfile`, `helm/jenkins-values.yaml`.

### 2.3 Post-Action Robustness

When agent allocation fails (e.g. image pull error), the pipeline never runs on an agent; only `post { always { ... } }` runs. Calling `cleanWs()` in that context causes `MissingContextVariableException` (no workspace/FilePath).

- **Change:** In pipelines that use `cleanWs()` in `post { always { ... } }`, the call is guarded so it runs only when the build ran on an agent: `script { if (currentBuild.rawBuild.getExecutor() != null) { cleanWs() } }`.
- **Pipelines updated:** `terraform-validation.Jenkinsfile`, `k8s-manifest-validation.Jenkinsfile`.

### 2.4 Operational Tooling and Docs

- **Stale agent cleanup:** `scripts/jenkins-clean-stale-agents.sh` removes stale Kubernetes agent nodes and cancels stuck queue items via the Jenkins API (skips built-in and `aks-agent`).
- **Troubleshooting guide:** `docs/JENKINS-503-TROUBLESHOOTING.md` covers 503 after restart, startup probes, agent image issues (ImageInspectError, valid tag), “only Declarative: Post Actions” in stage view, and cleanup steps.
- **Ingress for production URL:** `k8s/jenkins/jenkins-canepro-ingress.yaml` and `argocd/applications/jenkins-ingress-canepro.yaml` expose Jenkins at `jenkins.canepro.me` with TLS.

---

## 3. Current State

| Item | Value |
|------|--------|
| **Jenkins URL** | `https://jenkins.canepro.me` |
| **Controller** | OKE, namespace `jenkins`, Helm chart + `helm/jenkins-values.yaml` |
| **Controller image** | `docker.io/jenkins/jenkins:2.541.2-jdk17` |
| **Dynamic agents (OKE)** | Kubernetes cloud; pod templates with labels `terraform-oci`, `version-checker`, `helm`, `security`; jnlp image `docker.io/jenkins/inbound-agent:3355.v388858a_47b_33-8-jdk21` |
| **Static agent (AKS)** | Label `aks-agent`; connects via WebSocket to `https://jenkins.canepro.me` when AKS is up |
| **GrafanaLocal pipelines** | `.jenkins/*.Jenkinsfile`; multibranch jobs; script paths e.g. `.jenkins/terraform-validation.Jenkinsfile` |

---

## 4. Best Practices Applied

- **Image tags:** Use only tags that exist on Docker Hub; verify when upgrading (e.g. `jenkins/inbound-agent` tags).
- **CRI-O / OKE:** Always use fully qualified image names (`docker.io/...`) in Jenkinsfiles and Helm defaults.
- **GitOps-only admin changes:** Treat Jenkins UI warnings as signals; apply core/plugin changes in `helm/jenkins-values.yaml` and sync via ArgoCD (avoid UI plugin/core update actions that create drift).
- **Post actions:** Do not assume a workspace exists in `post { always { ... } }`; guard steps that require `FilePath` (e.g. `cleanWs()`) when agent allocation may have failed.
- **Cleanup after restarts:** After controller or plugin restarts, run the stale-agent cleanup script and abort stuck queue items before expecting normal behaviour.
- **Multibranch:** After changing Jenkinsfiles, run “Scan Multibranch Pipeline Now” and build the correct branch (e.g. `main`) so jobs use the latest pipeline definition.

---

## 5. References

| Document | Purpose |
|----------|---------|
| [hub-docs/JENKINS-SPLIT-AGENT-PLAN.md](../hub-docs/JENKINS-SPLIT-AGENT-PLAN.md) | Full migration plan, phases, architecture, prerequisites |
| [hub-docs/JENKINS-SPLIT-AGENT-RUNBOOK.md](../hub-docs/JENKINS-SPLIT-AGENT-RUNBOOK.md) | AKS shutdown/startup and agent offline procedure |
| [docs/JENKINS-503-TROUBLESHOOTING.md](JENKINS-503-TROUBLESHOOTING.md) | 503, image pull, stage view, and cleanup |
| [.jenkins/README.md](../.jenkins/README.md) | Pipeline list, OCI credentials, job setup |

---

*Last updated: 2026-02-22 — Jenkins controller image bumped to 2.541.2-jdk17; GitOps handling for admin warning banners documented.*
