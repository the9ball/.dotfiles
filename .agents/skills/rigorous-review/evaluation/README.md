# Issue #6 の評価ハーネス

このディレクトリは、`rigorous-review` の既定経路から分離した評価用の
fixture と validator を置く。

この第一スライスは fixture-only かつ observe-only である。

- 既定のレビュー経路、`SKILL.md`、lifecycle gate は変更しない。
- 実ランタイムの dispatch、モデル routing、独立 context、coverage を実行時に監視しない。
- synthetic receipt は fixture の整合性を検証するだけで、本番の dispatch 削減や fast path の安全性を証明しない。
- 不正、不足、対象 identity の不一致、未解決 evidence、信頼できない coverage は `BLOCKED` とする。

`schema/` は manifest、case、packet、result、dispatch receipt、zero-findings joint record の入力契約を保持する。

6 個の schema は固定 SHA-256 と fixture root 内の realpath containment でも検証する。

`fixtures/cases/` は同じ packet に対する baseline と candidate の paired run を保持する。

`fixtures/packets/`、`fixtures/results/`、`fixtures/receipts/`、`fixtures/records/` は、
manifest の SHA-256 と target、epoch の identity をそれぞれ参照する。

実行方法は、リポジトリルートから `node .agents/skills/rigorous-review/evaluation/validate.mjs` である。

回帰テストは `node .agents/skills/rigorous-review/evaluation/tests/validate.test.mjs` で実行する。

validator の `PASS` は、登録した fixture が比較契約を満たしたことを示す。

ハーネス全体の再現可能な snapshot identity は `node .agents/skills/rigorous-review/evaluation/validate.mjs --aggregate` で確認する。

JSON report の `observations` には、paired run の token、dispatch、model、routing、
context、escalation を比較するための観測値が含まれる。

ファイル読み込み失敗は CLI exit `64`、JSON や契約の不正は exit `2` として分類する。

実ランタイムの dispatch、model routing、context の独立性、既定 gate の置換を示す値ではない。
