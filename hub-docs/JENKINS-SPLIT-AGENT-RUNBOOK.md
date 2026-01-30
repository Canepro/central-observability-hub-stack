# Jenkins Split-Agent: Shutdown & Startup Runbook

Operational steps for the hybrid setup: Controller on OKE (24/7), static agent on AKS (16:00–23:00 UTC). See [JENKINS-SPLIT-AGENT-PLAN.md](JENKINS-SPLIT-AGENT-PLAN.md) for architecture and phases.

**Related in ops repo:** **JENKINS_DEPLOYMENT.md** (Split-Agent Hybrid subsection) and **OPERATIONS.md** (Jenkins Split-Agent shutdown/startup) reference this runbook and the plan.

---

## 1. AKS Shutdown (before 23:00 UTC)

**Goal:** Put the AKS agent offline in Jenkins before stopping AKS so Jenkins does not mark builds as Failed/Aborted, and avoid Terraform state lock left on Azure.

### 1.1 Check for running builds on `aks-agent`

- **Jenkins UI:** Manage Jenkins → Manage Nodes and Clouds → `aks-agent` → check for any running builds.
- **API (from a box with Jenkins API token):**

```bash
# Replace JENKINS_URL and TOKEN
curl -s -u "USER:TOKEN" "https://jenkins.canepro.me/computer/aks-agent/api/json?depth=1" | jq '.executors[]? | select(.currentExecutable != null) | .currentExecutable.url'
```

- If any build is running: either wait for it to finish, or abort it (accept one aborted build), or skip shutdown that night and alert.

### 1.2 Put agent offline

- **Jenkins UI:** Manage Jenkins → Manage Nodes and Clouds → `aks-agent` → Mark this node temporarily offline → Reason: `Scheduled AKS shutdown`.
- **API:**

```bash
# Disable (take offline) the agent
curl -X POST -u "USER:TOKEN" "https://jenkins.canepro.me/computer/aks-agent/toggleOffline?offlineMessage=Scheduled+AKS+shutdown"
```

- **CLI (if Jenkins CLI is available):**

```bash
java -jar jenkins-cli.jar -s https://jenkins.canepro.me -auth USER:TOKEN offline-node "aks-agent" "Scheduled AKS shutdown"
```

### 1.3 Wait

- Wait 30–60 seconds for Jenkins to acknowledge the node is offline.

### 1.4 Run AKS shutdown

- Run your existing AKS stop logic (e.g. Azure Automation runbook `Stop-AKS-Cluster`, or `az aks stop`, or scale-to-zero), as configured in `terraform/automation.tf` (in the ops repo).

### 1.5 Where to run this

- **Option A:** Azure Automation runbook: extend the stop runbook to call the Jenkins API (steps 1.1–1.2) before stopping the cluster. Store Jenkins API token in Key Vault; runbook uses managed identity to read it.
- **Option B:** CronJob on AKS that runs at 22:45 UTC: script that checks builds, puts agent offline, then triggers the stop (e.g. via webhook to Azure Automation). CronJob runs only when AKS is up.
- **Option C:** Manual: document that before 23:00 someone marks the agent offline in Jenkins UI, then the scheduled stop runs.

---

## 2. AKS Startup (morning)

- When AKS comes back up, the static agent pod (e.g. from `ops/manifests/jenkins-static-agent.yaml`) should reconnect automatically if launch method is “Launch agent by connecting it to the controller” (WebSocket).
- If the node was left offline in Jenkins, bring it back online: Manage Jenkins → Manage Nodes and Clouds → `aks-agent` → Bring this node back online.
- If you use “Launch agent via Java Web Start”, you may need a startup script on AKS to re-launch the agent; then bring the node back online in Jenkins.

---

## 3. State lock (Terraform) if AKS stopped mid-build

If AKS was stopped while a Terraform job was running on `aks-agent`, the lock on Azure Storage (e.g. `aks.terraform.tfstate`) may be left behind.

- **Prefer:** Avoid shutdown while builds are running (use the “check for running builds” step above).
- **Remediation:** Use `terraform force-unlock <LOCK_ID>` with the lock ID shown in the state. Document in your ops runbook (e.g. OPERATIONS.md in the ops repo) where state is stored and how to force-unlock.

---

**Clickable link** (for cross-repo use; replace `GrafanaLocal` with `hub-docs` if this file lives in a separate repo):  
`https://github.com/Canepro/GrafanaLocal/blob/main/hub-docs/JENKINS-SPLIT-AGENT-RUNBOOK.md`

---

*Runbook version: 1.0 — For Split-Agent Hybrid (Controller on OKE, Agent on AKS).*
