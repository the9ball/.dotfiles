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
`-StartNow`は`stop.request`または`recreate.request`があれば、ショートカット保存と起動の前に理由を通知して拒否する。
直接起動したmonitorも`recreate.request`があれば、`main.monitor.log`に`startup-refused recreate.request-present exit=81`を記録して新規作成を拒否する。
要求が残っていることは処理の停滞や残留の確定診断ではない。
同名session作成失敗、所有cookie不一致、識別不明、attachエラーは監視終了とし、新しい排他・引き継ぎ・無制限リトライは設けない。

ログの `new-session-exit=0`、`anchor-identity=matched`、serverとattachの `windows-session-id=1` を確認する。
新しいウィンドウが表示されず、attachが維持されていることも確認する。

## SSHログイン

通常SSH・psmux・CodexのDocker共通入口は[Routerの導入・保証範囲](../docker-ssh/ROUTER.md)を参照する。
Router公開前のManaged SSH分岐は維持し、公開後はペインとその子へ固定native入口のPATHを継承する。
既存ペイン・起動済みCodexはSSH再接続だけでは移行しない。serverや作業を止めず、自然な区切りで移行する。

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

## 常用registryの読み取り確認

SSH hookはrouting変数をsubshellに閉じ込めるため、detach後の通常シェルで単に`psmux list-sessions`を実行しても常用registryを見ているとは限らない。
Git Bashから次のブロック全体を実行し、表示されるregistryとnamespaceを確認する。
環境変数と入れ子判定用の変数の解除はsubshell内だけに適用し、親シェルには残さない。

<!-- daily-inspection:start -->
```bash
(
	if [ -z "${LOCALAPPDATA-}" ]; then
		printf '%s\n' 'LOCALAPPDATA is unavailable; daily registry not selected.' >&2
		exit 1
	fi
	PSMUX_DATA_DIR=$(cygpath -w "$LOCALAPPDATA/Dotfiles/PsmuxDaily/registry") || exit $?
	export PSMUX_DATA_DIR
	export PSMUX_NO_WARM=1
	unset PSMUX_SESSION PSMUX_SESSION_NAME PSMUX_SESSION_DISPLAY_NAME
	unset PSMUX_REMOTE_ATTACH PSMUX_TARGET_SESSION PSMUX_ACTIVE TMUX TMUX_PANE
	printf 'registry=%s namespace=dotfiles-session1\n' "$PSMUX_DATA_DIR"
	daily_sessions=$(command psmux -f NUL -L dotfiles-session1 list-sessions -F '#{session_name}') || exit $?
	printf '%s\n' "$daily_sessions"
	case $'\n'"$daily_sessions"$'\n' in
		*$'\nmain\n'*) ;;
		*) printf '%s\n' 'Daily main is absent; do not infer recovery readiness.' >&2; exit 1 ;;
	esac
	command psmux -f NUL -L dotfiles-session1 list-clients -t main
)
```
<!-- daily-inspection:end -->

`-f NUL`と`PSMUX_NO_WARM=1`で設定起点の新規作成とwarm起動を避け、常用の一覧照会だけを行う。
`list-sessions`はセッション名のみを表示する。
取得失敗、`main`不在、`list-clients`失敗はいずれも非0終了となり、停止完了や再作成可能の証拠にはならない。
空のclient一覧だけでも、monitor/helperや要求提出処理の終了までは証明できない。
この照会はセッションを作成、attach、停止しないが、psmux本体によるregistry管理情報の更新まで禁止するものではない。

手動復旧の前には、`main`内の作業を保存し、一覧にある他のSSHクライアントと利用者を確認する。
監視停止の完了は、対応するmonitor/helperとその所有attachの終了、監視ログの終了記録、停止要求の維持を合わせて確認する。
PIDだけで判定せず、プロセスの起動時刻、実行コマンド、runtime、namespace、世代cookieとの対応を照合し、不明なものがあれば復旧操作を止める。
serverと作業中paneは監視停止後も残り得るため、他clientの不在や監視終了だけを理由に終了しない。

`bash --noprofile --norc tests/windows-psmux-inspection.sh`は、この文書のブロックを抽出してstubで引数、環境分離、異常終了を検査する。
実際の常用psmuxへ問い合わせる検証ではない。

## tmuxとpsmuxの設定の管理

WindowsとそのSSH hookはpsmuxを使用する。aquaのtmux本体はLinux/macOS向けの導入宣言であり、WSLを含む手動利用はリポジトリの自動起動導線だけでは否定できないため維持する。TMUX/TMUX_PANEの判定もpsmux互換の入れ子防止に必要である。

リポジトリ直下の.tmux.confは古いvi操作・pane移動・サイズ変更・コピー・マウス等の設定で、自動session生成指示はない。現行chezmoiのsourceはchezmoi/であり、この旧ファイルをホームへ配置する定義は見つかっていない。Linux/macOSでの手動利用への影響が未確認のため削除しない。

Windowsの.psmux.confの管理元はchezmoi/dot_psmux.conf.tmplで、Git Bashを既定シェルにする設定を維持する。psmux 3.4.0はPSMUX_CONFIG_FILEを優先し、未指定ならホームの.psmux.conf、.psmuxrc、.tmux.conf、.config/psmux/psmux.confの最初に存在する設定を読む。ホームのローカル調整はテンプレートとは別であり、整理のために上書きしない。稼働済みserverの実効設定は、この探索順の確認だけでは証明できない。

.tmux.confの削除だけでは他の設定候補やPSMUX_CONFIG_FILEによる作成を防げない。attach-only保証は設定整理と分け、SSHと監視helperのattachに空設定を明示する。

## attach-onlyの隔離回帰検査

### 固定版の保証範囲と互換性

対象はpsmux 3.4.0、上流commit `20aa1d7254ee93f64dafa059ef89341d9767470a`。将来版の同じ挙動までは保証しない。

ソース確認では、main.rs L1206–1248の `-f NUL` が継承PSMUX_CONFIG_FILEを上書きし、config.rs L45–92は指定ファイルからホーム候補へfallbackしない。NULが空でも読取り失敗でも設定起点のnew-session分岐（main.rs L1861–1872）は成立しない。不在時はL1890–1910でexit 1、既存対象はremote attachとなり、L5686以降のcold spawnへ進まない。SSH hookは非0終了を受けて通常シェルへ戻る。既存serverの存在確認だけや.tmux.confの整理による保証ではない。

空設定はclient自身のpriority設定読取りも無効にする（config.rs L120–151）。client環境のPSMUX_CONFIG_FILE=NULはserverへ送られるが、既定update-environmentはDISPLAY等8項目だけで同変数を含まない（types.rs L2820–2829）。管理templateもdefault-shellだけである。独自にPSMUX_CONFIG_FILEや一致するwildcardをupdate-environmentへ追加した場合は、serverのsession／process環境にNULが取り込まれ、将来の設定読取りや新規paneへ影響し得る（server/mod.rs L3566–3574、environ.rs L337–380）。これは条件付き互換性であり、その場で既存default-shellが失われると実測したものではない。

### 実測と未検証の区別

PowerShell 7.4以上で `tests/windows-psmux-attach-only.ps1 -PsmuxExecutable <インストール済みpsmuxの絶対パス>` を実行する。SSH Session 0の検証では `-RequiredSessionId 0` を付ける。異なるSession IDでは検査を開始しない。

検査は専用TEMP内の仮ホーム・registryと一意のnamespaceを使う。PSMUX_CONFIG_FILEと4つのホーム設定候補それぞれにnew-sessionを置き、空設定付きattachがmain不在のexit 1になること、serverの登録情報や新しいpsmuxプロセスが残らないことを確認する。psmuxが作る空の.registry_sweepは許容する。通常のホーム、既存registry、Startupや既存sessionへ接続・終了要求は送らない。期限超過時は自分が起動した検査clientだけを終了する。失敗時のfixtureは調査用に残す。

2026-11-17、psmux 3.4.0の実体でローカルSession 1と既存SSH経路のSession 0から各5ケースが成功した。設定削除による抑止ではなく、設定が残っていてもクライアントが生成しないことを確認した。既存serverへのattachや次回ログオンのStartup発火は、この陰性検査の成功から推定しない。

2026-11-18のユーザー手動SSH確認は、PSMUX_SESSION=main、Windows Session ID=1、接続前後anchor一致=True、SSH切断後も同じSession 1 serverが生存した。既存未コミット層を含む環境の結果で、attach引数は修正commitと同一。commit単独のクリーン環境再測定とは区別する。修正引数で新規起動した監視helperの継続attach、次回ログオンのStartup実発火、独自update-environment設定の影響は未実測である。

修正後の `tests/ssh-psmux.sh` のTTY実行は未検証。実行前に隔離した固定対象、保持handleで識別できるPID・開始時刻、stdinの接続先、通常終了方法とタイムアウトを記録する。これらを確認できない環境では実行せず、追加SSH接続を代替手段にしない。既存psmux・SSHや試験用接続を対象とした終了処理は使わない。既存の各5件と手動確認の成功は保持し、TTY未実行をその成功で置き換えない。

## 通常の協調再作成

sessionを作り直すと作業中のpaneも終了するため、常用 `main` 内で保存・終了してから要求する。

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -File "$HOME\.dotfiles\scripts\windows-psmux-daily\request-recreation.ps1"
```

制御側は世代cookie入りファイルを提出するだけ。監視が照合し、自身のkill CLIと旧serverの実終了を両方確認してから次を作成する。
提出exit 0は要求ファイルの公開成功であり、再作成の完了ではない。公開後に要求ログの出力だけが失敗してもexit 0を維持し、stderrに提出済み・再送しない旨を表示する。要求を再送せず、監視ログを確認する。
公開前の所有確認・一時ファイル書込み・公開Moveの失敗はexit 1となる。公開済みの要求を取り消すために削除しない。
ログの `coordinated-recreation-ready` と新しいSession 1 server/attachで完了を確認する。

`pwsh -NoLogo -NoProfile -NonInteractive -File tests/windows-psmux-recreation-request.ps1` は、専用TEMPとowner queryのプロセスfacadeで公開前後の結果を検査する。ログ失敗はログ先にディレクトリを置いて再現し、ACLを変更しない。実psmux、既存registry、監視やSSHへ接続しない。

## 残留が疑われる再作成要求の診断と復旧

`recreate.request`は、協調再作成が処理中の場合も存在する。
`main`不在、PID不在、古い更新時刻、cookie不一致だけを根拠に要求を削除しない。
`stop.request`と両方ある場合も、停止を優先して保持する。
この節は手動復旧を判断するための手順であり、自動削除や無人復旧は提供しない。

1. 新しい起動と再作成要求を提出せず、`main.monitor.log`、`main.attach.log`、`recreation.requests.log`の順序と終了記録を確認する。`coordinated-recreation-ready`より前なら、所有照合、kill CLI、旧server終了待ち、要求削除の途中である可能性を残す。処理中と判明したら要求に触れず、その処理の結果を確認する。
2. 復旧へ移ると判断した場合は、作業を保存して他のSSHクライアントと利用者に確認し、停止要求を維持する。常用registryを明示した一覧手順は[#290の対応PR](https://github.com/the9ball/.dotfiles/pull/301)を参照する。別registryの空一覧やclient不在だけで安全と判定しない。
3. 要求提出処理、launcher、monitor、helper、進行中の所有control CLIがすべて終了したことを、実行コマンド、runtime、起動時刻、ログの対応で確認する。要求提出処理は停止確認の直後に公開する可能性があるため、停止ファイルの存在だけでは静止を証明できない。新規起動、ログオンによるStartup発火、別利用者による要求提出が入らない保守時間を確保できなければ、要求は保持して停止する。
4. 静止状態を維持したまま、要求の内容とSHA-256、更新時刻、registryのPIDと起動時刻anchor、ログの世代cookieの対応を記録する。ファイルとログは非公開の保全先に保存する。PID再利用、別世代、壊れた内容、ディレクトリやリンクなど通常ファイルでない状態は自動補正しない。現在のserver世代や要求の対応が確定しなければ、要求を保持して調査へ戻る。
5. 処理主体が終了し、これ以上提出や起動がないこと、および保全した要求と現在の要求が同じであることを再確認する。この条件が揃って残留と判断した要求だけを、手動で保全先へ退避する。停止要求と残るserverは保持する。退避は要求の取消しや旧killの取消しではなく、既に失われたpaneを復元するものでもない。確認中に内容、世代、プロセス状態が変わったら退避せず停止する。
6. 監視を再開するかはserverと作業の状態を確認して別に判断する。既存`main`が残っていればそのまま保持できるが、新規monitorの`new-session`は失敗する。再作成が必要な場合だけ保存と他client確認をやり直し、下記の再起動手順を使う。`stop.request`を最後まで保持し、要求ファイルがなくなっただけで起動可能と扱わない。

この手順は、すべての起動処理と要求提出処理を自動で排他するものではない。
静止の確認ができない場合に要求を残すことが、安全側の復旧中止条件となる。
`pwsh -NoLogo -NoProfile -NonInteractive -File tests/windows-psmux-startup-guards.ps1`は、専用TEMPで本体の起動前guardを抽出し、拒否理由と要求保持を検査する。
実server、Startup、要求ファイルの実復旧は検証しない。

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
- ホストWindows Terminalで `tests/ssh-psmux.sh` は全PASS、終了コード0。これはattach-only修正前の導入時のユーザー実測であり、修正後のTTY stub検査結果ではない。異常系の警告は期待された出力であり、テスト失敗は無し。
- 既存Codex serverとPoC serverは、同じPID・起動時刻・Session 1を維持。停止・置換しなかった。
- PowerShell構文検査と変更ファイルの形式検査は成功。sandboxでのGit Bash/aqua起動は拒否されたため、ホストの実機結果と区別した。

検証後も常用監視とSSHクライアントは接続中のまま維持した。
再起動・再ログオンによるStartupの実発火はまだ観測していない。次回はWindowsへSession 1で対話型ログオンすれば起動する設定であり、SSHだけの先行接続では作成しない。
