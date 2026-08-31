# 手動セットアップ

新規環境でこのリポジトリを使い始めるときの手順です。通常の更新は、リポジトリのルートで`chezmoi --source "$HOME/.dotfiles" apply`を実行します。

## 1. 前提コマンドを用意する

次のコマンドを、使用するOSの方法でインストールします。

- Git
- chezmoi
- aqua（Windowsは以下の手順）
- Windows: `winget`

### Windowsでのaquaの導入

aquaは自分自身を`aqua root-dir`で表示されるルートの`bin`へ配置して自己更新します。
wingetはその起点を用意するためだけに使い、配置後は重複を残さないようアンインストールします。
WinGetのインストール直後は、PATH変更を現在のPowerShellが認識しないため、新しいPowerShellを開いてから次へ進みます。

```powershell
winget install --id aquaproj.aqua --exact
```

新しいPowerShellで、自己更新とユーザーPATHへの永続登録を行います。次のスニペットは、展開前のPATH文字列とレジストリ型を保持して書き込み、変更時に環境変数の更新を通知します。PATHに同じディレクトリがある場合は追加しません。

```powershell
aqua update-aqua

$aquaRootDirectory = (aqua root-dir).Trim()
$aquaBinDirectory = Join-Path $aquaRootDirectory 'bin'
$environmentKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
if ($null -eq $environmentKey) {
    throw 'Failed to open HKCU:\Environment.'
}

$pathChanged = $false
try {
    $rawUserPath = $environmentKey.GetValue(
        'Path',
        $null,
        [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    )
    $pathValueKind = if ($null -eq $rawUserPath) {
        [Microsoft.Win32.RegistryValueKind]::ExpandString
    } else {
        $environmentKey.GetValueKind('Path')
    }

    if ($pathValueKind -notin @(
        [Microsoft.Win32.RegistryValueKind]::String,
        [Microsoft.Win32.RegistryValueKind]::ExpandString
    )) {
        throw "Unsupported HKCU:\Environment\Path registry type: $pathValueKind"
    }

    $rawUserPath = if ($null -eq $rawUserPath) { '' } else { [string]$rawUserPath }
    $pathEntries = if ([string]::IsNullOrEmpty($rawUserPath)) {
        @()
    } else {
        @($rawUserPath -split ';')
    }
    $normalizedAquaBinDirectory = [IO.Path]::GetFullPath($aquaBinDirectory).TrimEnd('\')
    $hasAquaBinDirectory = $false
    foreach ($pathEntry in $pathEntries) {
        if ([string]::IsNullOrWhiteSpace($pathEntry)) { continue }
        try {
            $expandedPathEntry = [Environment]::ExpandEnvironmentVariables($pathEntry)
            $normalizedPathEntry = [IO.Path]::GetFullPath($expandedPathEntry).TrimEnd('\')
            if ($normalizedPathEntry -ieq $normalizedAquaBinDirectory) {
                $hasAquaBinDirectory = $true
                break
            }
        }
        catch {
            # Ignore malformed existing PATH entries while preserving them.
        }
    }
    if (-not $hasAquaBinDirectory) {
        $newRawUserPath = if ([string]::IsNullOrEmpty($rawUserPath)) {
            $aquaBinDirectory
        } elseif ($rawUserPath.EndsWith(';')) {
            "$rawUserPath$aquaBinDirectory"
        } else {
            "$rawUserPath;$aquaBinDirectory"
        }
        $environmentKey.SetValue('Path', $newRawUserPath, $pathValueKind)
        $pathChanged = $true
    }
}
finally {
    $environmentKey.Close()
}

if ($pathChanged) {
    if (-not ('AquaEnvironmentChangeNotifier' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class AquaEnvironmentChangeNotifier
{
    /// <summary>Broadcasts a user environment change notification.</summary>
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr windowHandle,
        uint message,
        IntPtr parameter,
        string data,
        uint flags,
        uint timeoutMilliseconds,
        out IntPtr result);
}
'@
    }
    $broadcastResult = [IntPtr]::Zero
    [AquaEnvironmentChangeNotifier]::SendMessageTimeout(
        [IntPtr]0xffff,
        0x001A,
        [IntPtr]::Zero,
        'Environment',
        0x0002,
        5000,
        [ref]$broadcastResult
    ) | Out-Null
}
```

PATHの変更を反映するため、もう一度新しいPowerShellを開き、`aqua`が自己更新先から解決されることを確認します。

```powershell
(Get-Command aqua -ErrorAction Stop).Source
```

確認後にWinGet版を削除します。削除後も新しいPowerShellで上の確認を行い、`aqua`のパスが`aqua root-dir`の`bin`配下であることを確認してください。

```powershell
winget uninstall --id aquaproj.aqua --exact
```

以後のaquaの更新は`aqua update-aqua`で行います。
wingetに残したままにすると、実際には使われていない方が`winget upgrade`の対象になり、どちらが動いているのか分からなくなります。

## 2. リポジトリを配置する

```sh
git clone https://github.com/the9ball/.dotfiles.git "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
git submodule update --init --recursive
```

すでにclone済みの場合は、`git pull --rebase`と`git submodule update --init --recursive`で更新します。

## 3. マシン固有の設定を作る

POSIX系のシェルでは次を実行します。

```sh
cp .bashrc.local.example "$HOME/.bashrc.local"
cp .gitconfig.local.example "$HOME/.gitconfig.local"
```

WindowsのPowerShellでは`cp`の代わりに次を実行します。

```powershell
Copy-Item .bashrc.local.example "$HOME/.bashrc.local"
Copy-Item .gitconfig.local.example "$HOME/.gitconfig.local"
```

コピーしたファイルに名前、メールアドレス、マシン固有のPATHなどを設定します。認証情報は保存せず、必要なツールの認証機能を使ってください。

## 4. 差分を確認して適用する

まず適用前の差分を確認し、問題がなければ適用します。

```sh
chezmoi --source "$HOME/.dotfiles" diff
chezmoi --source "$HOME/.dotfiles" apply
chezmoi --source "$HOME/.dotfiles" verify
```

`apply`では、設定ファイルの配置に加えて次の処理が実行されます。

- `aqua.yaml`に定義されたCLIのインストール
- Windowsでは`winget.json`に定義されたAWS CLIとaws-vaultのインストール
- `prek`のGit hook設定
- `~/.agents`、`~/.claude/skills`、`~/.claude/agents`の共有リンク作成（Windowsではジャンクション）

これらのパスに通常のディレクトリや別のリンクがすでにある場合、スクリプトは上書きせず停止します。既存の内容とリンク先を確認し、必要なら手動で退避してから再実行してください。

## 5. 適用後の確認

シェルを再起動するか設定を読み込み直し、Gitや必要なCLIが使えることを確認します。設定を更新したときは、次の順に実行します。

```sh
cd "$HOME/.dotfiles"
git pull --rebase
git submodule update --init --recursive
chezmoi --source "$HOME/.dotfiles" apply
```

セットアップの詳細な挙動を確認したい場合は、[`SETUP.md`](SETUP.md)と`chezmoi/.chezmoiscripts/`を参照してください。

## Agent Skillsの導入

第三者スキルの実体はGitで追跡せず、ロックファイルと復元手順を追跡します。

### Codex pluginの導入

公式の`dotnet/skills`は、plugin本体を`.dotfiles`へvendorせず、Codex marketplaceから取得します。取得元、commit、対象pluginのversionとハッシュは[`.agents/.plugin-lock.json`](.agents/.plugin-lock.json)に記録します。

現在は、安定版の`dotnet` pluginだけを導入します。次のコマンドで、ロックされたcommitから復元できます。

`````sh
codex plugin marketplace add dotnet/skills --ref d68dd70857076a17d4b418649bbcd20a315d59c3
codex plugin add dotnet@dotnet-agent-skills
`````

導入後は新しいCodex CLIセッションを開始してください。pluginを一時停止する場合は`/plugins`で`dotnet`を無効化し、完全に戻す場合は次を実行します。

`````sh
codex plugin remove dotnet@dotnet-agent-skills
codex plugin marketplace remove dotnet-agent-skills
`````

更新は、upstreamの新しいcommitとの差分（manifest、LSP、skills、agents、MCP、外部ダウンロード処理）を確認してから、ロック情報と復元手順を同時に更新します。

### Claude Code pluginの導入

Claude CodeからCodexを呼び出す`codex@openai-codex`と、.NET開発のskillとC# language serverを追加する`dotnet@dotnet-agent-skills`は、plugin本体を`.dotfiles`へvendorせず、marketplaceから取得します。取得元、commit、versionとハッシュは[`.claude/.plugin-lock.json`](.claude/.plugin-lock.json)に記録します。

Claude Codeはmarketplace側のcommit固定に対応しません（`ref`はブランチとタグのみ）。ロックのcommitは、取得時点を記録して更新時の差分確認に使うもので、再現を保証するものではありません。

marketplaceの登録とpluginの有効・無効は、[`chezmoi/dot_claude/modify_settings.json`](chezmoi/dot_claude/modify_settings.json)を正とします。このテンプレートは`~/.claude/settings.json`のうち`extraKnownMarketplaces`と`enabledPlugins`だけを上書きし、`permissions`や`hooks`など他のキーは現在の内容をそのまま書き戻します。Claude Code自身が同じファイルへ書き込むため、ファイル全体を管理すると、その書き込みを巻き戻してしまうためです。

有効・無効の切り替えは、UIではなくテンプレートを書き換えて適用します。UIで切り替えても、次の適用でテンプレートの値に戻ります。

`codex`は無効（`false`）の状態で記録しています。有効化すると`SessionStart`、`SessionEnd`、`Stop`フックが動き出すためです。

`dotnet`は有効（`true`）です。フックは持たず、`setup-local-sdk` skillとC# language serverを追加します。有効化すると、起動時に`dotnet/skills`のリポジトリ全体が`~/.claude/plugins/marketplaces/`へcloneされます（`depth 1`のshallow cloneで約19MB）。pluginの実体はそこから`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`へ展開され、取得したcommitは`~/.claude/plugins/installed_plugins.json`の`gitCommitSha`に記録されます。展開はcloneと同時ではなく、pluginが読み込まれた後に現れます。またC#ファイルを開くと、`dnx`が`roslyn-language-server`のprerelease版をNuGetから取得して常駐させます。動作には.NET SDK 10以降（`dnx`を同梱）が必要です。

`````sh
chezmoi --source "$HOME/.dotfiles" apply "$HOME/.claude/settings.json"
`````

適用の対象は必ずこのパスに絞ってください。対象を指定しない`apply`は、`.bashrc`の更新やaqua、winget、prekの実行まで巻き込みます。

適用後は新しいClaude Codeセッションを開始してください。有効化した場合は、起動時にmarketplaceから`~/.claude/plugins/`配下へpluginが取得されます。使われていないplugin本体は掃除されることがありますが（`~/.claude/plugins/.last_inuse_sweep`）、削除は保証されません。無効な`codex`の実体も`cache/`に残っています。導入状態は`cache/`の有無ではなく、`installed_plugins.json`と`extraKnownMarketplaces`で判断してください。

完全に取り除く場合は、テンプレートから該当キーを削除して適用し、`~/.claude/settings.json`に残ったエントリを手動で消します。`modify_`テンプレートはキーを追加・上書きするだけで、削除はしません。

更新は、upstreamの新しいcommitとの差分（manifest、hooks、scripts、agents、commands、LSP、skills）を確認してから、ロック情報と復元手順を同時に更新します。

`gh-stack`は`.agents/.skill-lock.json`に出所を記録し、次のコマンドで復元します。

```sh
gh skill install github/gh-stack gh-stack
```

Datadogの`dd-pup`、`dd-logs`、`dd-docs`は、リポジトリのルートで次を実行して導入します。

```sh
npx skills add datadog-labs/agent-skills --skill dd-pup --skill dd-logs --skill dd-docs --full-depth -y
```

このコマンドは、`.agents/skills`に3つのスキルを配置し、ルートの`skills-lock.json`を更新します。

`.agents/skills/dd-readonly-delegate`は、このリポジトリで管理する共有スキルです。第三者スキルの導入コマンドでは復元しません。

このスキルはDatadogのメトリクス、ログ、ダッシュボード、ドキュメントの参照に使用します。単発の読み取り調査はサブエージェントへ委譲し、継続的な調査ではメインスレッドが関連スキルとMCPの文脈を保持します。

## Datadog MCPの設定

MCPエンドポイントは次のとおりです。

```text
https://mcp.datadoghq.com/v1/mcp
```

Codexは`~/.codex/config.toml`で`bearer_token_env_var = "DD_ACCESS_TOKEN"`を設定し、環境変数からSATを参照します。Claudeは`~/.claude.json`で`Authorization`ヘッダを設定します。SATの実値は、どちらの設定にもリポジトリにも保存しません。

現在のCodex設定では、`.agents/skills`の共有スキルを認識します。Windowsでは`~/.claude/skills`も`.agents/skills`を参照します。
