# Claude Code adapter

Use this adapter only when the current host is Claude Code.

## Create the destination when supported

- Discover whether the current Claude Code host exposes a capability that can create an independent, user-visible session and place an initial prompt in it.
- Use such a capability only when its result is visible to the user as a separate resumable session and the user's request authorizes creation.
- Put the complete handoff in the initial prompt and request the understanding-only first response defined by the main skill.
- Keep the destination in the same project and usable source workspace when the host supports it.

## Avoid incorrect substitutes

- Do not treat a subagent, agent team member, forked execution context, background worker, or isolated skill context as a new user-visible session.
- Do not clear, compact, or replace the source session.
- Do not attempt to invoke an interactive slash command through the shell or claim that the user ran one.

## Verify or fall back

- Verify destination creation and inline handoff delivery before reporting success.
- If no suitable session-creation capability exists or creation fails, return to the manual fallback in `SKILL.md`.
- In the fallback, tell the user to start a fresh Claude Code session and paste the returned handoff.
- Never claim that a session was created without a successful host result.
