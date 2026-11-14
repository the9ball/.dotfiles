/// <summary>Normalize registry identities while keeping Docker Hub OAuth records distinct.</summary>
internal static class CredentialKey
{
    internal const string Hub = "https://index.docker.io/v1/";
    internal const string AccessToken = Hub + "access-token";
    internal const string RefreshToken = Hub + "refresh-token";

    /// <summary>Accept exact OAuth keys and documented registry aliases without interpreting secrets.</summary>
    internal static string Normalize(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Any(char.IsWhiteSpace) || value.Any(char.IsControl) || value.Contains('\\')) throw new InvalidDataException();
        // OAuth endpoints are opaque identities; URI normalization must not create additional aliases.
        if (string.Equals(value, AccessToken, StringComparison.Ordinal) || string.Equals(value, RefreshToken, StringComparison.Ordinal)) return value;
        var uri = new Uri(value.Contains("://", StringComparison.Ordinal) ? value : "https://" + value);
        if (uri.Scheme is not ("https" or "http") || uri.UserInfo != "" || uri.Query != "" || uri.Fragment != "" || uri.Host == "") throw new InvalidDataException();
        bool hub = uri.Host is "docker.io" or "index.docker.io" or "registry-1.docker.io";
        if (hub && uri.Scheme == "https" && uri.IsDefaultPort && uri.AbsolutePath is "/" or "/v1" or "/v1/") return Hub;
        if (uri.AbsolutePath != "/") throw new InvalidDataException();
        return uri.Scheme + "://" + uri.Authority.ToLowerInvariant();
    }
}
