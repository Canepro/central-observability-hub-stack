#!/usr/bin/env bash
set -euo pipefail

warn() {
  echo "PipelineHealer bridge: $*" >&2
}

json_escape() {
  local value="${1:-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/}
  value=${value//$'\t'/\\t}
  value=${value//$'\f'/\\f}
  value=${value//$'\b'/\\b}
  printf '%s' "$value"
}

extract_url_path() {
  local url="$1"
  local without_scheme rest

  case "$url" in
    http://*) without_scheme="${url#http://}" ;;
    https://*) without_scheme="${url#https://}" ;;
    *) return 1 ;;
  esac

  [[ -n "$without_scheme" ]] || return 1
  [[ "$without_scheme" == */* ]] || {
    printf '/\n'
    return 0
  }

  rest="${without_scheme#*/}"
  printf '/%s\n' "${rest#/}"
}

extract_url_host() {
  local url="$1"
  local without_scheme

  case "$url" in
    http://*) without_scheme="${url#http://}" ;;
    https://*) without_scheme="${url#https://}" ;;
    *) return 1 ;;
  esac

  printf '%s\n' "${without_scheme%%/*}"
}

sanitize_commit_sha() {
  local commit="${1:-}"
  if [[ "$commit" =~ ^[0-9a-fA-F]{40}$ ]]; then
    printf '%s\n' "$commit"
  else
    printf '\n'
  fi
}

parse_int() {
  local value="${1:-0}"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
  else
    printf '0\n'
  fi
}

if [[ -z "${PH_BRIDGE_URL:-}" || -z "${PH_BRIDGE_SECRET:-}" ]]; then
  warn "missing PH_BRIDGE_URL or PH_BRIDGE_SECRET; skipping notification"
  exit 0
fi

for cmd in curl openssl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "required command '$cmd' is unavailable; skipping notification"
    exit 0
  fi
done

TARGET_URL="${PH_BRIDGE_URL%/}"
TARGET_PATH="$(extract_url_path "$TARGET_URL")" || {
  warn "invalid PH_BRIDGE_URL '${PH_BRIDGE_URL}'"
  exit 0
}

TIMESTAMP="$(date +%s)"
NONCE="${PH_NONCE:-jenkins-${JOB_NAME:-job}-${BUILD_NUMBER:-0}-${TIMESTAMP}}"
BODY_FILE="$(mktemp)"
EXCERPT_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$EXCERPT_FILE"' EXIT

if [[ -n "${PH_LOG_EXCERPT:-}" ]]; then
  printf '%s\n' "${PH_LOG_EXCERPT}" >"$EXCERPT_FILE"
elif [[ -n "${PH_LOG_EXCERPT_FILE:-}" && -f "${PH_LOG_EXCERPT_FILE}" ]]; then
  cat "${PH_LOG_EXCERPT_FILE}" >"$EXCERPT_FILE"
fi

RAW_EXCERPT=""
if [[ -f "$EXCERPT_FILE" ]]; then
  RAW_EXCERPT="$(tail -n 120 "$EXCERPT_FILE" 2>/dev/null || true)"
  if [[ -n "$RAW_EXCERPT" ]]; then
    RAW_EXCERPT="$(printf '%s' "$RAW_EXCERPT" | tail -c 20000)"
  fi
fi

if [[ "$RAW_EXCERPT" == "<html>"* || "$RAW_EXCERPT" == *"Authentication required"* ]]; then
  warn "discarding non-log bridge excerpt content"
  RAW_EXCERPT=""
fi

JOB_URL="${PH_JOB_URL:-${BUILD_URL:-}}"
JOB_HOST="$(extract_url_host "$JOB_URL" 2>/dev/null || true)"
JOB_NAME="${PH_JOB_NAME:-${JOB_NAME:-jenkins-job}}"
SUMMARY="${PH_FAILURE_SUMMARY:-Jenkins job ${JOB_NAME} failed}"
BUILD_NUMBER="$(parse_int "${PH_BUILD_NUMBER:-${BUILD_NUMBER:-0}}")"
DURATION_MS="$(parse_int "${PH_DURATION_MS:-0}")"
COMMIT_SHA="$(sanitize_commit_sha "${PH_COMMIT_SHA:-${GIT_COMMIT:-}}")"
SENT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"$BODY_FILE" <<EOF
{
  "schema_version": "1.0",
  "provider": "jenkins",
  "delivery_id": "$(json_escape "jenkins:${JOB_NAME}#${BUILD_NUMBER}")",
  "sent_at": "$(json_escape "$SENT_AT")",
  "repository": "$(json_escape "${PH_REPOSITORY:-Canepro/central-observability-hub-stack}")",
  "branch": "$(json_escape "${PH_BRANCH:-${GIT_BRANCH:-${BRANCH_NAME:-unknown}}}")",
  "commit_sha": "$(json_escape "$COMMIT_SHA")",
  "job": {
    "name": "$(json_escape "$JOB_NAME")",
    "url": "$(json_escape "$JOB_URL")",
    "build_number": ${BUILD_NUMBER},
    "result": "$(json_escape "${PH_RESULT:-FAILURE}")",
    "duration_ms": ${DURATION_MS}
  },
  "failure": {
    "stage": "$(json_escape "${PH_FAILURE_STAGE:-}")",
    "step": "$(json_escape "${PH_FAILURE_STEP:-}")",
    "command": "$(json_escape "${PH_FAILURE_COMMAND:-}")",
    "summary": "$(json_escape "$SUMMARY")",
    "log_excerpt": "$(json_escape "$RAW_EXCERPT")"
  },
  "artifacts": [],
  "metadata": {
    "jenkins_instance": "$(json_escape "$JOB_HOST")",
    "job_name": "$(json_escape "$JOB_NAME")",
    "build_url": "$(json_escape "$JOB_URL")",
    "bridge_excerpt_present": "$(json_escape "$([[ -n "$RAW_EXCERPT" ]] && printf true || printf false)")"
  }
}
EOF

BODY_SHA="$(openssl dgst -sha256 "$BODY_FILE" | awk '{print $NF}')"
CANONICAL="$(printf 'POST\n%s\n%s\n%s\n%s' "$TARGET_PATH" "$TIMESTAMP" "$NONCE" "$BODY_SHA")"
SIGNATURE="sha256=$(printf '%s' "$CANONICAL" | openssl dgst -sha256 -hmac "$PH_BRIDGE_SECRET" | awk '{print $NF}')"

curl -fsS -X POST "$TARGET_URL" \
  -H "Content-Type: application/json" \
  -H "X-PH-Bridge-Provider: jenkins" \
  -H "X-PH-Bridge-Timestamp: $TIMESTAMP" \
  -H "X-PH-Bridge-Nonce: $NONCE" \
  -H "X-PH-Bridge-Signature: $SIGNATURE" \
  --data-binary @"$BODY_FILE"
