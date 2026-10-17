using System.Security.AccessControl;
using System.Security.Principal;

/// <summary>Pure ACL regression checks; no filesystem security or key is changed.</summary>
internal static class AclChecks
{
    /// <summary>Distinguishes unrestricted null DACLs from explicit empty and user-only DACLs.</summary>
    internal static int Run()
    {
        var user = WindowsIdentity.GetCurrent().User!;
        var missing = new RawSecurityDescriptor(ControlFlags.None, user, user, null, null);
        var nullDacl = new RawSecurityDescriptor(ControlFlags.DiscretionaryAclPresent, user, user, null, null);
        foreach (var descriptor in new[] { missing, nullDacl })
        {
            try { Program.RequireDacl(Bytes(descriptor)); return 1; }
            catch (InvalidDataException) { }
        }
        Program.RequireDacl(Bytes(new RawSecurityDescriptor(ControlFlags.DiscretionaryAclPresent, user, user, null, new RawAcl(2, 0))));
        Program.RequireDacl(Bytes(new RawSecurityDescriptor($"O:{user.Value}D:P(A;;FA;;;{user.Value})")));
        var privateSecurity = new FileSecurity();
        privateSecurity.SetSecurityDescriptorSddlForm($"O:{user.Value}D:P(A;;FA;;;{user.Value})");
        Program.VerifySecurity(privateSecurity);
        var broadSecurity = new FileSecurity();
        broadSecurity.SetSecurityDescriptorSddlForm($"O:{user.Value}D:P(A;;FA;;;WD)");
        try { Program.VerifySecurity(broadSecurity); return 1; }
        catch (InvalidDataException) { }
        Console.WriteLine("null-dacl-regression : PASS; assertions=6; native-key-calls=0");
        return 0;
    }

    /// <summary>Serializes a synthetic descriptor without applying it to an OS object.</summary>
    private static byte[] Bytes(RawSecurityDescriptor descriptor)
    {
        var bytes = new byte[descriptor.BinaryLength];
        descriptor.GetBinaryForm(bytes, 0);
        return bytes;
    }
}
