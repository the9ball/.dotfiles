---
name: task-continuity
description: Maintain an evidence-checked external Markdown state record for long-running tasks. Use automatically when work is likely to span many turns or context compaction, includes multi-phase investigation and implementation, expands in scope, coordinates subagents, crosses sessions, or when a task-continuity hook requests evaluation or recovery. Once activated and approved, continuously maintain the memo until the task is closed. Do not use for short Q&A, isolated edits, or brief reviews.
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
- The task coordinates subagents, sessions, or separate workstreams.

Soft triggers:

- The task spans research, design, implementation, and verification phases.
- The task uses several files, systems, or external sources.
- Important decisions, constraints, or hypotheses are accumulating.
- The scope expands beyond the initial request.
- Tool output or elapsed work is becoming difficult to reconstruct reliably.

Do not activate for short questions, one small edit, or a brief review.

## Obtain one scoped approval

Before creating runtime state, tell the user why continuity protection is
appropriate and propose a memo path.

Use `<git-root>/.task-continuity/<session-id>.md` by default. If no Git root
exists, use `<cwd>/.task-continuity/<session-id>.md`. Explicitly offer the user
the option to choose another path.

When proposing a new `.task-continuity` directory, also offer to create a
`.gitignore` whose complete contents are `*` so the directory remains local.
Do not create it when the user chooses another location unless requested.

Ask for one approval covering:

- Creating the selected memo.
- Continuously updating it until this task is closed.
- Registering the selected path for the current session when hook integration
  is installed.
- Allowing mechanical, unverified `PreCompact` and `PostCompact` append-only
  records.

Do not write before approval. After approval, treat these exact runtime-state
writes as approved for the rest of the task. Obtain new approval if the path or
scope changes.

## Create and activate the memo

1. Copy `assets/task-memory-template.md` to the approved path.
2. Replace every placeholder and record the approval scope.
3. If approved, create `.gitignore` with exactly `*` in the newly created
   default directory.
4. Follow the activation interface supplied by installed task-continuity hook
   context to associate the session ID with the approved memo path.

Installed hook context should provide the current session ID, proposed default
path, active memo path when one exists, and environment-specific activation and
close instructions at session start. Routine prompt context may be abbreviated
to a risk or maintenance reminder to reduce repeated input overhead. If the
full session-start context does not exist, create and maintain the memo without
hook recovery and tell the user that compact automation is unavailable until
`INSTALL.md` is completed.

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
