# .dotfiles

個人用の設定リポジトリ。

## 共有設定のリンク管理

- `~/.agents`、`~/.claude/skills`、`~/.claude/agents` は、`link-targets/` 配下の正本を公開する symlink / junction です。
- これらの公開先を操作するときも、公開先を直接編集せず、`link-targets/` 配下の正本を編集します。
- 配置と張り直しの詳細は `link-targets/README.md` を参照します。

## スクリプト実行

- スクリプトファイルは、OSのファイル関連付けなどによる暗黙起動に依存せず、対象環境・プロジェクトに適したインタプリタ、ランタイム、またはランナーをコマンド上で明示して実行する。

## push 前のローカル検証

- push 前に `.github/workflows/ci.yaml` と `SETUP.md` の検証手順を確認し、リポジトリのルートで `pwsh -NoProfile -File scripts/check-ci.ps1` を実行する。Docker の Linux エンジンを使い、CI と共通のコンテナで `prek run --all-files --stage manual` を実行する。Desktop Commander を利用できる場合も、接続先のローカル環境で実行する。
- チェックが失敗した場合は原因を修正して再実行し、成功を確認するまで push しない。
- 実行できないチェックがある場合は、理由と未検証の範囲を報告する。ローカル検証の成功を装わず、CI と完全に同一の環境で検証できたとも主張しない。
- `pre-push` フックの導入は任意であり、フックの有無にかかわらず上記の全ファイルチェックを実行する。

## Windows cloudflared サービス

- Windows サービス `Cloudflared` は aqua の `pkgs` 配下を直接参照せず、固定パスのコピーを使う。サービスのバイナリパスを aqua のバージョン別ディレクトリへ戻さない。
- バージョン追従は `chezmoi/.chezmoiscripts/run_onchange_after_update-cloudflared-service.ps1.tmpl`、初回セットアップは `scripts/windows-cloudflared-service.ps1` が担う。経緯・受け入れたリスク・手順は `docs/windows-cloudflared.md` を参照する。

## Issue・Pull Request 運用

- Issue / Pull Request に散在するレビュー情報を現在の work plan と review state へ集約する作業は、対象 Issue / PR に対する「保守」「レビュー保守」または `review-consolidation` の明示指定、もしくはレビュー論点の集約・レビュー結論に基づく現行計画や状態の更新が明確に求められた場合に `review-consolidation` Skill を使用する。単なる閲覧・レビュー確認・個別返信・無関係な修正では起動せず、外部操作の認可は別途確認する。
