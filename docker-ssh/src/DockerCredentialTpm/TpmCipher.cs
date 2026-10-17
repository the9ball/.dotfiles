using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

/// <summary>Public identity pinned when a dedicated store is initialized; contains no secret key material.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record TpmKeyBinding(string ProviderName, string KeyName, string UserSid, string UniqueNameSHA256, string PublicSpkiSHA256);

/// <summary>Versioned authenticated ciphertext; the random per-write AES key is wrapped by TPM RSA.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record Envelope(int Version, byte[] WrappedKey, byte[] Nonce, byte[] Tag, byte[] Ciphertext);

/// <summary>Validates the exact PoC key boundary on every operation and never creates or repairs keys.</summary>
internal sealed class TpmCipher : IDisposable
{
    private readonly CngKey key;
    private readonly byte[] associatedData;

    /// <summary>Retains one validated key and binds ciphertext to this user, store and public key.</summary>
    private TpmCipher(CngKey key, TpmKeyBinding binding, string storeId)
    {
        this.key = key;
        associatedData = JsonSerializer.SerializeToUtf8Bytes(new { Purpose = "DockerSshTpm/v1", binding.UserSid, StoreId = storeId, binding.PublicSpkiSHA256 });
    }

    /// <summary>Reads only bounded public provenance from an explicitly supplied path during initialization.</summary>
    internal static TpmKeyBinding ReadBinding()
    {
        string path = Environment.GetEnvironmentVariable("DOCKER_SSH_TPM_BINDING") ?? throw new InvalidDataException();
        if (!Path.IsPathFullyQualified(path) || new FileInfo(path).Length > 16384 || File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidDataException();
        byte[] bytes = File.ReadAllBytes(path);
        Program.RejectDuplicateProperties(bytes);
        return JsonSerializer.Deserialize<TpmKeyBinding>(bytes) ?? throw new InvalidDataException();
    }

    /// <summary>Opens only a pinned decrypt-only, nonexportable, silent machine key with an exact user-only DACL.</summary>
    internal static TpmCipher Open(TpmKeyBinding binding, string storeId)
    {
        var user = WindowsIdentity.GetCurrent().User!;
        bool dedicated = binding.KeyName.StartsWith("docker-ssh-tpm-", StringComparison.Ordinal) && Guid.TryParseExact(binding.KeyName["docker-ssh-tpm-".Length..], "N", out _);
        if (binding.ProviderName != "Microsoft Platform Crypto Provider" || binding.UserSid != user.Value ||
            !(dedicated || binding.KeyName.StartsWith("docker-ssh-issue142-poc-", StringComparison.Ordinal)) || !Guid.TryParseExact(storeId, "N", out _)) throw new InvalidDataException();
        var key = CngKey.Open(binding.KeyName, new CngProvider(binding.ProviderName), (CngKeyOpenOptions)0x60);
        try
        {
            if (key.Provider?.Provider != binding.ProviderName || !key.IsMachineKey || key.KeyName != binding.KeyName ||
                Number(key, "Length") != 2048 || Number(key, "Key Usage") != 1 || Number(key, "Export Policy") != 0 ||
                Number(key, "PCP_KEY_USAGE_POLICY") is not (2 or 0x10002)) throw new InvalidDataException();
            byte[] ui = Property(key, "UI Policy");
            if (ui.Length < 8 || BitConverter.ToInt32(ui) != 1 || BitConverter.ToInt32(ui, 4) != 0) throw new InvalidDataException();
            using var publicAlgorithm = new RSACng(key);
            if (Convert.ToHexString(SHA256.HashData(publicAlgorithm.ExportSubjectPublicKeyInfo())) != binding.PublicSpkiSHA256 ||
                Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key.UniqueName ?? throw new InvalidDataException()))) != binding.UniqueNameSHA256) throw new InvalidDataException();
            var descriptor = new RawSecurityDescriptor(Property(key, "Security Descr", 5), 0);
            if (!user.Equals((object?)descriptor.Owner) || !descriptor.ControlFlags.HasFlag(ControlFlags.DiscretionaryAclProtected) || descriptor.DiscretionaryAcl?.Count != 1 ||
                descriptor.DiscretionaryAcl[0] is not CommonAce grant || grant.AceQualifier != AceQualifier.AccessAllowed || grant.AceFlags != AceFlags.None ||
                !user.Equals(grant.SecurityIdentifier) || grant.AccessMask != 0x130089) throw new InvalidDataException();
            return new TpmCipher(key, binding, storeId);
        }
        catch { key.Dispose(); throw; }
    }

    /// <summary>Encrypts the complete record set with a fresh AES key and nonce on each atomic write.</summary>
    internal byte[] Encrypt(byte[] plaintext)
    {
        byte[] dataKey = RandomNumberGenerator.GetBytes(32);
        try
        {
            byte[] nonce = RandomNumberGenerator.GetBytes(12);
            byte[] ciphertext = new byte[plaintext.Length];
            byte[] tag = new byte[16];
            using var aes = new AesGcm(dataKey, 16);
            aes.Encrypt(nonce, plaintext, ciphertext, tag, associatedData);
            using var publicAlgorithm = new RSACng(key);
            using var softwarePublicKey = RSA.Create();
            softwarePublicKey.ImportParameters(publicAlgorithm.ExportParameters(false));
            return JsonSerializer.SerializeToUtf8Bytes(new Envelope(1, softwarePublicKey.Encrypt(dataKey, RSAEncryptionPadding.OaepSHA256), nonce, tag, ciphertext));
        }
        finally { CryptographicOperations.ZeroMemory(dataKey); }
    }

    /// <summary>Unwraps silently and authenticates all ciphertext before any credential parsing.</summary>
    internal byte[] Decrypt(byte[] bytes)
    {
        if (bytes.Length > 8 * 1024 * 1024) throw new InvalidDataException();
        Program.RejectDuplicateProperties(bytes);
        var envelope = JsonSerializer.Deserialize<Envelope>(bytes) ?? throw new InvalidDataException();
        if (envelope.Version != 1 || envelope.WrappedKey?.Length != 256 || envelope.Nonce?.Length != 12 || envelope.Tag?.Length != 16 || envelope.Ciphertext is null) throw new InvalidDataException();
        byte[] dataKey = new byte[256];
        byte[] plaintext = new byte[envelope.Ciphertext.Length];
        try
        {
            IntPtr algorithm = Marshal.StringToHGlobalUni("SHA256");
            try
            {
                var padding = new OaepPadding { Algorithm = algorithm };
                using var handle = key.Handle;
                Check(NCryptDecrypt(handle, envelope.WrappedKey, 256, ref padding, dataKey, dataKey.Length, out int length, 0x44));
                if (length != 32) throw new InvalidDataException();
            }
            finally { Marshal.FreeHGlobal(algorithm); }
            using var aes = new AesGcm(dataKey.AsSpan(0, 32), 16);
            aes.Decrypt(envelope.Nonce, envelope.Ciphertext, envelope.Tag, plaintext, associatedData);
            return plaintext;
        }
        catch { CryptographicOperations.ZeroMemory(plaintext); throw; }
        finally { CryptographicOperations.ZeroMemory(dataKey); }
    }

    /// <summary>Reads bounded native metadata without altering the key.</summary>
    private static byte[] Property(CngKey key, string name, int flags = 0)
    {
        using var handle = key.Handle;
        byte[] buffer = new byte[65536];
        Check(NCryptGetProperty(handle, name, buffer, buffer.Length, out int length, flags));
        if (length < 0 || length > buffer.Length) throw new InvalidDataException();
        return buffer[..length];
    }

    /// <summary>Requires one exact DWORD property.</summary>
    private static int Number(CngKey key, string name)
    {
        byte[] value = Property(key, name);
        if (value.Length != 4) throw new InvalidDataException();
        return BitConverter.ToInt32(value);
    }

    /// <summary>Fails closed on native errors; the caller emits only a generic diagnostic.</summary>
    private static void Check(int status) { if (status != 0) throw new CryptographicException(status); }

    /// <summary>Releases this operation's handle without deleting or changing the persistent key.</summary>
    public void Dispose() => key.Dispose();

    [StructLayout(LayoutKind.Sequential)]
    private struct OaepPadding { internal IntPtr Algorithm; internal IntPtr Label; internal int LabelLength; }

    /// <summary>Reads public key metadata on an existing handle.</summary>
    [DllImport("ncrypt.dll", CharSet = CharSet.Unicode)]
    private static extern int NCryptGetProperty(SafeNCryptHandle handle, string property, byte[] output, int length, out int resultLength, int flags);

    /// <summary>Unwraps only a dummy-store data key with explicit OAEP and silent flags.</summary>
    [DllImport("ncrypt.dll")]
    private static extern int NCryptDecrypt(SafeNCryptKeyHandle handle, byte[] input, int inputLength, ref OaepPadding padding, byte[] output, int outputLength, out int resultLength, int flags);
}
