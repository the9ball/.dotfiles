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

- target identityまたは必要な範囲を一意に固定できない場合は、推測してdispatchせず、必要な証拠を`NEEDS_EVIDENCE`として要求する。未コミット対象では、capture開始時に実 index・working tree・untracked・ignored manifestのsnapshot identityを固定し、capture中または完了直後の再検証で変化したら旧snapshotを無効化して新しいepochへ戻す。
- snapshot captureが完了した後のrevision差分は`execution-lifecycle-gate`の`review_delta_classification`で`REVIEW_PRESERVING`または`REVIEW_INVALIDATING`に分類する。検証済みのpreserving差分はappend-only inheritance edgeを使い、capture完了後のrevision変更だけを理由に冗長なAdvisor dispatchを要求しない。対象がreview contract・rule・schema・allowlist・governanceを変更する場合は、classificationとfresh Advisor dispatchを`from_revision`のsource contract snapshot/hashに拘束し、destinationの変更後規則を自己評価へ使わない。source contractを固定できない場合は`NEEDS_EVIDENCE`とする。
- Advisorの結果には、target identity、epoch identity、実際に読んだ範囲、追加で読んだ範囲、未確認範囲、未確認理由を記録する。依頼したprimary scope、必須の周辺文脈、dependency closureに未確認が残る場合は、結果を`CLEAR`や`PASS`として扱わない。
- 依存先を事前に限定できない場合は無制限探索を許さず、発見した依存候補と必要証拠を返して`NEEDS_EVIDENCE`へ戻す。追加読取は、依頼したscopeの変更ではなく、理由と境界を伴う追加範囲として台帳へ記録する。

## Revision と evidence inheritance

- `revision_identity` は対象の内容または topology ごとに更新し、`advisor_review_epoch_id` と別に記録する。revision の差分を preserving と分類しても、source evidence の対象版は変更しない。
- Advisor evidence を再利用する場合は、source evidence id と source revision、destination revision、完全な delta manifest/hash、category、classifier/reason、impact axes、validation、epoch を含む append-only の `review_evidence_inheritance` edge を台帳へ追加する。source verdict を destination へ付け替えたり、evidence をコピーしたりしてはならない。
- 完全な tree identity を主 identity とし、delta hash は coordinator が固定 option `git diff --raw -z --no-renames --no-ext-diff --ignore-submodules=all --abbrev=40` と固定 encoding で計算した補助証拠とする。コミット済み target は `from_revision` と `to_revision` の tree をそのまま用いる。
- 未コミット target は、capture開始時に実 indexの絶対path・raw SHA-256、`git --no-optional-locks status --porcelain=v2 -z --untracked-files=all` のNUL byte stream、`git --no-optional-locks ls-files --stage -z` のreal-index byte stream、`git --no-optional-locks ls-files --others --ignored --exclude-standard -z` のignored-path byte streamを先に固定する。実 index・working treeを変更しない新規の専用 `GIT_INDEX_FILE` に `from_revision` を `git read-tree` で読み込み、後述のcandidate manifestを適用して `git write-tree` で不変の `to_tree` を作る。capture後に同じreal-index/status/ignored/manifest snapshotを`--no-optional-locks`で再取得し、index hash、raw status、各entryのcontent/mode hash、path集合が一つでも変化した場合はcaptureを破棄して`REVIEW_INVALIDATING` / `NEEDS_EVIDENCE`とする。
- candidate manifestはGitのNUL byte path順で固定し、各entryにpath bytes、mode、source state（`FROM`、`INDEX`、`WORKTREE`、`UNTRACKED`、`DELETE`、`IGNORED_EXCLUDED`）、source blob/OID、raw content SHA-256、size、symlink target bytesを記録する。候補treeへ採用するsourceは、working treeがindexと異なるentryは`WORKTREE`、indexだけがfrom_revisionと異なるentryは`INDEX`、新規は`UNTRACKED`、削除は`DELETE`とし、`MM`はworking tree bytesを採用してindex bytesも記録する。`IGNORED_EXCLUDED`と対象外pathはcandidate treeへ入れず、許可manifestとの不一致はfail-closedとする。raw bytesはclean filter・quote・改行変換・正規化なしで、専用の隔離 object database（`GIT_OBJECT_DIRECTORY` と repository object database を読む `GIT_ALTERNATE_OBJECT_DIRECTORIES`）へ `git hash-object --no-filters -w --stdin` で保存し、その出力のGit blob OID（repositoryの`git rev-parse --show-object-format`でobject formatも記録）とraw SHA-256を別々に記録する。専用 indexへはraw SHA-256ではなくGit blob OIDを`git update-index --add --cacheinfo <mode>,<git_blob_oid>,<path>`相当で適用し、削除は`git update-index --remove`相当で適用する。`git write-tree`も同じ隔離 object databaseで実行し、refや実 indexを変更しない。
- delta は `git diff --raw -z --no-renames --no-ext-diff --ignore-submodules=all --abbrev=40 <from_revision> <to_tree>` の stdout byte stream をそのまま（decode、quote、改行変換、正規化なし、Gitのpath順・NUL区切りのまま）SHA-256化し、tree、real-index/status snapshot、candidate manifest、hashを一組として固定する。不一致、未確認、source verdictが`CLEAR`以外、またはsource contract snapshot/hashの欠落はreuseを`NEEDS_EVIDENCE`とする。
- packet、child context、reviewer judgment は source revision-bound とし、preserving であっても revision 変更後に盲目的に再利用しない。必要な場合は destination revision 用に再取得する。
- inheritance ledger は現在の execution context で検証可能でなければならず、compaction・中断再開・別セッションから自動継承しない。`REVIEW_INVALIDATING`、ledger 欠落、hash 不一致、edge 欠落、判定不能は新しい epoch と再レビューへ戻す。
