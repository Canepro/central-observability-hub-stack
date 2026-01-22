#!/bin/bash
# Quick script to create Jenkins Multibranch Pipeline job via CLI
# Handles CSRF token automatically
# Note: This script must use Unix line endings (LF), not Windows (CRLF)

set -euo pipefail

# Configuration
JENKINS_URL="${JENKINS_URL:-https://jenkins.canepro.me}"
JOB_NAME="${JOB_NAME:-rocketchat-k8s}"
CONFIG_FILE="${CONFIG_FILE:-.jenkins/job-config.xml}"
JENKINS_USER="${JENKINS_USER:-}"

# Some Jenkins setups validate crumbs against the HTTP session.
# Keep a cookie jar and reuse it for crumb + POST requests.
COOKIE_JAR="$(mktemp -t jenkins-cookies.XXXXXX)"
cleanup() {
  rm -f "$COOKIE_JAR" 2>/dev/null || true
}
trap cleanup EXIT

# Get Jenkins credentials from Kubernetes secret (unless provided via env)
echo "Getting Jenkins admin credentials from Kubernetes secret..."
if [ -z "${JENKINS_USER}" ]; then
  JENKINS_USER=$(kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || true)
fi

JENKINS_PASSWORD="${JENKINS_PASSWORD:-}"
if [ -z "${JENKINS_PASSWORD}" ]; then
  JENKINS_PASSWORD=$(kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
fi

if [ -z "${JENKINS_USER}" ] || [ -z "${JENKINS_PASSWORD}" ]; then
  echo "❌ Failed to get Jenkins credentials from Kubernetes secret"
  if [ -z "${JENKINS_USER}" ]; then
    echo "Please provide username manually:"
    read -r JENKINS_USER
  fi
  if [ -z "${JENKINS_PASSWORD}" ]; then
    echo "Please provide password (or API token) manually:"
    read -rs JENKINS_PASSWORD
    echo ""
  fi
fi

# Get CSRF token (required when CSRF protection is enabled)
echo "Getting CSRF token..."
# Use JSON endpoint for more reliable parsing
CRUMB_JSON=$(curl -sS -L \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  "$JENKINS_URL/crumbIssuer/api/json")

# Check if we got a valid response
if [ -z "$CRUMB_JSON" ]; then
  echo "❌ Empty response from CSRF token endpoint"
  exit 1
fi

if echo "$CRUMB_JSON" | grep -q "Error\|401\|403"; then
  echo "❌ Failed to get CSRF token. Check credentials."
  echo "Response: $CRUMB_JSON"
  exit 1
fi

# Parse JSON response to extract crumb field and value
# Using jq if available, otherwise grep
if command -v jq &> /dev/null; then
  CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField')
  CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb')
else
  CRUMB_FIELD=$(echo "$CRUMB_JSON" | grep -o '"crumbRequestField":"[^"]*"' | cut -d'"' -f4)
  CRUMB_VALUE=$(echo "$CRUMB_JSON" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$CRUMB_FIELD" ] || [ -z "$CRUMB_VALUE" ] || [ "$CRUMB_FIELD" = "null" ] || [ "$CRUMB_VALUE" = "null" ]; then
  echo "❌ Failed to parse CSRF token from JSON response"
  echo "Response: $CRUMB_JSON"
  echo "Parsed field: '$CRUMB_FIELD', value: '${CRUMB_VALUE:0:10}...'"
  exit 1
fi

echo "✅ CSRF token obtained: $CRUMB_FIELD:${CRUMB_VALUE:0:10}..."

# Check if job already exists
echo "Checking if job already exists..."
EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -H "$CRUMB_FIELD:$CRUMB_VALUE" \
  "$JENKINS_URL/job/$JOB_NAME/api/json")

if [ "$EXISTS" = "200" ]; then
  echo "⚠️  Job '$JOB_NAME' already exists. Deleting it first..."
  curl -X POST \
    -u "$JENKINS_USER:$JENKINS_PASSWORD" \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -H "$CRUMB_FIELD:$CRUMB_VALUE" \
    "$JENKINS_URL/job/$JOB_NAME/doDelete"
  echo "✅ Old job deleted"
fi

# Verify config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config file not found: $CONFIG_FILE"
  exit 1
fi

echo "Using config file: $CONFIG_FILE ($(wc -c < "$CONFIG_FILE") bytes)"

# Create job
echo "Creating job: $JOB_NAME"
RESPONSE=$(curl -sS -L -w "\n%{http_code}" -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -H "$CRUMB_FIELD:$CRUMB_VALUE" \
  -H "Content-Type: application/xml" \
  --data-binary @"$CONFIG_FILE" \
  "$JENKINS_URL/createItem?name=$JOB_NAME")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "✅ Job created successfully!"
  
  # Trigger initial multibranch indexing
  # (Some Jenkins instances don't expose /scan; /build?delay=0sec triggers Branch Indexing.)
  echo "Triggering initial indexing..."
  INDEX_RESPONSE=$(curl -sS -L -w "\n%{http_code}" -X POST \
    -u "$JENKINS_USER:$JENKINS_PASSWORD" \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -H "$CRUMB_FIELD:$CRUMB_VALUE" \
    "$JENKINS_URL/job/$JOB_NAME/build?delay=0sec")
  
  INDEX_CODE=$(echo "$INDEX_RESPONSE" | tail -n1)
  
  if [ "$INDEX_CODE" = "200" ] || [ "$INDEX_CODE" = "201" ] || [ "$INDEX_CODE" = "302" ]; then
    echo "✅ Initial indexing triggered!"
    echo ""
    echo "Job URL: $JENKINS_URL/job/$JOB_NAME"
    echo "Check job status in Jenkins UI or wait a few moments for the scan to complete."
  else
    echo "⚠️  Index trigger returned HTTP $INDEX_CODE (job was created but indexing may have failed)"
    echo "Response: $(echo "$INDEX_RESPONSE" | head -n-1)"
  fi
else
  echo "❌ Failed to create job. HTTP Status: $HTTP_CODE"
  if [ -n "$RESPONSE_BODY" ]; then
    echo "Response body:"
    echo "$RESPONSE_BODY"
  fi
  echo ""
  echo "Troubleshooting:"
  echo "1. Check if job already exists: curl -u \"$JENKINS_USER:****\" \"$JENKINS_URL/job/$JOB_NAME/api/json\""
  echo "2. Check Jenkins logs: kubectl logs -n jenkins jenkins-0 -c jenkins --tail=50"
  echo "3. Verify XML config is valid: cat $CONFIG_FILE | head -20"
  exit 1
fi
