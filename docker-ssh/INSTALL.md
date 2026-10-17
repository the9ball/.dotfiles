# Windows 11への導入・更新・撤去

対象はWindows 11 x64、Docker DesktopのLinux Engine、Windows OpenSSH server、Git for Windows Bash、TPM 2.0 / Microsoft Platform Crypto Provider。
Docker DesktopとOpenSSHの初期導入・SSH公開鍵登録は端末管理者が公式手順に従って行う。このモジュールはサービスやWindows認証設定を変更しない。

## 前提検査とビルド

PowerShell 7.4以上、.NET 10 SDK/runtime、Git for Windows、Docker CLIが必要。
検証harnessにはNode.js 22以上とchezmoiが必要。依存を自動インストールしない。
`global.json`は安定版10.0.100以上・latestFeature、preview不可。配布物はframework-dependent 0.4.0で.NET 10 runtimeが必要。
管理ツールを含め、この移植のプロジェクトに外部NuGet package参照はない。

Git Bashから信頼した.dotfilesチェックアウトのルートで実行する。

`````bash
cd "$HOME/.dotfiles"
pwsh.exe -NoProfile -File docker-ssh/scripts/Test-TpmPrerequisites.ps1 -Purpose Test
`````

Ready=falseなら停止する。TPM状態UNKNOWNは管理情報の読取り権限不足の可能性があり、鍵利用可能の証明ではない。
PCP provider open成功も鍵作成・無人利用の証明ではない。実機初期化の用途・ACL・UI検査が最終ゲートになる。

chezmoiの通常適用は公開ファイル4個だけを追加する。この機能だけ適用する場合も既存設定に従いdiffを確認する。
全体applyには他機能のインストールhookがあるため、この機能だけを選ぶ例ではhookを除外する。

`````bash
mkdir -p "$HOME/AppData/Local/Dotfiles"
chezmoi diff --exclude=scripts "$HOME/AppData/Local/Dotfiles/DockerSsh"
chezmoi apply --exclude=scripts "$HOME/AppData/Local/Dotfiles/DockerSsh"
chezmoi verify --exclude=scripts "$HOME/AppData/Local/Dotfiles/DockerSsh"
`````

この段階ではHelperバイナリ・鍵・ストアを作らない。sourceDirはリポジトリルート、.chezmoirootはchezmoiという既存構成を維持する。
通常chezmoiファイルと、以下の独立したInstallationディレクトリを分離する。

`````bash
id=$(pwsh.exe -NoProfile -Command '[Guid]::NewGuid().ToString("N")')
local_app=$(cygpath -u "$LOCALAPPDATA")
package="$local_app/docker-ssh-issue142-lab-package-$id"
deployment="$local_app/Dotfiles/DockerSsh/Installations/$id"
pwsh.exe -NoProfile -File docker-ssh/scripts/Build-TpmDockerPackage.ps1 -OutputRoot "$(cygpath -m "$package")"
`````

packageディレクトリ名のissue142-lab接頭辞は検証済みbuilderのガードとして維持している。恒久配置の鍵名とは別物である。
新しいディレクトリだけを許可し、既存packageの上書きはしない。manifestのhashは署名の代替ではない。

## 接続先の確認と変更なしの事前検査

`docker context show` と `docker context inspect` で端末のEngine endpointを読み取り確認する。
トークンを含む全configや環境変数一覧は表示しない。下のnamed pipe例を別端末へ無条件で適用しない。
remote TLS endpointは未対応。DOCKER_TLS_VERIFY / DOCKER_CERT_PATHが設定されていれば勝手に解除せず停止する。

`````bash
endpoint='npipe:////./pipe/dockerDesktopLinuxEngine'
MSYS2_ARG_CONV_EXCL='npipe:' pwsh.exe -NoProfile -File docker-ssh/scripts/Initialize-DockerSshTpm.ps1 -PackageRoot "$(cygpath -m "$package")" -DestinationRoot "$(cygpath -m "$deployment")" -InstallationId "$id" -Mode permanent -EngineEndpoint "$endpoint" -CheckOnly
`````

CheckOnlyは配置先、鍵、資格情報を作成しない。既存配置ではREADY状態・選択したsettingsの識別情報と配布10ファイルのhash/ACLを照合し、検出した差異で停止する。
ただし既存READY配置のvault、store/settings、config、binding、installed-manifestや未知ファイル全件の完全性検査ではない。これらが欠落・変更していてもCheckOnlyが成功する場合がある。
既存Desktop configやcontext、Credential Managerをコピー・変更しない。

## 端末ごとの明示初期化

恒久鍵1個の作成と空ストア初期化を許可した端末でだけ実行する。

`````bash
MSYS2_ARG_CONV_EXCL='npipe:' pwsh.exe -NoProfile -File docker-ssh/scripts/Initialize-DockerSshTpm.ps1 -PackageRoot "$(cygpath -m "$package")" -DestinationRoot "$(cygpath -m "$deployment")" -InstallationId "$id" -Mode permanent -EngineEndpoint "$endpoint" -Execute -AcknowledgePermanent
source "$deployment/shell/docker-ssh.bash"
docker-ssh-activate "$deployment"
docker info --format '{{.OSType}}'
`````

鍵名は新しい端末のGUIDから作る `docker-ssh-tpm-<id>`。ユーザー名・SID・既存ホストの鍵IDを移植しない。
PCP RSA2048、非export、generic復号/PCP暗号化用途、対象SIDだけのDACL。SYSTEMへの明示grantはしない。
既存鍵の採用・上書き・自動修復はしない。用途/ACL/export/UI/公開識別情報が不一致なら暗号処理へ進めない。
既存READY配置への同一package再実行は上記の限定照合だけで、Executeでは追加の鍵inspectを行う。既存の鍵や暗号文を再作成・上書きしない。
これだけでstoreの復号・整合性や未知ファイル不在を確認したとは扱わない。通常利用前のGet-TpmDockerEnvironmentはconfig/Helper manifest等を追加検査し、暗号文の検証は実際のHelper操作が行う。結果不明なら使用せず保持して調査する。
別IDでの再実行は別鍵作成であり、更新ではない。

## 登録・更新・削除と再接続

実レジストリの対象・権限・成果物を確定し承認してから、Git Bashで非表示入力する。
xtraceを停止し、一時変数をexportしない。PATをコマンド引数、ファイル、履歴、チャットへ置かない。

`````bash
set +x
unset docker_ssh_pat
read -r -s -p 'PAT: ' docker_ssh_pat; printf '\n'
printf '%s' "$docker_ssh_pat" | docker login ghcr.io --username YOUR_GITHUB_USER --password-stdin
login_result=$?
unset docker_ssh_pat
printf 'login-exit=%s\n' "$login_result"
`````

GHCRはその端末用の短期PAT classicで、目的に応じread:packagesまたはwrite:packagesを選ぶ。repo/delete:packagesを安易に追加しない。
write:packagesは特定の試験packageだけに自動限定されるscopeではないため、対象アカウントの権限境界も確認する。
GitHubのscope選択画面で想定外の権限が選ばれたら発行前に止める。既存Desktop tokenは流用しない。

同じregistryへの再loginは専用ストアの登録更新、`docker logout ghcr.io` は該当資格情報削除である。実行前に選択中deploymentを照合する。
Helper getのstdoutは秘密を含むため、手動表示・保存しない。

新規SSHのGit Bashでも同じsourceとactivateを行う。接続元環境変数の継承、exportした関数、既存psmuxは前提にしない。
このmoduleはprofileやglobal PATHを変更しない。通常引数ではMSYSパス変換を保ち、endpointだけ変換除外する。
`docker --host / --context / --config`等の経路override、短縮option連結は誤経路を避けるため拒否する。
必要なoptionは長い形式または分離した値を使う。完全なDocker CLI引数互換を主張しない。

## Engineと再起動

再接続時は `docker info --format '{{.OSType}}'` を先に確認する。
Engineが停止していれば、既存コンテナが再開する影響を確認した上で `docker desktop start --timeout 60` を明示実行する。
失敗・timeoutで自動再試行しない。TPM取得とEngine利用可否を別々に記録する。
既存ホストではGUI未ログオンのSSHから起動成功したが、他端末での保証ではない。サービスや自動起動設定は変更しない。

## 更新とロールバック

同版の再適用は前述の限定された識別情報・配布物の一致だけを照合する。store全体の完全性を保証しない。既存暗号文・鍵・settingsを上書きするin-place更新や自動migrationは行わない。
更新版は別のpackageと別のInstallationIdでダミー検証し、明示承認した新トークンを登録してactivate先を切り替える。
選択先の切替前にdeactivateが成功したことを確認する。別deploymentがactiveのままのactivateは拒否される。切替・復旧の各段階が失敗したら停止する。
旧配置を保持し、以下のold_deploymentには切替前の既存配置を記録する。新しい配置の検証と登録が完了するまでは切り替えない。

`````bash
old_deployment=$DOCKER_SSH_DEPLOYMENT
docker-ssh-deactivate &&
  source "$deployment/shell/docker-ssh.bash" &&
  docker-ssh-activate "$deployment"

# 旧配置へ戻す必要があり、その状態を確認できた場合だけ実行する
docker-ssh-deactivate &&
  source "$old_deployment/shell/docker-ssh.bash" &&
  docker-ssh-activate "$old_deployment"
`````
実トークンを無断コピーせず、旧鍵・旧ストアが使える間だけロールバックできる。実際の異版移行・復旧は別途実機検証する。
一つのinstallationのbinやmanifestだけを取り替えると照合不一致で停止する。

## 無効化・完全撤去

当該shellの選択解除だけなら `docker-ssh-deactivate`。
以下の最初の呼出しは検査だけ、ExecuteはDISABLEDにする。鍵・暗号文を保持するが、解除を取り消す自動処理はない。
復帰が必要な場合に手動でStateを書き換えない。

`````bash
pwsh.exe -NoProfile -File docker-ssh/scripts/Remove-DockerSshTpm.ps1 -DestinationRoot "$(cygpath -m "$deployment")" -InstallationId "$id" -Mode permanent
pwsh.exe -NoProfile -File docker-ssh/scripts/Remove-DockerSshTpm.ps1 -DestinationRoot "$(cygpath -m "$deployment")" -InstallationId "$id" -Mode permanent -Execute
`````

鍵と専用配置の完全撤去は不可逆。token再発行・必要な監査記録を確保し、対象を承認してからだけ実行する。

`````bash
pwsh.exe -NoProfile -File docker-ssh/scripts/Remove-DockerSshTpm.ps1 -DestinationRoot "$(cygpath -m "$deployment")" -InstallationId "$id" -Mode permanent -Execute -DeleteKey -ConfirmIrreversibleKeyDeletion
`````

ID・receipt・公開鍵hash・所有者・ACL・配布hash・allowlistを照合。同じhandleへ削除1回、別照会で不存在を確認後に専用配置を撤去する。
失敗・不一致・UI・停滞・終了不明は保持して停止する。ACL緩和・強制削除・無条件retryはしない。
公開ランチャーは他installationでも使うため自動削除しない。chezmoi管理からの撤去もdiffで範囲を確認する。

## 障害とバックアップ

部分intent、stop marker、未知ファイル、破損storeを空store扱いにせず保持する。再初期化で隠さない。
UI/timeout時は子の終了と状態を確認するまで次の作成や削除へ進まない。providerの処理を確実に強制中断できる保証はない。
同一端末向けのprivateな暗号文・receiptバックアップは可能だが、自動backup/restoreは未実装。
暗号文だけを別TPMへコピーしても復旧できない。TPM交換/OS再インストール/鍵喪失では新しい端末別鍵と新tokenで初期化する。
秘密や暗号化ストアをGitへ加えない。管理者/SYSTEM・同一SIDの任意コード・侵害OSに対する保護は保証しない。

## 承認候補

- ?1：端末別の恒久初期化、実トークン登録、実レジストリへの接続。対象と最小権限を先に確定する。
- ?2：手動再起動/GUIログオフとEngine起動。作業中断・既存コンテナ再開の影響を確認する。
- ?3：DISABLEDへの変更、資格情報削除、鍵と配置の完全撤去。対象と不可逆性を照合する。
- ?4：更新先への実配置・token更新、Git push/PR。通常chezmoi適用はこれらを自動実行しない。
