# Jenkins CI Validation for GrafanaLocal

This directory contains Jenkinsfiles for CI validation of the `GrafanaLocal` repository.

## Available Pipelines

- **`terraform-validation.Jenkinsfile`**: Validates Terraform infrastructure code (format, validate, plan)
- **`k8s-manifest-validation.Jenkinsfile`**: Validates Kubernetes manifests

## Azure Storage Setup

The Terraform validation pipeline downloads `terraform.tfvars` from Azure Storage using Key Vault.

**✅ Already Configured!** Environment variables are set in the Jenkinsfile:
- Key Vault: `aks-canepro-kv-e8d280`
- Storage Account: `tfcaneprostate1`
- Container: `tfstate`

See [QUICK_SETUP.md](../../rocketchat-k8s/.jenkins/QUICK_SETUP.md) in `rocketchat-k8s` for setup details.

## Security

For public repositories, use the secure version:
- **`terraform-validation.Jenkinsfile.secure`**: Uses Jenkins credentials instead of hardcoded values

To use it:
1. Create Jenkins credentials: `azure-client-id` and `azure-tenant-id`
2. Replace the Jenkinsfile with the secure version

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
