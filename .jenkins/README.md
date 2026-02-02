# Jenkins CI Validation for GrafanaLocal

This directory contains Jenkinsfiles for CI validation of the `GrafanaLocal` repository (central-observability-hub-stack). The Jenkins controller runs on OKE; pipelines use dynamic Kubernetes agents (OKE) or the static `aks-agent` (AKS) per [JENKINS-SPLIT-AGENT-PLAN.md](../hub-docs/JENKINS-SPLIT-AGENT-PLAN.md).

**Related:** [docs/JENKINS-MIGRATION-SUMMARY.md](../docs/JENKINS-MIGRATION-SUMMARY.md) (migration summary), [docs/JENKINS-503-TROUBLESHOOTING.md](../docs/JENKINS-503-TROUBLESHOOTING.md) (troubleshooting).

## Available Pipelines

- **`terraform-validation.Jenkinsfile`**: Validates Terraform infrastructure code (format, validate, plan) for OKE
- **`k8s-manifest-validation.Jenkinsfile`**: Validates Kubernetes manifests
- **`security-validation.Jenkinsfile`**: Security scanning
- **`version-check.Jenkinsfile`**: Version update checking

### Version check pipeline (PR creation)

The version-check pipeline compares Helm chart versions in `argocd/applications/*.yaml` to the latest in Helm repos. When updates are found it creates GitHub artifacts in the **repo root** (main branch):

- **HIGH (major version bump)** → creates a **GitHub issue** only (no PR).
- **MEDIUM (minor/patch)** → creates a **PR** when there is at least one medium update (threshold ≥ 1). The pipeline checks out a branch (e.g. `chore/helm-version-updates-YYYYMMDD`), updates `targetRevision` in the ArgoCD app manifests and the "Last Updated" date in `VERSION-TRACKING.md`, then pushes and opens the PR.

**PR content (auto-generated):** The PR description states that it includes version updates detected by automated checks, lists each update (e.g. `PROMETHEUS: 28.7.0 → 28.8.0`), links to the Jenkins build, and includes a review checklist (release notes, breaking changes, ArgoCD sync, `VERSION-TRACKING.md`). The PR diff contains the monitoring/observability manifest changes (e.g. Prometheus upgraded to the new patch) and the version-tracking document with updated "Last Updated" timestamps.

**Requirements for PR branch updates to work:**

- **mikefarah/yq** is required for in-place YAML edits. Alpine’s `apk yq` (kislyuk) uses different syntax; the pipeline installs mikefarah/yq to `/usr/local/bin/yq` so manifest updates (e.g. `argocd/applications/prometheus.yaml`) are applied correctly. Without it, the PR may only contain the `VERSION-TRACKING.md` date change.
- **WORKDIR** — All paths used when applying updates and when calling `curl -d @...` for GitHub API payloads use `WORKDIR="${WORKSPACE:-$(pwd)}"` so files are found regardless of current directory.

See `version-check.Jenkinsfile` comments for the exact logic (HIGH → issue; MEDIUM ≥ 1 → PR).

## Agent Image Requirements (OKE / CRI-O)

On OKE, the container runtime (CRI-O) requires **fully qualified** image names. Each Jenkinsfile that uses `agent { kubernetes { ... yaml } }` must specify an explicit `jnlp` container with a **valid** image tag from Docker Hub, e.g. `docker.io/jenkins/inbound-agent:3355.v388858a_47b_33-8-jdk21`. Do **not** use unqualified names (e.g. `jenkins/inbound-agent`) or tags that do not exist (e.g. `3302.v1cfe4e081049-1-jdk21` — manifest unknown). See [docs/JENKINS-503-TROUBLESHOOTING.md](../docs/JENKINS-503-TROUBLESHOOTING.md) §5 and §6 if builds fail with ImageInspectError or only show "Declarative: Post Actions".

## OCI Authentication Setup (Required for Terraform Plan)

The Terraform validation pipeline runs **format + validate** on every build (including PRs). When OCI parameters and credentials are **not** set (e.g. PR or branch validation), **Setup** and **Terraform Plan** are skipped so the job can pass without injecting secrets. To run a full **terraform plan**, set the parameters and credentials below in the Jenkins job.

### OCI Parameters: Build with Parameters vs Credentials

When you want to run **terraform plan**, the pipeline needs OCI **identifiers** (tenancy, user, fingerprint, region, compartment). You can supply them in either of two ways:

1. **Build with Parameters** – each run, open the branch job (e.g. **main**), click **Build with Parameters**, and fill in the five parameters. No setup beyond the job.
2. **Jenkins credentials (Secret text)** – create five Secret text credentials under the **GrafanaLocal** folder (or the folder that contains the multibranch job). The pipeline reads them when parameters are empty, so you don’t have to type values each time.

If both parameters and credentials are empty, the pipeline runs only **Terraform Format** and **Terraform Validate** (with `terraform init -backend=false`), so PR and branch builds pass without OCI credentials.

**Credential IDs** (create as **Secret text** under the GrafanaLocal folder). Use the **Description** field in Jenkins so you know what each one is later:

| Credential ID           | Description | Secret text value |
|-------------------------|-------------|-------------------|
| `oci-tenancy-ocid`      | OCI Tenancy OCID – root compartment ID; from `grep tenancy ~/.oci/config` or OCI Console > Tenancy Details | Tenancy OCID |
| `oci-user-ocid`         | OCI User OCID – the user that owns the API key; from `grep user ~/.oci/config` or OCI Console > Identity > Users | User OCID |
| `oci-fingerprint`       | OCI API key fingerprint – from `grep fingerprint ~/.oci/config` or OCI Console > User > API Keys; matches the PEM in `oci-api-key` | Fingerprint |
| `oci-region`            | OCI region – e.g. `us-ashburn-1`; from `grep region ~/.oci/config` or OCI Console | Region |
| `tf-var-compartment-id` | Terraform compartment – OCID where OKE/OKE Hub resources live; often same as tenancy (root) or a child compartment | Compartment OCID |

**How to create:** Jenkins → your folder (e.g. GrafanaLocal) → **Credentials** → **Add** → **Jenkins** → Kind: **Secret text**, ID: (exact ID from table), **Description**: (copy from table), Secret: the value → **Create**. Repeat for the five IDs above.

**Priority:** If you fill in **Build with Parameters**, those values are used. If all five parameters are empty, the pipeline uses the credentials above (and fails if any credential is missing).

### Required Jenkins Credentials

Create these credentials in Jenkins (Manage Jenkins > Credentials). Use the **Description** field so you know what each one is later:

| Credential ID | Type | Description |
|---------------|------|-------------|
| `oci-api-key` | Secret file | OCI API private key (PEM file). From OCI Console > Identity > Users > Your User > API Keys. Used by Terraform/OCI CLI. |
| `oci-s3-access-key` | Secret text | OCI Customer Secret Key **access key** (S3-compatible). From OCI Console > Users > Customer Secret Keys. Used for Terraform state backend. |
| `oci-s3-secret-key` | Secret text | OCI Customer Secret Key **secret** (shown once when you create the key). Used with oci-s3-access-key for state backend. |
| `oci-ssh-public-key` | Secret text | SSH **public** key (e.g. `ssh-rsa AAAA...`). Injected as TF_VAR_ssh_public_key for OKE node access. |

### How to Get OCI Credentials

1. **OCI API Key**: Generate from OCI Console > Identity > Users > Your User > API Keys
2. **S3 Access/Secret Keys**: OCI Console > Identity > Users > Your User > Customer Secret Keys
3. **SSH Public Key**: Your existing SSH public key for OKE node access

### Terraform State Backend

State is stored in OCI Object Storage (S3-compatible):
- Bucket: `terraform-state`
- Key: `oke-hub/terraform.tfstate`
- Namespace: `iducrocaj9h2`

Create the bucket if it doesn't exist:
```bash
oci os bucket create --name terraform-state --compartment-id $COMPARTMENT_ID
```

### OCI S3 Authentication Notes

OCI Customer Secret Keys often contain special characters (`/`, `+`, `=`) that cause `SignatureDoesNotMatch` errors when passed via environment variables.

**Solution**: The Jenkinsfile passes credentials directly via `-backend-config` flags:
```bash
terraform init \
  -backend-config="access_key=${S3_ACCESS_KEY}" \
  -backend-config="secret_key=${S3_SECRET_KEY}"
```

**Local development**: Use a `backend.hcl` file (gitignored):
```hcl
access_key = "your_access_key"
secret_key = "your_secret_key"
```
Then run: `terraform init -backend-config=backend.hcl`

### Terraform plan artifacts

For safety, the pipeline does **not** archive `terraform show` output by default, because plan output can contain sensitive resource attributes. If you need artifacts, restrict access/retention and avoid publishing sensitive values.

## Setup in Jenkins

**Note:** UI config changes are locked in this environment. Use the CLI/API config files in `.jenkins/` (job-config XML) or Jenkins REST API updates.

### Option 1: CLI Setup (Recommended)

Use **JENKINS_URL** for the Jenkins controller (production URL is OKE):

```bash
cd GrafanaLocal
export JENKINS_URL="https://jenkins.canepro.me"
export JOB_NAME="GrafanaLocal"
export CONFIG_FILE=".jenkins/job-config.xml"
bash .jenkins/create-job.sh
```

**Note:** Create the **github-token** credential on that Jenkins first (Manage Jenkins → Credentials), or the multibranch scan will fail. See [hub-docs/JENKINS-SPLIT-AGENT-PLAN.md](../hub-docs/JENKINS-SPLIT-AGENT-PLAN.md) for jobs, pipelines, and credentials.

### Option 2: UI Setup

1. Go to Jenkins UI: https://jenkins.canepro.me
2. Click "New Item"
3. Enter job name: `GrafanaLocal`
4. Select "Multibranch Pipeline"
5. Configure GitHub branch source (credential ID: **github-token**)
6. Set Script Path: `.jenkins/terraform-validation.Jenkinsfile`

## GitHub Webhook

Configure webhook in repository settings to point at the **active** Jenkins URL (OKE after migration):

- **URL**: `https://jenkins.canepro.me/github-webhook/`
- **Events**: Pull requests, Pushes
- **Content type**: `application/json`
