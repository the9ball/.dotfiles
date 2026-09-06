# WSL版 Codex Remote Control のセットアップ

この手順は、Windows のログオン時に WSL2 上の Codex Remote Control を起動する構成を再現する。

## 構成

- **起動ディレクトリ**：codex-wsl
- **Windows ランチャー**：codex-wsl/start-codex-wsl.bat
- **WSL ランチャー**：codex-wsl/start-codex-wsl.sh
- **WSL 用 CODEX_HOME**：~/.codex-remote
- **Windows 用 CODEX_HOME**：C:\Users\<ユーザー名>\.codex-personal

Windows ランチャーはタスク スケジューラから呼び出され、WSL ランチャーに処理を渡す。

WSL ランチャーは、Aqua の設定ファイル、Aqua のバイナリディレクトリ、WSL 用 CODEX_HOME を明示してから codex remote-control start を実行する。

~/.codex-remote/AGENTS.md は、WSL 側だけに適用するグローバル指示を置く場所として使う。

Codex は CODEX_HOME 内の AGENTS.md をグローバル指示として読み込むため、Windows 側の指示と WSL 側の指示を分離できる。

## CODEX_HOME を分ける理由

Windows と WSL が同じ物理ディレクトリを参照すること自体は可能である。

ただし、現在の Windows 用 config.toml には Windows 専用のファイルパス、通知コマンド、MCP サーバーの実行ファイルが含まれている。

その config.toml を WSL の Linux 版 Codex から読むと、Windows パスを解釈できず codex login status の前に失敗する。

そのため、Windows 側の設定を ~/.codex-personal に残し、WSL 側は ~/.codex-remote に分けている。

この分離はアカウントを分けるためではない。

両方の auth.json に保存された account_id は一致しており、同じ ChatGPT アカウントを使用している。

共有方式へ変更する場合は、設定を OS 非依存に整理したうえで、config、認証情報、ログ、セッション、スキル、パッケージ情報、SQLite 状態を共有することになる。

Windows と WSL の同時アクセスを避ける運用まで確認できるまでは、現在の分離を維持する。

## 前提

- Windows に WSL2 がインストールされている。
- リポジトリが Windows 側の C:\Users\<ユーザー名>\.dotfiles に配置されている。
- WSL から $HOME/.dotfiles がリポジトリを参照できる。
- WSL で aqua コマンドを実行できる。

## WSL 側の CLI を導入する

WSL の対話型シェルで次を実行する。

~~~sh
cd "$HOME/.dotfiles"
export AQUA_GLOBAL_CONFIG="$HOME/.dotfiles/aqua.yaml"
export PATH="$HOME/.local/share/aquaproj-aqua/bin:$PATH"
aqua install --config "$AQUA_GLOBAL_CONFIG"
codex --version
~~~

AQUA_GLOBAL_CONFIG はシェルのプロファイルに依存せず、この手順とランチャーで明示する。

リポジトリの aqua.yaml には openai/codex が定義されている。

Remote Control は、Aqua 版の CLI だけでなく CODEX_HOME 配下のスタンドアロン実体も必要とする。

同じ WSL シェルで次を実行する。

~~~sh
export CODEX_HOME="$HOME/.codex-remote"
export CODEX_NON_INTERACTIVE=1
curl -fsSL https://chatgpt.com/codex/install.sh | sh
~~~

インストーラーは CODEX_HOME/packages/standalone/current/codex にスタンドアロン実体を配置する。

この手順では通常の codex コマンドを Aqua 版に固定し、Remote Control が必要とするスタンドアロン実体だけを CODEX_HOME から参照する。

## WSL 側の Codex にログインする

同じ WSL シェルで、次を実行する。

~~~sh
export AQUA_GLOBAL_CONFIG="$HOME/.dotfiles/aqua.yaml"
export PATH="$HOME/.local/share/aquaproj-aqua/bin:$PATH"
export CODEX_HOME="$HOME/.codex-remote"
mkdir -p "$CODEX_HOME"
codex login --device-auth
codex login status
~~~

ログイン操作は対話型シェルで行い、認証情報をスクリプトやリポジトリへ保存しない。

codex login status が Logged in using ChatGPT を返せば、WSL 側の認証状態を確認できる。

## Windows のタスク スケジューラへ登録する

PowerShell で次を実行する。

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

この登録は現在ユーザーの対話型ログオン時に実行し、バッテリー使用時も停止しない。

同名タスクが存在する場合は、ランチャーのパスを新しい codex-wsl のパスへ更新する。

## 起動を確認する

PowerShell でタスクの状態を確認し、手動起動する。

~~~powershell
Get-ScheduledTask -TaskName 'Codex Remote Control' |
  Select-Object TaskName, State
Start-ScheduledTask -TaskName 'Codex Remote Control'
Get-ScheduledTaskInfo -TaskName 'Codex Remote Control' |
  Select-Object LastRunTime, LastTaskResult
~~~

WSL 側で長時間実行中の Codex プロセスを確認する。

~~~sh
pgrep -af 'codex remote-control start'
~~~

LastTaskResult が 0 であり、WSL 側に remote-control プロセスが残っていれば、手動起動の確認は完了である。

## WSL 固有の指示を追加する

WSL 側だけの制約や運用規則は ~/.codex-remote/AGENTS.md に記述する。

~~~sh
cat > "$HOME/.codex-remote/AGENTS.md" <<'EOF'
# WSL 用 Codex 指示

ここに WSL 固有の指示を書く。
EOF
~~~

認証情報やアクセストークンは AGENTS.md に書かない。

## トラブルシューティング

### aqua が node を見つけられない

シェルの PATH に Aqua のバイナリディレクトリが入っているか確認する。

~~~sh
export PATH="$HOME/.local/share/aquaproj-aqua/bin:$PATH"
command -v node
command -v codex
~~~

cmd.exe ではシングルクォートが引用符として扱われないため、ログイン操作は対話型 WSL シェルか PowerShell から行う。

### Windows 側の設定を WSL から読んでしまう

WSL ランチャーが CODEX_HOME="$HOME/.codex-remote" を設定しているか確認する。

Windows 側の ~/.codex-personal を WSL の CODEX_HOME に指定すると、Windows 専用パスを含む config.toml の読み込みで失敗する。

### ログイン状態を確認する

~~~sh
export CODEX_HOME="$HOME/.codex-remote"
codex login status
~~~

## 参照

- [Codex の環境変数](https://learn.chatgpt.com/docs/config-file/environment-variables)
- [AGENTS.md の探索規則](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex の WSL ガイド](https://learn.chatgpt.com/docs/windows/wsl)
