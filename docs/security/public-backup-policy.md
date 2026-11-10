# Keep cluster backups out of public Git history

Raw Argo CD and Kubernetes exports can contain private keys, passwords,
service-account credentials and encoded Secret values. Encoding is not
encryption. Write exports only through the existing approved backup owner to
an encrypted destination outside this checkout. Never put them in public Git,
pull requests, workflow artifacts or logs. Replacement runtime values belong
in Infisical. If no approved encrypted route exists, stop the export.

Ignore rules cover the known Argo backup, full backup and all-manifests export
names in YAML and JSON, plus nested `backups/raw/` directories. Forced adds
can bypass ignores. Existing dashboard files remain tracked.

`Gitleaks new changes` checks the incoming PR or push range independently of
old findings. If a push base is missing or not an ancestor, or this is a new branch/manual run,
it scans all history reachable from the tip and may report historical
findings. Non-default branch/tag pushes use `Gitleaks ref changes`, and
manual runs use `Gitleaks manual audit`, so their historical fallback status
cannot collide with the required PR/default-branch check on the same commit.
Every event has a unique concurrency group: an earlier push scan is never
cancelled or displaced by a later push. `Gitleaks full history` separately audits fetched branches, tags
and public pull-request head/merge refs. Both include first-parent merge diffs
and fail on findings, errors, deadlines or missing completion proof. Neither
honors repository ignore lists or inline allow comments.

Make `Gitleaks new changes` required under the repository owner's branch
policy. Workflow/configuration changes also need owner review; a required
status alone does not prevent someone with workflow-write authority from
changing the check. These controls catch accidental commits, but cannot undo
an exposure or protect against an owner bypass. The full audit stays red until
historical findings have been resolved; do not suppress unresolved credentials.

Rotate or revoke exposed credentials first. Before an approved history rewrite,
keep the required private mode-600 pre-rewrite backup. Rewrite and push the
mutable branches/tags, then re-scan all advertised refs. GitHub pull refs are
read-only to Git pushes and may retain old commits; cached views and fork
copies can also remain. Resolve those through their owners/GitHub Support
where needed, with separate authorization before any message under Vincent's
name. Never report a branch/tag rewrite as complete erasure or a clean all-ref
scan while old refs still expose the material. Verify deployed consumers and
Argo CD sync after rotations. No credential values belong in reports.
