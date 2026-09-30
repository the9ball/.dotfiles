---
name: review-watch
description: Continuously monitor (as a resident process) GitHub pull requests for which you are designated as a reviewer, and notify you of review requests. When instructed, pre-review (下読み) the PR and compile the results into a single HTML report. Use for setting up or restarting review monitoring, detecting review requests, or requesting a PR pre-review and report.
---

# Monitoring review requests and PR pre-reviews

Detect PRs for which you have been designated as a reviewer and notify the user. When instructed, pre-review (下読み) the PR and produce a report with **1 PR = 1 HTML file**. The pre-review assumes that a person makes the final judgment, and review comments are never posted to GitHub automatically.

## Decide on a role first

**Separate monitoring and pre-review into different sessions.** Decide first which role you were called for, then read the matching chapters.

| Role | What to do | Chapters to read |
|---|---|---|
| **Monitoring session** | Resident monitoring and notifications only. No pre-review | A and C |
| **Pre-review session** | Pre-review one PR, submit a report, and respond directly to the discussion that follows | B and C |

The reason for separating the sessions is explained in "A-4. Do not pre-review here".

When editing this skill itself, read `DESIGN.md` (file placement and the reasons for it) first.
Changes in policy are recorded in [`SKILL.history.md`](SKILL.history.md).

---

## A. Monitoring session

The tool names that appear in this chapter (`Monitor` / `TaskStop` / `TaskList`) are Claude Code's.
In other environments, read them as the equivalent means of running a resident process and turning its standard output into notifications.

### A-1. Set up monitoring

Use the `Monitor` tool to run the script bundled with this skill as a `persistent` resident process.

- `command`: `bash "$HOME/.claude/skills/review-watch/watch-review-requests.sh"`
- `description`: `GitHub のレビュー依頼 (自分が指名された PR)` (a Japanese display label; keep it as is)
- `persistent`: `true`

Do not write the script out inline. Besides being rejected by the permission classifier,
any gap in the difference-detection logic makes the notification repeat every minute and keeps burning credits.

What the script does:
It polls `gh search prs --review-requested=@me --state=open` every 60 seconds
and writes only the difference from `$HOME/.claude/.review-watch/seen-pull-requests.tsv` to standard output.
What this command returns is a snapshot of "the PRs currently awaiting review", not a sequence of events,
so without taking the difference the same PR would be notified every time.
A PR that disappears from the search results because a review was submitted is dropped from the state file once it has been absent twice in a row
(hysteresis to avoid double notifications caused by a delay in updating the search index).

Tell the user the task ID returned by `Monitor` and record it.
Resident monitoring does not appear in `TaskList` (that is for the ToDo list).

### A-2. Restarting and stopping

**The script's process remains even after the session or Claude Code ends.**
Only the harness-side Monitor task disappears. The process keeps polling every 60 seconds,
becoming an orphan that is "still polling although no notifications arrive" (this happened twice in a row in practice).
`TaskStop` is the same: it only stops the harness record and does not guarantee that the process ends.

To restart monitoring, run the same setup procedure again. When the script starts, it writes its token to `$HOME/.claude/.review-watch/owner-token` and claims ownership. The previous process retires at its next ownership check (every 5 seconds by default), so the most recently started process wins. The invoking session does not need to find or kill older processes.

**Do not take over a monitor that is running in another session.**
Doing so takes away its ownership, and notifications move to this session. When you cannot tell whether it is running,
confirm with the user before restarting.

To make sure every process stops, write a value that does not belong to any process into this file.

```bash
echo stop > ~/.claude/.review-watch/owner-token
```

To reset the state for an operation check, delete `seen-pull-requests.tsv`
(at the next poll, all PRs without a submitted review are notified as new).

### A-3. When a request is detected, only notify

**Only notify; do not start a review automatically.** Pass along the information in the notification line as it is
(repository, PR number, title, number of changed files, URL), then
wait for the user to decide whether to review it.

When relaying it, repeat the PR URL as a `[owner/repo#number — title](URL)` Markdown link.
The rendering of the notification body itself is out of your control, so provide a clickable form in your own response.
Do not put it in a code block, because it would not become a link.

Fully reviewing every designated PR each time would multiply the cost,
so keep it in a form where the user chooses which PRs are actually read.

### A-4. Do not pre-review here

**Pre-review is the job of a separate session. Do not do it in a monitoring session, and do not make exceptions based on the size of the diff.**
Do not start it in this session even by delegating it to a subagent.

There are two reasons.

The main job of this session is to wait for hours and issue notifications, so keeping each notification lightweight is what gives it value.
If you carry even one pre-review, its weight stays with the session from then on.
Moreover, you cannot invoke compaction yourself (`/compact` is a user-side command),
so you cannot choose when automatic summarization runs.

The other reason is that **when you delegate to a subagent, the basis of each finding does not stay with you.**
Only the conclusion comes back, so when you are asked "show the basis for this finding", someone has to reread the diff.
If the session that did the pre-review becomes the discussion partner, this rereading is unnecessary.

Therefore, when asked for a pre-review, ask the user to **open a new session**.
The materials are stored at paths determined by the identifier (B-1), so there is no need to write a handoff prompt.
In the new session, saying `<owner>/<repo>#<番号> の下読み` (pre-review of `<owner>/<repo>#<number>`) or passing the PR URL is enough for this skill to start and continue from there.

**A PR number alone is not enough.** Numbers are assigned per repository, so the number alone does not
identify the repository. When giving directions, showing the PR URL as it is is the reliable way.

---

## B. Pre-review session

### B-1. Identifiers and where to keep materials

#### How to identify a PR

**The handoff identifier is the PR URL or `owner/repo#number`.**
PR numbers are assigned per repository, so the **number alone does not identify the repository.**
There is also no guarantee that the new session's working directory matches the target repository.
If you are given only a number, confirm which repository it is before starting.

`gh` looks at the repository in the working directory by default. When running from a location other than the target,
add `--repo <owner>/<repo>` (not needed when the URL is passed directly).

#### Storage location and naming

Place diffs and reports flat in `%TEMP%\claude-pr-review\`,
and **make the names derivable from the identifier**.

| Material | File name |
|---|---|
| Diff | `<owner><repo>-<PR number>.diff` |
| Report | `<owner><repo>-<PR number>.html` |

Remove the `/` in `owner/repo` and concatenate (`OrangeCube/Sentia` → `OrangeCubeSentia`).
Because the concatenation boundary disappears, `ab/c` and `a/bc` would in theory produce the same name, but the probability that both repositories exist
and have the same PR number is negligible. If you notice a collision, move one file aside by hand before pre-reviewing.

Keep one file per PR, and overwrite it when pre-reviewing again. Do not add a date/time or GUID to the name.
The key to handing work over is that the path can be computed from the identifier, so nobody has to hunt with globs.
If an overwrite fails and leaves a broken report, just recreate it.

**Do not put files in a session-specific scratchpad.** The session ID is part of its path
and it disappears when the session ends, so another session could not take over.

**First create the storage location and decide its absolute path before using it.** The diff is saved (B-3) before the report is written (B-8),
so redirecting into a directory that does not exist yet makes the save fail.

```powershell
$reportDirectory = Join-Path $env:TEMP "claude-pr-review"
New-Item -ItemType Directory -Force $reportDirectory | Out-Null
$reportDirectory   # From here on, pass this absolute path to the bash side as is
```

Do not rely on bash's `$TEMP`. It is not a POSIX variable, and **its value's representation depends on the environment that started the shell.**
On this machine, Claude Code's bash resolved it to `C:\Users\...\AppData\Local\Temp` (Windows format),
while Codex's Git Bash resolved it to `/tmp` (POSIX format).
Even when both point to the same place, a path assembled as a string in one environment breaks when passed to the other.
Decide the path once in PowerShell and reuse it from then on.

#### Start-up procedure

1. Receive the identifier and create the storage location (above).
2. Get the basic information and the **head SHA** with `gh pr view` (B-2).
3. If a report already exists, read it. It is the result of the previous pre-review, so you get the findings, evidence, confidence, and limitations as they were.
   **If the head SHA recorded in the report differs from the current `headRefOid`, it is a different revision from the previous one.**
   Judge again from the new diff whether the findings still hold.
   **Treat a report without a head SHA the same way** (since you cannot determine which revision was read,
   consider it a different revision and pre-review again). Reports issued before this became mandatory fall into this case.
4. If a diff file already exists, read it. However, it dates from the previous run. If its head SHA does not match,
   or cannot be determined, fetch it again. `gh pr diff` is cheap.
   Comparing update times (is `updatedAt` later than the diff file's mtime?) is only a rough guide.
   It is unreliable with a force-push, clock skew, or an update in progress, so when in doubt, fetch it again.
5. Look up the clone location in `repositories.log` (B-4).

### B-2. Always get the complete file list

`gh pr view --json files` **is cut off at 100 entries**. There is a real case where this was overlooked
and led to a false finding that "the model data is missing". Always get the file list this way.

```bash
gh api "repos/<owner>/<repo>/pulls/<number>/files" --paginate --jq '.[].filename'
```

Without `--jq`, the full `patch` text of every file is returned, and for a large PR hundreds of thousands of tokens of JSON
land in the context as they are. For checking for missing items or matching settings, file names are enough.

Confirm that the number of retrieved entries matches the PR's `changedFiles`,
and state it in the report if they do not match.

```bash
gh pr view <PR URL> --json changedFiles,additions,deletions,author,baseRefName,headRefName,headRefOid,title
```

Use `headRefOid` when verifying files that are not in the diff against the contents of the head.

### B-3. Get the diff from the API and save it

Get the diff contents with `gh pr diff`. No local clone or fetch is needed.
Do not read standard output as it is; save it to the path decided in B-1 and then read it.

**Write to a temporary file, confirm success, and then move it to the real name.**
`>` truncates the destination before running the command, so if `gh pr diff` fails midway,
an empty or incomplete diff remains with a new update time and is later mistaken for "a new diff exists".

```bash
diff_path="<absolute path decided in B-1>/<owner><repo>-<PR number>.diff"
if gh pr diff <PR URL> > "${diff_path}.partial"; then
  mv -f "${diff_path}.partial" "${diff_path}"
else
  rm -f "${diff_path}.partial"
  echo "Failed to fetch the diff; the previous diff was kept" >&2
fi
```

The reason for saving before reading is so that the same diff can be read again in another session or by a delegate.
Putting thousands of lines of diff directly into the conversation uses up much of the context by itself.

**Note down `headRefOid` at this point.** It records which revision you read,
and is used both in the report (B-8) and in the restart decision (B-1).

Do not use `git fetch` + `git diff origin/<base>...origin/<head>`.
It writes refs and objects into the user's repository,
and it can collide with other git operations running at the same time. If you only want to read, the API is enough.

When `additions` / `deletions` is large, first look at the file list and narrow down the range to read.

### B-4. Handling local clones

The API is enough for the diff itself, but a local clone is needed when you want to grep the whole repository
to check "whether the same pattern remains elsewhere".
Findings about the scope of impact come only from here, so do not drop this search.

However, **do not rely on the working-tree state.** The checked-out branch is often unrelated to the PR under review,
and there is no guarantee that the PR's branch has been fetched.
Do not run `git fetch` or `git checkout`; read what is there as it is.

- Read the local copy as **reference material for getting a lead**. Even if it is somewhat old,
  it is practically fine for looking for "is there other code of this kind?".
- **Verify only the parts that are the basis of a finding against the contents of the head.** Always do this
  when quoting a file that is not included in the diff.

```bash
gh api "repos/<owner>/<repo>/contents/<path>?ref=<head SHA>" --jq '.content' | base64 -d
```

If any quotation remains unverified, say so in the report's 「見ていない範囲・限界」 (Unreviewed Scope and Limitations) section.

#### Looking up the clone location

Record the locations of clones you have found in the past in `$HOME/.agents/skills/review-watch/repositories.log`
as TSV (`owner/repo<TAB>absolute path`). It is placed under `link-targets/agents` so that it can be reused
when the same monitoring is run from something other than Claude (such as Codex). `*.log` is already
gitignored on the dotfiles side, so it is not tracked.

This is a cache, not master data. Always verify it before use, and silently discard it if it is wrong.

1. If the file has a line for `<owner>/<repo>`, look at its path.
2. If the path exists and `git -C <path> remote get-url origin` points to the target repository, adopt it.
3. If it does not match, discard that line and search the disk. If found, add or update the line.
   **If multiple clones with the same origin are found**, prefer a plain working clone that has no suffix or directory
   indicating a derived or temporary copy, such as `_copydlls` or `gitmeta`.
   If you cannot decide, ask the user.
4. If you really cannot find it, you may proceed without a local reference.
   The scope-of-impact analysis will be weaker, so state that in the report's 「見ていない範囲・限界」 (Unreviewed Scope and Limitations) section.

When appending a line, embedding a Windows path directly in `printf`'s format string makes `\U` and similar sequences
be interpreted as escapes and produces a `printf: missing unicode digit for \U` warning (the output itself is correct).
Pass values as arguments, like `printf '%s\t%s\n' "$repository" "$path"`.

### B-5. Read it yourself or delegate it?

In a pre-review session, **you may read it yourself.** Reading it yourself is in fact better, because after the report is submitted
you can answer immediately when asked "what is the basis for this finding?" or "is there a similar pattern elsewhere?". Choose by scale.

- **Read it yourself**: diffs up to a few thousand lines, or up to a few dozen files.
  Choose this if you expect the discussion to continue after the report.
- **Split it up and send it to subagents**: for anything larger, or when each perspective can be read independently.
  Only conclusions come back, so verify again yourself any finding that needs detailed evidence.

**You may issue multiple delegations for one PR.** Splitting by perspective is sometimes faster.
Each subagent is single-use: **do not have one subagent read multiple PRs in a row.**
The contexts get mixed, and the problem avoided in the monitoring session recurs at the delegate.

A lower-cost model is enough for a pre-review. Mechanical matching and detecting uninitialized variables work even with a downgraded model.
Use a two-tier setup: verify with a higher-tier model only the findings the delegate marked "確度: 低" (confidence: low)
and findings that are assertive but have thin evidence.

#### How to hand work to a delegate

**Write the prompt to be self-contained, on the assumption that the delegate cannot see the caller's conversation.**

**Observed with Claude Code**: an agent that inherits the parent session's context
(`subagent_type: "fork"`) does not exist in this environment, and specifying it fails with
`Agent type 'fork' not found` (tried twice, failed twice).
The types that worked were `architect` / `claude` / `claude-code-guide` / `Explore` / `general-purpose` /
`implementer` / `investigator` / `Plan` / `reviewer` / `statusline-setup`.
For a general-purpose pre-review, choose `general-purpose`.

Limit what the delegate explores to "reading the diff and matching it against the surrounding code".
The calling side gets the diff and finds the clone location beforehand,
and **passes the path of the saved diff file so that the delegate does not rerun `gh pr diff`.**
Items with a limited count that are used directly for checking missing entries, such as the file list,
may go straight into the prompt (even about 60 files is fine).
If you leave this to the delegate, tool calls and waiting time increase accordingly.

| Scale | Result |
|---|---|
| 7 files, +45/-14 (materials not handed over; the delegate gathered them) | 149k tokens, 11 minutes |
| 60 files, +3188/-34 (diff handed over in advance as a file) | 218k tokens, 42 tool calls, 9.4 minutes |

### B-6. Perspectives

Just "reviewing" ends up superficial. Narrow the perspectives according to the type of PR.

- **Image PR (from a designer)**: Actually open the images and read the text one character at a time. Extra or missing characters, duplicates,
  mismatches with the source material, and notation variations within the same series. If the source material (such as a spreadsheet cell range)
  is provided, always match against it. Images are token-heavy, so narrow them down to the number you need.
- **Asset-addition PR**: Mechanically compare the compression settings, mesh type, and so on in `.meta` against all existing files.
  This reveals discrepancies that cannot be seen by eye.
- **Shaders and code**: Uninitialized variables, missing conditional branches, and identifying the scope of impact.
- **Generated products**: Is a generated product being edited directly? Is a type definition or product updated on only one side?

If the repository has an `AGENTS.md`, read it and prioritize project-specific review perspectives.

### B-7. Matching against other reviews

**Copilot**: If enabled for the repository, it adds automatic comments to the PR, but they are slow to appear
and are often not there yet right after a review request is detected. If you want to match against them,
read them later with `gh pr view <URL> --comments`.

**Codex**: Run it read-only and have it output only the conclusion. Its investigation log can run to thousands of lines,
and reading it becomes a cost on our side.

**Pass the saved diff file and the head SHA, and do not let it fetch the diff again.**
If it runs `gh pr diff` itself, the result may differ from the revision you read
(a force-push can happen in between). This is the same reason as for delegates (B-5).

```bash
codex exec --sandbox read-only "Review PR <owner>/<repo>#<number> (head <SHA>). The diff is already saved at <absolute path of the diff file>; read it and do not re-fetch it with gh pr diff. Do not run git fetch or git checkout. Give the conclusion and its basis in Japanese; no intermediate investigation log is needed. Do not edit any files."
```

`--sandbox read-only` is required. Without it, files may be rewritten.
If the conclusions conflict, compare the evidence on both sides and find out which is correct.

### B-8. Submit the report

The storage location was created in B-1. Clean out old materials, then decide the output path:

```powershell
$reportDirectory = Join-Path $env:TEMP "claude-pr-review"

# Delete reports and diffs older than 7 days, and leftovers from interrupted retrievals.
# A directory directly under %TEMP% is effectively never removed by OS cleanup (there are real cases of it remaining for over a year), so
# do not dig subdirectories; place files flat and do the cleanup here.
$cutoff = (Get-Date).AddDays(-7)
Get-ChildItem -LiteralPath $reportDirectory -File |
  Where-Object { ($_.Extension -in '.html', '.diff', '.partial') -and ($_.LastWriteTime -lt $cutoff) } |
  Remove-Item -Force

Join-Path $reportDirectory "<owner><repo>-<PR number>.html"
```

Limit deletion to `*.html` / `*.diff` / `*.partial` directly under `claude-pr-review`.
Do not create subdirectories or delete other extensions.

`*.partial` is an orphan left when the process died while retrieving a diff (B-3). Because of the 7-day condition,
it never catches a file that is being retrieved right now.

Use `report-template.html` as the template and fill in `{{...}}`.
Do not break the template. In particular, observe the following.

- **Do not reference external resources.** Keep it self-contained, including CSS (the template already is).
- Keep both light and dark modes working.
- **Always write the head SHA.** The template has no dedicated field, so write it
  together with the branch name where the head is displayed (`head <branch> @ <SHA>`). Without it, you cannot later
  determine which revision was reviewed, and cannot judge how fresh the diff is when resuming.
- Choose the severity from `critical` (must fix) / `warn` (needs confirmation) / `info` (suggestion),
  and keep the card's class and badge consistent. Sort in descending order of severity.
- For each finding, always fill in **根拠 (basis) / 確認方法 (how to verify) / 確度 (confidence)**. Do not write a finding that lacks why it holds ("why can you say that?") or how a person can verify it.
- **Do not leave the 「見ていない範囲・限界」 (Unreviewed Scope and Limitations) section empty.** State the ranges that may have been overlooked because of
  the validity of the specification, behavior on real devices, or retrieval limits. This is the starting point for a person's final judgment.
- Delete a severity's category section entirely if there are no corresponding findings.
  **However, keep the 「指摘」 (Findings) section itself.** When there are zero findings, remove the cards and
  write one sentence saying that "no problem could be detected by mechanical matching" (the template gives the same instruction).

When you finish writing, hand the report to the user and have it rendered on the spot
(in Claude Code, add `display: "render"` to `SendUserFile`).
Even a temporary file is fine for viewing.

### B-9. After the report is submitted

**Submitting the report is not the end.** From here on, the pre-review session serves as the discussion partner.
Keep waiting with what you read still at hand so that you can respond to follow-ups such as
providing the basis for a finding, looking at it from a different perspective, or preparing the text of review comments (without posting them).
This is why it is separate from the monitoring session.

Do not carry multiple PRs in one session. The problem avoided in the monitoring session recurs in a different place.

---

## C. What not to do (both sessions)

- **Automatically posting review comments to GitHub.** A wrong finding would go straight to the other person. A person checks it and posts it themselves.
  Do not use `gh pr review` or `gh pr comment`, and do not issue POST/PATCH/PUT/DELETE through `gh api`.
- **Pre-reviewing in a monitoring session.** Do not start one, even by delegating it to a subagent (see "A-4").
- **Accepting assertions uncritically.** Findings can be wrong. In one past case, a reference was wrongly reported as missing in code that was unused because of rendering settings, and the call target of a same-named method was mistaken, reporting a nonexistent problem. Findings of the "missing" or "reference has disappeared" kind are especially error-prone.
  The more assertive a finding, the more you should corroborate it.
- **Judging the validity of a specification.** Without the source material, you cannot know whether the implementation matches the specification.
  We are good at mechanical matching and detecting oversights, but whether "this specification is acceptable" is for a person to judge.
