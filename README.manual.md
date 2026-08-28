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
