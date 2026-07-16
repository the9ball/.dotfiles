# Codex adapter

Use this adapter only when the current host is Codex.

## Create the destination

- Discover the currently callable Codex task-management capabilities before choosing a fallback.
- Use the capability whose base name is `create_thread` (for example, `codex_app__create_thread`) to create a fresh, user-visible task when it is available.
- Satisfy any prerequisite required by that capability, such as listing projects before creating a project-scoped task.
- Keep the destination in the same project and usable source workspace. Do not create a new branch or worktree solely for the handoff.
- Put the complete handoff in the initial prompt and request the understanding-only first response defined by the main skill.
- Give the destination a concise continuation title when title management is available.

## Avoid incorrect substitutes

- Do not use a capability whose base name is `handoff_thread`; it moves an existing task or environment and does not create the clean destination required by this workflow.
- Do not use `fork_thread`, `/fork`, or another transcript-preserving fork because it carries the bloated history into the destination.
- Do not create a subagent or background task as a substitute for a user-owned task that appears in the Codex task list.

## Verify and report

- Verify that task creation and inline handoff delivery succeeded.
- Emit any host-required created-task directive only after successful creation.
- If `create_thread` is unavailable or fails, return to the manual fallback in `SKILL.md`.
- Never claim that a task was created without a successful tool result.
