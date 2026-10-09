<!-- Shared cross-tool instructions live in ~/.agents/AGENTS.md (single source, also read by Codex). -->
@~/.agents/AGENTS.md

<!-- Host-local Claude Code instructions. -->
@~/.agents/AGENTS.local.md

Claude Code hosts may expose shared Skills through explicit slash invocation
without automatically discovering every Skill from natural-language requests.
Until Issue #75 is completed, use this host-wide fallback for a matching
request family. Resolve the shared `~/.agents` link first, read the listed
shim, then immediately read the exposed Skill `SKILL.md`; the Skill remains
the only normative runtime source. Do not load a shim for an unrelated
request. If either path cannot be resolved, stop and report instead of
substituting another contract.

| Request family | Compatibility shim (canonical source) |
| --- | --- |
| Copyable code or text for another agent | `~/.agents/guides/agent-output.md` (`link-targets/agents/guides/agent-output.md`) |
| Explicit permission or judgment discovery | `~/.agents/guides/approval-request-workflow.md` (`link-targets/agents/guides/approval-request-workflow.md`) |
| Creating or editing a Git commit message | `~/.agents/guides/commit-message.md` (`link-targets/agents/guides/commit-message.md`) |
| Dispatch, handoff, Evidence child, or session identity | `~/.agents/guides/delegation.md` (`link-targets/agents/guides/delegation.md`) |
| .NET build or test | `~/.agents/guides/dotnet-testing.md` (`link-targets/agents/guides/dotnet-testing.md`) |
| Visible external posting | `~/.agents/guides/external-posting.md` (`link-targets/agents/guides/external-posting.md`) |
| Git state, diff, ref, lock, or range control | `~/.agents/guides/git-operations.md` (`link-targets/agents/guides/git-operations.md`) |
| GitHub service/API Issue, PR, review, or comment | `~/.agents/guides/github.md` (`link-targets/agents/guides/github.md`) |
| Scoping an AI Advisor review | `~/.agents/guides/advisor-review.md` (`link-targets/agents/guides/advisor-review.md`) |
| Creating, editing, or reviewing an implementation plan or runbook | `~/.agents/guides/implementation-planning.md` (`link-targets/agents/guides/implementation-planning.md`) |
| Checking authorization for an external operation | `~/.agents/guides/external-operation-authorization.md` (`link-targets/agents/guides/external-operation-authorization.md`) |
| JSON structure or value extraction | `~/.agents/guides/structured-data.md` (`link-targets/agents/guides/structured-data.md`) |

For an identifiable GitHub Issue/PR, when the user requests 「保守」,
「レビュー保守」, `review-consolidation`, or clearly requests consolidation
of review points or alignment of the current plan/state from review conclusions,
read `~/.agents/skills/review-consolidation/SKILL.md` directly and apply its
discovery contract. This is a host-specific routing entry, not a separate
normative contract or permission for external writes. Do not load it for mere
review checks, individual replies, unrelated edits or quoted trigger terms.
If the canonical Skill cannot be read, stop and report.

<!--
  The following is a Claude Code-specific operational note. In Opus 5 sessions, the system injects
  `Do not call the AgentTool unless the user requested it`, which can override the
  "delegate proactively" default in AGENTS.md. No official setting exists to lift it
  (https://github.com/anthropics/claude-code/issues/80988).
-->

## Delegation to subagents (Claude Code)

- Before starting work, consider whether delegating to a subagent would be more efficient. Follow the
  criteria in "Delegation to subagents" in `AGENTS.md`.
- If delegation looks advantageous, present the target agent name and the scope to delegate, and obtain
  permission before delegating. Do not delegate without permission. Do not skip the consideration itself.
