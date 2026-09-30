# Design memo

Why the files that make up `review-watch` are placed where they are.
Read this when editing this skill, especially when you are about to change the placement.
Separately from `SKILL.md` (the runtime procedure), this file keeps only the reasons for the decisions.

## File placement

| Target | Location | Tracking |
|---|---|---|
| Skill body | `link-targets/agents/skills/review-watch/` | Tracked by git |
| Repository location cache | `link-targets/agents/skills/review-watch/repositories.log` | gitignored |
| State of notified PRs | `$HOME/.claude/.review-watch/seen-pull-requests.tsv` | Outside dotfiles |
| Ownership token of the monitoring process | `$HOME/.claude/.review-watch/owner-token` | Outside dotfiles |
| Pre-review reports and diffs | `%TEMP%\claude-pr-review\` | Outside dotfiles |

### Skill body — `SKILL.md` / `watch-review-requests.sh` / `report-template.html`

Tracked in dotfiles. The same files are used across hosts.

`watch-review-requests.sh` is split out into a separate file because a command written out inline
for `Monitor` is rejected by the permission classifier. In addition, if any of the difference-detection logic is dropped
while writing it out, the notification repeats every minute and keeps burning credits.

### `repositories.log` — cache of repository locations

It is placed under `link-targets/agents`. It is **data that does not depend on the agent that runs it (Claude / Codex, etc.)**,
so it can be reused whichever of them runs the monitoring.

However, its contents are absolute paths, so it **does depend on the host.** It stops matching when taken to another machine,
but since paths are verified before use and discarded when they do not match, this does no harm.

The `.log` extension is used because it falls under the `*.log` rule already in dotfiles' `.gitignore`.
It can be left untracked without adding to `.gitignore`. Its contents are TSV (`owner/repo<TAB>absolute path`).

It is a cache, not master data. Clones are moved and deleted, so
verify a path with `git -C <path> remote get-url origin` before using it, and if it does not match, discard it and search again.

### `seen-pull-requests.tsv` — state of notified PRs

**Deliberately not shared.** It is placed in `$HOME/.claude/.review-watch/` and kept separate per host.

Unlike `repositories.log`, this file is read and written every 60 seconds. If Claude and Codex
run monitoring at the same time, sharing it causes write conflicts. What sharing across hosts would gain
is only "if one side has notified, the other stays silent", which is not worth the risk of conflicts.
It is rather safer for monitoring if both sides notify.

It is placed outside dotfiles because it is machine-specific volatile state.
Taking it to another machine is meaningless, and doing so would cause PRs that have not been notified to be missed.

### `owner-token` — ownership token of the monitoring process

It is placed in the same directory as `seen-pull-requests.tsv`. It is likewise machine-specific volatile state
and is not shared across hosts. It is outside dotfiles, so it does not need to be added to `.gitignore`
(`$HOME/.claude/` is a real directory, and only `skills` is a symbolic link to `link-targets/agents/skills`).

**A mechanism to prevent double startup.** A started process writes its own token (`PID-start time`)
into this file to claim ownership, and each process rereads it on every loop and
retires if it is not its own token. The process that starts later wins.
Writing a value that belongs to no process makes everyone retire, so it also serves as a way to stop them from outside.

It became necessary because we learned that **processes do not die when a session or Claude Code ends.**
Only the harness-side Monitor task disappears, and the process remains and keeps polling.
This orphan delivers notifications to no one, and it shares `seen-pull-requests.tsv` with the monitor set up next,
so it can write a newly found PR as already known before the real monitor sees it.
The real monitoring process then silently skips it, and **a review request is quietly missed.**
This is worse than a duplicate notification, and the main purpose of the prevention is to stop this miss.

Two alternatives were not adopted.

**Killing the process with `kill`** is dangerous. The command line of the wrapper that `Monitor` uses to start this script
also contains the script path, so a pattern match such as `pkill -f`
kills the newly started parent along with the orphan, and monitoring dies immediately.
Even with a PID-file approach, an orphan started before this feature was added has no record and cannot be detected.

A **stop flag** (exit if the file exists) is ideal for "stop everything", but
has a hole in "stop and immediately restart". If the flag is removed after the new process starts,
the process dies right after startup, and that immediate death cannot be told apart from a normal startup. Forgetting to remove it causes the same thing.
With the ownership-token approach, the starting side does nothing, and there is no failure mode of forgetting to remove anything.

Until the old process retires, the old and new processes run side by side, which is a window in which notifications can be missed,
so `sleep` is split into intervals of the ownership check (5 seconds by default), limiting the window to at most that width.
In addition, the new process waits one check interval before its first poll, so it starts reading after the earlier process has retired.

### Reports and diffs — `%TEMP%\claude-pr-review\`

One PR = one report file and one diff file. They are volatile, so they go in a temporary directory.

Files are placed flat without digging subdirectories, and `*.html` / `*.diff` / `*.partial` older than 7 days are deleted by the skill itself.
OS cleanup is effectively ineffective for directories directly under `%TEMP%` (they were observed remaining for over a year),
so cleanup cannot be left to the OS. The layout is flat so that the cleanup target is limited
to just these three types directly under `claude-pr-review`, which prevents accidental deletion.

`*.partial` is the write destination while a diff is being retrieved. `>` truncates the destination before the command runs, so
if retrieval fails, an empty or incomplete diff remains with a new update time and is later mistaken
for "a new diff exists". So the diff is written to a temporary name, and `mv` is run after success is confirmed.

**`.partial` is placed in the same directory too.** If it were put in another location or a subdirectory,
`mv` could turn into a copy across volumes. Then the safeguard of "move only after confirming success"
would itself be half-hearted. The cost of adding one more type of cleanup target is smaller.
An orphan left when a process crashes is cleaned up without catching a file being retrieved, thanks to the 7-day condition.

**The file name is `<owner><repo>-<PR number>`, with no date/time or GUID.**
The purpose is that **another session can compute the path from the identifier**, and since the pre-review is done in a separate session,
this is the key to handover. There is no need to hunt for the previous report with globs.

Previously, the first 8 characters of a GUID were added so that pre-reviewing the same PR twice would not overwrite the earlier report.
In practice there was no case where an overwrite caused trouble, and the random suffix made it impossible to tell new from old, which did more harm.

The `/` in `owner/repo` is removed and the parts are concatenated. Replacing it with `-` would make `a-b/c` and `a/b-c`
the same name, and removing `/` makes `ab/c` and `a/bc` the same, so **a collision remains
possible in principle either way.** The probabilities are similarly low, and a collision can be handled by moving a file aside manually,
so the option that does not add a delimiter was chosen.

Diffs are **placed here rather than in a session-specific scratchpad** for the same handover reason.
A scratchpad path contains the session ID and disappears when the session ends.

A diff becomes stale as the head advances. **The revision that was read is kept by writing the head SHA in the report body.**
Putting the SHA in the file name would show freshness from the name alone, but a file would be added for every head update,
and the advantage of the path being determined by the identifier would be lost.
Comparing update times (`gh pr view --json updatedAt` against the diff file's mtime) is used as a rough guide,
but it is unreliable with a force-push, clock skew, or an update in progress, so it is not used alone for the decision.
`gh pr diff` is cheap, so when in doubt, fetch it again.

The report template (`report-template.html`) has no dedicated field for the head SHA.
To avoid changing the template, the procedure (`SKILL.md` B-8) makes it mandatory to write the SHA together with the branch name
where the head is displayed.

## How far to read local clones

Diffs are fetched with `gh pr diff`, and local clones are read only as reference material for grep.
Neither `git fetch` nor `git checkout` is run.

There are two reasons: we do not want to write refs and objects into the user's repository,
and it could collide with other git operations running at the same time.
If we only read, the API is enough.

As a trade-off, the local working tree may be at a different revision from the one under review.
This is handled by "verify only the parts that are the basis of a finding with `gh api .../contents?ref=<sha>`".
For scoping the impact (is there other code of the same kind?), a somewhat old copy is practically fine.

## Splitting sessions and delegating to subagents

**Monitoring and pre-review are split into separate sessions.** The monitoring session only issues notifications and does not pre-review.
No exception is made based on the size of the diff.

The main job of a monitoring session is to wait for hours and issue notifications, so keeping each notification lightweight is what gives it value.
If it carries even one pre-review, that weight stays with it from then on.
Compaction cannot be invoked by the session itself (`/compact` is a user-side command), so it also cannot choose
when automatic summarization runs.

Previously the monitoring session guarded against this by always delegating to a subagent, but that meant
**the basis of each finding remained nowhere.** Only the conclusion comes back from the delegate, so when asked for the basis,
someone has to reread the diff. If the sessions are split, the one who read it becomes the discussion partner as is.
The history is recorded in `SKILL.history.md`.

On the pre-review session side, delegation is not mandatory and is chosen by scale. Reading it yourself lets you answer
discussion after the report immediately, while for a large PR it is faster to split it by perspective and send the pieces out.
