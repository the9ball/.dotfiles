# Issue #142：完了判定と検証範囲

## 今回の完了条件

2026-10-18の利用者指示に従い、別Windows実機での事前導入・動作試験は今回の必須完了条件から外す。
**別Windows実機：未実施・必要時に検証。** 隔離HOMEや同一ホストでの成功を別マシンの実績へ読み替えない。

今回の技術的な完了条件は、現行マシンでの機能・再起動後利用と、.dotfilesからの導入に必要なソース・手順・非破壊試験の整備。
push、PR、マージ、Issue Closeは別の操作であり、この文書やレビュー結果だけで実行を承認しない。

| 必須項目 | 判定と根拠 |
| --- | --- |
| Windows 11 / OpenSSH / Git Bashで専用DOCKER_CONFIGを使用 | PASS。B1恒久配置とGit Bash実測 |
| 秘密を平文またはBase64だけで永続保存しない | PASS。TPM保護鍵と暗号化ストア。秘密はHelperプロトコルのメモリ/pipeには存在する |
| get / store / erase / list、登録更新、破損拒否、同時実行 | PASS。既報の隔離ダミー検証。全障害条件への保証ではない |
| 新規公開鍵SSHで追加のPAT/PIN入力なし | PASS。再接続試験と実GHCR private pull |
| 再起動後GUI未ログオンでTPM資格情報取得 | PASS、F1。Engine不通時のpull未実施とは区別 |
| 同じ再起動後状態でSSHからEngine明示起動→private pull | PASS、G1/H1。Engine自動起動ではない |
| 実レジストリpush/pull | PASS、GHCRの承認済みprivate試験image。Docker Hub実認証は未実施 |
| 既存Desktop設定・Credential Manager・profileの保全 | 既存設定hashの保持と書込み経路の分離を確認。Credential Manager全内容を秘密取得して比較したという意味ではない |
| .dotfilesへのソース/公開chezmoi配布の統合 | ローカルコミット済み。通常applyは鍵・ストア・資格情報を自動初期化しない |
| 前提検査・ビルド・同版再適用・撤去/復旧方針 | スクリプト・文書あり。移植先ビルド、鍵なしCheckOnly、隔離HOMEのapply/reapply、限定撤去を検証 |
| 別マシンに既存ホストの秘密や鍵を持ち込まない | 端末別GUID/SID/pathで初期化。実データ・鍵・生成物をGit管理から除外し検査 |

実績：[G1](https://github.com/the9ball/.dotfiles/issues/142#issuecomment-6234689820)、[H1](https://github.com/the9ball/.dotfiles/issues/142#issuecomment-6234953430)、[.dotfiles統合](https://github.com/the9ball/.dotfiles/issues/142#issuecomment-6240984992)。
DesktopCommanderContainerのbuild・認証volumeを保持した差し替え・ChatGPT直接接続も既報PASSだが、TPM認証の別マシン実証とは区別する。

## 更新・復旧の実施済みと未実施

| 対象 | 実施した確認 | 未実施・制約 | 今回の追加試験 |
| --- | --- | --- | --- |
| 同版再適用 | ダミー実機lifecycleと隔離配置で再適用/無変更を確認 | READY再実行は選択settingsと配布ファイルの限定照合。vault等の完全性検査ではない | 不要。保証範囲をINSTALLに明示済み |
| 一時配置の無効化・撤去 | 試験配置でdisable、誤ID拒否、再配置、撤去 | 現在の恒久環境の撤去は実行しない | 不要。必要な環境を破壊する理由がない |
| 専用試験鍵の撤去 | 同一性照合、削除API成功、別照会の不存在 | すべての故障状態で削除できる保証はない | 不要。既存鍵を失う試験は完了条件ではない |
| TPM Helperの異版更新 | 別配置で検証しdeactivate→source→activateする手順を整備 | 異版in-place更新/自動migrationは未実装。実トークンを使った異版切替は未実施 | 対象版を導入するときに必要性を判断 |
| Desktop Commander差し替え | 新image ID、同じ認証/workspace volume、同じdevice ID、接続/機能を確認 | 元imageへ戻す実ロールバックは未実施。旧image保持と復旧設定の検査まで | 不要。現サービスを停止しての往復は今回の機能成立の証明に追加価値が小さい |
| TPM交換・OS再インストール・鍵喪失 | 復旧限界と新鍵/新tokenでの再初期化手順を記載 | 暗号文だけの復旧・鍵の移植は提供しない。実障害からの復旧は未実施 | 不要。TPMクリアや鍵破壊で試す機能ではない |

以上は今回の提供機能と受け入れ範囲に対する判断であり、未実施の復旧を成功扱いするものではない。
異版更新や実障害への対応時は、その対象・失敗条件・復旧可能性を改めて確認する。

## 今回の必須範囲外

- 別Windowsの事前実機試験：未実施・必要時に検証。
- EngineのWindows起動時自動起動。現行手順はSSHからの公式CLI明示起動。
- CurrentUser DPAPI障害自体の修復。調査記録は保全、根本原因未解決。2026-10-23にパスワードでのGUIサインインで復旧した手順は[SETUP.md](../SETUP.md#再起動後にアプリの再認証が毎回求められる場合)に記載。
- 非rootコンテナへの移行、すべてのexport形式や全ユーザー境界/全障害条件の検証。
- 既存恒久鍵の破壊、TPMクリア、現サービスの追加停止・実ロールバックによる試験。

## 将来の別マシン導入

担当モデルは [INSTALL.md](INSTALL.md)、[VALIDATION.md](VALIDATION.md)、実装とその時点の最新公式仕様を参照し、対象端末のWindows/OpenSSH/Docker Desktop/.NET/PCP、registry認証方式の差分を確認する。
以前の成功だけで採用せず、前提検査→隔離ダミー→端末別初期化→必要なSSH/再起動比較の順で必要性と承認範囲を決める。
新しい端末固有鍵と新しいtokenを使い、古い暗号文・秘密・SID・鍵識別子を移さない。

## 試験資格情報と残存物

GHCR専用credentialは消去済みで、getはnot-found、listは空。公開pullとランチャー・Desktop Commanderの継続は確認済み。
試験PATは利用者がGitHub側で手動削除済みと報告した。エージェントが削除APIやtokenの無効性試験を実行した結果ではない。
private pullの過去のPASSは維持するが、現在もGHCR認証済みであるとは記載しない。

試験packageとローカル試験imageは未削除。依存コンテナなしという既報と削除計画を維持し、削除は別承認とする。
これらは技術的な動作成立の未達項目と分けた後片付け事項であり、秘密を含むデータとしてGitに取り込まない。
恒久TPM鍵、Helper、専用環境、稼働コンテナと認証済みvolumeは保持する。

## 最終判定と承認候補

再定義された範囲では、必須の技術的未完了項目はない。別マシンや実障害復旧の未実施は上記の制約として残す。
追加の破壊的試験を行わず、ローカル差分と検証結果を最終レビューして公開手続きへ進める。
IssueのCloseは実行操作であり、レビュー完了と混同しない。

- ?1：ブランチpushとPR作成。対象ref/差分を固定して個別承認する。
- ?2：Issue #142のClose。利用者の判断と個別承認後に行う。
- ?3：試験packageとローカル試験imageの削除。直前のversion/参照/依存確認と別承認が必要。
- ?4：将来の別端末への鍵作成・token登録・実レジストリ/再起動試験や更新/復旧操作。その時点の対象と影響で承認を判定する。

今回の文書更新は実装コード0行、抽象化・依存・設定追加0。実環境に変更を加える作業は行わない。
