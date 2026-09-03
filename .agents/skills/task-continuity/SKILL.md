---
name: task-continuity
description: Maintain an evidence-checked external Markdown state record for long-running tasks. Use automatically when work is likely to span many turns or context compaction, includes multi-phase investigation and implementation, expands in scope, coordinates multiple subagents or persistent workstreams across turns, crosses sessions, or when a task-continuity hook requests evaluation or recovery. Once activated and approved, continuously maintain the memo until the task is closed. Do not use for short Q&A, isolated edits, or brief reviews.
---

# Task Continuity

Use a disposable Markdown memo as external working state. Treat it as easier to
recover than conversation memory, but less authoritative than current primary
evidence.

## Evaluate continuity risk

Activate this workflow when at least one hard trigger or two soft triggers
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

Do not activate for short questions, one small edit, or a brief review.
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

Resolve write approval separately from activation and registry recovery:

- `valid`: Hook context supplies `TASK_CONTINUITY_ACTIVE_MEMO_PATH` and the
  proposed operation is an approved maintenance write to exactly that active
  memo, or supplies a nonempty
  `TASK_CONTINUITY_WRITE_PREAPPROVED` directory that exactly covers the
  proposed runtime write. Reuse the recorded approval without asking again.
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
continuity-risk evaluation otherwise warrants activation.

If the host session ID is unavailable, do not guess it. This does not invalidate
standing approval for covered runtime writes; it only prevents session-bound
activation and automatic registry recovery. A custom memo directly inside the
approved directory remains covered, but must be maintained without hook
recovery until the adapter exposes the ID. Clearly distinguish any path-choice
question from a write-approval request.

When the decision state is `invalid` or `unavailable`, or is `scope-out` solely
because a different memo directory was selected, ask for one approval covering:

- Creating the selected memo.
- Continuously updating it until this task is closed.
- Registering the selected path for the current session when hook integration
  is installed.
- Allowing mechanical, unverified `PreCompact` and `PostCompact` append-only
  records.
- Creating a local `.allow-write` marker for future task-continuity sessions in
  the exact selected memo directory.

For any other `scope-out` operation, obtain approval that explicitly names the
proposed path and operation. Do not treat the activation approval bundle above
as authorization for nested-directory writes, moves, deletion, or changes to
other files.

Allow the user to decline the standing portion while approving only the current
task. Do not write before either current-task or standing approval exists.
Obtain new approval for deletion, moving files, writing outside the approved
directory, or expanding the approved operations.

## Create and activate the memo

1. Copy `assets/task-memory-template.md` to the approved path.
2. Replace every placeholder and record the approval scope.
3. If approved, create `.gitignore` with exactly `*` in the newly created
   default directory.
4. After new standing approval, follow the hook's directory-grant instruction
   to create `.allow-write` before activation. Do not create the marker
   manually, and do not run the instruction for task-scoped-only approval.
5. For the validated standing-approval default path, let the next host event
   validate the memo frontmatter and register it automatically. For a custom
   path or task-scoped-only approval, follow the activation interface supplied
   by installed task-continuity hook context.

Installed hook context should provide the current session ID, proposed default
path, active memo path when one exists, and environment-specific activation and
close instructions at session start. Routine prompt context may be abbreviated
to a risk or maintenance reminder to reduce repeated input overhead. If the
full session-start context does not exist but a valid standing marker and
session ID are available, create the default memo and let `UserPromptSubmit` or
`PreCompact` recover registration. Otherwise create and maintain the memo
without hook recovery and tell the user that compact automation is unavailable
until the adapter is repaired.

After activation, the hook may omit the standing-approval notification because
the active session registry entry already identifies the approved memo.

After activation, follow the host adapter's reminder policy. A long-interval
periodic reminder is the normal balance; boundary-only and strict per-turn
reminders are host-local alternatives. Prompt counters are operational state,
not memo content.

## Maintain the memo continuously

Once active, keep the memo synchronized with the task until it is closed.
Updating the memo is part of completing each state-changing step, not an
optional later checkpoint.

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

When hook context points to an active memo that no longer exists, treat the
memo as discarded volatile state rather than a fatal error. Never infer its
missing contents. Revalidate the available conversation and current primary
evidence. If continuity protection is still warranted, follow the normal
approval rules and recreate the memo at the exact path reported by the hook.
That path is already registered as this session's active memo, so do not run
the activation instruction; an existing session entry cannot be repointed and
activation may fail with a conflict. If the user selects a different path,
maintain it without hook recovery and state that compact automation is
unavailable for this session.

When hook context reports an active memo after `PostCompact`,
`SessionStart(compact)`, or resume:

1. Read the complete memo before continuing.
2. Inspect current files, Git state, and relevant external systems.
3. Revalidate entries that are material to the next action.
4. Correct stale or inconsistent current-state entries.
5. Append a reconciliation result for each unresolved emergency record.
6. Resume normal work and continuous maintenance.

Mechanical compact records are unverified. They may contain stale summaries or
pointers and must not override primary evidence.

The compact-time hook is deliberately minimal: it only appends the current
state and never deduplicates, reorganizes, or rewrites. Duplicate or
overlapping emergency records are expected and acceptable. Consolidating,
deduplicating, and rewriting them into clean current-state entries is the job
of this reconciliation step, not of the compact-time hook.

## Close the memo

Before completing the task:

1. Update the final outcome, verification, and remaining risks.
2. Set frontmatter `status` to `closed`.
3. Append a closing log entry.
4. Follow the environment-specific close instruction supplied by installed
   hook context.

Do not delete the memo unless the user asks. Closed memos are disposable
artifacts and may be removed after any needed revalidation.
