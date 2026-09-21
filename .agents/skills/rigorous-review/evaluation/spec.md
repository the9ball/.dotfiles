# 評価契約

## 目的

Issue #6 の第一スライスでは、legacy strict flow と候補フローを同じ fixture
で比較するための観測契約を固定する。

この契約は実ランタイムの dispatch を起動しない。

この契約の `PASS` は fixture の整合性と比較規則を満たしたことだけを示し、
既定の review gate や本番の model routing を承認しない。

## 実行境界

manifest の次の値は固定する。

```json
{
  "harness_mode": "fixture_only_observe_only",
  "default_path_changed": false,
  "runtime_dispatch_attempted": false,
  "runtime_dispatch_enforcement_claimed": false
}
```

validator は上記と異なる値を `BLOCKED` として扱う。

このスライスは `rigorous-review/SKILL.md`、
`execution-lifecycle-gate/SKILL.md`、agent metadata を変更しない。

synthetic receipt は、fixture に記録した role、model、routing、dispatch 数の
整合性だけを確認する。

synthetic receipt から、実ランタイムが全入口を通過したこと、二つの context が
実際に独立していたこと、model の能力が同等だったことを導いてはならない。

## identity

manifest は対象 commit、対象ファイルの SHA-256、epoch hash を保持する。

各 result、packet、receipt は同じ `target_manifest_hash`、`epoch_hash`、
`fixture_manifest_sha256` を参照する。

validator は manifest、packet、receipt、joint record の現在の UTF-8 バイト列から SHA-256 を
計算し、result に記録された digest と比較する。

manifest、case、packet、result、receipt、joint record はそれぞれ対応する JSON
 schema でも検証し、schema が許可しない field や required field の欠落を受け入れない。

6 個の schema 文書は固定した SHA-256 digest とも照合し、文書自体の弱体化や差し替えを
受け入れない。

schema 文書の読み込みも fixture root 配下へ realpath で containment 検証し、外部 symlink
を `BLOCKED` とする。

JSON の canonicalization や JCS はこのスライスの前提にしない。

評価ハーネス全体の snapshot identity は `node validate.mjs --aggregate` で計算する。

aggregate は `evaluation/` 配下の通常ファイルを再帰的に列挙し、相対パスを `/` に
正規化して JavaScript の UTF-16 code unit による単純な文字列順に並べる。

各ファイルを `{path, sha256, bytes}` として記録し、`{root, files}` を空白なしの
UTF-8 JSON にする。

JSON の object key は再帰的に辞書順へ並べ、array の順序は維持する。

`root` は常に `agents/skills/rigorous-review/evaluation` とし、その canonical JSON
の SHA-256 を aggregate identity とする。

このアルゴリズムは絶対パス、実行時刻、ロケールに依存しない。

`manifest` の `target.identity_hash` は対象 commit、対象ファイル一覧、各 SHA-256 を
まとめた identity であり、aggregate identity とは別の値である。

fixture 内の `epoch_hash` は対象と統制の preflight policy epoch である。

最終レビューの execution epoch は、台帳で contract hash、aggregate identity、
preflight policy epoch、対象 identity、実行環境を結合して別に記録する。

execution epoch を fixture の `epoch_hash` に書き戻すと自己参照になるため、両者を
同一値として扱ってはならない。

対象 commit や評価契約が変わった場合は、古い result と receipt を再利用せず、
新しい manifest と epoch で fixture を作り直す。

## paired run

一つの case は、同じ packet を使う baseline と candidate の二つの run を持つ。

各 run は次の条件を満たす。

- `side` は `baseline` または `candidate` のいずれかである。
- `run_id` は pair 内で重複しない。
- Reviewer context と Respondent context は異なる識別子を持つ。
- baseline と candidate の context 識別子も重複しない。
- Reviewer と Respondent の承認は、`PASS` の run では同じ joint record version
  に対してともに `true` である。
- `zero-findings` の `PASS` では、各 run が `joint_record_path` で実体を指定し、
  `joint_record_sha256` でその UTF-8 バイト列を参照する。
- joint record は対象、epoch、run、両 role context、`finding_count=0`、空の findings、
  両 role の `approved=true` を含む。
- `proceed_status` は常に `NOT_AUTHORIZED` である。

この検査は記録上の独立性を確認するだけで、実行環境の独立性を証明しない。

## quality contract

比較は case の immutable な `proposition_id` を単位に行う。

proposition の prose を fuzzy match してはならない。

次の値は baseline と candidate で完全一致しなければならない。

- `gate_status`
- `evidence_status`
- `coverage_status`
- `deterministic_checks`
- `proceed_status`
- high または critical の proposition の `discovery`

medium または low の proposition の `discovery` と `rejection` は比較結果を
report に残すが、差分をこのスライスの失敗条件にしない。

medium または low に母数下限や許容回帰数を設けない。

この扱いは重要な品質を high、critical、gate、evidence、coverage に限定する
というユーザー判断を反映する。

`NEEDS_EVIDENCE`、`INVALID`、`MISSING`、`UNRELIABLE`、identity mismatch、
schema error、重複または未知の proposition は `BLOCKED` とする。

`BLOCKED` を `PASS` に変えるための暗黙の omission や fallback は認めない。

## escalation の順序

result は `escalation_trace` に実際に記録した fixture 上の順序を保持する。

許可する順序は次のとおりである。

```text
eligibility → reviewer → respondent → evidence_reacquisition → neutral_adviser
```

`none` は escalation が発生しなかった run だけで単独使用する。

validator は trace の逆行、重複、`none` の混在、`escalation_step` との不一致を
`BLOCKED` とする。

この検査は記録された順序を確認するだけで、実ランタイムがその順序を強制した
ことを証明しない。

## fixture matrix

manifest は次の case を登録する。

| case | 目的 | 各 run の gate status |
| --- | --- | --- |
| `zero-findings` | empty joint record と reliable coverage | `PASS` |
| `high-critical-findings` | high と critical の discovery parity | `PASS` |
| `medium-low-observation` | medium と low の差分を report-only で記録 | `PASS` |
| `false-positive-rejection` | false positive の rejection 指標を記録 | `PASS` |
| `unresolved-evidence` | evidence 不足を gate へ通さない | `BLOCKED` |
| `unreliable-coverage` | coverage 不良を gate へ通さない | `BLOCKED` |

manifest の `expected_status` は、fixture が validator に受け入れられるかを
示す値であり、すべての登録 case で `PASS` になる。

各 run の `gate_status` は case 内の `expected` オブジェクトで固定する。

malformed result、receipt 欠落、packet hash mismatch、epoch mismatch、
duplicate proposition、unknown proposition は tests が一時 fixture を作って
`BLOCKED` を確認する。

## validator の出力

validator は JSON report と人間向け summary を出力する。

`status` は `PASS` または `BLOCKED` のいずれかである。

`errors` は合否を止めた理由を、case、side、field、proposition ID とともに
記録する。

`warnings` は medium または low の report-only 差分を記録する。

各 case の `observations` は baseline と candidate の入力 token、出力 token、合計 token、
dispatch 数、model identity、routing、role context、escalation を記録する。

`observations` は paired trial の比較材料であり、実ランタイムの証明や本番の
go/no-go 判定ではない。

正常終了の exit code は `0`、入力が契約を満たさない場合は `2`、
CLI 引数またはファイルの読み込みに失敗した場合は `64` とする。

JSON の構文エラーや symlink、identity、schema の契約違反は入力エラーとして `2` とし、
manifest、schema、fixture の読み込み自体に失敗した場合は `64` とする。

## このスライスで主張できないこと

次の事項は実ランタイム adapter と authenticated receipt が追加されるまで
評価できない。

- explicit invocation と自然言語 invocation の全 dispatch coverage
- packet、delta、model routing の runtime enforcement
- 実効 model の能力、context、tool access の同等性
- zero-finding fast path が既定 gate を安全に置き換えること
- token、dispatch 数、model 変更による本番コスト削減

これらを検証するには、fixture suite の合格に加えて、全入口の runtime 境界、
署名または同等の真正性を持つ receipt、再現可能な paired live trial、
新しい target と epoch の review が必要である。
