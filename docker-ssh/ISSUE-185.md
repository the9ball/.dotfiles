# Issue #185：SSH認証経路とOAuth対応

本書は0.5系のソース実装と、本番適用前に必要な確認を示す。
Issue #142の0.4系実機実績は、0.5系の実機成功を意味しない。
実装記録と承認は [Issue #185](https://github.com/the9ball/.dotfiles/issues/185) を参照する。

## 管理対象の起動経路

通常GUIのDocker設定は維持する。
Windows Git Bash SSHで `DOTFILES_DOCKER_SSH=required` を明示した場合だけ、親shellから専用環境を継承する。
この設定はソース配布だけでは有効にしない。
独立したnative PowerShell SSH、サービス、環境を消したプロセスは、同じbootstrapを通す設計を別に確認する。

1. `.bashrc` がWindows SSHの管理モードを判定する。
2. 必須 `.bashrc.docker-ssh` は信頼したcheckout内のcanonical Enter/readerを起動し、公開コピーを実行する前にACL・reparse・canonical内容との一致を確認する。selectorは検証済みの経路から読む。
3. owner、ACL、reparse point、manifest/hash、READY状態、専用config、競合overrideを検査する。
4. 検証済み `DOCKER_CONFIG`、`DOCKER_SSH_HELPER_ROOT`、dispatcher/helper PATHを親shellへ設定する。
5. 子PowerShellの `-NoProfile` やnative子でも通常の `docker` / `docker.exe` が検証付き入口へ解決される。

初回bootstrapは、既に読み込むcheckoutとGit/PowerShell toolchainを信頼する前提で起動する。
公開コピーの存在確認だけを信頼境界にせず、改変・広いACL・staleな内容はmetadataを受け取る前に拒否する。
required時の初期化失敗は親shellを非ゼロ終了する。
Docker以外の作業もそのshellでは開始できない。
`DOTFILES_DOCKER_SSH` の不正な値も管理対象SSHでは拒否する。

初期導入では管理対象SSHのpsmux自動attachを抑止する。
既存psmux server/sessionは終了・削除せず、GUI/local psmuxの動作も変更しない。
古いshellへ新SSHのexportは届かないため、そのまま再接続したshellを管理対象とみなさない。
既存sessionで必要なら、管理モードを指定した新しいlogin child shellを起動し、bootstrap成功を確認する。
自動再接続の復活は、対象sessionの環境を検証できる仕組みを別途実証してから判断する。

## selectorと実行時の保護

selectorは `%LOCALAPPDATA%/Dotfiles/DockerSsh/ssh-environment.json`。
構造は `Version: 1` と、その端末で明示選択したローカルdrive絶対パスの `DeploymentRoot`。
最初に見つかったinstallationを自動選択しない。
selectorは内容を読む前にleafと祖先を検査し、対象ユーザー所有・対象ユーザーだけの許可を必須とする。UNC・extended・相対パスはfilesystemへアクセスする前に拒否する。
このファイルと有効化設定の作成・変更は、本番適用の承認後に行う。

native dispatcherは自分の配置からdeploymentを確定し、helper/dispatcherと信頼するreader/launcherのmanifestを検査する。
PowerShellはinstallerが記録した絶対 `PowerShellExecutable` を使用し、実行前にpath/ACLを検査する。
受け取った引数はJSONのBase64としてlauncherへ渡し、PowerShellのparameter bindingにDocker引数を解釈させない。
これは暗号化ではない。tokenをコマンド引数へ置くことは避ける。
stdin、stdout/stderr、引数境界、終了コードを維持する。

native/managedの各呼出しでもREADYと0.5系を必須とし、STAGEDへ戻った配置からは実行しない。legacyの明示staging試験とは分離する。
競合するhost/context/auth/TLS環境、別config/helper、inline資格情報（registrytokenを含む）や引数overrideは黙って解除せず停止する。
失敗時にdesktop helperや平文ストアへfallbackしない。
ただしPATHはOS全体の強制機構ではない。
実Dockerの絶対パスと明示configの併用、起動hookを飛ばすshell、環境を消した新rootまで禁止できるとは主張しない。
compose/buildx/pluginsの独自builder/configは個別の受入試験を必要とする。

## OAuthキーの契約

- 通常Hub認証：`https://index.docker.io/v1/`
- access：`https://index.docker.io/v1/access-token`
- refresh：`https://index.docker.io/v1/refresh-token`

OAuthの2キーは入力文字列の完全一致だけを許し、通常Hubキーと別に保存する。
HTTP、別host/port、query、fragment、userinfo、encoded path、末尾slashを一般許可しない。
通常レジストリの既存正規化は維持する。
helperはSecretを不透明に扱い、refresh/client IDの連結値を解析しない。
独自のrefresh、期限判定、HTTP revoke、通常キーからの連鎖削除を追加しない。
暗号形式、鍵用途、ACL、入出力制限、1操作単位の原子更新は維持する。

Docker CLI v29.7.2はOAuth2件を独立Storeした後、AutoPAT等を経て通常Hub認証を保存する。
全3件の一括成功・一括rollbackは保証されず、途中失敗で一部だけ残り得る。
username指定loginは残るOAuthキーを消さない。
引数なしlogoutとregistry明示logoutは異なる。
OAuthのlocal erase後のremote revokeが失敗しても、CLIは警告だけでexit 0になり得る。
終了コード、local削除、remote失効を別々に確認し、承認なしに残存資格情報を消さない。

## 本番適用の承認範囲

ソースと隔離試験の成功だけでは、以下を実施しない。

1. 配布差分をレビューし、chezmoiで公開5ファイルを適用する。広いapplyは他のhookを含むため対象を限定する。
2. 0.5 packageを新しいdeploymentへ配置し、必要な場合の新TPM鍵/vault初期化を個別に承認する。0.4配置へ上書きしない。
3. 対象ユーザー専用ACLでselectorを新設し、選択したREADY 0.5配置を記録する。
4. host-local Bash設定に管理モードを明示し、新しいSSHで初期化・継承を確認する。GUI設定は維持する。
5. 対象・期限・権限を承認した実tokenを非表示入力から登録し、必要なprivate操作を確認する。
6. 再起動の影響を別承認し、GUI未ログオンの新規SSHで保存済み認証の利用を確認する。

selectorを切り替える前に、旧deployment/vault/keyと設定を保持する。
実tokenの移行・再登録・失効、試験entryの削除も承認範囲を固定する。
失敗時は新規作成・自動修復を繰り返さず、秘密なしの診断結果と部分状態を保全する。

## 切戻し

旧0.4 helperはOAuthキー入りvaultを読めない。
新版と旧版は別deployment/vaultとして保持し、旧helperへ新vaultを渡さない。
本番適用後の切戻しはselectorと有効化設定の承認済み差分を戻し、SSH/エージェントを新しく起動する。
旧版へ戻す場合は従来の明示launcherを使い、0.5必須のmanaged modeへ0.4を選択して成功するとは扱わない。

`docker-ssh-restore-environment` は元の値・unset・export属性を戻すための明示操作であり、既に起動した子は更新しない。
管理を解除した現shellをそのまま安全なmanaged入口とはみなさず、終了して再起動する。
古い資格情報が失効していれば明示エラーで停止する。
経路復旧は認証復旧の保証ではなく、再登録は別承認とする。
desktop fallbackを復旧成功とは扱わず、新旧の鍵/vaultを自動削除しない。

## 隔離試験と検証限界

`tests/OAuthKeys` はproductionの純粋キー処理を直接リンクする。
`tests/OAuthProtocol` はproductionのhelper本体・キー処理・ACL検査をリンクするが、TPM実装を含めず、dummy専用software cipherへ置換する。
実TPM・実tokenなしでget/store/update/erase/list、キー分離、not-found、重複JSON拒否、破損拒否を確認する。
これは実TPMの鍵取得・復号成功の証明ではない。

routing回帰はinertなDocker/probeと新規のユーザー専用試験領域を使う。
Temp祖先のACLで検査が拒否される環境では、保護を緩めずLocalAppData直下の新規private fixtureを使う。
本番のDocker設定・既存Installations・鍵・vaultを試験先にしない。

本番未検証：新規SSHの実起動、GUI未ログオンcold boot、実Web認証/remote失効、独立PowerShell/WSL/service root、実tokenによる異版切替とrollback。
Issue #142の過去PASSや今回のinert試験を、これらの成功と読み替えない。
