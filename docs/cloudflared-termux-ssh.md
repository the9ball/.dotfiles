# TermuxからCloudflare Access経由でWindowsへSSH接続する

2026-11-07にAndroidのTermuxから接続できた構成のメモ。
Cloudflare One (WARP) をAndroidで有効にするとワイヤレスAndroid Autoが通信エラー21になったため、WARPを使わずにSSHだけをCloudflare Access経由にした。
2026-11-19に現行ソースと関連文書を照合したが、Termuxからの再接続とCloudflare管理画面の実設定の再確認は行っていない。

## 構成

- クライアント: Android / Termux（2026-11-07の接続時はOpenSSH 10.3p1、cloudflared 2026.6.1。現在の必須バージョンを示すものではない）
- 公開ホスト名: `home-ssh.the9ball.net`
- Cloudflare: 既存のRemotely managed Tunnel + AccessのSelf-hosted application
- 転送先: 自宅Windows 11の`192.168.1.200:22`
- Windows側cloudflared: 固定パスのWindowsサービスで`--token-file`を使用。2026-11-07のルート追加時にはサービス設定変更と再起動は不要だった。更新方法は[Windows cloudflaredサービス](windows-cloudflared.md)を参照
- ルーターでTCP 22をインターネットに公開しない

## Cloudflare側

以下は成功時に設定した内容であり、既存環境では読み取り確認に使う。
接続不調を理由にルートやAccessアプリケーションを作り直さない。

1. 既存TunnelのPublished application routeは`home-ssh.the9ball.net`、サービスは`ssh://192.168.1.200:22`。転送先はTunnelコネクターから到達できるWindowsのLANアドレスであり、Termuxの接続先ではない。
2. DNSは同じTunnelを指すproxiedレコード、AccessのSelf-hosted applicationは同じ公開ホスト名。Allowポリシーで本人のメールアドレスを制限し、ログイン方法のRequire条件も設定した。他のポリシーによる意図しない許可やBypassがないかも確認する。
3. Tunnel側の「Accessで保護」は有効で、対象AccessアプリケーションのAUDタグを指定した。コネクターがAccess JWTを検証する設定であり、Allowポリシーの代わりにはならない。当時のUIではAUD入力後に**Enterでタグを確定**してから保存する必要があった。表示名や操作はUIの版で変わり得る。
4. Accessの認証方式とMFA、SSHサーバーの公開鍵認証設定は別途確認する。メールアドレス制限だけでMFAを保証するわけではない。

`home.ssh.the9ball.net`はCloudflare Universal SSLの通常の`*.the9ball.net`証明書ではカバーされず、TLS handshake failureになった。
`home-ssh.the9ball.net`へ変更するとTLS検証が成功した。
多階層名を使う場合は対応するエッジ証明書が必要。
これはTermuxからCloudflareまでのTLSであり、WindowsのSSHホスト鍵とは別の検証である。
`curl -k`やSSHのホスト鍵検証の無効化で回避しない。

公式仕様は[client-side cloudflaredによるSSH](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-cloudflared-authentication/)、[Access JWTの検証](https://developers.cloudflare.com/tunnel/reference/origin-parameters/#access)、[Universal SSLの範囲](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/enable-universal-ssl/)を参照。

## Termux側

```sh
pkg update
pkg install openssh cloudflared curl
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

既存の`~/.ssh/config`はバックアップを取り、`Host home`を次のように設定する（既存設定を無条件に上書きしない）。

```sshconfig
Host home
    HostName home-ssh.the9ball.net
    User WINDOWS_USER
    ProxyCommand cloudflared access ssh --hostname %h
```

`WINDOWS_USER`を接続先のWindowsユーザー名へ置き換える。
そのユーザーに登録済みの公開鍵に対応する秘密鍵をTermuxで使えることが前提で、鍵の新規登録やサーバー設定変更はこの手順に含めない。
既定以外の鍵を使う場合は、対象Hostに実際の`IdentityFile`を指定する。
`command -v cloudflared`で実体を確認し、ProxyCommandから見つからない場合はその絶対パスを使う。
`Host *`など先行設定の影響は、接続しない`ssh -G home`で`hostname`、`user`、`proxycommand`、`identityfile`を確認する。

WARPをOFFにしてAccessログインを行い、SSH接続する。
ブラウザーが自動で開かない場合は、cloudflaredが表示した認証URLを同じAndroid端末のブラウザーで開き、認証完了後にTermuxへ戻る。

```sh
cloudflared access login https://home-ssh.the9ball.net
ssh -v home
# 次回以降
ssh home
```

Accessセッションの期限切れ時は再認証が必要な場合がある。
Accessログインに加えて、Windows OpenSSHによるホスト鍵の検証と利用者の公開鍵認証が必要。
初回のSSHホスト鍵指紋は、管理者が信頼できる別経路で確認した値と照合する。
ホスト鍵変更の警告が出たら、登録済み鍵を削除して続行せず接続を止めて確認する。
SSH秘密鍵、Accessトークン、Tunnelトークン、認証URL、Cookie、認証ヘッダーをリポジトリやIssueに貼らない。

## Claude Codeの送信ボタン

[Claude Codeのキー設定](../README.manual.md#claude-codeのキー設定)では、Ctrl+Enterで送信する。
2026-11-25に確認したところ、TermuxからのEnterとCtrl+Enterは、接続先のWindowsではどちらも`0d`として届いた。
Claude Code側では区別できないため、Termuxの追加キー行に`Ctrl+X` `Ctrl+S`（既定の`chat:sendNow`）を送るボタンを置く。このボタンで送信できることを同日に確認した。

Termux側で、次を実行する。`SEND`が送信ボタンになる。
設定ファイルは`~/.termux/termux.properties`か`~/.config/termux/termux.properties`で、どちらもなければ前者を作る。既存のファイルは別名でバックアップしてから追記する。確認やバックアップに失敗した場合と、既に`extra-keys`がある場合は、設定ファイルに追記せずに止まる。
追記に失敗した場合は、書きかけの内容が残ることがある。バックアップを元のファイルへ戻す（新規に作った場合は、作られたファイルを削除する）。
`termux-reload-settings`に失敗した場合、追記は済んでいるので、このコマンドだけを再実行する。

```sh
(
  set -eu
  properties="$HOME/.termux/termux.properties"
  if [ ! -e "$properties" ] && [ -e "$HOME/.config/termux/termux.properties" ]; then
    properties="$HOME/.config/termux/termux.properties"
  fi
  if [ -e "$properties" ]; then
    match=0
    grep -nE '^[[:space:]]*extra-keys([[:space:]=:]|$)' "$properties" || match=$?
    case "$match" in
      0) echo "extra-keys is already set in $properties; edit it by hand." >&2; exit 1 ;;
      1) ;;
      *) echo "Cannot read $properties." >&2; exit 1 ;;
    esac
    backup=$(mktemp "$properties.bak.XXXXXX")
    cp "$properties" "$backup"
  else
    mkdir -p "$HOME/.termux"
  fi
  cat >> "$properties" <<'EOF'

extra-keys = [['ESC','/','-','HOME','UP','END','PGUP'],['TAB','CTRL','ALT','LEFT','DOWN','RIGHT',{macro: "CTRL x CTRL s", display: "SEND"}]]
EOF
  termux-reload-settings
)
```

`extra-keys`が既にある場合は、その配列に次の要素を加えて`termux-reload-settings`を実行する。

```text
{macro: "CTRL x CTRL s", display: "SEND"}
```

この設定はTermux側のファイルなので、chezmoiの管理対象にしない。

## 現行のWindowsシェルとの関係

PR #292以降の構成では、Windows Git Bash SSHで`DOTFILES_DOCKER_SSH=required`が設定されている場合、SSH認証後にManaged SSH Dockerを初期化する。
成功時は`DOCKER_SSH_MANAGED=1`、`PSMUX_SSH_AUTOATTACH=0`となり、psmuxへの自動attachを抑止する。
管理モードの指定がない通常SSHは既存のattach条件に従う。
これらはWindows側のシェル起動処理であり、TermuxのProxyCommandへの追加設定は不要。

必須初期化が失敗すると、SSH認証に成功していてもシェルが終了する。
公開bootstrapとcheckoutの不一致も拒否されるため、更新後の切り分けでは[公開コピーの同期と復旧](../docker-ssh/PUBLIC-BOOTSTRAP-SYNC.md)と[管理対象の起動経路](../docker-ssh/ISSUE-185.md#管理対象の起動経路)を確認する。
修復のための同期やモード変更は別途判断し、この接続確認では行わない。
既存psmuxへの手動attachでは、新しいSSHの管理環境が古いシェルへ反映されない点にも注意する。

## 切り分け

```sh
curl --connect-timeout 10 --max-time 20 -Iv https://home-ssh.the9ball.net
```

- TLS handshake failure: まずホスト名に対応するエッジ証明書を確認する。当時の多階層サブドメインが該当した。端末時刻とCA証明書も確認する。
- TLS成功・HTTP 302で`cloudflareaccess.com`へリダイレクト: Accessのログイン入口まで到達している。SSHサーバー到達の証明ではない。
- `ssh -v home`で`Executing proxy command: exec cloudflared access ssh ...`を確認する。出なければ`ssh -G home`で適用設定を確認する。
- Accessの拒否や認証待ち: ブラウザーでのログイン完了、対象アプリケーションとポリシー、セッション期限、Tunnel側のAUDの対応を確認する。認証URLを他人へ送らない。
- バナー交換前の切断やtimeout: Access認証、Tunnelの稼働とルート、コネクターからWindowsのTCP22への到達、SSHサービスの待受を順に確認する。エラー文だけで原因を断定しない。
- `Permission denied (publickey)`: SSHの利用者認証段階。Windowsユーザー名、Termuxの使用鍵、サーバーに登録済みの公開鍵を照合する。Accessログインのやり直しだけでは解消しない。
- 認証後すぐ終了する: `Authenticated to ...`の後のシェル診断を確認する。`Required managed SSH Docker bootstrap failed; ending this shell.`などが出たらWindows側初期化の問題として扱う。
- シェルには入れるがpsmuxが開かない: 管理モードでは自動attach抑止が期待される。通常SSHのattach条件は[Git Bashとpsmuxの手順](../README.manual.md#windows-ssh-の既定シェルと-psmux)を確認する。既存セッションを終了して試さない。

`curl -I`の結果だけでは、Access認証後のWebSocket転送やSSHの成功を確認できない。
共有する診断結果は確認した段階と非秘密のエラーコードに絞り、`curl -v`や`ssh -v`の生ログは公開しない。

このメモの接続成功は2026-11-07の記録であり、PR #292後のTermux再接続成功を示すものではない。
Android Autoとの長期的な共存、MFAの有効性、Windows sshdの認証設定まで検証済みとはしない。
Windows側SSHサーバーの運用記録は[Windows OpenSSH](windows-openssh.md)を参照。
