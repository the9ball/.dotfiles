using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

/// <summary>Runs the real gateway control flow with inert runtime/dispatcher children, never Docker, TPM or ACL operations.</summary>
internal static class RouterChecks
{
    private static int assertions;

    /// <summary>Selects an inert executable role or runs the isolated native and optional real-shell regression suite.</summary>
    public static int Main(string[] arguments)
    {
        var executable = Environment.ProcessPath!;
        var name = Path.GetFileName(executable);
        // The metadata protocol requires empty stderr, including when its parent is being diagnosed.
        if (name != "pwsh.exe" && Environment.GetEnvironmentVariable("ROUTER_FIXTURE_DIAGNOSTICS") == "1")
            Console.Error.WriteLine("ROUTER_DIAG stage=fixture-main image=" + executable);
        if (arguments.SequenceEqual(new[] { "--inert-startup-probe" }))
        {
            Console.WriteLine("INERT_STARTUP_OK image=" + executable);
            return 0;
        }
        if (name == "pwsh.exe") return Metadata(arguments);
        if (name == "native-probe.exe") return NativeChild(arguments);
        if (name == "docker.exe")
        {
            if (Path.GetFileName(Path.GetDirectoryName(executable)) == "0.5.0") return Dispatcher(arguments);
            if (Path.GetFileName(Path.GetDirectoryName(executable)) == "competing")
            {
                Console.WriteLine("UNEXPECTED_FALLBACK");
                return 99;
            }
            return RouterProgram.Main(arguments);
        }
        var fixture = Path.Combine(Path.GetTempPath(), "docker-router-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(fixture);
            var nativeVerified = RunChecks(executable, fixture, arguments.Contains("--shells"));
            Console.WriteLine($"PASS {assertions} gateway assertions; raw native lookup={(nativeVerified ? "VERIFIED" : "BLOCKED")}; bootstrap/runtime/dispatcher=inert; ACL/Docker/TPM=NONE");
            return nativeVerified ? 0 : 2;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine("FAIL " + exception.Message);
            return 1;
        }
        finally
        {
            // Only this invocation's unique TEMP tree is eligible for cleanup.
            if (Path.GetFullPath(fixture).StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase))
                Directory.Delete(fixture, true);
        }
    }

    /// <summary>Emulates only the bootstrap's six-field protocol from a synthetic selector.</summary>
    private static int Metadata(string[] arguments)
    {
        var selectorIndex = Array.IndexOf(arguments, "-SelectorPath");
        if (selectorIndex < 0) return 3;
        try
        {
            using var selector = JsonDocument.Parse(File.ReadAllText(arguments[selectorIndex + 1]));
            var root = selector.RootElement.GetProperty("DeploymentRoot").GetString()!;
            if (root == "invalid") return 4;
            Console.Write(string.Join('\n', root, Path.Combine(root, "actual-cli.exe"), Path.Combine(root, "bin", "0.5.0"),
                Path.Combine(root, "docker-config"), Path.Combine(root, "store"), "npipe:////./pipe/inertFixture"));
            return 0;
        }
        catch { return 5; }
    }

    /// <summary>Reports the selected fixture and environment or simulates an Engine/authentication failure.</summary>
    private static int Dispatcher(string[] arguments)
    {
        if (arguments.Contains("fixture-engine-down") || arguments.Contains("fixture-auth-failure")) return 42;
        if (arguments.Contains("fixture-stdin"))
        {
            Console.Write(Console.In.ReadToEnd());
            Console.Error.Write("fixture-stderr");
            return 0;
        }
        Console.Write(JsonSerializer.Serialize(new
        {
            deployment = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..")),
            arguments,
            builder = Environment.GetEnvironmentVariable("BUILDX_BUILDER"),
            buildxConfig = Environment.GetEnvironmentVariable("BUILDX_CONFIG"),
            parentConfig = Environment.GetEnvironmentVariable("DOCKER_CONFIG")
        }));
        return 0;
    }

    /// <summary>Exercises an ordinary native child's bare docker.exe lookup using the inherited process environment.</summary>
    private static int NativeChild(string[] arguments)
    {
        var expected = Path.Combine(AppContext.BaseDirectory, "router", "bin", "docker.exe");
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        // CreateProcess searches these locations before PATH; refuse a fixture escape before executing any CLI.
        var earlierDirectories = new[] { AppContext.BaseDirectory, Environment.CurrentDirectory,
            Environment.SystemDirectory, Path.Combine(windows, "System"), windows };
        foreach (var directory in earlierDirectories)
        {
            var candidate = Path.GetFullPath(Path.Combine(directory, "docker.exe"));
            if (File.Exists(candidate) && !candidate.Equals(expected, StringComparison.OrdinalIgnoreCase))
            {
                Console.Error.WriteLine("RAW_NATIVE_LOOKUP_BLOCKED: earlier executable: " + candidate);
                return 93;
            }
        }
        var selected = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
            .Select(directory => Path.Combine(directory.Trim('"'), "docker.exe")).FirstOrDefault(File.Exists);
        if (selected is null || !Path.GetFullPath(selected).Equals(expected, StringComparison.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine("RAW_NATIVE_LOOKUP_BLOCKED: fixture PATH prefix not selected.");
            return 93;
        }
        var start = new ProcessStartInfo("docker.exe") { UseShellExecute = false };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        process.WaitForExit();
        return process.ExitCode;
    }

    /// <summary>Requires one observable contract without hiding later failed assertions.</summary>
    private static void Check(bool condition, string description)
    {
        if (!condition) throw new InvalidDataException(description);
        assertions++;
    }

    /// <summary>Executes an owned fixture or selected shell and signals successful creation before redirected I/O, without process-wide mutations.</summary>
    private static (int Exit, string Output, string Error) Run(string executable, string[] arguments, string fixture,
        Dictionary<string, string?>? changes = null, string input = "", Action? onStarted = null)
    {
        var start = new ProcessStartInfo(executable)
        {
            UseShellExecute = false,
            WorkingDirectory = fixture,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        foreach (var name in new[] { "DOCKER_CONFIG", "DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_AUTH_CONFIG", "DOCKER_TLS_VERIFY",
            "DOCKER_CERT_PATH", "DOCKER_SSH_DEPLOYMENT", "DOCKER_SSH_HELPER_ROOT", "DOCKER_SSH_MANAGED", "BUILDX_BUILDER", "BUILDX_CONFIG", "BUILDKIT_HOST" })
            start.Environment.Remove(name);
        start.Environment["PATH"] = Path.Combine(fixture, "router", "bin") + ";" + Path.Combine(fixture, "competing") + ";" + Environment.GetEnvironmentVariable("PATH");
        start.Environment["ROUTER_FIXTURE_ENTRY"] = Path.Combine(fixture, "router", "bin", "docker.exe");
        if (changes is not null)
            foreach (var change in changes)
                if (change.Value is null) start.Environment.Remove(change.Key); else start.Environment[change.Key] = change.Value;
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Owned fixture did not start.");
        onStarted?.Invoke();
        var output = process.StandardOutput.ReadToEndAsync();
        var error = process.StandardError.ReadToEndAsync();
        process.StandardInput.Write(input);
        process.StandardInput.Close();
        if (!process.WaitForExit(30000))
        {
            process.Kill(true);
            process.WaitForExit();
            throw new InvalidOperationException("Owned fixture timed out.");
        }
        return (process.ExitCode, output.GetAwaiter().GetResult(), error.GetAwaiter().GetResult());
    }

    /// <summary>Reports bounded output, exit status and failures before or after process creation without exposing arguments or the inherited environment.</summary>
    private static (int Exit, string Output, string Error) RunDiagnostic(string label, string executable, string[] arguments, string fixture)
    {
        Console.WriteLine($"ROUTER_DIAG label={label} stage=spawn requested={JsonSerializer.Serialize(executable)}");
        var processStarted = false;
        try
        {
            var result = Run(executable, arguments, fixture,
                new Dictionary<string, string?> { ["ROUTER_FIXTURE_DIAGNOSTICS"] = "1" }, onStarted: () => processStarted = true);
            Console.WriteLine($"ROUTER_DIAG label={label} stage=exited exit={result.Exit} hex=0x{unchecked((uint)result.Exit):X8}");
            Console.WriteLine($"ROUTER_DIAG label={label} stdoutChars={result.Output.Length} stdout={DiagnosticExcerpt(result.Output)}");
            Console.WriteLine($"ROUTER_DIAG label={label} stderrChars={result.Error.Length} stderr={DiagnosticExcerpt(result.Error)}");
            return result;
        }
        catch (System.ComponentModel.Win32Exception exception)
        {
            Console.WriteLine($"ROUTER_DIAG label={label} stage={(processStarted ? "post-start-failed" : "start-failed")} win32={exception.NativeErrorCode} hex=0x{unchecked((uint)exception.NativeErrorCode):X8}");
            throw;
        }
        catch (Exception exception)
        {
            Console.WriteLine($"ROUTER_DIAG label={label} stage={(processStarted ? "post-start-failed" : "start-failed")} type={exception.GetType().Name}");
            throw;
        }
    }

    /// <summary>Escapes control characters and limits each synthetic diagnostic stream to 1024 characters.</summary>
    private static string DiagnosticExcerpt(string value) => JsonSerializer.Serialize(value[..Math.Min(value.Length, 1024)]);

    /// <summary>Creates a copy of this inert single-file executable without replacing pre-existing files.</summary>
    private static string CopyExecutable(string source, string target)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        File.Copy(source, target, false);
        return target;
    }

    /// <summary>Writes a selector snapshot atomically without changing any real selector.</summary>
    private static void Select(string selector, string deployment) =>
        File.WriteAllText(selector, JsonSerializer.Serialize(new { Version = 1, DeploymentRoot = deployment }));

    /// <summary>Proves selection, child inheritance, update and error containment through the production gateway code.</summary>
    private static bool RunChecks(string executable, string fixture, bool shells)
    {
        var inertStartup = RunDiagnostic("inert-startup", executable, ["--inert-startup-probe"], fixture);
        Check(inertStartup.Exit == 0 && inertStartup.Output.Contains("INERT_STARTUP_OK"), "managed startup without Router failed; see ROUTER_DIAG");
        var router = Path.Combine(fixture, "router");
        var binary = CopyExecutable(executable, Path.Combine(router, "bin", "docker.exe"));
        var runtime = CopyExecutable(executable, Path.Combine(fixture, "runtime", "pwsh.exe"));
        var native = CopyExecutable(executable, Path.Combine(fixture, "native-probe.exe"));
        CopyExecutable(executable, Path.Combine(fixture, "competing", "docker.exe"));
        var first = Path.Combine(fixture, "deployment-one");
        var second = Path.Combine(fixture, "deployment-two");
        foreach (var deployment in new[] { first, second })
            CopyExecutable(executable, Path.Combine(deployment, "bin", "0.5.0", "docker.exe"));
        var payloadName = new string('A', 64);
        var payload = Path.Combine(router, "releases", payloadName);
        Directory.CreateDirectory(payload);
        var files = new Dictionary<string, string>();
        foreach (var name in new[] { "Enter-DockerSshEnvironment.ps1", "Get-TpmDockerEnvironment.ps1" })
        {
            var file = Path.Combine(payload, name);
            File.WriteAllText(file, "# Inert protocol fixture; never executed as PowerShell.\n");
            files[name] = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file)));
        }
        var selector = Path.Combine(fixture, "selector.json");
        Select(selector, first);
        var configuration = new RouterConfiguration(1, payloadName, runtime,
            Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(runtime))), selector, Path.Combine(fixture, "public"), files);
        var current = Path.Combine(router, "current.json");
        var validConfiguration = JsonSerializer.Serialize(configuration);
        File.WriteAllText(current, validConfiguration);
        Check(RunDiagnostic("staging-health", binary, ["--dotfiles-router-check-staged"], fixture).Exit == 0,
            "staging health before publication failed; see ROUTER_DIAG");
        File.WriteAllText(Path.Combine(router, "published"), "1\n");
        var nativeProbe = RunDiagnostic("raw-native", native, ["ps"], fixture);
        var nativeVerified = nativeProbe.Exit == 0;
        Check(nativeVerified || nativeProbe.Exit == 93, "native lookup preflight: " + nativeProbe.Error);
        if (!nativeVerified) Console.Error.Write(nativeProbe.Error);
        // Continue gateway protocol checks by explicit fixture path when raw OS lookup is blocked; never call this native success.
        var caller = nativeVerified ? native : binary;
        var parentPath = Environment.GetEnvironmentVariable("PATH");
        foreach (var command in new[] { new[] { "ps" }, new[] { "build", "--tag", "inert:fixture", "." },
            new[] { "compose", "logs", "--tail", "10" }, new[] { "buildx", "build", "." },
            new[] { "run", "inert", "space value", "日本語", "quote\"value", "literal$()" } })
        {
            var result = Run(caller, command, fixture);
            Check(result.Exit == 0, "gateway protocol: " + result.Error);
            using var output = JsonDocument.Parse(result.Output);
            Check(output.RootElement.GetProperty("deployment").GetString() == first, "selected deployment");
            Check(output.RootElement.GetProperty("arguments").EnumerateArray().Select(value => value.GetString()).SequenceEqual(command), "argument boundaries");
            Check(output.RootElement.GetProperty("builder").GetString() == "default", "fixed default builder");
            Check(output.RootElement.GetProperty("parentConfig").ValueKind == JsonValueKind.Null, "no parent deployment config");
        }
        Check(Environment.GetEnvironmentVariable("PATH") == parentPath, "parent PATH retained");
        var streams = Run(caller, ["ps", "fixture-stdin"], fixture, input: "inert pipe input\n");
        Check(streams.Exit == 0 && streams.Output == "inert pipe input\n" && streams.Error == "fixture-stderr", "stdin/stdout/stderr inherited through native children");
        Select(selector, second);
        Check(Run(caller, ["ps"], fixture).Output.Contains("deployment-two"), "next-call selector change");
        foreach (var failure in new[] { "fixture-engine-down", "fixture-auth-failure" })
        {
            Check(Run(caller, ["ps", failure], fixture).Exit == 42, "Docker child failure returned");
            Check(Run(caller, ["ps"], fixture).Exit == 0, "parent/next command remains usable");
        }
        foreach (var environment in new[] { new Dictionary<string, string?> { ["BUILDX_BUILDER"] = "remote" },
            new Dictionary<string, string?> { ["BUILDKIT_HOST"] = "tcp://inert.invalid" },
            new Dictionary<string, string?> { ["BUILDX_CONFIG"] = "other" } })
            Check(Run(caller, ["build", "."], fixture, environment).Exit == 1, "competing builder rejected");
        foreach (var arguments in new[] { new[] { "build", "--builder=remote", "." }, new[] { "buildx", "create" }, new[] { "bake" } })
            Check(Run(caller, arguments, fixture).Exit == 1, "alternate builder arguments rejected");
        File.Delete(selector);
        Check(Run(binary, ["--dotfiles-router-check"], fixture).Exit == 0, "shell health independent of selector");
        Check(Run(caller, ["ps"], fixture).Exit == 1, "missing selector rejected");
        File.WriteAllText(selector, "{");
        Check(Run(caller, ["ps"], fixture).Exit == 1, "malformed selector rejected");
        Select(selector, "invalid");
        Check(Run(caller, ["ps"], fixture).Exit == 1, "deployment validation rejected");
        Select(selector, second);
        foreach (var invalid in new[] { "{", validConfiguration.Replace(payloadName, "../escape"), validConfiguration.Replace(files.Values.First(), new string('0', 64)) })
        {
            File.WriteAllText(current, invalid);
            var result = Run(caller, ["ps"], fixture);
            Check(result.Exit == 1 && !result.Output.Contains("UNEXPECTED_FALLBACK"), "invalid config/hash never falls back");
        }
        File.WriteAllText(current, validConfiguration);
        File.WriteAllText(Path.Combine(router, "published"), "invalid");
        Check(Run(caller, ["ps"], fixture).Exit == 1, "invalid publication rejected");
        File.WriteAllText(Path.Combine(router, "published"), "1\n");
        if (shells) ShellChecks(fixture, first, selector);
        return nativeVerified;
    }

    /// <summary>Exercises actual Bash/PowerShell children and the actual repository startup gate against the inert bundle.</summary>
    private static void ShellChecks(string fixture, string first, string selector)
    {
        Select(selector, first);
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var bash = Path.Combine(programFiles, "Git", "bin", "bash.exe");
        var powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        var startupResult = RunDiagnostic("windows-powershell-startup", powershell,
            ["-NoProfile", "-NonInteractive", "-Command", "[Console]::WriteLine('SHELL_STARTUP_OK')"], fixture);
        var shellCommand = "printf 'ROUTER_DIAG stage=shell-main shell=bash\\n' >&2; selected=$(command -v docker); printf 'ROUTER_DIAG stage=resolved selected=%s\\n' \"$selected\" >&2; expected=$(cygpath -u \"$ROUTER_FIXTURE_ENTRY\"); [[ $selected -ef $expected ]] || exit 93; printf 'ROUTER_DIAG stage=invoke-fixture\\n' >&2; docker ps";
        var bashResult = RunDiagnostic("bash-direct", bash, ["--noprofile", "--norc", "-c", shellCommand], fixture);
        // Keep native stderr non-terminating in Windows PowerShell 5.1; discovery still fails closed with ErrorAction Stop.
        // A missing native exit status must not turn a failed launch into shell success.
        // Get-Command lists every PATH match in search order, and PowerShell invokes only the first; comparing the whole
        // list with -ine would filter it instead of producing a boolean, so the route check uses the first entry.
        var powershellCommand = "[Console]::Error.WriteLine('ROUTER_DIAG stage=shell-main shell=powershell version=' + $PSVersionTable.PSVersion); "
            + "$ErrorActionPreference='Continue'; try { $selected=@(Get-Command docker.exe -CommandType Application -ErrorAction Stop); "
            + "[Console]::Error.WriteLine('ROUTER_DIAG stage=resolved count=' + $selected.Count + ' selected=' + ($selected.Source -join '|')); "
            + "if($selected[0].Source -ine $env:ROUTER_FIXTURE_ENTRY){exit 93}; "
            + "[Console]::Error.WriteLine('ROUTER_DIAG stage=invoke-fixture'); $LASTEXITCODE=$null; & docker.exe ps; "
            + "if($null -eq $LASTEXITCODE){exit 94}; exit $LASTEXITCODE "
            + "} catch { [Console]::Error.WriteLine('ROUTER_DIAG stage=shell-error type=' + $_.Exception.GetType().FullName); exit 94 }";
        var powershellResult = RunDiagnostic("windows-powershell-direct", powershell,
            ["-NoProfile", "-NonInteractive", "-Command", powershellCommand], fixture);
        var explicitCommand = "[Console]::Error.WriteLine('ROUTER_DIAG stage=shell-main route=absolute-fixture'); "
            + "$ErrorActionPreference='Continue'; try { Get-Command $env:ROUTER_FIXTURE_ENTRY -CommandType Application -ErrorAction Stop | Out-Null; "
            + "$LASTEXITCODE=$null; & $env:ROUTER_FIXTURE_ENTRY ps; if($null -eq $LASTEXITCODE){exit 94}; exit $LASTEXITCODE "
            + "} catch { [Console]::Error.WriteLine('ROUTER_DIAG stage=shell-error type=' + $_.Exception.GetType().FullName); exit 94 }";
        var explicitResult = RunDiagnostic("windows-powershell-absolute-fixture", powershell,
            ["-NoProfile", "-NonInteractive", "-Command", explicitCommand], fixture);
        var modernPowerShell = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
            .Select(directory => directory.Trim('"')).Where(Path.IsPathRooted)
            .Select(directory => Path.Combine(directory, "pwsh.exe")).FirstOrDefault(File.Exists);
        if (modernPowerShell is not null)
        {
            var modernResult = RunDiagnostic("pwsh-direct", modernPowerShell,
                ["-NoProfile", "-NonInteractive", "-Command", powershellCommand], fixture);
            Check(modernResult.Exit == 0 && modernResult.Output.Contains("deployment-one"), "actual pwsh native route failed; see ROUTER_DIAG");
        }
        else Console.WriteLine("ROUTER_DIAG label=pwsh-direct stage=not-tested reason=no-rooted-path-candidate");
        Check(startupResult.Exit == 0 && startupResult.Output.Contains("SHELL_STARTUP_OK"), "Windows PowerShell startup failed; see ROUTER_DIAG");
        Check(bashResult.Exit == 0 && bashResult.Output.Contains("deployment-one"), "actual Bash native route failed; see ROUTER_DIAG");
        Check(powershellResult.Exit == 0 && powershellResult.Output.Contains("deployment-one"), "actual PowerShell native route failed; see ROUTER_DIAG");
        Check(explicitResult.Exit == 0 && explicitResult.Output.Contains("deployment-one"), "absolute PowerShell fixture route failed; see ROUTER_DIAG");
        var repository = Environment.GetEnvironmentVariable("DOCKER_ROUTER_TEST_REPOSITORY") ?? throw new InvalidDataException("Repository test root required.");
        var home = Path.Combine(fixture, "home");
        Directory.CreateDirectory(Path.Combine(home, ".dotfiles"));
        foreach (var name in new[] { ".bashrc", ".bashrc.docker-router" }) File.Copy(Path.Combine(repository, name), Path.Combine(home, ".dotfiles", name));
        File.WriteAllText(Path.Combine(home, ".bashrc.local"), "export DOTFILES_DOCKER_SSH=required\n");
        File.WriteAllText(Path.Combine(home, ".dotfiles", ".bashrc.docker-ssh"), "printf LEGACY_BOOTSTRAP\n");
        File.WriteAllText(Path.Combine(home, ".dotfiles", ".bashrc.ssh-psmux"), "printf OVERLAY_REACHED\n");
        var local = Path.Combine(fixture, "local");
        var environment = new Dictionary<string, string?> { ["HOME"] = home, ["LOCALAPPDATA"] = local, ["SSH_CONNECTION"] = "synthetic ssh", ["PSMUX_SESSION"] = "main" };
        var startup = "source \"$HOME/.dotfiles/.bashrc\"; printf SHELL_ALIVE; if ! declare -F docker >/dev/null; then selected=$(command -v docker); expected=$(cygpath -u \"$ROUTER_FIXTURE_ENTRY\"); [[ $selected -ef $expected ]] || exit 93; fi; docker ps";
        var before = Run(bash, ["--noprofile", "--norc", "-c", startup], fixture, environment);
        Check(before.Output.Contains("LEGACY_BOOTSTRAP") && before.Output.Contains("SHELL_ALIVE"), "prepublication legacy branch retained");
        var installed = Path.Combine(local, "Dotfiles", "DockerRouter");
        Directory.CreateDirectory(Path.GetDirectoryName(installed)!);
        Directory.Move(Path.Combine(fixture, "router"), installed);
        environment["ROUTER_FIXTURE_ENTRY"] = Path.Combine(installed, "bin", "docker.exe");
        var after = Run(bash, ["--noprofile", "--norc", "-c", startup], fixture, environment);
        Check(after.Exit == 0 && !after.Output.Contains("LEGACY_BOOTSTRAP") && after.Output.Contains("SHELL_ALIVE")
            && after.Output.Contains("deployment-one"), "published stale-required flag uses common route: " + after.Error);
        File.WriteAllText(Path.Combine(installed, "current.json"), "{");
        var broken = Run(bash, ["--noprofile", "--norc", "-c", startup + "; printf STILL_ALIVE"], fixture, environment);
        Check(broken.Output.Contains("STILL_ALIVE") && !broken.Output.Contains("LEGACY_BOOTSTRAP")
            && !broken.Output.Contains("UNEXPECTED_FALLBACK"), "configuration failure preserves shell and suppresses legacy");
    }
}
