# Windows cloudflaredサービスの更新

## 経緯

2026-11-05時点の記録です。
cloudflaredはaqua（`aqua.yaml`）でバージョンを固定しています。Windowsサービス`Cloudflared`は、aquaの`pkgs`配下にあるバージョン別ディレクトリの実行ファイルを直接参照していました。
そのため、aquaでバージョンを上げてもサービスは古い実行ファイルで動き続けていました。

cloudflared自身の自動更新（`tunnel run`の既定24時間周期）は、サービスの起動コマンドで無効化していなかったにもかかわらず、2026.10.0の実行ファイルが約1か月更新されていませんでした。
仮に自己更新が働いても、aquaのバージョン別ディレクトリの中身が書き換わり、`aqua.yaml`での固定とも食い違うため採用しません。

## 現在の構成

- サービスは固定パス`%LOCALAPPDATA%\cloudflared-service\cloudflared.exe`を、`tunnel --no-autoupdate run ...`で起動します。
- `chezmoi apply`の`run_onchange_after_update-cloudflared-service.ps1`が、`aqua.yaml`のcloudflaredのバージョンが変わったときに、aquaの実行ファイルを固定パスへコピーし、サービスを停止・起動します。管理者権限とUACは不要です。
- これを可能にするため、`chezmoi apply`を実行するユーザーへ、サービスの照会・開始・停止の権限を付与しています。構成変更（`SERVICE_CHANGE_CONFIG`）は付与しません。
- サービスが固定パスを参照するので、aquaの古いバージョンは`aqua vacuum`などで削除できます。

## 受け入れたリスク

SYSTEMで動くサービスの実行ファイルを、ユーザーが書き込めるディレクトリに置いています。
ユーザー権限で動く任意のプロセスが実行ファイルを差し替えると、次のサービス起動時にSYSTEM権限で実行されます。
ユーザーにサービスの開始・停止権限を付与しているため、OSの再起動を待たずに、そのプロセス自身がサービスを再起動して即座に実行させることもできます。
これは移行前のaqua配下の参照でも同じ状態でした。個人の端末で、ユーザー権限を奪われた時点で他の手段でも被害を防げないと判断し、許容しています。
守りを優先する場合は、実行ファイルを管理者のみ書き込める場所（Program Filesなど）に置き、更新のたびに管理者権限で反映する構成にします。

## 初回セットアップ

`chezmoi apply`を実行するユーザーで、管理者として開いたPowerShellから一度だけ実行します。
既存サービスの引数（トークンファイルの指定など）は引き継ぎ、`--no-autoupdate`を追加します。

```powershell
pwsh -NoProfile -File "$HOME\.dotfiles\scripts\windows-cloudflared-service.ps1" -WhatIf
pwsh -NoProfile -File "$HOME\.dotfiles\scripts\windows-cloudflared-service.ps1"
```

最後に表示される`State`が`Running`、`PathName`が固定パスを指していれば完了です。
サービスが固定パスを参照していない間、`chezmoi apply`は警告を出して何もしません。

## 更新時の動作と確認

`aqua.yaml`のcloudflaredのバージョンが変わると、次の`chezmoi apply`でサービスが数秒停止し、新しいバージョンで再起動します。
新しい実行ファイルはサービスを止める前に`cloudflared.exe.new`へコピーしてハッシュを検証し、置き換え時は旧版を`cloudflared.exe.old`へ退避します。
置き換えまたは起動に失敗した場合は旧版へ戻して起動し、`chezmoi apply`はエラーで終了します。原因を解消して再実行すれば同じ処理をやり直します。
初回セットアップのスクリプトも、実行ファイルと起動コマンドがすでに期待どおりならサービスを停止しません。
停止中に置き換え・起動コマンドの変更・起動のいずれかが失敗した場合は、変更した実行ファイルと起動コマンドを元に戻してサービスを起動します。
このスクリプトはPowerShell 7（`pwsh`）専用です。

```powershell
Get-CimInstance Win32_Service -Filter "Name='Cloudflared'" | Select-Object State, PathName | Format-List
& "$env:LOCALAPPDATA\cloudflared-service\cloudflared.exe" --version
```

トンネルの接続状態は、Cloudflareのダッシュボードで確認します。
