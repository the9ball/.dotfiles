---
name: approval-request-workflow
description: 次の自走区間に必要な明示的 permission または judgment を discovery と handoff するときに使う。無関係な実行では発動しない。
---

# Approval request workflow

## Discovery contract

- Positive trigger: 実行を進める前に明示的な permission または judgment の discovery が必要になる。
- Negative trigger: 承認要求がなく、通常の build・test・review だけを実行する。
- Conditional dependency: external-operation-authorization Skill は認可境界の責務が発生した場合だけ適用する。再設計材料は本 Skill 内の非runtime Design section に含まれ、通常 runtime では適用しない。
- Failure mode: 必要な依存契約を解決できない場合は推測で代替せず、fail-safe に停止して報告する。

## Runtime contract

この Skill が discovery されたときだけ、下記の Guide section を normative contract として適用する。条件付き依存は必要な場合だけ読み込み、解決不能なら推測による代替や silent omission をせず fail-safe に停止する。

実行 authorization の共通契約は link-targets/agents/skills/external-operation-authorization/SKILL.md を責務が発生した場合だけ適用する。runtime workflow の設計判断を再検討するときは、本 Skill の非runtime Design section を参照する。

## Guide

実行前に必要な承認要求を discovery・集約し、回答を解釈して execution へ handoff するための portable な runtime contract。
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

設計変更や workflow の再設計では下記の非runtime Design section を参照する。これは runtime contract を変更せず、通常 runtime では適用しない。


## Design (nonruntime)

This section preserves design rationale, alternatives, and non-normative scenarios for future redesign. It is not loaded as a runtime contract and does not change the Guide section above.

approval-request-workflow Skill の runtime contract に関する設計理由、責務境界、却下した alternative、判断補助 scenario を記録する。
通常 runtime では不要で、workflow の編集・再設計・不確実な判断・review 時に参照する。この section の scenario は非規範的であり、Guide と矛盾する場合は Guide を優先する。

### 設計意図

#### discovery は「次の自走区間」に限定する

plan 全体を strict serial に承認してから実行する方式は、まだ実行状態が確定していない将来区間の承認を早期収集し、不要な中断や stale な判断を増やす。そのため discovery は次の自走区間を開始するため現在必要な承認へ限定する。

「自走区間」は独立 state ではない。最大区間を計算する仕組みを作ると workflow が実行 planner を所有してしまうため、合理的な停止理由の判断は applicable rules と agent に残す。

#### collection は batching であって permission boundary ではない

複数の独立した approval item を一度に提示できると往復を減らせるが、collection を一つの承認境界にすると既存 authorization contract を侵食する。そのため collection / prefix / ID は表示と回答追跡だけを担い、各 approval item の permission semantics は既存規則に残す。

collection を「全回答が揃った時」に閉じると、回答後・handoff 前に判明した item を不自然に別 collection へ分ける。execution への handoff を close point とすることで、approval phase のまとまりと実行境界を一致させる。

#### ID は軽量な会話上の identity に限定する

runtime ID は初回提示時に割り当てる。未提示 candidate に先に番号を振ると、plan candidate の形式や永続管理まで workflow が所有しやすくなるためである。

ID の維持は semantic identity の追跡に役立つが、authorization の有効性を証明しない。内容更新後の approval applicability、permission boundary、消費等は既存所有者が判定する。

#### reconstruction は collection history を復元しない

execution continuity を保証できない状態で古い collection を復元すると、表示 state の再現を permission state の復元と誤認しやすい。current remaining work から再 discovery して新 collection を作る一方、独立して有効な既存 approval は通常の判定で維持する。

### 責務境界

approval-request workflow は「何を今ユーザーへ判断依頼するか」と「その回答をどの runtime item に作用させるか」を所有する。

一方、以下は所有しない。

- valid approval の成立条件と semantic authorization boundary
- approval の実行時有効性、消費、retry、read-back、結果記録
- review evidence、revision / review epoch、execution lifecycle
- plan 上の approval candidate の生成、専用 section、format、identifier
- GitHub / Issue maintenance 全体の外部操作モデル

この分離により、workflow 上の identity / lineage と execution authorization を自動写像しない。

### 却下した alternative

- **plan 全体の strict serial**: 将来状態まで承認収集対象にして実行を不必要に止めるため採用しない。
- **将来区間の承認の先取り**: 早期認識だけを理由に現在区間を中断すると stale / unnecessary approval を増やすため採用しない。
- **承認待ち中の replay-safe work 特則**: 並行実行の一般規則をこの workflow が上書きするため採用しない。
- **plan candidate の固定形式・番号付け**: plan authoring の責務を侵食するため採用しない。
- **workflow 独自の revision/hash/state store**: authorization / review lifecycle と重複し、軽量な表示 workflow を越えるため採用しない。
- **resume 時の既存 approval 一律再取得**: 独立して有効な approval まで無効化するため採用しない。

### 非規範 scenario

#### 同じ開始境界に複数の独立承認がある

次の実行区間に公開操作と別の権限判断が必要なら、`A1`、`A2` として同じ collection に提示できる。ユーザーが `A1だけOK` と答えた場合、`A2` を推測せず pending のまま扱う。両 item の authorization semantics はそれぞれの既存規則が判定する。

#### handoff 前に追加 item が判明する

`A1` の回答後、execution へ handoff する前の再評価で別承認が必要と分かった場合は `A2` として同じ collection に追加する。必要承認が満たされて handoff した後に新しい need が判明した場合は `B1` から新 collection を開始する。

#### 拒否後に alternative を選ぶ

`A2` が拒否され、その操作なしで目的を達成できる alternative に新しい承認が必要なら、handoff 前である限り同じ collection の次番号へ追加する。`A1` の既存 approval が alternative にも独立して applicable なら、workflow は再取得を要求しない。

#### 提示内容を更新する

未承認の `A2` が同じ unfinished logical operation のまま具体化された場合、同じ ID を維持して `更新: A2` と現在内容を全文提示できる。ただし、古い提示への遅延回答が新しい内容にも有効かは workflow ID から決めず、曖昧なら自動適用しない。

#### reconstruction が必要になる

execution state の連続性を保証できず current remaining work を再構築した場合、古い `A` collection を再現せず次 prefix の collection で discovery し直す。以前の approval が既存 authorization contract 上まだ applicable なら、それを workflow が失効させることはない。
