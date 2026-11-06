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
and `actions: write`.

## How the update PR gets its CI

A PR opened by `GITHUB_TOKEN` does trigger the `pull_request` CI run, but the
repository's approval policy for fork pull request workflows
(**Require approval for all external contributors**) treats
`github-actions[bot]` as an external contributor. GitHub therefore creates the
run in the `action_required` state, and that pending run keeps the PR blocked.
A separately dispatched CI run on the same commit does not unblock it.

After opening the PR, the workflow waits for that `pull_request` CI run on the
PR head commit and approves it through the Actions API (this is why it needs
`actions: write`). The approved run reports `ci-required`, and auto-merge
merges the PR once it passes. If the policy is relaxed so the run starts
without approval, the workflow skips the approval step.

The approval is limited to the run for a commit this workflow just created,
after the checks above allowed only an `aqua.yaml` change.

## Verifying changes after merge

This automation cannot be exercised from a pull request branch:

- GitHub only dispatches workflows that exist on the default branch, so a new
  or changed `aqua-update.yaml` cannot be run before it reaches `master`.
- The parts most likely to fail (PR creation by `GITHUB_TOKEN`, approving the
  held CI run, and auto-merge) need a real PR, so a dry run on a branch would
  not cover them.

After merging a change to the workflow, run **Update aqua packages** manually
once and check that:

1. The run opens a `chore/aqua-update-*` PR, or reports no updates or an
   already-open update PR.
2. The run log shows the PR's `pull_request` CI run being approved, and that
   run reports `ci-required` on the PR's head commit.
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
