/// <summary>Exercise the production key policy without loading the helper, credentials, or TPM.</summary>
internal static class Program
{
    private static int passed;

    /// <summary>Verify registry compatibility and exact, independent OAuth identities.</summary>
    private static int Main()
    {
        foreach (string alias in new[] { "docker.io", "index.docker.io", "registry-1.docker.io", "https://docker.io/", "https://index.docker.io/v1", "https://registry-1.docker.io/v1/", "https://INDEX.DOCKER.IO/", "https://index.docker.io:443/v1/" })
            Equal(CredentialKey.Hub, CredentialKey.Normalize(alias));
        foreach (string key in new[] { CredentialKey.Hub, CredentialKey.AccessToken, CredentialKey.RefreshToken })
        {
            Equal(key, CredentialKey.Normalize(key));
            Equal(key, CredentialKey.Normalize(CredentialKey.Normalize(key)));
        }
        Equal(3, new[] { CredentialKey.Hub, CredentialKey.AccessToken, CredentialKey.RefreshToken }.Select(CredentialKey.Normalize).Distinct(StringComparer.Ordinal).Count());
        Equal("https://ghcr.io", CredentialKey.Normalize("ghcr.io"));
        Equal("https://registry.example:5000", CredentialKey.Normalize("registry.example:5000"));
        Equal("http://registry.example", CredentialKey.Normalize("http://registry.example/"));
        Equal("https://docker.io:444", CredentialKey.Normalize("https://docker.io:444/"));
        foreach (string invalid in new[]
        {
            "", " ", "https://index.docker.io/v1/access-token\n", "https://index.docker.io/v1/refresh-token\0",
            "http://index.docker.io/v1/access-token", "https://docker.io/v1/access-token",
            "https://registry-1.docker.io/v1/refresh-token", "https://INDEX.DOCKER.IO/v1/access-token",
            "https://index.docker.io:443/v1/access-token", "https://index.docker.io:444/v1/refresh-token",
            "index.docker.io/v1/access-token", "https://index.docker.io/v1/access-token/",
            "https://index.docker.io/v1/refresh-token?scope=x", "https://index.docker.io/v1/access-token#x",
            "https://user@index.docker.io/v1/access-token", "https://index.docker.io/v1/access%2Dtoken",
            "https://index.docker.io/v1/../v1/access-token", "https://index.docker.io/v1/ACCESS-TOKEN",
            "https://example.invalid/v1/access-token", "https://index.docker.io\\v1\\refresh-token",
            "https://index.docker.io/v1/other", "https://registry.example/path", "ftp://registry.example/"
        }) Reject(invalid);
        Console.WriteLine($"OAuth key policy: passed={passed}; failed=0; TPM/credential operations=0");
        return 0;
    }

    /// <summary>Compare expected policy output without writing input or secret-bearing values.</summary>
    private static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new InvalidOperationException("Key policy assertion failed.");
        passed++;
    }

    /// <summary>Require malformed or unapproved key identities to fail closed.</summary>
    private static void Reject(string value)
    {
        try { CredentialKey.Normalize(value); }
        catch (Exception exception) when (exception is InvalidDataException or UriFormatException)
        {
            passed++;
            return;
        }
        throw new InvalidOperationException("Unapproved key identity accepted.");
    }
}
