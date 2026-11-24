# 通常SSH、psmux、Codexの共通Docker入口

Windowsの通常SSHとpsmuxのBashは、Routerを配置、公開した後、固定native `docker.exe`のディレクトリをPATH先頭に置く。

手動opt-inや毎回のactivationは不要。
同じペインで新しく起動したCodex、PowerShell、native子も通常のPATH検索で同じ入口を使う。

本書は導入手順を示すものであり、このPRが実ホストへの配置や実Docker利用に成功したという記録ではない。

## 経路と保証

`SSH → 既存psmux → Bash／Codex／native子 → 固定Router → selector検証 → 選択deploymentのdispatcher → launcher → 実CLI`。

Session 1が不在なら、従来のattach失敗後の直接Git Bashから同じRouterを使える。

- 配置先は `%LOCALAPPDATA%/Dotfiles/DockerRouter`。
`bin/docker.exe`を固定入口とし、公開後は更新の途中でも削除しない。

- `current.json`は固定PowerShell実体、そのhash、versionedなbootstrap payload、そのhash、既存selectorと公開bootstrapの場所を記録する。
秘密、endpoint、選択deploymentは保持しない。

- Router自身の配置、設定、runtime、bootstrapをACL/reparse/hash検査してからPowerShellを起動する。
既存Enterがselector、公開コピー一致、deployment、manifest、READYを検証する。

- 選択された既存0.5 dispatcherを絶対パスで起動する。
既存launcherの固定endpoint/config/helper、引数override拒否、READY検証を維持する。

- 親shellにはdeployment固有のDOCKER_CONFIG、helper root、認証情報をexportしない。
selector切替は次回呼び出しに反映され、進行中のコマンドは元の選択を維持する。

- 健全な固定入口へ到達した後の設定、配置、認証、Engine障害はDockerの非0終了となる。
通常Dockerを検索し直さず、shellやCodexを終了しない。
Engineの自動起動、token再登録はしない。

保証は、配置済みの健全な固定入口と継承PATHを使う呼び出しに限る。

別CLIの絶対パス、PATH置換、優先するalias/function、別rootやサービス、WSL、native呼出し元のapplication/current directoryによる別exe選択は対象外。WindowsがPATHより先に検索するシステムディレクトリ（System32、System、Windows）に別の `docker.exe` がある場合も、bare-nameのnative呼び出しはRouterを通らないため対象外とする。

固定入口そのものの欠落は不完全な配置であり、Bashは起動時に明確に異常を通知し、通常のdocker/docker.exeへ失敗guardを置く。
任意のnative子まで遮断できるとは扱わない。

既存bindingとの競合は上書きせず通知する。
`routing is NOT active`を成功と解釈しない。

## compose、buildx、Codex

基本対象は `docker ps/build`、`docker compose`、default builderによる `docker buildx build`、コンテナのlogs/restart等。

BUILDX_BUILDERは子だけでdefaultに固定し、BUILDX_CONFIGも選択deploymentの専用config配下へ固定する。

競合するBUILDKIT_HOST/BUILDX_CONFIG/別builder、明示--builder、buildxのbuilder管理、Bakeは拒否する。
独自remote builderは保証対象外。

compose/buildx pluginの発見場所と版、default builderが選択Engineへ到達すること、compose up --build等は実機受入で別々に確認する。

plugin不在を別CLIへのfallbackで補わない。
独自plugin/configの追加も別検証とする。

Codexの子環境フィルターがPATHを除外、置換する場合は、その実効設定を確認する。

Routerへ到達できることと、sandboxからdeployment、named pipe、TPM helperへアクセスできることは別の条件。

sandboxの無効化、方式変更、権限拡大は導入に含めない。
失敗を通常sandboxでの成功と報告しない。

## 導入順序

通常のchezmoi適用はRouterをビルド、配置、公開しない。

`published`がない間は、起動コードの変更後も従来のManaged bootstrap分岐を維持する。

そのため、参照中のcheckoutで開発しても、未配置のRouterへ新規SSHを切り替えない。

公開は初回導入時の状態遷移であり、毎回の利用者opt-inではない。

1. ソース、CI、独立レビューを確認する。
既存接続、作業、復旧資料を保持する。

2. 新しい出力先に公開packageをビルドする。
明示的なPowerShell 7.5以上で `Build-DockerRouter.ps1 -OutputRoot <new-absolute-directory>` を実行する。

3. 同じPowerShellから `Install-DockerRouter.ps1 -PackageRoot <package>` を実行してCheckOnlyを確認する。
鍵、ストア、Engineは触らない。

4. **実ホスト配置と新規領域ACLへの別承認後だけ**、同コマンドに `-Execute` を追加する。
既存ACLは変更しない。
配置、hash、staged healthの確認後、最後に`published`を作る。

5. 新規ペインで両コマンドの解決先、通常shell継続を確認する。
新規SSHのattachと、そこから起動するCodexの子を確認する。

6. 必要な実Docker操作は対象と影響を別承認して実施する。
それまで実Docker／認証は未検証とする。

公開後は、残る `DOTFILES_DOCKER_SSH=required`を旧bootstrapへ渡さない。
DOCKER_SSH_MANAGEDやPSMUX_SSH_AUTOATTACH=0を新たに設定しない。

利用者が明示した既存のattach bypassは解除しない。

壊れた、読めない、ディレクトリ化した`published`が存在しても、旧required経路へ戻さずDocker側を失敗させる。

Router用overlay自体が欠落しても、既存publicationを検出した場合は旧bootstrapを抑止し異常通知する。

## 更新と既存ペイン

selector切替にペイン再起動は不要。
ただし旧親環境に別deploymentのconfig/helper指定が残る場合は競合として拒否する。

公開bootstrapを更新するときは、対応するhash付きRouter payloadもレビュー、更新する。
同期不一致はDocker失敗となる。

installerは旧current.jsonをbackupし、payloadを新規配置してからcurrent.jsonを置換する。
公開markerと固定exeを削除しない。

固定exe本体が異なるpackageはinstallerが拒否する。
本体更新には実行中Routerの有無を確認する別の保守、承認が必要。

既存ペインへSSH再接続しても環境は変わらない。
自然なペイン交代を優先する。

既存ペインを明示更新する場合も別承認とし、進行中コマンドがないことを確認する。
旧Managed環境はそのshell自身が保持する復元状態だけを使い、他者の変数を一括解除しない。

起動済みCodexやnative子は親の変更を遡及継承しない。
作業を維持し、自然な終了後に更新済みペインで起動する。

psmux server、Startup、monitor、再作成要求は変更せず、既存ペインを強制再作成しない。

## ロールバック

公開後にmarkerだけを削除すると旧requiredのshell終了契約が戻るため、ロールバック手段にしない。

対応する旧current.jsonとpayloadをhash、ACL確認後に戻し、固定入口は保持する。
既存プロセスの環境は変更しない。

コード全体を戻す場合は、旧起動コードとの組合せ、新規接続への影響を確認する別の承認が必要。

Routerを使用中のペインがある間は固定exeやpayloadを削除しない。
旧deployment、鍵、vault、backup、復旧資料は保持する。

## 合成試験と未検証事項

`tests/DockerRouter`は本番Router制御フローをリンクし、runtime/bootstrap/dispatcherをinertなnative子に置換する。

ACL検査はfixture用の存在/reparse検査へ置換し、ACLを読み書きしない。
これを実ACL、実PowerShell bootstrap、Docker、TPMの成功と扱わない。

`--shells`は実Bash、PowerShellから通常docker/docker.exeを呼び、実`.bashrc`の未公開／公開済み／設定破損を合成HOMEで確認する。

Windows CIでは本番Routerをビルドし、このfixtureと既存のACL不要回帰を実行する。

Codex通常sandboxからの子起動、実SSH attach、plugin発見、build/compose/default builder、実認証は、実際の結果が記録されるまで未検証である。

