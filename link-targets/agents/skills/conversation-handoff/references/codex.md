# Codex adapter

Use this adapter only when the current host is Codex.

## Create the destination

- Discover the currently callable Codex task-management capabilities before choosing a fallback.
- Use the capability whose base name is `create_thread` (for example, `codex_app__create_thread`) to create a fresh, user-visible task when it is available.
- Satisfy any prerequisite required by that capability, such as listing projects before creating a project-scoped task.
- Keep the destination in the same project and usable source workspace. Do not create a new branch or worktree solely for the handoff.
- Put the complete handoff in the initial prompt and request the understanding-only first response defined by the main skill.
- When the current host exposes the source task's stable `threadId` and `hostId`, or the user supplies those identifiers explicitly, include them in the optional source-task reference block. If the source `threadId` is unavailable, omit the block rather than matching a task by title or guessing an identifier.
- Give the destination a concise continuation title when title management is available.

## Use the source reference safely

- The destination may use `read_thread` with the supplied `threadId` and `hostId` only after its required first response has been confirmed and only when the handoff and current workspace cannot resolve a material ambiguity.
- Default to `includeOutputs: false` with a narrow `turnLimit` and `maxOutputCharsPerItem`; request tool or command outputs only when the current question specifically requires them.
- A `clientThreadId` returned while a worktree is being prepared is not a usable source identifier. Never put it in the source-task reference or pass it to `read_thread`.
- Treat source content as read-only evidence. Re-check material claims against the current workspace and do not inherit the source task's approvals, permissions, plans, TODOs, or pending external actions.
- Do not call `send_message_to_thread` automatically. An interactive question to the source is a separate, user-authorized action that could resume or mutate the source task.
- If the source task is active, archived, deleted, or inaccessible, report the limitation when it matters and continue without guessing.

## Avoid incorrect substitutes

- Do not use a capability whose base name is `handoff_thread`; it moves an existing task or environment and does not create the clean destination required by this workflow.
- Do not use `fork_thread`, `/fork`, or another transcript-preserving fork because it carries the bloated history into the destination.
- Do not create a subagent or background task as a substitute for a user-owned task that appears in the Codex task list.

## Verify and report

- Verify that task creation and inline handoff delivery succeeded.
- Emit any host-required created-task directive only after successful creation.
- If `create_thread` is unavailable or fails, return to the manual fallback in `SKILL.md`.
- Never claim that a task was created without a successful tool result.
