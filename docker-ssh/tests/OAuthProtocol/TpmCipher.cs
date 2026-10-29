using System.Security.Cryptography;

/// <summary>Nonsecret test binding used only by this separately compiled protocol harness.</summary>
internal sealed record TpmKeyBinding(string ProviderName, string KeyName, string UserSid, string UniqueNameSHA256, string PublicSpkiSHA256);

/// <summary>Encrypt dummy fixtures in software; this harness never compiles or invokes the TPM implementation.</summary>
internal sealed class TpmCipher : IDisposable
{
    private static readonly byte[] DummyKey = SHA256.HashData("Issue185 protocol dummy data only"u8);

    /// <summary>Supply a synthetic binding without inspecting any operating-system key.</summary>
    internal static TpmKeyBinding ReadBinding() => new("inert", "inert", "inert", "00", "00");

    /// <summary>Require the synthetic binding before allowing fixture encryption.</summary>
    internal static TpmCipher Open(TpmKeyBinding binding, string storeId)
    {
        if (binding != ReadBinding() || !Guid.TryParseExact(storeId, "N", out _)) throw new InvalidDataException();
        return new();
    }

    /// <summary>Encrypt only fixed dummy protocol data with a test-only software key.</summary>
    internal byte[] Encrypt(byte[] plaintext)
    {
        byte[] result = new byte[28 + plaintext.Length];
        RandomNumberGenerator.Fill(result.AsSpan(0, 12));
        using var cipher = new AesGcm(DummyKey, 16);
        cipher.Encrypt(result.AsSpan(0, 12), plaintext, result.AsSpan(28), result.AsSpan(12, 16));
        return result;
    }

    /// <summary>Detect fixture corruption without opening or using a TPM key.</summary>
    internal byte[] Decrypt(byte[] bytes)
    {
        if (bytes.Length < 28) throw new InvalidDataException();
        byte[] plaintext = new byte[bytes.Length - 28];
        using var cipher = new AesGcm(DummyKey, 16);
        cipher.Decrypt(bytes.AsSpan(0, 12), bytes.AsSpan(28), bytes.AsSpan(12, 16), plaintext);
        return plaintext;
    }

    /// <summary>Release no native resources because the inert cipher owns none.</summary>
    public void Dispose() { }
}
