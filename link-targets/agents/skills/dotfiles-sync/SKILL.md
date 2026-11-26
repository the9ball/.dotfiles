---
name: dotfiles-sync
description: Bring the local `~/.dotfiles` checkout and environment up to date - check the working tree, fast-forward `master` to `origin/master`, run the `aqua-update.yaml` workflow on demand and wait until its package update pull request is merged, then review `chezmoi diff` and apply it with the user's approval. Use for requests such as `dotfilesを最新にして` (bring dotfiles up to date), `aquaを今すぐ更新して同期して` (update aqua now and sync), or `masterを取り込んでchezmoi applyまで` (pull master and run chezmoi apply). Not for editing `aqua.yaml` by hand, changing the workflow, other repositories, or winget packages (use `winget-upgrade`).
---

# dotfiles sync

Package updates come only from the `aqua-update.yaml` workflow. Do not run `aqua update` locally, and do not commit, push, or open a pull request in this skill. The workflow already checks the diff, blocks kubectx updates, approves the CI run, and enables auto-merge.

The commands are written for a POSIX shell. In PowerShell, quote arguments that contain `@{`, `{`, or `$`.

## 0. Fix the target and the scope

- **Checkout:** `git rev-parse --show-toplevel` is the `~/.dotfiles` directory, and `git remote get-url origin` is one of `https://github.com/the9ball/.dotfiles(.git)` or `git@github.com:the9ball/.dotfiles(.git)`. Otherwise stop.
- **GitHub:** pass `-R github.com/the9ball/.dotfiles` to every `gh` repository command in this skill (written as `-R "$REPO"` below after `REPO=github.com/the9ball/.dotfiles`), and `--hostname github.com` to `gh api`, which has no `-R`. Then neither `GH_REPO`, `GH_HOST`, nor the remote configuration can select another repository or host.
- **Package update:** start the workflow (steps 3 and 4) only when the request explicitly mentions updating packages or aqua (for example `aquaを今すぐ更新して同期して`). For a generic request such as `dotfilesを最新にして`, ask whether to include the package update before step 3. When it is not included, skip steps 3 to 5.

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

Starting the workflow is an external operation. Apply `external-operation-authorization` for it: the boundary is **one** dispatch of `aqua-update.yaml` on `master` in `github.com/the9ball/.dotfiles`, authorized by the request as fixed in step 0. No later step dispatches again; a second dispatch needs a new instruction from the user.

Before dispatching, look for update work already in flight. Either one replaces the dispatch:

```sh
gh pr list -R "$REPO" --state open --limit 200 --json number,headRefName,author \
  --jq '.[] | select(.author.login == "app/github-actions" and (.headRefName | startswith("automate/aqua-update-")))'
gh run list -R "$REPO" --workflow aqua-update.yaml --limit 20 --json databaseId,status,event,createdAt \
  --jq '.[] | select(.status != "completed")'
```

- A queued or running update run (whether or not an update PR is also open, because a running workflow may still be approving CI and enabling auto-merge): skip the dispatch and go to step 4.1 with the newest such run. Record its ID and `createdAt` as the **anchor run**.
- Only an open update PR: skip the dispatch and go to step 4.3 with that PR number.
- Neither: record the current UTC time, the IDs of the 20 most recent `aqua-update.yaml` runs (`gh run list -R "$REPO" --workflow aqua-update.yaml --limit 20 --json databaseId`), and the authenticated login (`gh api --hostname github.com user --jq .login`), then dispatch:

```sh
gh workflow run aqua-update.yaml -R "$REPO" --ref master
```

`gh workflow run` prints the URL of the new run when it is available; take the run ID from it. When it prints no URL, find the run with `gh run list -R "$REPO" --workflow aqua-update.yaml --event workflow_dispatch --user <login> --limit 10 --json databaseId,createdAt`, keeping runs whose ID was not recorded before the dispatch and that were created no earlier than two minutes before the recorded time (to allow for clock skew). A new run can take a few seconds to appear, so check a few more times. If not exactly one run matches (none or several), stop and report rather than guessing. Record the new run's ID and `createdAt` as the anchor run.

## 4. Wait for the update

Run each wait in the background, because it can outlast the tool timeout, and keep the whole of step 4 under about 30 minutes. When that is exceeded, report the state and let the user decide.

### 4.1 The update workflow

```sh
gh run watch <run-id> -R "$REPO" --exit-status --interval 30 --compact
```

A nonzero exit covers both failure and cancellation, so read `gh run view <run-id> -R "$REPO" --json status,conclusion` afterwards and branch on it. When `status` is not `completed` (the watch itself ended early, for example on a network error), watch the same run again within the time limit. Otherwise branch on `conclusion`:

- `success`: go to step 4.2.
- `cancelled`: the workflow's `concurrency` group may have replaced it with a newer pending run. Do not dispatch again. Run the in-flight checks of step 3 once more and continue with a queued or running run (step 4.1) or an open update PR (step 4.3). When neither exists, list `aqua-update.yaml` runs with `--json databaseId,createdAt,status,conclusion` and take the most recent run that is `completed`, is not `cancelled`, is not the cancelled run, and was created after the anchor run's `createdAt`. Go to step 4.2 with it when its conclusion is `success`, and otherwise handle that run, with its own ID, as in the next item. When there is no such run, stop and report.
- Any other conclusion (such as `failure`): show the failing steps with `gh run view <run-id> -R "$REPO" --log-failed` (filtered excerpts). Also run the PR search of step 4.2, because the workflow can fail after creating the PR (for example while approving CI or enabling auto-merge). Report any PR found, which stays open and makes later runs skip, and stop.

The workflow ends after **enabling** auto-merge. A successful run does not mean that the PR is merged.

### 4.2 Determine the outcome of the run

First look for the PR this run opened. The workflow names its branch `automate/aqua-update-<date>-<run-id>-<attempt>`:

```sh
gh pr list -R "$REPO" --state all --limit 50 --json number,url,headRefName,state \
  --jq '.[] | select(.headRefName | startswith("automate/aqua-update-") and contains("-<run-id>-"))'
```

Confirm the outcome from the run's output lines. The log (`gh run view <run-id> -R "$REPO" --log`) also contains the step's script, whose `echo` lines carry the same messages, so match a message only where it directly follows the timestamp of a line and ends the line (for example `[0-9]Z No aqua package updates\.$`). Do not count lines that contain `echo`.

- **A PR was found** (and the output has `Created https://github.com/...`): go to step 4.3 with it.
- **`No aqua package updates.`** with no PR: nothing to merge. Go to step 5.
- **`An aqua update PR is already open; skipping.`** with no PR: run the open-PR query of step 3 again and go to step 4.3 with the PR it finds. When none is open any more, the PR may have been merged in the meantime. Take the run's `startedAt` (`gh run view <run-id> -R "$REPO" --json startedAt`) and look for it:

```sh
gh pr list -R "$REPO" --state merged --limit 20 --json number,url,headRefName,author,mergedAt,mergeCommit \
  --jq '.[] | select(.author.login == "app/github-actions" and (.headRefName | startswith("automate/aqua-update-")) and .mergedAt > "<startedAt>")'
```

Exactly one PR must match; go to step 4.4 with it. Otherwise stop and report.

If the PR search and the output lines disagree, or none or more than one outcome is found, stop and report.

### 4.3 Wait for the checks

When you reached this step with a PR that no run of this skill created (from step 3, or after a `cancelled` or skipped run), first read `gh pr view <number> -R "$REPO" --json state,headRefName,headRefOid,autoMergeRequest`:

- `MERGED`: it was merged in the meantime. Go to step 4.4.
- `CLOSED`: stop and report.
- `OPEN`: check that the workflow that created it finished. Read the PR's CI runs with `gh run list -R "$REPO" --workflow ci.yaml --event pull_request --branch <headRefName> --json headSha,status,conclusion` and keep those for `headRefOid`. Stop and report the PR instead of waiting when `autoMergeRequest` is null, when there is no CI run for `headRefOid`, or when the newest one is waiting for approval (`conclusion` is `action_required`).

```sh
gh pr checks <number> -R "$REPO" --watch --required --fail-fast --interval 30
```

The required check (`ci-required`, set by a repository ruleset) is created only after the jobs it depends on. When the command exits because no checks or no required checks are reported yet, treat it as pending and run it again after about 30 seconds, within the overall time limit. When a check fails or is cancelled, stop and report the PR URL and the failing checks. The PR stays open and is not merged.

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
- The update PR (URL, merged packages from `gh pr diff <number> -R "$REPO"`), "no updates", or "package update not included".
- What `chezmoi apply` changed, which scripts ran, and the verification result.
- Anything skipped or left for the user, such as working-tree changes kept in step 1.

Delete the temporary files this skill created.
