# 🚀 OKE Cluster Information

This file documents the Oracle Kubernetes Engine (OKE) environment used by this repo.

> Security note: identifiers like **OCIDs**, **public endpoints**, and **subnet IDs** are treated as sensitive for public sharing.
> This document intentionally uses **REDACTED** placeholders. Retrieve exact values from your OCI console or from `terraform/` in a private context.

## 🔎 How to retrieve REDACTED values (OCI Console + CLI)

### OCI Console (fastest)

| What you need | Where to find it in the OCI Console |
|---|---|
| **Cluster OCID / Name / Kubernetes Version / Type / Endpoint** | **Developer Services → Kubernetes Clusters (OKE) →** select your cluster |
| **Node Pool details (shape, node count, image)** | **OKE Cluster → Node Pools →** select node pool |
| **VCN + Subnets (OCIDs)** | **OKE Cluster → Cluster details → Networking** (links to VCN/Subnets) |
| **Compartment** | Shown in the header/breadcrumb for the resource (or on the resource details page) |
| **Pod/Service CIDR** | **OKE Cluster → Cluster details → Networking** |

### OCI CLI (scriptable)

> Tip: you can copy OCIDs from the console, or query by name and compartment.

```bash
# 1) List clusters in a compartment (find the OCID)
oci ce cluster list --compartment-id <COMPARTMENT_OCID> --region <REGION>

# 2) Get full cluster details (endpoints, CIDRs, VCN/subnet IDs, type, version)
oci ce cluster get --cluster-id <CLUSTER_OCID> --region <REGION>

# 3) List node pools for a cluster
oci ce node-pool list --compartment-id <COMPARTMENT_OCID> --cluster-id <CLUSTER_OCID> --region <REGION>

# 4) Get node pool details (shape, size, image)
oci ce node-pool get --node-pool-id <NODE_POOL_OCID> --region <REGION>
```

### Terraform (private repo context)

If you manage OKE via this repo, you can also retrieve identifiers from:

- `terraform/main.tf` (declared resources)
- `terraform/terraform.tfstate` (resolved OCIDs/endpoints after apply)

---

## 🏗️ 1. Core Cluster Identity

| Item | Value |
|---|---|
| **Cluster Name** | `oke-cluster` |
| **Cluster OCID** | `REDACTED` |
| **Kubernetes Version** | `v1.34.1` |
| **Type** | `BASIC_CLUSTER` |
| **Region** | `us-ashburn-1` |
| **Compartment** | `REDACTED` |

---

## 🖥️ 2. Data Plane (Node Pools)

| Item | Value |
|---|---|
| **Node Pool Name** | `pool-canepro` |
| **Node Count** | 2 |
| **Shape** | `VM.Standard.A1.Flex` (ARM64) |
| **OCPU / Memory** | 2 OCPU / 12 GB RAM **per node** |
| **Image** | `Oracle-Linux-8.10-aarch64-2025.10.23-0` |

---

## 🌐 3. Networking Details

| Item | Value |
|---|---|
| **VCN OCID** | `REDACTED` |
| **Pod CIDR** | `10.244.0.0/16` |
| **Service CIDR** | `10.96.0.0/16` |

### Subnets (OCIDs)

| Subnet | OCID |
|---|---|
| **API Endpoint Subnet** | `REDACTED` |
| **Worker Node Subnet** | `REDACTED` |
| **Load Balancer Subnet(s)** | `REDACTED` |

> Note: The Pod/Service CIDRs are listed here to help avoid future overlapping networks (especially in multi-cluster/hub-spoke designs).

---

## 🛠️ 4. Quick Access Commands

### Update Kubeconfig

```bash
oci ce cluster create-kubeconfig --cluster-id <CLUSTER_OCID> --file $HOME/.kube/config --region <REGION> --token-version 2.0.0 --overwrite
```

### Check Node Status

```bash
kubectl get nodes -o wide
```

### List Pods in All Namespaces

```bash
kubectl get pods -A
```

---

## 🛡️ 5. Compliance & Best Practices

| Area | Standard |
|---|---|
| **Namespaces** | `monitoring`, `argocd`, `kube-system`, `ingress-nginx`, `cert-manager` |
| **Resource Limits** | All workloads should define CPU/memory **requests + limits** (free-tier stability). |
| **Monitoring** | Grafana: `https://grafana.canepro.me` (see “Master Health Dashboard”). |

---

## 📊 6. Node capacity and resource usage (snapshot)

The following is a **point-in-time snapshot** of hub node capacity and usage. Re-run the commands below periodically (or after adding workloads) to refresh.

**When captured:** 2026-02-10 (2 nodes, VM.Standard.A1.Flex 2 OCPU / 12 GB RAM per node).

### Node list and allocatable resources

| Node       | Status | Allocatable CPU | Allocatable memory |
|------------|--------|------------------|---------------------|
| 10.0.2.147 | Ready  | 1830m            | 9650076 Ki (~9.2 Gi) |
| 10.0.2.62  | Ready  | 1830m            | 9650076 Ki (~9.2 Gi) |

*Total capacity: 2 nodes × ~9.2 Gi allocatable memory.*

### Allocated resources (requests / limits)

| Node       | CPU requests | CPU limits | Memory requests | Memory limits |
|------------|---------------|------------|------------------|----------------|
| 10.0.2.147 | 1450m (79%)   | 6300m (344%) | 2434Mi (25%)     | 5792Mi (61%)   |
| 10.0.2.62  | 1580m (86%)   | 5450m (297%) | 2244Mi (23%)     | 7028Mi (74%)   |

*Note: CPU limits are overcommitted (burst); memory limits are within allocatable. Actual usage can exceed the sum of limits if the kernel allows.*

### Actual usage (`kubectl top nodes`)

| Node       | CPU (cores) | CPU (%) | Memory (Mi) | Memory (%) |
|------------|-------------|---------|-------------|------------|
| 10.0.2.147 | 313m        | 17%     | 7108Mi      | 75%        |
| 10.0.2.62  | 352m        | 19%     | 7912Mi      | 83%        |

### Pod-level memory (actual vs request/limit)

Same snapshot date. **Actual** = `kubectl top pods -A --containers`; **Request/Limit** = from pod spec. Use this to decide which workloads to trim (high limit, low actual) vs which need more (e.g. OOM’d).

| Pod | Namespace | Container | Actual (Mi) | Request | Limit |
|-----|-----------|-----------|-------------|---------|-------|
| argocd-application-controller-0 | argocd | application-controller | 432 | 512Mi | 512Mi |
| argocd-repo-server-* | argocd | repo-server | 129 | 512Mi | 512Mi |
| argocd-server-* | argocd | server | 92 | 128Mi | 512Mi |
| argocd-applicationset-controller-* | argocd | applicationset-controller | 51 | — | — |
| argocd-dex-server-* | argocd | dex-server | 41 | — | — |
| argocd-notifications-controller-* | argocd | notifications-controller | 45 | — | — |
| argocd-redis-* | argocd | redis | 14 | — | — |
| grafana-* | monitoring | grafana | 143 | 256Mi | 768Mi |
| loki-0 | monitoring | loki | 400 | — | — |
| loki-0 | monitoring | loki-sc-rules | 89 | — | — |
| prometheus-alertmanager-0 | monitoring | alertmanager | 23 | 128Mi | 512Mi |
| prometheus-server-* | monitoring | (server) | — | 1Gi | 2Gi |
| prometheus-kube-state-metrics-* | monitoring | kube-state-metrics | 45 | — | — |
| otel-collector-* | monitoring | opentelemetry-collector | 52 | 128Mi | 256Mi |
| loki-promtail-* | monitoring | promtail | 102 / 97 | — | — |
| promtail-* (DaemonSet) | monitoring | promtail | — | 128Mi | 256Mi |
| tempo-0 | monitoring | — | — | — | — |
| nginx-ingress-*-controller-* | ingress-nginx | controller | 54 | 128Mi | 512Mi |
| jenkins-0 | jenkins | jenkins | 1779 | 1Gi | 4Gi |
| jenkins-0 | jenkins | config-reload | 81 | — | — |
| coredns-* | kube-system | coredns | 29–30 | 70Mi | 170Mi |
| kube-flannel-ds-* | kube-system | kube-flannel | 27–29 | 50Mi | 500Mi |
| metrics-server-* | kube-system | metrics-server | 39 | 64Mi | 128Mi |
| proxymux-client-* | kube-system | proxymux-client | 30–32 | 64Mi | 256Mi |
| csi-oci-node-* | kube-system | csi-node-driver | 23–24 | 70Mi | 300Mi |
| cert-manager-* | cert-manager | (various) | 19–56 | — | — |
| external-secrets-* | external-secrets | (various) | 29–75 | — | — |

*— = not set in pod spec.*

**Takeaway:** Memory is the constraining resource. Keep node memory usage under ~85% to avoid pressure and OOM risk; see `docs/TROUBLESHOOTING.md` (HubContainerOOMKilled) and `hub-docs/OPERATIONS-HUB.md` (OOM diagnosis procedure).

### Commands to refresh this snapshot

```bash
kubectl get nodes -o wide
kubectl describe nodes | grep -E "Name:|Allocatable:|  memory|  cpu"
kubectl describe nodes | grep -A 5 "Allocated resources"
kubectl top nodes
```

For per-pod memory (limits vs actual) to decide where to trim or increase:

```bash
kubectl top pods -A --containers | head -60
kubectl get pods -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,MEM_REQ:.spec.containers[*].resources.requests.memory,MEM_LIM:.spec.containers[*].resources.limits.memory
```

---

## ⏮️ Reverting to a Stable State

To revert the entire stack to the `v1.0.0-stable` state:

- **Local Repo**:

  ```bash
  git checkout v1.0.0-stable
  ```

- **ArgoCD**: If an app is failing, you can force a sync to this tag in the UI or via CLI:

  ```bash
  argocd app sync <app-name> --revision v1.0.0-stable
  ```

> Note: In this lab/test environment, ArgoCD may still be configured to follow `main`. Using `--revision <tag>` lets you recover quickly **without changing** the tracked branch.

- **Validation**: After reverting, run:

  ```bash
  ./scripts/validate-deployment.sh
  ```

### 🏷️ How to create the Git Tag

Once you commit this file, run these commands to “freeze” this perfect state:

```bash
# 1. Ensure everything is committed
git add .
git commit -m "docs: finalize cluster info and add revert instructions"
git push

# 2. Create the tag
git tag -a v1.0.0-stable -m "Stable state: Grafana healthy, PVCs bound, 194GB storage used."

# 3. Push the tag to GitHub
git push origin v1.0.0-stable
```

### 🏁 What this achieves

- **Safety Net**: If changes break the stack later, you can revert quickly to a known-good state.
- **Documentation Purity**: This file remains safe to share publicly (no sensitive IPs/OCIDs).
