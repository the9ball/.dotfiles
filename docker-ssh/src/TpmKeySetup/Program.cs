using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

/// <summary>Public binding consumed by the credential helper, without any private key material.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record Binding(string ProviderName, string KeyName, string UserSid, string UniqueNameSHA256, string PublicSpkiSHA256);
/// <summary>Exact public identity and policy captured after creation and checked before every management operation.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record Identity(Binding Binding, string Owner, string DescriptorHash, int KeyType, int Length, int Usage, int PcpUsage, int Export, int UiVersion, int UiFlags);
/// <summary>Immutable verified creation receipt; incomplete intent never qualifies as creation provenance.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record Receipt(int Version, string InstallationId, string Mode, Identity Identity);

/// <summary>Explicit dedicated-key lifecycle, separate from Docker's credential protocol; default plan is read-only.</summary>
internal static class Program
{
    private const string ProviderName = "Microsoft Platform Crypto Provider";
    private static string root = "";
    private static string stage = "arguments";
    private static readonly SecurityIdentifier user = WindowsIdentity.GetCurrent().User!;
    private static SafeWaitHandle? stopEvent;

    /// <summary>Runs only an explicit key-management operation; errors expose stage and HRESULT, never exception contents.</summary>
    public static int Main(string[] arguments)
    {
        try
        {
            if (arguments.SequenceEqual(new[] { "--self-test" })) return SelfTest();
            if (arguments.Length != 4 || arguments[0] is not ("plan" or "create" or "inspect" or "delete")) throw new InvalidDataException();
            string operation = arguments[0], installationId = arguments[2], mode = arguments[3];
            string keyName = KeyName(installationId, mode);
            if (!Path.IsPathFullyQualified(arguments[1])) throw new InvalidDataException();
            root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(arguments[1]));
            RequirePrivate(root);
            if (Path.GetFileName(root) != "key") throw new InvalidDataException();
            CheckStop();
            if (operation == "plan")
            {
                Console.WriteLine(JsonSerializer.Serialize(new { Status = "PLAN_ONLY", KeyName = keyName, Mode = mode, PersistentChange = false }));
                return 0;
            }
            stage = "create-intent-preconditions";
            if (operation == "create" && (File.Exists(Path.Combine(root, "create-intent.json")) || File.Exists(Path.Combine(root, "receipt.json")))) throw new InvalidOperationException();
            if (operation is "create" or "delete")
            {
                stopEvent = OpenEvent(0x100000, false, "Local\\DockerSshIssue142BootStop-" + installationId);
                if (stopEvent.IsInvalid) throw new InvalidOperationException();
                CheckStop();
            }
            using var mutex = new Mutex(false, "Global\\DockerSshIssue142PocGate");
            bool acquired;
            try { acquired = mutex.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) throw new InvalidOperationException();
            try
            {
                if (File.Exists(Path.Combine(root, "operation.lock"))) RequirePrivate(Path.Combine(root, "operation.lock"));
                using var lease = new FileStream(Path.Combine(root, "operation.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
                stage = "provider";
                Check(NCryptOpenStorageProvider(out var provider, ProviderName, 0));
                using (provider)
                {
                    if ((Number(provider, "Impl Type") & 1) == 0 || Number(provider, "Security Descr Support") != 1) throw new InvalidDataException();
                    if (operation == "create") return Create(provider, installationId, mode, keyName);
                    return InspectOrDelete(provider, operation, installationId, mode, keyName);
                }
            }
            finally { mutex.ReleaseMutex(); }
        }
        catch (Exception exception)
        {
            Console.WriteLine($"key-setup : STOP; Stage={stage}; HRESULT=0x{exception.HResult:X8}; preserve state; no automatic retry");
            return 1;
        }
        finally { stopEvent?.Dispose(); }
    }

    /// <summary>Derives one exact namespace-bound key name, requiring explicit permanent versus disposable mode.</summary>
    internal static string KeyName(string installationId, string mode)
    {
        if (!Guid.TryParseExact(installationId, "N", out _) || installationId != installationId.ToLowerInvariant()) throw new InvalidDataException();
        return mode switch { "poc" => "docker-ssh-issue142-poc-" + installationId, "permanent" => "docker-ssh-tpm-" + installationId, _ => throw new InvalidDataException() };
    }

    /// <summary>Records create intent first, creates without overwrite, then verifies the same live key before completing provenance.</summary>
    private static int Create(SafeNCryptProviderHandle provider, string installationId, string mode, string name)
    {
        stage = "create-preconditions";
        if (File.Exists(Path.Combine(root, "create-intent.json")) || File.Exists(Path.Combine(root, "receipt.json"))) throw new InvalidOperationException();
        RequireNoResidualPoc(provider);
        int exists = NCryptOpenKey(provider, out var probe, name, 0, 0x60);
        probe.Dispose();
        if (exists != unchecked((int)0x80090016)) throw new InvalidOperationException();
        WriteNew("create-intent.json", new
        {
            Version = 1,
            InstallationId = installationId,
            Mode = mode,
            ProviderName,
            KeyName = name,
            Owner = user.Value,
            Length = 2048,
            GenericUsage = 1,
            PcpUsage = 2,
            Export = 0,
            UiFlags = 0,
            RequestedDacl = "USER_READ_DELETE_ONLY",
            CreatedUtc = DateTime.UtcNow
        });
        stage = "create-attempted";
        CheckStop();
        Check(NCryptCreatePersistedKey(provider, out var key, "RSA", name, 0, 0x20));
        using (key)
        {
            EncryptionPolicy.Configure(new NativePropertyWriter(key, StopRequested));
            CheckStop();
            Check(NCryptFinalizeKey(key, 0x40));
            stage = "public-provenance";
            var initial = Capture(key);
            WriteNew("created-public.json", new { InstallationId = installationId, Mode = mode, Identity = initial });
            byte[] descriptor = EncryptionPolicy.UserDescriptor(user);
            CheckStop();
            Check(NCryptSetProperty(key, "Security Descr", descriptor, descriptor.Length, unchecked((int)0x80000004)));
            stage = "policy-acl-verification";
            var identity = Capture(key);
            Verify(identity, key, name);
            if (initial.Binding != identity.Binding) throw new InvalidDataException();
            CheckStop();
            WriteNew("receipt.json", new Receipt(1, installationId, mode, identity));
            WriteNew("key-binding.json", identity.Binding);
            Console.WriteLine("key-create : PASS; policy-acl=VERIFIED; private-decryption=UNTESTED");
            return 0;
        }
    }

    /// <summary>Reads only verified provenance and deletes once on the same matched handle; API result and absence are independent records.</summary>
    private static int InspectOrDelete(SafeNCryptProviderHandle provider, string operation, string installationId, string mode, string name)
    {
        stage = "verified-receipt";
        var receipt = Read<Receipt>("receipt.json");
        if (receipt.Version != 1 || receipt.InstallationId != installationId || receipt.Mode != mode || receipt.Identity.Binding.KeyName != name) throw new InvalidDataException();
        if (File.Exists(Path.Combine(root, "delete-intent.json"))) throw new InvalidOperationException();
        CheckStop();
        Check(NCryptOpenKey(provider, out var key, name, 0, 0x60));
        using (key)
        {
            var identity = Capture(key);
            Verify(identity, key, name);
            if (identity != receipt.Identity) throw new InvalidDataException();
            if (operation == "inspect") { Console.WriteLine("key-inspect : PASS; exact-identity-policy-acl=MATCH"); return 0; }
            stage = "delete-preconditions";
            string storeLock = Path.Combine(Path.GetDirectoryName(root)!, "store/store.lock");
            if (File.Exists(storeLock)) RequirePrivate(storeLock);
            using var storeLease = File.Exists(storeLock) ? new FileStream(storeLock, FileMode.Open, FileAccess.ReadWrite, FileShare.None) : null;
            WriteNew("delete-intent.json", new { receipt.InstallationId, receipt.Identity, Flags = 0 });
            CheckStop();
            stage = "delete-attempted";
            int status = NCryptDeleteKey(key, 0);
            if (status == 0) key.SetHandleAsInvalid();
            WriteNew("delete-api.json", new { Status = $"0x{status:X8}" });
            CheckStop();
            stage = "absence-confirmation";
            int exists = NCryptOpenKey(provider, out var probe, name, 0, 0x60);
            probe.Dispose();
            bool absent = exists == unchecked((int)0x80090016);
            WriteNew("delete-existence.json", new { Status = $"0x{exists:X8}", Absent = absent });
            Console.WriteLine($"key-delete : {(status == 0 && absent ? "PASS" : "INCOMPLETE")}; DeleteHRESULT=0x{status:X8}; ExistenceHRESULT=0x{exists:X8}");
            return status == 0 && absent ? 0 : 1;
        }
    }

    /// <summary>Captures only public key material, identity hashes and actual policy values.</summary>
    private static Identity Capture(SafeNCryptKeyHandle handle)
    {
        CheckStop();
        using var key = CngKey.Open(handle, CngKeyHandleOpenOptions.None);
        using var rsa = new RSACng(key);
        byte[] descriptor = Property(handle, "Security Descr", 5), ui = Property(handle, "UI Policy");
        if (ui.Length < 8) throw new InvalidDataException();
        return new(new(key.Provider?.Provider ?? "", key.KeyName ?? "", user.Value, Hash(Encoding.UTF8.GetBytes(key.UniqueName ?? "")), Hash(rsa.ExportSubjectPublicKeyInfo())),
            new RawSecurityDescriptor(descriptor, 0).Owner?.Value ?? "", Hash(descriptor), Number(handle, "Key Type"), Number(handle, "Length"),
            Number(handle, "Key Usage"), Number(handle, "PCP_KEY_USAGE_POLICY"), Number(handle, "Export Policy"), BitConverter.ToInt32(ui), BitConverter.ToInt32(ui, 4));
    }

    /// <summary>Rejects any identity, namespace, policy or exact mapped DACL discrepancy before private use or removal.</summary>
    private static void Verify(Identity identity, SafeNCryptKeyHandle handle, string name)
    {
        if (identity.Binding.ProviderName != ProviderName || identity.Binding.KeyName != name || identity.Binding.UserSid != user.Value || identity.Owner != user.Value ||
            identity.KeyType != 0x20 || identity.Length != 2048 || identity.UiVersion != 1 ||
            !EncryptionPolicy.Accepts(identity.Usage, identity.PcpUsage, identity.Export, identity.UiFlags) || !EncryptionPolicy.AcceptsDescriptor(Property(handle, "Security Descr", 5), user)) throw new InvalidDataException();
    }

    /// <summary>Blocks creation if either CNG namespace contains any residual dedicated experiment name.</summary>
    private static void RequireNoResidualPoc(SafeNCryptProviderHandle provider)
    {
        foreach (int scope in new[] { 0, 0x20 })
        {
            IntPtr state = IntPtr.Zero;
            try
            {
                for (int count = 0; ; count++)
                {
                    if (count >= 10000) throw new InvalidDataException();
                    int status = NCryptEnumKeys(provider, null, out var item, ref state, scope | 0x40);
                    try
                    {
                        if (status == unchecked((int)0x8009002A)) break;
                        Check(status);
                        if (Marshal.PtrToStringUni(Marshal.ReadIntPtr(item))?.StartsWith("docker-ssh-issue142-poc-", StringComparison.OrdinalIgnoreCase) == true) throw new InvalidOperationException();
                    }
                    finally { if (item != IntPtr.Zero) Check(NCryptFreeBuffer(item)); }
                }
            }
            finally { if (state != IntPtr.Zero) Check(NCryptFreeBuffer(state)); }
        }
    }

    /// <summary>Validates user-only leaves and safe ancestors without traversing reparse points or changing permissions.</summary>
    internal static void RequirePrivate(string path)
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string absolute = Path.GetFullPath(path);
        if (!absolute.StartsWith(local + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException();
        var trusted = new[] { user.Value, "S-1-5-18", "S-1-5-32-544", ((SecurityIdentifier)new NTAccount("NT SERVICE", "TrustedInstaller").Translate(typeof(SecurityIdentifier))).Value };
        for (string? current = absolute; current != null; current = Path.GetDirectoryName(current))
        {
            if (File.GetAttributes(current).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidDataException();
            FileSystemSecurity security = Directory.Exists(current) ? new DirectoryInfo(current).GetAccessControl() : new FileInfo(current).GetAccessControl();
            var raw = new RawSecurityDescriptor(security.GetSecurityDescriptorBinaryForm(), 0);
            if (raw.DiscretionaryAcl is null || raw.Owner is null || !trusted.Contains(raw.Owner.Value)) throw new InvalidDataException();
            if (current == absolute && raw.Owner != user) throw new InvalidDataException();
            foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            {
                if (rule.AccessControlType != AccessControlType.Allow) continue;
                if (current == absolute && !user.Equals(rule.IdentityReference)) throw new InvalidDataException();
                var forbidden = FileSystemRights.Delete | FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
                if (!rule.PropagationFlags.HasFlag(PropagationFlags.InheritOnly) && !trusted.Contains(rule.IdentityReference.Value) && (rule.FileSystemRights & forbidden) != 0) throw new InvalidDataException();
            }
        }
    }

    /// <summary>Reads bounded, nonduplicate, strictly typed public metadata from a private leaf.</summary>
    private static T Read<T>(string name)
    {
        string path = Path.Combine(root, name);
        RequirePrivate(path);
        if (new FileInfo(path).Length > 65536) throw new InvalidDataException();
        byte[] bytes = File.ReadAllBytes(path);
        var reader = new Utf8JsonReader(bytes);
        var objects = new Stack<HashSet<string>>();
        while (reader.Read())
        {
            if (reader.TokenType == JsonTokenType.StartObject) objects.Push(new(StringComparer.Ordinal));
            else if (reader.TokenType == JsonTokenType.EndObject) objects.Pop();
            else if (reader.TokenType == JsonTokenType.PropertyName && !objects.Peek().Add(reader.GetString()!)) throw new InvalidDataException();
        }
        return JsonSerializer.Deserialize<T>(bytes) ?? throw new InvalidDataException();
    }

    /// <summary>Writes only public metadata with create-only semantics and a durable flush.</summary>
    private static void WriteNew<T>(string name, T value)
    {
        using var file = new FileStream(Path.Combine(root, name), FileMode.CreateNew, FileAccess.Write, FileShare.Read, 4096, FileOptions.WriteThrough);
        JsonSerializer.Serialize(file, value);
        file.Flush(true);
    }

    /// <summary>Checks naming and incomplete-state refusal without a provider or cryptographic operation.</summary>
    private static int SelfTest()
    {
        string id = "0123456789abcdef0123456789abcdef";
        if (KeyName(id, "poc") != "docker-ssh-issue142-poc-" + id || KeyName(id, "permanent") != "docker-ssh-tpm-" + id) return 1;
        foreach (var pair in new[] { ("../key", "poc"), (id.ToUpperInvariant(), "poc"), (id, "auto") })
        {
            try { KeyName(pair.Item1, pair.Item2); return 1; } catch (InvalidDataException) { }
        }
        Console.WriteLine("key-setup-simulation : PASS; assertions=5; key-operations=0");
        return 0;
    }

    /// <summary>Stops subsequent operations after an external UI/stall signal; cannot cancel an in-flight native call.</summary>
    private static void CheckStop() { if (StopRequested()) throw new OperationCanceledException(); }
    /// <summary>Combines the nonpersistent stop-only event with a durable marker, failing closed on an unknown event state.</summary>
    private static bool StopRequested()
    {
        if (stopEvent is not null)
        {
            uint status = WaitForSingleObject(stopEvent, 0);
            if (status is not (0 or 258)) throw new InvalidOperationException();
            if (status == 0) return true;
        }
        return File.Exists(Path.Combine(root, "stop-request.json"));
    }
    /// <summary>Hashes only public metadata, never private key material.</summary>
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    /// <summary>Reads one bounded public property from an already-owned handle.</summary>
    private static byte[] Property(SafeNCryptHandle handle, string name, int flags = 0)
    {
        CheckStop();
        byte[] bytes = new byte[65536];
        Check(NCryptGetProperty(handle, name, bytes, bytes.Length, out int length, flags));
        if (length < 0 || length > bytes.Length) throw new InvalidDataException();
        return bytes[..length];
    }
    /// <summary>Requires a DWORD property rather than accepting truncated values.</summary>
    private static int Number(SafeNCryptHandle handle, string name) { byte[] bytes = Property(handle, name); if (bytes.Length != 4) throw new InvalidDataException(); return BitConverter.ToInt32(bytes); }
    /// <summary>Turns only native failure codes into nonsecret HRESULT diagnostics.</summary>
    private static void Check(int status) { if (status != 0) throw new CryptographicException(status); }
    /// <summary>Opens the fixed hardware provider without modifying it.</summary>
    [DllImport("ncrypt.dll", CharSet = CharSet.Unicode)] private static extern int NCryptOpenStorageProvider(out SafeNCryptProviderHandle provider, string name, int flags);
    /// <summary>Opens only the exact selected key silently.</summary>
    [DllImport("ncrypt.dll", CharSet = CharSet.Unicode)] private static extern int NCryptOpenKey(SafeNCryptProviderHandle provider, out SafeNCryptKeyHandle key, string name, int legacy, int flags);
    /// <summary>Creates without any overwrite flag, after durable intent.</summary>
    [DllImport("ncrypt.dll", CharSet = CharSet.Unicode)] private static extern int NCryptCreatePersistedKey(SafeNCryptProviderHandle provider, out SafeNCryptKeyHandle key, string algorithm, string name, int legacy, int flags);
    /// <summary>Finalizes only the caller-created key with silent flags.</summary>
    [DllImport("ncrypt.dll")] private static extern int NCryptFinalizeKey(SafeNCryptKeyHandle key, int flags);
    /// <summary>Sets the new key's intended user-only descriptor.</summary>
    [DllImport("ncrypt.dll", CharSet = CharSet.Unicode)] private static extern int NCryptSetProperty(SafeNCryptKeyHandle key, string name, byte[] input, int length, int flags);
    /// <summary>Reads provider and key public policy values.</summary>
    [DllImport("ncrypt.dll", CharSet = CharSet.Unicode)] private static extern int NCryptGetProperty(SafeNCryptHandle key, string name, byte[] output, int length, out int returned, int flags);
    /// <summary>Enumerates public names for residual PoC prevention.</summary>
    [DllImport("ncrypt.dll", CharSet = CharSet.Unicode)] private static extern int NCryptEnumKeys(SafeNCryptProviderHandle provider, string? scope, out IntPtr name, ref IntPtr state, int flags);
    /// <summary>Releases only provider-owned enumeration memory.</summary>
    [DllImport("ncrypt.dll")] private static extern int NCryptFreeBuffer(IntPtr memory);
    /// <summary>Consumes exactly the verified key handle once, with flags zero.</summary>
    [DllImport("ncrypt.dll")] private static extern int NCryptDeleteKey(SafeNCryptKeyHandle key, int flags);
    /// <summary>Opens only the caller-created user-authorized stop event with synchronize access.</summary>
    [DllImport("kernel32.dll", EntryPoint = "OpenEventW", CharSet = CharSet.Unicode)] private static extern SafeWaitHandle OpenEvent(int access, bool inherit, string name);
    /// <summary>Observes the stop event without resetting it or blocking.</summary>
    [DllImport("kernel32.dll")] private static extern uint WaitForSingleObject(SafeWaitHandle handle, uint milliseconds);
}
