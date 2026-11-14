using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text.Json;

/// <summary>Guards native Docker calls before handing them to the shared deployment launcher.</summary>
internal static class Program
{
    /// <summary>Validates trusted launcher bytes and inherits all standard streams and argument boundaries.</summary>
    private static int Main(string[] arguments)
    {
        try
        {
            var binary = Path.TrimEndingDirectorySeparator(AppContext.BaseDirectory);
            if (Path.GetFileName(binary) != "0.5.0" || Path.GetFileName(Path.GetDirectoryName(binary)) != "bin")
                throw new InvalidDataException();
            var root = Path.GetDirectoryName(Path.GetDirectoryName(binary))!;
            var manifestPath = Path.Combine(root, "installed-manifest.json");
            AssertPath(root, true);
            AssertPath(manifestPath, true);
            using var manifest = JsonDocument.Parse(File.ReadAllBytes(manifestPath));
            var expected = new[] { "docker-credential-ssh-tpm.exe", "docker-credential-ssh-tpm.dll", "docker-credential-ssh-tpm.deps.json", "docker-credential-ssh-tpm.runtimeconfig.json",
                "docker.exe", "docker.dll", "docker.deps.json", "docker.runtimeconfig.json", "shell/Get-TpmDockerEnvironment.ps1", "shell/Invoke-DockerSshTpm.ps1" };
            if (manifest.RootElement.EnumerateObject().Count() != expected.Length) throw new InvalidDataException();
            foreach (var name in expected)
            {
                var file = Path.Combine(name.StartsWith("shell/", StringComparison.Ordinal) ? root : binary, name);
                AssertPath(file, true);
                var hash = manifest.RootElement.GetProperty(name).GetString();
                if (hash is null || hash.Length != 64 || Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))) != hash)
                    throw new InvalidDataException();
            }
            // The installer pins the physical runtime; an inherited PATH or environment cannot select executable code.
            var settingsPath = Path.Combine(root, "settings.json");
            AssertPath(settingsPath, true);
            using var settings = JsonDocument.Parse(File.ReadAllBytes(settingsPath));
            var powershell = settings.RootElement.GetProperty("PowerShellExecutable").GetString()!;
            if (!Path.IsPathFullyQualified(powershell) || !Path.GetFileName(powershell).Equals("pwsh.exe", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException();
            AssertPath(powershell, false);
            var start = new ProcessStartInfo(powershell) { UseShellExecute = false };
            foreach (var argument in new[] { "-NoProfile", "-File", Path.Combine(root, "shell", "Invoke-DockerSshTpm.ps1"), "-DeploymentRoot", root })
                start.ArgumentList.Add(argument);
            start.ArgumentList.Add("-RequireReady");
            start.ArgumentList.Add("-DockerArgumentsBase64");
            start.ArgumentList.Add(Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(arguments)));
            using var process = Process.Start(start) ?? throw new InvalidOperationException();
            process.WaitForExit();
            return process.ExitCode;
        }
        catch
        {
            Console.Error.WriteLine("Docker SSH dispatcher validation failed; no fallback was attempted.");
            return 1;
        }
    }

    /// <summary>Rejects reparse paths, unsafe leaf grants and ancestors replaceable by untrusted principals.</summary>
    private static void AssertPath(string path, bool privateLeaf)
    {
        if (path.Length < 3 || !char.IsAsciiLetter(path[0]) || path[1] != ':' || (path[2] != Path.DirectorySeparatorChar && path[2] != Path.AltDirectorySeparatorChar)) throw new InvalidDataException();
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
            if (descriptor.DiscretionaryAcl is null || descriptor.Owner is null || !trusted.Contains(descriptor.Owner.Value)) throw new InvalidDataException();
            if (privateLeaf && current == absolute && descriptor.Owner != owner) throw new InvalidDataException();
            foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            {
                if (rule.AccessControlType != AccessControlType.Allow) continue;
                var sid = (SecurityIdentifier)rule.IdentityReference;
                if (privateLeaf && current == absolute && sid != owner) throw new InvalidDataException();
                var forbidden = FileSystemRights.Delete | FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
                if (current == absolute && !privateLeaf) forbidden |= FileSystemRights.WriteData | FileSystemRights.AppendData | FileSystemRights.WriteAttributes | FileSystemRights.WriteExtendedAttributes;
                if ((rule.PropagationFlags & PropagationFlags.InheritOnly) == 0 && !trusted.Contains(sid.Value) && (rule.FileSystemRights & forbidden) != 0)
                    throw new InvalidDataException();
            }
        }
    }
}
