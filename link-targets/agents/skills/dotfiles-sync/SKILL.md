---
name: dotfiles-sync
description: Bring the local `~/.dotfiles` checkout and environment up to date - check the working tree, fast-forward `master` to `origin/master`, run the Renovate workflow on demand for aqua dependencies and wait for any resulting update pull request to merge, then review `chezmoi diff` and apply it with the user's approval. Use for requests such as `dotfilesを最新にして` (bring dotfiles up to date), `aquaを今すぐ更新して同期して` (update aqua now and sync), or `masterを取り込んでchezmoi applyまで` (pull master and run chezmoi apply). Not for editing `aqua.yaml` by hand, changing the workflow, other repositories, or winget packages (use `winget-upgrade`).
---

# dotfiles sync

The `renovate.yaml` workflow updates aqua dependencies and enables GitHub auto-merge, which waits for `ci-required` to pass. Do not run `aqua update` locally, and do not commit, push, or open a pull request in this skill.

The commands are written for a POSIX shell. In PowerShell, quote arguments that contain `@{`, `{`, or `$`.

## 0. Fix the target and the scope

- **Checkout:** `git rev-parse --show-toplevel` is the `~/.dotfiles` directory, and `git remote get-url origin` is one of `https://github.com/the9ball/.dotfiles(.git)` or `git@github.com:the9ball/.dotfiles(.git)`. Otherwise stop.
- **GitHub:** pass `-R github.com/the9ball/.dotfiles` to every `gh` repository command in this skill (written as `-R "$REPO"` below after `REPO=github.com/the9ball/.dotfiles`), and `--hostname github.com` to `gh api`, which has no `-R`. Then neither `GH_REPO`, `GH_HOST`, nor the remote configuration can select another repository or host.
- **Package update:** include the Renovate package update (steps 3 and 4) only when the user explicitly requests updating aqua or its packages (for example `aquaを今すぐ更新して同期して`). For a generic request such as `dotfilesを最新にして`, ask whether to include the package update before step 3. When it is not included, skip steps 3 to 5.

## 1. Check the working tree

```sh
git status --porcelain=v1 --untracked-files=all
git status
```

Stop and report when HEAD is detached or a merge, rebase, cherry-pick, or revert is in progress (the second command shows these). Record the starting branch for the report; do not switch back to it automatically.

When the first command prints anything, show the user a short summary per file (the kind of change, and whether it touches `aqua.yaml`, `aqua-registry.yaml`, `winget.json`, `.pre-commit-config.yaml`, or `chezmoi/`), and ask which of these to do:

- **Stop** so the user can deal with it.
- **Continue as is.** Offer this only when the changes do not block `git switch master` and the fast-forward. Warn that `chezmoi apply` reads the working tree (`sourceDir` is under `~/.dotfiles`), so uncommitted changes under `chezmoi/` and in the manifests above are applied as well. When the package update is included, also warn that an uncommitted `aqua.yaml` change will make the fast-forward in step 5 fail once the update PR is merged.
- **Something else** the user specifies.

Never stash, discard, commit, or delete anything on your own.

## 2. Fast-forward master

```sh
git fetch --prune origin
git log --oneline origin/master..master
```

When the current branch is not `master` and has an upstream, also check `git log --oneline '@{u}..HEAD'`. Report local commits that are not on the remote. Commits on `master` itself must be resolved by the user before continuing, because the fast-forward would keep them and `chezmoi apply` would apply them.

```sh
git switch master
git merge --ff-only origin/master
```

If the fast-forward fails, stop and report the local and remote commits that differ. Do not reset, rebase, or merge.

## 3. Start the package update

Apply `external-operation-authorization` to dispatching the workflow. Step 0 authorizes **one** dispatch of `renovate.yaml` on `master` in `github.com/the9ball/.dotfiles` to update aqua dependencies, including auto-merge of the resulting PR after required checks pass. Another dispatch requires a new user instruction. If App permissions are insufficient, stop and ask the user before changing permissions or repository settings.

Check for work already in flight. Use the same PR filter throughout, with the login matching the created App's slug.

```sh
RENOVATE_PR_FILTER='map(select(.author.login == "app/the9ball-dotfiles-renovate" and (.headRefName | startswith("renovate/"))))'
gh pr list -R "$REPO" --state open --limit 200 --json number,url,headRefName,author
(
  for status in queued in_progress requested waiting pending; do
    gh run list -R "$REPO" --workflow renovate.yaml --status "$status" --limit 1 \
      --json databaseId,status,createdAt || exit "$?"
  done
)
```

Count the PRs before applying `RENOVATE_PR_FILTER` to the JSON with jq. If the list reached the limit, double it and repeat until the response has fewer entries than the limit. Stop and report if any lookup fails, the PR list is incomplete, or multiple Renovate PRs are open. Otherwise:

- A queued or running update run: skip the dispatch and go to step 4.1 with the newest such run. Record its ID and `createdAt` as the **anchor run**.
- Only an open Renovate PR: skip the dispatch and go to step 4.3 with that PR number.
- Neither: dispatch once:

```sh
gh workflow run renovate.yaml -R "$REPO" --ref master
```

This requires the aqua-managed GitHub CLI (`cli/cli` v2.106.0 in `aqua.yaml`), which requests `return_run_details` and prints the run URL when GitHub returns it. Take the run ID from the dispatch response URL and read its `createdAt` to record the anchor run. If no run URL is printed, stop and report that the outcome could not be confirmed. A dispatch may already have been accepted.

## 4. Wait for the update

Run each wait in the background, because it can outlast the tool timeout, and keep the whole of step 4 under about 30 minutes. When that is exceeded, report the state and let the user decide.

### 4.1 The update workflow

```sh
gh run watch <run-id> -R "$REPO" --exit-status --interval 30 --compact
```

A nonzero exit covers both failure and cancellation, so read `gh run view <run-id> -R "$REPO" --json status,conclusion` afterwards and branch on it. When `status` is not `completed` (the watch itself ended early, for example on a network error), watch the same run again within the time limit. Otherwise branch on `conclusion`:

- `success`: go to step 4.2.
- `cancelled`: the workflow's `concurrency` group may have replaced it with a newer pending run. Do not dispatch again. Run the in-flight checks of step 3 once more. If a newer run is active, record it as the anchor and go to step 4.1. Otherwise list `renovate.yaml` runs with `--json databaseId,createdAt,status,conclusion` and take the most recent completed, non-cancelled run created after the anchor run's `createdAt`. If its conclusion is `success`, make it the anchor and go to step 4.2. For any other conclusion, handle that run with its own ID as in the next item. If the lookup succeeds and there is no replacement run, go to step 4.3 with the open Renovate PR, or stop and report if there is none.
- Any other conclusion (such as `failure`): show the failing steps with `gh run view <run-id> -R "$REPO" --log-failed` (filtered excerpts). Use the open-PR query in step 3 and report any open Renovate PR alongside the failure, then stop.

### 4.2 Determine the outcome of a successful run

Read the anchor run's `startedAt` and query matching PRs in one list so that a merge during the lookup can appear as either state.

```sh
gh run view <run-id> -R "$REPO" --json startedAt
gh pr list -R "$REPO" --state all --limit 200 \
  --json number,url,headRefName,author,state,mergedAt,mergeCommit
```

Repeat the PR lookup at a larger limit if it reached the limit, as in step 3, then apply `RENOVATE_PR_FILTER`. Count an `OPEN` PR or a `MERGED` PR with `mergedAt` at or after the anchor run's `startedAt`. Stop and report if either lookup fails, the PR list is incomplete, the start time is missing, multiple PRs qualify, or the evidence conflicts.

- **One open PR:** report PR creation and go to step 4.3 with its number.
- **One qualifying merged PR:** go to step 4.4 with its number.
- **Neither:** report "no updates" and go to step 5.

### 4.3 Wait for the checks

First read `gh pr view <number> -R "$REPO" --json state,headRefName,headRefOid,autoMergeRequest`:

- `MERGED`: it was merged in the meantime. Go to step 4.4.
- `CLOSED`: stop and report.
- `OPEN`: stop and report if `autoMergeRequest` is null. Renovate 44.263.5 only logs a failure to enable auto-merge, so the update run can still succeed. Read the PR's CI runs with `gh run list -R "$REPO" --workflow ci.yaml --event pull_request --branch <headRefName> --json headSha,status,conclusion` and keep those for `headRefOid`. Stop and report the PR if the newest run for `headRefOid` has `conclusion` set to `action_required`. Ask the user before changing permissions or settings. For a PR found in the in-flight lookup, also stop if there is no CI run for that commit.

```sh
gh pr checks <number> -R "$REPO" --watch --required --fail-fast --interval 30
```

The required check (`ci-required`, set by a repository ruleset) is created only after the jobs it depends on. When the command exits because no checks or no required checks are reported yet, treat it as pending and run it again after about 30 seconds, within the overall time limit. While the watch runs, recheck the CI run for the current PR head. If it reports `action_required`, stop the watch and report the approval requirement. When a check fails or is cancelled, stop and report the PR URL and the failing checks. The PR stays open and is not merged.

### 4.4 Confirm the merge

Auto-merge runs shortly after the required checks pass. Read `gh pr view <number> -R "$REPO" --json state,mergedAt,mergeCommit,mergeStateStatus,autoMergeRequest` up to about ten times at 15-second intervals.

- `MERGED`: keep `mergeCommit.oid` and continue.
- `CLOSED` without merging, or still `OPEN`: stop and report `mergeStateStatus` and `autoMergeRequest`, which show whether auto-merge is still enabled and what it waits for.

## 5. Fast-forward master again

Run after every outcome of step 4 that did not stop, including "no updates", because a scheduled update may have been merged while the workflow ran. Repeat the commands of step 2. When a PR was merged, also confirm that `master` contains its merge commit:

```sh
git merge-base --is-ancestor <merge-commit-oid> HEAD
```

## 6. Review and apply chezmoi changes

First confirm which source and destination chezmoi uses:

```sh
chezmoi source-path
chezmoi execute-template '{{ .chezmoi.workingTree }} {{ .chezmoi.destDir }}'
```

The source path must be the `chezmoi` directory of this checkout (the repository sets it through `.chezmoiroot`), the working tree must be this checkout, and the destination must be the user's home directory. Otherwise stop.

```sh
chezmoi status --exclude=scripts
chezmoi diff --exclude=scripts
chezmoi status --include=scripts
```

Write long `chezmoi diff` output to a new file under the OS temporary directory and read filtered excerpts. Present to the user:

- the files that will be added, changed, or removed;
- **locally modified targets:** entries whose first status column is not a space were changed since chezmoi last wrote them, and `chezmoi apply` would ask interactively whether to overwrite them, which a non-interactive shell cannot answer. Show their `chezmoi diff`, and let the user choose between overwriting them with `chezmoi apply --force` (only with explicit approval of that overwrite) and stopping so that they resolve the targets themselves (for example with `chezmoi merge` or an interactive `chezmoi apply`). Do not apply only part of the targets;
- the scripts that will run, in two groups:
  - **Every apply:** plain `run_before_*` and `run_after_*` scripts, such as `00-aqua-policy`, `environment`, and `junctions`.
  - **Triggered by this change:** `run_onchange_*` and `run_once_*` scripts. Base the list on what `chezmoi status --include=scripts` actually reports, and show their rendered bodies from `chezmoi diff --no-pager --use-builtin-diff`. For reference, `tools` reruns when `aqua.yaml`, `aqua-registry.yaml`, or `.pre-commit-config.yaml` changes, and on Windows also when `winget.json` changes. It runs `aqua install`, and on Windows also installs the winget packages. On Windows, a cloudflared version change also reruns `update-cloudflared-service`, which updates the `Cloudflared` service.

Scripts of the other OS can also be listed; chezmoi does not run a script whose template renders empty.

`chezmoi apply` changes files outside the repository and runs those scripts, so run it only after the user approves what you presented. When there is no file change and no triggered script, tell the user and skip the apply unless they ask for it.

The approval covers only the state you presented, including the content of every script that will run. Take the fingerprint below before and after collecting the output you present, and present it only when the two match (otherwise collect it again). Immediately before the apply, take the fingerprint once more. If it differs from the presented one, do not apply: present the new state and ask for approval again. Judge failure by the exit status of the block, not by its output, which still prints a hash on failure; if it fails, do not apply either.

```sh
set -o pipefail
{
  git rev-parse HEAD &&
  git status --porcelain=v1 --untracked-files=all &&
  git diff HEAD --binary --no-ext-diff --no-textconv --no-color | sha256sum &&
  git ls-files --others --exclude-standard -z | xargs -0 -r sha256sum -- &&
  chezmoi status | sha256sum &&
  chezmoi diff --no-pager --use-builtin-diff | sha256sum
} | sha256sum
```

`chezmoi diff` without `--exclude=scripts` includes the rendered bodies of the scripts that will run, and the Git parts cover the content of uncommitted and untracked source files, such as a second edit to an already modified file. Files ignored by Git that templates read are not covered.

```sh
chezmoi apply
chezmoi verify --exclude=scripts
chezmoi diff --exclude=scripts
```

If the apply fails, verification fails, or the last command still prints differences, do not report success. Report the error output and stop.

## 7. Report

- The starting branch, and the starting and final `master` commits.
- The Renovate run and its outcome. For a Renovate PR, report its URL and state, and list the merged aqua changes from `gh pr diff <number> -R "$REPO"`. Otherwise report "no updates", "update failed", or "package update not included", as applicable.
- What `chezmoi apply` changed, which scripts ran, and the verification result.
- Anything skipped or left for the user, such as working-tree changes kept in step 1.

Delete the temporary files this skill created.
