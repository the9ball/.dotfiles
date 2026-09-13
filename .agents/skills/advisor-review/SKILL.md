---
name: advisor-review
description: execution-lifecycle-gate、rigorous-review、または明示的な読み取りスコープ契約が独立した Advisor の設計・安全・互換性レビューを要求したときに使う。通常の確認や文章校正には使わない。
---

# Advisor review workflow

この Skill は、Advisor に対象ファイルを渡す必要があるときの入口です。

## 発動条件

- execution-lifecycle-gate / rigorous-review の契約、または明示された Advisor review が読み取りスコープの固定を要求したときに使う。
- 通常のレビュー、短時間の確認、文章校正には発動させない。

## 実行

1. 読み込まれた Skill の symlink / junction を実体パスへ解決し、その祖先から`.agents/reference-map.json`を見つけ、JSONの`repository_root`をmap所在ディレクトリから解決して instruction root を固定する。この root は共有 instruction の参照専用であり、work root や Git 対象は依頼から別途固定する。現在の作業ディレクトリやホスト固有の絶対パスを基準にしない。
2. instruction-root 相対の`.agents/guides/advisor-review.md`を全文で読み、各対象ファイルの読み取りスコープ宣言を作る。
3. 共通 policy kernel と execution lifecycle の承認・独立性・read-only 契約を維持する。
4. Advisor の出力を裁定や実装承認とみなさず、実読範囲、追加範囲、未確認範囲、出所付き助言として台帳へ記録する。

部分参照の行番号・安定アンカー、dependency closure、未確認時の停止条件を省略しない。参照を解決できない場合は`CLEAR`や`PASS`として扱わず停止して報告する。
