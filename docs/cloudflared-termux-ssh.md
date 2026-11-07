# TermuxからCloudflare Access経由でWindowsへSSH接続する

2026-11-07にAndroidのTermuxから接続できた構成のメモ。Cloudflare One (WARP) をAndroidで有効にするとワイヤレスAndroid Autoが通信エラー21になるため、WARPを使わずにSSHだけをCloudflare Access経由にした。

## 構成

- クライアント: Android / Termux（OpenSSH 10.3p1、cloudflared 2026.6.1で接続確認）
- 公開ホスト名: `home-ssh.the9ball.net`
- Cloudflare: 既存のRemotely managed Tunnel + AccessのSelf-hosted application
- 転送先: 自宅Windows 11の`192.168.1.200:22`
- Windows側cloudflared: Windowsサービスで`--token-file`を使用。今回の追加設定に伴うサービス設定変更・再起動は不要だった
- ルーターでTCP 22をインターネットに公開しない

## Cloudflare側

1. 既存TunnelのPublished application routeに`home-ssh.the9ball.net`を追加し、サービスを`ssh://192.168.1.200:22`にする。
2. AccessのSelf-hosted applicationに同じ公開ホスト名を登録し、Allowポリシーで本人のメールアドレスを制限する。ログイン方法のRequire条件も設定する。
3. Tunnel側の「Accessで保護」を有効にし、AccessアプリケーションのAUDタグを設定する。UIのAUD入力は**Enterでタグを確定**してから保存する。
4. Accessの認証方式、MFA、SSHサーバーの公開鍵認証設定は別途確認する。メールアドレス制限だけでMFAを保証するわけではない。

`home.ssh.the9ball.net`はCloudflare Universal SSLの通常の`*.the9ball.net`証明書ではカバーされず、TLS handshake failureになった。`home-ssh.the9ball.net`へ変更するとTLS検証が成功した。多階層名を使う場合は対応する証明書が必要。

## Termux側

```sh
pkg update
pkg install openssh cloudflared
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

既存の`~/.ssh/config`はバックアップを取り、`Host home`を次のように設定する（既存設定を無条件に上書きしない）。

```sshconfig
Host home
    HostName home-ssh.the9ball.net
    User syasui
    ProxyCommand cloudflared access ssh --hostname %h
```

WARPをOFFにしてAccessログインを行い、SSH接続する。

```sh
cloudflared access login https://home-ssh.the9ball.net
ssh -v home
# 次回以降
ssh home
```

Accessセッションの期限切れ時は再認証が必要な場合がある。SSH秘密鍵やAccessトークン、TunnelトークンはリポジトリやIssueに貼らない。

## 切り分け

```sh
curl -Iv https://home-ssh.the9ball.net
```

- TLS handshake failure: まずホスト名に対応するエッジ証明書を確認する。今回の多階層サブドメインが該当した。
- TLS成功・HTTP 302で`cloudflareaccess.com`へリダイレクト: Accessのログイン入口まで到達している。SSHサーバー到達の証明ではない。
- `ssh -v home`で`Executing proxy command: exec cloudflared access ssh ...`を確認する。失敗時はTLS、Access認証、Tunnelルート、Windows sshdの順に切り分ける。

このメモはTermuxからのSSH接続成功を記録するもので、Android Autoとの長期的な共存、MFAの有効性、Windows sshdの認証設定まで検証済みとはしない。Windows側SSHサーバーの運用記録は[Windows OpenSSH](windows-openssh.md)を参照。
