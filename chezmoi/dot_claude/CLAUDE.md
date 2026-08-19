<!-- Shared cross-tool instructions live in ~/.agents/AGENTS.md (single source, also read by Codex). -->
@~/.agents/AGENTS.md

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
