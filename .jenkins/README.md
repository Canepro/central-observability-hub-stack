# Jenkins CI Validation for GrafanaLocal

This directory contains Jenkinsfiles for CI validation of the `GrafanaLocal` repository (central-observability-hub-stack).

## Available Pipelines

- **`terraform-validation.Jenkinsfile`**: Validates Terraform infrastructure code (format, validate, plan) for OKE
- **`k8s-manifest-validation.Jenkinsfile`**: Validates Kubernetes manifests
- **`security-validation.Jenkinsfile`**: Security scanning
- **`version-check.Jenkinsfile`**: Version update checking

## OCI Authentication Setup (Required for Terraform Plan)

The Terraform validation pipeline requires OCI credentials to run `terraform plan`.

### Required Jenkins Credentials

Create these credentials in Jenkins (Manage Jenkins > Credentials):

| Credential ID | Type | Description |
|---------------|------|-------------|
| `oci-api-key` | Secret file | OCI API private key (PEM file) |
| `oci-s3-access-key` | Secret text | OCI Object Storage S3 access key |
| `oci-s3-secret-key` | Secret text | OCI Object Storage S3 secret key |
| `oci-ssh-public-key` | Secret text | SSH public key for OKE nodes |

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
