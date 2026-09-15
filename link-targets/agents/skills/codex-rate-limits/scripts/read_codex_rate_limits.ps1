$ErrorActionPreference = 'Stop'

function Stop-Safely([string]$Stage) { throw "処理を停止しました: $Stage" }

function Test-CodexExecutionContext {
    if ($env:CLAUDECODE -or $env:CLAUDE_CODE) { Stop-Safely 'Claude Code の実行環境では使用できません' }
    if ($env:CODEX_INTERNAL_ORIGINATOR_OVERRIDE -ne 'Codex Desktop') { Stop-Safely 'Codex Desktop の実行環境を確認できません' }
    $threadIdentifier = [Guid]::Empty
    if (-not [Guid]::TryParse($env:CODEX_THREAD_ID, [ref]$threadIdentifier)) { Stop-Safely 'Codex のスレッド識別子を確認できません' }
}

function Get-CodexExecutableCandidate {
    $candidatePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($process in @(Get-Process -Name codex -ErrorAction SilentlyContinue)) { if ($process.Path) { $candidatePaths.Add($process.Path) } }
    foreach ($command in @(Get-Command codex.exe -All -ErrorAction SilentlyContinue)) { if ($command.Source) { $candidatePaths.Add($command.Source) } }
    $cachedCodexDirectory = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    if (Test-Path -LiteralPath $cachedCodexDirectory -PathType Container) {
        foreach ($cachedDirectory in @(Get-ChildItem -LiteralPath $cachedCodexDirectory -Directory -ErrorAction SilentlyContinue)) {
            $cachedExecutable = Join-Path $cachedDirectory.FullName 'codex.exe'
            if (Test-Path -LiteralPath $cachedExecutable -PathType Leaf) { $candidatePaths.Add($cachedExecutable) }
        }
    }
    $validCandidates = @($candidatePaths | Sort-Object -Unique | ForEach-Object {
        try {
            $resolvedPath = [System.IO.Path]::GetFullPath($_)
            $normalizedPath = $resolvedPath.Replace('/', '\')
            $isWindowsAppsBundle = $normalizedPath -match '\\WindowsApps\\OpenAI\.Codex_[^\\]+\\app\\resources\\codex\.exe$'
            $isUserCachedBundle = $normalizedPath -match '\\AppData\\Local\\OpenAI\\Codex\\bin\\[A-Fa-f0-9]+\\codex\.exe$'
            if (-not ($isWindowsAppsBundle -or $isUserCachedBundle)) { return }
            if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) { return }
            $resourcesDirectory = Split-Path -Parent $resolvedPath
            if ($isWindowsAppsBundle -and -not (Test-Path -LiteralPath (Join-Path $resourcesDirectory 'app.asar') -PathType Leaf)) { return }
            $signature = Get-AuthenticodeSignature -FilePath $resolvedPath
            if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate.Subject.Contains('OpenAI')) { return }
            $resolvedPath
        } catch { return }
    }) | Sort-Object -Unique
    if ($validCandidates.Count -eq 0) { Stop-Safely '署名付きの Codex Desktop 同梱実行ファイルが見つかりません' }
    $cachedCandidates = @($validCandidates | Where-Object { $_ -match '\\AppData\\Local\\OpenAI\\Codex\\bin\\[A-Fa-f0-9]+\\codex\.exe$' })
    if ($cachedCandidates.Count -eq 1) { return $cachedCandidates[0] }
    $windowsAppsCandidates = @($validCandidates | Where-Object { $_ -match '\\WindowsApps\\OpenAI\.Codex_[^\\]+\\app\\resources\\codex\.exe$' })
    if ($windowsAppsCandidates.Count -eq 1) { return $windowsAppsCandidates[0] }
    Stop-Safely "Codex Desktop 同梱実行ファイルの候補が曖昧です（$($validCandidates.Count) 件）"
}

function Convert-UnixSecondsToJapanTime($Value, [string]$MissingText = '未提供') {
    if ($null -eq $Value) { return $MissingText }
    $unixSeconds = 0L
    if (-not [long]::TryParse([string]$Value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$unixSeconds)) { return '変換不可' }
    try { return [DateTimeOffset]::FromUnixTimeSeconds($unixSeconds).ToOffset([TimeSpan]::FromHours(9)).ToString('yyyy-MM-dd HH:mm:ss zzz') + ' JST' } catch { return '変換不可' }
}

function Get-Property($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Send-RpcMessage($Process, $Message, [System.Collections.Generic.List[string]]$SentMethods) {
    $method = [string](Get-Property $Message 'method')
    if ($method -notin @('initialize', 'initialized', 'account/rateLimits/read')) { Stop-Safely '許可されていないRPCメソッドを拒否しました' }
    $SentMethods.Add($method)
    $Process.StandardInput.WriteLine(($Message | ConvertTo-Json -Compress -Depth 10))
    $Process.StandardInput.Flush()
}

function Read-RpcResponse($Reader, [int]$ExpectedIdentifier, [DateTime]$Deadline) {
    while ([DateTime]::UtcNow -lt $Deadline) {
        $readTask = $Reader.ReadLineAsync()
        $remainingMilliseconds = [Math]::Max(1, [int]($Deadline - [DateTime]::UtcNow).TotalMilliseconds)
        $completedTask = [System.Threading.Tasks.Task]::WhenAny($readTask, [System.Threading.Tasks.Task]::Delay($remainingMilliseconds)).GetAwaiter().GetResult()
        if ($completedTask -ne $readTask) { Stop-Safely 'app-serverの応答がタイムアウトしました' }
        $line = $readTask.GetAwaiter().GetResult()
        if ($null -eq $line) { Stop-Safely 'app-serverが予期せず終了しました' }
        try { $message = $line | ConvertFrom-Json -Depth 20 } catch { Stop-Safely 'app-serverの応答を解釈できません' }
        $messageIdentifier = Get-Property $message 'id'
        if ($null -eq $messageIdentifier) { continue }
        if ([int]$messageIdentifier -ne $ExpectedIdentifier) { Stop-Safely '予期しないRPC応答を受信しました' }
        if ($null -ne (Get-Property $message 'error')) { Stop-Safely 'app-serverが要求を拒否しました' }
        return $message
    }
    Stop-Safely 'app-serverの応答がタイムアウトしました'
}

function Write-LimitLine([string]$Label, $Limit) {
    $primary = Get-Property $Limit 'primary'; $secondary = Get-Property $Limit 'secondary'
    Write-Output "- $Label / primary: $(Convert-UnixSecondsToJapanTime (Get-Property $primary 'resetsAt'))"
    if ($null -eq $secondary) { Write-Output "- $Label / secondary: 未提供" } else { Write-Output "- $Label / secondary: $(Convert-UnixSecondsToJapanTime (Get-Property $secondary 'resetsAt'))" }
}

Test-CodexExecutionContext
$codexExecutable = Get-CodexExecutableCandidate
$codexHome = if ($env:CODEX_HOME) { [System.IO.Path]::GetFullPath($env:CODEX_HOME) } else { Join-Path $env:USERPROFILE '.codex' }
if (-not (Test-Path -LiteralPath $codexHome -PathType Container)) { Stop-Safely 'Codexホームが見つかりません' }

$processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processStartInfo.FileName = $codexExecutable
$processStartInfo.ArgumentList.Add('app-server')
$processStartInfo.UseShellExecute = $false; $processStartInfo.CreateNoWindow = $true
$processStartInfo.RedirectStandardInput = $true; $processStartInfo.RedirectStandardOutput = $true; $processStartInfo.RedirectStandardError = $true
$processStartInfo.Environment['CODEX_HOME'] = $codexHome
$serverProcess = [System.Diagnostics.Process]::new(); $serverProcess.StartInfo = $processStartInfo
$sentMethods = [System.Collections.Generic.List[string]]::new(); $deadline = [DateTime]::UtcNow.AddSeconds(15)

try {
    if (-not $serverProcess.Start()) { Stop-Safely 'app-serverを起動できません' }
    $discardedErrorTask = $serverProcess.StandardError.ReadToEndAsync()
    Send-RpcMessage $serverProcess ([ordered]@{ jsonrpc='2.0'; id=1; method='initialize'; params=[ordered]@{ clientInfo=[ordered]@{ name='codex-rate-limits'; version='1.0.0' }; capabilities=[ordered]@{} } }) $sentMethods
    $initializeResponse = Read-RpcResponse $serverProcess.StandardOutput 1 $deadline
    $reportedCodexHome = Get-Property (Get-Property $initializeResponse 'result') 'codexHome'
    if (-not $reportedCodexHome -or ([System.IO.Path]::GetFullPath($reportedCodexHome) -ne [System.IO.Path]::GetFullPath($codexHome))) { Stop-Safely 'app-serverが使用したCodexホームが一致しません' }
    Send-RpcMessage $serverProcess ([ordered]@{ jsonrpc='2.0'; method='initialized'; params=[ordered]@{} }) $sentMethods
    Send-RpcMessage $serverProcess ([ordered]@{ jsonrpc='2.0'; id=2; method='account/rateLimits/read'; params=[ordered]@{} }) $sentMethods
    $rateLimitResponse = Read-RpcResponse $serverProcess.StandardOutput 2 $deadline
    if (($sentMethods -join ',') -ne 'initialize,initialized,account/rateLimits/read') { Stop-Safely '許可された順序以外のRPCを送信しました' }

    $result = Get-Property $rateLimitResponse 'result'
    $limitsById = Get-Property $result 'rateLimitsByLimitId'
    Write-Output '通常利用枠'
    if ($null -ne $limitsById -and @($limitsById.PSObject.Properties).Count -gt 0) {
        foreach ($limitProperty in @($limitsById.PSObject.Properties | Sort-Object Name)) { Write-LimitLine $limitProperty.Name $limitProperty.Value }
    } else {
        $singleLimit = Get-Property $result 'rateLimits'
        if ($null -eq $singleLimit) { Write-Output '- 未提供' } else { Write-LimitLine '互換形式' $singleLimit }
    }

    Write-Output ''; Write-Output 'リセットクレジット（通常利用枠とは別）'
    $resetCredits = Get-Property $result 'rateLimitResetCredits'
    if ($null -eq $resetCredits) { Write-Output '- 未提供' } else {
        $availableCountProperty = $resetCredits.PSObject.Properties['availableCount']
        if ($null -eq $availableCountProperty) { Write-Output '- availableCount: 未提供' } else { Write-Output "- availableCount: $($availableCountProperty.Value)" }
        $creditsProperty = $resetCredits.PSObject.Properties['credits']
        if ($null -eq $creditsProperty -or $null -eq $creditsProperty.Value) { Write-Output '- 詳細: 未提供' }
        elseif (@($creditsProperty.Value).Count -eq 0) { Write-Output '- 詳細: 0件' }
        else {
            $creditNumber = 0
            foreach ($credit in @($creditsProperty.Value)) {
                $creditNumber++; $expiresAtProperty = $credit.PSObject.Properties['expiresAt']
                $expiresAt = if ($null -eq $expiresAtProperty) { '未提供' } elseif ($null -eq $expiresAtProperty.Value) { '無期限' } else { Convert-UnixSecondsToJapanTime $expiresAtProperty.Value }
                Write-Output "- #$creditNumber expiresAt: $expiresAt"
            }
            if ($availableCountProperty -and [int]$availableCountProperty.Value -gt $creditNumber) { Write-Output "- 詳細: $creditNumber 件のみ取得（利用可能総数は $($availableCountProperty.Value) 件）" }
        }
    }
} catch { Write-Error $_.Exception.Message; exit 1 }
finally {
    if ($serverProcess) {
        try { $serverProcess.StandardInput.Close() } catch {}
        try { if (-not $serverProcess.HasExited) { $serverProcess.Kill() } } catch {}
        $serverProcess.Dispose()
    }
}
