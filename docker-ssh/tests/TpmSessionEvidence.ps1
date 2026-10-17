<# .SYNOPSIS Reads the current process logon metadata only; never reads credential material. #>
function Get-TpmSessionEvidence {
    <# .SYNOPSIS Returns SID, AuthenticationId, logon type and boot time for a same-boot SSH comparison. #>
    if (-not ('TpmFixtureLogon' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;
/// <summary>Queries only the current token's public authentication identifier.</summary>
public static class TpmFixtureLogon {
    /// <summary>Reads TOKEN_STATISTICS into a bounded local buffer.</summary>
    [DllImport("advapi32.dll", SetLastError=true)]
    private static extern bool GetTokenInformation(SafeAccessTokenHandle token, int informationClass, byte[] buffer, int length, out int returned);
    /// <summary>Returns the AuthenticationId LUID; never queries a credential or another user's token.</summary>
    public static string ReadAuthenticationId() {
        using var identity = WindowsIdentity.GetCurrent();
        byte[] buffer = new byte[256];
        if (!GetTokenInformation(identity.AccessToken, 10, buffer, buffer.Length, out int returned) || returned < 16 || returned > buffer.Length)
            throw new InvalidOperationException();
        return (((ulong)BitConverter.ToUInt32(buffer, 12) << 32) | BitConverter.ToUInt32(buffer, 8)).ToString();
    }
}
'@
    }
    $authenticationId = [TpmFixtureLogon]::ReadAuthenticationId()
    if ($authenticationId -notmatch '^\d+$') { throw 'Invalid authentication metadata.' }
    $session = Get-CimInstance Win32_LogonSession -Filter "LogonId='$authenticationId'"
    if ($null -eq $session.LogonType) { throw 'Logon type is unknown.' }
    [pscustomobject]@{
        UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        AuthenticationId = $authenticationId
        LogonType = [int]$session.LogonType
        BootUtc = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
        ProcessId = $PID
        ProcessSessionId = (Get-Process -Id $PID).SessionId
        ObservedUtc = [DateTime]::UtcNow.ToString('o')
    }
}
