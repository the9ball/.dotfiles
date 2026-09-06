# WSL版Codex Remote Controlのセットアップ

この構成は任意です。
Windowsのログオン時にWSL2上のCodex Remote Controlを起動する場合だけ実行します。

通常のCodex CLIはAquaで管理します。
`.codex-remote`の作成、standalone版の導入、ログイン、Windowsの自動起動登録は、`chezmoi apply`では実行しません。

## 実行順

次の順番で実行します。

1. WSL側でAqua管理の通常CLIを確認する。
2. [`CODEX_HOME.md`](CODEX_HOME.md)で`~/.codex-remote`をセットアップする。
3. この文書の手順でWindowsの自動起動を登録する。

`.codex-remote`の手順は、WSL基盤の確認を前提にします。
Windowsの自動起動登録は、`.codex-remote`のログイン確認後に行います。

## 構成

- **リポジトリ**：`$HOME/.dotfiles`
- **Windowsランチャー**：`codex-wsl/start-codex-wsl.bat`
- **WSLランチャー**：`codex-wsl/start-codex-wsl.sh`
- **通常CLI**：Aquaが管理する`codex`
- **Remote Control実体**：`$HOME/.codex-remote/packages/standalone/current/codex`
- **Windows側のCODEX_HOME**：`C:\Users\<ユーザー名>\.codex-personal`

Windowsランチャーはタスクスケジューラから呼び出され、WSLランチャーに処理を渡します。

WSLランチャーは、`$HOME/.codex-remote`のstandalone実体を明示して`codex remote-control start`を実行します。
通常CLIのAqua管理とRemote Controlのstandalone管理を分離するため、ランチャーから裸の`codex`コマンドは呼び出しません。

## WSL基盤を確認する

### 前提

- WindowsにWSL2がインストールされている。
- リポジトリがWindows側の`C:\Users\<ユーザー名>\.dotfiles`に配置されている。
- WSLから`$HOME/.dotfiles`がリポジトリを参照できる。
- WSLで`aqua`コマンドを実行できる。

### Aqua管理の通常CLIを導入する

WSLの対話型シェルで次を実行します。

~~~sh
cd "$HOME/.dotfiles"
export AQUA_GLOBAL_CONFIG="$HOME/.dotfiles/aqua.yaml"
export PATH="$HOME/.local/share/aquaproj-aqua/bin:$PATH"
aqua install --config "$AQUA_GLOBAL_CONFIG"
command -v aqua
command -v codex
codex --version
~~~

`aqua install`は`aqua.yaml`に宣言したバージョンを適用します。
通常の`chezmoi apply`でも同じAqua管理CLIを導入します。

### 通常CLIを更新する

Aqua管理のCodex CLIは、Aquaの宣言を更新してからインストールします。

~~~sh
cd "$HOME/.dotfiles"
export AQUA_GLOBAL_CONFIG="$HOME/.dotfiles/aqua.yaml"
export PATH="$HOME/.local/share/aquaproj-aqua/bin:$PATH"
aqua --config "$AQUA_GLOBAL_CONFIG" update codex
git diff -- aqua.yaml
# 差分を確認してコミットした後に実行する
aqua install --config "$AQUA_GLOBAL_CONFIG"
codex --version
~~~

`aqua update`は`aqua.yaml`を更新し、`aqua install`はその宣言を実体へ反映します。
Aqua管理の`codex`に対して`codex update`を実行すると、Aquaの宣言と実体の管理が分かれるため、この手順では使用しません。

## `.codex-remote`をセットアップする

通常CLIの確認が完了したら、[`CODEX_HOME.md`](CODEX_HOME.md)を実行します。

この手順では、standalone版、専用`CODEX_HOME`、ログイン、WSL固有の`AGENTS.md`を扱います。
認証情報とruntimeデータはリポジトリへ保存しません。

## Windowsの自動起動を登録する

次の条件を満たしてから登録します。

- WSL基盤の確認が完了している。
- `$HOME/.codex-remote/packages/standalone/current/codex`が存在する。
- standalone実体で`login status`が`Logged in using ChatGPT`を返す。

PowerShellで次を実行します。

~~~powershell
$dotfiles = Join-Path $HOME '.dotfiles'
$batch = Join-Path $dotfiles 'codex-wsl\start-codex-wsl.bat'
$arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -Command "& ''{0}''"' -f $batch
$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $arguments -WorkingDirectory $dotfiles
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable
Register-ScheduledTask -TaskName 'Codex Remote Control' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Starts codex-wsl from the dotfiles repository when this user logs on.' -Force
~~~

同名タスクが存在する場合は、`-Force`でアクションを`codex-wsl`のランチャーへ更新します。

## 起動を確認する

PowerShellでタスクの状態を確認し、手動起動します。

~~~powershell
Get-ScheduledTask -TaskName 'Codex Remote Control' |
  Select-Object TaskName, State
Start-ScheduledTask -TaskName 'Codex Remote Control'
Get-ScheduledTaskInfo -TaskName 'Codex Remote Control' |
  Select-Object LastRunTime, LastTaskResult
~~~

WSL側でRemote Controlのプロセスを確認します。

~~~sh
pgrep -af 'codex remote-control start'
~~~

`LastTaskResult`が`0`であり、WSL側にRemote Controlプロセスが残っていれば、手動起動の確認は完了です。

## トラブルシューティング

### standalone実体が見つからない

WSLランチャーは`$HOME/.codex-remote/packages/standalone/current/codex`を直接実行します。
ファイルが存在しない場合は、[`CODEX_HOME.md`](CODEX_HOME.md)のstandalone導入手順を再実行します。

### Windowsタスクが失敗する

タスクのアクションが`codex-wsl/start-codex-wsl.bat`を指していることを確認します。
その後、WSLでstandalone実体の`--version`と`login status`を確認します。

### Windows側の設定をWSLから読んでしまう

WSLランチャーが`CODEX_HOME=$HOME/.codex-remote`を設定していることを確認します。
Windows側の`~/.codex-personal`をWSLの`CODEX_HOME`に指定すると、Windows専用パスを含む設定の読み込みで失敗する可能性があります。

### `AQUA_GLOBAL_CONFIG`が別の設定を指す

WSLランチャーは`$HOME/.dotfiles/aqua.yaml`を明示します。
対話型シェルでAquaの操作を行う場合も、この文書の`export`を先に実行します。

## 参照

- [`CODEX_HOME.md`](CODEX_HOME.md)
- [OpenAI公式のCodex CLI手順](https://learn.chatgpt.com/docs/codex/cli)
- [Codexの環境変数](https://learn.chatgpt.com/docs/config-file/environment-variables)
- [AGENTS.mdの探索規則](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [CodexのWSLガイド](https://learn.chatgpt.com/docs/windows/wsl)
