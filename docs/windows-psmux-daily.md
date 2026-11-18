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
PSMUX_NO_WARM=1 psmux -f NUL -L dotfiles-session1 attach -t main
```

自動接続時のregistry環境変数はsubshellに閉じ込め、元のSSHシェルへ残さない。
SSHからnew-sessionや監視起動は行わない。デスクトップ監視が無ければエラーを表示してGit Bashへ戻る。
`-f NUL`はattachクライアントだけに空設定を指定する。psmux 3.4.0は、有効設定にトップレベルのnew-sessionがあると、server不在時のattachでも内部で新規作成する。PSMUX_NO_WARMだけではこの経路を抑止しない。
既存serverが起動時に読み込んだ設定や、新規paneの既定シェルは変更しない。監視が明示的に作成するnew-sessionでは通常のpsmux設定を維持する。
既存の個人用overlay、入れ子回避、環境変数・ファイルによるbypassは維持する。
現在接続中のCodex/SSHプロセスを切断したり、startupファイルを強制的に再読み込みしたりしない。

初回は既存Codex接続を残したまま新しいSSHを開き、手動attach無しで `main` に入ることを確認する。
SSHクライアントはSession 0でもよい。serverはSession 1のままであることを確認する。

## tmuxとpsmuxの設定の管理

WindowsとそのSSH hookはpsmuxを使用する。aquaのtmux本体はLinux/macOS向けの導入宣言であり、WSLを含む手動利用はリポジトリの自動起動導線だけでは否定できないため維持する。TMUX/TMUX_PANEの判定もpsmux互換の入れ子防止に必要である。

リポジトリ直下の.tmux.confは古いvi操作・pane移動・サイズ変更・コピー・マウス等の設定で、自動session生成指示はない。現行chezmoiのsourceはchezmoi/であり、この旧ファイルをホームへ配置する定義は見つかっていない。Linux/macOSでの手動利用への影響が未確認のため削除しない。

Windowsの.psmux.confの管理元はchezmoi/dot_psmux.conf.tmplで、Git Bashを既定シェルにする設定を維持する。psmux 3.4.0はPSMUX_CONFIG_FILEを優先し、未指定ならホームの.psmux.conf、.psmuxrc、.tmux.conf、.config/psmux/psmux.confの最初に存在する設定を読む。ホームのローカル調整はテンプレートとは別であり、整理のために上書きしない。稼働済みserverの実効設定は、この探索順の確認だけでは証明できない。

.tmux.confの削除だけでは他の設定候補やPSMUX_CONFIG_FILEによる作成を防げない。attach-only保証は設定整理と分け、SSHと監視helperのattachに空設定を明示する。

## attach-onlyの隔離回帰検査

PowerShell 7.4以上で `tests/windows-psmux-attach-only.ps1 -PsmuxExecutable <インストール済みpsmuxの絶対パス>` を実行する。SSH Session 0の検証では `-RequiredSessionId 0` を付ける。異なるSession IDでは検査を開始しない。

検査は専用TEMP内の仮ホーム・registryと一意のnamespaceを使う。PSMUX_CONFIG_FILEと4つのホーム設定候補それぞれにnew-sessionを置き、空設定付きattachがmain不在のexit 1になること、serverの登録情報や新しいpsmuxプロセスが残らないことを確認する。psmuxが作る空の.registry_sweepは許容する。通常のホーム、既存registry、Startupや既存sessionへ接続・終了要求は送らない。期限超過時は自分が起動した検査clientだけを終了する。失敗時のfixtureは調査用に残す。

2026-11-17、psmux 3.4.0の実体でローカルSession 1と既存SSH経路のSession 0から各5ケースが成功した。設定削除による抑止ではなく、設定が残っていてもクライアントが生成しないことを確認した。既存serverへのattachや次回ログオンのStartup発火は、この陰性検査の成功から推定しない。

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
