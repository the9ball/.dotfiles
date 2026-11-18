using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

/// <summary>Run the production helper protocol against new dummy fixtures with no TPM implementation linked.</summary>
internal static class ProtocolChecks
{
    private static int passed;
    private static string store = "";

    /// <summary>Execute a child protocol request or a bounded suite in a new user-only fixture.</summary>
    private static int Main(string[] arguments)
    {
        if (arguments.Length > 0 && arguments[0] == "--helper") return Program.Main(arguments[1..]);
        if (arguments.Length != 1) throw new InvalidDataException();
        string root = Path.GetFullPath(arguments[0]);
        string parent = Path.GetFullPath(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
        if (!string.Equals(Path.GetDirectoryName(root), parent, StringComparison.OrdinalIgnoreCase) || !Path.GetFileName(root).StartsWith("docker-ssh-issue185-protocol-", StringComparison.Ordinal) || Directory.Exists(root) || File.Exists(root)) throw new InvalidDataException();
        var owner = WindowsIdentity.GetCurrent().User!;
        var security = new DirectorySecurity();
        security.SetOwner(owner);
        security.SetAccessRuleProtection(true, false);
        security.AddAccessRule(new FileSystemAccessRule(owner, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        FileSystemAclExtensions.CreateDirectory(security, root);
        store = Path.Combine(root, "store");
        try
        {
            Check(Run("init").Code == 0);
            foreach (string key in new[] { CredentialKey.Hub, CredentialKey.AccessToken, CredentialKey.RefreshToken })
                Check(Run("store", JsonSerializer.Serialize(new { ServerURL = key, Username = "dummy-user", Secret = "dummy-" + key.Split('/')[^1] })).Code == 0);
            Check(Get(CredentialKey.Hub) == "dummy-");
            Check(Get(CredentialKey.AccessToken) == "dummy-access-token");
            Check(Get(CredentialKey.RefreshToken) == "dummy-refresh-token");
            Check(Run("store", JsonSerializer.Serialize(new { ServerURL = CredentialKey.AccessToken, Username = "dummy-user", Secret = "dummy-updated" })).Code == 0);
            Check(Get(CredentialKey.AccessToken) == "dummy-updated");
            Check(Get(CredentialKey.RefreshToken) == "dummy-refresh-token");
            Check(Get(CredentialKey.Hub) == "dummy-");
            string list = Run("list").Output;
            using (var listed = JsonDocument.Parse(list)) Check(listed.RootElement.EnumerateObject().Count() == 3);
            byte[] before = SHA256.HashData(File.ReadAllBytes(Path.Combine(store, "vault.tpm")));
            Check(Run("store", "{\"ServerURL\":\"https://index.docker.io/v1/access-token\",\"Username\":\"dummy\",\"Secret\":\"a\",\"Secret\":\"b\"}").Code != 0);
            Check(before.SequenceEqual(SHA256.HashData(File.ReadAllBytes(Path.Combine(store, "vault.tpm")))));
            Check(Run("erase", CredentialKey.Hub).Code == 0);
            Check(Get(CredentialKey.RefreshToken) == "dummy-refresh-token");
            Check(Get(CredentialKey.AccessToken) == "dummy-updated");
            Check(Run("erase", CredentialKey.AccessToken).Code == 0);
            var missing = Run("get", CredentialKey.AccessToken);
            Check(missing.Code == 1 && missing.Output.Trim() == "credentials not found in native keychain");
            Check(Run("erase", CredentialKey.AccessToken).Code == 0);
            Check(Get(CredentialKey.RefreshToken) == "dummy-refresh-token");
            Check(Run("erase", CredentialKey.RefreshToken).Code == 0);
            using (var empty = JsonDocument.Parse(Run("list").Output)) Check(!empty.RootElement.EnumerateObject().Any());
            File.WriteAllBytes(Path.Combine(store, "vault.tpm"), [1, 2, 3]);
            Check(Run("store", JsonSerializer.Serialize(new { ServerURL = CredentialKey.Hub, Username = "dummy-user", Secret = "dummy" })).Code != 0);
            Check(File.ReadAllBytes(Path.Combine(store, "vault.tpm")).SequenceEqual(new byte[] { 1, 2, 3 }));
            Console.WriteLine($"Production helper dummy protocol: passed={passed}; failed=0; TPM calls=0; real credentials=0");
            return 0;
        }
        finally
        {
            // Only this newly claimed, validated user-only fixture is eligible for recursive cleanup.
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    /// <summary>Launch the linked production protocol in a bounded child with only dummy input captured.</summary>
    private static (int Code, string Output) Run(string command, string input = "")
    {
        var start = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true };
        if (string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath), "dotnet", StringComparison.OrdinalIgnoreCase)) start.ArgumentList.Add(typeof(ProtocolChecks).Assembly.Location);
        start.ArgumentList.Add("--helper");
        start.ArgumentList.Add(command);
        start.Environment["DOCKER_SSH_HELPER_ROOT"] = store;
        var process = Process.Start(start) ?? throw new InvalidOperationException();
        using (process)
        {
            var output = process.StandardOutput.ReadToEndAsync();
            var errors = process.StandardError.ReadToEndAsync();
            process.StandardInput.Write(input);
            process.StandardInput.Close();
            if (!process.WaitForExit(30000))
            {
                process.Kill(true);
                process.WaitForExit();
                throw new TimeoutException("Dummy child timed out.");
            }
            _ = errors.GetAwaiter().GetResult();
            return (process.ExitCode, output.GetAwaiter().GetResult());
        }
    }

    /// <summary>Read a dummy secret for an in-memory comparison without printing its value.</summary>
    private static string Get(string key)
    {
        var result = Run("get", key);
        Check(result.Code == 0);
        using var document = JsonDocument.Parse(result.Output);
        return document.RootElement.GetProperty("Secret").GetString()!;
    }

    /// <summary>Record a public assertion without including request payloads in diagnostics.</summary>
    private static void Check(bool condition)
    {
        if (!condition) throw new InvalidOperationException($"Dummy protocol assertion {passed + 1} failed.");
        passed++;
    }
}
