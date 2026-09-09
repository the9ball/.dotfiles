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
$script:TargetProduct = 'Visual Studio'

function Write-Info {
    <#
    .SYNOPSIS
    Writes an informational installer message.
    .DESCRIPTION
    Formats a non-error status message consistently for interactive runs.
    .PARAMETER Message
    Message text to display.
    #>
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnMessage {
    <#
    .SYNOPSIS
    Writes a warning installer message.
    .DESCRIPTION
    Formats a recoverable or noteworthy condition consistently for interactive runs.
    .PARAMETER Message
    Warning text to display.
    #>
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Add-Result {
    <#
    .SYNOPSIS
    Records one extension restore result.
    .DESCRIPTION
    Appends the normalized status, extension name, target instance, and reason
    to the process-wide summary collection.
    .PARAMETER Status
    Result state: Planned, Succeeded, Skipped, or Failed.
    .PARAMETER Name
    Inventory extension name.
    .PARAMETER Instance
    Target Visual Studio instance identifier, when applicable.
    .PARAMETER Reason
    Human-readable result explanation.
    #>
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
    <#
    .SYNOPSIS
    Reads a named value from a dictionary or object.
    .DESCRIPTION
    Provides one null-safe accessor for imported PowerShell data-file records.
    .PARAMETER Object
    Dictionary or object to inspect.
    .PARAMETER Name
    Property or dictionary key to retrieve.
    .PARAMETER Default
    Value returned when the object or member is absent.
    .OUTPUTS
    System.Object
    #>
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

function Test-MicrosoftSignedExecutable {
    <#
    .SYNOPSIS
    Confirms that an executable has a valid Microsoft Authenticode signature.
    .DESCRIPTION
    Reads the embedded Authenticode signature and accepts only a valid signer
    whose subject identifies Microsoft Corporation. Missing or unverifiable
    signatures fail closed so an attacker-controlled executable is never used.
    .PARAMETER Path
    Executable path to validate.
    .OUTPUTS
    System.Boolean
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) {
            return $false
        }
        return [bool]($signature.SignerCertificate.Subject -match '(?i)(?:^|,\s*)CN=Microsoft Corporation(?:,|$)' -or
            $signature.SignerCertificate.Subject -match '(?i)(?:^|,\s*)O=Microsoft Corporation(?:,|$)')
    }
    catch {
        return $false
    }
}

function Get-VsWherePath {
    <#
    .SYNOPSIS
    Locates the signed Visual Studio Installer vswhere executable.
    .DESCRIPTION
    Searches only the two Microsoft Visual Studio Installer locations derived
    from Program Files. PATH lookup is intentionally excluded because an
    untrusted same-named executable must not control instance discovery.
    .OUTPUTS
    System.String or null
    .EXCEPTION
    Throws when a candidate exists but fails the Microsoft signature check.
    #>
    $candidates = @()

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $candidates += Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
    }

    $programFiles = [Environment]::GetEnvironmentVariable('ProgramFiles')
    if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
        $candidates += Join-Path $programFiles 'Microsoft Visual Studio\Installer\vswhere.exe'
    }

    foreach ($candidate in @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $fullPath = (Get-Item -LiteralPath $candidate).FullName
            if (-not (Test-MicrosoftSignedExecutable -Path $fullPath)) {
                throw "The Visual Studio vswhere executable is not a valid Microsoft-signed binary: $fullPath"
            }
            return $fullPath
        }
    }

    return $null
}

function Get-VisualStudioInstances {
    <#
    .SYNOPSIS
    Discovers complete, launchable Visual Studio IDE instances in a version range.
    .DESCRIPTION
    Uses the signed official vswhere executable and applies the selected target
    product before returning instances with a usable VSIXInstaller path.
    .PARAMETER TargetVersionRange
    Inclusive/exclusive Visual Studio version range from the inventory.
    .PARAMETER IncludePrerelease
    Whether vswhere may include prerelease instances.
    .PARAMETER TargetProduct
    Inventory product selector; currently only Visual Studio is supported.
    .OUTPUTS
    PSCustomObject[]
    #>
    param(
        [string]$TargetVersionRange,
        [bool]$IncludePrerelease,
        [string]$TargetProduct = 'Visual Studio'
    )

    if ($TargetProduct -ne 'Visual Studio') {
        throw "Unsupported target product: '$TargetProduct'."
    }

    $vswherePath = Get-VsWherePath
    if ([string]::IsNullOrWhiteSpace($vswherePath)) {
        throw 'The signed Visual Studio Installer vswhere.exe was not found in the official Installer locations.'
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
        if ([string]::IsNullOrWhiteSpace($productId) -or $productId -notmatch '^Microsoft\.VisualStudio\.Product\.(Community|Professional|Enterprise)$') {
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

function Get-XmlAttributeValue {
    <#
    .SYNOPSIS
    Reads an XML attribute without depending on a document namespace.
    .DESCRIPTION
    VSIX manifests use a default XML namespace, so PowerShell property access is
    not reliable. This helper returns an empty string for a missing attribute.
    .PARAMETER Element
    XML element containing the attribute.
    .PARAMETER Name
    Attribute name.
    .OUTPUTS
    System.String
    #>
    param(
        [System.Xml.XmlElement]$Element,
        [string]$Name
    )
    if ($null -eq $Element -or $null -eq $Element.Attributes) {
        return ''
    }
    $attribute = $Element.Attributes.GetNamedItem($Name)
    if ($null -eq $attribute) {
        return ''
    }
    return [string]$attribute.Value
}

function Get-XmlChildText {
    <#
    .SYNOPSIS
    Reads the first child element text by local name.
    .DESCRIPTION
    Resolves a child through local-name XPath so default namespace prefixes do
    not alter VSIX manifest parsing.
    .PARAMETER Parent
    Parent XML element.
    .PARAMETER LocalName
    Child local name.
    .OUTPUTS
    System.String
    #>
    param(
        [System.Xml.XmlNode]$Parent,
        [string]$LocalName
    )
    if ($null -eq $Parent) {
        return ''
    }
    $child = $Parent.SelectSingleNode("./*[local-name()='$LocalName']")
    if ($null -eq $child) {
        return ''
    }
    return [string]$child.InnerText
}

function Get-InstalledVsixManifests {
    <#
    .SYNOPSIS
    Enumerates installed VSIX manifests for the selected instances.
    .DESCRIPTION
    Reads machine and per-user manifest roots and fails closed when any
    manifest cannot be parsed or read. The caller may explicitly opt into the
    unknown-state override, but malformed state is never silently treated as
    an absent extension.
    .PARAMETER Instances
    Visual Studio instances whose extension roots should be scanned.
    .OUTPUTS
    PSCustomObject[]
    .EXCEPTION
    Throws when a manifest or extension root cannot be enumerated.
    #>
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
                $targets = @()
                $packageManifest = $xml.SelectSingleNode("/*[local-name()='PackageManifest']")
                if ($null -ne $packageManifest) {
                    $metadata = $packageManifest.SelectSingleNode("./*[local-name()='Metadata']")
                    $identity = if ($null -ne $metadata) { $metadata.SelectSingleNode("./*[local-name()='Identity']") } else { $null }
                    if ($null -eq $metadata -or $null -eq $identity) {
                        throw 'VSIX manifest is missing PackageManifest/Metadata/Identity.'
                    }
                    $identityId = Get-XmlAttributeValue -Element $identity -Name 'Id'
                    $identityVersion = Get-XmlAttributeValue -Element $identity -Name 'Version'
                    $identityPublisher = Get-XmlAttributeValue -Element $identity -Name 'Publisher'
                    $displayName = Get-XmlChildText -Parent $metadata -LocalName 'DisplayName'
                    foreach ($target in @($packageManifest.SelectNodes(".//*[local-name()='InstallationTarget']"))) {
                        $targetId = Get-XmlAttributeValue -Element $target -Name 'Id'
                        $targetVersion = Get-XmlAttributeValue -Element $target -Name 'Version'
                        if (-not [string]::IsNullOrWhiteSpace($targetId)) {
                            $targets += "$targetId`:$targetVersion"
                        }
                    }
                }
                else {
                    $legacyRoot = $xml.SelectSingleNode("/*[local-name()='Vsix']")
                    $legacyIdentity = if ($null -ne $legacyRoot) { $legacyRoot.SelectSingleNode("./*[local-name()='Identifier']") } else { $null }
                    if ($null -eq $legacyIdentity) {
                        throw 'VSIX manifest is missing PackageManifest/Metadata/Identity or Vsix/Identifier.'
                    }
                    $identityId = Get-XmlAttributeValue -Element $legacyIdentity -Name 'Id'
                    $identityVersion = Get-XmlChildText -Parent $legacyIdentity -LocalName 'Version'
                    $identityPublisher = Get-XmlChildText -Parent $legacyIdentity -LocalName 'Author'
                    $displayName = Get-XmlChildText -Parent $legacyIdentity -LocalName 'Name'
                }
                if ([string]::IsNullOrWhiteSpace($identityId)) {
                    throw 'VSIX manifest identity has no Id attribute.'
                }

                $manifests += [PSCustomObject]@{
                    Id                  = $identityId
                    Version             = $identityVersion
                    Publisher           = $identityPublisher
                    DisplayName         = $displayName
                    Path                = $file.FullName
                    InstanceId          = [string]$root.InstanceId
                    Scope               = [string]$root.Scope
                    InstallationTargets = $targets
                }
            }
            catch {
                throw "Could not read installed VSIX manifest '$($file.FullName)': $($_.Exception.Message)"
            }
        }
    }

    return @($manifests | Sort-Object -Property InstanceId, Scope, Id, Path -Unique)
}

function Find-InstalledExtension {
    <#
    .SYNOPSIS
    Finds an installed extension by its exact VSIX identity.
    .DESCRIPTION
    Uses the inventory VsixId as the sole identity key. Display names are not
    unique and therefore cannot authorize an installed-state match.
    .PARAMETER Entry
    Inventory extension record containing VsixId.
    .PARAMETER Manifests
    Enumerated installed manifests.
    .PARAMETER InstanceId
    Instance identifier to constrain the search.
    .OUTPUTS
    PSCustomObject or null
    #>
    param(
        [object]$Entry,
        [object[]]$Manifests,
        [string]$InstanceId
    )

    $entryId = [string](Get-PropertyValue -Object $Entry -Name 'VsixId' -Default '')
    $instanceManifests = @($Manifests | Where-Object { $_.InstanceId -ieq $InstanceId })
    foreach ($manifest in @($instanceManifests | Sort-Object -Property @{ Expression = { if ($_.Scope -ieq 'User') { 0 } else { 1 } } }, Path)) {
        $manifestId = [string](Get-PropertyValue -Object $manifest -Name 'Id' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($entryId) -and $manifestId -ieq $entryId) {
            return $manifest
        }

    }

    return $null
}

function Test-VersionRangeIncludes {
    <#
    .SYNOPSIS
    Tests whether a version lies inside a bounded range.
    .DESCRIPTION
    Parses Visual Studio-style inclusive or exclusive endpoints and returns
    false for malformed or reversed ranges.
    .PARAMETER Range
    Range text such as [18.0,19.0).
    .PARAMETER Version
    Version to test.
    .OUTPUTS
    System.Boolean
    #>
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
    <#
    .SYNOPSIS
    Parses a stable extension version into a four-component Version value.
    .DESCRIPTION
    Normalizes missing build and revision components to zero and rejects
    prerelease or otherwise non-System.Version text.
    .PARAMETER Text
    Version text to parse.
    .OUTPUTS
    System.Version or null
    #>
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.Trim() -ne $Text -or $Text -notmatch '^[0-9]+(?:\.[0-9]+){0,3}$') {
        return $null
    }

    try {
        $parsed = [version]$Text
        $build = if ($parsed.Build -lt 0) { 0 } else { $parsed.Build }
        $revision = if ($parsed.Revision -lt 0) { 0 } else { $parsed.Revision }
        return [version]::new($parsed.Major, $parsed.Minor, $build, $revision)
    }
    catch {
        return $null
    }
}

function Get-VersionRangeBounds {
    <#
    .SYNOPSIS
    Parses a two-sided Visual Studio version range.
    .DESCRIPTION
    Returns normalized bounds and endpoint inclusivity for inventory overlap
    checks. Invalid or reversed ranges return null.
    .PARAMETER Range
    Range text such as [18.0,19.0).
    .OUTPUTS
    PSCustomObject or null
    #>
    param([string]$Range)

    if ([string]::IsNullOrWhiteSpace($Range)) {
        return $null
    }
    $match = [regex]::Match($Range.Trim(), '^(?<open>[\[\(])\s*(?<lower>[0-9]+(?:\.[0-9]+){0,3})\s*,\s*(?<upper>[0-9]+(?:\.[0-9]+){0,3})\s*(?<close>[\]\)])$')
    if (-not $match.Success) {
        return $null
    }
    $lower = ConvertTo-VersionOrNull -Text $match.Groups['lower'].Value
    $upper = ConvertTo-VersionOrNull -Text $match.Groups['upper'].Value
    if ($null -eq $lower -or $null -eq $upper -or $lower -ge $upper) {
        return $null
    }
    return [PSCustomObject]@{
        Lower = $lower
        Upper = $upper
        LowerInclusive = ($match.Groups['open'].Value -eq '[')
        UpperInclusive = ($match.Groups['close'].Value -eq ']')
    }
}

function Test-VersionRangesIntersect {
    <#
    .SYNOPSIS
    Determines whether two bounded version ranges overlap.
    .DESCRIPTION
    Compares normalized bounds while preserving open and closed endpoint
    semantics. Invalid ranges are treated as non-overlapping.
    .PARAMETER Left
    First version range.
    .PARAMETER Right
    Second version range.
    .OUTPUTS
    System.Boolean
    #>
    param(
        [string]$Left,
        [string]$Right
    )

    $leftBounds = Get-VersionRangeBounds -Range $Left
    $rightBounds = Get-VersionRangeBounds -Range $Right
    if ($null -eq $leftBounds -or $null -eq $rightBounds) {
        return $false
    }

    $lower = if ($leftBounds.Lower -gt $rightBounds.Lower) { $leftBounds.Lower } else { $rightBounds.Lower }
    $upper = if ($leftBounds.Upper -lt $rightBounds.Upper) { $leftBounds.Upper } else { $rightBounds.Upper }
    if ($lower -lt $upper) {
        return $true
    }
    if ($lower -gt $upper) {
        return $false
    }

    $lowerInclusive = (($leftBounds.Lower -eq $lower -and $leftBounds.LowerInclusive) -or
        ($rightBounds.Lower -eq $lower -and $rightBounds.LowerInclusive))
    $upperInclusive = (($leftBounds.Upper -eq $upper -and $leftBounds.UpperInclusive) -or
        ($rightBounds.Upper -eq $upper -and $rightBounds.UpperInclusive))
    return [bool]($lowerInclusive -and $upperInclusive)
}

function Test-VersionRangeSyntax {
    <#
    .SYNOPSIS
    Validates a bounded version-range expression.
    .DESCRIPTION
    Accepts numeric two-sided ranges and rejects malformed or reversed bounds.
    .PARAMETER Range
    Range text to validate.
    .OUTPUTS
    System.Boolean
    #>
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
    <#
    .SYNOPSIS
    Validates the selected Visual Studio extension inventory.
    .DESCRIPTION
    Checks schema, target-product, identity, acquisition, version-policy, and
    Marketplace-target consistency before any network or installer action.
    Auto-install records are pinned to an explicitly reviewed version and
    SHA-256 digest so a moving Marketplace response cannot silently change the
    installed artifact.
    .PARAMETER Inventory
    Complete imported inventory document.
    .PARAMETER Profile
    Selected profile object.
    .PARAMETER ProfileName
    Human-readable selected profile name.
    .PARAMETER Entries
    Extension records selected by the profile.
    .EXCEPTION
    Throws when any validation rule fails.
    #>
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

    $targetProduct = [string](Get-PropertyValue -Object $Profile -Name 'TargetProduct' -Default '')
    if ($targetProduct -ne 'Visual Studio') {
        $errors.Add("Profile '$ProfileName' must target exactly 'Visual Studio'.")
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
        if ($installScope -notin @('User', 'Any')) {
            $errors.Add("Extension '$name' has unsupported per-user InstallScope '$installScope'.")
        }

        $versionPolicy = [string](Get-PropertyValue -Object $entry -Name 'VersionPolicy' -Default 'Pinned')
        if ($versionPolicy -ne 'Pinned') {
            $errors.Add("Auto-install extension '$name' must use VersionPolicy='Pinned'.")
        }

        $acquireMethod = [string](Get-PropertyValue -Object $entry -Name 'AcquireMethod' -Default '')
        if ($acquireMethod -ne 'MarketplaceGalleryApi') {
            $errors.Add("Auto-install extension '$name' must use AcquireMethod='MarketplaceGalleryApi'.")
        }

        $classification = [string](Get-PropertyValue -Object $entry -Name 'Classification' -Default '')
        if ($classification -ne 'Marketplace') {
            $errors.Add("Auto-install extension '$name' must use Classification='Marketplace'.")
        }

        $downloadUrl = [string](Get-PropertyValue -Object $entry -Name 'DownloadUrl' -Default '')
        try {
            $downloadUri = [Uri]$downloadUrl
            if ($downloadUri.Scheme -ine 'https' -or $downloadUri.Host -ine 'marketplace.visualstudio.com') {
                throw 'not-official-marketplace-url'
            }
            $itemNameMatch = [regex]::Match($downloadUri.Query, '(?i)(?:^|[?&])itemName=([^&]+)')
            $itemName = if ($itemNameMatch.Success) { [Uri]::UnescapeDataString($itemNameMatch.Groups[1].Value) } else { '' }
            if ($itemName -ine $marketplaceId) {
                throw 'marketplace-id-mismatch'
            }
        }
        catch {
            $errors.Add("Auto-install extension '$name' must record the official Marketplace item URL for '$marketplaceId'.")
        }

        $marketplaceTargetsText = [string](Get-PropertyValue -Object $entry -Name 'MarketplaceTargets' -Default '')
        $targetRanges = @($marketplaceTargetsText -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($targetRanges.Count -eq 0) {
            $errors.Add("Auto-install extension '$name' must declare MarketplaceTargets.")
        }
        else {
            $hasCompatibleTarget = $false
            foreach ($targetRange in $targetRanges) {
                if (-not (Test-VersionRangeSyntax -Range $targetRange)) {
                    $errors.Add("Extension '$name' has an invalid MarketplaceTargets range '$targetRange'.")
                    continue
                }
                if (Test-VersionRangesIntersect -Left $targetVersionRange -Right $targetRange) {
                    $hasCompatibleTarget = $true
                }
            }
            if (-not $hasCompatibleTarget) {
                $errors.Add("Auto-install extension '$name' has no MarketplaceTargets range compatible with profile '$ProfileName'.")
            }
        }

        $expectedVersion = ConvertTo-VersionOrNull -Text ([string](Get-PropertyValue -Object $entry -Name 'ExpectedVersion' -Default ''))
        if ($null -eq $expectedVersion) {
            $errors.Add("Pinned auto-install extension '$name' must declare a stable ExpectedVersion.")
        }
        $expectedSha256 = [string](Get-PropertyValue -Object $entry -Name 'ExpectedSha256' -Default '')
        if ($expectedSha256 -notmatch '^(?i:[0-9a-f]{64})$') {
            $errors.Add("Pinned auto-install extension '$name' must declare a 64-character ExpectedSha256.")
        }
        $expectedPublisher = [string](Get-PropertyValue -Object $entry -Name 'ExpectedPublisher' -Default '')
        if ([string]::IsNullOrWhiteSpace($expectedPublisher)) {
            $errors.Add("Pinned auto-install extension '$name' must declare ExpectedPublisher.")
        }
    }

    if ($errors.Count -gt 0) {
        throw ('Extension inventory validation failed: ' + ($errors -join ' '))
    }
}

function Get-VisualStudioInstanceState {
    <#
    .SYNOPSIS
    Determines whether a Visual Studio instance is stopped, running, or unknown.
    .DESCRIPTION
    Matches devenv.exe by the instance product path. Any inability to inspect a
    process path is treated as Unknown so the installer fails closed rather
    than assuming the instance is stopped.
    .PARAMETER Instance
    Visual Studio instance record containing ProductPath.
    .OUTPUTS
    System.String: NotRunning, Running, or Unknown
    #>
    param([object]$Instance)

    $productPath = [string](Get-PropertyValue -Object $Instance -Name 'ProductPath' -Default '')
    if ([string]::IsNullOrWhiteSpace($productPath)) {
        return 'Unknown'
    }

    try {
        $processes = @(Get-Process -Name 'devenv' -ErrorAction Stop)
    }
    catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        return 'NotRunning'
    }
    catch {
        return 'Unknown'
    }

    foreach ($process in $processes) {
        try {
            if ([string]::IsNullOrWhiteSpace([string]$process.Path)) {
                return 'Unknown'
            }
            if ([IO.Path]::GetFullPath([string]$process.Path) -ieq [IO.Path]::GetFullPath($productPath)) {
                return 'Running'
            }
        }
        catch {
            return 'Unknown'
        }
    }

    return 'NotRunning'
}

function Test-OfficialMarketplaceAssetUrl {
    <#
    .SYNOPSIS
    Checks whether a Marketplace asset URL is an allowed HTTPS CDN URL.
    .DESCRIPTION
    Restricts downloads to the official Visual Studio gallery CDN hostnames.
    This predicate is applied to the initial URL and every redirect hop.
    .PARAMETER Url
    URL to validate.
    .OUTPUTS
    System.Boolean
    #>
    param([string]$Url)

    try {
        $uri = [Uri]$Url
    }
    catch {
        return $false
    }

    if ($uri.Scheme -ine 'https' -or $uri.Port -ne 443) {
        return $false
    }

    $hostName = $uri.Host.ToLowerInvariant()
    return ($hostName -eq 'gallerycdn.vsassets.io' -or
        $hostName.EndsWith('.gallerycdn.vsassets.io') -or
        $hostName -eq 'gallery.vsassets.io' -or
        $hostName.EndsWith('.gallery.vsassets.io'))
}

function Get-MarketplaceMetadata {
    <#
    .SYNOPSIS
    Resolves a pinned or latest stable Marketplace version for an extension.
    .DESCRIPTION
    Queries only the official Marketplace API, validates the canonical ID, and
    selects the highest parseable validated stable version unless the inventory
    pins an ExpectedVersion. Prerelease and malformed versions are excluded.
    .PARAMETER Entry
    Inventory extension record.
    .PARAMETER Inventory
    Complete imported inventory document.
    .PARAMETER IncludePrerelease
    Whether prerelease versions are allowed by the selected profile.
    .OUTPUTS
    PSCustomObject
    .EXCEPTION
    Throws when the official response is incomplete or inconsistent.
    #>
    param(
        [object]$Entry,
        [object]$Inventory,
        [bool]$IncludePrerelease = $false
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
                pageSize   = 100
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
    $versionCandidates = @()
    foreach ($candidate in $versions) {
        $candidateText = [string](Get-PropertyValue -Object $candidate -Name 'version' -Default '')
        $candidateVersion = ConvertTo-VersionOrNull -Text $candidateText
        if ($null -eq $candidateVersion) {
            continue
        }
        $flagsText = [string](Get-PropertyValue -Object $candidate -Name 'flags' -Default '')
        $isPrerelease = $candidateText -match '(?i)[-+]' -or $flagsText -match '(?i)prerelease'
        if (-not $IncludePrerelease -and $isPrerelease) {
            continue
        }
        # Marketplace normally exposes a textual validated flag. Numeric flags
        # are retained for compatibility with older API responses, while a
        # textual flag set must explicitly identify a validated release.
        if (-not [string]::IsNullOrWhiteSpace($flagsText) -and
            $flagsText -notmatch '^[0-9]+$' -and
            $flagsText -notmatch '(?i)\bvalidated\b') {
            continue
        }
        $versionCandidates += [PSCustomObject]@{
            Record = $candidate
            Text = $candidateText
            Version = $candidateVersion
            Flags = $flagsText
            IsPrerelease = $isPrerelease
        }
    }
    if ($versionCandidates.Count -eq 0) {
        throw 'The Marketplace extension has no parseable validated stable version.'
    }

    $expectedVersionText = [string](Get-PropertyValue -Object $Entry -Name 'ExpectedVersion' -Default '')
    $expectedVersion = ConvertTo-VersionOrNull -Text $expectedVersionText
    if (-not [string]::IsNullOrWhiteSpace($expectedVersionText) -and $null -eq $expectedVersion) {
        throw "Inventory ExpectedVersion is not a stable version: '$expectedVersionText'."
    }
    $selectedVersion = if ($null -ne $expectedVersion) {
        @($versionCandidates | Where-Object { $_.Version -eq $expectedVersion } | Select-Object -First 1)
    }
    else {
        @($versionCandidates | Sort-Object -Property @{ Expression = { $_.Version }; Descending = $true } | Select-Object -First 1)
    }
    if ($null -eq $selectedVersion -or @($selectedVersion).Count -eq 0) {
        throw "The Marketplace did not return the pinned ExpectedVersion '$expectedVersionText'."
    }
    $selectedVersion = @($selectedVersion)[0]
    $version = $selectedVersion.Record
    $versionText = $selectedVersion.Text

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
        VersionObject     = $selectedVersion.Version
        DownloadUrl       = $downloadUrl
        InstallationTargets = $installationTargets
        AssetType         = $assetType
        Flags             = $selectedVersion.Flags
        IsPrerelease      = $selectedVersion.IsPrerelease
    }
}

function Get-CompatibleMarketplaceTargets {
    <#
    .SYNOPSIS
    Lists Marketplace installation targets compatible with a Visual Studio version.
    .DESCRIPTION
    Filters the validated Marketplace target ranges and returns stable textual
    identifiers for installer result reporting.
    .PARAMETER Marketplace
    Marketplace metadata returned by Get-MarketplaceMetadata.
    .PARAMETER TargetVersion
    Visual Studio version to test.
    .OUTPUTS
    System.String[]
    #>
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
    <#
    .SYNOPSIS
    Reads identity and Visual Studio targets from a VSIX manifest.
    .DESCRIPTION
    Opens the VSIX as a ZIP archive and returns the manifest identity, version,
    display name, and installation targets. Missing identity or malformed
    archives are rejected by the caller.
    .PARAMETER Path
    VSIX archive path.
    .OUTPUTS
    PSCustomObject or null
    #>
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

        $targets = @()
        $packageManifest = $xml.SelectSingleNode("/*[local-name()='PackageManifest']")
        if ($null -ne $packageManifest) {
            $metadata = $packageManifest.SelectSingleNode("./*[local-name()='Metadata']")
            $identity = if ($null -ne $metadata) { $metadata.SelectSingleNode("./*[local-name()='Identity']") } else { $null }
            if ($null -eq $metadata -or $null -eq $identity) {
                throw 'VSIX manifest is missing PackageManifest/Metadata/Identity.'
            }
            $identityId = Get-XmlAttributeValue -Element $identity -Name 'Id'
            $identityVersion = Get-XmlAttributeValue -Element $identity -Name 'Version'
            $identityPublisher = Get-XmlAttributeValue -Element $identity -Name 'Publisher'
            $displayName = Get-XmlChildText -Parent $metadata -LocalName 'DisplayName'
            foreach ($target in @($packageManifest.SelectNodes(".//*[local-name()='InstallationTarget']"))) {
                $targetId = Get-XmlAttributeValue -Element $target -Name 'Id'
                $targetVersion = Get-XmlAttributeValue -Element $target -Name 'Version'
                if (-not [string]::IsNullOrWhiteSpace($targetId)) {
                    $targets += [PSCustomObject]@{ Id = $targetId; Version = $targetVersion }
                }
            }
        }
        else {
            $legacyRoot = $xml.SelectSingleNode("/*[local-name()='Vsix']")
            $legacyIdentity = if ($null -ne $legacyRoot) { $legacyRoot.SelectSingleNode("./*[local-name()='Identifier']") } else { $null }
            if ($null -eq $legacyIdentity) {
                throw 'VSIX manifest is missing PackageManifest/Metadata/Identity or Vsix/Identifier.'
            }
            $identityId = Get-XmlAttributeValue -Element $legacyIdentity -Name 'Id'
            $identityVersion = Get-XmlChildText -Parent $legacyIdentity -LocalName 'Version'
            $identityPublisher = Get-XmlChildText -Parent $legacyIdentity -LocalName 'Author'
            $displayName = Get-XmlChildText -Parent $legacyIdentity -LocalName 'Name'
        }

        return [PSCustomObject]@{
            Id          = $identityId
            Version     = $identityVersion
            Publisher   = $identityPublisher
            DisplayName = $displayName
            Targets     = $targets
        }
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

function Invoke-OfficialMarketplaceDownload {
    <#
    .SYNOPSIS
    Downloads a Marketplace asset while validating every redirect hop.
    .DESCRIPTION
    Uses an HttpClient with automatic redirects disabled. Each URL must remain
    HTTPS on an official gallery CDN host, relative Location headers are
    resolved against the current URL, and the bounded redirect count prevents
    loops or policy bypasses.
    .PARAMETER Url
    Initial official Marketplace asset URL.
    .PARAMETER OutputPath
    Destination path for the final response body.
    .PARAMETER MaximumRedirects
    Maximum number of redirect responses to follow.
    .OUTPUTS
    PSCustomObject containing FinalUrl and RedirectCount
    .EXCEPTION
    Throws for invalid hosts, missing Location headers, redirect loops, HTTP
    errors, or failed file writes.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [int]$MaximumRedirects = 5
    )

    Add-Type -AssemblyName System.Net.Http
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(120)
    [void]$client.DefaultRequestHeaders.UserAgent.ParseAdd('dotfiles-vs-extension-restore/1.0')
    $currentUri = $null
    try {
        try {
            $currentUri = [Uri]$Url
        }
        catch {
            throw "Marketplace asset URL is invalid: $Url"
        }
        for ($redirectCount = 0; ; $redirectCount++) {
            if (-not (Test-OfficialMarketplaceAssetUrl -Url $currentUri.AbsoluteUri)) {
                throw "Marketplace redirect leaves the official HTTPS CDN: $($currentUri.AbsoluteUri)"
            }

            $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $currentUri)
            $response = $null
            try {
                $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                $statusCode = [int]$response.StatusCode
                if ($statusCode -ge 300 -and $statusCode -lt 400) {
                    if ($redirectCount -ge $MaximumRedirects) {
                        throw "Marketplace asset exceeded the maximum redirect count of $MaximumRedirects."
                    }
                    $location = $response.Headers.Location
                    if ($null -eq $location) {
                        throw "Marketplace asset returned HTTP $statusCode without a Location header."
                    }
                    $currentUri = [Uri]::new($currentUri, $location)
                    continue
                }
                if (-not $response.IsSuccessStatusCode) {
                    throw "Marketplace asset download returned HTTP $statusCode."
                }

                $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $outputStream = [IO.File]::Open($OutputPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try {
                    $inputStream.CopyToAsync($outputStream).GetAwaiter().GetResult()
                }
                finally {
                    $outputStream.Dispose()
                    $inputStream.Dispose()
                }
                return [PSCustomObject]@{
                    FinalUrl = $currentUri.AbsoluteUri
                    RedirectCount = $redirectCount
                }
            }
            finally {
                if ($null -ne $response) {
                    $response.Dispose()
                }
                $request.Dispose()
            }
        }
    }
    finally {
        $client.Dispose()
        $handler.Dispose()
    }
}

function Download-AndValidateVsix {
    <#
    .SYNOPSIS
    Downloads and validates a pinned Marketplace VSIX.
    .DESCRIPTION
    Validates the VSIX identity, Marketplace-selected version, manifest target,
    and inventory SHA-256 pin before returning a temporary artifact for the
    installer.
    .PARAMETER Entry
    Inventory extension record.
    .PARAMETER Marketplace
    Validated Marketplace metadata.
    .OUTPUTS
    PSCustomObject containing Path, TempRoot, Manifest, and Sha256.
    .EXCEPTION
    Throws when the artifact, redirect chain, hash, identity, or version is
    inconsistent; temporary data is removed before rethrowing.
    #>
    param(
        [object]$Entry,
        [object]$Marketplace
    )

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-vsix-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $vsixPath = Join-Path $tempRoot 'extension.vsix'

    try {
        Write-Info "Downloading $($Entry.Name) v$($Marketplace.Version) from $($Marketplace.DownloadUrl)"
        $downloadInfo = Invoke-OfficialMarketplaceDownload -Url $Marketplace.DownloadUrl -OutputPath $vsixPath
        if (-not (Test-Path -LiteralPath $vsixPath -PathType Leaf) -or (Get-Item -LiteralPath $vsixPath).Length -le 0) {
            throw 'The Marketplace download produced no VSIX file.'
        }

        $expectedHash = [string](Get-PropertyValue -Object $Entry -Name 'ExpectedSha256' -Default '')
        $actualHash = (Get-FileHash -LiteralPath $vsixPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        if ($actualHash -ine $expectedHash.ToLowerInvariant()) {
            throw "VSIX SHA-256 mismatch: expected '$expectedHash', received '$actualHash'."
        }

        $vsixManifest = Get-VsixManifestInfo -Path $vsixPath
        if ($null -eq $vsixManifest) {
            throw 'The downloaded file does not contain extension.vsixmanifest.'
        }

        $expectedId = [string](Get-PropertyValue -Object $Entry -Name 'VsixId' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($expectedId) -and $vsixManifest.Id -ine $expectedId) {
            throw "VSIX identity mismatch: expected '$expectedId', received '$($vsixManifest.Id)'."
        }

        $expectedPublisher = [string](Get-PropertyValue -Object $Entry -Name 'ExpectedPublisher' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($expectedPublisher) -and $vsixManifest.Publisher -ine $expectedPublisher) {
            throw "VSIX publisher mismatch: expected '$expectedPublisher', received '$($vsixManifest.Publisher)'."
        }

        $manifestVersion = ConvertTo-VersionOrNull -Text ([string]$vsixManifest.Version)
        $marketplaceVersion = ConvertTo-VersionOrNull -Text ([string]$Marketplace.Version)
        if ($null -eq $manifestVersion -or $null -eq $marketplaceVersion -or $manifestVersion -ne $marketplaceVersion) {
            throw "VSIX version mismatch: Marketplace '$($Marketplace.Version)', manifest '$($vsixManifest.Version)'."
        }

        return [PSCustomObject]@{
            Path     = $vsixPath
            TempRoot = $tempRoot
            Manifest = $vsixManifest
            Sha256   = $actualHash
            FinalUrl = $downloadInfo.FinalUrl
        }
    }
    catch {
        $downloadException = $_
        if (Test-Path -LiteralPath $tempRoot) {
            try {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction Stop
            }
            catch {
                throw "$($downloadException.Exception.Message) Temporary VSIX cleanup also failed: $($_.Exception.Message)"
            }
        }
        throw $downloadException
    }
}

function Test-VsixManifestSupportsVersion {
    <#
    .SYNOPSIS
    Tests whether a VSIX manifest targets a Visual Studio version.
    .DESCRIPTION
    Accepts only Microsoft.VisualStudio targets that are not the IDE-only target
    and whose declared version range contains the selected instance version.
    .PARAMETER Manifest
    Parsed VSIX manifest information.
    .PARAMETER TargetVersion
    Visual Studio version to test.
    .OUTPUTS
    System.Boolean
    #>
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
    <#
    .SYNOPSIS
    Invokes VSIXInstaller for a per-user extension installation.
    .DESCRIPTION
    Runs VSIXInstaller without /admin and returns its exit code and captured
    output. The caller decides whether the installer-reported result is a
    success or failure.
    .PARAMETER Instance
    Visual Studio instance receiving the extension.
    .PARAMETER VsixPath
    Validated VSIX archive path.
    .OUTPUTS
    PSCustomObject
    #>
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

function Remove-DownloadedVsix {
    <#
    .SYNOPSIS
    Removes a temporary downloaded VSIX and reports cleanup failures.
    .DESCRIPTION
    Cleanup is best-effort only after the installation attempt, but any failure
    is surfaced as a failed result so a leftover artifact is observable.
    .PARAMETER Downloaded
    Object returned by Download-AndValidateVsix.
    .PARAMETER EntryName
    Inventory name used in the result record.
    .OUTPUTS
    System.Boolean
    #>
    param(
        [object]$Downloaded,
        [string]$EntryName
    )

    if ($null -eq $Downloaded -or [string]::IsNullOrWhiteSpace([string]$Downloaded.TempRoot) -or
        -not (Test-Path -LiteralPath $Downloaded.TempRoot)) {
        return $true
    }
    try {
        Remove-Item -LiteralPath $Downloaded.TempRoot -Recurse -Force -ErrorAction Stop
        return $true
    }
    catch {
        $reason = "Temporary VSIX cleanup failed for '$($Downloaded.TempRoot)': $($_.Exception.Message)"
        Write-WarnMessage $reason
        Add-Result -Status 'Failed' -Name $EntryName -Instance '' -Reason $reason
        return $false
    }
}

function Write-Summary {
    <#
    .SYNOPSIS
    Prints the extension restore summary.
    .DESCRIPTION
    Groups recorded results by status and displays the final dry-run or install
    outcome for the selected profile.
    #>
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
    $script:TargetProduct = [string](Get-PropertyValue -Object $selectedProfile -Name 'TargetProduct' -Default '')
    $entries = @((Get-PropertyValue -Object $selectedProfile -Name 'Extensions' -Default @()))
}
else {
    # Read the original flat shape for hand-maintained inventories created
    # before profile support.  New inventories should use Profiles.
    $script:ProfileName = if ([string]::IsNullOrWhiteSpace($Profile)) { 'legacy' } else { $Profile }
    $script:TargetVersionRange = [string](Get-PropertyValue -Object $inventory -Name 'TargetVersionRange' -Default '')
    $script:IncludePrerelease = $false
    $script:TargetProduct = [string](Get-PropertyValue -Object $inventory -Name 'TargetProduct' -Default 'Visual Studio')
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
    $instances = @(Get-VisualStudioInstances -TargetVersionRange $script:TargetVersionRange -IncludePrerelease $script:IncludePrerelease -TargetProduct $script:TargetProduct)
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

$runningInstanceStates = @{}
foreach ($instance in $instances) {
    $instanceState = Get-VisualStudioInstanceState -Instance $instance
    if ($instanceState -ne 'NotRunning') {
        $runningInstanceStates[$instance.InstanceId] = $instanceState
        Write-WarnMessage ("Visual Studio state for instance {0} is {1}; install attempts for this instance are refused until it is confirmed stopped." -f $instance.DisplayName, $instanceState)
    }
}

foreach ($entry in $autoEntries) {
    $entryName = [string](Get-PropertyValue -Object $entry -Name 'Name' -Default '(unnamed extension)')
    $marketplace = $null

    try {
        $marketplace = Get-MarketplaceMetadata -Entry $entry -Inventory $inventory -IncludePrerelease $script:IncludePrerelease
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
        $versionPolicy = [string](Get-PropertyValue -Object $entry -Name 'VersionPolicy' -Default 'Pinned')
        if ($null -ne $installed -and ($installScope -ieq 'Any' -or $installed.Scope -ieq $installScope)) {
            $installedVersion = ConvertTo-VersionOrNull ([string]$installed.Version)
            $availableVersion = ConvertTo-VersionOrNull ([string]$marketplace.Version)
            if ($versionPolicy -eq 'Pinned' -and $null -eq $installedVersion) {
                Add-Result -Status 'Failed' -Name $entryName -Instance $instance.DisplayName -Reason ("Installed VSIX identity '$($installed.Id)' has an invalid version '$($installed.Version)'; refusing to overwrite unknown state.")
                continue
            }
            $needsUpdate = $false
            if ($versionPolicy -eq 'Pinned' -and $null -ne $installedVersion -and $null -ne $availableVersion) {
                $needsUpdate = $installedVersion -ne $availableVersion
            }
            if (-not $needsUpdate) {
                Add-Result -Status 'Skipped' -Name $entryName -Instance $instance.DisplayName -Reason ("Already installed in {0} scope (identity {1}, version {2})." -f $installed.Scope, $installed.Id, $installed.Version)
                continue
            }
            Write-Info ("{0}: updating {1} from installed version {2} to Marketplace version {3}." -f $entryName, $instance.DisplayName, $installed.Version, $marketplace.Version)
        }

        if ($runningInstanceStates.ContainsKey($instance.InstanceId)) {
            Add-Result -Status 'Failed' -Name $entryName -Instance $instance.DisplayName -Reason ("Visual Studio process state is '{0}'; close Visual Studio and rerun the script so the per-user extension can be applied safely." -f $runningInstanceStates[$instance.InstanceId])
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
                $currentState = Get-VisualStudioInstanceState -Instance $instance
                if ($currentState -ne 'NotRunning') {
                    Add-Result -Status 'Failed' -Name $entryName -Instance $instance.DisplayName -Reason ("Visual Studio process state changed to '{0}' before installation." -f $currentState)
                    continue
                }
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
        [void](Remove-DownloadedVsix -Downloaded $downloaded -EntryName $entryName)
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
