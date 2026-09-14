---
name: delegate-luna-investigation
description: "【Codex app専用。Claude Codeや他のエージェントからは使用しない】 Coordinate bounded read-only investigations in reusable, user-visible GPT-5.6 Luna Max tasks from a primary Codex task. Use when delegation protects the primary context, enables useful parallel research, or continues an earlier Luna investigation through follow-up questions or corrections. Do not use for write work or small tasks whose delegation overhead exceeds the work."
---

# Delegate Luna Investigation

> Codex app only. Never use this skill from Claude Code or another agent product. If the Codex task creation, listing, messaging, reading, or waiting capabilities are unavailable, report the limitation and stop. Do not substitute a different model or execution route silently.

Coordinate an investigation from the primary Codex task. Keep the delegated task read-only, preserve its context across follow-ups, and return evidence to the primary task for verification and final judgment.

## Guardrails

- Create a user-visible task only when the user explicitly authorizes it in the current request or through durable instructions such as `AGENTS.md`.
- Delegate only bounded read-only search, documentation checks, codebase exploration, and evidence gathering.
- Keep small, clear work in the primary task when delegation overhead exceeds the work.
- Do not delegate file edits, external writes, destructive actions, approvals, purchases, or material scope expansion.
- Instruct the Luna task not to create subagents or additional tasks and not to modify files or external state.
- Use the same saved local checkout as the primary Sol task. Never create, select, move, or remove a worktree from this skill.
- Run sequentially: while the Luna task is active, make the primary Sol task wait and do not perform separate work against the shared checkout.
- Leave any worktree decision to the user and the primary Sol task. If they select another checkout, use that existing selection without changing it.
- Keep integration, evidence verification, decisions, and the final response in the primary task.
- Do not claim Luna ran unless task activity identifies the effective model or the task was created explicitly with `gpt-5.6-luna`.

## Decide Whether to Reuse

Treat these fields as the delegated workstream identity:

- objective and expected deliverable;
- relevant artifacts and investigation scope;
- project, selected checkout, and branch;
- authorization and read-only boundary;
- governing assumptions.

Reuse the same Luna task when those fields remain materially the same. Continue it for follow-up research, corrections, clarification, stronger evidence, and validation of the same conclusion.

Create a new Luna task when any identity field changes materially, prior assumptions become obsolete, or stale context is visibly impairing quality or efficiency. Do not split solely because work enters a new phase. Prefer a concise handoff of confirmed facts and open questions over copying the full transcript.

Use observed degradation rather than turn count alone. Examples include repeatedly relying on superseded assumptions, confusing distinct artifacts, or requiring the core constraints to be restated.

## Find an Existing Delegated Task

1. Prefer a previously retained `threadId` and `hostId` from the current primary task.
2. If those identifiers are unavailable, list recent tasks and look for the title prefix `[Luna調査]`.
3. Read each plausible candidate and verify its initial delegation marker and workstream identity.
4. Never reuse a task based on title alone, and never reuse an unrelated user-created task.

## Create the Luna Task

1. List available projects and select the project matching the primary task.
2. Use that project's saved local environment so Luna reads the same checkout as Sol. Do not request a new worktree.
3. Create a task with model `gpt-5.6-luna`, reasoning effort `max`, and title `[Luna調査] <short workstream>`.
4. If creation still returns only a `clientThreadId`, do not pass it to tools requiring a `threadId`. Resolve the ready task through the recent-task list and verify its delegation marker before continuing.
5. Retain the ready task's `threadId` and `hostId` for follow-ups.

Make the initial prompt self-contained and include:

- marker: `Delegated role: Luna read-only investigator`;
- objective and relevant context;
- in-scope and out-of-scope artifacts;
- constraints and authorization boundary;
- acceptance criteria and exact validation;
- expected return format;
- escalation conditions;
- an explicit ban on edits, external state changes, and further delegation.

Require concise findings that distinguish verified facts from inference and include exact file references or source links, relevant commands or queries, uncertainty, and the cheapest next check when evidence is incomplete.

## Continue and Collect Results

1. Wait for the delegated task rather than repeatedly polling it or doing other work against the shared checkout.
2. Read its final result and inspect the cited evidence from the primary task when practical.
3. If evidence is incomplete or a correction is needed, send a follow-up to the same task. Omit model and reasoning overrides so its Luna Max settings and conversation context remain intact.
4. State only the delta, new evidence, challenged conclusion, and required output in the follow-up.
5. Wait again and repeat while the workstream identity remains stable.
6. If the delegated task requests user approval or expanded authority, leave that decision to the user; do not answer on the user's behalf.

Keep an active delegated task unarchived while meaningful follow-up is likely. Archive it only when the user asks or another explicit lifecycle policy authorizes archival.

## Handle Failure

If Luna task creation or continuation fails, report the exact error and the affected step. Do not silently fall back to Sol, Terra, a subagent, or local execution. Offer the smallest viable next action to the user.
