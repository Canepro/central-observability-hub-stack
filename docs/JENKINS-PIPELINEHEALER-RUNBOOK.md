# Jenkins and PipelineHealer issue triage

Use this runbook when PipelineHealer opens low-context GitHub issues for this
repo. The goal is to separate repo-owned Jenkins failures from external
PipelineHealer or hosted GitHub/Copilot failures before editing source files.

Closing references for this triage pass: Closes #87, Closes #91, Closes #92,
Closes #93.

## Quick classifier

Run the deterministic local classifier against an issue body:

```bash
gh issue view 91 --json body --jq '.body' | python3 scripts/pipelinehealer-triage.py --pretty
```

Or fetch the issue directly:

```bash
python3 scripts/pipelinehealer-triage.py --issue 91 --pretty
```

Then validate the classification with the checks below.

## External Copilot autofind.js rate limits

Classification:

- `classification`: `external_copilot_autofind_rate_limit`
- `repo_side`: `no`
- Signal: issue body names `Config File: autofind.js` and `External API rate limit reached`.

Validation:

```bash
gh run view 26724719862 --json name,displayTitle,event,headBranch,conclusion,jobs
gh api repos/Canepro/central-observability-hub-stack/actions/jobs/78757906170/logs |
  rg -n -i 'autofind|rate limit|statusCode: 429|errorType'
```

Expected evidence:

- The workflow is GitHub's hosted Copilot code-review flow, not
  `.github/workflows/devops-quality-gate.yml`.
- Logs show `autofind.js` from the downloaded Copilot runtime.
- Logs show Copilot quota failure, usually `statusCode: 429` and
  `errorType: 'rate_limit'`.

Repo action:

- Do not patch GrafanaLocal for `autofind.js`; that file is not in this repo.
- Wait for the Copilot limit reset, switch Copilot to an allowed model/quota
  path, or rerun the hosted review after quota recovers.
- Close or comment on the PipelineHealer issue only after the hosted-run
  evidence above is attached.

## Jenkins bridge FileNotFoundError diagnosis failures

Classification:

- `classification`: `pipelinehealer_jenkins_bridge_diagnosis_runtime_error`
- `repo_side`: `no_repo_patch_identified`
- Signal: issue body has `source_selection_path: jenkins_bridge`,
  `bridge_evidence_quality: log_excerpt`, and root cause
  `Diagnosis failed: [Errno 2] No such file or directory`.

Current issue pattern:

| Issue | Jenkins job | Classification |
|---|---|---|
| `#91` | `GrafanaLocal/codex%2Foke-infisical-doc-cleanup#1` | PipelineHealer diagnosis runtime error |
| `#92` | `GrafanaLocal/PR-69#20` | PipelineHealer diagnosis runtime error |
| `#93` | `GrafanaLocal/main#129` | PipelineHealer diagnosis runtime error |

Why this is not automatically a repo bug:

- PipelineHealer accepted a Jenkins bridge payload with `log_excerpt` evidence.
- The failure happened after ingest, while PipelineHealer was diagnosing the
  payload.
- The issue marker uses Jenkins build numbers as synthetic workflow-run ids
  (`1`, `20`, `129`), so GitHub Actions lookups for those ids can return 404.
  That is expected for Jenkins bridge events and is not a GrafanaLocal workflow
  run failure.

Repo validation:

```bash
bash scripts/test-pipelinehealer-bridge.sh
python3 scripts/test-pipelinehealer-triage.py
```

Jenkins validation, read-only:

1. Open the `jenkins_job_url` from the issue body.
2. Check Console Output for the real failing command.
3. Patch GrafanaLocal only when the console points at a repo-owned file,
   Jenkinsfile, manifest, Helm values file, or helper script.
4. If the console shows only PipelineHealer diagnosis failure or GitHub Actions
   run id lookup failure, treat the issue as external PipelineHealer churn.

Duplicate handling:

- Group these issues by root cause, `source_selection_path`, and
  `pipelinehealer:signature`.
- Do not create separate repo patches for repeated issues that share the same
  `Diagnosis failed: [Errno 2] No such file or directory` signature unless the
  Jenkins console shows a new repo-owned failure.
- Duplicate suppression belongs in PipelineHealer. This repo's guard is the
  deterministic classifier and bridge smoke test.

## Bridge sender sanity check

The bridge sender is expected to:

- include `failure.log_excerpt` when a real Jenkins log excerpt exists
- drop HTML login/auth pages instead of forwarding them as evidence
- sign the POST with the configured bridge secret

Local proof:

```bash
bash scripts/test-pipelinehealer-bridge.sh
```

This does not contact Jenkins or PipelineHealer; it starts a local HTTP server
and verifies the payload shape.
