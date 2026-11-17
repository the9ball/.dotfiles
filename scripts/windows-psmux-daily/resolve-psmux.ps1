# Resolve an installed psmux from this checkout without installing or changing PATH.
$ErrorActionPreference = 'Stop'
$aquaConfig = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\aqua.yaml'))
$aquaExecutable = (Get-Command aqua -CommandType Application -ErrorAction Stop).Source
$psmuxExecutable = (& $aquaExecutable -c $aquaConfig which psmux | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not [IO.Path]::IsPathRooted($psmuxExecutable) -or
    -not (Test-Path -LiteralPath $psmuxExecutable -PathType Leaf)) {
    throw 'aqua could not resolve the installed psmux. Check the existing aqua installation.'
}
Write-Output $psmuxExecutable
