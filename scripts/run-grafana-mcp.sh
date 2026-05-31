#!/usr/bin/env bash
set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-https://grafana.canepro.me}"
GRAFANA_MCP_ENABLED_TOOLS="${GRAFANA_MCP_ENABLED_TOOLS:-search,datasource,prometheus,loki,alerting,dashboard,folder,navigation,rendering,runpanelquery,examples}"
GRAFANA_MCP_DISABLE_WRITE="${GRAFANA_MCP_DISABLE_WRITE:-false}"
GRAFANA_MCP_IMAGE="${GRAFANA_MCP_IMAGE:-docker.io/grafana/mcp-grafana}"
GRAFANA_MCP_RUNTIME="${GRAFANA_MCP_RUNTIME:-auto}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-}"

if [[ -z "${CONTAINER_RUNTIME}" ]]; then
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
  elif command -v docker >/dev/null 2>&1; then
    CONTAINER_RUNTIME="docker"
  else
    echo "podman or docker is required to run grafana/mcp-grafana." >&2
    exit 1
  fi
fi

if [[ -z "${GRAFANA_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
  cat >&2 <<'EOF'
GRAFANA_SERVICE_ACCOUNT_TOKEN is required.

Create a dedicated Grafana service account token, store it outside Git, then
inject it into this process as GRAFANA_SERVICE_ACCOUNT_TOKEN.
EOF
  exit 1
fi

grafana_mcp_args=(
  -t stdio
  --enabled-tools "${GRAFANA_MCP_ENABLED_TOOLS}"
)

if [[ "${GRAFANA_MCP_DISABLE_WRITE}" == "true" ]]; then
  grafana_mcp_args+=(--disable-write)
fi

if [[ "${GRAFANA_MCP_RUNTIME}" != "container" ]] && command -v mcp-grafana >/dev/null 2>&1; then
  export GRAFANA_URL
  export GRAFANA_SERVICE_ACCOUNT_TOKEN
  if [[ -n "${GRAFANA_ORG_ID:-}" ]]; then
    export GRAFANA_ORG_ID
  fi
  exec mcp-grafana "${grafana_mcp_args[@]}"
fi

if [[ "${CONTAINER_RUNTIME}" == "podman" ]] && podman machine list >/dev/null 2>&1; then
  podman_machine="${PODMAN_MACHINE:-}"
  if [[ -z "${podman_machine}" ]]; then
    podman_machine="$(podman machine list --format '{{.Name}} {{.Default}}' | awk '$2 == "true" {gsub(/\\*/, "", $1); print $1; exit}')"
  fi
  podman_machine="${podman_machine:-podman-machine-default}"
  podman_state="$(podman machine inspect "${podman_machine}" --format '{{.State}}' 2>/dev/null || true)"
  if [[ "${podman_state}" != "running" ]]; then
    podman machine start "${podman_machine}" >&2
  fi
fi

container_args=(
  run
  --pull=missing
  --rm
  -i
  -e "GRAFANA_URL=${GRAFANA_URL}"
  -e "GRAFANA_SERVICE_ACCOUNT_TOKEN=${GRAFANA_SERVICE_ACCOUNT_TOKEN}"
)

if [[ -n "${GRAFANA_ORG_ID:-}" ]]; then
  container_args+=(-e "GRAFANA_ORG_ID=${GRAFANA_ORG_ID}")
fi

exec "${CONTAINER_RUNTIME}" "${container_args[@]}" "${GRAFANA_MCP_IMAGE}" \
  "${grafana_mcp_args[@]}"
