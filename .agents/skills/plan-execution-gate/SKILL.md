---
name: plan-execution-gate
description: 承認済み実装計画または goal に基づく変更を、計画ごとに選択したレビュー契約に従って自走させ、必要な最終確認を固定したコミット範囲に対して行う。計画書だけの作成・更新や、挙動を変えない説明文書だけの変更には適用しない。
---

# Plan Execution Gate

## 目的

承認済みの実装計画または goal から実装完了までの品質ゲートを、計画書への定型的なレビュー手順の追記なしで自走させる。計画の承認、実装の採否、外部公開の承認を代替せず、計画または goal で選択したレビュー契約に従って必要なレビュー対象とコミット範囲を固定し、指定されたレビューだけを実行する。指摘を修正した新しい対象は、契約で選択されたレビューと検証を経て再確認する。

## レビュー契約

- `user_review` と `review_level` は一つの計画または goal run ごとに独立して指定できる。前者はユーザー通常レビューの要否、後者は Advisor と `rigorous-review` という独立した AI レビューの強度だけを制御する。計画済み検証、既存の承認・権限ゲート、他の上位規則は、いずれの値でも省略しない。
- 両方の指定元は、明示的なユーザーまたは goal の契約、計画書の対応する指定、既定値の順で個別に解決する。計画書にレビュー手順や起動文を繰り返し書く必要はない。`PASS` 後の successor run はレビュー契約を自動継承せず、新たに解決する。
- `user_review` の値は次のいずれかとする。
  - `REQUIRED`: 最終 candidate target に結び付くユーザー通常レビューを必ず実施する。snapshot identity、提示内容、ユーザーの明示的な承認・変更なし、または各 feedback の解消確認を証拠として記録する。
  - `NONE`: ユーザー通常レビューを実施せず、`SKIPPED` とした理由、根拠、指定元を記録する。既存の上位規則が同じ candidate target のユーザー通常レビューを要求している場合は、この指定だけで無効化せず、競合として停止して確認を求める。編集承認、実装採否、履歴書き換え、push、外部送信など別種の承認ゲートは通常レビューと独立して履行する。
  - `AUTO`: 既定値。計画・goal・ユーザー・上位規則にユーザー通常レビューの要否が明示されていればそれに従い、明示がなければ `NONE` として扱う。競合または判断不能なら推測せず停止して確認する。Skill の発動だけを理由に `REQUIRED` と推定してはならない。
- `review_level` の値は次のいずれかとする。
  - `NONE`: Advisor と `rigorous-review` を実行しない。すべての必須 Advisor トリガーが根拠付きで false で、計画・goal・上位規則にレビュー必須指定がない場合だけ有効とする。
  - `ADVISOR`: 最終 Advisor を実行し、`rigorous-review` は実行しない。
  - `RIGOROUS`: `rigorous-review` を実行し、Advisor は必須トリガーがある場合だけ実行する。
  - `FULL`: 最終 Advisor と `rigorous-review` の両方を実行する。
  - `AUTO`: 既定値。必須トリガーがあれば Advisor を加え、通常の実装ゲートでは `RIGOROUS` を選ぶ従来の安全側挙動とする。
- `NONE` や `RIGOROUS` が必須 Advisor トリガーと衝突する場合、選択値を黙って優先せず、`effective_review_level` を少なくとも `FULL` へ引き上げる。ユーザーが必須下限を拒否した場合は停止して確認を求め、レビューなしで `PASS` にしてはならない。明示的な `rigorous-review` 指定も `RIGOROUS` の下限として扱う。
- preflight と最終 candidate 固定時に `requested_user_review`、`effective_user_review`、`requested_review_level`、`effective_review_level`、それぞれの入力元、必須下限、選択理由、実行または `SKIPPED` の理由を台帳へ記録する。`NONE` は選択したレビュー工程を省略する意味に限られ、品質確認全体の免除ではない。

## 発動条件

- 承認済み実装計画または goal のレビュー契約で本 Skill が選択された作業、またはユーザーが本 Skill を明示指定した作業で発動する。
- 対象は、コード、テスト、実行・ビルド・デプロイ設定、スキーマ・データ移行、生成元・生成物、API・通信、またはエージェントやツールの動作を制御するファイルを変更する実装とする。
- 計画書自体の作成・更新だけ、または規範・仕様・契約・運用手順を変更しない説明文書だけの編集は発動しない。拡張子ではなく変更の役割で判定する。
- 計画書へ個別レビュー手段の呼出し手順を毎回記載することは、発動条件でも完了条件でもない。本 Skill の適用と実行順序を共通経路とし、計画書には固有のレビュー判断点や追加検証が必要な場合だけ記載する。
- 対象か判断できない場合、免除扱いにせずユーザーへ確認する。

## 権限と役割

- 計画、範囲、実装承認、外部操作の既存ゲートを弱めない。レビュー結果は実装・本番採用・外部送信の承認ではない。
- 調整者は対象 identity、レビュー epoch、コミット範囲、ゲート状態を管理する。レビュー者と回答者は対象と台帳を読み取り、台帳の更新案だけを返す。
- `effective_user_review=REQUIRED` のユーザー通常レビューは、ユーザーへ候補差分と計画済み検証結果を提示し、提示した snapshot identity に結び付いたユーザーの明示的なレビュー完了・承認（変更なしを含む）、または各 feedback の解消確認を含む応答と、未解決 feedback がないことを台帳へ記録する工程である。無応答、計画承認だけ、または snapshot と結び付かない曖昧・無関係な応答を通常レビュー完了の証拠にしない。`effective_user_review=NONE` の場合は、この工程を `SKIPPED` として記録する。通常レビューは独立したレビュー者・回答者による `rigorous-review` の代替ではない。
- Advisor は一般的な品質レビュー担当ではなく、設計、セキュリティ、互換性、データ整合性、破壊的移行、重大な計画逸脱などの判断を助言する。Advisor が利用できない場合に別のモデルを黙って代用しない。

### Advisor 要否の判定

- Advisor の要否は、実行結果とは分けて `REQUIRED`、`NOT_REQUIRED`、`UNRESOLVED` のいずれかを先に判定する。調整者は各トリガーの true/false/unknown、該当する計画条項・パス・差分範囲、判定理由、証拠、判定主体を台帳へ記録する。
- 次のいずれかに該当するときは `REQUIRED` とする。
  1. セキュリティ、プライバシー、認証・認可、暗号、secret、決済、権限、または信頼境界を追加・変更する。
  2. データ消失・不可逆操作、破壊的移行、永続データの整合性、または rollback 可否を変更する。
  3. 分散整合性、並行性、順序性、冪等性、複数サービス・複数バージョン展開の正しさに影響する。
  4. 公開 API、通信形式、保存形式、スキーマ、互換性保証を破る、または段階展開を必要とする。
  5. 承認済み計画にない設計判断が必要で、選択肢により上記リスク、コンポーネント境界、永続化方式、互換性、rollback 方針のいずれかが変わる。
  6. `AGENTS.md`、`SKILL.md`、agent 定義、権限・sandbox・routing・tool/plugin 設定などの統制規則を変更し、発動、承認、write・外部送信・破壊的操作、委譲・モデル・ツール選択、対象 identity・証拠、役割独立性、停止、waiver、または `PASS` に影響する。
  7. 承認済み計画から重大な逸脱がありリスク受容の判断が必要、重大な原因候補が複数残る、または同じ問題への証拠に基づく修正が2回失敗する。
- `AGENTS.md` や `SKILL.md` のパスだけでは `REQUIRED` としない。誤字、整形、リンク修正、意味を変えない言い換えだけの場合は、規範的意味が同値である根拠を記録できたときに限り `NOT_REQUIRED` とする。
- 要否判定は、いずれかのトリガーが true なら `REQUIRED`、true がなく unknown が一つでもあれば `UNRESOLVED`、すべて false なら `NOT_REQUIRED` の順で決める。true と unknown が混在する場合は `REQUIRED` を優先する。
- `UNRESOLVED` の場合は Advisor を実行するかユーザーへ停止・確認を報告し、追加証拠を台帳へ記録して三値判定をやり直す。Advisor の回答 `CLEAR` は要否を自動的に `NOT_REQUIRED` へ変えず、unknown が残る場合は停止する。`UNRESOLVED` を無検証で `NOT_REQUIRED` と記録してはならない。

### Advisor の実行時期と追加 checkpoint

- preflight では要否だけを三値判定し、Advisor の dispatch は原則として実装・計画済み検証・`effective_user_review=REQUIRED` のユーザー通常レビュー（選択時）が完了し、当該 epoch の candidate target を固定した直後に一度だけ行う。`effective_user_review=NONE` の場合は通常レビューを待たず、計画済み検証後に candidate target を固定する。`REQUIRED` なら最終 Advisor の `CLEAR`、`UNRESOLVED` なら追加証拠による再分類と必要な Advisor の結果が、厳密レビュー開始と `PASS` の前提になる。`NOT_REQUIRED` は最終 target で全トリガーが根拠付きで false と再確認できた場合だけ dispatch を省略できる。
- 実装前または途中に、最終まで待つと安全に継続できない重要な判断点（セキュリティ・信頼境界、不可逆なデータ変更・移行、公開 API・互換性、分散整合性・rollout、または計画外の重大な設計・リスク受容）がある場合は、当該判断を通過・確定・commit・実施する前に Advisor の追加 checkpoint を必ず dispatch し、結果が `CLEAR` になるまでその判断点と作業の継続を停止する。実行不能、`BLOCKED`、`REQUIRES_USER_DECISION`、またはその他の `CLEAR` 以外の結果でも停止してユーザーへ報告する。各 checkpoint は判断目的、具体的な質問、対象 scope/epoch、理由、結果、次の判断を台帳へ記録し、最終 Advisor 判定の代替にしない。
- 追加 checkpoint は一つのゲート実行全体（fixup・amend による全 epoch を含む）で最大2回とし、epoch が変わっても上限をリセットしない。3回目が必要になった場合は Advisor を黙って追加せず、ユーザーへ停止・確認を報告する。通常の実装手順、単なる進捗確認、同じ判断の反復には dispatch しない。

## 事前固定

実装完了レビューを始める前に、次を同じ台帳へ記録する。

1. 承認済み計画の絶対パス、内容 hash または commit、承認状態、対象範囲、計画時の検証方法と見積り。
2. 比較基準の base SHA、対象の target SHA または対象 commit 群、作業ツリーの staged・unstaged・untracked 状態、epoch identity に含める実行環境・ゲート統制面の識別子と各識別子を再計算する方法。
3. 対象に含めるファイルの identity manifest と、除外する既存差分・untracked の一覧。
4. Advisor の要否判定、レビュー契約（requested/effective `user_review` と `review_level`、各入力元、必須下限）、追加 checkpoint の上限・実績、ユーザー通常レビューの証拠方法、レビュー役割、進捗確認予算、今回のコミット方式（fixup の対象 SHA、または amend 操作と対象コミットを明示した承認）。

対象と既存の dirty な変更を分離できない、manifest が変化した、または SHA・hash を再現できない場合は、レビューを開始せずユーザーへ報告する。

### Epoch identity の再検証

- epoch identity は、計画 identity、base/target、対象 identity manifest、除外範囲に加え、ゲートに関係する実行環境・統制面の識別子で構成する。後者には、利用するモデル・役割・推論予算、permission・sandbox、routing、tool/plugin の設定と利用可能範囲、ゲートに影響する `AGENTS.md`・`SKILL.md`・agent 定義の版を含め、何をどの方法で識別したかを台帳へ記録する。
- 調整者は、Advisor を実行する場合はその dispatch 直前、レビュー者・回答者の各役割を開始する直前、共同最終記録を確定する直前、`PASS` を確定する直前に、変更可能な対象 manifest と epoch identity を現物から再計算して照合する。意味のある差異、識別不能、または比較不能があれば、旧役割承認と共同記録を再利用せず、対象変化として現在の epoch を無効化して新しい epoch を開始する。
- 無関係または意味同値の環境変更だけを除外する場合も、対象の独立性、read-only 保証、モデル・tool 条件、ゲートの規範的意味に影響しない根拠を台帳へ記録する。これは `PASS` 後の変更を扱う無効化規則とは別に、`PASS` 前の再検証として適用する。

## コミット単位

- 既定は、一つの一貫した、レビュー可能で revert 可能な意図を一つのコミットにする。ファイルやレイヤーだけを理由に分割しない。
- 対象実装と、その検証に必要なテストは機械的に分離しない。生成物を生成元から分離する場合も、プロジェクト固有の生成手順と依存順序を優先する。
- 複数の独立機能、独立 rollback 単位、DB の additive change・backfill・切替、複数サービスの互換性展開、複雑な生成元と生成物の対応、または fixup 先が曖昧な場合のいずれかに該当するときは、計画書に `Commit map` を必須化する。map には各単位の識別子、意図、対象ファイル（共有ファイルは変更範囲）、依存順序、検証方法、rollback 範囲、想定する初回コミットと fixup target を記載する。単純な作業で毎回定型文を書く必要はないが、該当性が判断できなければユーザーへ確認する。
- 固定コミットをレビューする場合は、先に初回実装コミットを作る。fixup は対応する実装コミットを target にし、amend はユーザーまたは計画が操作名 `amend` と対象コミット（SHA または一意な ref）を明示して承認し、既存の履歴書き換え条件も満たす場合だけ使う。「一つの論理コミットを維持する」という指定だけでは amend の承認とみなさない。
- 複雑な計画では、レビュー開始前に Commit map と実際の commit range を照合する。各単位が計画した commit または明示した commit 群へ対応し、対象ファイルと共有ファイル内の変更範囲に未対応・重複がなく、依存順序・検証方法・rollback 範囲・fixup target が一致していない場合は停止する。

## レビュー状態

Advisor を実行した場合は次のいずれかを返す。実行前の要否判定 `REQUIRED`・`NOT_REQUIRED`・`UNRESOLVED` と混同しない。

- `CLEAR`: 判断が必要な論点は解消し、ゲートを妨げる助言がない。
- `REQUIRES_USER_DECISION`: 計画・範囲・リスク受容をユーザーが決める必要がある。
- `BLOCKED`: Advisor の実行、証拠、対象 identity を確立できない。

`rigorous-review` の「完了」は、そのままゲートの `PASS` ではない。ここでいう `gate-blocking` は、未修正の `指摘成立`、すべての `不同意確定`、および `調整不能` を指し、非 blocking の不同意は設けない。ゲートの `PASS` は、固定した最終 target に対して gate-blocking が一つも残らず、双方の最終記録が同じ対象版を承認している状態とする。`指摘撤回` だけは残っていてよい。指摘を修正せずに進めるユーザーの明示的 waiver は、対象 ID、理由、受容する影響、承認者を記録した `WAIVED` として扱うが、通常の `PASS` を満たさず、完了報告の代わりに停止・確認状態とする。指摘候補が0件の場合は、対象 identity、範囲、証拠、双方の no-findings の立場を含む空の共同最終記録を作成し、その同じ版を双方が承認する。全候補が撤回された場合は空の記録で代用せず、全固定IDと撤回理由、双方の withdrawal の立場を列挙した共同最終記録を双方が承認する。

## 実行順序

### 1. 実装と計画済み検証

承認済み計画に従って実装し、計画で定めた build・test・生成検証を行う。計画からの逸脱、見積り超過、追加設計判断が必要になった場合は、通常レビューや Advisor の前に停止して再承認を得る。

### 2. ユーザー通常レビュー（選択時）

`effective_user_review=REQUIRED` の場合だけ候補差分と検証結果をユーザーへ提示し、ユーザーの feedback を反映する。レビューした snapshot の identity、提示内容、snapshot に結び付いたユーザーの明示的な承認・変更なし、または各 feedback の解消確認を含む応答、未解決 feedback がないことを台帳へ記録し、内容変更後は検証と通常レビューの証拠を更新する。計画範囲、設計、リスク、見積りを変える feedback は既存の承認ゲートへ戻す。`effective_user_review=REQUIRED` で通常レビュー完了の証拠がないまま Advisor や `rigorous-review` を開始してはならない。`effective_user_review=NONE` の場合は、ユーザー通常レビューを `SKIPPED` とした理由、根拠、指定元を台帳へ記録する。

`effective_user_review=REQUIRED` の通常レビュー完了、または `effective_user_review=NONE` の `SKIPPED` 記録後に candidate target を固定する。レビュー済み snapshot（`REQUIRED` の場合）と target の内容が同一であることを base SHA、tree/commit identity、hunk または Commit map manifest で検証し、commit topology 自体が意味を持つ場合は、`REQUIRED` なら commit 後の target を通常レビュー対象として再確認し、`NONE` なら通常レビューを復活させず target identity と topology の照合だけを行う。

### 3. レビュー強度の確定

candidate target を固定した直後に、`requested_review_level` と必須トリガーを照合して `effective_review_level` を確定する。`effective_user_review` は preflight で解決した値を引き継ぎ、選択値が `NONE` でも、必須 Advisor トリガーまたは明示的な `rigorous-review` 指定があれば AI レビュー側の下限を適用する。Advisor または `rigorous-review` を含まない場合は、当該レビューを `SKIPPED` とした理由、根拠、ユーザーまたは goal の契約を台帳へ記録する。`SKIPPED` は検証、選択された通常レビュー、承認の完了を意味しない。

### 4. 最終 Advisor 判定

`effective_review_level` が `ADVISOR` または `FULL` の場合、`effective_user_review=REQUIRED` なら通常レビュー後、`NONE` なら通常レビューを省略して固定した candidate target に対して、Advisor を dispatch する直前に epoch identity を再検証してから固定した計画と対象を渡す。必須トリガーがある場合は `REQUIRED` として扱い、`REQUIRES_USER_DECISION` または `BLOCKED` なら停止する。`UNRESOLVED` で Advisor を実行できない場合も停止してユーザーへ報告する。`effective_review_level` に Advisor が含まれない場合、全トリガーが根拠付きで false であることを確認し、Advisor を `SKIPPED` と記録する。最終 Advisor の結果は、追加 checkpoint の結果やユーザー通常レビューの承認で代用してはならない。

### 5. 厳密レビュー

`effective_review_level` が `RIGOROUS` または `FULL` の場合、`effective_user_review=REQUIRED` なら通常レビューと必要な最終 Advisor 判定を記録し、`NONE` なら通常レビューを `SKIPPED` と記録したうえで、固定した当該 epoch の candidate target に対して `rigorous-review` を明示的に呼び出す。レビュー者と回答者を同時実行せず、同じ対象 identity と台帳を使う。`effective_review_level` に rigorous-review が含まれない場合、厳密レビューを `SKIPPED` とした理由、根拠、契約を台帳へ記録する。厳密レビュー自身の台帳、確認点、停止条件を上書きしない。

### 6. 指摘の修正

- すべての `指摘成立` は、影響度や修正要否に不同意が残っていても gate-blocking として扱い、承認済み範囲内でまとめて修正する。レビュー者・回答者に修正や commit をさせない。修正しない場合は対象 ID ごとの明示的なユーザー waiver を `WAIVED` として記録し、PASS にしない。
- 修正後に計画で定めた build・test・生成検証を実行する。計画からの逸脱、見積り超過、追加設計判断が必要になった場合は停止して再承認を得る。
- 修正、fixup、amend の後は、変更後 snapshot に対する旧 epoch の通常レビュー結果を再利用せず、まず新しいレビュー epoch を開始する。新 epoch でレビュー契約を再解決し、その `effective_user_review=REQUIRED` なら変更後 snapshot に対するユーザー通常レビューを実施して提示内容、ユーザー応答、未解決 feedback がないことを台帳へ記録し、`NONE` なら通常レビューを実施せず `SKIPPED` 記録を更新してから、次の Advisor 判定または `rigorous-review` へ進む。
- 修正を対応する実装コミットへの fixup として記録する。計画またはユーザーが操作名 `amend` と対象コミットを明示して承認した場合だけ、そのコミットを amend してよい。「一つのコミットを維持する」という指定だけでは amend してはならない。

### 7. 新しいレビュー epoch

修正、fixup、amend、履歴整理、または epoch identity の意味のある変更のいずれでも、旧 epoch の厳密レビュー結果を再利用してはならない。対象 manifest、SHA、計画 identity、epoch identity を再検証して新しい epoch を開始し、旧 epoch の通常レビュー結果や契約を新しい target に先に適用してはならない。新 epoch のレビュー契約を解決した後は、`effective_user_review=REQUIRED` なら変更後 snapshot の通常レビューを完了し、`NONE` ならその `SKIPPED` 記録を更新する。`effective_review_level` が rigorous-review を含む場合は、既知の指摘の解消確認だけで済ませず、変更後のコミット範囲全体を `rigorous-review` で再確認する。Advisor は下記の比較条件を満たす場合を除き、最終 candidate target に対して再実行する。

新しい epoch ではレビュー契約と Advisor の要否トリガーを必ず再評価する。前回の `NOT_REQUIRED` または最終 Advisor の `REQUIRED/CLEAR` を再利用する場合は、計画 hash/commit、承認状態・範囲・制約、requested/effective `user_review` と `review_level`、旧 target と新 target の差分が記録済み指摘の修正だけであること、新規パスや無関係な hunk がないこと、epoch identity に含まれる全実行・統制要素（実効モデル・役割・推論予算、permission・sandbox、routing、tool/plugin の設定・利用可能範囲、関連する `AGENTS.md`・`SKILL.md`・agent 定義の版）が old/new で同一、または各要素について比較証拠付きで意味同値であること、統制規則・権限・データ・互換性・rollout・rollback・役割独立性に関する前提が不変であることを比較証拠付きで確認し、要否と結果を新 target に対して再検証する。前回の Advisor 状態を再利用する場合も、台帳へ `assessment_mode: revalidated-reuse`、参照元 epoch、old/new target、delta manifest、比較結果、追加 checkpoint の累計回数を記録する。一つでも不一致、識別不能、比較不能、レビュー契約の変更、または前提・対象範囲・規範的意味の変化がある場合は、最終 candidate target に対して必要なレビューを再実行し、Advisorを省略できない場合に実行できなければ `BLOCKED` またはユーザー確認で停止する。旧状態を無検証でコピーして `NOT_REQUIRED`、`CLEAR`、または `SKIPPED` としてはならない。

## 完了条件

次をすべて満たしたときだけゲートを `PASS` とする。

- 計画 identity、承認済み範囲、対象 manifest、最終 target、最終化直前に再検証した epoch identity が一致している。
- 計画に定めた検証が成功している。
- `effective_user_review=REQUIRED` の場合は、最終 candidate target に結び付くユーザー通常レビューの snapshot、提示内容、明示的な承認・変更なし、または feedback 解消確認を含む応答、未解決 feedback がないことを台帳で確認できる。`NONE` の場合は、ユーザー通常レビューを `SKIPPED` とした理由、根拠、指定元を台帳で確認できる。
- `effective_review_level` が Advisor を含む場合は、最終 Advisor の実行結果が `CLEAR` である（比較証拠付きの `assessment_mode: revalidated-reuse` による `CLEAR` の再検証を含む）。Advisor を含まない場合は、必須トリガーがすべて根拠付きで false であり、Advisor を `SKIPPED` とした理由が記録されている。
- 追加 Advisor checkpoint の累計がゲート全体で最大2回以内で、各 checkpoint の理由・判断質問・対象・結果が記録されている。
- `effective_review_level` が rigorous-review を含む場合は、`rigorous-review` の `指摘成立`、`指摘撤回`、`不同意確定`、`調整不能` の全固定IDが共同最終記録で確定し、`指摘成立`、`不同意確定`、`調整不能` が残っていない。rigorous-review を含まない場合は、厳密レビューを `SKIPPED` とした理由が記録されている。実行した場合、指摘ゼロの場合は対象 identity に結び付いた空の共同最終記録を、全撤回の場合は全固定IDと撤回理由を含む記録を双方が同じ版で承認している。
- 初回コミットと fixup・amend の範囲が、計画で承認された変更だけで構成されている。
- Commit map が必須の計画では、actual commit/hunk manifest と map を双方向に完全照合し、全 commit/hunk がちょうど一つの単位へ割り当てられ、map にない変更や重複がない。独立 rollback 単位は commit 境界で分離し、依存により同一 commit に結合する場合は理由と共同 rollback 範囲を map に記録している。
- ユーザーの実装採否、本番採用、履歴書き換え、push、PR・Issue 更新、外部送信が必要な場合は、それぞれの既存承認を別途取得している。

PASS 後に epoch identity のいずれか（計画 identity・承認状態、base/target、対象 manifest、除外範囲、実効モデル・役割・推論予算、permission・sandbox、routing、tool/plugin の設定・利用可能範囲、またはレビューに固定したゲート統制ファイル（`AGENTS.md`、`SKILL.md`、agent 定義）の版）に意味のある差異、識別不能、または比較不能が生じた場合、レビュー契約が変化した場合、または `effective_user_review=REQUIRED` のユーザー通常レビューの snapshot・提示内容・応答・未解決 feedback・承認状態が変化（新規 feedback、未解決化、承認撤回を含む）した場合、PASS は無効になり、対象 identity・除外範囲・epoch identity・選択された通常レビューの証拠を再検証して最終 target から新しい epoch を開始する。`effective_user_review=NONE` の場合も、その指定の根拠が変化したときは同様に扱う。無関係な環境変更や意味同値の整形は、固定した対象と規範的意味に影響しない根拠を記録できる場合に限り除外する。squash・rebase は別操作として扱い、実行後に対象 identity と差分を検証する。

## 停止・確認条件

次の場合は自動継続せず、状態、証拠、残っている指摘、次の選択肢をユーザーへ報告する。

- 同じ指摘への修正が2回失敗した、epoch が3回に達した、または `rigorous-review` の確認点に達した。
- 計画範囲、計画 identity、見積り上限、対象 manifest、fixup target が一意でなくなった。
- 既存 dirty 差分を安全に除外できない、対象がレビュー中に変化した、または build・test・生成検証が失敗した。
- `effective_user_review=REQUIRED` なのに当該 epoch のユーザー通常レビューが完了していない、snapshot に結び付く明示的承認・変更なしまたは feedback 解消確認がない、未解決 feedback が残っている、追加 Advisor checkpoint が `CLEAR` 以外（`BLOCKED` を含む）を返した、または追加 Advisor checkpoint の3回目が必要になった。`effective_user_review=NONE` の場合に `SKIPPED` の根拠を記録できないときも停止する。
- `user_review` または `review_level` の入力元・値が不明、必須の Advisor 下限と衝突している、明示的な `rigorous-review` 指定を無効化しようとしている、または選択したレビューを `SKIPPED` とする根拠を記録できない。
- Advisor がユーザー判断を要求した、レビューの独立性・台帳の真正性を確認できない、`指摘成立`・`不同意確定`・`調整不能` が残っている、または `WAIVED` を選択した。

これは失敗を隠すための waiver ではない。継続、範囲変更、追加証拠、免除、終了の判断をユーザーに委ねる。

## 最終報告

比較基準と最終 target の SHA、対象・除外状態、計画 identity、requested/effective `user_review` と `review_level` および各入力元、選択されたユーザー通常レビューの証拠または `SKIPPED` 理由、Advisor 状態と追加 checkpoint 累計、各 review epoch の結果、fixup・amend の一覧、Commit map の照合結果、検証結果、未解決の不同意・`WAIVED` または停止理由、外部操作を行っていないことを簡潔に報告する。レビュー結果とユーザーの採否判断を混同しない。
