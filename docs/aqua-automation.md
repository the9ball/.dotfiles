# Automated aqua package updates

[Renovate](../.github/workflows/renovate.yaml) runs daily at 05:20 JST
(20:20 UTC on the previous day). To run it on demand, select
**Actions → Renovate aqua packages → Run workflow** on `master`.

## Update scope

The [configuration](../.github/renovate.json5) uses the aqua `file` preset at
2.15.0 and enables only its regex managers for `aqua.yaml`. Renovate groups the
package versions and the annotated standard registry `ref` in a single PR.
The kubectx and kubens entries stay pinned because their completion archive
versions and hashes in `chezmoi/.chezmoiexternal.toml` must change together.

curl-for-win is excluded and updated manually. Its download source is curl.se,
and `curl/curl-for-win` has no GitHub releases or tags, so Renovate finds no
candidates without warning. The previous `aqua update` workflow also left it
unchanged. The explicit exclusion prevents wrong candidates if GitHub tags
appear later. To update it, edit its version in `aqua.yaml`, check that the
curl.se download and checksum file exist for that version, then follow the
usual review.

GitHub Actions, the Renovate image and aqua preset, the bootstrap aqua version,
and files outside `aqua.yaml` are outside automatic update scope.

## GitHub App setup

1. Create a GitHub App and install it on `the9ball/.dotfiles` only. Grant these
   repository permissions:

   | Permission | Access |
   | --- | --- |
   | Contents | Read and write |
   | Pull requests | Read and write |
   | Metadata | Read |
   | Checks | Read |
   | Commit statuses | Read |

2. Confirm that the App's slug matches the expected PR author login
   `app/the9ball-dotfiles-renovate`. If GitHub assigns a different slug, update
   the login here and in the [dotfiles-sync Skill](../link-targets/agents/skills/dotfiles-sync/SKILL.md).
3. Register the App client ID in the repository variable `RENOVATE_APP_CLIENT_ID`
   and its private key in the repository secret `RENOVATE_APP_PRIVATE_KEY`.
   The workflow requests an installation token limited to the current
   repository and the permissions above. GitHub grants Metadata read implicitly.
4. Keep **Allow auto-merge** enabled and keep the `master` ruleset requiring
   `ci-required`. Leave the App out of the ruleset bypass list and leave
   Administration write access disabled. GitHub native auto-merge then waits
   for the required check and leaves the PR open if that check fails.

The App omits the permissions below. If a run exposes a missing permission or
a PR's CI reports `action_required`, stop and get user approval before changing
permissions or repository settings.

| Omitted permission | Expected effect |
| --- | --- |
| Workflows | The App cannot change workflow files. GitHub may also reject rebasing an open Renovate PR after a workflow change lands on `master`. That rebase behavior remains unverified. |
| Issues | Renovate cannot open a configuration-error issue. The Dependency Dashboard is disabled. Renovate reads the issue list on every run while finalizing the repository. Whether the installation token can read it without Issues permission is unverified. A rejection would fail every run and requires stopping under the permission rule above. |
| Administration | Settings writes are unavailable. If Renovate tries to read an administration-only setting, that request may be rejected. |
| Merge queues | The App cannot use a merge queue. This repository uses PR auto-merge. |
| Dependabot alerts | Renovate cannot read vulnerability alerts. Failed alert lookup is logged as a warning. |
| Members | Membership or team lookups may be rejected if a configuration uses them. This configuration does not use them. |

## Failure detection and run outcomes

Renovate uses `exitCodeForErrors` to surface repository errors as nonzero exit
codes. In Renovate 44.263.5, a GitHub API 403 identified as a rate limit maps
to `PLATFORM_RATE_LIMIT_EXCEEDED` and exit code 4. This behavior was verified
from the pinned source only and remains untested against the live API.
See [GitHub HTTP handling](https://github.com/renovatebot/renovate/blob/44.263.5/lib/util/http/github.ts),
[repository error handling](https://github.com/renovatebot/renovate/blob/44.263.5/lib/workers/repository/error.ts),
and [repository results](https://github.com/renovatebot/renovate/blob/44.263.5/lib/workers/repository/result.ts).

A lookup can return dependency warnings even when Renovate exits zero.
The report step reads the JSON report from the action's default `/tmp` mount.
The path includes the run ID and attempt. The step fails for any of these cases:

- The report is missing or cannot be parsed, or the repository entry is missing.
- No dependency in `aqua.yaml` is active across the reported managers.
- A reported dependency has warnings or a skip reason other than
  `disabled` or `package-rules`.
- A dependency with a name starting with `ahmetb/kubectx` has no skip reason.
- A branch reports `error`, `pr-limit-reached`, `branch-limit-reached`,
  `commit-per-run-limit-reached`, or `commit-hourly-limit-reached`.
  These are Renovate 44.263.5 branch results. An absent branch list counts as empty.

Find Renovate PRs using the App login above and a head branch starting with
`renovate/`. Check the watched run's conclusion before classifying its outcome.

| Run conclusion | Matching PR | Outcome |
| --- | --- | --- |
| Failure | Any | Report the failing step and any open Renovate PR. |
| Success | Open | Report PR creation and wait for CI and auto-merge. |
| Success | Merged at or after the anchor run's start | Confirm the merge commit. |
| Success | Neither | Report no updates. |

In Renovate 44.263.5, a failure to enable auto-merge does not fail the run.
dotfiles-sync stops if an open PR has no auto-merge request.

Closing the aqua update PR without merging does not hold back the update. In
Renovate 44.263.5, a grouped update PR is recreated on a later run unless
`recreateWhen` is `never`. To hold back a package, add a package rule instead.

Stop and report multiple qualifying PRs or conflicting evidence. If the run
was cancelled, check for a replacement run first. If there is none, check for
an open Renovate PR.

## Migration and post-merge checks

1. Before merging, set up the App, variable, and secret so scheduled runs can
   authenticate immediately. Merge or close any open `automate/aqua-update-*` PRs.
2. Merge the migration PR and manually dispatch **Renovate aqua packages** once.
   Confirm repository finalization can read the issue list with the installation
   token that omits Issues permission. This access remains unverified. A
   rejection would fail every run. Stop under the permission rule above.
3. When a PR is opened, verify its author, head branch, and `aqua.yaml` diff.
   Confirm `ci-required` runs on its head commit without `action_required` and
   that auto-merge waits for it to pass. Compare dotfiles-sync's reported
   outcome with the run and PR state. Exercise the PR checks on a later run
   if this first run has no updates.
4. Delete any remaining `automate/aqua-update-*` branches from the old workflow.
   The **Allow GitHub Actions to create and approve pull requests** setting is
   no longer required for aqua updates. Leave any settings change to the user.

## Rollback

Get separate authorization before executing these external operations.

1. Disable `renovate.yaml` with `gh workflow disable` and confirm that any active
   run has stopped.
2. Disable auto-merge for open Renovate update PRs, close them, and delete
   their `renovate/` branches.
3. Merge a PR reverting the migration to restore `aqua-update.yaml` and the old
   Skill. Resolve later conflicts by removing the Renovate configuration and
   workflow and restoring the previous files.
4. Verify **Allow GitHub Actions to create and approve pull requests** is
   enabled for the old workflow. Dispatch `aqua-update.yaml` once and confirm
   it works.
5. If appropriate, uninstall the App and remove its variable and secret.

## Maintenance and risks

Renovate does not validate version candidates against aqua's registry asset
definitions. An upstream asset rename can therefore produce a broken version.
`ci-required` can catch such breakage for tools with the `ci` tag.

Update the two Action references manually by pinning each to a commit SHA with
its version in a comment. Update the image version and digest together and
update the aqua preset pin manually. When updating the image, rerun the
checks for a no-update report, exclusion by package rule, an `allowedVersions`
restriction, lookup warnings, a connection failure, and missing or invalid
report data. Review the rate-limit mapping in the new source. The experimental
`exitCodeForErrors` option and the report schema can change between versions.
Confirm the Action's default `/tmp` mount when updating the Action. A missing
report fails the job if that mount stops exposing the expected path.
