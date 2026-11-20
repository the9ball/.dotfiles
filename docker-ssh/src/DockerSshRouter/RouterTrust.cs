using System.Security.AccessControl;
using System.Security.Principal;

/// <summary>Applies the deployment dispatcher's filesystem trust boundary to router installation data.</summary>
internal static class RouterTrust
{
    /// <summary>Rejects redirected paths, foreign leaf grants and replaceable ancestors before trusting code or metadata.</summary>
    internal static void AssertPath(string path, bool privateLeaf = true)
    {
        if (path.Length < 3 || !char.IsAsciiLetter(path[0]) || path[1] != ':' || path[2] is not ('/' or '\\'))
            throw new InvalidDataException();
        var owner = WindowsIdentity.GetCurrent().User!;
        var installer = (SecurityIdentifier)new NTAccount("NT SERVICE", "TrustedInstaller").Translate(typeof(SecurityIdentifier));
        var trusted = new HashSet<string> { owner.Value, "S-1-5-18", "S-1-5-32-544", installer.Value };
        var absolute = Path.GetFullPath(path);
        for (string? current = absolute; current is not null; current = Path.GetDirectoryName(current))
        {
            var attributes = File.GetAttributes(current);
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException();
            FileSystemSecurity security = (attributes & FileAttributes.Directory) != 0
                ? new DirectoryInfo(current).GetAccessControl() : new FileInfo(current).GetAccessControl();
            var descriptor = new RawSecurityDescriptor(security.GetSecurityDescriptorBinaryForm(), 0);
            if (descriptor.DiscretionaryAcl is null || descriptor.Owner is null || !trusted.Contains(descriptor.Owner.Value))
                throw new InvalidDataException();
            if (privateLeaf && current == absolute && descriptor.Owner != owner) throw new InvalidDataException();
            foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            {
                if (rule.AccessControlType != AccessControlType.Allow) continue;
                var sid = (SecurityIdentifier)rule.IdentityReference;
                if (privateLeaf && current == absolute && sid != owner) throw new InvalidDataException();
                var forbidden = FileSystemRights.Delete | FileSystemRights.DeleteSubdirectoriesAndFiles
                    | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
                if (!privateLeaf && current == absolute)
                    forbidden |= FileSystemRights.WriteData | FileSystemRights.AppendData
                        | FileSystemRights.WriteAttributes | FileSystemRights.WriteExtendedAttributes;
                if ((rule.PropagationFlags & PropagationFlags.InheritOnly) == 0
                    && !trusted.Contains(sid.Value) && (rule.FileSystemRights & forbidden) != 0)
                    throw new InvalidDataException();
            }
        }
    }
}
