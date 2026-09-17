---
name: issue-management
description: Issue または Pull Request の要件、レビュー対応、REVIEW-SUMMARY、HANDOFF、obsolete なトップレベル通常コメントの保守をユーザーまたは対象タスクが採用したときに使う。GitHub の対象特定と外部投稿は必要なときだけ共通 reference として読む。
---

# Issue / Pull Request workflow

この Skill は、Issue / Pull Request の状態・本文・コメント・HANDOFF を扱う作業の入口です。

## 発動条件

- ユーザーまたは対象タスクが Issue / Pull Request の要件、通常コメント、REVIEW-SUMMARY、HANDOFF、レビュー対応、obsolete なトップレベル通常コメントの保守（Hideを含む）を採用したときに使う。
- 単なるローカル調査では発動させず、外部操作を行う場合は外部操作の承認を別に確認する。

## 実行

1. 読み込まれた Skill の symlink / junction を実体パスへ解決し、その祖先から`link-targets/agents/reference-map.json`を見つけ、JSONの`repository_root`をmap所在ディレクトリから解決して instruction root を固定する。この root は共有 instruction の参照専用であり、work root や Git 対象は依頼から別途固定する。現在の作業ディレクトリやホスト固有の絶対パスを基準にしない。
2. instruction-root 相対の`link-targets/agents/guides/issue-management.md`を全文で読み、GitHub 固有の操作が必要なら`link-targets/agents/guides/github.md`を、公開文面が必要なら`link-targets/agents/guides/external-posting.md`を追加で読む。
3. 共通 policy kernel の対象固定、承認、秘密情報、外部操作、Git 安全をこの Skill の手順より先に適用する。
4. guide に記録された状態・不確実性・未解決事項を維持し、推測で別の Issue / PR や投稿経路へ読み替えない。Issue/PR保守のHide対象、REVIEW-SUMMARYの確認、PR review threadのResolveとreview commentの個別Hideとの区別はguideの定義をそのまま適用する。

guide は共通 reference として維持し、この entrypoint に詳細手順を複製しない。参照を解決できない場合は内容を推測せず停止して報告する。
