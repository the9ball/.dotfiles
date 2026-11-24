/// <summary>Filesystem-only fixture boundary; production ACL enforcement is intentionally not linked into this harness.</summary>
internal static class RouterTrust
{
    /// <summary>Rejects missing or redirected fixture paths without reading or changing any ACL.</summary>
    internal static void AssertPath(string path, bool privateLeaf = true)
    {
        if (!Path.IsPathFullyQualified(path) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException();
    }
}
