# Global instruction bootstrap

- Read and follow `~/.agents/AGENTS.md`.
- When `AGENTS.local.md` exists in the same directory as this file, read and follow it as additional host-local instructions. It supplements this file and does not change normal instruction precedence.

## Luna-first agent routing

- Use GPT-6 Luna Max as the primary model for normal conversation, search, investigation, implementation, testing, and task orchestration.
- Keep small, clear tasks in the primary Luna thread when delegation overhead would exceed the work.
- In the Codex app only, use `$delegate-luna-investigation` for bounded read-only investigations that benefit from delegation or context isolation. This durable instruction authorizes creating the required user-visible Luna Max task without asking again; do not use this route from Claude Code or other agents.
- Reuse an existing delegated Luna task while its objective, deliverable, relevant artifacts, workspace, authorization scope, and governing assumptions remain materially the same. Continue it for follow-up investigation, corrections, and clarification. Create a new task when those materially change or stale context is impairing quality or efficiency; do not split solely because the work enters a new phase.
- Run delegated Luna tasks in the same saved local checkout as the primary Sol task. Do not create or select a worktree inside the delegation skill. While Luna is active, Sol must wait and must not perform separate work against that checkout; worktree decisions remain with the user and the primary Sol task.
- Use `sol_advisor` only for material ambiguity, architecture, security, privacy, authentication, authorization, cryptography, payments, destructive migration, data integrity, distributed consistency, breaking compatibility, several plausible root causes after targeted checks, or two failed evidence-based attempts.
- Sol is an advisor, not the routine implementer. After receiving its decision, return implementation and normal validation to Luna.
- Every delegated task must be self-contained and include the objective, relevant context, in-scope and out-of-scope files, constraints, acceptance criteria, exact validation, expected return, and escalation conditions. Do not assume that a child agent can see the primary conversation.
- Do not claim that Luna, Sol, or another model ran unless agent activity or tool output identifies the effective model. If a named custom agent is unavailable, report the limitation instead of silently substituting another route.
- Write-task file ownership and primary-thread final diff/validation confirmation are defined by `~/.agents/AGENTS.md`, which this bootstrap loads; do not duplicate those shared rules here.
- When creating a user-visible subagent task in the Codex app, prefix its title with `Subagent: `.
