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

## Verifying changes after merge

This automation cannot be exercised from a pull request branch:

- GitHub only dispatches workflows that exist on the default branch, so a new
  or changed `aqua-update.yaml` cannot be run before it reaches `master`.
- The update branch is cut from `master`, so the CI it dispatches uses the
  `ci.yaml` on `master`. A change to the `workflow_dispatch` path in `ci.yaml`
  takes effect only after it is merged.
- The parts most likely to fail (PR creation by `GITHUB_TOKEN`, the dispatched
  `ci-required` check attaching to the PR, and auto-merge) need a real PR, so a
  dry run on a branch would not cover them.

After merging a change to either workflow, run **Update aqua packages**
manually once and check that:

1. The run opens a `chore/aqua-update-*` PR, or reports no updates or an
   already-open update PR.
2. The dispatched **CI** run reports `ci-required` on that PR's head commit.
3. The PR merges automatically once `ci-required` passes.

When no package update is available, steps 2 and 3 wait for the next run that
opens a PR.

## Safeguards

- An already-open `chore/aqua-update-` PR opened by GitHub Actions blocks a
  duplicate run. A failed lookup of open PRs fails the run.
- Changes outside `aqua.yaml` cause a failure rather than an automatic PR.
- Changes to kubectx/kubens are blocked because their completion archive
  versions and checksums in `chezmoi/.chezmoiexternal.toml` must also change.
- The workflow does not force-merge or bypass branch rules.
- A failed CI check leaves the PR open for investigation.
- A failed run can be inspected in the Actions run log.
