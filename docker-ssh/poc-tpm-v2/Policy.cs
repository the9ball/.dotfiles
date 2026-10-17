using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;

/// <summary>Separates the generic and provider-specific usage namespaces before key finalization.</summary>
internal static class EncryptionPolicy
{
    internal const int GenericDecrypt = 1;
    internal const int PcpEncryption = 2;
    internal const int ProviderCompatibilityBit = 0x10000;
    internal const int MappedUserReadAndDelete = 0x130089;

    /// <summary>Configures an unfinalized new key; the caller must have separate creation approval.</summary>
    internal static void Configure(IPropertyWriter writer)
    {
        writer.WriteNumber("Length", 2048);
        writer.WriteNumber("Export Policy", 0);
        writer.WriteNumber("Key Usage", GenericDecrypt);
        writer.WriteNumber("PCP_KEY_USAGE_POLICY", PcpEncryption);
        writer.WriteNoUiPolicy();
    }

    /// <summary>Rejects extra signing/agreement/export/UI policy and unknown PCP flags.</summary>
    internal static bool Accepts(int genericUsage, int pcpUsage, int exportPolicy, int uiFlags) =>
        genericUsage == GenericDecrypt && (pcpUsage & ~ProviderCompatibilityBit) == PcpEncryption && exportPolicy == 0 && uiFlags == 0;

    /// <summary>Builds a protected user-only key descriptor with read/use and cleanup rights; no explicit SYSTEM grant.</summary>
    internal static byte[] UserDescriptor(SecurityIdentifier user)
    {
        var descriptor = new RawSecurityDescriptor($"O:{user.Value}D:P(A;;GRSD;;;{user.Value})");
        var bytes = new byte[descriptor.BinaryLength];
        descriptor.GetBinaryForm(bytes, 0);
        return bytes;
    }

    /// <summary>Accepts only the intended owner and one exact mapped user ACE; missing DACL or extra principals fail closed.</summary>
    internal static bool AcceptsDescriptor(byte[] bytes, SecurityIdentifier user)
    {
        var descriptor = new RawSecurityDescriptor(bytes, 0);
        return descriptor.Owner == user && descriptor.ControlFlags.HasFlag(ControlFlags.DiscretionaryAclProtected) &&
            descriptor.DiscretionaryAcl?.Count == 1 && descriptor.DiscretionaryAcl[0] is CommonAce ace &&
            ace.SecurityIdentifier == user && ace.AceQualifier == AceQualifier.AccessAllowed && ace.AceFlags == AceFlags.None &&
            ace.AccessMask == MappedUserReadAndDelete;
    }
}

internal interface IPropertyWriter
{
    /// <summary>Writes one DWORD creation property before finalization.</summary>
    void WriteNumber(string property, int value);
    /// <summary>Requests version1 UI policy with no protected-UI flags.</summary>
    void WriteNoUiPolicy();
}

/// <summary>Native policy writer for an explicitly selected caller-owned creation handle.</summary>
internal sealed class NativePropertyWriter(SafeNCryptKeyHandle key, Func<bool>? stopRequested = null) : IPropertyWriter
{
    /// <summary>Sets one named property on the caller-owned unfinalized handle; never finalizes or creates a key.</summary>
    public void WriteNumber(string property, int value) => Set(property, BitConverter.GetBytes(value));

    /// <summary>Passes a correctly aligned native NCRYPT_UI_POLICY with no authentication prompt request.</summary>
    public void WriteNoUiPolicy()
    {
        var bytes = new byte[IntPtr.Size == 8 ? 32 : 20];
        BitConverter.GetBytes(1).CopyTo(bytes, 0);
        Set("UI Policy", bytes);
    }

    /// <summary>Checks the native status and stops immediately on an unsupported property.</summary>
    private void Set(string property, byte[] bytes)
    {
        if (stopRequested?.Invoke() == true) throw new OperationCanceledException();
        var status = NCryptSetProperty(key, property, bytes, bytes.Length, 0);
        if (status != 0) throw new CryptographicException(status);
    }

    /// <summary>Writes only a caller-selected key property; no create/open/delete operation is exposed here.</summary>
    [DllImport("ncrypt.dll", CharSet = CharSet.Unicode)]
    private static extern int NCryptSetProperty(SafeNCryptKeyHandle key, string property, byte[] input, int length, int flags);
}
