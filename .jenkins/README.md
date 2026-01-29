# Jenkins CI Validation for GrafanaLocal

This directory contains Jenkinsfiles for CI validation of the `GrafanaLocal` repository (central-observability-hub-stack).

## Available Pipelines

- **`terraform-validation.Jenkinsfile`**: Validates Terraform infrastructure code (format, validate, plan) for OKE
- **`k8s-manifest-validation.Jenkinsfile`**: Validates Kubernetes manifests
- **`security-validation.Jenkinsfile`**: Security scanning
- **`version-check.Jenkinsfile`**: Version update checking

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

### Option 1: CLI Setup (Recommended)

```bash
cd GrafanaLocal
export JENKINS_URL="https://jenkins.canepro.me"
export JOB_NAME="GrafanaLocal"
export CONFIG_FILE=".jenkins/job-config.xml"
bash .jenkins/create-job.sh
```

### Option 2: UI Setup

1. Go to Jenkins UI: https://jenkins.canepro.me
2. Click "New Item"
3. Enter job name: `GrafanaLocal`
4. Select "Multibranch Pipeline"
5. Configure GitHub branch source
6. Set Script Path: `.jenkins/terraform-validation.Jenkinsfile`

## GitHub Webhook

Configure webhook in repository settings:
- **URL**: `https://jenkins.canepro.me/github-webhook/`
- **Events**: Pull requests, Pushes
- **Content type**: `application/json`
