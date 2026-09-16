<#
.SYNOPSIS
Runs focused regression checks for the Unity build-log extractor.

.DESCRIPTION
Verifies nested Player Build pairing, rejection of a generic completion without
an explicit Player Build context, and the presence of the content snapshot
identity in successful output.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\scripts\extract-unity-build-log.ps1'
$nestedFixturePath = Join-Path $PSScriptRoot 'fixtures\nested-player-build.log'
$genericFixturePath = Join-Path $PSScriptRoot 'fixtures\generic-build-success.log'

$nestedOutput = & pwsh -NoProfile -File $scriptPath -LogFilePath $nestedFixturePath 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "Nested Player Build fixture failed: $nestedOutput"
}
if ($nestedOutput -notmatch 'Player Build' -or $nestedOutput -notmatch '1' -or $nestedOutput -notmatch '4') {
    throw "Nested Player Build did not preserve the outer completed interval: $nestedOutput"
}
if ($nestedOutput -notmatch '[0-9a-f]{64}') {
    throw "Snapshot content identity was not emitted: $nestedOutput"
}

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$genericOutput = & pwsh -NoProfile -File $scriptPath -LogFilePath $genericFixturePath 2>&1 | Out-String
$ErrorActionPreference = $previousErrorActionPreference
if ($LASTEXITCODE -eq 0) {
    throw "Generic Build success was incorrectly treated as a terminal event: $genericOutput"
}

Write-Output 'Unity build-log extractor regression checks passed.'
