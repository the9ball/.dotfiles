# .dotfiles

個人用の設定リポジトリ。

## 共有設定のリンク管理

- `~/.agents`、`~/.claude/skills`、`~/.claude/agents` は、`link-targets/` 配下の正本を公開する symlink / junction です。
- これらの公開先を操作するときも、公開先を直接編集せず、`link-targets/` 配下の正本を編集します。
- 配置と張り直しの詳細は `link-targets/README.md` を参照します。

## スクリプト実行

- スクリプトファイルは、OSのファイル関連付けなどによる暗黙起動に依存せず、対象環境・プロジェクトに適したインタプリタ、ランタイム、またはランナーをコマンド上で明示して実行する。

## Issue・Pull Request 運用

- Issue または Pull Request の要件、通常コメント、HANDOFF の運用を採用するとユーザーまたは対象タスクが明示した場合は、`issue-management` Skill を優先して使用する。Skill を発見できない場合は、`link-targets/agents/guides/issue-management.md` を実行前に読む。

## ブランチ運用

- 個人用設定リポジトリなので、余計なブランチは使わず master へ直接コミットする。
  デフォルトブランチであることを理由に作業用ブランチを切らない。
- 作業用ブランチを切るのは、ユーザーが明示的に指示した場合だけ。
- push はユーザーから指示があったときだけ行う。
