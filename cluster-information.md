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
