# Advisor依頼のファイル参照スコープ

AIレビューでAdvisorへファイルを指定するときに、対象と読み取り範囲を再現可能な形で固定するための契約。パスだけを渡して、Advisorの探索範囲や対象版を推測させてはならない。

## 依頼で固定する項目

各ファイルについて、次の読み取りスコープ宣言を依頼文へ記録する。共有台帳を使うフローでは、同じ宣言を台帳にも記録する。

- `path`: 対象ファイルのパス。
- `target_identity`: commit、blob、snapshot hashなど、対象内容を固定できる識別子。
- `epoch_identity`: target identity、比較基準、対象・除外範囲、レビューの役割・実行環境などを含む、今回のレビューepochを再検証できる識別子。単なる任意のepoch名だけでは代用しない。
- `mode`: `全文`、`差分`、`行範囲`、`構造指定`のいずれか。
- `primary_scope`: 主対象となる行範囲、見出し、シンボル、JSON Pointer／key、diff hunkなど。
- `surrounding_context`: 主対象の理解に必要な前後行、同一節、定義元など。
- `excluded_scope`: 読まないファイル、範囲、状態。
- `dependency_closure`: 判定に必要な参照先・依存先と、その確認境界。

複数ファイルを指定する場合も、ファイルごとに宣言する。共通の指定だけで省略してはならない。

## 読み取りモード

- 部分参照（`mode=行範囲`）では、対象identity上の1始まり・両端含みの行番号と、見出し・シンボル・JSON Pointer／key・diff hunkなどの安定アンカーを併記する。行範囲は主対象であり、判定に必要な周辺文脈や依存先の確認を禁止しない。それらは追加範囲として記録する。
- 全文参照は`mode=全文`と明記する。短いファイルや新規ファイルは原則として全文を指定する。
- 差分参照は、base／targetと差分定義を固定した`mode=差分`とする。差分の行番号は補助情報であり、行番号だけで差分の対象版を定義してはならない。
- 生成物、minifiedファイル、行番号が不安定なJSONは、生成元、構造セレクター、JSON Pointer／key、シンボルなどを`mode=構造指定`で指定する。行番号を無理に固定しない。

## 固定できない場合と結果の記録

- target identityまたは必要な範囲を一意に固定できない場合は、推測してdispatchせず、必要な証拠を`NEEDS_EVIDENCE`として要求する。未コミット対象では、HEAD、index、working tree、untracked manifestのsnapshot identityを固定し、変化したら旧範囲を無効化して新しいepochで再dispatchする。
- Advisorの結果には、target identity、epoch identity、実際に読んだ範囲、追加で読んだ範囲、未確認範囲、未確認理由を記録する。依頼したprimary scope、必須の周辺文脈、dependency closureに未確認が残る場合は、結果を`CLEAR`や`PASS`として扱わない。
- 依存先を事前に限定できない場合は無制限探索を許さず、発見した依存候補と必要証拠を返して`NEEDS_EVIDENCE`へ戻す。追加読取は、依頼したscopeの変更ではなく、理由と境界を伴う追加範囲として台帳へ記録する。
