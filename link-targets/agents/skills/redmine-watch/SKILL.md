---
name: redmine-watch
description: Monitor Redmine tickets for which you have ever been the assignee (including ones you no longer hold) and notify you of changes made by others, such as comments, status changes, and send-backs (差し戻し). Use for requests to set up or restart Redmine ticket monitoring or to detect activity on tickets you have been assigned.
---

# Monitoring Redmine tickets you have been assigned

Add every ticket for which you have ever been the assignee to a watch list, and notify the user of changes made by others.
**Only notify; do not automatically read the ticket contents.** Never write anything to Redmine.

When editing this skill itself, read `DESIGN.md` (file placement and the reasons for design decisions) first.

## 1. Set up monitoring

Use the `Monitor` tool to run the script bundled with this skill as a `persistent` resident process.

- `command`: `bash "$HOME/.claude/skills/redmine-watch/watch-assigned-issues.sh"`
- `description`: `Redmine の担当チケットの変更 (過去に担当したものを含む)` (a Japanese display label; keep it as is)
- `persistent`: `true`

Do not write the script out inline. Besides being rejected by the permission classifier,
any gap in the difference-detection logic makes the notification repeat and keeps burning credits.

**Set up this monitoring in a dedicated session.** If you set it up in a session that is doing other work,
that session becomes the owner of the monitor and notifications are directed to it.

Tell the user the task ID returned by `Monitor` and record it.
Resident monitoring does not appear in `TaskList` (that is for the ToDo list).

### What the script does

It calls `$HOME/tools/Redmine.Cli/redmine.exe` (see the `redmine-cli` skill) at 1-hour intervals
and writes only the difference from the state file `$HOME/.claude/.redmine-watch/watched-issues.tsv` to standard output.
Each CLI call is aborted after 15 seconds by default (changeable with `REDMINE_WATCH_CLI_TIMEOUT_SECONDS`).
One poll does four things.

1. **Reference table**: Get the status list with `statuses list` and build the set of IDs that count as finished.
   A loop that cannot get it and has no previous cache is carried over to the next time, with no notification and no advancing of the difference.
2. **Discovery**: Use `issues list --assigned-to me --status open` to add the open tickets
   you are currently assigned to the watch list.
   If the first discovery is incomplete, the initial state is not fixed, and if it is incomplete three times in a row, only one warning line is issued.
   The first-run handling is kept until discovery becomes complete again, and `totalCount=0` with `issues=[]` counts as a normal, complete discovery.
   From the second run on, retrieval of the tickets already being monitored continues even if discovery fails.
3. **Retrieval**: Send `issues show <id> --include journals` once for each ticket on the watch list.
4. **Difference**: If there are changes made by **someone other than you** after the last journal you saw, notify with one line per ticket,
   and fix that ticket's state immediately afterward.

For an existing ticket that has entered a finished status, if there are un-notified journals from others, the change is notified once and then
the ticket is dropped from the watch list. A ticket already finished at the moment it is newly added (`lastJournalId=-1`)
is dropped without notification, because it cannot be told whether it is existing or new. The six statuses that count as finished in this Redmine are
**`保留` (Pending), `却下` (Rejected), `本番適用済み` (Applied to production), `組込み済み/完了` (Integrated/Completed), `リリースなし` (No release), and `終了` (Closed)**.
The transition to `本番適用済み` or `組込み済み/完了` is itself notified once, but a send-back (差し戻し) comment
after it has left monitoring cannot be picked up. To keep following it, change the status back in Redmine.

### Why a local watch list is needed

There is no way to ask Redmine "which tickets was I assigned to in the past". The API can only return
"the tickets I am assigned to now", and a ticket disappears from the search results once you are no longer the assignee.
To keep following a ticket on which you left a comment and then handed off the assignment, the only way is to store locally
what was detected while you were the assignee.

Two constraints remain because of this structure. Both are accepted by design.

- **A ticket you stopped being assigned to before monitoring began cannot be picked up.** The list is built after monitoring starts.
- **A ticket you were assigned to for less than the polling interval (1 hour) cannot be picked up.**

### Handling duplicates and misses

Writing to standard output and updating the state file cannot be committed at the same moment, so
"zero duplicates and zero misses" cannot be guaranteed in principle.
The design leans toward **avoiding misses and limiting duplicates**.

So the same change may be notified twice in the following cases. None of these is abnormal.

- The process stopped or lost ownership immediately after issuing a notification (a resend of at most one ticket)
- The old process was in the middle of a retrieval when monitoring was restarted

### Retrieval cost

The retrieval pass sends one request per ticket on the watch list. Tickets you are no longer assigned to
cannot be picked up by a list query, so there is no way to fetch them in bulk. Each CLI call is aborted after 15 seconds by default,
but there is no upper time limit on a whole poll. At a 1-hour interval, up to a few dozen tickets is no problem, but once the list
grows to several hundred, lengthen the interval or remove rows from `watched-issues.tsv` by hand. A ticket that permanently fails to be retrieved or parsed
stays on the list to avoid missing anything.

## 2. What to do when a change is detected

**Only notify; do not automatically read the ticket.** Pass along the information in the notification line as it is
(ticket number, subject, current status, who changed it, what changed, URL), and
wait for the user to decide whether to follow up on the contents.

When relaying it, repeat the ticket URL as a `[#number — subject](URL)` Markdown link.
The rendering of the notification body itself is out of your control, so provide a clickable form in your own response.
Do not put it in a code block, because it would not become a link.

The messages written to standard output are as follows. Each one line is one notification. Save failures and startup failures
terminate the process to protect the state. Cache-save failures and first-discovery failures keep monitoring running.
The message strings are Japanese literals output by the script; they are kept as is, and the English after each is only a gloss.

- `Redmine更新:` — Someone else made a change to a ticket being monitored.
- `Redmine担当追加:` — A ticket you were newly assigned to was added to the watch list.
- `Redmine監視: Redmine への問い合わせが3回連続で失敗している。API キーの失効や接続設定を確認する` —
  Retrieval of the reference table failed three times in a row. If there is no usable cache, notifications and advancing of state are stopped.
- `Redmine監視: Redmine への問い合わせが復旧した` — Retrieval succeeded after three or more consecutive failures.
- `Redmine監視: 初回の担当チケット発見が3回連続で不完全。次回も再試行する` —
  The first discovery was incomplete three times in a row. The initial state is not fixed.
- `Redmine監視: 初回の担当チケット発見が復旧した` — Discovery returned to complete after an incomplete first discovery.
- `Redmine監視: ステータス参照表を保存できない。監視は継続する` —
  Retrieval of the reference table succeeded, but saving the cache failed. It is not notified again during the same process.
- `Redmine監視: 接続先 URL を解決できなかった。通知の URL が不完全になる` — Issued only once at startup.
- `Redmine監視の起動に失敗: 状態ディレクトリを作成できない (<path>)` — Stops with exit code 1.
- `Redmine監視の起動に失敗: CLI のディレクトリが見つからない (<path>)` — Stops with exit code 1.
- `Redmine監視の起動に失敗: 所有トークンを書き込めない (<path>)` — Stops with exit code 1.
- `Redmine監視を停止: 監視リストの状態を保存できない` — Stops with exit code 1 because the state cannot be fixed.

A notification carries only enough to detect a send-back (差し戻し), and attribute changes are not resolved down to names
(status is the one exception, and shows the names before and after, such as `新規→割振済` (New → Allocated)).
When you want to know what a `担当者変更` (assignee change) or `優先度変更` (priority change) actually was, fetch the details after the notification.
Even if the subject, the changer's name, or a status name contains line breaks or tabs, the finished notification string is normalized to one line.

```powershell
redmine issues show <number> --include journals --json
```

Delegate running this command to a read-only subagent on an inexpensive model, following the `redmine-cli` skill's policy.
Do not leave the raw JSON in this session's context.
**The main job of a monitoring session is to wait and issue notifications, so keeping each notification lightweight is what gives it value.**

## 3. Stopping and restarting

**The script's process remains even after the session or Claude Code ends.**
Only the harness-side Monitor task disappears, and the process keeps polling.
`TaskStop` is the same: it only stops the harness record and does not guarantee that the process ends.

To restart monitoring, run the same setup procedure again. When the script starts, it writes its token to `$HOME/.claude/.redmine-watch/owner-token` and claims ownership. The previous process retires as soon as it next checks ownership, so the most recently started process wins. The invoking session does not need to find or kill older processes.

To make sure every process stops, write a value that does not belong to any process into this file.

```bash
echo stop > ~/.claude/.redmine-watch/owner-token
```

### Working on the watch list

**Stop the process before touching the file.** If you delete `watched-issues.tsv` while the process is running, the next poll sends a `Redmine担当追加` (assignment added) notification for **every ticket** you are currently assigned to. Each notification is one line, so the more tickets you are assigned, the more credits are burned. The no-notification behavior of a first startup applies only when the process starts while the state file does not exist.

Procedure to wipe the list and set up monitoring again:

```bash
echo stop > ~/.claude/.redmine-watch/owner-token
rm ~/.claude/.redmine-watch/watched-issues.tsv
```

If you set up monitoring again after this, it counts as a first startup, and the tickets you are currently assigned to are re-registered without notification.

To remove only a specific ticket from monitoring, stop the process and then delete its line.
However, as long as you are still its assignee, it is added again in the discovery pass of the next poll, and at that time
a `Redmine担当追加` (assignment added) notification is issued once.

## 4. State directory

Four files are kept in `$HOME/.claude/.redmine-watch/`. All are machine-specific and are not tracked in dotfiles.

| File | Role | If deleted |
|---|---|---|
| `watched-issues.tsv` | The watch list itself | The memory of tickets you were assigned to in the past is lost |
| `status-reference.json` | Cache of the status list | Monitoring stops until the next successful retrieval. A save failure issues one warning line and monitoring continues |
| `self-user-id` | Your user ID | While it cannot be restored (for example when zero tickets are assigned to you), your own changes may also be notified |
| `owner-token` | Ownership of the running process | All processes retire |

## 5. What not to do

- **Writing to Redmine.** The CLI is read-only and can neither post comments nor change statuses.
  If a change is needed, a person makes it in Redmine.
- **Automatically investigating a ticket when a notification arrives.** The cost jumps as the number of monitored tickets grows.
  The user chooses which tickets to actually read.
- **Including the API key in prompts, logs, or the final answer.** Keep the connection settings entirely within the CLI's local settings
  file and environment variables.
