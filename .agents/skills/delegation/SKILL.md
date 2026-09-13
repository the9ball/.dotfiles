---
name: delegation
description: サブエージェントの dispatch、再利用、handoff、Evidence child、session identity を扱うときに使う。モデル固有の補助資料は必要なときだけ選択する。
---

# Delegation workflow

この Skill は、サブエージェントまたは委譲先を使う作業の入口です。

## 発動条件

- dispatch、再利用、handoff、Evidence child、role、session / epoch identity の判断が必要なときに使う。
- 短い自己完結した作業や、ユーザー判断を頻繁に必要とする作業を自動的に委譲しない。

## 実行

1. Skill tree の祖先から`.agents/reference-map.json`を見つけ、JSONの`repository_root`をmap所在ディレクトリから解決して repository root を固定する。現在の作業ディレクトリやホスト固有の絶対パスを基準にしない。
2. repository-root 相対の`.agents/guides/delegation.md`を全文で読み、選択したモデルに固有の調整が必要な場合だけ対応する model guide を追加で読む。
3. 共通 policy kernel の権限・承認・対象範囲・停止条件を維持し、委譲で権限や承認範囲を広げない。
4. 子の報告をそのまま事実とせず、root で対象、差分、ログ、検証結果を照合する。

model guide は共通契約や role 固有契約を上書きしない。対応表にないモデルは推測で補助資料を適用せず、必要なら explicit に選択する。
