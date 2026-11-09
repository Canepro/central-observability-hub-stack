# Keep cluster backups out of public Git history

Raw Argo CD and Kubernetes exports can contain private keys, passwords,
service-account credentials and encoded Secret values. Encoding is not
encryption. Do not write these exports anywhere inside this public checkout,
including untracked files, pull requests, workflow artifacts or logs.

Use the existing approved backup owner and an encrypted destination outside the
checkout. Runtime credentials and new replacement values belong in Infisical;
backup access must use the established consumer. Do not create a new backup
consumer, encryption key or storage destination as part of an ad hoc export.
If no approved encrypted route exists, stop the export until one is configured.

The ignore rules cover known raw backup names and the `backups/raw/` directory.
They protect against accidental adds; `git add --force` can bypass them. The
Secrets scan workflow scans branch and tag history, including merge changes,
with pinned Gitleaks default rules. It does not honor repository ignore lists
or inline allow comments. Findings, scan errors and incomplete coverage fail
the check. Make `Gitleaks full history` a required branch check where the
repository's owner policy permits it. CI catches a committed leak; it cannot
undo an exposure that has already happened.

Before adding a backup or export feature, keep its output private or encrypted
outside the checkout and confirm that it cannot enter Git or CI artifacts.
Legitimate dashboards with backup in their names remain tracked normally.

For a leaked credential, rotate or revoke it at its authority first, then purge
history under the repository owner's approval. Preserve the approved private
pre-rewrite backup and validate the rewritten history and deployed consumers.
Never include credential values in reports or remediation records.
