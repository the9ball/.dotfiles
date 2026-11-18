---
name: pr-status-summary
description: Summarize the current status of the user's own open GitHub pull requests in one repository as a short, paste-ready task status list (for example for a Slack thread). Use for requests such as `PRの状態をまとめて` (summarize my PR status), `現在のタスク状況をまとめて` (summarize my current task status), or `自分名義のPRのサマリ` (summary of PRs under my name). Read-only; it never posts, comments on, or changes pull requests. Not for reviewing PR contents or for PRs where the user is only a reviewer.
---

# PR status summary

Collect the user's open pull requests in one repository with `gh`, classify each one, and return a paste-ready list in the fixed format below. This skill only reads GitHub. Posting the result anywhere is out of scope; when the user asks for that, it is a separate external operation under the usual authorization rules.

## 1. Fix the target

- **Repository:** use the `owner/repo` the user names. Otherwise use the GitHub repository of the current directory (`gh repo view --json nameWithOwner`). If neither resolves to exactly one repository, ask instead of guessing. Do not carry a repository over from earlier sessions or from this skill's examples.
- **Author:** `@me` (the authenticated `gh` account) unless the user names another login.
- **Since date (optional):** used only for the "merged since" part of step 5.

## 2. Collect open pull requests

```bash
gh pr list -R <owner/repo> --author "<author>" --state open --limit 200 \
  --json number,title,url,isDraft,updatedAt,baseRefName,headRefName,isCrossRepository,reviewDecision,mergeStateStatus,reviewRequests,reviews,statusCheckRollup
```

`gh pr list` reads the repository directly, so prefer it over `gh search prs`, whose index can lag.

If `mergeStateStatus` is `UNKNOWN`, GitHub has not computed it yet. Read that pull request once more with `gh pr view <number> -R <owner/repo> --json` and the same field list. If it is still `UNKNOWN`, classify it with the remaining fields; rule 6 in step 3 handles an approved one.

### Exclusions

Leave out, and list after the paste-ready block (step 6):

- draft pull requests;
- pull requests not updated for `stale_days` days (an adjustable parameter, default 30; the user can change it for the request).

## 3. Classify each pull request

### Derived values

- **Bot reviewer:** a login that ends in `[bot]`, or is one of `copilot-pull-request-reviewer`, `github-actions`, `dependabot`, `renovate`, or otherwise clearly names an automated reviewer. `gh pr` JSON drops the `[bot]` suffix that the REST API shows, so do not rely on the suffix alone. When unsure, treat the login as a bot and mention it in the notes.
- **Human review state:** for each non-bot author in `reviews`, take their latest review whose state is `APPROVED`, `CHANGES_REQUESTED`, or `DISMISSED`, and ignore `COMMENTED` and `PENDING`. Do not use `latestReviews`: a reviewer who approves and then leaves a comment review shows there as `COMMENTED`, which hides the approval.
- **Human approval:** a human review state of `APPROVED`.
- **Failing check:** a `statusCheckRollup` item that is a CheckRun with `conclusion` in `FAILURE`, `TIMED_OUT`, `ACTION_REQUIRED`, or `STARTUP_FAILURE`, or a StatusContext with `state` in `FAILURE` or `ERROR`. A `CANCELLED` CheckRun is not failing (it often comes from a run superseded by a newer one); mention it in the notes only when no later run of the same check succeeded.
- **Pending check:** a CheckRun whose `status` is not `COMPLETED`, or a StatusContext with `state` `PENDING` or `EXPECTED`.
- **Upstream pull request:** another open pull request of the same author whose `headRefName` equals this one's `baseRefName` and whose `isCrossRepository` is `false`.

### Rules

Every pull request matches at least one rule; the first match wins.

| Order | Condition | Status (exact string) |
|---|---|---|
| 1 | `mergeStateStatus` is `DIRTY` | `コンフリクト解消待ち` (waiting for conflict resolution) |
| 2 | at least one failing check | `CI 修正待ち` (waiting for a CI fix) |
| 3 | `reviewDecision` is `CHANGES_REQUESTED`, or some human review state is `CHANGES_REQUESTED` | `修正対応中` (addressing requested changes) |
| 4 | an upstream pull request exists | `上流マージ待ち` (waiting for the upstream PR to merge) |
| 5 | approved (see below), `mergeStateStatus` is `CLEAN`, `HAS_HOOKS`, `UNSTABLE`, or `BEHIND`, and no pending check | `マージ待ち` (waiting to be merged) |
| 6 | approved, but a pending check exists or `mergeStateStatus` is `BLOCKED` or still `UNKNOWN` | `マージ待ち(?)` |
| 7 | anything else | `レビュー待ち` (waiting for review) |

- **Approved** means `reviewDecision` is `APPROVED`; or `reviewDecision` is empty (the base branch requires no review), there is at least one human approval, and `reviewRequests` is empty. Requested reviewers who have not reviewed yet keep the pull request at `レビュー待ち` even when others approved.
- `mergeStateStatus` values are `BEHIND`, `BLOCKED`, `CLEAN`, `DIRTY`, `DRAFT`, `HAS_HOOKS`, `UNKNOWN`, and `UNSTABLE`. For `BEHIND` under rule 5, add a note that the branch needs updating. For rule 6, add a note saying why (`CI 実行中` (CI running), the merge is blocked, or the merge state is unknown).
- Do not invent statuses beyond this table. The only other variation is appending `(?)` to a status from rules 1–5 or 7 when the merge state stayed `UNKNOWN` after step 2; never add the suffix twice.

## 4. Find items that need attention

For each included pull request, read the recent activity:

```bash
gh pr view <number> -R <owner/repo> --json comments,reviews
```

Flag a pull request when, after its latest human approval (or after the author's latest activity when there is no approval), someone other than the author left a `COMMENTED` or `CHANGES_REQUESTED` review with a non-empty body, or a comment, that the author has not answered. Automated review bots count here, because their findings can still block a merge. Summarize the point in one line; do not judge whether it is valid.

Unresolved inline review threads are not visible in these fields. Say so if the user asks for complete coverage, instead of implying none exist.

## 5. Compare with the previous summary (optional)

- If this conversation already contains a summary from this skill for the same repository and author, or the user pastes one, compare with it: pull requests that disappeared (check whether they were merged or closed with `gh pr view`), new pull requests, and status changes.
- Otherwise, if the user gave a since date, list pull requests merged since then:

  ```bash
  gh pr list -R <owner/repo> --author "<author>" --state merged --limit 200 --search "merged:>=<YYYY-MM-DD>" --json number,title,url,mergedAt
  ```

  The date is interpreted in UTC; add an offset such as `merged:>=2026-11-12T00:00:00+09:00` when the user's local day matters. This query goes through the search index, so a pull request merged in the last few minutes can be missing.
- Otherwise omit the comparison. Do not fetch earlier summaries from Slack or other services to build it.

## 6. Output

Return one fenced `text` block that the user can paste as is, then the notes.

Paste-ready block (keep the first line, the bullets `•` and `◦`, the four-space indent, and the ` : ` separator exactly):

```text
現在のタスク状況は以下の通りです。
• <topic>
    ◦ <status> : <url>
```

The first line means "The current task status is as follows."

- **Lines:** one `◦` line per pull request.
- **Topic:** a short Japanese noun phrase for the feature, derived from the PR title without the conventional-commit prefix. When a previous summary exists (step 5), reuse its topic wording for the same pull requests.
- **Grouping:** put a pull request under the same topic as its upstream pull request (rule 4), upstream first. Otherwise group pull requests only when the previous summary grouped them or the user asks; do not merge topics by judging that features are similar.
- **Order:** keep the order of the previous summary when step 5 found one, and add new topics at the end. Otherwise order topics by their oldest pull request number.
- **URL:** the plain pull request URL, without Markdown link syntax, so that chat tools link it themselves.

After the block, in the conversation language and briefly:

- changes since the previous summary (step 5), if any;
- items that need attention (step 4) and the notes required by step 3, with the pull request number;
- excluded pull requests (drafts, stale ones) by number, so the user can ask to include them.

## Notes

- When `gh` comes from aqua, a following `aqua failed ... exit status 1` line only repeats the `gh` exit code. Judge the result by that exit code and the `gh` error message.
- If `gh` fails, follow the access-failure rules of the `github` Skill. Do not switch to another account, connector, or browser.
