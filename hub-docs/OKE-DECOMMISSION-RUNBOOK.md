# OKE Decommission Runbook

## Current state

The OKE observability hub was cleanly decommissioned on 2026-08-03 to release
OCI Always Free A1 compute and block-storage capacity. The final provider and
Terraform checks proved:

- Terraform remote state contains zero managed resources.
- The `oke-cluster` control plane, two A1 workers, worker boot volumes,
  dedicated VCN, subnets, route table, security list, internet gateway, and OCI
  network load balancers are absent.
- The Jenkins and Prometheus source block volumes were deleted only after their
  provider-native full backups reached `AVAILABLE`.
- Loki and Tempo Object Storage buckets were outside the destroy plan and were
  retained.
- OpenClaw, Mira Workbench, Hostinger, and `claw.canepro.me` were not migrated
  or changed by this decommission.

The former weekly OKE automation is paused. The repository is historical source
and does not currently have a live Argo CD consumer.

## Retained recovery points

OCI holds two full block-volume backups created immediately before teardown:

- `jenkins-pre-oke-decommission-20260803T175100Z`
- `prometheus-pre-oke-decommission-20260803T175100Z`

Before relying on either backup, query OCI and require `lifecycle-state` to be
`AVAILABLE`, `type` to be `FULL`, and the source volume to match the intended
workload. Do not expose OCI credentials, Terraform backend credentials,
kubeconfigs, Jenkins credentials, or secret-backed configuration while proving
metadata.

## Safe teardown order

1. Inventory Terraform state, Kubernetes public services, PVC/PV reclaim
   policies, source volume handles, active jobs, DNS, OCI load balancers,
   compute, boot volumes, and object-storage dependencies.
2. Put Jenkins into quiet-down mode. Require an empty queue and no active build
   or executor before snapshotting. Record a failed or aborted final build
   honestly; do not treat it as successful work.
3. Flush the Jenkins and Prometheus filesystems, create provider-native `FULL`
   block-volume backups, and wait for both to become `AVAILABLE`.
4. Stop Argo CD from recreating ingress, delete the public LoadBalancer Service,
   and verify the matching OCI network load balancer is gone.
5. Create a saved `terraform plan -destroy`, inspect that every action is an
   intended delete, record its checksum, and apply only that saved plan.
6. After the control plane is gone, enumerate OCI network load balancers and
   private IPs by the former public subnet. Argo CD may win a final reconciliation
   race and create a replacement load balancer during shutdown. Delete only the
   exact blocker returned by OCI, then allow Terraform's existing subnet waiter
   to continue.
7. Prove Terraform state is empty and verify provider-side absence of the OKE
   cluster, A1 instances, boot volumes, source block volumes, load balancers,
   and dedicated VCN.
8. Remove retired DNS records with the canonical Cloudflare
   `delete-dns-record` helper. Supply the observed record type, name, and current
   content so changed or ambiguous records are refused. Leave unrelated routes
   such as OpenClaw untouched.
9. Pause OKE-only recurring automation and mark operational documentation as
   historical.

## OCI Object Storage backend recovery

Terraform 1.14.9 attempted AWS chunked encoding while saving to OCI's
S3-compatible Object Storage backend, even with `skip_s3_checksum = true`, and
OCI returned HTTP 501. For state-changing commands against this backend, set:

```bash
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
```

If Terraform reports `Failed to persist state to backend` and writes
`errored.tfstate`:

1. Stop. Do not rerun `apply`; that can fork state.
2. Immediately `chmod 600 errored.tfstate`.
3. Pull the remote state to a mode-600 temporary file.
4. Compare lineage, serial, and managed resource addresses only. Never print
   full state content.
5. Push `errored.tfstate` with the two checksum environment variables set.
6. Pull remote state again and prove the expected lineage and managed resource
   set before generating a fresh plan.
7. Delete every local recovery-state and saved-plan copy after the remote state
   is verified.

Do not display `terraform/backend.hcl`, `terraform.tfvars`, state files, saved
plans, or environment variables during diagnosis. Inspect only existence,
permissions, hashes, and redacted metadata.

## Rebuild gate

Recreating the historical stack is a new live-infrastructure decision. Before
any `terraform apply`, choose the new owner and topology, confirm OCI cost and
capacity, review the old manifests against current versions, define DNS and
secret-consumer cutovers, and write a rollback plan. Restore a volume backup
only into an explicitly approved replacement consumer.
