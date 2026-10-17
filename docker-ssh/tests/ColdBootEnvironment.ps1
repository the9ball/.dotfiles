<# .SYNOPSIS Reads current WTS user-session presence without changing sessions, audit policy or credentials. #>
function Get-TpmGuiSessionCount {
    <# .SYNOPSIS Returns the observed count of user-bearing sessions outside session zero; throws if enumeration is unknown. #>
    if (-not ('TpmGuiSessions' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
/// <summary>Queries only current terminal-session metadata, never a password or token.</summary>
public static class TpmGuiSessions {
    [StructLayout(LayoutKind.Sequential)]
    private struct Session { public int Id; public IntPtr Station; public int State; }
    /// <summary>Enumerates the current server's terminal sessions.</summary>
    [DllImport("wtsapi32.dll", EntryPoint="WTSEnumerateSessionsW", SetLastError=true)]
    private static extern bool Enumerate(IntPtr server, int reserved, int version, out IntPtr sessions, out int count);
    /// <summary>Queries only the public username field for one terminal session.</summary>
    [DllImport("wtsapi32.dll", EntryPoint="WTSQuerySessionInformationW", SetLastError=true)]
    private static extern bool Query(IntPtr server, int session, int information, out IntPtr value, out int bytes);
    /// <summary>Releases only an API-owned metadata allocation.</summary>
    [DllImport("wtsapi32.dll", EntryPoint="WTSFreeMemory")]
    private static extern void Free(IntPtr value);
    /// <summary>Counts current GUI-user sessions; this does not prove absence of earlier GUI logons.</summary>
    public static int Count() {
        if (!Enumerate(IntPtr.Zero, 0, 1, out IntPtr sessions, out int count)) throw new InvalidOperationException();
        try {
            if (count < 0 || count > 1024) throw new InvalidOperationException();
            int users = 0;
            for (int index = 0; index < count; index++) {
                var session = Marshal.PtrToStructure<Session>(IntPtr.Add(sessions, index * Marshal.SizeOf<Session>()));
                if (session.Id == 0) continue;
                if (!Query(IntPtr.Zero, session.Id, 5, out IntPtr value, out int bytes)) throw new InvalidOperationException();
                try {
                    if (bytes < 0 || bytes > 65536) throw new InvalidOperationException();
                    if (bytes > 2 && !string.IsNullOrEmpty(Marshal.PtrToStringUni(value))) users++;
                } finally { if (value != IntPtr.Zero) Free(value); }
            }
            return users;
        } finally { if (sessions != IntPtr.Zero) Free(sessions); }
    }
}

'@
    }
    [TpmGuiSessions]::Count()
}

function New-TpmBootStopEvent {
    <# .SYNOPSIS Creates a transient user-only stop event, verifies its exact DACL, and rejects name collisions. #>
    param([Parameter(Mandatory)][string] $FixtureId)
    if ($FixtureId -notmatch '^[a-f0-9]{32}$') { throw 'Invalid stop event identity.' }
    if (-not ('TpmBootStop' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;
/// <summary>A stop-only IPC object; it neither stores secrets nor grants access to a TPM key.</summary>
public static class TpmBootStop {
    [StructLayout(LayoutKind.Sequential)]
    private struct Attributes { public int Length; public IntPtr Descriptor; public int Inherit; }
    /// <summary>Builds a protected user-only kernel object descriptor.</summary>
    [DllImport("advapi32.dll", EntryPoint="ConvertStringSecurityDescriptorToSecurityDescriptorW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern bool ConvertDescriptor(string text, int revision, out IntPtr descriptor, out int length);
    /// <summary>Creates a manual-reset event with explicit minimum modify/synchronize/read-control rights.</summary>
    [DllImport("kernel32.dll", EntryPoint="CreateEventExW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern SafeWaitHandle CreateEvent(ref Attributes attributes, string name, int flags, int access);
    /// <summary>Reads owner and DACL of the just-created event.</summary>
    [DllImport("advapi32.dll", SetLastError=true)]
    private static extern bool GetKernelObjectSecurity(SafeWaitHandle handle, int information, byte[] descriptor, int length, out int returned);
    /// <summary>Signals only an already-owned stop event.</summary>
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool SetEvent(SafeWaitHandle handle);
    /// <summary>Releases only the descriptor buffer allocated by the conversion API.</summary>
    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr buffer);
    /// <summary>Creates and validates one user-owned event; a pre-existing event is signaled and rejected.</summary>
    public static SafeWaitHandle Create(string fixtureId) {
        var user = WindowsIdentity.GetCurrent().User;
        if (!ConvertDescriptor("O:" + user.Value + "D:P(A;;0x00120002;;;" + user.Value + ")", 1, out IntPtr descriptor, out int length)) throw new InvalidOperationException();
        try {
            var attributes = new Attributes { Length=Marshal.SizeOf<Attributes>(), Descriptor=descriptor, Inherit=0 };
            var handle = CreateEvent(ref attributes, "Local\\DockerSshIssue142BootStop-" + fixtureId, 1, 0x120002);
            int status = Marshal.GetLastWin32Error();
            if (handle.IsInvalid) { handle.Dispose(); throw new InvalidOperationException(); }
            try {
                if (status == 183) { Signal(handle); throw new InvalidOperationException(); }
                byte[] bytes = new byte[65536];
                if (!GetKernelObjectSecurity(handle, 5, bytes, bytes.Length, out int returned) || returned <= 0 || returned > bytes.Length) throw new InvalidOperationException();
                var security = new RawSecurityDescriptor(bytes, 0);
                if (security.Owner != user || !security.ControlFlags.HasFlag(ControlFlags.DiscretionaryAclProtected) || security.DiscretionaryAcl == null || security.DiscretionaryAcl.Count != 1 ||
                    !(security.DiscretionaryAcl[0] is CommonAce grant) || grant.SecurityIdentifier != user || grant.AceQualifier != AceQualifier.AccessAllowed || grant.AceFlags != AceFlags.None || grant.AccessMask != 0x120002)
                    throw new InvalidOperationException();
                return handle;
            } catch { handle.Dispose(); throw; }
        } finally { LocalFree(descriptor); }
    }
    /// <summary>Signals the stop event before attempting any fallible disk log or marker write.</summary>
    public static void Signal(SafeWaitHandle handle) { if (!SetEvent(handle)) throw new InvalidOperationException(); }
}
'@
    }
    [TpmBootStop]::Create($FixtureId)
}
