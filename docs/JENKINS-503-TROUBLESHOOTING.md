# Jenkins 503 After Plugin Update / Restart

After updating plugins and restarting Jenkins, nginx returns **503 Service Temporarily Unavailable** because the Jenkins pod is not ready yet (or failed to start).

## 1. Check pod and logs (run these first)

```bash
# Is the pod running, or CrashLoopBackOff?
kubectl get pods -n jenkins -l app.kubernetes.io/component=jenkins-controller

# Recent events (OOMKilled? Failed probe?)
kubectl describe pod -n jenkins -l app.kubernetes.io/component=jenkins-controller

# Is Jenkins still starting? (look for "Jenkins is fully up and running" or errors)
kubectl logs -n jenkins -l app.kubernetes.io/component=jenkins-controller --tail=100 -f
```

**If you see "Jenkins is fully up and running"** in the logs but the pod is not Ready, the readiness probe may be failing (e.g. login filter). Give it another minute or check probe path.

**If the pod is Restarting / CrashLoopBackOff**, check logs for:
- `OutOfMemoryError` → increase memory/limits and/or `controller.javaOpts` (e.g. `-Xmx3072m` → `-Xmx3584m`).
- Plugin/startup exception → note the plugin name; you may need to disable it (see §3).

**If the pod is Running but not Ready**, Jenkins is likely still loading (plugin updates can take 10–20 minutes). Either wait, or increase the startup probe (see §2).

---

## 2. Allow longer startup (after plugin updates)

Plugin updates can make the first startup much slower. Your current startup probe allows **10 minutes** (60 × 10s). If Jenkins needs more time, increase it in `helm/jenkins-values.yaml`:

```yaml
  probes:
    startupProbe:
      failureThreshold: 120   # 120 × 10s = 20 min
      periodSeconds: 10
      timeoutSeconds: 5
```

Then upgrade/reload:

```bash
helm upgrade jenkins jenkins/jenkins -n jenkins -f helm/jenkins-values.yaml
# Or if you use ArgoCD: sync the jenkins application.
```

Then wait (or restart the pod once) and recheck:

```bash
kubectl get pods -n jenkins -l app.kubernetes.io/component=jenkins-controller -w
```

---

## 3. If Jenkins failed to start (bad plugin / OOM)

- **OOM:** Increase `controller.resources.limits.memory` and `controller.javaOpts` (e.g. `-Xmx3584m`) in `helm/jenkins-values.yaml`, then redeploy.
- **Plugin error:** If logs show a specific plugin failing:
  1. Temporarily remove that plugin from `controller.installPlugins` in `helm/jenkins-values.yaml`, or
  2. Disable it at runtime: exec into the pod and remove its directory under `$JENKINS_HOME/plugins`, then restart (only if you are comfortable with that).

- **`No hudson.slaves.Cloud implementation found for kubernetes`:** JCasC is applying a kubernetes cloud from the chart default, but the plugin isn’t ready at init. Fix: set `jenkins.clouds: []` in JCasC so no dynamic cloud is configured (you only use the static aks-agent). Add a configScript in `controller.JCasC.configScripts` (e.g. `no-kubernetes-cloud`) with `jenkins: clouds: []`, then redeploy.

---

## 4. After a restart: clean stale agents first

Pending or stuck agent pods and queued builds can block the Jenkins controller from deploying or running properly (same PVC, launcher state). **Clean stale agents and abort stuck queue items before expecting the new Jenkins pod to come up.**

1. **If Jenkins is reachable:** Run the cleanup script (skips `aks-agent` and Built-In Node):
   ```bash
   export JENKINS_URL="https://jenkins.canepro.me"   # or https://jenkins-oke.canepro.me before Phase 5 cutover
   export JENKINS_USER="admin"
   export JENKINS_PASSWORD="<api-token>"
   bash scripts/jenkins-clean-stale-agents.sh
   ```
   Then in the UI: **Build Queue** → abort any stuck items.

2. **If Jenkins is not reachable yet:** Delete the stuck agent pods so the controller can use the PVC and start:
   ```bash
   kubectl get pods -n jenkins
   kubectl delete pod -n jenkins <stale-agent-pod-names> --force --grace-period=0
   ```
   Then restart the controller pod if needed: `kubectl delete pod -n jenkins jenkins-0`.

3. After the controller is up, run the script (step 1) to remove stale agent *nodes* from Jenkins so new builds create fresh pod templates.

---

## 5. Agent pods: ImageInspectError (short name mode is enforcing)

On OKE (CRI-O), agent pods can fail with **ImageInspectError** and *short name mode is enforcing, but image name jenkins/inbound-agent:... returns ambiguous list*. CRI-O requires **fully qualified** image names (e.g. `docker.io/jenkins/inbound-agent:...`).

- **Fix in this repo (GrafanaLocal):** The Jenkinsfiles under `.jenkins/` use an explicit `jnlp` container with a **valid** tag, e.g. `docker.io/jenkins/inbound-agent:3355.v388858a_47b_33-8-jdk21`. Do **not** use `3302.v1cfe4e081049-1-jdk21` — that tag does not exist on Docker Hub (manifest unknown). Ensure changes are on **main** and pushed; then run the cleanup script (§4), abort stuck builds, and **re-run** the jobs.
- **Fix in rocketchat-k8s:** In that repo’s Jenkinsfile(s), add an explicit `jnlp` container with `docker.io/jenkins/inbound-agent:3355.v388858a_47b_33-8-jdk21` (or the same tag your plugin uses) in the pod yaml.
- **Cloud default:** `helm/jenkins-values.yaml` sets the Kubernetes cloud default jnlp image to the same tag with `docker.io/` so any job that doesn’t specify jnlp gets a qualified image. Sync ArgoCD and reload JCasC after changing it.

---

## 6. Stage view only shows "Declarative: Post Actions"

If the pipeline run shows **only** the stage "Declarative: Post Actions" and none of the real stages (e.g. "Resolve OCI config", "Install Tools", "Terraform Format"), the run **never got an agent**. Declarative runs `post { always { ... } }` even when no stage ran, so that is the only "stage" you see.

**Common cause:** Agent pod failed to start—usually **ImageInspectError** (unqualified image name) or pod scheduling failure. The pipeline fails during agent allocation; no stage runs on an agent; only post actions run.

**What to do:**

1. **Fix image names** – Ensure every Jenkinsfile that uses `kubernetes { ... yaml }` has an explicit `jnlp` container with a **fully qualified** image and a **tag that exists** on Docker Hub, e.g. `docker.io/jenkins/inbound-agent:3355.v388858a_47b_33-8-jdk21` (avoid `3302.v1cfe4e081049-1-jdk21` — manifest unknown). Same for any other images in the pod (e.g. `docker.io/hashicorp/terraform:latest`). See §5.
2. **Clean stale agents and queue** – Run `scripts/jenkins-clean-stale-agents.sh` (§4), abort stuck builds in the UI, then **re-run** the job so it uses the updated Jenkinsfile and a fresh pod.
3. **Confirm branch and script path** – Multibranch jobs must be scanning the branch that has the fixed Jenkinsfile (e.g. **main**). Job config should use the correct Script Path (e.g. `.jenkins/terraform-validation.Jenkinsfile`). After pushing fixes, run "Scan Multibranch Pipeline Now" and build the **main** (or correct) branch.
4. **Check build logs** – Open the failed run → Console Output. Look for errors **before** any stage (e.g. "Error provisioning agent", "ImageInspectError", "Unable to pull"). That confirms agent allocation failed.

Once the agent pod starts successfully, the normal stages will appear in the stage view and run.

---

## 7. Quick reference

| Symptom | Action |
|--------|--------|
| Pod Running, not Ready; logs show "starting" / "loading" | Wait 5–15 min or increase startup probe (§2). |
| Pod Restarting / CrashLoopBackOff | Check logs for OOM or exception; increase memory or disable problematic plugin (§3). |
| Logs say "Jenkins is fully up and running" but 503 | Check readiness probe; ensure service targets correct port (8080). |
| Agent pods ImageInspectError (short name) | Use `docker.io/jenkins/inbound-agent:...` in Jenkinsfile pod yaml and/or cloud default (§5). |
| Only "Declarative: Post Actions" in stage view | Agent never allocated; fix images (§5), clean stale agents (§4), re-run job; check Console for errors before first stage (§6). |
