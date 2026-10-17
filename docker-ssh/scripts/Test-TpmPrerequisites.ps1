<# .SYNOPSIS Reports read-only TPM deployment prerequisites; never installs dependencies, creates keys, or starts services. #>
[CmdletBinding()]
param([ValidateSet('Build','Run','Test')][string] $Purpose='Test')
$ErrorActionPreference='Stop'
$base=& (Join-Path $PSScriptRoot 'Test-Prerequisites.ps1') -Purpose $Purpose -AsJson | ConvertFrom-Json
$checks=[Collections.Generic.List[object]]::new()
foreach($check in $base.Checks){$checks.Add($check)}
$build=if($IsWindows){[Environment]::OSVersion.Version.Build}else{0}
$checks.Add(@{Name='Windows11 build>=22000';Passed=($IsWindows -and $build -ge 22000);Version=$build})
$bash=Join-Path $env:ProgramFiles 'Git/usr/bin/bash.exe'
$checks.Add(@{Name='Git for Windows Bash';Passed=(Test-Path -LiteralPath $bash -PathType Leaf)})
$desktop=Join-Path $env:ProgramFiles 'Docker/Docker/Docker Desktop.exe'
$checks.Add(@{Name='Docker Desktop';Passed=(Test-Path -LiteralPath $desktop -PathType Leaf)})
$server=Get-Service sshd -ErrorAction SilentlyContinue
$checks.Add(@{Name='OpenSSH server running';Passed=($null -ne $server -and $server.Status -eq 'Running')})
$providerStatus='UNTESTED'
if($IsWindows){
    if(-not ('DockerSshReadOnlyProvider' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
/// <summary>Opens and closes the PCP provider only; never enumerates, creates, or operates on a key.</summary>
public static class DockerSshReadOnlyProvider {
    /// <summary>Obtains a provider handle without touching persistent keys.</summary>
    [DllImport("ncrypt.dll", CharSet=CharSet.Unicode)]
    private static extern int NCryptOpenStorageProvider(out IntPtr handle, string name, int flags);
    /// <summary>Releases only the provider handle opened by this probe.</summary>
    [DllImport("ncrypt.dll")]
    private static extern int NCryptFreeObject(IntPtr handle);
    /// <summary>Returns the native open or close status; never exports key information.</summary>
    public static int Probe() {
        IntPtr handle;
        int status=NCryptOpenStorageProvider(out handle, "Microsoft Platform Crypto Provider", 0);
        if(status!=0) return status;
        return NCryptFreeObject(handle);
    }
}
'@
    }
    $providerStatus='0x{0:X8}' -f [DockerSshReadOnlyProvider]::Probe()
}
$checks.Add(@{Name='PCP provider open/close';Passed=($providerStatus -eq '0x00000000');HRESULT=$providerStatus})
$tpmState='UNKNOWN'
$tpmVersion='UNKNOWN'
try{
    $tpm=Get-CimInstance -Namespace root/cimv2/security/microsofttpm -ClassName Win32_Tpm -ErrorAction Stop
    $tpmVersion=([string]$tpm.SpecVersion -split ',')[0].Trim()
    $tpmState=if($tpm.IsEnabled_InitialValue -and $tpm.IsActivated_InitialValue){'ENABLED_ACTIVATED'}else{'NOT_READY'}
}catch{
    # Provider availability is independent of permission to read Win32_Tpm; never elevate to fill a metadata gap.
}
if($tpmState -eq 'NOT_READY'){$checks.Add(@{Name='TPM enabled/activated';Passed=$false})}
if($tpmVersion -ne 'UNKNOWN'){$checks.Add(@{Name='TPM2.0';Passed=($tpmVersion -eq '2.0');Version=$tpmVersion})}
[ordered]@{
    Purpose=$Purpose
    Ready=(@($checks | Where-Object{-not $_.Passed}).Count -eq 0)
    Checks=$checks.ToArray()
    TpmState=$tpmState
    TpmVersion=$tpmVersion
    KeyCreation='UNTESTED'
    ColdBoot='UNTESTED'
    OtherMachine='UNTESTED'
    PersistentChanges=0
}|ConvertTo-Json -Depth 6
