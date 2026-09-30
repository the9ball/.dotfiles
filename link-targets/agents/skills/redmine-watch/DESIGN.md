# Design memo

Why the files that make up `redmine-watch` are placed where they are, and why they are built this way.
Read this when editing this skill, especially when you are about to change the placement or the difference-detection method.
Separately from `SKILL.md` (the runtime procedure), this file keeps only the reasons for the decisions.

This skill is the counterpart of `review-watch`, and it uses the same ownership token to prevent double startup.
However, **the way of waiting during a handover cannot be made the same** (see below). When you fix one, look at the other too.

## Invariants

**Writing to standard output and updating the state file cannot be made one transaction.**
Therefore "zero duplicates and zero misses" cannot be guaranteed in principle. This monitor chooses to
**avoid misses and limit duplicates**. Do not break this order in later changes either.

1. Advance the journal position only **after** the notification has been issued. The reverse order causes misses.
2. State is fixed per ticket, by writing to a temporary file and replacing with `mv`.
3. When the material for judging finished status, first discovery, or retrieval and parsing is missing, neither the notification nor
   the advancing of the journal position is fixed for that target.
4. As soon as it is found that ownership has been lost, retire without writing state.

Number 4 is especially important: if a retiring process writes state, the new owner
skips that change as "already known", and **the notification vanishes without reaching anyone.**

## File placement

| Target | Location | Tracking |
|---|---|---|
| Skill body | `link-targets/agents/skills/redmine-watch/` | Tracked by git |
| Watch list | `$HOME/.claude/.redmine-watch/watched-issues.tsv` | Outside dotfiles |
| Status list cache | `$HOME/.claude/.redmine-watch/status-reference.json` | Outside dotfiles |
| Your own user ID | `$HOME/.claude/.redmine-watch/self-user-id` | Outside dotfiles |
| Ownership token of the monitoring process | `$HOME/.claude/.redmine-watch/owner-token` | Outside dotfiles |

### Skill body

Tracked in dotfiles. The same files are used across hosts.

`watch-assigned-issues.sh` is split out into a separate file for the same reason as in `review-watch`:
a command written out inline for `Monitor` is rejected by the permission classifier.

### `watched-issues.tsv` — the watch list

A TSV of `issueId <TAB> lastJournalId`. It is **the core of this skill**, and unlike the other state files,
if it is lost the monitoring loses its very meaning (the memory of tickets you were assigned to in the past exists only here).

It is placed under `$HOME/.claude/` and kept separate per host. The reason it is not shared through dotfiles is
the same as for `seen-pull-requests.tsv` in `review-watch`: it is read and written on every poll, so
touching it from multiple hosts or agents causes conflicts.

**The existence of the file means only that "a fixed snapshot exists".**
The first-startup decision is made from this existence alone, **not from the number of lines.** An empty file
can mean both "not initialized" and "initialized but zero monitored tickets", so judging by line count
would treat the correct empty state after all tickets have finished as a first run, and would swallow the notification for a ticket
newly assigned afterward (because a first run is silent). To keep this meaning, **do not `touch` it at startup.**

Only the first startup fixes the state in one go. It issues no notification, so there is no atomicity problem,
and if it stops midway no file is created, so the next run can start over from the beginning.

A newly discovered ticket is not written to the watch list until it is fixed. Fixing it after a failed retrieval
would make it "known" without ever having told you that you became its assignee.
The initial value at fixing time is the current maximum journal ID. With `0`, all comments that existed before it was added to monitoring
would be notified as "new".

In a loop where the first discovery is incomplete, the initial snapshot is not fixed and is carried over to
the next loop. If it is incomplete three times in a row, one warning line is issued, and once discovery is complete again the recovery is
reported once. From the second run on, a new ticket that could not be discovered can simply be picked up in the next loop,
so retrieval and fixing of the tickets already monitored continue. `totalCount=0` with `issues=[]` is a complete discovery.

A ticket for which `issues show` failed is not fixed and is carried over to the next poll.
If it were dropped, a monitored ticket would silently disappear because of a communication error.
The same treatment applies when jq fails. If the journal position were advanced without distinguishing it from "no change",
a change that should have been detected in that round would be lost forever.

### `status-reference.json` — cache of the status list

It is used for the finished-status decision (`isClosed`) and for resolving status names. **If a loop that cannot get it
notified "without knowing whether the ticket is finished", a change on a finished ticket would produce a billable notification.**
One notification = one model turn, so this is not merely the safe side but an increase in cost.

The last successful response is cached as it is, and a loop whose retrieval fails uses it.
If there is no cache either, that loop carries over without notifying or advancing the journal position.
The journal difference can be taken again in the next successful loop, so nothing is missed.

The cache is updated only with a non-empty response that passed syntax validation. This is so that
an empty or broken response does not destroy a good cache.

Even if saving the cache fails, the reference table retrieved in that loop keeps being used in memory.
A save failure issues only one warning line to standard output and is not notified again during the same process. If there is
no cache at the next startup, notifications and advancing of the journal position stop until the reference table can be retrieved again.

As a trade-off, when the cache is old, a finished status newly added on the Redmine side cannot be
recognized. No expiry is set (statuses are rarely added, and the cache is refreshed on the next successful retrieval).

### `self-user-id` — your own user ID

It is needed so that changes you made yourself are not notified. This CLI does not use `/users.json`, which requires administrator rights,
so the ID is taken from `assignedTo.id` of the tickets returned by `issues list --assigned-to me`.
It cannot be obtained while you have no assigned tickets, so it is tried on every loop until it is obtained,
and while it is unknown, everyone's changes are notified (being noisy is safer than being silent).

### `owner-token` — ownership token of the monitoring process

How the token is held and "the process that starts later wins" are the same as in `review-watch`. Read that skill's
`DESIGN.md` for the details. The key points are that processes do not die when a session or Claude Code ends,
and that a leftover orphan writes "already known" into the state file so that the real monitor misses changes.

**What cannot be made the same is how to wait during the handover.** In `review-watch`, one poll finishes with a few `gh` calls,
so if the new process waits a fixed few seconds, the old process has retired. Here, requests are sent sequentially
for as many tickets as are monitored (measured at about 0.4 seconds per ticket, with Windows process startup being heavy),
which a fixed wait cannot cover. So ownership is also checked at the start of each ticket in the retrieval pass and just before fixing,
and if it has been lost, the process retires without writing state.

Each CLI call was given a 15-second timeout in step 2 (D). This limits the exposure to a stuck CLI extending the wait indefinitely,
but the structure of waiting for as many calls as there are monitored tickets remains.

This approach only converts misses into duplicates and does not remove the window.
In measurement as well, for a ticket whose ownership was taken right after a notification was issued, the journal position does not advance
and the new owner notifies the same change again. In light of the invariants above, this is the correct behavior.

## Why a "running marker" approach was not adopted

A graceful handoff, in which the new process requests a takeover and waits until the old process stops its work and removes a running marker,
could reduce duplicates at handover further. It was not adopted.

It can reduce only duplicates, and misses do not occur with either approach (even the ownership check alone converts
misses into duplicates). The marker approach, on the other hand, **brings in two new failure modes**:
the marker is not removed until the old process finishes several calls, so the new process keeps waiting, and
telling a marker left by an abnormal exit apart requires a PID liveness check and expiry handling.
It does not pay off under the policy of "avoid misses and limit duplicates".

If duplicates become a problem in real operation, update this memo and reconsider introducing it.

## Why "previously assigned" is kept locally

The Redmine API has no way to query "tickets I was once assigned to".
`issues list --assigned-to me` returns only the current assignments, and a ticket vanishes the moment you stop being the assignee.

So a ticket detected once while you were assigned is stored locally and followed even after you stop being the assignee.
Two holes remain as a trade-off. Both are accepted under the requirement that a judgment made at the polling stage is good enough.

- A ticket you stopped being assigned to before monitoring began cannot be picked up.
- A ticket you were assigned to for less than the polling interval cannot be picked up.

## Why journal IDs are used for difference detection

Comparing `updatedOn` also tells you that "something changed", but **what changed** is unknown,
and the notification would say only "updated". A journal (the history of comments and attribute changes) contains who made the change and
what changed, so the difference can be built directly by picking up what comes after the journal ID seen last time.

In Redmine an attribute change always creates a journal, so journal IDs alone do not miss anything.
There is no need to hold `updatedOn` as well.

## Why the retrieval pass is one request per ticket

A ticket you are no longer assigned to cannot be picked up by any condition of `issues list`
(`--assigned-to` takes only `me` or a specific user ID, and there is no filter by ticket ID).
Even with `--updated-after` the assignee condition cannot be avoided, so there is no way other than sending
`issues show` one ticket at a time for each ticket on the watch list.

The whole watch list is rewritten at every fixing, so the amount written grows with the square of the number of tickets.
Up to a few dozen tickets this is no problem. If it grows to several hundred, switch to per-ticket files, or
an append-only log with periodic compaction.

## Why notification text resolves only down to the attribute name

The `oldValue` / `newValue` returned in a journal's `details` are raw IDs
(`status_id: "1"→"2"`), which cannot be read as they are. Turning them into names needs a lookup table.

Only status uses a lookup table and is shown like `新規→割振済` (New → Allocated).
Detecting a send-back (差し戻し) is the main purpose of this monitor, and without being able to read that, the notification would be meaningless.

Priority, tracker, assignee, due date, and so on are written only as `優先度変更` (priority changed) and the like.
Name-resolution branches and fetching the reference tables would add about 40 lines to the script, yet they would not help the notification's job
(deciding whether to go and look). The details can be read with `issues show` after the notification.

For the assignee in particular, the policy is not to use `/users.json`, which requires administrator rights,
so a table from user IDs to names cannot be built in the first place.

## Why `isClosed` is used for the finished-status decision

If the decision were made by status name ("終了" (Closed), "却下" (Rejected)), it would silently leak when statuses are added on the Redmine side.
`statuses list --json` returns `isClosed`, so it is used as it is.

As a side effect, in this Redmine the six statuses 保留 (Pending) / 却下 (Rejected) / 本番適用済み (Applied to production) / 組込み済み/完了 (Integrated/Completed) /
リリースなし (No release) / 終了 (Closed) end monitoring. **An existing ticket that
enters 本番適用済み or 組込み済み has the journal included in that transition notified once and then drops off**,
so a send-back (差し戻し) comment added after release cannot be picked up. A ticket that is already finished at the moment it is newly
added to the watch list (`lastJournalId=-1`) cannot be told apart as existing or new, so it is
dropped without notification.
As of 2026-08-21, the choice to exclude everything with `isClosed` was made with this behavior understood.

If a ticket dropped because it finished is reopened and you are still its assignee, the discovery pass adds it again,
so an "assignment added" notification is issued (even though the assignment has not changed). At the same time, the journals from the finished period until the reopening
are swallowed as the initial value. This is accepted as a compromise.

## CR from jq on Windows

jq on Windows opens stdout in text mode, so a CR is appended to the end of each output line.
If this is written to the state file, the ticket ID becomes `30708\r`, the known-ticket check fails at the next poll,
and the same ticket is registered twice (observed). Every jq call whose output is used as a value goes through `jq_strip`.

`jq_strip` drops the CR through a variable rather than a pipe. With a pipe, `$?` would be
`tr`'s, and a jq failure could not be detected. `jq -e`, which looks only at the exit code, is called directly as `jq`, not through `jq_strip`.

## Holes that remain after the fixes

- A TOCTOU in which ownership is taken right after it was checked. The window is a few milliseconds, and it falls on the duplicate side.
- A duplicate when the process stops after issuing a notification and before `mv`. At most one ticket.
- In an environment where the status list can never be retrieved, monitoring keeps stopping without issuing notifications.
  One line is issued after three consecutive failures, and it is not notified again until recovery.
- The journals from the finished period until reopening are swallowed as the baseline when the discovery pass adds the ticket again.
- A ticket that permanently fails to be retrieved or parsed stays on the watch list. This is intended behavior that prioritizes not missing anything;
  if needed, stop the process and delete its line by hand (out of scope this time).
- No upper time limit is set for a whole poll. Each CLI call has a 15-second limit, but
  with 100 tickets it can reach about 1,500 seconds at most. Once the list grows to several hundred, revisit the retrieval interval first.
