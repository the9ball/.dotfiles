---
name: task-continuity
description: Maintain an evidence-checked external Markdown state record for long-running tasks. Use automatically when work is likely to span many turns or context compaction, includes multi-phase investigation and implementation, expands in scope, coordinates multiple subagents or persistent workstreams across turns, crosses sessions, or when a task-continuity hook requests evaluation or recovery. After approval, bind the memo to the current host session and maintain it while the task is underway. Task completion does not require lifecycle status or a close operation. Do not use for short Q&A, isolated edits, or brief reviews.
---

# Task Continuity

Use a disposable Markdown memo as external working state. Treat it as easier to
recover than conversation memory, but less authoritative than current primary
evidence.

## Evaluate continuity risk

Use this workflow when at least one hard trigger or two soft triggers
apply.

Hard triggers:

- The user requests long-running work, handoff, persistent notes, or recovery.
- The task resumes after compaction or a context-loss incident.
- The task coordinates multiple subagents, sessions, or separate workstreams
  whose state must be integrated or preserved across turns.

Soft triggers:

- The task spans research, design, implementation, and verification phases.
- The task uses several files, systems, or external sources.
- Important decisions, constraints, or hypotheses are accumulating.
- The scope expands beyond the initial request.
- Tool output or elapsed work is becoming difficult to reconstruct reliably.

Do not use this workflow for short questions, one small edit, or a brief review.
A single bounded, read-only subagent or Advisor consultation that is expected
to return one result without persistent follow-up state is not a hard trigger
by itself.

## Resolve write approval

Before creating runtime state, tell the user why continuity protection is
appropriate and propose a memo path.

Use `<git-root>/.task-continuity/<session-id>.md` by default. If no Git root
exists, use `<cwd>/.task-continuity/<session-id>.md`. Explicitly offer the user
the option to choose another path.
When a validated standing marker already covers the proposed path, this notice
and path offer are informational; do not wait solely for the user to repeat
write approval.

When proposing a new `.task-continuity` directory, also offer to create a
`.gitignore` whose complete contents are `*` so the directory remains local.
Do not create it when the user chooses another location unless requested.

For this skill, a covered runtime write is creating or updating a
task-continuity memo whose immediate parent is the exact validated approved
directory, including approved compact-boundary appends. It does not include
nested-directory writes, moves, deletion, changes to `.allow-write`,
`.gitignore`, skills, hook or installation files, other project files, or
writes outside that exact directory.

A validated standing marker is durable evidence that the user previously gave
explicit change-scope approval for covered runtime writes. It does not waive
the approval requirement; it records that the requirement has already been
satisfied for that exact scope. For covered runtime writes, do not ask the user
to repeat that approval. It does not grant or suppress host sandbox, operating
system, or tool permission prompts.

`TASK_CONTINUITY_*` names are labels inside model-visible hook context, not
process environment variables.

Resolve write approval separately from memo binding and boundary recovery:

- `valid`: Hook context supplies `TASK_CONTINUITY_BOUND_MEMO_PATH` with a
  validated binding, or supplies only the legacy path alias together with a
  validated binding record for the same host, session, and exact path. The
  proposed operation must be an approved write to that bound memo. A nonempty
  `TASK_CONTINUITY_WRITE_PREAPPROVED` directory also covers writes within that
  exact approved directory. Reuse the recorded approval without asking again.
- During mixed-version rollout, accept
  `TASK_CONTINUITY_ACTIVE_MEMO_PATH` only as a legacy alias when the bound-path
  label is absent. Normalize both absolute paths before comparison; if both
  labels are present and differ, fail closed. The legacy label is only a path
  alias and does not establish activity, approval, or lifecycle state.
- `valid-fallback`: The preapproval label or hook context is absent or empty,
  but a read-only fallback validates the standing marker and the proposed
  runtime write is covered. Reuse the recorded approval without asking again.
- `invalid`: The marker exists but fails any required validation. Do not reuse
  it or repair it without approval.
- `unavailable`: The marker is absent, cannot be read, or cannot be fully
  validated. Do not infer approval.
- `scope-out`: The marker is valid, but the proposed path or operation is not a
  covered runtime write. Obtain approval for the new scope.

For the fallback, resolve the default `.task-continuity` directory from the
current Git root or working directory, then validate `.allow-write` using every
rule in `references/hook-contract.md`: regular non-symbolic file, exact
normalized parent path, exact required schema/scope/source/ownership values,
presence of an approval timestamp, and untracked plus Git-ignored when inside
Git. Mere directory, memo, or unvalidated marker existence is never approval.
The approval timestamp is metadata and its age alone does not invalidate a
marker.

An absent or empty preapproval label is not by itself evidence that the user
denied approval. Complete the read-only fallback before asking. Ask for write
approval only for `invalid`, `unavailable`, or `scope-out`, and only when the
continuity-risk evaluation otherwise warrants creating a memo.

If the host session ID is unavailable, do not guess it. This does not invalidate
standing approval for covered runtime writes; it only prevents session-bound
memo binding and automatic registry recovery. A custom memo directly inside the
approved directory remains covered, but must be maintained without hook
recovery until the adapter exposes the ID. Clearly distinguish any path-choice
question from a write-approval request.

When the decision state is `invalid` or `unavailable`, or is `scope-out` solely
because a different memo directory was selected, ask for one approval covering:

- Creating the selected memo.
- Continuously maintaining it while the task is underway.
- Binding the selected path to the current host session when hook integration
  is installed.
- Allowing mechanical, unverified `PreCompact` and `PostCompact` append-only
  records.
- Creating a local `.allow-write` marker for future task-continuity sessions in
  the exact selected memo directory.

Task-scoped approval and its recorded binding cover writes to that exact host,
session, and memo path. Do not extend the approval to another path, session, or
operation. If a different path is requested while a binding exists, preserve
the existing binding and fail closed for the conflicting path. This contract
defines no binding-removal or path-replacement operation.

For any other `scope-out` operation, obtain approval that explicitly names the
proposed path and operation. Do not treat the memo-approval bundle above
as authorization for nested-directory writes, moves, deletion, or changes to
other files.

Allow the user to decline the standing portion while approving only the current
task. Do not write before either current-task or standing approval exists.
Obtain new approval for deletion, moving files, writing outside the approved
directory, or expanding the approved operations.

## Memo binding and boundary revalidation

The session registry binds one host/session lineage to one exact approved memo
path. It is an authorization record for covered writes, not task-lifecycle
state. At fork, resume, compact, and recovery boundaries, revalidate the same
task and session-or-fork lineage, target epoch, exact approved memo path,
binding ownership, and approval evidence before accepting or repairing state.
Do not repeat this identity check for every ordinary memo write; continuous
maintenance follows the already validated binding and its scope.

New binding records explicitly identify `approval_scope` as `standing-marker`
or `task-scoped`. A standing binding records its exact approved directory; a
task-scoped binding records the user's explicit approval for its exact path and
omits that directory. Accept legacy records only in the complete shapes defined
in `references/hook-contract.md`; unknown writer provenance or partial or
conflicting approval fields fail closed. Do not infer task-scoped approval from
the absence of a standing marker.

New bindings and memos must omit lifecycle `status`. Existing `active`,
`closed`, unknown, or absent status fields are legacy metadata. They must not
authorize or block a write, change binding validity, or control recovery. Memo
existence alone does not create a binding. A boundary failure is fail-closed
unless the exact existing binding can be validated and the recovery conditions
below are met.

## Create and bind the memo

1. Copy `assets/task-memory-template.md` to the approved path.
2. Replace every placeholder and record the approval scope.
3. If approved, create `.gitignore` with exactly `*` in the newly created
   default directory.
4. After new standing approval, follow the hook's directory-grant instruction
   to create `.allow-write` before binding. Do not create the marker
   manually, and do not run the instruction for task-scoped-only approval.
5. For the validated standing-approval default path, let the next host event
   validate the memo metadata and record its binding automatically when no
   binding exists. For a custom path or task-scoped-only approval, follow the
   binding interface supplied by installed hook context. An existing binding
   to a different path remains unchanged and causes the conflicting path to
   fail closed.

Installed hook context should provide the current session ID, proposed default
path, bound memo path when one exists, and an environment-specific bind
instruction at session start. It must not provide a task-continuity close
instruction. Routine prompt context may be abbreviated to a risk or
maintenance reminder. If the full session-start context does not exist but a
valid standing marker and session ID are available, create the default memo
and let `UserPromptSubmit` or `PreCompact` recover its binding when no binding
exists. Otherwise create and maintain the memo without hook recovery and tell
the user that compact automation is unavailable until the adapter is repaired.

After binding, the hook may omit the standing-approval notification because
the validated session binding preserves the exact approved path and approval
evidence. A task-scoped-only approval does not require a standing marker during
recovery when the binding records that explicit approval for the same exact
host, session, and path.

After binding, follow the host adapter's reminder policy. A long-interval
periodic reminder is the normal balance; boundary-only and strict per-turn
reminders are host-local alternatives. Prompt counters are operational state,
not memo content.

## Maintain the memo continuously

While the task is underway, keep the memo synchronized with current primary
evidence. Updating the memo is part of completing each state-changing step,
not an optional later checkpoint. Continue to use the validated binding only
for its exact host, session, memo path, and approved operations. If a requested
path conflicts with that binding, fail closed and do not repoint it. Do not
extend approval to another path, session, or operation.

Update it after:

- The user changes goals, constraints, priority, or approval.
- A fact is verified, invalidated, or becomes stale.
- A hypothesis is accepted or rejected.
- A decision, implementation change, or external mutation occurs.
- The task changes phase.
- A subagent is dispatched or returns material results.
- A context-heavy operation is about to begin.
- Before yielding each assistant turn.

Skip writes only when no recorded state changed. Keep the current-state
sections concise and move history into the append-only log.

The main agent owns the memo. Subagents report findings to the main agent
instead of editing it concurrently unless explicit ownership is assigned.

## Preserve verification integrity

Label material statements as `verified`, `inferred`, or `pending`. For verified
facts, include the primary evidence location and verification time.

Resolve conflicts in this order:

1. Latest explicit user instruction.
2. Current repository, file, command, or external-system state.
3. Verified memo entry with evidence.
4. Inference in the memo.
5. Recalled conversation context.

When the memo conflicts with primary evidence, re-check the evidence and then
correct or discard the memo entry. Never force current evidence to match the
memo.

## Recover after compaction or resume

When hook context points to a bound memo that no longer exists, treat the
memo as discarded volatile state rather than a fatal error. At the next
fork/resume/compact/recovery boundary, revalidate the same task and
session-or-fork lineage, target epoch, exact bound path, binding ownership, and
approval evidence. A task-scoped-only binding uses its recorded explicit
approval for that exact path; it does not require a standing marker. A
standing-approved binding requires revalidation of the exact `.allow-write`
marker. Before recovery writes, validate the exact parent directory using
no-follow metadata checks and reject symbolic links, junctions, and reparse
points. If these checks pass and the current boundary can establish task and
target-epoch identity, notify the user and recreate a fresh memo from the
template at the exact bound path. Verify the recreated target is a regular
non-link file before appending. Do not copy transcript contents, infer
discarded sections, or repoint the binding. Record that reconciliation is
required in the new memo.

A binding proves host/session lineage, path, and recorded approval; it does not
by itself prove the current task meaning or target epoch. If the hook cannot
establish that identity, it must not recreate the memo or append a compact
record. It must provide recovery context for the model to validate identity
from the current conversation and primary evidence. `PreCompact` and
`PostCompact` skip appending until recovery is complete. One host/session
lineage has one bound memo path. If a different path is requested, preserve the
existing binding, fail closed for the conflicting path, and provide recovery
context. This contract defines no binding-removal or path-replacement
operation. Never move or repoint the binding.

When hook context reports a bound memo after `PostCompact`,
`SessionStart(compact)`, fork, resume, or another recovery boundary:

1. Read the complete memo before continuing.
2. Revalidate the same task and session-or-fork lineage, target epoch, exact
   memo path, binding ownership, and approval metadata. Ignore legacy lifecycle
   status fields.
3. Inspect current files, Git state, commands, and relevant external state.
4. Correct stale or inconsistent memo entries.
5. Append a reconciliation result for each unresolved emergency record.
6. Resume normal work and continuous maintenance.

Mechanical compact records are unverified. They may contain stale summaries or
pointers and must not override primary evidence.

The compact-time hook is deliberately minimal: it only appends the current
state after revalidating the bound memo path and no-follow file/parent metadata
as specified in `references/hook-contract.md`. It never deduplicates,
reorganizes, or rewrites. Duplicate or overlapping emergency records are
expected and acceptable. Consolidating, deduplicating, and rewriting them into
clean current-state entries is the job of this reconciliation step, not of the
compact-time hook.

## Finish task work

Record the outcome, verification, and remaining risks in the memo before
finishing the task. Do not add or change lifecycle status, issue a close
command, or let completion metadata control the session-to-memo binding. The
memo remains a disposable working-state artifact; its later cleanup still
requires the separate preview and deletion approval defined by
`task-continuity-cleanup`.
