# Jenkins CI Validation for central-observability-hub-stack

This directory contains Jenkinsfiles for CI validation.

## Available Pipelines
- terraform-validation.Jenkinsfile: Terraform validation
- k8s-manifest-validation.Jenkinsfile: Kubernetes manifest validation

## Setup
export JENKINS_URL="https://jenkins.canepro.me"
export JOB_NAME="central-observability-hub-stack"
export CONFIG_FILE=".jenkins/job-config.xml"
bash .jenkins/create-job.sh

## GitHub Webhook
URL: https://jenkins.canepro.me/github-webhook/
Events: Pull requests, Pushes
