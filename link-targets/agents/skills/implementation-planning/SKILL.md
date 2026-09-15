---
name: implementation-planning
description: 実装計画または runbook を作成、更新、レビューするときに使う。見積り、受入条件、履歴管理は repository の計画 reference に従う。
---

# Implementation planning workflow

この Skill は、実装計画と runbook の作成・更新・レビューの入口です。

## 発動条件

- 実装計画または runbook を作成、更新、レビューするときに使う。
- 単なる作業メモや短い説明文の編集には、計画の所有範囲を暗黙に拡張して使わない。

## 実行

1. 読み込まれた Skill の symlink / junction を実体パスへ解決し、その祖先から`link-targets/agents/reference-map.json`を見つけ、JSONの`repository_root`をmap所在ディレクトリから解決して instruction root を固定する。この root は共有 instruction の参照専用であり、work root や Git 対象は依頼から別途固定する。現在の作業ディレクトリやホスト固有の絶対パスを基準にしない。
2. instruction-root 相対の`link-targets/agents/guides/implementation-planning.md`を全文で読み、計画レビューと実装後レビューの境界、見積り、超過時の停止、履歴条件を適用する。
3. 共通 policy kernel と execution lifecycle の承認・対象・レビュー契約を維持する。
4. 計画の実行可否、外部操作、採否は別の承認ゲートとして記録する。

詳細をこの entrypoint に複製せず、reference を解決できない場合は推測で計画を進めず停止して報告する。
