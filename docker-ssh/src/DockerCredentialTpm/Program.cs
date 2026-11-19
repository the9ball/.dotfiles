using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

/// <summary>A Docker protocol record; plaintext exists only in process memory and protocol pipes.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record Credential(string ServerURL, string Username, string Secret);
/// <summary>Nonsecret identity for one explicitly initialized store.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record Settings(int Version, string Kind, string Owner, string StoreId, TpmKeyBinding Binding);

/// <summary>TPM-wrapped encrypted credential storage for a dedicated Docker configuration.</summary>
internal static class Program
{
    private const int InputLimit = 1024 * 1024;
    private const int FileLimit = 8 * 1024 * 1024;
    private static readonly SecurityIdentifier Owner = WindowsIdentity.GetCurrent().User!;
    private static readonly SecurityIdentifier SystemSid = new(WellKnownSidType.LocalSystemSid, null);
    private static readonly SecurityIdentifier Administrators = new(WellKnownSidType.BuiltinAdministratorsSid, null);
    private static readonly SecurityIdentifier Installer = (SecurityIdentifier)new NTAccount("NT SERVICE", "TrustedInstaller").Translate(typeof(SecurityIdentifier));
    private static string Root = "";

    /// <summary>Execute one request without including input or exception details in diagnostics.</summary>
    public static int Main(string[] arguments)
    {
        try
        {
            if (arguments.SequenceEqual(new[] { "--self-test" })) return AclChecks.Run();
            Console.InputEncoding = new UTF8Encoding(false, true);
            Console.OutputEncoding = new UTF8Encoding(false, true);
            string configuredRoot = Environment.GetEnvironmentVariable("DOCKER_SSH_HELPER_ROOT") ?? throw new InvalidDataException();
            if (!Path.IsPathFullyQualified(configuredRoot)) throw new InvalidDataException();
            Root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(configuredRoot));
            string original = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".docker");
            if (Root.Equals(original, StringComparison.OrdinalIgnoreCase) || Root.StartsWith(original + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException();
            CheckAncestors(Root, arguments.Length == 1 && arguments[0] is "init" or "validate-path");
            if (arguments.Length != 1) throw new InvalidDataException();
            if (arguments[0] == "validate-path") return 0;
            if (arguments[0] == "init")
            {
                if (Directory.Exists(Root) || File.Exists(Root)) throw new InvalidDataException();
                var initializedSettings = new Settings(1, "DockerSshTpm", Owner.Value, Guid.NewGuid().ToString("N"), TpmCipher.ReadBinding());
                using var initializedCipher = TpmCipher.Open(initializedSettings.Binding, initializedSettings.StoreId);
                CreatePrivateDirectory(Root);
                CheckAncestors(Root);
                // CreateDirectory is idempotent; a persistent exclusive claim closes concurrent-init races.
                using var initializationClaim = new FileStream(Path.Combine(Root, "initialization.claim"), FileMode.CreateNew, FileAccess.Write, FileShare.None);
                using var initializationLock = Lock();
                Atomic("settings.json", JsonSerializer.SerializeToUtf8Bytes(initializedSettings));
                Save(new(), initializedCipher);
                return 0;
            }
            if (arguments[0] is not ("store" or "get" or "erase" or "list")) throw new InvalidDataException();
            VerifySecurity(new DirectoryInfo(Root).GetAccessControl());
            using var operationLock = Lock();
            VerifyTree(Root);
            byte[] settingsBytes = ReadBounded("settings.json");
            RejectDuplicateProperties(settingsBytes);
            var settings = JsonSerializer.Deserialize<Settings>(settingsBytes) ?? throw new InvalidDataException();
            if (settings.Version != 1 || settings.Kind != "DockerSshTpm" || settings.Owner != Owner.Value || !Guid.TryParseExact(settings.StoreId, "N", out _)) throw new InvalidDataException();
            using var operationCipher = TpmCipher.Open(settings.Binding, settings.StoreId);
            string input = arguments[0] == "list" ? "" : ReadInput();
            Credential? submitted = null;
            if (arguments[0] == "store")
            {
                byte[] inputBytes = Encoding.UTF8.GetBytes(input);
                try { RejectDuplicateProperties(inputBytes); submitted = JsonSerializer.Deserialize<Credential>(inputBytes) ?? throw new InvalidDataException(); }
                finally { CryptographicOperations.ZeroMemory(inputBytes); }
            }
            string key = arguments[0] == "list" ? "" : Canonical(submitted?.ServerURL ?? input.TrimEnd('\r', '\n'));
            if (submitted != null) ValidateCredential(submitted with { ServerURL = key });
            var credentials = Load(operationCipher);
            switch (arguments[0])
            {
                case "store": credentials[key] = submitted! with { ServerURL = key }; Save(credentials, operationCipher); break;
                case "erase": if (credentials.Remove(key)) Save(credentials, operationCipher); break;
                case "list": Console.WriteLine(JsonSerializer.Serialize(credentials.ToDictionary(pair => pair.Key, pair => pair.Value.Username))); break;
                case "get": if (!credentials.TryGetValue(key, out var found)) throw new KeyNotFoundException(); Console.WriteLine(JsonSerializer.Serialize(found)); break;
            }
            return 0;
        }
        catch (KeyNotFoundException) { Console.WriteLine("credentials not found in native keychain"); return 1; }
        catch (Exception exception) { Console.WriteLine($"credential helper failed; HRESULT=0x{exception.HResult:X8}; inspect store integrity, permissions and configuration"); return 1; }
    }

    /// <summary>Reject reparse points and replaceable ancestors; user, SYSTEM, administrators and TrustedInstaller are trusted.</summary>
    private static void CheckAncestors(string path, bool initializing = false)
    {
        bool firstExisting = true;
        for (string? current = path; current != null; current = Path.GetDirectoryName(current))
        {
            if (!Directory.Exists(current))
            {
                if (File.Exists(current)) throw new InvalidDataException();
                continue;
            }
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException();
            var security = new DirectoryInfo(current).GetAccessControl();
            RequireDacl(security.GetSecurityDescriptorBinaryForm());
            if (!TrustedAncestorPrincipal(security.GetOwner(typeof(SecurityIdentifier)))) throw new InvalidDataException();
            var forbidden = FileSystemRights.Delete | FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
            // The nearest existing parent must also exclude a competing creator of a new store path.
            if (initializing && firstExisting) forbidden |= FileSystemRights.CreateDirectories | FileSystemRights.CreateFiles;
            foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                if (rule.AccessControlType == AccessControlType.Allow && (rule.PropagationFlags & PropagationFlags.InheritOnly) == 0 && !TrustedAncestorPrincipal(rule.IdentityReference) && (rule.FileSystemRights & forbidden) != 0) throw new InvalidDataException();
            firstExisting = false;
        }
    }

    /// <summary>Identify OS administration principals excluded from the cross-user filesystem threat boundary.</summary>
    private static bool TrustedAncestorPrincipal(IdentityReference? principal) => Owner.Equals(principal) || SystemSid.Equals(principal) || Administrators.Equals(principal) || Installer.Equals(principal);

    /// <summary>Secure a newly created leaf before any credential-bearing write.</summary>
    private static void CreatePrivateDirectory(string path)
    {
        var security = new DirectorySecurity();
        security.SetOwner(Owner);
        security.SetAccessRuleProtection(true, false);
        foreach (var principal in new[] { Owner })
            security.AddAccessRule(new FileSystemAccessRule(principal, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        FileSystemAclExtensions.CreateDirectory(security, path);
    }

    /// <summary>Validate owner and all grants on the store, persistent lock and temporary files.</summary>
    private static void VerifyTree(string path)
    {
        CheckAncestors(path);
        var directory = new DirectoryInfo(path);
        VerifySecurity(directory.GetAccessControl());
        foreach (var entry in directory.EnumerateFileSystemInfos())
        {
            if ((entry.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException();
            if (entry is DirectoryInfo child) VerifyTree(child.FullName);
            else VerifySecurity(((FileInfo)entry).GetAccessControl());
        }
    }

    /// <summary>Allow only this user; same-user malicious processes are outside this boundary.</summary>
    internal static void VerifySecurity(FileSystemSecurity security)
    {
        RequireDacl(security.GetSecurityDescriptorBinaryForm());
        if (!Owner.Equals(security.GetOwner(typeof(SecurityIdentifier)))) throw new InvalidDataException();
        foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            if (rule.AccessControlType == AccessControlType.Allow && !rule.IdentityReference.Equals(Owner)) throw new InvalidDataException();
    }

    /// <summary>Reject an absent or null DACL explicitly; an empty DACL is a different, deny-all state.</summary>
    internal static void RequireDacl(byte[] descriptorBytes)
    {
        var descriptor = new RawSecurityDescriptor(descriptorBytes, 0);
        if (!descriptor.ControlFlags.HasFlag(ControlFlags.DiscretionaryAclPresent) || descriptor.DiscretionaryAcl is null) throw new InvalidDataException();
    }

    /// <summary>Hold an exclusive persistent file handle across the entire read-modify-write transaction.</summary>
    private static FileStream Lock()
    {
        var clock = Stopwatch.StartNew();
        while (true)
        {
            try { return new FileStream(Path.Combine(Root, "store.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) when (clock.Elapsed < TimeSpan.FromSeconds(45)) { Thread.Sleep(40); }
        }
    }

    /// <summary>Limit the protocol request before deserialization; callers must close stdin.</summary>
    private static string ReadInput()
    {
        var builder = new StringBuilder();
        while (true)
        {
            int character = Console.In.Read();
            if (character < 0) return builder.ToString();
            if (builder.Length >= InputLimit) throw new InvalidDataException();
            builder.Append((char)character);
        }
    }

    /// <summary>Read a committed file with a size bound; missing files are never reinitialized.</summary>
    private static byte[] ReadBounded(string name)
    {
        string path = Path.Combine(Root, name);
        if (new FileInfo(path).Length > FileLimit) throw new InvalidDataException();
        return File.ReadAllBytes(path);
    }

    /// <summary>Flush ciphertext or nonsecret identity metadata before same-directory replacement.</summary>
    private static void Atomic(string name, byte[] bytes)
    {
        if (bytes.Length > FileLimit) throw new InvalidDataException();
        string destination = Path.Combine(Root, name);
        string temporary = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
        { stream.Write(bytes); stream.Flush(true); }
#if CREDENTIAL_HELPER_TEST_HOOKS
        if (name == "vault.tpm") Pause("before-commit");
#endif
        File.Move(temporary, destination, true);
#if CREDENTIAL_HELPER_TEST_HOOKS
        if (name == "vault.tpm") Pause("after-commit");
#endif
    }

#if CREDENTIAL_HELPER_TEST_HOOKS
    /// <summary>Pause only the separate, non-publishable test harness at a crash boundary.</summary>
    private static void Pause(string point)
    {
        if (Environment.GetEnvironmentVariable("DOCKER_SSH_TEST_PAUSE") == point)
        { File.WriteAllText(Path.Combine(Root, "test-ready"), point); Thread.Sleep(Timeout.Infinite); }
    }
#endif

    /// <summary>Use the shared pure key policy for protocol requests and loaded vault records.</summary>
    private static string Canonical(string value) => CredentialKey.Normalize(value);

    /// <summary>Validate loaded and incoming records while preserving supported UTF-8 token values.</summary>
    private static void ValidateCredential(Credential credential)
    {
        if (credential.ServerURL != Canonical(credential.ServerURL) || string.IsNullOrEmpty(credential.Username) || string.IsNullOrEmpty(credential.Secret)) throw new InvalidDataException();
        foreach (string value in new[] { credential.Username, credential.Secret })
            if (value.Length > 65536 || value.IndexOfAny(['\r', '\n', '\0']) >= 0) throw new InvalidDataException();
    }

    /// <summary>Reject duplicate properties throughout JSON rather than silently accepting last values.</summary>
    internal static void RejectDuplicateProperties(byte[] bytes)
    {
        var reader = new Utf8JsonReader(bytes);
        var objects = new Stack<HashSet<string>>();
        while (reader.Read())
        {
            if (reader.TokenType == JsonTokenType.StartObject) objects.Push(new(StringComparer.Ordinal));
            else if (reader.TokenType == JsonTokenType.EndObject) objects.Pop();
            else if (reader.TokenType == JsonTokenType.PropertyName && !objects.Peek().Add(reader.GetString()!)) throw new InvalidDataException();
        }
    }

    /// <summary>Decrypt and validate a versioned dictionary; corrupted stores fail closed.</summary>
    private static Dictionary<string, Credential> Load(TpmCipher cipher)
    {
        byte[] plaintext = cipher.Decrypt(ReadBounded("vault.tpm"));
        try
        {
            return ParseVault(plaintext);
        }
        finally { CryptographicOperations.ZeroMemory(plaintext); }
    }

    /// <summary>Validate the exact versioned vault schema before accepting decrypted data.</summary>
    private static Dictionary<string, Credential> ParseVault(byte[] plaintext)
    {
        RejectDuplicateProperties(plaintext);
        using var document = JsonDocument.Parse(plaintext);
        if (document.RootElement.EnumerateObject().Count() != 2 || document.RootElement.EnumerateObject().Any(property => property.Name is not ("Version" or "Credentials"))) throw new InvalidDataException();
        if (document.RootElement.GetProperty("Version").GetInt32() != 1) throw new InvalidDataException();
        var result = new Dictionary<string, Credential>(StringComparer.Ordinal);
        foreach (var property in document.RootElement.GetProperty("Credentials").EnumerateObject())
        {
            var credential = property.Value.Deserialize<Credential>() ?? throw new InvalidDataException();
            ValidateCredential(credential);
            if (property.Name != credential.ServerURL || !result.TryAdd(property.Name, credential)) throw new InvalidDataException();
        }
        return result;
    }

    /// <summary>Encrypt the complete versioned dictionary before writing any bytes to disk.</summary>
    private static void Save(Dictionary<string, Credential> credentials, TpmCipher cipher)
    {
        byte[] plaintext = JsonSerializer.SerializeToUtf8Bytes(new { Version = 1, Credentials = credentials });
        try { Atomic("vault.tpm", cipher.Encrypt(plaintext)); }
        finally { CryptographicOperations.ZeroMemory(plaintext); }
    }
}
