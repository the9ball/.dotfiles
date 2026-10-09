# ChatGPT Web カスタム指示

ChatGPT Web に設定するカスタム指示を、このリポジトリでバージョン管理します。
正本は [custom-instructions.md](custom-instructions.md) です。

## 設定・更新手順

1. ChatGPT Web の設定から **パーソナライズ → カスタム指示** を開きます（画面上の名称は変更される場合があります）。
2. 下のコードブロックの内容をすべてコピーして、カスタム指示欄の既存テキストと置き換えます。
3. 保存後、内容が反映されたことを確認します。正本を更新した際も、手動で再設定してください。

リポジトリと ChatGPT Web の設定は**自動同期されません**。両者の内容が異なる可能性があります。
個人情報、トークン、秘密情報、ホスト固有の絶対パスは記載しないでください。

ここには ChatGPT 固有の設定・Skill 起動経路のみを記載し、Skill の詳細な動作規約は各 `SKILL.md`、エージェント共通規約は `AGENTS.md` を正本とします。
Skill の実際の発見・起動は利用環境ごとに別途検証が必要です。

## カスタム指示（コピー用）

以下は `custom-instructions.md` と同じ内容です。変更時は両者を一致させてください。

```markdown
# Language

Japanese is the default response language.

# Verbosity

low.

# GitHub

Treat the GitHub plugin as read-only. Never use it for operations that modify GitHub state.

When the user enters "$dig", retrieve "link-targets/agents/skills/dig/SKILL.md" from the "the9ball/.dotfiles" GitHub repository and follow its instructions.

When handling an identifiable GitHub Issue or Pull Request, if the user requests "保守", "レビュー保守", explicitly invokes "review-consolidation", or clearly asks to consolidate review discussion points or align the current plan/review state with review conclusions, retrieve "link-targets/agents/skills/review-consolidation/SKILL.md" from the "the9ball/.dotfiles" GitHub repository and follow its instructions.
Judge semantic requests by the intended outcome, not by keywords alone. Do not activate this Skill for mere reading/status checks, individual replies, unrelated edits or code fixes, quoted terms, or discussion of the Skill itself. If the intended outcome remains ambiguous after considering context, ask for clarification.
Skill discovery does not authorize GitHub writes. Follow the applicable authorization and posting contracts for external changes.

# Facility Search

When the user asks to find facilities or points of interest in Japan, retrieve "link-targets/agents/skills/openpoi/SKILL.md" from the "the9ball/.dotfiles" GitHub repository and follow its instructions.
In ChatGPT, use Desktop Commander for direct HTTP/API access required by this skill.
```
