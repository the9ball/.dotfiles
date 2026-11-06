# Automated aqua package updates

`.github/workflows/aqua-update.yaml` checks for updates once daily (08:30 JST / 23:30 UTC on the previous day)
and supports manual runs via **Actions → Update aqua packages → Run workflow**.

When `aqua update` changes only `aqua.yaml`, the workflow opens a branch and
pull request and enables GitHub native auto-merge. The existing `ci-required`
status check must succeed before merging. No changes means no PR.

## One-time setup

1. In Settings → Actions → General → Workflow permissions, enable
   **Allow GitHub Actions to create and approve pull requests**.
2. Keep **Allow auto-merge** enabled under Settings → General → Pull Requests.
3. Keep the `master` ruleset requiring `ci-required`.

No personal access token or repository secret is needed. The update workflow
uses the default `GITHUB_TOKEN` with `contents: write`, `pull-requests: write`
and `actions: write`. Because a PR created by that token does not trigger
`pull_request` workflows, it explicitly starts the existing CI via
`workflow_dispatch` on the PR head branch. That run reports the required
`ci-required` check against the PR head SHA; GitHub auto-merge waits for it.

## Safeguards

- An already-open `chore/aqua-update-` PR blocks a duplicate run.
- Changes outside `aqua.yaml` cause a failure rather than an automatic PR.
- Changes to kubectx/kubens are blocked because their completion archive
  versions and checksums in `chezmoi/.chezmoiexternal.toml` must also change.
- The workflow does not force-merge or bypass branch rules.
- A failed CI check leaves the PR open for investigation.
- A failed run can be inspected in the Actions run log.
