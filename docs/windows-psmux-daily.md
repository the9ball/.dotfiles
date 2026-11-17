# Windows Session 1 psmux の常用構成

Issue #278 / upstream openai/codex #46412 の暫定対応。Windowsの対話型Session 1で監視を起動し、SSHはその既存セッションへattachする。
Codexは自動起動しない。作業ディレクトリ、sandbox、ACL、token、Windowsサービスは変更しない。

## 構成

| 用途 | 設定 |
| --- | --- |
| 常用namespace / session | `dotfiles-session1` / `main` |
| 常用runtime | `%LOCALAPPDATA%\Dotfiles\PsmuxDaily` |
| registry | runtime内の `registry`、`PSMUX_NO_WARM=1` |
| ログ | `main.monitor.log` / `main.attach.log` / `recreation.requests.log` |
| 制御ファイル | 常用runtime内の `stop.request` / `recreate.request` |
| ログオン登録 | ユーザーのStartup内の `Dotfiles psmux Session 1.lnk` |

実装は `scripts/windows-psmux-daily/`。PoCの監視・世代cookie・協調再作成・所有attachだけを止める処理を再利用した。
実験用診断スクリプトは常用側へコピーしていない。
psmux実体はこのcheckoutの `aqua.yaml` と `aqua which psmux` から解決する。インストールは行わない。

旧SSHセッション、既存のCodex作業セッション、PoCは移行時に停止・置換しない。
PoCのTEMP registryや停止ファイルを常用側へコピーしない。

## 初回導入と起動

通常のWindows Session 1 TerminalのPowerShellから実行する。管理者権限は不要。

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -File "$HOME\.dotfiles\scripts\windows-psmux-daily\install-startup.ps1" -StartNow
```

ユーザーStartupへ、`wscript.exe //B //Nologo <launch-hidden.vbs>` を実行するショートカットを登録し、同じコマンドで初回起動する。
既存の同名ショートカットが別のターゲットを指している場合は上書きしない。
VBSはBATを非表示のconsoleで起動する。監視はSession IDが1以外なら作成前に終了する。
同名session作成失敗、所有cookie不一致、識別不明、attachエラーは監視終了とし、新しい排他・引き継ぎ・無制限リトライは設けない。

ログの `new-session-exit=0`、`anchor-identity=matched`、serverとattachの `windows-session-id=1` を確認する。
新しいウィンドウが表示されず、attachが維持されていることも確認する。

## SSHログイン

新しい直接対話型SSHログインでは `.bashrc.ssh-psmux` が個人用overlayを読み込み、常用registryの次の操作だけを行う。

```bash
PSMUX_DATA_DIR="$(cygpath -w "$LOCALAPPDATA/Dotfiles/PsmuxDaily/registry")" \
PSMUX_NO_WARM=1 psmux -L dotfiles-session1 attach -t main
```

自動接続時のregistry環境変数はsubshellに閉じ込め、元のSSHシェルへ残さない。
SSHからnew-sessionや監視起動は行わない。デスクトップ監視が無ければエラーを表示してGit Bashへ戻る。
既存の個人用overlay、入れ子回避、環境変数・ファイルによるbypassは維持する。
現在接続中のCodex/SSHプロセスを切断したり、startupファイルを強制的に再読み込みしたりしない。

初回は既存Codex接続を残したまま新しいSSHを開き、手動attach無しで `main` に入ることを確認する。
SSHクライアントはSession 0でもよい。serverはSession 1のままであることを確認する。

## 通常の協調再作成

sessionを作り直すと作業中のpaneも終了するため、常用 `main` 内で保存・終了してから要求する。

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -File "$HOME\.dotfiles\scripts\windows-psmux-daily\request-recreation.ps1"
```

制御側は世代cookie入りファイルを提出するだけ。監視が照合し、自身のkill CLIと旧serverの実終了を両方確認してから次を作成する。
提出exit 0は完了ではない。ログの `coordinated-recreation-ready` と新しいSession 1 server/attachで完了を確認する。

## 停止・再起動・撤去

監視だけを止める:

```powershell
& $env:ComSpec /d /c "$HOME\.dotfiles\scripts\windows-psmux-daily\stop.bat"
```

自分のattachだけを終了し、serverや他のSSHクライアントは止めない。停止ファイルはログオン後も有効。
既に協調再作成のkillを開始した後の停止では、その終了操作を取り消せない。CLI・出力・旧serverの期限付き待機が加算され得る。

監視を新規起動からやり直す場合は、停止完了を確認し、残る常用sessionを必要なら保持する。
残ったsessionがある間、監視のnew-sessionは失敗する。やり直すときだけ、保存済み・他client無しを確認して常用 `main` を終了し、
常用runtimeの `stop.request` を削除してVBSを通常のSession 1から実行する。古い `recreate.request` は状態確認なしに消さない。

```powershell
wscript.exe //B //Nologo "$HOME\.dotfiles\scripts\windows-psmux-daily\launch-hidden.vbs"
```

ログオン登録だけを外す（既存serverや監視は停止しない）:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -File "$HOME\.dotfiles\scripts\windows-psmux-daily\install-startup.ps1" -Remove
```

SSHの自動attachを一時回避する方法は、既存hookの条件に従う `PSMUX_SSH_AUTOATTACH=0`、またはホームの `.psmux-no-autoattach`。
旧namespaceを戻すためにsessionを停止する必要はない。接続先の変更はhookだけで行う。

## 再起動後と制約

- Windowsへ対話型ログオンするとStartupが監視を起動する。まずそのログオンが必要で、SSHだけではserverを作らない。
- 停止ファイルを残した場合は自動起動しない。Session IDが1以外のログオンも監視が拒否する。
- 外部から生のkill-sessionを実行した場合の旧CLIと新世代の競合は未解決。通常は専用の協調要求を使う。
- 別監視の新規起動と再作成要求の全タイミングを排他しない。cookieは協調用の所有確認であり認証ではない。
- 短時間で自然に戻るattachは監視を止める。常用化のためだけの新しいMutex、復旧daemon、サービス、再試行機構は追加しない。
- ログとregistryはユーザー専用。registryの認証キーを外部へ公開しない。

PoCでは協調再作成2回、重なった起動から監視1本維持、SSH接続中の監視だけの停止が成功した。
常用配置の初回起動、SSH自動attach、再ログオン時のStartup発火は、それぞれ実測できた範囲を区別して記録する。

## 導入確認結果（2026-11-17）

- 通常のWindows Session 1から `install-startup.ps1 -StartNow` を実行し、Startup登録成功、終了コード0、ウィンドウ非表示を確認。
- rootによるStartupショートカットのTargetPath・Arguments照合は一致。ログオン時に設定されたコマンドと同じコマンドで初回起動した。
- 常用server / helper / 監視attachはいずれもSession 1。PIDとserver作成時刻anchorを照合し、attachは10分以上維持。
- 新しいSSH接続が手動操作無しで `main` へ自動attach。list-clientsは監視とSSHの2件、終了コード0。SSH clientはSession 0、serverは同じSession 1のまま。
- Session一覧は `main` attached、終了コード0。常用stop.request / recreate.requestは無し。
- ホストWindows Terminalで `tests/ssh-psmux.sh` は全PASS、終了コード0。異常系の警告は期待された出力であり、テスト失敗は無し（ユーザー実測）。
- 既存Codex serverとPoC serverは、同じPID・起動時刻・Session 1を維持。停止・置換しなかった。
- PowerShell構文検査と変更ファイルの形式検査は成功。sandboxでのGit Bash/aqua起動は拒否されたため、ホストの実機結果と区別した。

検証後も常用監視とSSHクライアントは接続中のまま維持した。
再起動・再ログオンによるStartupの実発火はまだ観測していない。次回はWindowsへSession 1で対話型ログオンすれば起動する設定であり、SSHだけの先行接続では作成しない。
