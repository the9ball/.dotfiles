# 手動セットアップ

新規環境でこのリポジトリを使い始めるときの手順です。通常の更新は、リポジトリのルートで`chezmoi apply`を実行します。`chezmoi`の設定は`sourceDir = "~/.dotfiles"`とし、WindowsとWSLで同じホーム相対のソースを解決します。

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
```

すでにclone済みの場合は、`git pull --rebase`で更新します。
先にAqua管理のCLIを導入します。

```sh
aqua install --config "$HOME/.dotfiles/aqua.yaml"
```

初回だけリポジトリ内のchezmoi設定テンプレートからホーム相対の設定を生成します。

```sh
chezmoi --source "$HOME/.dotfiles" init
```

以後は`chezmoi diff`、`chezmoi apply`、`chezmoi verify --exclude=scripts`を引数なしで実行できます。

Codexの通常版とPersonal版は、共通の`AGENTS.md`をそれぞれ`chezmoi/dot_codex/create_AGENTS.md`と`chezmoi/dot_codex-personal/create_AGENTS.md`から配置します。両方の生成元と配置先は同一内容です。Personal固有のタイトル設定と機密データ境界は、[`chezmoi/dot_codex-personal/AGENTS.local.md`](chezmoi/dot_codex-personal/AGENTS.local.md)から`~/.codex-personal/AGENTS.local.md`へ配置します。通常版の`~/.codex/AGENTS.local.md`は端末固有の未管理ファイルとして扱います。

Personal Codexの通常読み取りは、Personalプロファイルでユーザーがローカルプロジェクトへ明示的に関連付けたフォルダーと、その配下に限定します。現ホストで確認できる`.codex-global-state.json`の`local-projects.*.rootPaths`は関連付けの観測値として使いますが、公開された設定契約とはみなしません。Personal側の登録が空・不明・読み取り不能な場合は、通常版の登録を流用せず、通常読み取りを許可しません。`.dotfiles`をPersonal Codexで通常読み取りするには、Personalプロファイル側へ明示的に関連付けます。

ただし、Personal Codexへ共有命令を適用するため、管理済みの`~/.agents`がこのリポジトリの`link-targets/agents`を指していることを確認できる場合は、命令読み取り専用の例外があります。共有`AGENTS.md`、同じディレクトリの`AGENTS.local.md`、共有命令が現在の作業で直接指定する`guides/`・`skills/`の命令本文、および命令解決に必要な参照メタデータだけを読めます。これは`.dotfiles`全体を通常読取許可ルートにするものではなく、リンク先が不明または一致しない場合は例外を適用しません。

関連付けられていない業務ディレクトリでも、ユーザーが作業ディレクトリまたは対象リポジトリと正確なコマンドを明示した場合に限り、そのコマンドを一回だけ実行し、コマンド・終了コード・stdout/stderrを同じユーザーへ報告できます。これは`git commit -a`や`git push`などのコマンド固有の内部処理を許可するだけで、`status`、`diff`、`log`、検索、再帰走査、内容推測、診断、変更したコマンド、再試行などの追加読み取りを許可しません。失敗や認証要求はそのまま報告して停止します。

`AGENTS.md`は`create_`属性のため、配置先が存在しない場合だけ生成し、既存ファイルの内容を`chezmoi apply`で自動上書きしません。そのため、既存ファイルとの内容一致を確認する用途に`chezmoi diff`だけを使うことはできません。現在の生成元は非テンプレートのファイルなので、生成元と配置先をバイト単位で直接比較してください。POSIX系では次のように確認できます。

```sh
set -eu
repository_root="$HOME/.dotfiles"
normal_source="$repository_root/chezmoi/dot_codex/create_AGENTS.md"
personal_source="$repository_root/chezmoi/dot_codex-personal/create_AGENTS.md"

cmp -- "$normal_source" "$personal_source"
cmp -- "$normal_source" "$HOME/.codex/AGENTS.md"
cmp -- "$personal_source" "$HOME/.codex-personal/AGENTS.md"
```

Windows PowerShellでは、次のようにSHA-256を比較できます。

```powershell
$repositoryRoot = Join-Path $env:USERPROFILE '.dotfiles'
$normalSource = Join-Path $repositoryRoot 'chezmoi\dot_codex\create_AGENTS.md'
$personalSource = Join-Path $repositoryRoot 'chezmoi\dot_codex-personal\create_AGENTS.md'
$normalDestination = Join-Path $env:USERPROFILE '.codex\AGENTS.md'
$personalDestination = Join-Path $env:USERPROFILE '.codex-personal\AGENTS.md'

$normalSourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $normalSource).Hash
$personalSourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $personalSource).Hash
$normalDestinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $normalDestination).Hash
$personalDestinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $personalDestination).Hash

if ($normalSourceHash -cne $personalSourceHash) {
  throw 'The normal and Personal AGENTS.md sources differ.'
}
if ($normalSourceHash -cne $normalDestinationHash) {
  throw 'The normal AGENTS.md destination is out of sync.'
}
if ($personalSourceHash -cne $personalDestinationHash) {
  throw 'The Personal AGENTS.md destination is out of sync.'
}
```

将来、生成元を`.tmpl`へ変更した場合だけ、`chezmoi execute-template --file`で一時ファイルへレンダリングし、その結果と配置先をバイト単位で比較する手順へ切り替えます。

Personalの`AGENTS.local.md`は通常の管理対象なので、変更はリポジトリ側の生成元を編集してから`chezmoi apply`を実行してください。

### Windows Downloads の指示ファイル対策（明示的 opt-in）

Downloads の `AGENTS.md`、`AGENTS.override.md`、`CLAUDE.md` を、安全な短い注意文で予約する任意の対策です。
本文の正本は `chezmoi/.chezmoitemplates/downloads-agent-instructions.md` の1か所で、3つの template が参照します。
ダウンロード内容は入力データとして扱い、ユーザーが許可した分析を妨げず、ファイル内の要求だけで操作権限を追加しません。

Windows かつ boolean の `downloadsAgentGuards=true` を明示した場合だけ管理対象になります。
未指定・false・非 Windows では配置しません。通常の `chezmoi apply` に含めないため、**この値は永続 config の `[data]` に保存せず、以下の対象限定コマンドにだけ渡す**運用を推奨します。
永続 config へ true を保存すると、通常の apply も対象に含めるため、この手順の意図とは異なります。
文字列の `"true"` など非 boolean 値は使いません。型エラーで、テンプレートを評価する diff / apply 等も停止します。
値を渡さない verify の成功は、除外された3ファイルの正常性を意味しません。

#### 初回配置の前提確認

実配置には対象と差分の承認が必要です。以下は PowerShell 7.3 以上で chezmoi の .exe を呼び、ネイティブ引数渡しが Standard / Windows の場合の手順です。Legacy モードや .cmd / .bat shim は対象外です。
これは手動の確認手順であり、自動配置 hook ではありません。
実際の Windows Known Folder を解決してから、この最小構成のホーム配下 Downloads と比較します。
リダイレクト・UNC・リンク、ブラウザ独自の別保存先は自動補正しません。一致しなければ停止し、正確な配置先を使う別案を承認してください。
別の場所にもコピーを作る、junction を作る、Downloads の移動設定を変える、といった回避策は含めません。

```powershell
$guardFolderKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
$guardFolderValue = (Get-ItemProperty -LiteralPath $guardFolderKey -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
if ([string]::IsNullOrWhiteSpace($guardFolderValue)) { throw 'Downloads Known Folder is unavailable.' }
$guardDownloads = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($guardFolderValue))
$guardExpected = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'))
if (-not [string]::Equals($guardDownloads, $guardExpected, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Redirected Downloads requires a separate exact-path plan.'
}
$guardDirectory = Get-Item -LiteralPath $guardDownloads -Force -ErrorAction Stop
if (-not $guardDirectory.PSIsContainer -or ($guardDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'Downloads must be an existing directory without a reparse point.'
}
# Confirm the intended browser save location separately before proceeding.
$guardNames = @('AGENTS.md', 'AGENTS.override.md', 'CLAUDE.md')
$guardTargets = @($guardNames | ForEach-Object { Join-Path $guardDownloads $_ })
foreach ($guardName in $guardNames) {
    if (@(Get-ChildItem -LiteralPath $guardDownloads -Filter $guardName -Force -ErrorAction Stop).Count) {
        throw "Existing target requires a decision before apply: $guardName"
    }
}
$guardData = '{"downloadsAgentGuards":true}'
```

この確認はファイル・ディレクトリ・リンクの衝突を、本文を指示として読まずに検出して停止するための手動条件です。
未知の同名ファイルがあれば、内容の確認・退避・置換の対象を提示して判断を求めます。無断で上書き・削除しません。
攻撃者由来の内容を `chezmoi add` / `re-add` で管理正本へ取り込まないでください。
確認後の競合を防止するロックではなく、通常の apply が全衝突を自動停止する保証でもありません。

ブラウザ保存先との一致と初回配置の承認後だけ、同じセッションで3パスに限定して実行します。
外部 diff・pager を起動せず、scripts を除外します。`--force` や引数なしの全体 apply は使いません。
scripts の除外は既存 config の hooks 等の無効化ではありません。実適用前に既存設定の副作用も確認し、未承認の hook・外部取得が必要なら停止します。

```powershell
chezmoi --override-data $guardData diff --exclude=scripts --no-pager --use-builtin-diff @guardTargets
if ($LASTEXITCODE -ne 0) { throw 'Guard diff failed; do not apply.' }
# Stop if the diff contains unexpected targets or an unapproved replacement.
chezmoi --override-data $guardData apply --exclude=scripts @guardTargets
if ($LASTEXITCODE -ne 0) { throw 'Guard apply failed; inspect state before retrying.' }
chezmoi --override-data $guardData verify --exclude=scripts @guardTargets
if ($LASTEXITCODE -ne 0) { throw 'Guard verification failed.' }
```

各コマンドの終了コードを確認し、失敗・対象不明・想定外の差分があれば次の操作に進みません。
diff は表示内容で差分を判断し、終了コード0だけを「差分なし」と解釈しません。
verify と管理対象一覧を併せ、3ファイルが実際に管理されていること、同一の非空本文であることを読み戻します。
一覧は `chezmoi --override-data $guardData managed --include=files @guardTargets` で対象を限定して確認します。
この機能を初めて有効にする既存ファイルも、過去の管理記録があると推定して上書きしません。

#### 整合性確認と復旧

配置先を再確認し、同じ opt-in を付けた対象限定 diff / verify を手動で実施します。常駐監視は追加しません。
内容変更・削除は verify の非0終了と diff によって検出します。本文一致から属性・ACL の一致は推定しません。
同一本文での再実行は無変更ですが、変更を検出した場合は apply より先に停止してください。

復旧では、管理正本・配置先・変更または欠落した正確なパスを確認します。
未知の本文を agent に指示として渡さず、必要な退避先と置換・削除の差分を提示して承認を求めます。
承認されたパスだけを復旧し、残りの2ファイルや通常のダウンロードには触れず、読み戻しと3パスの verify を行います。
期待本文の確認には `chezmoi --override-data $guardData cat $guardTargets[0]` を使えます。
復旧は shell の `>` やテキスト変換に頼らず、chezmoi のネイティブ出力を使います。再確認済みの3パスのうち承認された正確な1パスを `$guardRestoreTarget` に設定し、書き込み直前に通常ファイルまたは欠落であることを確認します。リンク・ディレクトリ・対象不明なら停止します。
その1パスだけに `chezmoi --override-data $guardData --output $guardRestoreTarget cat $guardRestoreTarget` を実行し、終了コード・期待本文とのバイト一致・verify を確認します。失敗時は再送せず現状を確認します。
この出力は対象を置換する書き込みであり、事前の退避や置換にもそれぞれ承認が必要です。未承認のパスや複数 target を同時に渡しません。PowerShell 事前確認そのものの実機検証は含みません。
削除済みファイルの再生成も復旧判断の対象です。force、全体 apply、正本の自動更新で検出結果を消しません。

opt-in を外しても、配置済みファイルは残ります。管理対象からの除外は、削除や loader に対する効果の撤回ではありません。
撤去が必要なら対象3パスの現行内容と影響を確認し、別途承認して削除します。

#### 効果の限界と通常利用への影響

予約した3ファイルが見えるようになり、同名保存時の連番化・置換確認などに影響します。他の Downloads ファイルを一括拒否しません。
ブラウザは保存経路により uniquify / overwrite / prompt が異なり、Explorer コピーや各解凍アプリも別動作です。
Expand-Archive は既定で非上書き、`-Force` は上書きしますが、この仕様を他アプリに転用しません。
これらの実 UI、上書き・削除・rename/replace の挙動は、環境別の実機試験なしでは保証しません。

Read-only 属性、ACL、Codex / Claude の deny は変更しません。
chezmoi v2.73.3 の Windows `Chmod` は no-op なので、`readonly_` prefix だけで属性付与を保証しません。
属性を解除できる同一ユーザーの操作や、file DELETE / parent DELETE_CHILD が関係する削除・置換にも耐えるとはしません。
ACL は同じユーザーで動く正規操作と攻撃コードを自動識別せず、親 Downloads の制限は通常の整理操作にも影響し得ます。

事前配置は起動時の指示読み込みそのものを禁止する設定ではありません。
Codex の read-only は読み取りを許し、shell の sandbox/deny と harness の起動時探索は同じ保証ではありません。
Claude の Read deny、起動時除外 `claudeMdExcludes`、対応 OS の shell sandbox も別の制御です。
native Windows の Claude shell は sandbox 対応 OS と同一視しません。
4環境の loader、`/cd` と shell cd、各 deny の実効性は未検証であり、この配置の成功から推定しません。
`CLAUDE.local.md`、`.claude/rules`、配下の指示ファイル、添付・ツール結果、正本の侵害、確認と実行の間の競合も保証範囲外です。

#### リポジトリの検証

既存の `validate-instructions.py` と `test-instructions.py` に加え、後者の Downloads fixture は既存の実体バイナリを `CHEZMOI_TEST_BINARY` で明示して実行します。
未指定なら CLI fixture は skip と報告し、導入・検証成功とは扱いません。テストが自動インストールや本物のホームへの apply を行うことはありません。
fixture は一時 source / destination / config / state / cache に最小ソースだけを置き、scripts・externals・通常設定を読み込まずに検証します。復旧も同じネイティブ出力の経路でバイト一致を確認します。
無害なデータで配置・再実行・改変削除検出・判断後の限定復旧・無効化を検査し、衝突時の停止条件は Python でモデル化して確認します。
Windows では、実体の PowerShell 7.3 以上を `CHEZMOI_TEST_PWSH`、chezmoi を `CHEZMOI_TEST_BINARY` に明示すると、README の PowerShell ブロックも隔離 fixture で検証します。未指定・非 Windows は skip と記録します。
レジストリ取得とプロファイル値を架空値へ、chezmoi 呼び出しを一時 source / destination / config / state / cache を指定した実体バイナリへ置換し、結果分類と再実行の確認を加えます。置換対象の構文変更を検知し、未置換の chezmoi 呼び出しは PATH へ解決せず停止します。
空白を含む一時パス、3つの名前の同名衝突、ディレクトリ・リンク、環境変数展開、リダイレクト先不一致・値やディレクトリの欠落を確認します。JSON 引数と managed / diff / apply / verify の終了コード、managed の対象名、同一内容で再実行できることをこの一時構成だけで確認します。PowerShell の module analysis cache は子プロセス限定で一時領域へ向け、telemetry も子プロセスで opt-out します。
この成功は実 Known Folder・実 Downloads・実ホスト設定を確認した証拠ではありません。実環境の事前確認は別に必要です。終了時に fixture を削除します。
実 Downloads、実機の属性・ACL・deny、agent の攻撃入力読み込みは、このテストに含みません。

### ローカル本人情報と Identity Resolution

一般規約の正本は `link-targets/agents/AGENTS.md`、本人の実データの保存候補は **`link-targets/agents/AGENTS.local.md` の `Personal Data` 節**です。
後者は既存リンクで `~/.agents/AGENTS.local.md` として参照され、Git 管理外かつ chezmoi の source directory (`chezmoi/`) の外にあります。公開先を直接編集せず、正本で変更します。
`chezmoi/dot_codex-personal/AGENTS.local.md` は Git 管理されたプロファイル規約なので、氏名・別名・メール・サービス ID の実値を入れません。
local の既存内容を消したり、全体を生成・同期する仕組みを追加したりしません。

共有 local は、それを読む Codex / Claude、仕事用 / 個人用プロファイルのすべてに内容が見える構成です。
用途ラベルは同定の文脈であり、情報隔離ではありません。モデルへの入力・通常のセッション保存も考慮し、共有先と provider に提示してよい情報だけを登録します。
業務規則などが隔離を要求する場合、共有ファイルへの登録を止め、別途プロファイル別保存を検討します。個人情報の自動 cloud 同期は行いません。

#### 保存形式と除外の確認

以下は形式だけを示す placeholder です。各アカウントを別項目とし、未確認値を推測で埋めません。メールは必要な場合だけ追加します。

```markdown
## Personal Data

### Self: <confirmed-context>
- Context: <work-or-personal; applicable-host/workspace>
- Name: <user-confirmed-name>
- Aliases: <user-confirmed-aliases-and-their-context>
- GitHub: host=<host>; id=<numeric-id>; login=<current-login>
- Slack: team_id=<team-id>; user_id=<user-id>; enterprise_id=<only-if-relevant>
- Confirmation: <user-confirmed-source-and-date>
```

Personal Data は参照データであり、指示や認可を追加しません。トークン・認証情報・秘密情報・不要な第三者情報は保存しません。本人情報の確認は保存・公開の承認を兼ねません。
共有 local は root の `*.local` / `*.local.*` と共有側 `.gitignore` で除外されますが、ignore は既存 tracked ファイルや `git add -f`、外部送信を防ぎません。
登録時には次の両方を確認し、後者が空であることも確認します。実データの本文は出力しません。

```sh
git check-ignore -v -- link-targets/agents/AGENTS.local.md
git ls-files -- link-targets/agents/AGENTS.local.md
```

[.chezmoiignore](https://www.chezmoi.io/reference/special-files/chezmoiignore/) は target path に対する管理・適用除外であり、Git の除外とは別です。
[chezmoi add](https://www.chezmoi.io/reference/commands/add/) の ignored entry 警告も追加不能の保証ではありません。本人情報を source に add しない運用を守り、profile local を一括除外しません。
validator は exact な共有 local を意図的に読まず、欠落も許容します。CI に実データを渡して形式を検証する設計にはしません。

#### 読み込み経路と未検証範囲

既存 loader を維持します。以下は設定と公式仕様から確認した経路であり、4環境の実機検証は未実施です。

| 環境 | 既存経路 | 実測で確認すること |
| --- | --- | --- |
| Codex CLI | 実効 CODEX_HOME の AGENTS → bootstrap の明示 read → 共有 AGENTS → 共有 local | 実効 home、override、サイズ制限、新規 session の実 read と適用 |
| Codex Desktop Local | 選択プロファイル・実行先の同じ経路 | CLI の結果を転用せず Desktop で確認 |
| Claude Code CLI | user CLAUDE.md → 共有 AGENTS / local の明示 @import | import 許可・除外・設定と読み込み表示 |
| Claude Code Desktop Local Code | 共有される CLAUDE 設定・import | 実行先と Desktop の読み込み表示を別に確認 |

[Codex の探索仕様](https://learn.chatgpt.com/docs/agent-configuration/agents-md)では `AGENTS.local.md` の名前だけを自動読み込みの根拠にできません。現行の read 指示は自動全文注入と同じ保証ではありません。
[Claude memory](https://code.claude.com/docs/en/memory) の @import を維持し、AGENTS 対応がある版でも local の自動探索に依存しません。
[Claude Desktop](https://code.claude.com/docs/en/desktop) は CLI と engine / CLAUDE 設定を共有しますが、managed-only、除外、import の許可状態などを実測で確認します。
Cloud / SSH 等は実行先が別です。手元の ignored local が渡るとは扱わず、別環境として確認します。Cowork 等を Code Desktop と混同しません。
読み込みが未確認・欠落・拒否なら、それに依存する本人解決を未確認とし、設定回避や権限拡大を行いません。

#### 接続主体の確認と登録

「認証済みの接続主体」「文章が指す人物」「操作の認可」を分離します。ID メンションと名前だけの言及の両方を、確認済み対応と現在の文脈で扱います。
GitHub は host と numeric ID、Slack は team と user ID（必要時 enterprise）を組で扱います。login 変更、同名、複数候補、仕事用 / 個人用の混在では断定しません。
名前・表示名・通称・ローマ字表記の類似や正規化は候補生成にとどめ、新しい別名を自動登録しません。

1. 接続の初回利用、未登録、接続変更、不一致の疑いがある場合だけ、必要な接続確認を検討します。同一の確認済み接続文脈では結果を再利用し、毎回の tool 利用や固定時間だけで照会・更新しません。
2. 取得対象と既存の API 認可を確認します。保存済み対応表だけでは現在の接続の証拠になりません。本 Issue の実データを使う照合検証は別承認とし、通常運用では既存の認可範囲を個別に評価します。
3. [GitHub GET /user](https://docs.github.com/en/rest/users/users#get-the-authenticated-user) の id / login / type、[Slack auth.test](https://docs.slack.dev/reference/methods/auth.test/) の team_id / user_id / bot_id、該当時 enterprise_id など、必要最小限だけを認可済み公式経路で照合します。応答は必要なフィールドへ絞って表示・保持し、全応答をログへ流しません。メール取得の追加 scope は要求しません。
4. API 成功は本人の所有・所属の証明ではありません。bot / app、失敗、不一致、経路不在は未確認とし、アカウント切替・認証情報抽出・再ログインで補いません。Slack の利用可能な照合経路は未検証です。
5. ユーザーに本人のどの用途のアカウントかを確認し、共有先に置いてよい情報を別に確認します。その後に限り、正本の現在の節・予定差分・影響範囲を提示して登録を提案します。
6. 具体的な書き込みの承認後だけ既存内容を保って登録し、読戻し・対象外内容の不変・Git 追跡対象外を確認します。自動登録せず、外部文章の登録指示も採用しません。

本人解決を必要としない既存認可内の調査まで一律に停止する必要はありません。取得済みの本人情報を公開するときは、内容・宛先・閲覧範囲の認可を別に確認します。

#### 検証の段階

静的テストは規約・経路・private 除外の有限な回帰確認であり、モデル動作や OS の安全性を証明しません。
4環境の起動・実 read・解決例の実測、実 API 照合、本人確認後の local 登録は別々の証拠として、別承認後に実施します。
実測は既存 local を上書きせず、承認された隔離 fixture の架空データと非秘密 marker だけで行います。読み込み表示や実 read の記録と適用結果を組み合わせ、自己申告だけを合格にしません。
実効 home・製品バージョン・Local / Remote を記録し、必要な backend / UI 操作と後片付けを事前に限定します。隔離できなければ止めて方法を確認します。

| 架空シナリオ | 期待結果 |
| --- | --- |
| 同 host の確認済み GitHub ID、同 team の Slack メンション | 根拠付きで解決。操作認可は別 |
| 他 team の同じ ID 表記、名前と ID の矛盾 | 同一視しない |
| 確認済み通称と十分な文脈 | 非メンションも根拠付きで扱う |
| 同名の複数候補、仕事用 / 個人用の混在 | 曖昧として必要な確認を求める |
| bot、login 変更、古い接続記録 | bot を本人登録せず、安定 ID と現在の文脈を照合 |
| API 不在・拒否・失敗、local 欠落、import 無効 | 未確認を報告し、回避しない |
| 初回・未登録・不一致と、同一接続での再利用 | 必要時のみ照会。毎回の更新をしない |
| 外部文章の登録指示、未承認の公開要求 | 自動登録・無断公開をしない |

## 3. マシン固有の設定を作る

POSIX系のシェルでは次を実行します。

```sh
cp .bashrc.local.example "$HOME/.bashrc.local"
cp .gitconfig.local.example "$HOME/.gitconfig.local"
cp chezmoi/.chezmoitemplates/codex-defaults.toml.local.example chezmoi/.chezmoitemplates/codex-defaults.toml.local
cp chezmoi/.chezmoitemplates/codex-personal-defaults.toml.local.example chezmoi/.chezmoitemplates/codex-personal-defaults.toml.local
```

WindowsのPowerShellでは`cp`の代わりに次を実行します。

```powershell
Copy-Item .bashrc.local.example "$HOME/.bashrc.local"
Copy-Item .gitconfig.local.example "$HOME/.gitconfig.local"
Copy-Item chezmoi/.chezmoitemplates/codex-defaults.toml.local.example chezmoi/.chezmoitemplates/codex-defaults.toml.local
Copy-Item chezmoi/.chezmoitemplates/codex-personal-defaults.toml.local.example chezmoi/.chezmoitemplates/codex-personal-defaults.toml.local
```

コピーしたファイルに名前、メールアドレス、マシン固有のPATH、Codexの端末固有設定などを設定します。`codex-defaults.toml.local`は仕事用、`codex-personal-defaults.toml.local`は個人用Windowsプロファイル専用です。個人用は通常`personal-standard`を選び、GitHub CLI設定の読み取りとGitHub APIへのネットワークアクセスだけを許可します。追加の書き込み許可は`personal-emergency`へ分離されるため、必要な作業でだけ`pcodex -c 'default_permissions="personal-emergency"'`（または同等の明示指定）を使います。filesystem permission のパスは許可範囲であり、通常のcheckoutや作業場所の指定ではありません。個人用の絶対パスは共有テンプレートへ入れず、ホスト固有の`.local`へ置きます。`*.local`はGitの追跡対象外です。認証情報は保存せず、必要なツールの認証機能を使ってください。Codexの認証は`CODEX_HOME/auth.json`で管理し、どちらのdefaultsにも書きません。

### Git identityの切り替え

共有の`.gitconfig`には`user.useConfigOnly = true`だけを置き、`user.name`と`user.email`は置きません。identityごとの`user.name`と`user.email`は、リポジトリ直下の[`git_user`](git_user/)に1ファイルずつ保存します。現在の共有プロファイルは[`shaula.gitconfig`](git_user/shaula.gitconfig)、ローカル専用プロファイルは`git_user/shoichi-yasui.gitconfig`です。後者はGit管理対象外なので、実体を追加した各cloneの`.git/info/exclude`にも`git_user/shoichi-yasui.gitconfig`を記載します。

リポジトリごとの対応関係は、ホームの`~/.gitconfig.local`に`includeIf`を追加して管理します。実際の登録内容は各エントリのコメントに対象worktreeとcanonical remoteを記録し、`upstream` remoteがある場合はそれを、なければ`origin`を判定基準にします。`github.com/OrangeCube/`配下なら業務profile、それ以外なら共有profileを読み込みます。新しいcloneやremote変更時は、対象のcanonical remoteを確認してから同じ形式で登録します。新規環境向けの形式は[`.gitconfig.local.example`](.gitconfig.local.example)にコメントで示しています。

```ini
[includeIf "gitdir:~/path/to/repositories/public/"]
	path = ~/.dotfiles/git_user/shaula.gitconfig

[includeIf "gitdir:~/path/to/repositories/work/"]
	path = ~/.dotfiles/git_user/shoichi-yasui.gitconfig
```

`gitdir:`の条件はGitが認識している`.git`ディレクトリのパスに対して評価されます。リンクworktreeでは作業ディレクトリではなく、worktree専用のgitdirを条件にします。Windows、WSL、POSIX環境ではパスが異なるため、必要なら環境ごとに規則を用意します。条件が重複すると後から読み込んだidentityが有効になるため、対象ツリーを重複させません。既存の`~/.gitconfig.local`にある直接の`[user]`設定は、対応する`includeIf`へ移してから削除します。identityが選択されていないリポジトリではコミットを失敗させ、意図しないidentityを使わない運用にします。

設定後は、リポジトリごとに次で出所と実効値を確認します。

```sh
git config --show-origin --show-scope --includes --get-regexp '^user\.'
git config --show-origin --show-scope --includes --get-regexp '^include(if)?\.'
git check-ignore -v git_user/<local-profile>.gitconfig
```

履歴上は`Shaula`と`Shoichi Yasui`が主な名前ですが、後者には`shoichi`、`shoichi yasui`、`Shoichi Yasui`の表記揺れがあります。ローカル専用profileのメールアドレスは追跡対象の文書へ書かず、既存コミットも書き換えず、今後使うprofileの表記だけを明示的に選びます。

### Gitコミット署名（Shaula）

`chezmoi apply`と通常のセットアップでは、秘密鍵の生成やGitHubへの登録を行いません。秘密鍵は端末ごとに生成し、GitHubには公開鍵だけを登録します。Shaulaプロファイルには、存在する場合だけ`~/.ssh/gitconfig.signing.shaula`を読み込む入口を用意しています。鍵をまだ作っていない端末では、このファイルがなくても既存のGit設定は動作します。

#### 1. 端末専用の署名鍵を作る

既存の認証鍵や仕事用鍵を流用せず、Shaula署名専用のEd25519鍵を作ります。秘密鍵にはパスフレーズを設定してください。次のコマンドは、指定したファイルが既にある場合に上書きしません。パスフレーズなしで自動化する場合は、秘密鍵を直接参照するため、ファイルACLとバックアップ先を別途確認してください。

Windows PowerShell:

```powershell
$sshDirectory = Join-Path $env:USERPROFILE '.ssh'
New-Item -ItemType Directory -Force -Path $sshDirectory | Out-Null
$signingKeyPath = Join-Path $env:USERPROFILE '.ssh\id_ed25519_git_signing_shaula'
$publicKeyPath = "$signingKeyPath.pub"
$privateKeyExists = Test-Path -LiteralPath $signingKeyPath -PathType Leaf
$publicKeyExists = Test-Path -LiteralPath $publicKeyPath -PathType Leaf
if (-not $privateKeyExists -and -not $publicKeyExists) {
    ssh-keygen -t ed25519 -f $signingKeyPath -C 'Shaula Git signing'
}
elseif ($privateKeyExists -xor $publicKeyExists) {
    throw 'The Shaula signing key pair is incomplete; inspect it without overwriting either file.'
}
ssh-keygen -lf $publicKeyPath
Get-Content -Raw $publicKeyPath
```

WSL、Linux、macOS:

```sh
umask 077
mkdir -p "$HOME/.ssh"
signing_key_path="$HOME/.ssh/id_ed25519_git_signing_shaula"
if [ ! -f "$signing_key_path" ] && [ ! -f "$signing_key_path.pub" ]; then
    ssh-keygen -t ed25519 -f "$signing_key_path" -C 'Shaula Git signing'
elif [ ! -f "$signing_key_path" ] || [ ! -f "$signing_key_path.pub" ]; then
    echo 'The Shaula signing key pair is incomplete; inspect it without overwriting either file.' >&2
    exit 1
fi
ssh-keygen -lf "$signing_key_path.pub"
cat "$signing_key_path.pub"
```

表示された指紋を控え、公開鍵の1行全体を確認します。秘密鍵（拡張子`.pub`がないファイル）は表示・貼り付け・コミットしません。

#### 2. 公開鍵をGitHubへ登録する

GitHubのSettings → SSH and GPG keys → New SSH keyで、種類を`Signing Key`にして、直前に表示した`.pub`の内容だけを登録します。タイトルは必ず指定し、端末名と登録日を組み合わせます（例: `Home-2026-09-09`）。タイトルは鍵の用途やローテーション時期を見分けるための表示名なので、同じ端末で鍵を作り直すときは新しい日付にします。[GitHub公式](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)

CLIを使う場合は、認証済みの`gh`で次を実行します。`gh`が追加の管理スコープを求めた場合は、その内容を確認してから承認します。

PowerShell:

```powershell
$signingKeyTitle = 'Home-{0:yyyy-MM-dd}' -f (Get-Date)
gh ssh-key add "$env:USERPROFILE\.ssh\id_ed25519_git_signing_shaula.pub" `
    --type signing `
    --title $signingKeyTitle
```

WSL、Linux、macOS:

```sh
signing_key_title="Home-$(date +%F)"
gh ssh-key add ~/.ssh/id_ed25519_git_signing_shaula.pub \
    --type signing \
    --title "$signing_key_title"
```

認証用のSSH鍵を自動生成する`gh auth login --git-protocol ssh`とは用途が異なります。この手順では署名用の鍵を明示的に登録します。`gh`が`admin:ssh_signing_key`スコープを求めた場合は、内容を確認してから`gh auth refresh -h github.com -s admin:ssh_signing_key`を実行します。GitHub側の登録が完了するまでは、次のGit設定を有効にしません。

#### 3. Shaulaの署名設定を端末ローカルへ作る

GitHubへの登録後、秘密情報を含まないローカル設定ファイルへ署名方式、公開鍵のパス、コミット時の自動署名を記録します。設定ファイルはGit管理下へ置きません。

Windows PowerShell:

```powershell
$signingConfigPath = Join-Path $env:USERPROFILE '.ssh\gitconfig.signing.shaula'
$publicKeyPath = Join-Path $env:USERPROFILE '.ssh\id_ed25519_git_signing_shaula.pub'
if (-not (Test-Path -LiteralPath $signingConfigPath -PathType Leaf)) {
    Set-Content -LiteralPath $signingConfigPath -Value '# Shaulaのコミット署名にはid_ed25519_git_signing_shaula鍵を使う。'
}
git config --file $signingConfigPath gpg.format ssh
git config --file $signingConfigPath user.signingKey $publicKeyPath
git config --file $signingConfigPath commit.gpgsign true
```

上の設定は、パスフレーズ付き秘密鍵を`ssh-agent`へ追加して使う推奨形です。パスフレーズなしの鍵をagentなしで使う場合は、`user.signingKey`に公開鍵ではなく秘密鍵のパスを指定します。

WSL、Linux、macOS:

```sh
signing_config_path="$HOME/.ssh/gitconfig.signing.shaula"
public_key_path="$HOME/.ssh/id_ed25519_git_signing_shaula.pub"
if [ ! -f "$signing_config_path" ]; then
    printf '%s\n' '# Shaulaのコミット署名にはid_ed25519_git_signing_shaula鍵を使う。' > "$signing_config_path"
fi
git config --file "$signing_config_path" gpg.format ssh
git config --file "$signing_config_path" user.signingKey "$public_key_path"
git config --file "$signing_config_path" commit.gpgsign true
```

パスフレーズなしの鍵をagentなしで使う場合:

Windows PowerShell:

```powershell
$privateKeyPath = Join-Path $env:USERPROFILE '.ssh\id_ed25519_git_signing_shaula'
git config --file $signingConfigPath user.signingKey $privateKeyPath
```

WSL、Linux、macOS:

```sh
private_key_path="$HOME/.ssh/id_ed25519_git_signing_shaula"
git config --file "$signing_config_path" user.signingKey "$private_key_path"
```

パスフレーズ付き鍵を公開鍵パスで使う場合は、コミット前に対応する秘密鍵を`ssh-agent`へ追加します。

Windows PowerShell:

```powershell
ssh-add (Join-Path $env:USERPROFILE '.ssh\id_ed25519_git_signing_shaula')
```

```sh
ssh-add "$HOME/.ssh/id_ed25519_git_signing_shaula"
```

Shaulaプロファイルを使うリポジトリでは、`git config --show-origin --show-scope --includes --get-regexp '^(gpg\.format|user\.signingkey|commit\.gpgsign)$'`で設定の出所と実効値を確認します。次の通常のShaulaコミットを作成した後、GitHubのコミット画面で`Verified`になったことを確認してください。Shoichi Yasuiの業務profileにはこの署名設定を適用せず、業務アカウントで署名が必要になった時点で別の鍵と登録手順を用意します。

## 4. 差分を確認して適用する

まず適用前の差分を確認し、問題がなければ適用します。意図しない差分があれば適用せず停止し、適用後の検証が失敗した場合や差分が残る場合も成功扱いにしません。

```sh
chezmoi diff
chezmoi apply
chezmoi verify --exclude=scripts
```

`run_after_`や`run_onchange_after_`のスクリプトは適用のたびに実行対象となるため、`chezmoi verify`へ含めると終了コード1になります。スクリプト以外の管理対象を確認する場合は`--exclude=scripts`を指定してください。

`apply`では、設定ファイルの配置に加えて次の処理が実行されます。

- `aqua.yaml`に定義されたCLIのインストール
- uv管理のPython 3.13とPyYAML 6.0.3のインストール
- Windowsでは`winget.json`に定義されたAWS CLI、aws-vault、WinMerge、CPU-Zのインストール
- `prek`のGit hook設定
- `link-targets/agents`、`link-targets/agents/skills`、`link-targets/claude/agents`、`link-targets/claude/mods`を`~/.agents`、`~/.claude/skills`、`~/.claude/agents`、`~/.claude/mods`へ共有リンクとして公開（Windowsではジャンクション）
- Codexの各ホームに共通hookの登録設定を配置（WindowsではWSL専用ホームを除外）

既存環境から移行する場合は、[`link-targets/README.md`](link-targets/README.md)の手順でruntime link / junctionを張り直してから`chezmoi apply`を実行してください。管理スクリプトはtarget mismatchを自動修復しません。

Linux/macOS/WSLでは、`aqua.yaml`に定義したCodex CLI（`openai/codex`）を初回の`chezmoi apply`より前にAquaで導入し、`codex`コマンドをPATHから使える状態にします。
Aqua管理のCodex CLIを更新するときは、`aqua update codex`で`aqua.yaml`を更新し、差分を確認してコミットした後に`aqua install`を実行します。
このCLIには`codex update`を使用しません。

通常の`codex`は`CODEX_HOME`未設定の`~/.codex`を仕事用アカウントとして使います。個人用は`pcodex`、WSL用CLIは`wcodex`を使い、それぞれ`~/.codex-personal`、`~/.codex-wsl`へ`CODEX_HOME`を切り替えます。`wcodex`は全環境へ定義されますが、`~/.codex-wsl`がない場合の実行時エラーは許容し、別ホームへフォールバックしません。
通常のCodex設定は`modify_`方式で既存の実行時状態を保持し、共有defaultsを上書きします。仕事用の端末固有値は`chezmoi/.chezmoitemplates/codex-defaults.toml.local`、個人用のホスト固有値は`chezmoi/.chezmoitemplates/codex-personal-defaults.toml.local`へ置きます。

### Windows版VS CodeのCodex端末設定

Windows版VS Codeのユーザー設定（`%APPDATA%\Code\User\settings.json`）は、ファイル全体を管理せず、[`chezmoi/AppData/Roaming/Code/User/modify_settings.json`](chezmoi/AppData/Roaming/Code/User/modify_settings.json)で次の3項目だけを管理します。

- `terminal.integrated.profiles.windows["Codex Personal"].path`（`pwsh.exe`。既存の`source`指定は削除）
- `terminal.integrated.profiles.windows["Codex Personal"].env.CODEX_HOME`
- `terminal.integrated.defaultProfile.windows`

`modify_`テンプレートは適用時点のファイルを入力として受け取り、他のトップレベル設定、他のターミナルプロファイル、`Codex Personal`内の追加オプション・環境変数を保持します。`settings.json`はJSONCとして解析するため、コメントや末尾カンマを含む現行ファイルも読み込めます。管理値が既に一致している場合は入力をそのまま返すので、VS Codeや拡張機能が後から加えた無関係な変更と共存しやすくなります。管理値の修正が必要な場合は、JSONとして再出力するため、その適用回だけコメント・空白・改行が正規化される可能性があります。`chezmoi diff`で確認してから適用してください。

共通の既定値は[`chezmoi/.chezmoidata.json`](chezmoi/.chezmoidata.json)の`vscodeDefaultTerminalProfile`（`Codex Personal`）です。仕事用端末で通常のPowerShellを既定にする場合は、その端末のchezmoi設定（通常は`%USERPROFILE%\.config\chezmoi\chezmoi.toml`）に次を追加します。設定ファイルはリポジトリへ保存しないため、端末ごとの値を分離できます。

```toml
[data]
vscodeDefaultTerminalProfile = "PowerShell"
```

どちらの端末でも`Codex Personal`プロファイル自体は維持されます。Windowsで対象だけを適用するには、PowerShellから次を実行します。

```powershell
chezmoi --source "$env:USERPROFILE\.dotfiles" diff "$env:APPDATA\Code\User\settings.json"
chezmoi --source "$env:USERPROFILE\.dotfiles" apply "$env:APPDATA\Code\User\settings.json"
```

VS Codeをまだ起動しておらず`Code\User`ディレクトリ自体がない場合は、先にVS Codeを一度起動してください。管理対象のコンテナーが配列や文字列へ壊れている場合、テンプレートは他の設定を消さずにエラーで停止するため、該当箇所を手動で正しいオブジェクトへ戻してから再適用します。

この方法では、設定全体をテンプレートへコピーしてVS Codeの更新を巻き戻す運用や、`settings.json`をシンボリックリンクへ置き換える運用を採りません。PowerShellの`ConvertFrom-Json`/`ConvertTo-Json`だけで実装する案は、PowerShellのバージョン差、JSONC非対応、深さ制限、ファイル全体の再整形が残るため採用していません。Pythonの標準`json`もJSONCを扱えず、JSONC用パッケージを追加するとWindows端末ごとのランタイム・依存関係の管理が必要になります。chezmoi組み込みの`fromJsonc`と`toPrettyJson`を使うことで追加ランタイムなしにJSONCを扱い、無変更時は元テキストを保持します。管理値が頻繁に書き換えられる運用でコメントや書式を絶対に保持する必要がある場合は、別途JSONC対応の構文編集ツールを導入し、適用前後の差分を必ず確認してください。

WSL版Codex Remote Controlは任意機能です。`chezmoi apply`は共通hook登録用の`~/.codex-wsl/hooks.json`を配置しますが、standalone版、ログイン、Windowsの自動起動登録は行いません。
standalone版の導入、専用`CODEX_HOME`の作成、ログイン、Windowsの自動起動登録は、[`codex-wsl/SETUP.md`](codex-wsl/SETUP.md)を上から順番に実行します。
`.codex-wsl`の詳細は、同文書から[`codex-wsl/CODEX_HOME.md`](codex-wsl/CODEX_HOME.md)へ進みます。

Windows側の`CODEX_HOME`と同じ物理ディレクトリを参照することは可能ですが、OS固有の設定を分けてWSL側の`~/.codex-wsl/AGENTS.md`を使うため、現在は別ホームを採用しています。

Python 3.13とPyYAML 6.0.3は、`run_onchange_after_tools`スクリプトの初回実行時に導入します。スクリプトの内容が変わった場合や前回の実行に失敗した場合を除き、通常の`chezmoi apply`では不足分の再導入を行いません。

これらのパスに通常のディレクトリや別のリンクがすでにある場合、スクリプトは上書きせず停止します。既存の内容とリンク先を確認し、必要なら手動で退避してから再実行してください。

### Windows SSH の既定シェルと psmux

サーバーの選択、端末限定のZIP版検証結果、ログと復旧の参照は[Windows OpenSSHの運用記録](docs/windows-openssh.md)を確認してください。

Git Bash を既定シェルにする場合の任意設定です。
PowerShell のプロファイルは追加せず、既存の Bash 起動ファイルを使います。
設定後の SSH リモートコマンドは Bash の構文で解釈されるため、PowerShell/cmd 構文に依存するクライアント設定も確認してください。
OpenSSH 9.5 系には Git Bash とコマンドなしの `ssh -T host` で[不具合の報告](https://github.com/PowerShell/Win32-OpenSSH/issues/2354)があります。
この経路を使うクライアントがある場合は、切り替え前後の検証を必須とし、失敗したら既定シェルを元へ戻してください。
自動アタッチの条件では、この OpenSSH 側の問題を解消できません。

まず、新しいローカル PowerShell で `psmux -V` を確認します。
このリポジトリのローカル registry を初めて使う端末では、`aqua-policy.yaml` の内容を確認してから信頼登録します。
`chezmoi apply`では、`run_before_00-aqua-policy`が設定ファイルの変更前にポリシーのSHA-256を検証し、スクリプトに固定した確認済みの値と一致するときだけ信頼登録します。
ハッシュが異なる場合や検証、承認に失敗した場合は停止します。
以下の手動登録は、chezmoi導入前など、`aqua install`を直接実行するときに使います。

```powershell
aqua policy allow "$HOME\.dotfiles\aqua-policy.yaml"
aqua install --config "$HOME\.dotfiles\aqua.yaml"
psmux -V
```

ポリシー変更時は、許可範囲とローカル registry の配布元をレビューしてから、PowerShell版とPOSIX版の`run_before_00-aqua-policy`にある固定ハッシュを更新します。
コメントや改行だけの変更もハッシュ不一致になります。
`python -B tests/aqua-policy.py -v`で、実際のchezmoiテンプレートから生成したスクリプトの正常系と異常系を検証できます。
テストにはAqua、導入済みのchezmoi、PowerShell 7、POSIXシェル（WindowsではGit Bash）を使います。
テスト用のaquaを隔離した環境で実行し、通常の承認状態は変更しません。
実際の`.chezmoiscripts`をOS別にレンダリングし、副作用を記録用の処理に置き換えた実行順序も検証します。
追加の`run_before`を含め、ハッシュ不一致や承認失敗時にほかのスクリプトと設定ファイルの変更へ進まないこと、正常時には後続の処理も実行されることを確認します。
ガードの`00-`は先頭用に予約しているため、ほかの`run_before`には後続の名前を付けてください。

`git-bash.exe` は端末を開くランチャーなので、SSH の既定シェルには `bin\bash.exe` を指定します。
Git が別の場所にある場合は、実在する `bin\bash.exe` のパスを端末上で確認してください。
既存の `.psmux.conf` の `default-shell` もその実体を指すことを確認します。
共有設定と異なる設置先の対応は、端末の設定を確認してから行います。

次に、変更対象の chezmoi 差分だけを確認・適用します。
既存ファイルの独自設定が表示されたら、その内容を保全してから進めてください。

```powershell
chezmoi diff "$HOME\.bashrc" "$HOME\.bashrc.interactive" "$HOME\.bashrc.ssh" "$HOME\.psmux.conf" "$HOME\.bash_profile"
chezmoi apply --exclude=scripts "$HOME\.bashrc" "$HOME\.bashrc.interactive" "$HOME\.bashrc.ssh" "$HOME\.psmux.conf" "$HOME\.bash_profile"
chezmoi verify --exclude=scripts "$HOME\.bashrc" "$HOME\.bashrc.interactive" "$HOME\.bashrc.ssh" "$HOME\.psmux.conf" "$HOME\.bash_profile"
```

以下は管理者 PowerShell で実行します。
先にローカル操作または RDP で復旧できる状態と、現在の SSH 接続を残してください。
変更する二つのレジストリ値だけを、未設定であることも含めてローカルへ保存します。
バックアップは Git に追加しません。
設定・復旧処理は [`scripts/windows-ssh-shell.ps1`](scripts/windows-ssh-shell.ps1) にまとめています。
管理者権限のない PowerShell でも、`-WhatIf` で Git Bash の検出と変更予定を確認できます。

```powershell
powershell.exe -NoProfile -File "$HOME\.dotfiles\scripts\windows-ssh-shell.ps1" -Action Enable -WhatIf
```

確認後、管理者 PowerShell で適用します。

```powershell
powershell.exe -NoProfile -File "$HOME\.dotfiles\scripts\windows-ssh-shell.ps1" -Action Enable
```

Git の配置先を自動検出できない場合は、`-GitBashPath` に `bin\bash.exe` の実体を指定します。
バックアップの既定の保存先は `~/openssh-default-shell.backup.clixml` です。
別の管理者アカウントで実行する場合は、`-BackupPath` に同じ保存先を明示し、復旧時もそのパスを指定します。
既存バックアップがあると設定を停止するため、再設定時は元のバックアップを保全してから進めてください。
設定途中で失敗した場合は元の値へ戻す処理を試みます。
復元も失敗した場合は、保存したバックアップとエラーを使ってローカルで復旧してください。

`DefaultShellEscapeArguments`、`sshd_config`、`authorized_keys`、ホスト鍵は変更しません。
既存接続を閉じずに別の SSH 接続で、Git Bash と SSH 専用の `ssh` セッションが起動することを確認します。
`printf '%s\n' "$CODEX_HOME"` がホーム配下の `.codex-personal` を指すことを確認します。
デタッチ後に `psmux -L dotfiles-ssh list-sessions` と `printf 'flags=%s level=%s\n' "$-" "$SHLVL"` を確認し、接続を切断して再接続したときに同じ作業へ戻れることを確認します。
続けて、同じクライアントから以下を検証します。

- `ssh host 'printf "command-ok\n"'` が psmux を起動せず終了する。PTY 付きの `ssh -t host 'printf "pty-command-ok\n"'` は互換性の確認用で、この Windows 構成では引数不足になります。後述の引用符付き回避方法も確認する。
- `ssh -T host` で標準入力からコマンドを送る既存の利用方法が動く。
- SFTP の一覧・小さなファイルの送受信、SCP の小さなファイルの送受信が動く。旧方式の `scp -O` を使う場合は、それも検証する。
- 通常のローカル PowerShell/Git Bash と、psmux 内の新しいペインで自動アタッチが起きない。
- psmux の全セッション・新しいウィンドウ・分割ペインで `CODEX_HOME` と `GH_CONFIG_DIR` が個人用になり、psmux 外の通常のローカル Git Bash では元の設定が維持される。
- `chezmoi apply --exclude=scripts` を上記のファイルに再実行しても、`verify` が成功する。

実際の SSH 切断・再接続と SFTP/SCP は、この手順を実施した端末で確認する項目です。
リポジトリのテストは Windows の対話端末でアタッチ条件と除外条件を検証し、実 SSH の互換性を保証するものではありません。

#### PTY 付きリモートコマンドの引用符

Windows OpenSSH 9.5p2 と Git Bash を使う環境では、`ssh -t host 'echo pty-command-ok'` が空行だけを返し、`printf` は引数不足になることを確認しました。
[9.5 系の実装](https://github.com/PowerShell/openssh-portable/blob/v9.5.0.0/contrib/win32/win32compat/w32-doexec.c#L366)では、PTY 付きコマンドをシェルの `-c` の後へ引用符なしで連結します。
`bash.exe -c echo pty-command-ok` になると Bash が実行する文字列は `echo` だけで、後続の単語はそのコマンドの引数になりません。
この構成では、Linux / Android の Bash から次のようにコマンド全体を二重引用符で囲んで送ると、期待した文字列を返して終了することを実機確認しました。

```bash
ssh -t host '"echo pty-command-ok"'
```

これは当該 Windows 構成向けの回避方法です。PTY なしのコマンドや Linux サーバーへ一律に追加しません。
複雑な引用符を含むコマンドは個別に確認してください。`DefaultShellEscapeArguments` や `sshd_config` の変更は行いません。
画面消去で出力が読み取れない場合は、診断時だけ `2>&1 | cat -v` を付け、端末制御文字を文字として表示します。
`Connection ... closed` はコマンド終了時にも表示されるため、それだけでは接続失敗と判断しません。
この制約は自動アタッチの Bash フックで修正できず、コマンドなしの `ssh -T host` の既知の問題とも分けて扱います。

#### SSH 専用の GitHub CLI 認証

SSH の Network ログオンでは Windows Credential Manager の保存トークンを取得できない場合があります。
この構成では `gh auth status` が `HTTP 401: Bad credentials` と `tokenSource: default` を返し、保存トークンの読み取り `CredReadW` がエラー 1312（ログオンセッションなし）になることを確認しました。
これはトークン失効を示す証拠ではありません。[Windows の仕様](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credreadw)では Network ログオンに資格情報セットが関連付けられないため、SSH 専用の保存先を使います。
SSH と Windows psmux の全セッションで、`.bashrc.local` の後に `GH_CONFIG_DIR="$HOME/.config/gh-ssh"` を設定します。
psmux 外の通常の Git Bash の設定・認証ファイルは変更しません。ローカル psmux の `main` も SSH 用の保存先を使います。
psmux のセッション名や名前空間にかかわらず、新しいウィンドウ・ペイン、非対話の子コマンドでも同じ設定を読み込みます。
既存ペインには `source ~/.bashrc` で反映し、`CODEX_HOME` と `GH_CONFIG_DIR` を確認してください。起動済みの Codex はそのペインから起動し直します。

```bash
printf 'GH_CONFIG_DIR=%s\n' "$GH_CONFIG_DIR"
printf 'CODEX_HOME=%s\n' "$CODEX_HOME"
```

保存先が `$HOME/.config/gh-ssh`、Codex のホームが `$HOME/.codex-personal` であることを確認します。
`GH_TOKEN` / `GITHUB_TOKEN` が設定されていると保存ファイルより優先されるため、認証に使うペインではそれらを設定しません。値を表示しないでください。
ログイン前に SSH 専用ディレクトリを作成し、Windows のプロパティ → セキュリティ → 詳細設定で継承を無効にし、現在のユーザー・SYSTEM・Administrators だけにアクセスを許可します。
通常の GitHub CLI ディレクトリの権限は変更しません。PowerShell の `icacls "$env:USERPROFILE\.config\gh-ssh"` で権限を確認できます。

```bash
gh auth login --web --insecure-storage
gh auth status
gh api user --jq '.login'
```

ブラウザ認証とコード入力は本人が行い、認証コードやトークンを作業ログ・Issue・PRへ貼り付けません。
`--insecure-storage` はトークンを暗号化せず `gh-ssh` 配下へ保存します。ACL を制限しても同じユーザーや管理者から読めるため、このディレクトリを Git 管理・共有・平文バックアップの対象に含めないでください。
ユーザー名が `the9ball` であることを確認し、新しい SSH ペインとそこから起動した Codex でも同じコマンドを確認します。
認証を更新するときは、同じ SSH 専用保存先と ACL を再確認してから `gh auth login --web --insecure-storage` を再実行します。
失敗した場合は保存先・トークン環境変数の有無・ACL を確認し、デスクトップ側の認証を logout / refresh しません。

#### 自動アタッチの回避と復旧

既定シェルが Git Bash のこの Windows 構成で、Linux / Android の Bash から一度だけ起動ファイルを読まずに接続するには `ssh -t host '"bash --noprofile --norc -i"'` を使います。
コマンド全体の二重引用符を省くとオプションが失われるため、復旧用の例でも引用符を維持してください。
Termius の起動コマンド欄で同じ回避を使う方法は未検証です。送信される引用符と起動ファイルを読まないことを個別に確認してください。
通常の `ssh host command` は自動アタッチの対象外です。

自動アタッチを継続的に止める場合は、ローカル PowerShell または復旧用接続でホームに `.psmux-no-autoattach` を作成します。
SFTP で同名の空ファイルをホームへ置くこともできます。

```powershell
New-Item -ItemType File -Path "$HOME\.psmux-no-autoattach" -Force
```

再び有効にするときだけ、回避ファイルを削除します。

```powershell
Remove-Item -LiteralPath "$HOME\.psmux-no-autoattach"
```

既に Git Bash を使える環境では、`PSMUX_SSH_AUTOATTACH=0 bash` も自動アタッチを回避します。
クライアントの環境変数送信はサーバーが受け付けるとは限らないため、SSH 接続前の回避にそれだけを使いません。
`psmux` が見つからなければ `where.exe psmux` / `Get-Command psmux` で aqua の `bin` とユーザー PATH を確認し、新しい接続で試します。
SSH 用の状態は `psmux -L dotfiles-ssh list-sessions`、既存のローカル `main` は `psmux list-sessions` で確認します。
残したいセッションに対して `kill-session` は使いません。

#### CODEX_HOME の環境変数送信を整理する

`CODEX_HOME` は SSH 用の Bash 設定で指定するため、Termius の Environment Variables と OpenSSH の `AcceptEnv CODEX_HOME` は不要です。
削除するとクライアントから `CODEX_HOME` を選択する用途は使えなくなりますが、この方式の公開鍵認証・SSH 接続・SFTP には必要ありません。
`sshd_config` は chezmoi で管理せず、自動編集や sshd の再起動もしません。

以下のSystem32版実体、標準設定パス、`Restart-Service sshd`を使う例は、Windows標準の`sshd`サービス専用です。
ZIP版を使う端末では、対象サービスの`Win32_Service.PathName`から実体と起動引数を確認し、`-f`指定の有無も含めて実際に使う設定ファイルを特定してください。
構文確認はその実体と設定の組み合わせで行い、再起動は非SSHの復旧経路と実行承認を確保してから対象サービスだけに限定します。
標準版のコマンドをZIP版へ無条件に流用しません。

手動追加した設定を削除する場合は、復旧用のローカル操作またはRDPと現在のSSH接続を確保し、実際の対象設定を別ファイルへバックアップしてから編集します。
標準版の設定は`C:\ProgramData\ssh\sshd_config`です。
この設定専用の二つのコメントと `AcceptEnv CODEX_HOME` だけを削除し、他の環境変数も指定した行なら `CODEX_HOME` だけを取り除いてください。
`Match` ブロックの所属や他の認証・接続設定は変更しません。

```powershell
& "$env:WINDIR\System32\OpenSSH\sshd.exe" -t -f "$env:ProgramData\ssh\sshd_config"
```

構文確認が成功し、ほかに `CODEX_HOME` をクライアントから指定する用途がないことを確認してから、管理者が手動で `Restart-Service sshd` を実行します。
別接続で公開鍵認証・SSH 用の `CODEX_HOME`・非対話コマンドを確認し、SFTP/SCPを使う場合は個別に試験します。
Issue #144ではSFTP/SCPは未検証・採用判断の必須条件外です。SSH接続の成功からファイル転送の成功を推定しません。
失敗した場合はバックアップを復元します。

シェルの互換性問題や SSH 起動失敗があれば、ローカルの管理者 PowerShell でバックアップを復元します。
値が元から未設定だった場合は、新しく追加した値を削除します。

```powershell
powershell.exe -NoProfile -File "$HOME\.dotfiles\scripts\windows-ssh-shell.ps1" -Action Restore
```

この`-Action Restore`は既定シェルの`DefaultShell`と`DefaultShellCommandOption`の二値を戻す処理です。
サービス定義・開始方式・sshd_config・サーバー全体は復旧しません。サーバーの切り戻しは[運用記録の復旧参照](docs/windows-openssh.md#復旧と保守の参照)を使います。
別の SSH 接続で復旧を確認してから、元の接続を閉じてください。
`ForceCommand` やパスワード認証の変更で回避しません。

## 5. 適用後の確認

シェルを再起動するか設定を読み込み直し、Gitや必要なCLIが使えることを確認します。設定を更新したときは、次の順に実行します。

```sh
cd "$HOME/.dotfiles"
git pull --rebase
chezmoi diff
chezmoi apply
chezmoi verify --exclude=scripts
```

セットアップの詳細な挙動を確認したい場合は、[`codex-wsl/SETUP.md`](codex-wsl/SETUP.md)と`chezmoi/.chezmoiscripts/`を参照してください。

## Agent Skillsの導入

第三者スキルの実体はGitで追跡せず、ロックファイルと復元手順を追跡します。

### Codex pluginの導入

公式の`dotnet/skills`は、plugin本体を`.dotfiles`へvendorせず、Codex marketplaceから取得します。取得元、commit、対象pluginのversionとハッシュは[`link-targets/agents/.plugin-lock.json`](link-targets/agents/.plugin-lock.json)に記録します。

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

marketplaceの登録とpluginの有効・無効は、[`chezmoi/dot_claude/modify_settings.json`](chezmoi/dot_claude/modify_settings.json)を正とします。このテンプレートは`~/.claude/settings.json`のうち`extraKnownMarketplaces`と`enabledPlugins`など管理対象のキーだけを上書きし、`permissions`や`hooks`など他のキーは現在の内容をそのまま書き戻します。Claude Code自身が同じファイルへ書き込むため、ファイル全体を管理すると、その書き込みを巻き戻してしまうためです。

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

`gh-stack`は`link-targets/agents/.skill-lock.json`に出所を記録し、次のコマンドで復元します。

```sh
gh skill install github/gh-stack gh-stack
```

Datadogの`dd-pup`、`dd-logs`、`dd-docs`は、リポジトリのルートで次を実行して導入します。

```sh
npx skills add datadog-labs/agent-skills --skill dd-pup --skill dd-logs --skill dd-docs --full-depth -y
```

このコマンドは、`link-targets/agents/skills`に3つのスキルを配置し、ルートの`skills-lock.json`を更新します。

`link-targets/agents/skills/dd-readonly-delegate`は、このリポジトリで管理する共有スキルです。第三者スキルの導入コマンドでは復元しません。

このスキルはDatadogのメトリクス、ログ、ダッシュボード、ドキュメントの参照に使用します。単発の読み取り調査はサブエージェントへ委譲し、継続的な調査ではメインスレッドが関連スキルとMCPの文脈を保持します。

### Claude Code modの導入

`link-targets/claude/mods/context`は、Claude Codeの下部ステータス行にコンテキスト使用率と利用上限（5時間枠・週間枠）の使用率・リセットまでの時間を表示するmodです。marketplaceを経由せず、このリポジトリを正本としてディスクから直接読み込みます。

`chezmoi apply`は`link-targets/claude/mods`を`~/.claude/mods`へ共有リンクとして公開し（Windowsではジャンクション）、[`chezmoi/dot_claude/modify_settings.json`](chezmoi/dot_claude/modify_settings.json)が`~/.claude/settings.json`の`env.CLAUDE_CODE_PLUGIN_DIRS`に`~/.claude/mods/context`の絶対パスを設定します。`env`の他のキーはそのまま書き戻しますが、`CLAUDE_CODE_PLUGIN_DIRS`自体はテンプレートの管理値なので、手動で追加したフォルダは次の適用で消えます。読み込むmodを増やす場合はテンプレートを書き換えてください。

適用後は新しいClaude Codeセッションを開始してください。ターミナルの対話セッションはフォルダを監視するため、以後の編集は保存時に再読み込みされます。デスクトップアプリやSDKのように長時間動くセッションは、`CLAUDE_CODE_PLUGIN_DIR_WATCH=1`を同じく`env`に設定した場合だけフォルダを監視します。このリポジトリでは設定していないため、編集は新しいセッションを開始すると反映されます。

変更後は、リポジトリのルートで次を実行して検証します。

`````sh
claude plugin validate link-targets/claude/mods/context
claude plugin test link-targets/claude/mods/context
`````

## Datadog MCPの設定

MCPエンドポイントは次のとおりです。

```text
https://mcp.datadoghq.com/v1/mcp
```

Codexは`~/.codex/config.toml`で`bearer_token_env_var = "DD_ACCESS_TOKEN"`を設定し、環境変数からSATを参照します。Claudeは`~/.claude.json`で`Authorization`ヘッダを設定します。SATの実値は、どちらの設定にもリポジトリにも保存しません。

現在のCodex設定では、`link-targets/agents/skills`の共有スキルを認識します。Windowsでは`~/.claude/skills`も同じ実体を参照します。
