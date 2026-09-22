---
name: approval-request-workflow
description: 次の自走区間に必要な明示的 permission または judgment を discovery と handoff するときに使う。無関係な実行では発動しない。
---

# Approval request workflow

## Discovery contract

- Positive trigger: 実行を進める前に明示的な permission または judgment の discovery が必要になる。
- Negative trigger: 承認要求がなく、通常の build・test・review だけを実行する。
- Conditional dependency: authorization contract と非runtimeの design companion は必要な条件でだけ解決し、通常 runtime では複製しない。
- Failure mode: 必要な依存契約を解決できない場合は推測で代替せず、fail-safe に停止して報告する。

## Runtime contract

この Skill が discovery されたときだけ、下記の Guide section を normative contract として適用する。条件付き依存は必要な場合だけ読み込み、解決不能なら推測による代替や silent omission をせず fail-safe に停止する。

実行 authorization の共通契約は `link-targets/agents/guides/external-operation-authorization.md` を必要な場合だけ解決する。runtime workflow の設計判断を再検討するときだけ、非規範 companion の `link-targets/agents/guides/approval-request-workflow.design.md` を解決する。

## Guide

実行前に必要な承認要求を discovery・集約し、回答を解釈して execution へ handoff するための portable な runtime guide。
この workflow は新しい承認要件を作らず、既存承認の成立・有効性・permission boundary・消費・retry・read-back・review evidence・execution lifecycle を再定義しない。

### 基本原則

- 承認項目は、applicable な上位規則、guide、skill、ユーザー指示等により、現在の実行を自律的に進める前に明示的な permission / judgment が必要なものだけとする。process step、automatic review、checkpoint、build/test をこの workflow 自体が承認項目へ変換しない。
- workflow 上の collection、ID、lineage、semantic identity は表示・追跡用であり、承認状態、重要度、実行順、実行権限、permission boundary、有効性を表さない。
- 既存の applicable な承認・delegation が要件を満たす場合は再要求しない。成立・有効性・消費等は、それらを所有する既存規則で判定する。
- 「自走区間」は、新しい承認を取得せず継続できる実行範囲の便宜的な呼称であり、独立 state、ID、table、数学的な最大区間を持たない。合理的な停止理由がなければ不必要に細分化しない。

### 1. 次の自走区間に必要な承認を discovery する

利用可能な work context から、**次の自走区間を開始するため現在必要な承認**を合理的に特定する。

plan 等に approval candidate が存在する場合は must-check input として確認する。ただし authoritative / exhaustive な一覧とは扱わず、現在状態から必要性を再評価する。candidate の生成方法、heading、format、identifier はこの workflow では規定しない。

将来の自走区間を承認収集のためだけに全走査しない。将来区間の承認必要性を早期に認識しても、それだけを理由に現在区間を中断して先取り収集しない。

特定自体にユーザー判断や別の承認が必要なら、判明済みの範囲を提示して止める。

### 2. 独立したまま集約提示する

複数の approval item を一つの承認境界へ統合しない。各 item は独立したまま、一つの collection でまとめて提示できる。
各 item は対象・範囲・操作を判断できるよう簡潔に示す。条件、理由、不可逆性、公開範囲、権限、重要データ等が判断に重要な場合だけ補足する。

plan 等の approval candidate に由来する runtime item は provenance を示す。candidate に既存 identifier があれば使い、なければ既存 label / referenceable expression を使う。それも明確でなければ `（計画上の承認候補）` のような一般表示でよい。複数 candidate 由来でも multi-parent mapping は要求しない。

### collection と ID

- collection ごとに display prefix を持ち、`A..Z, AA, AB...` と進める。
- 同じ work unit 内では閉じた prefix を再利用しない。新しい work unit は `A` から始めてよい。
- runtime item ID は初めてユーザーへ提示するとき、display order に `A1`, `A2`, ... と機械的に割り当てる。
- 一度提示した ID は renumber / reuse しない。欠番を許容する。
- 同じ collection に後から追加する item は次の未使用番号を使い、表示位置によって既存 ID を変更しない。
- prefix と ID のための永続 state store は要求しない。

### 3. 回答を解釈し、必要なら再検討する

承認 workflow の提示では毎回 `回答対象` を明示する。対象がなければ `回答対象: なし` とする。

- 通常の無限定な肯定（例: `OK`, `進めて`）は、その時点で明示された `回答対象` 全体への肯定として扱う。ユーザーが限定・除外した指定を優先する。
- 通常の否定は、`回答対象` が1件ならその item の拒否として扱う。複数件なら対象を推測せず確認する。
- partial response では省略された item を承認・拒否と推測しない。未変更で既提示の item は、その後 ID だけで `回答対象` へ再掲してよい。
- 回答がどの提示内容を対象にしたか曖昧なら自動適用しない。

拒否によって次の自走区間へ入れない場合は、拒否された path を実行せず alternative を再検討する。handoff 前に alternative の新しい承認が必要なら同じ collection に追加する。代替不能なら進行不能として止める。再検討後も、他の取得済み承認が独立して applicable なら取り直さない。
### 更新・再提示・新規・撤回

- **更新**: 提示済み・未承認の同じ unfinished logical operation の提示内容を更新する場合、同じ ID を維持できる。更新と判断した次の提示で一度だけ `更新: A2` 等と示し、現在の承認内容を全文提示する。更新該当性の細かな分類は agent 判断とする。
- **再提示**: 拒否された同じ unfinished logical operation を再び判断対象にする場合は新しい ID を発行し、初回だけ `B1（A3の再提示）` のように直接の親を示す。内容更新も伴う場合は更新・再提示の両方が分かる表示にしてよい。祖先履歴は要求しない。
- **新規**: 統合・分割、完了/消費済み操作後の別操作、撤回後に再び必要になった操作、同じ unfinished logical operation か合理的に判断できないものは新規 item とする。不明な lineage を推測しない。
- **撤回**: 提示済み item が明示的拒否以外の理由で不要になった場合は `撤回: A2` 等を一度示す。拒否時に重ねて撤回表示しない。撤回した ID は復活させず、後で同種操作が必要なら新規 item とする。撤回だけの通知でも `回答対象: なし` とする。

ID の継続や更新・再提示表示は、既存 approval の実行時有効性を意味しない。

### 4. required approvals gate と handoff

次の自走区間を開始するために必要な承認が、既存の applicable rules に照らして満たされ、必要な再評価も終わったことを確認してから execution へ handoff する。

collection は全回答取得時ではなく、この handoff で閉じる。handoff 前に新しい approval item が判明した場合は同じ collection に追加する。handoff 後に新しい approval need が判明した場合は閉じた collection を再開せず、新しい collection を開始する。

### 自走区間の途中で新しい承認が必要になった場合

現在の自走区間を完了するため新しい承認が必要だと判明した場合、その承認が必要な操作には入らない。安全かつ整合した合理的な停止点まで進め、approval phase へ移る。

停止点へ着地する過程で自然に判明した approval candidate は利用してよいが、candidate を増やすためだけに実行を引き延ばさない。将来区間にだけ必要な承認を早期発見しても現在区間を中断せず、将来の境界で再 discovery する。専用 persistence store は設けない。

承認待ちの空き時間を理由に次区間の replay-safe work を先行する特則は設けず、並行実行の一般可否は既存規則に委ねる。
### reconstruction

compact や時間経過だけでは reconstruction としない。execution state の連続性を保証できず、memo / context 等から現在状態を再構築する必要がある場合に reconstruction とする。

古い collection は復元せず、current remaining work から必要な approval item を再 discovery し、新しい collection / 次 prefix を使う。同じ work unit なら `A` に戻さない。

reconstruction は既存 approval 自体を無効化しない。通常の既存判定で現在も applicable なら重複要求しない。

### 責務境界

この workflow が扱うのは approval need の discovery、runtime item への分割と集約提示、collection / display ID、`回答対象` と response interpretation、表示上の更新・再提示・撤回、rejection 後の reconsideration、execution への handoff、reconstruction 時の collection 再構築である。

次は既存の所有者へ委ねる。

- prior statement が valid approval として成立する条件
- semantic permission boundary の記録・判定
- approval の消費、retry、read-back、実行結果
- review evidence / revision epoch / execution lifecycle
- plan approval candidate の生成・format・identifier

設計変更、workflow の再設計、またはこの runtime guide だけでは判断が不確実な場合に限り、`link-targets/agents/guides/approval-request-workflow.design.md` を参照する。通常 runtime では参照不要であり、矛盾する場合は本 guide を優先する。
