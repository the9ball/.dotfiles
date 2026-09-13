---
name: git-operations
description: Git の状態取得、差分・レビュー範囲固定、index.lock や権限エラー、範囲制御を扱うときに使う。破壊的操作や push の承認を代替しない。
---

# Git operations workflow

この Skill は、Git の状態確認・変更・復旧・レビュー範囲固定の入口です。

## 発動条件

- Git の状態取得、index / ref の変更、差分やレビュー範囲の固定、index.lock、権限エラー、formatter・lint の範囲制御を扱うときに使う。
- push、force push、履歴書き換え、ロック削除などの外部・破壊的操作は、別の明示承認と上位規則を必要とする。

## 実行

1. 読み込まれた Skill の symlink / junction を実体パスへ解決し、その祖先から`.agents/reference-map.json`を見つけ、JSONの`repository_root`をmap所在ディレクトリから解決して instruction root を固定する。この root は共有 guide の参照専用であり、Git の work root、比較基準、終端、対象 identity、除外範囲は依頼と現在の Git 状態から別途固定する。現在の作業ディレクトリやホスト固有の絶対パスを暗黙の基準にしない。
2. instruction-root 相対の`.agents/guides/git-operations.md`を全文で読み、状態取得・権限エラー・差分範囲・範囲制御を適用する。
3. 読み取り専用の状態確認には`git --no-optional-locks`を使い、権限エラー時は原因を確認して同じ Git 操作だけを許可された経路で再試行する。
4. scope 外の変更を暗黙に対象へ含めず、対象 identity の不一致を受け入れない。対象と既存の dirty changes を安全に分離できない場合だけ停止して報告する。

この Skill は policy kernel の Git 安全、外部操作承認、ユーザー変更保護を縮小しない。
