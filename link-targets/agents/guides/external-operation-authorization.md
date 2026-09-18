# 外部操作の認可境界

外部操作の承認は、完成したコマンドや送信本文そのものではなく、ユーザーが許可した意味的な操作範囲に結び付ける。

この範囲を **authorization boundary** と呼ぶ。

boundary は、具体値を自動的に固定したり、後の作業へ無期限に承認を引き継いだりする仕組みではない。

実行主体は、各試行の直前に現在の対象と操作を boundary へ照合し、照合結果を操作記録へ残す。

## Boundary record

承認を取得したときは、少なくとも次の項目を一つの boundary record に記録する。

* `authorization_id`
* 根拠となるユーザー指示と取得時点
* 目的
* 対象または安全な target selector
* 許可する論理操作、成功適用回数、対象集合の上限
* 意味的な内容範囲
* 反映先と公開範囲
* 使用主体、アカウント、許可経路、権限上限
* 前提条件と明示的な対象外
* 完了、取消、失効、再検証条件
* 有限の retry budget

## 中断・再開と承認の非継承

計画書、Issue本文、REVIEW-SUMMARY、HANDOFF、task-continuityメモは boundary record の代わりにならない。

それらの文書を読み直しただけでは、承認を生成、拡張、復活させない。

中断、再開、環境移動の後は、元のユーザー指示と未消費の操作状態を現在の対象へ再適用できるか確認する。

## 実行直前の照合

具体値が承認時点と異なる場合でも、値の比較方法は項目の性質に応じて選ぶ。

同一性を比較する項目は、明示された target または selector、actor、account、path、反映先、公開範囲、権限上限である。

selector から展開した個々の target は、列挙可能な現物 identity 証拠に基づき、selector が許可する集合への membership を比較する。

selector の構成員判定は列挙可能な現物 identity 証拠に限り、意味的な包含を構成員の許可根拠にしない。

意味的な包含を比較する項目は、目的、許可操作、意味的内容、送信本文である。

残数を比較する項目は、対象集合の上限、実際に展開した対象数、成功適用回数、retry budget である。

selector の展開結果が対象集合の上限を超えた場合は `OUTSIDE_BOUNDARY` とし、展開を完了できない、または対象数を確認できない場合は `INDETERMINATE` とする。

次の三値を使う。

| 判定 | 条件 | 実行 |
| --- | --- | --- |
| `WITHIN_BOUNDARY` | すべての項目を現物証拠で確認し、同一性、包含、残数を満たす | 実行できる |
| `OUTSIDE_BOUNDARY` | 確認できた項目の一つ以上が範囲外である | 新しい承認が必要 |
| `INDETERMINATE` | 必須項目を確認できない、または範囲内か判断できない | 証拠取得または新しい承認まで停止 |

具体的な本文やコマンドの変更だけを理由に `OUTSIDE_BOUNDARY` と判定してはならない。

変更後の意味的内容が boundary に包含されるかを判定できないときは `INDETERMINATE` とする。

判定の優先順は、確認済みの `OUTSIDE_BOUNDARY`、確認不能な `INDETERMINATE`、すべて確認済みの `WITHIN_BOUNDARY` の順とする。

既知の範囲外と確認不能な項目が同時にある場合は `OUTSIDE_BOUNDARY` とし、範囲外がなく確認不能な項目だけがある場合は `INDETERMINATE` とする。

## 消費状態と retry

論理操作ごとに次の状態を区別する。

* `AVAILABLE`：まだ外部効果を成功させていない。
* `ATTEMPTING`：照合後の試行中である。
* `SUCCEEDED_CONSUMED`：外部効果を確認し、成功回数を消費した。
* `FAILED_NO_EFFECT`：送信前または外部効果なしを確認した。
* `OUTCOME_AMBIGUOUS`：成功と失敗のどちらかを確定できない。
* `INVALIDATED`：boundaryまたは前提条件が失効した。

成功を確認した論理操作は再送しない。

送信前または外部効果なしを確認した失敗は、同じ論理操作、副作用、対象、主体、権限、boundary のままなら retry できる。

既定の retry budget は初回試行と自動 retry 1回の合計とする。

timeoutや不明応答は `OUTCOME_AMBIGUOUS` として扱い、read-back、ID照合、remote state照合で未適用を確認するまで再送しない。

read-back で未適用を確認できない場合は、承認が残っていても停止する。

retry を理由に対象、サービス、アカウント、資格情報、権限、remote、ref、公開範囲、経路を変更しない。

403、404、認証変更、scope 追加、別CLI/APIへの切替は自動 retry に含めない。

## 規範的な回帰行列

| ケース | 現物証拠と期待判定 | 実行または停止 |
| --- | --- | --- |
| 具体的な送信本文だけが変化し、意味的包含が成立する | `WITHIN_BOUNDARY` | 再承認なしで実行し、成功時に消費する |
| 具体的な意味的包含を判断できない | `INDETERMINATE` | 証拠取得まで停止し、解決不能なら新しい承認を求める |
| selector 内へ展開した対象数が対象集合の上限を超える | `OUTSIDE_BOUNDARY` | 新しい承認まで停止する |
| selector の展開完了または対象数を確認できない | `INDETERMINATE` | 証拠取得まで停止し、推測で実行しない |
| 列挙集合外だが意味的に類似する target、またはそのidentityが確認できない | `OUTSIDE_BOUNDARY` または `INDETERMINATE` | 類似性を許可根拠にせず、範囲外または確認不能として停止する |
| 既知の範囲外と確認不能な項目が同時にある | `OUTSIDE_BOUNDARY`（`INDETERMINATE` より優先） | 新しい承認まで停止し、確認不能な項目の証拠も取得する |
| 外部効果なしを確認した同一操作で retry budget が残る | `FAILED_NO_EFFECT` から同一操作を自動 retry 1回 | retry 成功時だけ消費し、追加の自動 retry はしない |
| timeout 後に read-back で未適用を確認できない | `OUTCOME_AMBIGUOUS` | 再送せず停止する |
| credential、scope、remote、ref、actor、権限のいずれかが変化する | `OUTSIDE_BOUNDARY` または `INVALIDATED` | retryせず、新しい承認まで停止する |
| boundary は不変だが review evidence が意味的に変化する | authorization は維持、review/verification は旧状態 | 新しい review または verification の完了まで実行しない |
| REVIEW-SUMMARY の具体的な最終本文だけが変化し、重要な意思表示が追加されない | `WITHIN_BOUNDARY`、重要主張チェック済み | 完成本文の事前承認を要求せず、投稿後にartifactとread-backを記録する |
| CLI の不正オプションを除去した結果が外部効果なしで、同一操作・同一boundaryに留まる | `FAILED_NO_EFFECT` | 初回＋自動 retry 1回の範囲で再実行し、成否不明なら停止する |

## Review evidence との分離

authorization boundary と target または epoch に結び付いた review evidence は別の状態として扱う。

| Authorization boundary | Review evidence | 扱い |
| --- | --- | --- |
| 有効・不変 | 不変 | 実行時再検証後に実行できる |
| 有効・不変 | 意味のある変更あり | 承認は維持できるが、新しい review または verification epoch の完了まで実行しない |
| `OUTSIDE_BOUNDARY` | 不変 | 新しい承認が必要 |
| `OUTSIDE_BOUNDARY` | 変更あり | 新しい承認と新しい review または verification が必要 |
| `INDETERMINATE` | 不変 | 必要な証拠で `WITHIN_BOUNDARY` または `OUTSIDE_BOUNDARY` を解決するまで停止し、解決不能なら新しい承認が必要 |
| `INDETERMINATE` | 変更あり | 承認と review または verification の両方を解決するまで停止する |
| 有効性またはidentityを確認不能 | 任意 | `INDETERMINATE` として承認と証拠を実行根拠に使わず停止する |

boundary を `USER_AUTHORIZED`、`PASS_WITH_USER_AUTHORIZATION`、target/epoch evidence へ写像しない。

execution lifecycle の fail-closed な identity、review contract、ledger、通常レビュー要件は別の契約として維持する。

## 明示委任の裁量

「対応して」「保守して」などの明示委任があっても、裁量は boundary 内の具体化に限る。

確認済み事実、実施作業、検証結果、既存判断の忠実な要約、通常の文章品質や表現調整は、意味的範囲内で決定できる。

次の内容をユーザーの立場として新たに作る場合は、追加の確認を要する。

* 約束、期限、サポート責任、リスク受容
* 法務、コンプライアンス、金銭、セキュリティ方針
* 対外評価、推薦、非難、プロジェクト方針、優先順位、終了判断
* 未公開情報、個人の経験、意図、感情、未検証の事実

判断の出所を偽らず、レビュー所見には出所を付ける。

## IssueとPull Requestへの適用

Issue本文更新、REVIEW-SUMMARY投稿、HideまたはResolve、push、Pull Request作成は、別々の論理操作として識別・記録する。

一回のIssue保守委任へ含める操作集合は、開始時点の対象snapshotと既存の保守契約から bounded に定める。

本文更新、Summary投稿、HideまたはResolveの各操作は成功回数を個別に消費する。

実行中に追加されたコメントや別対象を、自動的に操作集合へ追加しない。

操作後は、operation ID、対象、具体的操作、外部artifact、read-back結果、boundary判定、消費とretry、skipped、failed、ambiguousな操作、未解決事項を記録する。

この記録は承認の代わりにならず、追加操作の承認も与えない。

## 適用順序

AGENTS.md には常時必要な最小の認可境界だけを置く。

GitHub、Issue管理、外部投稿、execution lifecycle の各ガイドは、この契約を論理操作へ適用する。

承認要求の洗い出し、一括取得、pending state、計画との連携は、別の承認要求ワークフローの責務とする。

後段の承認要求ワークフローは、取得した承認をこのガイドの boundary record として実行入力へ引き渡す。

その boundary の有効性、消費、retry、実行後記録はこのガイドの責務とし、#48の実装完了を前提にしない。
