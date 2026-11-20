using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

/// <summary>Nonsecret, protected router configuration; no endpoint or credential selection is cached here.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record RouterConfiguration(int Version, string Payload, string PowerShellExecutable,
    string PowerShellSha256, string SelectorPath, string PublicBootstrapRoot, Dictionary<string, string> Files);

/// <summary>Stable native Docker entry that selects a validated deployment for each command.</summary>
internal static class RouterProgram
{
    private static readonly string[] PayloadFiles = ["Enter-DockerSshEnvironment.ps1", "Get-TpmDockerEnvironment.ps1"];

    /// <summary>Validates the installed gateway and delegates one command without changing any parent environment.</summary>
    public static int Main(string[] arguments)
    {
        try
        {
            var binary = Path.TrimEndingDirectorySeparator(AppContext.BaseDirectory);
            if (Path.GetFileName(binary) != "bin") throw new InvalidDataException();
            var root = Path.GetDirectoryName(binary)!;
            RouterTrust.AssertPath(root);
            RouterTrust.AssertPath(binary);
            RouterTrust.AssertPath(Path.Combine(binary, "docker.exe"));
            var publication = Path.Combine(root, "published");
            var stagedCheck = arguments.SequenceEqual(new[] { "--dotfiles-router-check-staged" });
            if (!stagedCheck || File.Exists(publication) || Directory.Exists(publication))
            {
                RouterTrust.AssertPath(publication);
                if (File.ReadAllText(publication) != "1\n") throw new InvalidDataException();
            }
            var configurationPath = Path.Combine(root, "current.json");
            RouterTrust.AssertPath(configurationPath);
            var configuration = JsonSerializer.Deserialize<RouterConfiguration>(File.ReadAllBytes(configurationPath))
                ?? throw new InvalidDataException();
            if (configuration.Version != 1 || !IsHash(configuration.Payload)
                || configuration.Files.Count != PayloadFiles.Length) throw new InvalidDataException();
            var payload = Path.Combine(root, "releases", configuration.Payload);
            RouterTrust.AssertPath(Path.Combine(root, "releases"));
            RouterTrust.AssertPath(payload);
            foreach (var name in PayloadFiles)
                AssertHash(Path.Combine(payload, name), configuration.Files[name]);
            if (!Path.IsPathFullyQualified(configuration.PowerShellExecutable)
                || !Path.GetFileName(configuration.PowerShellExecutable).Equals("pwsh.exe", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException();
            AssertHash(configuration.PowerShellExecutable, configuration.PowerShellSha256, false);
            // This health check deliberately does not read the selector, contact the Engine or access credentials.
            if (stagedCheck || arguments.SequenceEqual(new[] { "--dotfiles-router-check" }))
            {
                Console.WriteLine("DOTFILES_DOCKER_ROUTER_READY");
                return 0;
            }
            AssertArguments(arguments);
            var metadata = ReadMetadata(configuration, payload);
            var deployment = Path.TrimEndingDirectorySeparator(Path.GetFullPath(metadata[0]));
            var dispatcher = Path.Combine(deployment, "bin", "0.5.0", "docker.exe");
            if (!Path.GetFullPath(metadata[2]).Equals(Path.GetDirectoryName(dispatcher), StringComparison.OrdinalIgnoreCase)
                || !Path.GetFullPath(metadata[3]).Equals(Path.Combine(deployment, "docker-config"), StringComparison.OrdinalIgnoreCase)
                || !Path.GetFullPath(metadata[4]).Equals(Path.Combine(deployment, "store"), StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException();
            RouterTrust.AssertPath(dispatcher);
            if (Path.GetFullPath(metadata[1]).Equals(Path.Combine(binary, "docker.exe"), StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException();
            var start = new ProcessStartInfo(dispatcher) { UseShellExecute = false };
            // Buildx must not select a persisted or remote builder outside the selected Engine.
            start.Environment["BUILDX_BUILDER"] = "default";
            start.Environment["BUILDX_CONFIG"] = Path.Combine(deployment, "docker-config", "buildx");
            foreach (var argument in arguments) start.ArgumentList.Add(argument);
            using var process = Process.Start(start) ?? throw new InvalidOperationException();
            process.WaitForExit();
            return process.ExitCode;
        }
        catch
        {
            Console.Error.WriteLine("Docker router validation failed; no other Docker CLI was attempted. Shell remains available.");
            return 1;
        }
    }

    /// <summary>Checks an uppercase SHA-256 representation before it can select a payload or trusted hash.</summary>
    private static bool IsHash(string value) => value.Length == 64 && value.All(character => character is >= '0' and <= '9' or >= 'A' and <= 'F');

    /// <summary>Validates filesystem trust before comparing a file's protected installation hash.</summary>
    private static void AssertHash(string path, string expected, bool privateLeaf = true)
    {
        RouterTrust.AssertPath(path, privateLeaf);
        if (!IsHash(expected) || Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))) != expected)
            throw new InvalidDataException();
    }

    /// <summary>Obtains one bounded selector snapshot from the existing canonical bootstrap without leaking its diagnostics.</summary>
    private static string[] ReadMetadata(RouterConfiguration configuration, string payload)
    {
        var start = new ProcessStartInfo(configuration.PowerShellExecutable)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-File",
            Path.Combine(payload, PayloadFiles[0]), "-SelectorPath", configuration.SelectorPath,
            "-PublicBootstrapRoot", configuration.PublicBootstrapRoot }) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException();
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(15000))
        {
            // Only the gateway's own metadata child is bounded; no Docker/server process is selected for termination.
            process.Kill();
            process.WaitForExit();
            throw new InvalidDataException();
        }
        var output = outputTask.GetAwaiter().GetResult();
        var error = errorTask.GetAwaiter().GetResult();
        if (process.ExitCode != 0 || error.Length != 0 || output.Length > 32768 || output.Contains('\r'))
            throw new InvalidDataException();
        var fields = output.Split('\n');
        if (fields.Length != 6 || fields.Any(string.IsNullOrEmpty)) throw new InvalidDataException();
        return fields;
    }

    /// <summary>Rejects alternate routing and builder transports while retaining the launcher's existing argument restrictions.</summary>
    private static void AssertArguments(string[] arguments)
    {
        if (arguments.Length == 0 || arguments[0].StartsWith('-')) throw new InvalidDataException();
        foreach (var name in new[] { "BUILDKIT_HOST", "BUILDX_CONFIG" })
            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable(name))) throw new InvalidDataException();
        var builder = Environment.GetEnvironmentVariable("BUILDX_BUILDER");
        if (!string.IsNullOrEmpty(builder) && builder != "default") throw new InvalidDataException();
        foreach (var argument in arguments)
            if (argument == "--builder" || argument.StartsWith("--builder=", StringComparison.Ordinal)) throw new InvalidDataException();
        if (arguments[0] == "buildx" && (arguments.Length < 2 || arguments[1] is not ("build" or "version")))
            throw new InvalidDataException();
        // Bake can select independent BuildKit routes; custom builder management is outside this gateway contract.
        if (arguments[0] == "bake") throw new InvalidDataException();
    }
}
