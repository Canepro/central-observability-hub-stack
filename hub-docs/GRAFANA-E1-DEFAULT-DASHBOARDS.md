# Grafana E1: Default dashboards to provision

With **E1** (Grafana on emptyDir, freed 50GB for Jenkins), Grafana has no persistent storage. Dashboards must be re-provisioned on each pod start from **git** (and optionally backed up to S3). This doc lists your current dashboards, maps them to public Grafana.com IDs where possible, and defines the **default set** to include by default so Grafana is useful after every restart.

---

## 1. Your current dashboard list (reference)

| Your name | Tags / folder | Grafana.com ID / source |
|-----------|----------------|-------------------------|
| **AKS Maintenance Jobs** | aks-canepro, cronjobs, kubernetes, maintenance | **Custom — in-repo (code)**. Add JSON to `dashboards/` and provisioning; do not limit to what was there — extend as needed. |
| K8S Dashboard CN 20240513 StarsL.cn | Kubernetes, Prometheus, StarsL.cn | **13105** |
| Kubernetes / Views / Global | Kubernetes, Prometheus | **15757** |
| Kubernetes / Views / Pods | Kubernetes, Prometheus | **15760** |
| Master Health Dashboard | health, hub, spoke | **In-repo** (inline in `helm/grafana-values.yaml` + `dashboards/master-health-backup.json`) |
| Node Exporter Full | linux | **1860** |
| Rocket.Chat Metrics | — | **23428** |
| Rocket.Chat MicroService Metrics | — | **23427** |
| Rocket.Chat MongoDB Single Node Overview | use1, workspace | **23712** |
| Windows Exporter Dashboard 20230531-StarsL.cn | Prometheus, StarsL.cn, windows_exporter | **10467** |
| Unified World Tree | — | **In-repo** (`dashboards/unified-world-tree.json`) |

---

## 2. Curated public dashboards (cool & useful by default)

Use these **Grafana.com dashboard IDs** for provisioning (import by ID in UI, or download JSON and add to repo for full GitOps).

| Purpose | Grafana.com ID | Name | Datasource | Notes |
|---------|----------------|------|------------|--------|
| **Linux / node metrics** | **1860** | Node Exporter Full | Prometheus | Classic; needs `node` scrape job. Recommended args for node-exporter: `--collector.systemd --collector.processes`. |
| **Kubernetes / Views / Global** | **15757** | Kubernetes / Views / Global | Prometheus | Grafana Labs; cluster overview. |
| **Kubernetes / Views / Pods** | **15760** | Kubernetes / Views / Pods | Prometheus | Pod-level view (Grafana Labs / dotdc). |
| **Kubernetes / Views / Namespaces** | **15758** | Kubernetes / Views / Namespaces | Prometheus | Namespace-level view. |
| **Kubernetes / Views / Nodes** | **15759** | Kubernetes / Views / Nodes | Prometheus | Node-level view. |
| **Kubernetes / Views / Workloads** | **15761** | Kubernetes / Views / Workloads | Prometheus | Deployments, StatefulSets, etc. |
| **K8S Dashboard CN (StarsL.cn)** | **13105** | K8S Dashboard CN 20240513 StarsL.cn | Prometheus | [grafana.com/grafana/dashboards/13105](https://grafana.com/grafana/dashboards/13105-k8s-dashboard-cn-20240513-starsl-cn/). |
| **Rocket.Chat Metrics** | **23428** | Rocket.Chat Metrics | Prometheus | Community. |
| **Rocket.Chat MicroService Metrics** | **23427** | Rocket.Chat MicroService Metrics | Prometheus | Community. |
| **Rocket.Chat MongoDB Single Node** | **23712** | Rocket.Chat MongoDB Single Node Overview | Prometheus | Community. |
| **Windows Exporter StarsL.cn** | **10467** | Windows Exporter for Prometheus Dashboard CN v20230531 (StarsL.cn) | Prometheus | [URL](https://grafana.com/grafana/dashboards/10467-windows-exporter-for-prometheus-dashboard-cn-v20230531/). |
| **Windows nodes (generic)** | **14696** | Windows Exporter Dashboard | Prometheus | Alternative; for Windows Exporter metrics. |
| **MongoDB (single node)** | **2583** | MongoDB Overview | Prometheus | If you scrape MongoDB exporter. |

**AKS Maintenance Jobs (custom):** Keep in code (e.g. `dashboards/aks-maintenance-jobs.json`); extend with cool panels and best practices. Windows Exporter StarsL.cn = ID **10467** (see table above).

---

### 2a. Cool / best-practice dashboards (recommended additions)

Beyond your current list, consider adding these for observability-stack and platform health. Add by ID to provisioning or download JSON into `dashboards/`.

| Purpose | Grafana.com ID | Name | Datasource | Notes |
|---------|----------------|------|------------|--------|
| **Prometheus overview** | **3662** | Prometheus 2.0 Overview | Prometheus | Scrape health, retention, query performance. |
| **Prometheus stats** | **3663** | Prometheus Stats | Prometheus | TSDB, rules, targets. |
| **Loki / logs** | **12019** | Loki Dashboard | Loki | Log volume, query performance; useful if you use Loki. |
| **Loki dashboard (alt)** | **13186** | Loki Dashboard | Loki | This repo provisions **13186** + **12019** by default. (These two currently collide on UID upstream; see troubleshooting below.) |
| **Loki datasource (optional)** | **13639** | Loki & Prometheus | Loki + Prometheus | Combined logs + metrics (optional). |
| **Tempo / traces** | **23242** | OpenTelemetry + Tempo | Tempo | This repo provisions **23242** by default (patched for file provisioning). |
| **NGINX Ingress** | **9614** | NGINX Ingress controller | Prometheus | Request rate, latency, errors; matches your Hub ingress. |
| **NGINX Ingress (alt)** | **14314** | NGINX Ingress Controller (Prometheus) | Prometheus | Alternative; very popular. |
| **ArgoCD** | **14583** | Argo CD - Application metrics | Prometheus | App sync status, health; if you scrape ArgoCD metrics. |
| **ArgoCD (alt)** | **14584** | Argo CD - Overview | Prometheus | Overview of Argo CD. |
| **Alertmanager** | **8010** | Alertmanager | Prometheus | Firing alerts, silences; if you use Alertmanager. |
| **Alerts overview** | **9578** | Alerts | Prometheus | Useful once Prometheus alert rules exist (uses `ALERTS` / rule metrics). |
| **Kubernetes API server** | **15762** | Kubernetes / Views / API server | Prometheus | API server latency, errors (dotdc set). |
| **etcd** | **3070** | etcd | Prometheus | If you scrape etcd metrics. |

**Best practice:** Start with Prometheus (3662 or 3663), NGINX Ingress (9614 or 14314), and — if you use them — Loki (13186/12019), Tempo (23242), ArgoCD (14583/14584). Add others as needed.

---

## 3. Default set to include by default (E1)

So that Grafana is useful out of the box after every restart (no manual import), provision at least:

| # | Dashboard | Grafana.com ID | How |
|---|-----------|----------------|-----|
| 1 | **Master Health Dashboard** | — | In-repo: inline in `helm/grafana-values.yaml` and backup in `dashboards/master-health-backup.json`. |
| 2 | **Unified World Tree** | — | In-repo: `dashboards/unified-world-tree.json`. Ensure it is in the provisioning path (see below). |
| 3 | **Node Exporter Full** | **1860** | Add to provisioning (download JSON or import by ID). |
| 4 | **Kubernetes / Views / Global** | **15757** | Add to provisioning (download JSON or import by ID). |
| 5 | **Kubernetes / Views / Pods** | **15760** | Add to provisioning (download JSON or import by ID). |
| 6 | **K8S Dashboard CN 20240513 StarsL.cn** | **13105** | Add to provisioning; [URL](https://grafana.com/grafana/dashboards/13105-k8s-dashboard-cn-20240513-starsl-cn/). |
| 7 | **Rocket.Chat Metrics** | **23428** | Add to provisioning (download JSON or import by ID). |
| 8 | **Rocket.Chat MicroService Metrics** | **23427** | Add to provisioning (download JSON or import by ID). |
| 9 | **Rocket.Chat MongoDB Single Node Overview** | **23712** | Add to provisioning (download JSON or import by ID). |
| 10 | **Windows Exporter 20230531 StarsL.cn** | **10467** | Add to provisioning; [URL](https://grafana.com/grafana/dashboards/10467-windows-exporter-for-prometheus-dashboard-cn-v20230531/). |
| 11 | **AKS Maintenance Jobs** | — | **In-repo:** `dashboards/aks-maintenance-jobs.json` (custom; add to code and extend with cool panels / best practices). |

Optional (add if you use them):

- **15758** (Namespaces), **15759** (Nodes), **15761** (Workloads)
- **14696** (Windows Exporter generic) if you prefer over 10467
- **2583** (MongoDB Overview) if you scrape MongoDB
- See **§2a** below for more cool / best-practice dashboards (Prometheus, Loki, Tempo, NGINX Ingress, ArgoCD, etc.)

---

## 4. How to provision (E1)

1. **In-repo JSON**  
   - Place dashboard JSONs under `dashboards/` (e.g. `master-health-backup.json`, `unified-world-tree.json`, and any new files like `node-exporter-full.json`).  
   - These files are packaged into a ConfigMap by the `grafana-dashboards` ArgoCD app (see `argocd/applications/grafana-dashboards.yaml` + `dashboards/kustomization.yaml`).  
   - Grafana mounts them into the provider path via `extraConfigmapMounts` in `helm/grafana-values.yaml`, so they load on every Grafana start (E1).

2. **Public IDs**  
   - **Option A:** Download JSON from `https://grafana.com/api/dashboards/<ID>/revisions/<rev>/download` (or from the UI), save into `dashboards/<name>.json`, and add to provisioning so they load from git.  
   - **Option B:** Document “After Grafana starts, import these IDs: 1860, 15757, 15760, 13105, 23428, 23427, 23712, 10467” (and optionally 15758, 15759, 15761, 14696, 2583) and optionally script it (e.g. Grafana API or Terraform/Helm post-install).

3. **Optional S3 backup**  
   - For extra safety, back up dashboard JSONs (or full provisioning dir) to your OCI S3 bucket. On restore you can re-provision from S3 or copy back into git and re-deploy.

---

## 5. Verify provisioning path

- Current provider in `helm/grafana-values.yaml`: `path: /var/lib/grafana/dashboards/default`.  
- In-repo dashboards in `dashboards/*.json` are mounted into that path via:
  - ArgoCD app `grafana-dashboards` (creates ConfigMap `grafana-dashboards-repo`)
  - Grafana Helm value `extraConfigmapMounts` (mounts each JSON into `/var/lib/grafana/dashboards/default/`)

---

## 6. Troubleshooting dashboard provisioning (common)

### Error: "the same UID is used more than once"

Some Grafana.com dashboards ship with the same `"uid"` value across multiple dashboards. When file-provisioning sees duplicate UIDs, Grafana will reject one (or both) and the whole provider can behave badly.

**This repo fix:** `helm/grafana-values.yaml` includes an initContainer (`fix-dashboard-uids`) that patches the downloaded JSON on startup to enforce unique UIDs.

### Loki dashboard error: `parse error ... unexpected IDENTIFIER`

If a Loki dashboard panel/variable is accidentally using **Prometheus-style templating** (PromQL) while the datasource is **Loki**, Grafana sends the wrong query to Loki and you’ll see:

`parse error at line 1, col 1: syntax error: unexpected IDENTIFIER`

**This repo fix:** `helm/grafana-values.yaml` initContainer rewrites the affected Loki dashboards so variables use Loki `label_values(...)` semantics and filters use `pod=...` instead of `instance=...` (matching our promtail labels).

---

## 7. Quick reference: Grafana.com IDs and URLs

| ID | Dashboard name | URL |
|----|----------------|-----|
| 1860 | Node Exporter Full | https://grafana.com/grafana/dashboards/1860 |
| 13105 | K8S Dashboard CN 20240513 StarsL.cn | https://grafana.com/grafana/dashboards/13105-k8s-dashboard-cn-20240513-starsl-cn/ |
| 15757 | Kubernetes / Views / Global | https://grafana.com/grafana/dashboards/15757 |
| 15758 | Kubernetes / Views / Namespaces | https://grafana.com/grafana/dashboards/15758 |
| 15759 | Kubernetes / Views / Nodes | https://grafana.com/grafana/dashboards/15759 |
| 15760 | Kubernetes / Views / Pods | https://grafana.com/grafana/dashboards/15760 |
| 15761 | Kubernetes / Views / Workloads | https://grafana.com/grafana/dashboards/15761 |
| 23427 | Rocket.Chat MicroService Metrics | https://grafana.com/grafana/dashboards/23427 |
| 23428 | Rocket.Chat Metrics | https://grafana.com/grafana/dashboards/23428 |
| 23712 | Rocket.Chat MongoDB Single Node Overview | https://grafana.com/grafana/dashboards/23712 |
| 10467 | Windows Exporter 20230531 StarsL.cn | https://grafana.com/grafana/dashboards/10467-windows-exporter-for-prometheus-dashboard-cn-v20230531/ |
| 14696 | Windows Exporter Dashboard (generic) | https://grafana.com/grafana/dashboards/14696 |
| 2583 | MongoDB Overview | https://grafana.com/grafana/dashboards/2583 |
| 3662 | Prometheus 2.0 Overview | https://grafana.com/grafana/dashboards/3662 |
| 3663 | Prometheus Stats | https://grafana.com/grafana/dashboards/3663 |
| 8010 | Alertmanager | https://grafana.com/grafana/dashboards/8010 |
| 9578 | Alerts | https://grafana.com/grafana/dashboards/9578 |
| 9614 | NGINX Ingress controller | https://grafana.com/grafana/dashboards/9614 |
| 12019 | Loki Dashboard | https://grafana.com/grafana/dashboards/12019 |
| 13186 | Loki Dashboard (alt) | https://grafana.com/grafana/dashboards/13186 |
| 13639 | Loki & Prometheus | https://grafana.com/grafana/dashboards/13639 |
| 23242 | OpenTelemetry + Tempo | https://grafana.com/grafana/dashboards/23242 |
| 14314 | NGINX Ingress Controller (Prometheus) | https://grafana.com/grafana/dashboards/14314 |
| 14583 | Argo CD - Application metrics | https://grafana.com/grafana/dashboards/14583 |
| 14584 | Argo CD - Overview | https://grafana.com/grafana/dashboards/14584 |
| 15762 | Kubernetes / Views / API server | https://grafana.com/grafana/dashboards/15762 |
| 3070 | etcd | https://grafana.com/grafana/dashboards/3070 |

---

*Document version: 1.2 — E1 default dashboards; updated Loki/Tempo gnet IDs to match `helm/grafana-values.yaml`; added provisioning troubleshooting for UID collisions and Loki parse errors.*
