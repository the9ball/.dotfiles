# Task-complete notification: design record

この文書は、`task-complete-notify` の現在の契約と、採用理由を対応付けるための設計記録です。
利用手順と実行時の安全境界は、親文書の [`SKILL.md`](../SKILL.md) を正本とします。

## 現在の不変条件

- arm の入力からは、standalone なUUID候補を正規化し、異なる候補が1件だけのときだけ対象を確定する。同じUUIDの繰り返しは許可する。
- canonical URIは `codex://threads/<UUID>`。legacy形式、余分なpath/query/fragmentは拒否する。
- relaxedなUUID抽出は外部arm入力だけに適用し、hook・transcript metadata・state・watcherの内部値はstrict parserで完全一致検証する。
- arm前に、現在のプロセスが選択しているCodex homeの `session_index.jsonl` と、同homeのactive rollout先頭 `session_meta` を照合する。`id == session_id == target`、`thread_source == user`、親なしを満たさなければstateを作らない。
- runtime stateは実行時に解決した `$CODEX_HOME\.task-complete-notify` に置く。`CODEX_HOME`未設定時だけユーザープロファイルの`.codex`を使う。
- Stop hookを第一検出器、JSONL watcherを明示的なfallbackとし、両方を独立senderとして有効化しない。
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

最低限、入力抽出の曖昧性、wrong-home拒否とstate未作成、homeごとのlock分離、Stop/watcherの一回性、秘密値非漏洩を再検証します。

## 根拠リンク

- [GitHub Issue #3: notification-skill](https://github.com/the9ball/.dotfiles/issues/3)
- [Issue #3 initial process-reuse draft](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5628328226)
- [Issue #3 final contract discussion](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5629234932)
- [Issue #3 implementation and verification record](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5630098951)
- [Issue #3 review-response policy](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5632941893)
- [Issue #3 live-canary result](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5633214614)
