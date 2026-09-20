# 承認要求 workflow — design notes

companion runtime guide の設計理由、責務境界、却下した alternative、判断補助 scenario を記録する。
通常 runtime では不要で、workflow の編集・再設計・不確実な判断・review 時に参照する。本書の scenario は非規範的であり、runtime guide と矛盾する場合は runtime guide を優先する。

## 設計意図

### discovery は「次の自走区間」に限定する

plan 全体を strict serial に承認してから実行する方式は、まだ実行状態が確定していない将来区間の承認を早期収集し、不要な中断や stale な判断を増やす。そのため discovery は次の自走区間を開始するため現在必要な承認へ限定する。

「自走区間」は独立 state ではない。最大区間を計算する仕組みを作ると workflow が実行 planner を所有してしまうため、合理的な停止理由の判断は applicable rules と agent に残す。

### collection は batching であって permission boundary ではない

複数の独立した approval item を一度に提示できると往復を減らせるが、collection を一つの承認境界にすると既存 authorization contract を侵食する。そのため collection / prefix / ID は表示と回答追跡だけを担い、各 approval item の permission semantics は既存規則に残す。

collection を「全回答が揃った時」に閉じると、回答後・handoff 前に判明した item を不自然に別 collection へ分ける。execution への handoff を close point とすることで、approval phase のまとまりと実行境界を一致させる。

### ID は軽量な会話上の identity に限定する

runtime ID は初回提示時に割り当てる。未提示 candidate に先に番号を振ると、plan candidate の形式や永続管理まで workflow が所有しやすくなるためである。

ID の維持は semantic identity の追跡に役立つが、authorization の有効性を証明しない。内容更新後の approval applicability、permission boundary、消費等は既存所有者が判定する。

### reconstruction は collection history を復元しない

execution continuity を保証できない状態で古い collection を復元すると、表示 state の再現を permission state の復元と誤認しやすい。current remaining work から再 discovery して新 collection を作る一方、独立して有効な既存 approval は通常の判定で維持する。

## 責務境界

approval-request workflow は「何を今ユーザーへ判断依頼するか」と「その回答をどの runtime item に作用させるか」を所有する。

一方、以下は所有しない。

- valid approval の成立条件と semantic authorization boundary
- approval の実行時有効性、消費、retry、read-back、結果記録
- review evidence、revision / review epoch、execution lifecycle
- plan 上の approval candidate の生成、専用 section、format、identifier
- GitHub / Issue maintenance 全体の外部操作モデル

この分離により、workflow 上の identity / lineage と execution authorization を自動写像しない。

## 却下した alternative

- **plan 全体の strict serial**: 将来状態まで承認収集対象にして実行を不必要に止めるため採用しない。
- **将来区間の承認の先取り**: 早期認識だけを理由に現在区間を中断すると stale / unnecessary approval を増やすため採用しない。
- **承認待ち中の replay-safe work 特則**: 並行実行の一般規則をこの workflow が上書きするため採用しない。
- **plan candidate の固定形式・番号付け**: plan authoring の責務を侵食するため採用しない。
- **workflow 独自の revision/hash/state store**: authorization / review lifecycle と重複し、軽量な表示 workflow を越えるため採用しない。
- **resume 時の既存 approval 一律再取得**: 独立して有効な approval まで無効化するため採用しない。

## 非規範 scenario

### 同じ開始境界に複数の独立承認がある

次の実行区間に公開操作と別の権限判断が必要なら、`A1`、`A2` として同じ collection に提示できる。ユーザーが `A1だけOK` と答えた場合、`A2` を推測せず pending のまま扱う。両 item の authorization semantics はそれぞれの既存規則が判定する。

### handoff 前に追加 item が判明する

`A1` の回答後、execution へ handoff する前の再評価で別承認が必要と分かった場合は `A2` として同じ collection に追加する。必要承認が満たされて handoff した後に新しい need が判明した場合は `B1` から新 collection を開始する。

### 拒否後に alternative を選ぶ

`A2` が拒否され、その操作なしで目的を達成できる alternative に新しい承認が必要なら、handoff 前である限り同じ collection の次番号へ追加する。`A1` の既存 approval が alternative にも独立して applicable なら、workflow は再取得を要求しない。

### 提示内容を更新する

未承認の `A2` が同じ unfinished logical operation のまま具体化された場合、同じ ID を維持して `更新: A2` と現在内容を全文提示できる。ただし、古い提示への遅延回答が新しい内容にも有効かは workflow ID から決めず、曖昧なら自動適用しない。

### reconstruction が必要になる

execution state の連続性を保証できず current remaining work を再構築した場合、古い `A` collection を再現せず次 prefix の collection で discovery し直す。以前の approval が既存 authorization contract 上まだ applicable なら、それを workflow が失効させることはない。
