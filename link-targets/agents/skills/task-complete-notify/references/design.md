# Task-complete notification: design record

この文書は、`task-complete-notify` の現在の契約と、採用理由を対応付けるための設計記録です。
利用手順と実行時の安全境界は、親文書の [`SKILL.md`](../SKILL.md) を正本とします。

## 現在の不変条件

- arm の入力からは、standalone なUUID候補を正規化し、異なる候補が1件だけのときだけ対象を確定する。同じUUIDの繰り返しは許可する。
- canonical URIは `codex://threads/<UUID>`。legacy形式、余分なpath/query/fragmentは拒否する。
- relaxedなUUID抽出は外部arm入力だけに適用し、hook・transcript metadata・state・watcherの内部値はstrict parserで完全一致検証する。
- arm前に、現在のプロセスが選択しているCodex homeの `session_index.jsonl` と、同homeのactive rollout先頭 `session_meta` を照合する。`id == session_id == target`、`thread_source == user`、親なしを満たさなければstateを作らない。
- runtime stateは実行時に解決した `$CODEX_HOME\.task-complete-notify` に置く。`CODEX_HOME`未設定時だけユーザープロファイルの`.codex`を使う。
- `armedAtUtc` はarm時にrequestへ記録する唯一の有効期限基準で、`armed`だけに固定24時間TTLを適用する。欠落・不正・オーバーフローはfail closedで期限切れとし、arm・Stop・watcherの関連経路がlazyにrequestを先に削除し、checkpointをbest-effortで後処理する。checkpoint側の時刻でTTLを延長しない。
- `attempting`はTTL掃除の対象外で、Stopの送信・terminal化を妨げない。期限切れrequestは通知処理へ渡さず、ロック競合時は次回scanで再試行する。
- cancelは明示対象のthreadに対してcoordination lock→per-thread lockの順で状態を再読込し、`armed`だけをrequest先・checkpoint後の順に削除する。`attempting`は削除せず`too_late`、ロックまたは状態が不確定なら`busy`、不在・期限切れ・消費済みなら`Ok=true, Status=not_armed`を返し、terminal/tombstoneは作らない。cancelはactive ownershipを再検証せず、実行時点のgenerationに対する操作とする。
- Stop hookを第一検出器、JSONL watcherを明示的なfallbackとし、両方を独立senderとして有効化しない。
- JSONL watcherはLFをrecordのcommit boundaryとして扱う。LF済み行のstrict
  UTF-8/JSON解析失敗はappend-only writer契約下の恒久破損としてcursorを
  `NextOffset`まで進め、破損内容を保持・出力しない。LFのない末尾partial
  lineだけを次回scanへ残す。writerがLF後に同じbyte rangeを書き換える証拠が
  得られた場合は、この方針を再評価してからcheckpoint schemaを変更する。
- Stop hookは同期呼出しだが、thread lock 10秒＋notifier child 35秒＋後処理マージン5秒＜helper wrapper 55秒＜hook設定上限90秒の階層に固定する。notifierのHTTP設定はconnect timeout 10秒とoperation inactivity timeout 20秒であり、HTTP全体の上限とは扱わない。失敗してもturn結果は変更せず、非同期workerは導入しない。
- stdinは各境界で標準入力ストリームを明示的なUTF-8 `StreamReader`として読み、`Console.InputEncoding`の変更やコンソール接続を前提にしない。
- 1 generationにつき送信APIを1回だけ試行し、結果はterminal stateへ消費する。retryや自動再送は行わない。
- state、stdout/stderr、hook outputにはtopic、秘密、raw arm input、prompt/response、thread title、repository pathを保存・出力しない。
- hookやwatcherを有効化する前に、対象セッションで実際に選択されるpermission profileとsandboxの組み合わせをcanaryで確認する。必要な権限は同homeのsession index/transcript読取、同home state rootへの限定書込、`ntfy.sh`へのHTTPS通信に絞り、skillはCodex設定を自動変更しない。

## 判断理由

### UUIDを最初の一致で採用しない

Codexのログ、Markdown、引用文には複数のUUIDが混在し得ます。最初の一致やcanonical URI優先では、別threadを黙って選択する危険があります。そのため、同じUUIDの反復だけを重複排除し、異なるUUIDが複数あれば `thread_ambiguous` として停止します。

UUIDにASCII英数字・underscore・hyphenが直結した部分一致も候補にしません。入力全体が大きくなり過ぎないようarm入力はUTF-8 4 KiBに制限し、抽出元の全文は保持しません。

### strict parserとarm extractorを分離する

hookやstateの値まで部分一致にすると、壊れたmetadataや改変されたstateから別のUUIDを拾う可能性があります。したがって、外部入力には `Extract-ArmThreadId`、内部境界には厳格な `Normalize-CodexThreadId` を使い分けます。

### stateをCodex home単位に分ける

skill checkout内の共有stateでは、`.codex`と`.codex-personal`を同時に使ったときにrequest、watcher lock、checkpointが衝突します。Codexが実際に使っているhomeからstateとsessions rootを同時に導出すれば、homeごとの常駐watcherを独立させられます。

stateディレクトリはインストール時には作らず、対象が現在のhomeで管理されていることを確認したarm後にだけ作ります。未知のhomeや未知のUUIDを試しただけで新しいruntime directoryを増やさないためです。

`CODEX_HOME`はプロセス環境からのみ選びます。別homeを入力値から推測したり、WSL envelopeで任意homeを上書きしたりしません。WSL側が現在のセッション環境を継承できない場合は、誤ったhomeへの登録を避けるため失敗させます。

### request-owned TTLとlazy cleanup

予約が未来のturnを待つ間も、常駐workerや再送機構を追加せずに上限を設けるため、arm時刻から24時間の絶対TTLを採用します。requestの `armedAtUtc` だけを判定に使い、checkpointのコピーや欠落した時刻を補助値として扱うと、古いcheckpointによる延命や不明な時刻からの送信を防げます。期限判定はarm・Stop・watcherの既存実行点に限定し、期限切れのrequestを論理的に無効化したうえで物理削除します。削除はrequestを先に行うため、checkpointの残骸だけではwatcherが通知対象を再構成できません。

### LF済みmalformed行の扱い

JSONL fallbackは単調な単一cursorでrolloutを走査する。LFをrecordのcommit
boundaryと定義するappend-only writerでは、LF済みでstrict UTF-8またはJSON
解析に失敗した行は恒久破損であり、直ちに破棄して後続recordの検出を妨げない。
解析失敗位置を永遠に再試行すると、その行の後ろにある正常な
`task_complete`までstarveさせるため、retry-foreverは採用しない。raw bytesや
decoded textをstateに保存せず、checkpointには既存のpath/offsetだけを残す。

この判断はrollout writerがLF済み範囲を更新しないことを前提とする。もし
writerの実装またはtraceがその前提を否定する場合は、同一範囲・失敗回数を
再起動後も保持するbounded retry/discardへ再設計する。その場合も、破損内容を
保存・出力せず、失敗回数を観測回数として明示する。

### cancelの線形化

cancelは新しい状態機械を作らず、arm/Stop/watcherが既に共有するcoordination lockとthread lockを同じ順序で取得します。ロック下で `armed` を再確認してからrequestを削除するため、Stopの`attempting` claimと無条件のファイル削除が交差しません。ロック取得が間に合わない場合はrequest本文を二度読みして安定性を確認しますが、安定した `attempting` 以外は安全側に`busy`とします。thread単位の明示cancelなので、呼び出し間の再armを世代トークンで拘束せず、後続のcancelがその時点のgenerationを対象にする制約を契約として残します。

### indexとtranscriptを二重に確認する

`session_index.jsonl`は同じhomeの候補を高速に絞るために使いますが、indexだけではrolloutの正当性を確認できません。最終判定はactive rolloutの先頭 `session_meta` とし、root user sessionであることを確認します。filename一致だけの判定や、archived rolloutの受理は行いません。

### `references/design.md`をREADMEの代わりに使う

`SKILL.md`は呼び出し方と現行契約に集中させ、採用理由・却下案・証拠・保守条件はこの設計記録に分離します。READMEを別に複製すると利用手順と契約が陳腐化しやすいためです。

このファイルにはローカル絶対path、ユーザー名、実UUID、thread名、prompt/transcript内容、topic、credential、private configの値を記録しません。Issueはprovenance linkとして参照しますが、Issueが読めなくても現行判断が理解できるよう要約を自足させます。

### 診断スクリプトを本番経路から分離する

端末表示の比較用スクリプトは、実ntfy publishを行うため本番のadapter・hook・watcherから分離し、`scripts/diagnostics/`に置きます。これらは受入経路から自動起動せず、明示的な表示確認でだけ実行します。ランダム値以外のmessage、topic、prompt、responseは扱いません。

## 検証と保守

仕様を変更するときは、次を同じ変更として扱います。

1. `SKILL.md`の現行契約
2. `scripts/`のadapter・検出器・sender、および`scripts/diagnostics/`の診断資材
3. `tests/task-complete-notify.tests.ps1`の受入条件
4. この設計記録の不変条件・判断理由
5. GitHub Issue #3の本文と判断履歴コメント

最低限、入力抽出の曖昧性、wrong-home拒否とstate未作成、homeごとのlock分離、Stop/watcherの一回性、24時間TTLと不正時刻のfail-closed掃除、cancelとStopの競合、watcherの自然終了、秘密値非漏洩を再検証します。
JSONL watcherの完全行破損については、invalid JSON/UTF-8の後続にある正常な
`task_complete`、checkpointの再起動永続性、破損内容の非出力、LFなしpartial
lineの再試行を受入テストで確認します。

## 根拠リンク

- [GitHub Issue #3: notification-skill](https://github.com/the9ball/.dotfiles/issues/3)
- [Issue #3 initial process-reuse draft](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5628328226)
- [Issue #3 final contract discussion](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5629234932)
- [Issue #3 implementation and verification record](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5630098951)
- [Issue #3 review-response policy](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5632941893)
- [Issue #3 live-canary result](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5633214614)
