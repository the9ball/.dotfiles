# .dotfiles

個人用の設定リポジトリ。

## 共有設定のリンク管理

- `~/.agents`、`~/.claude/skills`、`~/.claude/agents` は、`link-targets/` 配下の正本を公開する symlink / junction です。
- これらの公開先を操作するときも、公開先を直接編集せず、`link-targets/` 配下の正本を編集します。
- 配置と張り直しの詳細は `link-targets/README.md` を参照します。

## スクリプト実行

- スクリプトファイルは、OSのファイル関連付けなどによる暗黙起動に依存せず、対象環境・プロジェクトに適したインタプリタ、ランタイム、またはランナーをコマンド上で明示して実行する。

## Windows cloudflared サービス

- Windows サービス `Cloudflared` は aqua の `pkgs` 配下を直接参照せず、固定パスのコピーを使う。サービスのバイナリパスを aqua のバージョン別ディレクトリへ戻さない。
- バージョン追従は `chezmoi/.chezmoiscripts/run_onchange_after_update-cloudflared-service.ps1.tmpl`、初回セットアップは `scripts/windows-cloudflared-service.ps1` が担う。経緯・受け入れたリスク・手順は `docs/windows-cloudflared.md` を参照する。

## Issue・Pull Request 運用

- Issue / Pull Request に散在するレビュー情報を現在の work plan と review state へ集約する作業は、対象 Issue / PR に対する「保守」「レビュー保守」または `review-consolidation` の明示指定、もしくはレビュー論点の集約・レビュー結論に基づく現行計画や状態の更新が明確に求められた場合に `review-consolidation` Skill を使用する。単なる閲覧・レビュー確認・個別返信・無関係な修正では起動せず、外部操作の認可は別途確認する。
