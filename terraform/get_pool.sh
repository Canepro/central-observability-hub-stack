#!/bin/bash

# Ensure we are in the script's directory so terraform finds the files
cd "$(dirname "$0")" || exit

echo "Starting OKE Node Pool Provisioning Loop..."

while true; do
  echo "Attempting to apply Terraform at $(date)..."

  # UPDATED: Timeout increased to 20 minutes (1200s) 
  # This allows time for the Cluster to build.
  timeout 1200s terraform apply -auto-approve

  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ]; then
    echo "SUCCESS! Infrastructure is ready."
    break
  else
    echo "Failed (Exit Code: $EXIT_CODE). Retrying in 60s..."
    sleep 60
  fi
done
