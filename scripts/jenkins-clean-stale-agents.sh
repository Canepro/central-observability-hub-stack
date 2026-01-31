#!/usr/bin/env bash
# Remove stale Kubernetes agent nodes from Jenkins after a restart.
# Use when you see "Unable to resolve pod template from id=..." for agents that
# were provisioning before Jenkins restarted.
#
# Run this (and abort stuck builds in the queue) before expecting the Jenkins
# controller to deploy/run properly—stuck agents and queued jobs can block the
# controller when it shares the same PVC or launcher state.
#
# Usage:
#   export JENKINS_URL="https://jenkins-oke.canepro.me"
#   export JENKINS_USER="admin"
#   export JENKINS_PASSWORD="<api-token-or-password>"
#   bash scripts/jenkins-clean-stale-agents.sh
#
# Or with crumb (script obtains crumb if JENKINS_USER/JENKINS_PASSWORD are set).

set -e
JENKINS_URL="${JENKINS_URL:-}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASSWORD="${JENKINS_PASSWORD:-}"

if [ -z "$JENKINS_URL" ]; then
  echo "Set JENKINS_URL (e.g. https://jenkins-oke.canepro.me)"
  exit 1
fi

if [ -z "$JENKINS_PASSWORD" ]; then
  echo "Set JENKINS_PASSWORD (API token or password)"
  exit 1
fi

BASE="${JENKINS_URL%/}"
echo "Getting crumb..."
CRUMB_JSON=$(curl -s -u "${JENKINS_USER}:${JENKINS_PASSWORD}" "${BASE}/crumbIssuer/api/json" || true)
if echo "$CRUMB_JSON" | grep -q "crumb"; then
  CRUMB_FIELD=$(echo "$CRUMB_JSON" | sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p')
  CRUMB_VAL=$(echo "$CRUMB_JSON" | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')
  CURL_OPTS=(-H "${CRUMB_FIELD}: ${CRUMB_VAL}")
else
  CURL_OPTS=()
fi

echo "Fetching computer list..."
JSON=$(curl -s -u "${JENKINS_USER}:${JENKINS_PASSWORD}" "${BASE}/computer/api/json?depth=0")

# Jenkins may return HTML (login/error) instead of JSON
if [ -z "$JSON" ] || [ "${JSON#\{}" = "$JSON" ]; then
  echo "Jenkins did not return JSON. Check JENKINS_URL and credentials (API token may have expired)."
  echo "Response starts with: ${JSON:0:80}"
  exit 1
fi

# Parse computer displayNames (no jq required)
NAMES=$(echo "$JSON" | grep -o '"displayName":"[^"]*"' | sed 's/"displayName":"//;s/"//')

COUNT=0
while IFS= read -r name; do
  [ -z "$name" ] && continue
  case "$name" in
    "Built-In Node"|"master"|"aks-agent"|"Nodes") continue ;;
  esac
  echo "Deleting stale agent: $name"
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST -u "${JENKINS_USER}:${JENKINS_PASSWORD}" "${CURL_OPTS[@]}" "${BASE}/computer/$(echo "$name" | sed 's/ /%20/g')/doDelete")
  [ "$HTTP" = "302" ] || [ "$HTTP" = "200" ] && COUNT=$((COUNT+1))
done <<< "$NAMES"

echo "Done ($COUNT agents deleted)."

# Clear Build Queue (cancel all queued items so Jenkins stops launching new agent pods)
echo "Fetching build queue..."
QUEUE_JSON=$(curl -s -u "${JENKINS_USER}:${JENKINS_PASSWORD}" "${BASE}/queue/api/json?depth=0")
if [ -n "$QUEUE_JSON" ] && [ "${QUEUE_JSON#\{}" != "$QUEUE_JSON" ]; then
  # Parse queue item IDs: "id":123
  QUEUE_IDS=$(echo "$QUEUE_JSON" | grep -o '"id":[0-9]*' | sed 's/"id"://g')
  QCOUNT=0
  for qid in $QUEUE_IDS; do
    echo "Cancelling queue item: $qid"
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST -u "${JENKINS_USER}:${JENKINS_PASSWORD}" "${CURL_OPTS[@]}" --data "id=${qid}" "${BASE}/queue/cancelItem")
    [ "$HTTP" = "302" ] || [ "$HTTP" = "200" ] && QCOUNT=$((QCOUNT+1))
  done
  echo "Queue: $QCOUNT item(s) cancelled."
else
  echo "Queue: empty or could not fetch."
fi

echo "All set. Re-run jobs when ready; new builds will create fresh pod templates."
