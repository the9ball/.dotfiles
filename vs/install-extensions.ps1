<#
.SYNOPSIS
    Restores the Visual Studio extensions recorded in the selected profile.

.DESCRIPTION
    The inventory and the classification live in extensions.psd1.  Marketplace
    entries are resolved through the official Visual Studio Marketplace API,
    and the returned VSIX is checked before VSIXInstaller is invoked.

    Only instances in the selected inventory profile returned by vswhere are
    considered.  VSIXInstaller is called without /admin, so the normal path is
    a per-user installation and no elevation is requested.

    The script deliberately does not use an unknown mirror, a guessed VSIX URL,
    or a local binary that is not recorded in the data file.

.PARAMETER DryRun
    Resolve the target VS2026 instances and Marketplace metadata, then show
    what would be installed without downloading or installing a VSIX.

.PARAMETER ManifestPath
    Optional path to an alternative .psd1 inventory.  The default is the
    extensions.psd1 file next to this script.

.PARAMETER Profile
    Name of the Visual Studio profile in the inventory.  Defaults to the
    inventory's DefaultProfile value.

.PARAMETER InstanceId
    Restrict the operation to one exact vswhere instanceId.

.PARAMETER AllInstances
    Allow the selected profile to target every matching instance.  Without this
    switch, multiple matching instances require -InstanceId for safety.

.PARAMETER AllowUnknownInstalledState
    Continue after installed-extension enumeration fails.  This weakens the
    fail-closed idempotency check and should only be used deliberately.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\vs\install-extensions.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\vs\install-extensions.ps1 -DryRun

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\vs\install-extensions.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$DryRun,
    [string]$ManifestPath,
    [string]$Profile,
    [string]$InstanceId,
    [switch]$AllInstances,
    [switch]$AllowUnknownInstalledState
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Results = New-Object 'System.Collections.Generic.List[object]'
$script:DryRunEffective = [bool]$DryRun -or [bool]$WhatIfPreference
$script:ProfileName = ''
$script:TargetVersionRange = ''
$script:IncludePrerelease = $false

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnMessage {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Add-Result {
    param(
        [ValidateSet('Planned', 'Succeeded', 'Skipped', 'Failed')]
        [string]$Status,
        [string]$Name,
        [string]$Instance,
        [string]$Reason
    )

    $script:Results.Add([PSCustomObject]@{
            Status   = $Status
            Name     = $Name
            Instance = $Instance
            Reason   = $Reason
        })
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
        return $Object[$Name]
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Get-VsWherePath {
    $candidates = @()

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $candidates += Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
    }

    $programFiles = [Environment]::GetEnvironmentVariable('ProgramFiles')
    if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
        $candidates += Join-Path $programFiles 'Microsoft Visual Studio\Installer\vswhere.exe'
    }

    try {
        $command = Get-Command 'vswhere.exe' -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $candidates += $command.Source
        }
    }
    catch {
        # A PATH lookup is only a fallback; a missing command is handled below.
    }

    foreach ($candidate in @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Get-Item -LiteralPath $candidate).FullName
        }
    }

    return $null
}

function Get-VisualStudioInstances {
    param(
        [string]$TargetVersionRange,
        [bool]$IncludePrerelease
    )

    $vswherePath = Get-VsWherePath
    if ([string]::IsNullOrWhiteSpace($vswherePath)) {
        throw 'vswhere.exe was not found. Install the selected Visual Studio profile or make the official vswhere.exe available on PATH.'
    }

    Write-Info "Using vswhere.exe: $vswherePath"
    $vswhereArguments = @(
        '-all'
        '-products'
        '*'
        '-version'
        $TargetVersionRange
        '-format'
        'json'
        '-utf8'
    )
    if ($IncludePrerelease) {
        $vswhereArguments = @('-all', '-prerelease') + $vswhereArguments[1..($vswhereArguments.Count - 1)]
    }
    $jsonLines = @(
        & $vswherePath @vswhereArguments 2>$null
    )
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -or $jsonLines.Count -eq 0) {
        return @()
    }

    $json = $jsonLines -join [Environment]::NewLine
    try {
        # Use -InputObject instead of piping: Windows PowerShell 5.1 wraps a
        # JSON array as one nested array when it is sent through the pipeline.
        $parsedJson = ConvertFrom-Json -InputObject $json
        $records = @($parsedJson)
    }
    catch {
        throw "vswhere returned invalid JSON: $($_.Exception.Message)"
    }

    $instances = @()
    foreach ($record in $records) {
        $installationPath = [string](Get-PropertyValue -Object $record -Name 'installationPath' -Default '')
        $installationVersionText = [string](Get-PropertyValue -Object $record -Name 'installationVersion' -Default '')
        if ([string]::IsNullOrWhiteSpace($installationPath) -or [string]::IsNullOrWhiteSpace($installationVersionText)) {
            continue
        }

        try {
            $installationVersion = [version]$installationVersionText
        }
        catch {
            continue
        }

        # Keep this check even though vswhere was passed -version.  It prevents
        # a future query change from selecting an instance outside the profile.
        if (-not (Test-VersionRangeIncludes -Range $TargetVersionRange -Version $installationVersion)) {
            continue
        }

        if (-not [bool](Get-PropertyValue -Object $record -Name 'isComplete' -Default $false)) {
            continue
        }

        $isLaunchable = [bool](Get-PropertyValue -Object $record -Name 'isLaunchable' -Default $true)
        if (-not $isLaunchable) {
            continue
        }

        # Build Tools is also discoverable by vswhere, but it is not the IDE
        # targeted by this inventory.  Restrict the editions explicitly.
        $productId = [string](Get-PropertyValue -Object $record -Name 'productId' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($productId) -and $productId -notmatch '^Microsoft\.VisualStudio\.Product\.(Community|Professional|Enterprise)$') {
            continue
        }

        $vsixInstaller = Join-Path $installationPath 'Common7\IDE\VSIXInstaller.exe'
        if (-not (Test-Path -LiteralPath $vsixInstaller -PathType Leaf)) {
            Write-WarnMessage "Skipping $installationPath because VSIXInstaller.exe was not found."
            continue
        }

        $instances += [PSCustomObject]@{
            InstanceId         = [string](Get-PropertyValue -Object $record -Name 'instanceId' -Default '')
            DisplayName        = [string](Get-PropertyValue -Object $record -Name 'displayName' -Default 'Visual Studio 2026')
            InstallationPath   = $installationPath
            InstallationVersion = $installationVersionText
            ProductId          = $productId
            ProductPath        = [string](Get-PropertyValue -Object $record -Name 'productPath' -Default (Join-Path $installationPath 'Common7\IDE\devenv.exe'))
            IsPrerelease        = [bool](Get-PropertyValue -Object $record -Name 'isPrerelease' -Default $false)
            VsixInstaller      = $vsixInstaller
        }
    }

    return @($instances | Sort-Object -Property InstallationPath -Unique)
}

function Get-InstalledVsixManifests {
    param([object[]]$Instances)

    $roots = @()
    foreach ($instance in @($Instances)) {
        $machineRoot = Join-Path $instance.InstallationPath 'Common7\IDE\Extensions'
        if (Test-Path -LiteralPath $machineRoot -PathType Container) {
            $roots += [PSCustomObject]@{
                Root       = $machineRoot
                InstanceId = [string]$instance.InstanceId
                Scope      = 'Machine'
            }
        }
    }

    $localAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        $userVisualStudioRoot = Join-Path $localAppData 'Microsoft\VisualStudio'
        if (Test-Path -LiteralPath $userVisualStudioRoot -PathType Container) {
            $userConfigurations = @(Get-ChildItem -LiteralPath $userVisualStudioRoot -Directory -Force -ErrorAction Stop)
            foreach ($configuration in $userConfigurations) {
                $configurationInstanceId = $null
                if ($configuration.Name -match '^[0-9]+\.[0-9]+_(?<instanceId>.+)$') {
                    $configurationInstanceId = $Matches['instanceId']
                }
                if ([string]::IsNullOrWhiteSpace($configurationInstanceId)) {
                    continue
                }

                $matchingInstances = @($Instances | Where-Object { $_.InstanceId -ieq $configurationInstanceId })
                if ($matchingInstances.Count -eq 0) {
                    continue
                }

                $userRoot = Join-Path $configuration.FullName 'Extensions'
                if (Test-Path -LiteralPath $userRoot -PathType Container) {
                    foreach ($matchingInstance in $matchingInstances) {
                        $roots += [PSCustomObject]@{
                            Root       = $userRoot
                            InstanceId = [string]$matchingInstance.InstanceId
                            Scope      = 'User'
                        }
                    }
                }
            }
        }
    }

    $manifests = @()
    foreach ($root in @($roots | Sort-Object -Property InstanceId, Scope, Root -Unique)) {
        $files = @(Get-ChildItem -LiteralPath $root.Root -Recurse -Filter 'extension.vsixmanifest' -File -Force -ErrorAction Stop)
        foreach ($file in $files) {
            try {
                [xml]$xml = Get-Content -LiteralPath $file.FullName -Raw
                $identity = $xml.PackageManifest.Metadata.Identity
                $identityId = [string](Get-PropertyValue -Object $identity -Name 'Id' -Default '')
                if ([string]::IsNullOrWhiteSpace($identityId)) {
                    continue
                }

                $targets = @()
                foreach ($target in @($xml.PackageManifest.Installation.InstallationTarget)) {
                    $targetId = [string](Get-PropertyValue -Object $target -Name 'Id' -Default '')
                    $targetVersion = [string](Get-PropertyValue -Object $target -Name 'Version' -Default '')
                    if (-not [string]::IsNullOrWhiteSpace($targetId)) {
                        $targets += "$targetId`:$targetVersion"
                    }
                }

                $manifests += [PSCustomObject]@{
                    Id                  = $identityId
                    Version             = [string](Get-PropertyValue -Object $identity -Name 'Version' -Default '')
                    DisplayName         = [string](Get-PropertyValue -Object $xml.PackageManifest.Metadata -Name 'DisplayName' -Default '')
                    Path                = $file.FullName
                    InstanceId          = [string]$root.InstanceId
                    Scope               = [string]$root.Scope
                    InstallationTargets = $targets
                }
            }
            catch {
                # One malformed or unrelated manifest must not prevent the
                # remaining extensions from being considered.
            }
        }
    }

    return @($manifests | Sort-Object -Property InstanceId, Scope, Id, Path -Unique)
}

function Find-InstalledExtension {
    param(
        [object]$Entry,
        [object[]]$Manifests,
        [string]$InstanceId
    )

    $entryId = [string](Get-PropertyValue -Object $Entry -Name 'VsixId' -Default '')
    $entryName = [string](Get-PropertyValue -Object $Entry -Name 'Name' -Default '')

    $instanceManifests = @($Manifests | Where-Object { $_.InstanceId -ieq $InstanceId })
    foreach ($manifest in @($instanceManifests | Sort-Object -Property @{ Expression = { if ($_.Scope -ieq 'User') { 0 } else { 1 } } }, Path)) {
        $manifestId = [string](Get-PropertyValue -Object $manifest -Name 'Id' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($entryId) -and $manifestId -ieq $entryId) {
            return $manifest
        }

        # The identity ID is the authoritative check.  DisplayName is only a
        # conservative fallback for old extensions whose recorded ID changed.
        $displayName = [string](Get-PropertyValue -Object $manifest -Name 'DisplayName' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($entryName) -and $displayName -ieq $entryName) {
            return $manifest
        }
    }

    return $null
}

function Test-VersionRangeIncludes {
    param(
        [string]$Range,
        [version]$Version
    )

    if ([string]::IsNullOrWhiteSpace($Range)) {
        return $false
    }

    $match = [regex]::Match($Range.Trim(), '^(?<open>[\[\(])\s*(?<lower>[0-9]+(?:\.[0-9]+){0,3})\s*,\s*(?<upper>[0-9]+(?:\.[0-9]+){0,3})\s*(?<close>[\]\)])$')
    if (-not $match.Success) {
        return $false
    }

    try {
        $lower = [version]$match.Groups['lower'].Value
        $upper = [version]$match.Groups['upper'].Value
    }
    catch {
        return $false
    }

    $lowerOk = if ($match.Groups['open'].Value -eq '[') { $Version -ge $lower } else { $Version -gt $lower }
    $upperOk = if ($match.Groups['close'].Value -eq ']') { $Version -le $upper } else { $Version -lt $upper }
    return [bool]($lowerOk -and $upperOk)
}

function ConvertTo-VersionOrNull {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    try {
        return [version]$Text
    }
    catch {
        return $null
    }
}

function Test-VersionRangeSyntax {
    param([string]$Range)

    if ([string]::IsNullOrWhiteSpace($Range)) {
        return $false
    }

    $match = [regex]::Match($Range.Trim(), '^(?<open>[\[\(])\s*(?<lower>[0-9]+(?:\.[0-9]+){0,3})\s*,\s*(?<upper>[0-9]+(?:\.[0-9]+){0,3})\s*(?<close>[\]\)])$')
    if (-not $match.Success) {
        return $false
    }

    try {
        $lower = [version]$match.Groups['lower'].Value
        $upper = [version]$match.Groups['upper'].Value
    }
    catch {
        return $false
    }

    return [bool]($lower -lt $upper)
}

function Assert-Inventory {
    param(
        [object]$Inventory,
        [object]$Profile,
        [string]$ProfileName,
        [object[]]$Entries
    )

    $errors = New-Object 'System.Collections.Generic.List[string]'
    $schemaVersion = Get-PropertyValue -Object $Inventory -Name 'SchemaVersion' -Default $null
    $hasProfiles = $null -ne (Get-PropertyValue -Object $Inventory -Name 'Profiles' -Default $null)
    $minimumSchemaVersion = if ($hasProfiles) { 2 } else { 1 }
    try {
        if ($null -eq $schemaVersion -or [int]$schemaVersion -lt $minimumSchemaVersion) {
            $errors.Add("SchemaVersion must be $minimumSchemaVersion or newer for this inventory shape.")
        }
    }
    catch {
        $errors.Add('SchemaVersion must be an integer.')
    }

    $targetVersionRange = [string](Get-PropertyValue -Object $Profile -Name 'TargetVersionRange' -Default '')
    if (-not (Test-VersionRangeSyntax -Range $targetVersionRange)) {
        $errors.Add("Profile '$ProfileName' has an invalid TargetVersionRange: '$targetVersionRange'.")
    }

    if ($Entries.Count -eq 0) {
        $errors.Add("Profile '$ProfileName' has no extension records.")
    }

    $seenVsixIds = @{}
    foreach ($entry in @($Entries)) {
        $name = [string](Get-PropertyValue -Object $entry -Name 'Name' -Default '')
        $vsixId = [string](Get-PropertyValue -Object $entry -Name 'VsixId' -Default '')
        if ([string]::IsNullOrWhiteSpace($name)) {
            $errors.Add('An extension record has no Name.')
        }
        if ([string]::IsNullOrWhiteSpace($vsixId)) {
            $errors.Add("Extension '$name' has no VsixId.")
        }
        elseif ($seenVsixIds.ContainsKey($vsixId)) {
            $errors.Add("Duplicate VsixId '$vsixId' in profile '$ProfileName'.")
        }
        else {
            $seenVsixIds[$vsixId] = $true
        }

        $autoInstall = [bool](Get-PropertyValue -Object $entry -Name 'AutoInstall' -Default $false)
        if (-not $autoInstall) {
            continue
        }

        $marketplaceId = [string](Get-PropertyValue -Object $entry -Name 'MarketplaceId' -Default '')
        if ([string]::IsNullOrWhiteSpace($marketplaceId) -or $marketplaceId -notmatch '\.') {
            $errors.Add("Auto-install extension '$name' must have a MarketplaceId containing a publisher separator.")
        }

        $installScope = [string](Get-PropertyValue -Object $entry -Name 'InstallScope' -Default 'User')
        if ($installScope -notin @('User', 'Machine', 'Any')) {
            $errors.Add("Extension '$name' has unsupported InstallScope '$installScope'.")
        }

        $versionPolicy = [string](Get-PropertyValue -Object $entry -Name 'VersionPolicy' -Default 'LatestCompatible')
        if ($versionPolicy -notin @('LatestCompatible', 'Manual')) {
            $errors.Add("Extension '$name' has unsupported VersionPolicy '$versionPolicy'.")
        }
    }

    if ($errors.Count -gt 0) {
        throw ('Extension inventory validation failed: ' + ($errors -join ' '))
    }
}

function Test-VisualStudioInstanceRunning {
    param([object]$Instance)

    $productPath = [string](Get-PropertyValue -Object $Instance -Name 'ProductPath' -Default '')
    if ([string]::IsNullOrWhiteSpace($productPath)) {
        return $false
    }

    foreach ($process in @(Get-Process -Name 'devenv' -ErrorAction SilentlyContinue)) {
        try {
            if ($process.Path -ieq $productPath) {
                return $true
            }
        }
        catch {
            # An inaccessible unrelated process is not attributed to this
            # instance; VSIXInstaller will report any actual lock failure.
        }
    }

    return $false
}

function Test-OfficialMarketplaceAssetUrl {
    param([string]$Url)

    try {
        $uri = [Uri]$Url
    }
    catch {
        return $false
    }

    if ($uri.Scheme -ine 'https') {
        return $false
    }

    $hostName = $uri.Host.ToLowerInvariant()
    return ($hostName -eq 'gallerycdn.vsassets.io' -or
        $hostName.EndsWith('.gallerycdn.vsassets.io') -or
        $hostName -eq 'gallery.vsassets.io' -or
        $hostName.EndsWith('.gallery.vsassets.io'))
}

function Get-MarketplaceMetadata {
    param(
        [object]$Entry,
        [object]$Inventory
    )

    $marketplaceId = [string](Get-PropertyValue -Object $Entry -Name 'MarketplaceId' -Default '')
    if ([string]::IsNullOrWhiteSpace($marketplaceId)) {
        throw 'No Marketplace ID is recorded.'
    }

    $apiUrl = [string](Get-PropertyValue -Object $Inventory -Name 'MarketplaceApiUrl' -Default '')
    if ($apiUrl -ne 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery') {
        throw 'The inventory does not use the official Visual Studio Marketplace API endpoint.'
    }

    $assetType = [string](Get-PropertyValue -Object $Inventory -Name 'MarketplaceAssetType' -Default '')
    if ([string]::IsNullOrWhiteSpace($assetType)) {
        throw 'MarketplaceAssetType is missing from the inventory.'
    }

    $query = @{
        filters = @(
            @{
                criteria  = @(@{ filterType = 7; value = $marketplaceId })
                pageNumber = 1
                pageSize   = 1
                sortBy     = 0
                sortOrder  = 0
            }
        )
        flags = 16863
    } | ConvertTo-Json -Depth 8

    $headers = @{
        Accept     = 'application/json;api-version=7.2-preview.1'
        'User-Agent' = 'dotfiles-vs-extension-restore/1.0'
    }

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -ContentType 'application/json' -Body $query -TimeoutSec 120
    }
    catch {
        throw "Marketplace query failed: $($_.Exception.Message)"
    }

    $results = @((Get-PropertyValue -Object $response -Name 'results' -Default @()))
    if ($results.Count -eq 0) {
        throw 'The official Marketplace API returned no result set.'
    }

    $extensions = @((Get-PropertyValue -Object $results[0] -Name 'extensions' -Default @()))
    if ($extensions.Count -eq 0 -or $null -eq $extensions[0]) {
        throw "No current Marketplace extension was returned for '$marketplaceId'."
    }

    $extension = $extensions[0]
    $publisher = Get-PropertyValue -Object (Get-PropertyValue -Object $extension -Name 'publisher' -Default $null) -Name 'publisherName' -Default ''
    $extensionName = [string](Get-PropertyValue -Object $extension -Name 'extensionName' -Default '')
    $canonicalId = "{0}.{1}" -f $publisher, $extensionName
    if ($canonicalId -ine $marketplaceId) {
        throw "Marketplace ID mismatch: requested '$marketplaceId', received '$canonicalId'."
    }

    $versions = @((Get-PropertyValue -Object $extension -Name 'versions' -Default @()))
    if ($versions.Count -eq 0) {
        throw 'The Marketplace extension has no published version.'
    }
    $version = $versions[0]
    $versionText = [string](Get-PropertyValue -Object $version -Name 'version' -Default '')

    $installationTargets = @()
    foreach ($target in @((Get-PropertyValue -Object $extension -Name 'installationTargets' -Default @()))) {
        $targetName = [string](Get-PropertyValue -Object $target -Name 'target' -Default '')
        $targetRange = [string](Get-PropertyValue -Object $target -Name 'targetVersion' -Default '')
        if ($targetName -like 'Microsoft.VisualStudio.*' -and $targetName -notlike '*.Ide' -and -not [string]::IsNullOrWhiteSpace($targetRange)) {
            $installationTargets += [PSCustomObject]@{
                Id    = $targetName
                Range = $targetRange
            }
        }
    }
    if ($installationTargets.Count -eq 0) {
        throw "The current Marketplace version '$versionText' does not declare a Visual Studio installation target."
    }

    $files = @((Get-PropertyValue -Object $version -Name 'files' -Default @()))
    $asset = $files | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'assetType' -Default '') -eq $assetType } | Select-Object -First 1
    if ($null -eq $asset) {
        throw "The Marketplace version has no '$assetType' asset."
    }

    $downloadUrl = [string](Get-PropertyValue -Object $asset -Name 'source' -Default '')
    if (-not (Test-OfficialMarketplaceAssetUrl -Url $downloadUrl)) {
        throw "The Marketplace returned a non-official or non-HTTPS asset URL: $downloadUrl"
    }

    return [PSCustomObject]@{
        CanonicalId       = $canonicalId
        Version           = $versionText
        DownloadUrl       = $downloadUrl
        InstallationTargets = $installationTargets
        AssetType         = $assetType
    }
}

function Get-CompatibleMarketplaceTargets {
    param(
        [object]$Marketplace,
        [version]$TargetVersion
    )

    $compatibleTargets = @()
    foreach ($target in @((Get-PropertyValue -Object $Marketplace -Name 'InstallationTargets' -Default @()))) {
        $targetId = [string](Get-PropertyValue -Object $target -Name 'Id' -Default '')
        $targetRange = [string](Get-PropertyValue -Object $target -Name 'Range' -Default '')
        if ((Test-VersionRangeIncludes -Range $targetRange -Version $TargetVersion)) {
            $compatibleTargets += "$targetId`:$targetRange"
        }
    }

    return @($compatibleTargets)
}

function Get-VsixManifestInfo {
    param([string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = $null
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($Path)
        $manifestEntry = $archive.Entries | Where-Object { $_.FullName -match '(^|/)extension\.vsixmanifest$' } | Select-Object -First 1
        if ($null -eq $manifestEntry) {
            return $null
        }

        $reader = New-Object IO.StreamReader($manifestEntry.Open())
        try {
            [xml]$xml = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }

        $identity = $xml.PackageManifest.Metadata.Identity
        $targets = @()
        foreach ($target in @($xml.PackageManifest.Installation.InstallationTarget)) {
            $targetId = [string](Get-PropertyValue -Object $target -Name 'Id' -Default '')
            $targetVersion = [string](Get-PropertyValue -Object $target -Name 'Version' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($targetId)) {
                $targets += [PSCustomObject]@{ Id = $targetId; Version = $targetVersion }
            }
        }

        return [PSCustomObject]@{
            Id          = [string](Get-PropertyValue -Object $identity -Name 'Id' -Default '')
            Version     = [string](Get-PropertyValue -Object $identity -Name 'Version' -Default '')
            DisplayName = [string](Get-PropertyValue -Object $xml.PackageManifest.Metadata -Name 'DisplayName' -Default '')
            Targets     = $targets
        }
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

function Download-AndValidateVsix {
    param(
        [object]$Entry,
        [object]$Marketplace
    )

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-vsix-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $vsixPath = Join-Path $tempRoot 'extension.vsix'

    try {
        Write-Info "Downloading $($Entry.Name) v$($Marketplace.Version) from $($Marketplace.DownloadUrl)"
        Invoke-WebRequest -Uri $Marketplace.DownloadUrl -OutFile $vsixPath -UseBasicParsing -TimeoutSec 120
        if (-not (Test-Path -LiteralPath $vsixPath -PathType Leaf) -or (Get-Item -LiteralPath $vsixPath).Length -le 0) {
            throw 'The Marketplace download produced no VSIX file.'
        }

        $vsixManifest = Get-VsixManifestInfo -Path $vsixPath
        if ($null -eq $vsixManifest) {
            throw 'The downloaded file does not contain extension.vsixmanifest.'
        }

        $expectedId = [string](Get-PropertyValue -Object $Entry -Name 'VsixId' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($expectedId) -and $vsixManifest.Id -ine $expectedId) {
            throw "VSIX identity mismatch: expected '$expectedId', received '$($vsixManifest.Id)'."
        }

        return [PSCustomObject]@{
            Path     = $vsixPath
            TempRoot = $tempRoot
            Manifest = $vsixManifest
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Test-VsixManifestSupportsVersion {
    param(
        [object]$Manifest,
        [version]$TargetVersion
    )

    foreach ($target in @((Get-PropertyValue -Object $Manifest -Name 'Targets' -Default @()))) {
        $targetId = [string](Get-PropertyValue -Object $target -Name 'Id' -Default '')
        $targetRange = [string](Get-PropertyValue -Object $target -Name 'Version' -Default '')
        if ($targetId -like 'Microsoft.VisualStudio.*' -and $targetId -notlike '*.Ide' -and (Test-VersionRangeIncludes -Range $targetRange -Version $TargetVersion)) {
            return $true
        }
    }

    return $false
}

function Invoke-VsixInstall {
    param(
        [object]$Instance,
        [string]$VsixPath
    )

    # No /admin is intentional: this requests the normal per-user install.
    # /norepair avoids turning a failed identity check into an in-place repair.
    $arguments = @(
        '/quiet'
        '/norepair'
        ("/instanceIds:{0}" -f $Instance.InstanceId)
        $VsixPath
    )

    $output = @(& $Instance.VsixInstaller @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = $output
    }
}

function Write-Summary {
    Write-Host ''
    $profileText = if ([string]::IsNullOrWhiteSpace($script:ProfileName)) { 'selected profile' } else { $script:ProfileName }
    Write-Host ("=== Visual Studio extension restore summary ({0}) ===" -f $profileText) -ForegroundColor White
    if ($script:DryRunEffective) {
        Write-Host 'Dry-run: no VSIX was downloaded or installed.' -ForegroundColor Yellow
    }

    foreach ($status in @('Planned', 'Succeeded', 'Skipped', 'Failed')) {
        $items = @($script:Results | Where-Object { $_.Status -eq $status })
        Write-Host ("{0} ({1})" -f $status, $items.Count) -ForegroundColor $(if ($status -eq 'Failed') { 'Red' } elseif ($status -eq 'Skipped') { 'Yellow' } else { 'Green' })
        foreach ($item in $items) {
            $instanceText = if ([string]::IsNullOrWhiteSpace($item.Instance)) { '-' } else { $item.Instance }
            Write-Host ("  - {0} [{1}] {2}" -f $item.Name, $instanceText, $item.Reason)
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $PSScriptRoot 'extensions.psd1'
}

if ([Environment]::GetEnvironmentVariable('OS') -ne 'Windows_NT') {
    Write-Error 'This script targets Windows Visual Studio installations only.'
    exit 1
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Write-Error "Extension inventory was not found: $ManifestPath"
    exit 1
}

try {
    $manifestFullPath = (Resolve-Path -LiteralPath $ManifestPath).Path
    $manifestDirectory = Split-Path -Parent $manifestFullPath
    $inventory = Import-PowerShellDataFile -LiteralPath $manifestFullPath
}
catch {
    Write-Error "Could not read extension inventory '$ManifestPath': $($_.Exception.Message)"
    exit 1
}

$profiles = Get-PropertyValue -Object $inventory -Name 'Profiles' -Default $null
$selectedProfile = $null
if ($null -ne $profiles) {
    $selectedProfileName = $Profile
    if ([string]::IsNullOrWhiteSpace($selectedProfileName)) {
        $selectedProfileName = [string](Get-PropertyValue -Object $inventory -Name 'DefaultProfile' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($selectedProfileName)) {
        Write-Error 'The inventory defines Profiles but no profile was selected and no DefaultProfile is recorded.'
        exit 1
    }
    if (-not ($profiles -is [System.Collections.IDictionary]) -or -not $profiles.Contains($selectedProfileName)) {
        Write-Error "The requested Visual Studio profile was not found: $selectedProfileName"
        exit 1
    }

    $selectedProfile = $profiles[$selectedProfileName]
    $script:ProfileName = $selectedProfileName
    $script:TargetVersionRange = [string](Get-PropertyValue -Object $selectedProfile -Name 'TargetVersionRange' -Default '')
    $script:IncludePrerelease = [bool](Get-PropertyValue -Object $selectedProfile -Name 'IncludePrerelease' -Default $false)
    $entries = @((Get-PropertyValue -Object $selectedProfile -Name 'Extensions' -Default @()))
}
else {
    # Read the original flat shape for hand-maintained inventories created
    # before profile support.  New inventories should use Profiles.
    $script:ProfileName = if ([string]::IsNullOrWhiteSpace($Profile)) { 'legacy' } else { $Profile }
    $script:TargetVersionRange = [string](Get-PropertyValue -Object $inventory -Name 'TargetVersionRange' -Default '')
    $script:IncludePrerelease = $false
    $entries = @((Get-PropertyValue -Object $inventory -Name 'Extensions' -Default @()))
}

if ($entries.Count -eq 0) {
    Write-Error 'The extension inventory is empty.'
    exit 1
}
if ([string]::IsNullOrWhiteSpace($script:TargetVersionRange)) {
    Write-Error "The selected profile '$($script:ProfileName)' has no TargetVersionRange."
    exit 1
}

$profileForValidation = if ($null -ne $selectedProfile) { $selectedProfile } else { $inventory }
try {
    Assert-Inventory -Inventory $inventory -Profile $profileForValidation -ProfileName $script:ProfileName -Entries $entries
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

$sourceDocumentName = [string](Get-PropertyValue -Object $inventory -Name 'SourceDocument' -Default 'extensions.md')
$sourceDocument = if ([IO.Path]::IsPathRooted($sourceDocumentName)) {
    $sourceDocumentName
}
else {
    Join-Path $manifestDirectory $sourceDocumentName
}
if (-not (Test-Path -LiteralPath $sourceDocument -PathType Leaf)) {
    Write-WarnMessage "The source record was not found next to the inventory: $sourceDocument"
}

Write-Info ("Loaded {0} extension records from profile '{1}' ({2})" -f $entries.Count, $script:ProfileName, $manifestFullPath)

$autoEntries = @()
foreach ($entry in $entries) {
    $name = [string](Get-PropertyValue -Object $entry -Name 'Name' -Default '(unnamed extension)')
    $autoInstall = [bool](Get-PropertyValue -Object $entry -Name 'AutoInstall' -Default $false)
    if ($autoInstall) {
        $autoEntries += $entry
    }
    else {
        $classification = [string](Get-PropertyValue -Object $entry -Name 'Classification' -Default 'NotAutomated')
        $notes = [string](Get-PropertyValue -Object $entry -Name 'Notes' -Default 'Not marked for automatic installation.')
        Add-Result -Status 'Skipped' -Name $name -Instance '' -Reason ("{0}: {1}" -f $classification, $notes)
    }
}

if ($autoEntries.Count -eq 0) {
    Write-Summary
    exit 0
}

$instances = @()
try {
    $instances = @(Get-VisualStudioInstances -TargetVersionRange $script:TargetVersionRange -IncludePrerelease $script:IncludePrerelease)
}
catch {
    Write-WarnMessage $_.Exception.Message
}
if ($instances.Count -eq 0) {
    foreach ($entry in $autoEntries) {
        Add-Result -Status 'Failed' -Name ([string](Get-PropertyValue -Object $entry -Name 'Name' -Default '(unnamed extension)')) -Instance '' -Reason ("No usable Visual Studio instance was found for profile '{0}' ({1})." -f $script:ProfileName, $script:TargetVersionRange)
    }
    Write-Summary
    exit 1
}

if (-not [string]::IsNullOrWhiteSpace($InstanceId)) {
    $selectedInstances = @($instances | Where-Object { $_.InstanceId -ieq $InstanceId })
    if ($selectedInstances.Count -eq 0) {
        foreach ($entry in $autoEntries) {
            Add-Result -Status 'Failed' -Name ([string](Get-PropertyValue -Object $entry -Name 'Name' -Default '(unnamed extension)')) -Instance '' -Reason ("The requested Visual Studio instanceId was not found in profile '{0}': {1}" -f $script:ProfileName, $InstanceId)
        }
        Write-Summary
        exit 1
    }
    $instances = $selectedInstances
}
elseif ($instances.Count -gt 1 -and -not $AllInstances) {
    foreach ($entry in $autoEntries) {
        Add-Result -Status 'Failed' -Name ([string](Get-PropertyValue -Object $entry -Name 'Name' -Default '(unnamed extension)')) -Instance '' -Reason ("Multiple Visual Studio instances match profile '{0}'. Specify -InstanceId or -AllInstances." -f $script:ProfileName)
    }
    Write-Summary
    exit 1
}

foreach ($instance in $instances) {
    Write-Info ("Target: {0} v{1} [{2}] (profile {3})" -f $instance.DisplayName, $instance.InstallationVersion, $instance.InstanceId, $script:ProfileName)
}

$installedManifests = @()
try {
    $installedManifests = @(Get-InstalledVsixManifests -Instances $instances)
    Write-Info ("Found {0} installed VSIX manifest(s) while checking idempotency." -f $installedManifests.Count)
}
catch {
    if (-not $AllowUnknownInstalledState) {
        foreach ($entry in $autoEntries) {
            Add-Result -Status 'Failed' -Name ([string](Get-PropertyValue -Object $entry -Name 'Name' -Default '(unnamed extension)')) -Instance '' -Reason ("Could not enumerate installed VSIX manifests; refusing to install with unknown state. Use -AllowUnknownInstalledState only when this is intentional. Details: {0}" -f $_.Exception.Message)
        }
        Write-Summary
        exit 1
    }
    Write-WarnMessage "Could not enumerate installed VSIX manifests; continuing because -AllowUnknownInstalledState was specified: $($_.Exception.Message)"
}

$runningInstanceIds = @{}
foreach ($instance in $instances) {
    if (Test-VisualStudioInstanceRunning -Instance $instance) {
        $runningInstanceIds[$instance.InstanceId] = $true
        Write-WarnMessage ("Visual Studio is running for instance {0}; install attempts for this instance are recorded as failures until it is closed." -f $instance.DisplayName)
    }
}

foreach ($entry in $autoEntries) {
    $entryName = [string](Get-PropertyValue -Object $entry -Name 'Name' -Default '(unnamed extension)')
    $marketplace = $null

    try {
        $marketplace = Get-MarketplaceMetadata -Entry $entry -Inventory $inventory
        $targetSummary = @($marketplace.InstallationTargets | ForEach-Object { "{0}:{1}" -f $_.Id, $_.Range })
        Write-Info ("{0}: Marketplace {1}, version {2}, declared targets {3}" -f $entryName, $marketplace.CanonicalId, $marketplace.Version, ($targetSummary -join ', '))
    }
    catch {
        Add-Result -Status 'Failed' -Name $entryName -Instance '' -Reason $_.Exception.Message
        continue
    }

    $pendingInstances = @()
    foreach ($instance in $instances) {
        $instanceVersion = [version]$instance.InstallationVersion
        $compatibleTargets = @(Get-CompatibleMarketplaceTargets -Marketplace $marketplace -TargetVersion $instanceVersion)
        if ($compatibleTargets.Count -eq 0) {
            Add-Result -Status 'Skipped' -Name $entryName -Instance $instance.DisplayName -Reason ("Marketplace version {0} does not support this instance version {1}." -f $marketplace.Version, $instance.InstallationVersion)
            continue
        }

        $installed = Find-InstalledExtension -Entry $entry -Manifests $installedManifests -InstanceId $instance.InstanceId
        $installScope = [string](Get-PropertyValue -Object $entry -Name 'InstallScope' -Default 'User')
        $versionPolicy = [string](Get-PropertyValue -Object $entry -Name 'VersionPolicy' -Default 'LatestCompatible')
        if ($null -ne $installed -and ($installScope -ieq 'Any' -or $installed.Scope -ieq $installScope)) {
            $installedVersion = ConvertTo-VersionOrNull ([string]$installed.Version)
            $availableVersion = ConvertTo-VersionOrNull ([string]$marketplace.Version)
            $needsUpdate = $false
            if ($versionPolicy -eq 'LatestCompatible' -and $null -ne $installedVersion -and $null -ne $availableVersion) {
                $needsUpdate = $installedVersion -lt $availableVersion
            }
            if (-not $needsUpdate -or $versionPolicy -eq 'Manual') {
                Add-Result -Status 'Skipped' -Name $entryName -Instance $instance.DisplayName -Reason ("Already installed in {0} scope (identity {1}, version {2})." -f $installed.Scope, $installed.Id, $installed.Version)
                continue
            }
            Write-Info ("{0}: updating {1} from installed version {2} to Marketplace version {3}." -f $entryName, $instance.DisplayName, $installed.Version, $marketplace.Version)
        }

        if ($runningInstanceIds.ContainsKey($instance.InstanceId)) {
            Add-Result -Status 'Failed' -Name $entryName -Instance $instance.DisplayName -Reason 'devenv.exe is running; close Visual Studio and rerun the script so the per-user extension can be applied safely.'
            continue
        }

        $pendingInstances += $instance
    }

    if ($pendingInstances.Count -eq 0) {
        continue
    }

    if ($script:DryRunEffective) {
        foreach ($instance in $pendingInstances) {
            Add-Result -Status 'Planned' -Name $entryName -Instance $instance.DisplayName -Reason ("Would download the official Marketplace asset and run VSIXInstaller /quiet /norepair /instanceIds:{0} for VS {1}." -f $instance.InstanceId, $instance.InstallationVersion)
        }
        continue
    }

    $downloaded = $null
    try {
        $downloaded = Download-AndValidateVsix -Entry $entry -Marketplace $marketplace
        foreach ($instance in $pendingInstances) {
            if (-not (Test-VsixManifestSupportsVersion -Manifest $downloaded.Manifest -TargetVersion ([version]$instance.InstallationVersion))) {
                Add-Result -Status 'Skipped' -Name $entryName -Instance $instance.DisplayName -Reason ("The downloaded VSIX manifest does not support this instance version {0}." -f $instance.InstallationVersion)
                continue
            }

            $targetDescription = "{0} ({1})" -f $entryName, $instance.DisplayName
            if (-not $PSCmdlet.ShouldProcess($targetDescription, 'Install the validated Marketplace VSIX for the current user')) {
                Add-Result -Status 'Skipped' -Name $entryName -Instance $instance.DisplayName -Reason 'WhatIf/confirmation prevented installation.'
                continue
            }

            try {
                Write-Info ("Installing {0} into {1} (per-user, no /admin)" -f $entryName, $instance.DisplayName)
                $installResult = Invoke-VsixInstall -Instance $instance -VsixPath $downloaded.Path
                if ($installResult.ExitCode -eq 0) {
                    Add-Result -Status 'Succeeded' -Name $entryName -Instance $instance.DisplayName -Reason 'VSIXInstaller exited with code 0. Restart Visual Studio to load the extension.'
                }
                else {
                    $details = (@($installResult.Output | ForEach-Object { [string]$_ } | Select-Object -Last 3) -join ' ').Trim()
                    if ([string]::IsNullOrWhiteSpace($details)) {
                        $details = 'VSIXInstaller returned a non-zero exit code.'
                    }
                    Add-Result -Status 'Failed' -Name $entryName -Instance $instance.DisplayName -Reason ("VSIXInstaller exit code {0}: {1}" -f $installResult.ExitCode, $details)
                }
            }
            catch {
                Add-Result -Status 'Failed' -Name $entryName -Instance $instance.DisplayName -Reason $_.Exception.Message
            }
        }
    }
    catch {
        foreach ($instance in $pendingInstances) {
            Add-Result -Status 'Failed' -Name $entryName -Instance $instance.DisplayName -Reason $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $downloaded -and (Test-Path -LiteralPath $downloaded.TempRoot)) {
            Remove-Item -LiteralPath $downloaded.TempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Summary

$failedCount = @($script:Results | Where-Object { $_.Status -eq 'Failed' }).Count
if ($script:DryRunEffective) {
    exit 0
}
if ($failedCount -gt 0) {
    exit 1
}
exit 0
