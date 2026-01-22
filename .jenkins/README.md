# Jenkins CI Validation for GrafanaLocal

This directory contains Jenkinsfiles for CI validation of the `GrafanaLocal` repository.

## Available Pipelines

See the Jenkinsfiles in this directory for available validation pipelines.

## Setup in Jenkins

### Option 1: CLI Setup (Recommended)

```bash
# From this repository directory
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
6. Set Script Path to the appropriate Jenkinsfile (e.g., `.jenkins/terraform-validation.Jenkinsfile`)

## GitHub Webhook

Configure webhook in repository settings:
- **URL**: `https://jenkins.canepro.me/github-webhook/`
- **Events**: Pull requests, Pushes
- **Content type**: `application/json`

## More Information

See [JENKINS_STRATEGY.md](../../rocketchat-k8s/JENKINS_STRATEGY.md) in the `rocketchat-k8s` repository for:
- Understanding what Jenkins does
- How to maximize Jenkins across repos
- Best practices
