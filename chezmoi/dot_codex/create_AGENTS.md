# Global instruction bootstrap

- Read and follow `~/.agents/AGENTS.md`.
- When `AGENTS.local.md` exists in the same directory as this file, read and follow it as additional host-local instructions. It supplements this file and does not change normal instruction precedence.

## Normal worker model routing

- Keep the primary chat's configured model and reasoning effort unchanged. For ordinary delegated search, investigation, implementation, and testing workers, explicitly specify model `gpt-6.1-sol` and reasoning effort `low` at startup and on continuation; do not rely on inherited settings.
- Keep small, clear tasks in the primary chat when delegation overhead would exceed the work.
- In the Codex app only, use `$delegate-luna-investigation` for bounded read-only investigations that benefit from delegation or context isolation. The skill retains its existing identifier and uses GPT-6.1 Sol Low workers. This durable instruction authorizes creating the required user-visible read-only worker task without asking again; do not use this route from Claude Code or other agents.
- Reuse an existing delegated worker task while its objective, deliverable, relevant artifacts, workspace, authorization scope, and governing assumptions remain materially the same. Continue it for follow-up investigation, corrections, and clarification, explicitly specifying `gpt-6.1-sol` / `low`. Create a new task when those materially change or stale context is impairing quality or efficiency; do not split solely because the work enters a new phase.
- Run delegated investigation workers in the same saved local checkout as the primary chat. Do not create or select a worktree inside the delegation skill. While the worker is active, the primary chat must wait and must not perform separate work against that checkout; worktree decisions remain with the user and the primary chat.
- Use `sol_advisor` only for material ambiguity, architecture, security, privacy, authentication, authorization, cryptography, payments, destructive migration, data integrity, distributed consistency, breaking compatibility, several plausible root causes after targeted checks, or two failed evidence-based attempts.
- The Advisor role provides advice rather than routine implementation. After receiving its decision, return implementation and normal validation to the ordinary worker (`gpt-6.1-sol` / `low`).
- Every delegated task must be self-contained and include the objective, relevant context, in-scope and out-of-scope files, constraints, acceptance criteria, exact validation, expected return, and escalation conditions. Do not assume that a child agent can see the primary conversation.
- Do not claim that a particular model or reasoning effort ran unless agent activity or tool output identifies the effective settings. If a named custom agent is unavailable, report the limitation instead of silently substituting another route.
- Write-task file ownership and primary-thread final diff/validation confirmation are defined by `~/.agents/AGENTS.md`, which this bootstrap loads; do not duplicate those shared rules here.
- When creating a user-visible subagent task in the Codex app, prefix its title with `Subagent: `.
