# Grafana MCP SRE Access

This repo uses the official Grafana MCP server as the MCP surface for SRE
questions against the OKE observability hub.

Do not build a custom MCP server first. `grafana/mcp-grafana` already exposes
Grafana search, dashboards, Prometheus, Loki, alerting, datasource, navigation,
and optional panel-query tools through the Model Context Protocol.

References:

- Grafana MCP introduction: https://grafana.com/docs/grafana/latest/developer-resources/mcp/introduction/
- Tool filtering and read-only mode: https://grafana.com/docs/grafana-cloud/machine-learning/mcp/configure/enable-and-disable-tools
- Command-line flags: https://grafana.com/docs/grafana/latest/developer-resources/mcp/configure/command-line-flags/
- Upstream server: https://github.com/grafana/mcp-grafana

## Target Use

Use this for local SRE callups such as:

- finding dashboards and panels for an alert
- checking alert rules and alert state
- querying Prometheus for current hub or spoke metrics
- querying Loki for recent application or ingress logs
- opening Grafana deeplinks for the right dashboard or panel
- running dashboard panel queries when that tool is explicitly enabled
- creating or updating dashboards and alerting config in this lab cluster

The default local launcher is write-capable because this is Vincent's OKE
playground cluster. Set `GRAFANA_MCP_DISABLE_WRITE=true` for a temporary
read-only session.

## SRE Check Order

Treat Grafana as observability evidence, not the only source of truth. Before
calling a spoke broken, establish whether that spoke is expected to be online.

Default expected state:

| Target | Expected state | Source of truth |
| --- | --- | --- |
| OKE hub | Live | This repo and Grafana MCP telemetry |
| AKS spoke (`aks-canepro`, `k8.canepro.me`) | On-demand / cost parked unless explicitly started | Azure control plane plus `/Users/canepro/src/rocketchat-k8s` |

For OKE checks:

1. Use Grafana MCP to query Prometheus, Loki, alerting, and dashboards.
2. Verify scrape health, nodes, workloads, restarts, storage, capacity, and
   recent high-signal logs.
3. Treat OKE-local Argo CD apps as expected online unless a runbook says
   otherwise.

For AKS checks:

1. First decide whether AKS is supposed to be online for a job, migration,
   startup window, or explicit user request.
2. Use Azure control-plane truth before interpreting Grafana or Argo CD:
   `az` is available on Vincent's Mac at `/opt/homebrew/bin/az`.
3. Use `/Users/canepro/src/rocketchat-k8s` for AKS desired state, runbooks,
   manifests, and repo-local context.
4. Use Grafana and Argo CD as supporting evidence:
   - absent `cluster="aks-canepro"` metrics
   - Argo CD `Healthy/Unknown`
   - DNS failure for the AKS API hostname

Those signals are expected while AKS is parked. Escalate them only when Azure
or repo context says AKS should be online, or when startup/shutdown automation
reports failure.

Do not print Azure credentials, kubeconfigs, tokens, or full auth headers.
Azure CLI checks should stay read-only unless Vincent explicitly approves a
start, stop, scale, credential, or deployment action for the current task.

## Security Model

Use a dedicated Grafana service account token. Do not use a personal login,
Grafana admin password, or deprecated `GRAFANA_API_KEY`.

Initial recommended Grafana role:

- Editor for normal SRE read/write work in this lab cluster.
- Admin only if the enabled tools need account, role, or system-level actions.
- Keep a dedicated service account so MCP activity is auditable and revocable.

Store the token outside Git. For this repo, the durable secret class is:

| Field | Value |
| --- | --- |
| Consumer | local MCP client or operator workstation |
| Secret name | `GRAFANA_MCP_SERVICE_ACCOUNT_TOKEN` |
| Preferred store | Infisical |
| Environment | `prod` |
| Folder | `/platform/oke/monitoring` |
| Grafana URL | `https://grafana.canepro.me` |

Creating, reading, exporting, or rotating that token is a secret-value action.
Do it only with current-task approval. Public proof should show only secret name,
consumer, readiness, and successful tool calls with secret values redacted.

## Local Server

The tracked launcher is [scripts/run-grafana-mcp.sh](../scripts/run-grafana-mcp.sh).
It runs `mcp-grafana` over stdio. The script prefers the local
`mcp-grafana` binary when installed, then falls back to the upstream
`docker.io/grafana/mcp-grafana` container image. For containers, it prefers
Podman when `podman` is installed and falls back to Docker when needed. Set
`GRAFANA_MCP_RUNTIME=container`, `CONTAINER_RUNTIME=podman`, or
`CONTAINER_RUNTIME=docker` when you want to force a runtime.

```bash
export GRAFANA_URL="https://grafana.canepro.me"
export GRAFANA_SERVICE_ACCOUNT_TOKEN="<redacted>"
./scripts/run-grafana-mcp.sh
```

The script defaults to:

```bash
--enabled-tools search,datasource,prometheus,loki,alerting,dashboard,folder,navigation,rendering,runpanelquery,examples
```

It does not pass `--disable-write` unless `GRAFANA_MCP_DISABLE_WRITE=true` is
set in the environment.

`--enabled-tools` replaces Grafana MCP's default list, so keep the list explicit
when adding or removing categories. `rendering` can return panel or dashboard
images only when Grafana has the image renderer configured. Without that
dependency, use deeplinks as the fallback.

## Install Location

For local Codex, Cursor, Claude Desktop, or other stdio-based clients, the MCP
server is not installed in the cluster. The client starts
`scripts/run-grafana-mcp.sh` on the workstation, and the container talks to
`https://grafana.canepro.me` with the service account token.

It can run inside OKE if you want a shared HTTP MCP endpoint. In that shape:

- deploy `grafana/mcp-grafana` as a Kubernetes Deployment in `monitoring`
- use `-t streamable-http --address :8000`
- mount `GRAFANA_SERVICE_ACCOUNT_TOKEN` from an ExternalSecret backed by
  Infisical
- expose it as a ClusterIP Service first
- add Ingress only if a specific MCP client needs remote network access
- protect any Ingress with strong auth and network restrictions
- use `/healthz` for probes and `/mcp` for streamable HTTP clients

Prefer local stdio for a single operator workstation. Prefer in-cluster
streamable HTTP when more than one trusted client needs the same MCP endpoint or
when you want the server managed by ArgoCD like the rest of the hub.

## Codex MCP Client Shape

Use this shape in the local Codex MCP config. Keep the real token in a local
secret source, not in the repo.

```toml
[mcp_servers.grafana-sre]
command = "/Users/canepro/src/GrafanaLocal/scripts/run-grafana-mcp.sh"

[mcp_servers.grafana-sre.env]
GRAFANA_URL = "https://grafana.canepro.me"
GRAFANA_SERVICE_ACCOUNT_TOKEN = "<inject from Infisical or local secret manager>"
GRAFANA_MCP_DISABLE_WRITE = "false"
```

If the client cannot inject secrets directly, run the client from a shell where
Infisical has already injected `GRAFANA_SERVICE_ACCOUNT_TOKEN`, or use a
machine-local wrapper outside this public repo.

On this Mac, the local wrapper stores the durable Infisical secret as
`GRAFANA_MCP_SERVICE_ACCOUNT_TOKEN` and maps it to the upstream
`GRAFANA_SERVICE_ACCOUNT_TOKEN` name when launching `grafana/mcp-grafana`.

## Setup Steps

1. In Grafana, create a service account named `mcp-sre`.
2. Grant Editor, or narrower read/write RBAC scopes if you want to tune later.
3. Generate a service account token.
4. Store the token as `GRAFANA_MCP_SERVICE_ACCOUNT_TOKEN` in Infisical under
   `prod` and `/platform/oke/monitoring`.
5. Configure the MCP client to call `scripts/run-grafana-mcp.sh`.
6. Start a new MCP client session so it discovers the `grafana-sre` tools.
7. Run read/write smoke prompts:

```text
List Grafana datasources.
Find dashboards related to hub health.
Query Prometheus for up targets over the last 5 minutes.
Search Loki for recent ingress-nginx errors.
Create a scratch folder named mcp-smoke-test, then delete it.
```

## Verification

Good proof:

- MCP server starts without printing token values.
- Grafana datasource list succeeds.
- Dashboard search returns expected hub dashboards.
- Prometheus query returns series or a clear empty result.
- Loki query returns recent logs or a clear empty result.
- A low-risk write smoke succeeds, such as creating a scratch folder or test
  dashboard, then deleting it.

Do not paste token values, token IDs, cookies, or full auth headers into PRs,
chat, screenshots, reports, or commits.
