<# .SYNOPSIS Sends a hidden interactive secret through stdin to an explicitly selected TPM helper; never prints get payloads. #>
param(
    [Parameter(Mandatory)][string]$DeploymentRoot,
    [Parameter(Mandatory)][ValidateSet('store', 'erase', 'list')][string]$Operation,
    [string]$Registry,
    [string]$Username
)
$ErrorActionPreference = 'Stop'
$secureSecret = $null
try {
    if (-not [IO.Path]::IsPathFullyQualified($DeploymentRoot)) { throw 'Absolute deployment required.' }
    $deployment = [IO.Path]::GetFullPath($DeploymentRoot)
    $settings = Get-Content -LiteralPath (Join-Path $deployment 'settings.json') -Raw | ConvertFrom-Json
    if ($settings.HelperKind -ne 'tpm' -or $settings.Version -ne 1 -or $settings.HelperVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid settings.' }
    if ($Operation -ne 'list' -and -not $Registry) { throw 'Registry required.' }
    if ($Operation -eq 'store' -and -not $Username) { throw 'Username required.' }
    $helper = Join-Path $deployment ('bin/' + $settings.HelperVersion + '/docker-credential-ssh-tpm.exe')
    $start = [Diagnostics.ProcessStartInfo]::new($helper)
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $start.Environment['DOCKER_SSH_HELPER_ROOT'] = Join-Path $deployment 'store'
    $start.ArgumentList.Add($Operation)
    if ($Operation -eq 'store') {
        $secureSecret = Read-Host 'Token/password (not recorded)' -AsSecureString
        $plainSecret = [Net.NetworkCredential]::new('', $secureSecret).Password
        $payload = @{ ServerURL = $Registry; Username = $Username; Secret = $plainSecret } | ConvertTo-Json -Compress
    } else { $payload = $Registry }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($payload)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(60000)) { throw 'Helper timed out; child may remain. Stop and establish quiescence.' }
        $result = $output.GetAwaiter().GetResult()
        [void]$errors.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw 'Helper failed.' }
        if ($Operation -eq 'list') { Write-Output $result } else { Write-Output 'Dedicated credential operation completed.' }
    } finally { $process.Dispose() }
} catch {
    # Fixed diagnostics prevent input or child exception text from reaching a transcript.
    [Console]::Error.WriteLine('Credential operation failed; check the dedicated deployment and input.')
    exit 1
} finally {
    $plainSecret = $null
    $payload = $null
    if ($secureSecret) { $secureSecret.Dispose() }
}
