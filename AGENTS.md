# .dotfiles

個人用の設定リポジトリ。

## 共有設定のリンク管理

- `~/.agents`、`~/.claude/skills`、`~/.claude/agents` は、`link-targets/` 配下の正本を公開する symlink / junction です。
- これらの公開先を操作するときも、公開先を直接編集せず、`link-targets/` 配下の正本を編集します。
- 配置と張り直しの詳細は `link-targets/README.md` を参照します。

## スクリプト実行

- スクリプトファイルは、OSのファイル関連付けなどによる暗黙起動に依存せず、対象環境・プロジェクトに適したインタプリタ、ランタイム、またはランナーをコマンド上で明示して実行する。

## Issue・Pull Request 運用

- Issue / Pull Request に散在するレビュー情報を現在の work plan と review state へ集約する作業は、ユーザーまたは対象タスクが `review-consolidation` を明示的に呼び出した場合だけ `review-consolidation` Skill を使用する。通常の Issue / PR 操作から自動発動させない。
