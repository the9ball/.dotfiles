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
| JSON structure or value extraction | `~/.agents/guides/structured-data.md` (`link-targets/agents/guides/structured-data.md`) |

<!--
  以下は Claude Code 固有の運用メモ。Opus 5 のセッションには
  `Do not call the AgentTool unless the user requested it` がシステム側から注入され、
  AGENTS.md の「積極的に委譲する」既定を上書きすることがある。設定ファイルによる解除手段は
  公式に用意されていない (https://github.com/anthropics/claude-code/issues/80988)。
-->

## サブエージェントへの委譲(Claude Code)

- 作業に入る前に、サブエージェントへ委譲した方が効率がよいかを検討する。判断基準は `AGENTS.md` の
  「サブエージェントへの委譲」に従う。
- 委譲が有利だと判断した場合は、対象エージェント名と委譲する範囲を提示して許可を得てから委譲する。
  許可を得ずに委譲しない。検討自体を省略しない。
