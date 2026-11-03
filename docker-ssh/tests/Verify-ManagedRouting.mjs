import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const repository = path.dirname(root);
const scratch = fs.mkdtempSync(path.join(process.env.LOCALAPPDATA, 'docker-ssh-issue185-tests-'));
const local = path.join(scratch, 'Local');
const home = path.join(scratch, 'Home');
const deployment = path.join(local, '日本語 deployment');
const shell = path.join(root, 'chezmoi/AppData/Local/Dotfiles/DockerSsh');
const installedShell = path.join(deployment, 'shell');
const canonicalShell = path.join(home, '.dotfiles/docker-ssh/chezmoi/AppData/Local/Dotfiles/DockerSsh');
const binary = path.join(deployment, 'bin/0.5.0');
const hookDirectory = path.join(local, 'Dotfiles/DockerSsh');
const selector = path.join(hookDirectory, 'ssh-environment.json');
const bash = path.join(process.env.ProgramFiles, 'Git/usr/bin/bash.exe');
const powershell = process.env.ISSUE185_PWSH;
const dispatcher = path.join(binary, 'docker.exe');
const marker = path.join(scratch, 'calls.jsonl');
const results = [];
const environment = { ...process.env, TEMP: scratch, TMP: scratch, HOME: home.replaceAll('\\', '/'), USERPROFILE: home, LOCALAPPDATA: local,
    DOCKER_CONFIG: '', DOCKER_HOST: '', DOCKER_CONTEXT: '', DOCKER_AUTH_CONFIG: '', DOCKER_TLS_VERIFY: '', DOCKER_CERT_PATH: '', DOCKER_SSH_HELPER_ROOT: '',
    DOTFILES_DOCKER_SSH: '', SSH_CONNECTION: '', ROUTING_PROBE_MARKER: marker };

/** Execute only isolated shell/compiler/probe processes with a bounded timeout. */
function run(executable, arguments_, extraEnvironment = {}, input = '') {
    const child = spawnSync(executable, arguments_, { env: { ...environment, ...extraEnvironment }, input, encoding: 'utf8', windowsHide: true, timeout: 300000, maxBuffer: 1048576 });
    assert.equal(child.error, undefined, 'Isolated subprocess must complete');
    return child;
}

/** Record an assertion without printing environment or protocol payloads. */
function check(name, condition) {
    assert.equal(condition, true, name);
    results.push(name);
    console.log(name + ' : PASS');
}

/** Hash fixture artifacts only. */
function digest(file) { return createHash('sha256').update(fs.readFileSync(file)).digest('hex').toUpperCase(); }

/** Count inert Docker executions. */
function calls() { return fs.existsSync(marker) ? fs.readFileSync(marker, 'utf8').trim().split('\n').filter(Boolean).length : 0; }

/** Run the real managed Bash startup with an isolated home and simulated SSH identity. */
function startup(body = 'printf READY', extraEnvironment = {}) {
    return run(bash, ['--noprofile', '--norc', '-c', 'source "$HOME/.dotfiles/.bashrc"; ' + body],
        { SSH_CONNECTION: 'inert ssh identity', DOTFILES_DOCKER_SSH: 'required', ...extraEnvironment });
}

try {
    const protect = run(powershell, ['-NoProfile', '-CommandWithArgs', '$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User; $acl=[Security.AccessControl.DirectorySecurity]::new(); $acl.SetOwner($owner); $acl.SetAccessRuleProtection($true,$false); $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner,\'FullControl\',\'ContainerInherit,ObjectInherit\',\'None\',\'Allow\')); Set-Acl -LiteralPath $args[0] -AclObject $acl', scratch]);
    check('private-scratch-root', protect.status === 0);
    fs.mkdirSync(local);
    fs.mkdirSync(home, { recursive: true });
    const privateDirectory = path.join(scratch, 'private.ps1');
    fs.writeFileSync(privateDirectory, `param([string] $Path)
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
$security=[Security.AccessControl.DirectorySecurity]::new()
$security.SetOwner($owner)
$security.SetAccessRuleProtection($true,$false)
$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
[void][IO.FileSystemAclExtensions]::CreateDirectory($security,$Path)
`);
    check('private-local-fixture', run(powershell, ['-NoProfile', '-File', privateDirectory, '-Path', hookDirectory]).status === 0);
    check('private-deployment-fixture', run(powershell, ['-NoProfile', '-File', privateDirectory, '-Path', deployment]).status === 0);
    fs.mkdirSync(binary, { recursive: true });
    fs.mkdirSync(installedShell);
    fs.mkdirSync(path.join(deployment, 'docker-config'));
    fs.mkdirSync(path.join(home, '.dotfiles'));
    for (const name of ['.bashrc', '.bashrc.docker-ssh']) fs.copyFileSync(path.join(repository, name), path.join(home, '.dotfiles', name));
    fs.mkdirSync(canonicalShell, { recursive: true });
    fs.writeFileSync(path.join(home, '.dotfiles/.bashrc.ssh-psmux'), '[[ ${PSMUX_SSH_AUTOATTACH-} == 0 ]] || printf ATTACHED\n');
    for (const name of ['Get-TpmDockerEnvironment.ps1', 'Invoke-DockerSshTpm.ps1', 'Enter-DockerSshEnvironment.ps1']) {
        fs.copyFileSync(path.join(shell, name), path.join(installedShell, name));
        fs.copyFileSync(path.join(shell, name), path.join(canonicalShell, name));
        fs.copyFileSync(path.join(shell, name), path.join(hookDirectory, name));
    }
    const probe = path.join(scratch, 'probe');
    fs.mkdirSync(probe);
    fs.writeFileSync(path.join(probe, 'Probe.csproj'), '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0-windows</TargetFramework><AssemblyName>docker-credential-ssh-tpm</AssemblyName><ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>');
    // The inert child observes only fixture input/environment; it contains no Docker, credential or TPM operation.
    fs.writeFileSync(path.join(probe, 'Program.cs'), `using System.Text; using System.Text.Json;
var input = Environment.GetEnvironmentVariable("ROUTING_PROBE_READ") == "1" ? Console.In.ReadToEnd() : "";
var record = JsonSerializer.Serialize(new { Arguments=args, Input=input, Config=Environment.GetEnvironmentVariable("DOCKER_CONFIG"), Store=Environment.GetEnvironmentVariable("DOCKER_SSH_HELPER_ROOT") });
File.AppendAllText(Environment.GetEnvironmentVariable("ROUTING_PROBE_MARKER")!, record+"\\n");
var bytes=Encoding.UTF8.GetBytes(record); Console.OpenStandardOutput().Write(bytes);
return int.TryParse(Environment.GetEnvironmentVariable("ROUTING_PROBE_EXIT"), out var code) ? code : 0;
`);
    check('inert-probe-build', run(path.join(process.env.ProgramFiles, 'dotnet/dotnet.exe'), ['build', path.join(probe, 'Probe.csproj'), '-c', 'Release', '--source', path.join(scratch, 'empty-feed'), '--nologo']).status === 0);
    const manifest = {};
    for (const base of ['docker-credential-ssh-tpm', 'docker']) {
        const source = base === 'docker' ? path.join(root, 'src/DockerSshDispatcher/bin/Release/net10.0-windows') : path.join(probe, 'bin/Release/net10.0-windows');
        for (const extension of ['.exe', '.dll', '.deps.json', '.runtimeconfig.json']) {
            const name = base + extension;
            fs.copyFileSync(path.join(source, name), path.join(binary, name));
            manifest[name] = digest(path.join(binary, name));
        }
    }
    for (const name of ['Get-TpmDockerEnvironment.ps1', 'Invoke-DockerSshTpm.ps1']) manifest['shell/' + name] = digest(path.join(installedShell, name));
    const manifestPath = path.join(deployment, 'installed-manifest.json');
    fs.writeFileSync(manifestPath, JSON.stringify(manifest));
    const settingsPath = path.join(deployment, 'settings.json');
    const settings = { Version: 1, State: 'READY', HelperKind: 'tpm', HelperVersion: '0.5.0', PowerShellExecutable: powershell, DockerExecutable: path.join(binary, 'docker-credential-ssh-tpm.exe'), EngineEndpoint: 'npipe:////./pipe/inertProbe' };
    fs.writeFileSync(settingsPath, JSON.stringify(settings));
    const configPath = path.join(deployment, 'docker-config/config.json');
    fs.writeFileSync(configPath, '{"credsStore":"ssh-tpm"}');
    fs.writeFileSync(selector, JSON.stringify({ Version: 1, DeploymentRoot: deployment }));
    const direct = run(dispatcher, ['version', '日本語 space', '', '-x'], { ROUTING_PROBE_READ: '1', ROUTING_PROBE_EXIT: '17' }, 'inert stdin\n');
    check('native-dispatcher-exit-and-streams', direct.status === 17);
    const record = JSON.parse(direct.stdout);
    check('native-argv-empty-unicode-boundaries', JSON.stringify(record.Arguments.slice(4)) === JSON.stringify(['version', '日本語 space', '', '-x']));
    check('native-stdin-preserved', record.Input === 'inert stdin\n');
    check('native-config-helper-routing', record.Config === path.join(deployment, 'docker-config') && record.Store === path.join(deployment, 'store'));
    fs.writeFileSync(settingsPath, JSON.stringify({ ...settings, State: 'STAGED' }));
    const beforeStaged = calls();
    check('native-staged-without-managed-marker-rejected', run(dispatcher, ['version'], { DOCKER_SSH_MANAGED: '' }).status !== 0 && calls() === beforeStaged);
    check('managed-launcher-staged-rejected', run(powershell, ['-NoProfile', '-File', path.join(installedShell, 'Invoke-DockerSshTpm.ps1'), '-DeploymentRoot', deployment, 'version'], { DOCKER_SSH_MANAGED: '1' }).status !== 0 && calls() === beforeStaged);
    fs.writeFileSync(settingsPath, JSON.stringify(settings));
    const initialized = startup('pwsh.exe -NoProfile -Command "& docker version"');
    check('bash-pwsh-native-grandchild', initialized.status === 0 && initialized.stdout.includes('"Config"') && !initialized.stdout.includes('ATTACHED'));
    for (const session of ['', 'old-gui', 'old-tpm', 'new-managed']) {
        check('managed-no-autoattach-' + (session || 'new-root'), startup('printf READY', { PSMUX_SESSION: session }).status === 0 && !startup('printf READY', { PSMUX_SESSION: session }).stdout.includes('ATTACHED'));
    }
    const restored = startup('docker-ssh-restore-environment; [[ ! ${DOCKER_CONFIG+x} && ${PSMUX_SSH_AUTOATTACH+x} && -z $PSMUX_SSH_AUTOATTACH ]]', { DOCKER_CONFIG: undefined, PSMUX_SSH_AUTOATTACH: '' });
    check('restore-unset-versus-empty', restored.status === 0);
    check('gui-unmanaged-preserved', startup('printf READY', { SSH_CONNECTION: '', DOTFILES_DOCKER_SSH: 'invalid' }).stdout.includes('ATTACHED'));
    check('ssh-unmanaged-preserved', startup('printf READY', { DOTFILES_DOCKER_SSH: '' }).stdout.includes('ATTACHED'));
    check('ssh-invalid-mode-exits-parent', !startup('printf MUST_NOT_RUN', { DOTFILES_DOCKER_SSH: 'invalid' }).stdout.includes('MUST_NOT_RUN'));
    for (const name of ['DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_AUTH_CONFIG', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH', 'DOCKER_CONFIG', 'DOCKER_SSH_HELPER_ROOT']) {
        const before = calls();
        check('reject-environment-' + name, run(dispatcher, ['version'], { [name]: 'conflict' }).status !== 0 && calls() === before);
    }
    for (const argument of ['--config=x', '--host=x', '--context=x', '-Hpipe', '-ccontext', '-it', '-DeploymentRoot']) {
        const before = calls();
        check('reject-override-' + argument, run(dispatcher, ['version', argument]).status !== 0 && calls() === before);
    }
    const definitionProbe = path.join(scratch, 'definitions-only.ps1');
    const definitionAccess = path.join(scratch, 'definitions-filesystem-access');
    fs.writeFileSync(definitionProbe, `param([string] $Reader,[string] $Marker)
<# .SYNOPSIS Get-Item records forbidden filesystem access during definition loading or invalid path rejection. #>
function Get-Item { param([string] $LiteralPath,[switch] $Force) [IO.File]::WriteAllText($Marker,'access'); throw 'Filesystem access forbidden.' }
<# .SYNOPSIS Get-Acl records forbidden security access during definition loading or invalid path rejection. #>
function Get-Acl { param([string] $LiteralPath) [IO.File]::WriteAllText($Marker,'access'); throw 'Filesystem access forbidden.' }
<# .SYNOPSIS Get-Content records forbidden metadata reads during definition-only loading. #>
function Get-Content { param([string] $LiteralPath,[switch] $Raw) [IO.File]::WriteAllText($Marker,'access'); throw 'Filesystem access forbidden.' }
. $Reader -DefinitionsOnly
if (-not (Get-Command Assert-TpmDeploymentPath -CommandType Function -ErrorAction SilentlyContinue)) { exit 2 }
foreach ($invalid in @('\\\\inert.invalid\\share','\\\\?\\C:\\inert','relative')) {
    try { Assert-TpmDeploymentPath -Path $invalid; exit 3 } catch { }
}
`);
    const definitions = run(powershell, ['-NoProfile', '-File', definitionProbe, '-Reader', path.join(canonicalShell, 'Get-TpmDockerEnvironment.ps1'), '-Marker', definitionAccess]);
    check('definitions-only-and-invalid-paths-no-filesystem-access', definitions.status === 0 && definitions.stdout === '' && !fs.existsSync(definitionAccess));
    const unsafeSelector = path.join(scratch, 'unsafe-selector.json');
    const deploymentAccess = path.join(scratch, 'unsafe-selector-deployment-access');
    const dummyDeployment = path.join(scratch, 'never-accessed-deployment');
    fs.writeFileSync(unsafeSelector, JSON.stringify({ Version: 1, DeploymentRoot: dummyDeployment }));
    check('unsafe-selector-fixture', run(powershell, ['-NoProfile', '-CommandWithArgs', '$acl=Get-Acl -LiteralPath $args[0]; $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new(\'S-1-1-0\'),\'Read\',\'Allow\')); Set-Acl -LiteralPath $args[0] -AclObject $acl', unsafeSelector]).status === 0);
    const selectorProbe = path.join(scratch, 'unsafe-selector-order.ps1');
    fs.writeFileSync(selectorProbe, `param([string] $Enter,[string] $Selector,[string] $Deployment,[string] $Marker)
<# .SYNOPSIS Get-Content observes selector reads while forwarding other local file reads to the real cmdlet. #>
function Get-Content { param([string] $LiteralPath,[switch] $Raw) if ($LiteralPath -eq $Selector) { [IO.File]::WriteAllText($Marker,'selector-read') }; Microsoft.PowerShell.Management\\Get-Content @PSBoundParameters }
<# .SYNOPSIS Get-Item observes selected deployment access while forwarding selector ACL prerequisites locally. #>
function Get-Item { param([string] $LiteralPath,[switch] $Force) if ($LiteralPath.StartsWith($Deployment)) { [IO.File]::WriteAllText($Marker,'deployment-access') }; Microsoft.PowerShell.Management\\Get-Item @PSBoundParameters }
& $Enter -SelectorPath $Selector
exit $LASTEXITCODE
`);
    const unsafe = run(powershell, ['-NoProfile', '-File', selectorProbe, '-Enter', path.join(canonicalShell, 'Enter-DockerSshEnvironment.ps1'), '-Selector', unsafeSelector, '-Deployment', dummyDeployment, '-Marker', deploymentAccess]);
    check('unsafe-selector-rejected-before-read-or-deployment-access', unsafe.status !== 0 && !fs.existsSync(deploymentAccess));
    const selected = fs.readFileSync(selector);
    for (const value of ['{', '{}', JSON.stringify({ Version: 1, DeploymentRoot: 'relative' })]) {
        fs.writeFileSync(selector, value);
        check('malformed-selector-' + results.length, startup('printf MUST_NOT_RUN').status !== 0);
    }
    fs.writeFileSync(selector, selected);
    const hook = path.join(hookDirectory, 'Enter-DockerSshEnvironment.ps1');
    fs.renameSync(hook, hook + '.saved');
    check('required-missing-hook-exits-parent', startup('printf MUST_NOT_RUN').status !== 0);
    fs.renameSync(hook + '.saved', hook);
    const localOverride = path.join(home, '.bashrc.local');
    fs.writeFileSync(localOverride, "alias docker='printf invalid'\n");
    check('existing-alias-fails-required-shell', startup('printf MUST_NOT_RUN').status !== 0);
    fs.unlinkSync(localOverride);
    fs.renameSync(selector, selector + '.saved');
    check('required-missing-selector-exits-parent', startup('printf MUST_NOT_RUN').status !== 0 && !startup('printf MUST_NOT_RUN').stdout.includes('MUST_NOT_RUN'));
    fs.renameSync(selector + '.saved', selector);
    fs.renameSync(dispatcher, dispatcher + '.saved');
    check('required-missing-dispatcher-exits-parent', startup('printf MUST_NOT_RUN').status !== 0);
    fs.renameSync(dispatcher + '.saved', dispatcher);
    for (const file of [configPath, manifestPath, path.join(installedShell, 'Invoke-DockerSshTpm.ps1')]) {
        const original = fs.readFileSync(file);
        fs.writeFileSync(file, 'invalid');
        const before = calls();
        check('reject-damaged-' + path.basename(file), run(dispatcher, ['version']).status !== 0 && calls() === before);
        fs.writeFileSync(file, original);
    }
    fs.writeFileSync(settingsPath, JSON.stringify({ ...settings, DockerExecutable: dispatcher }));
    check('recursive-real-docker-rejected', run(dispatcher, ['version']).status !== 0);
    fs.writeFileSync(settingsPath, JSON.stringify(settings));
    const beforeChangedState = calls();
    fs.writeFileSync(settingsPath, JSON.stringify({ ...settings, State: 'STAGED' }));
    check('ready-to-staged-native-rejected', run(dispatcher, ['version']).status !== 0 && calls() === beforeChangedState);
    fs.writeFileSync(settingsPath, JSON.stringify(settings));
    for (const property of ['registrytoken', 'RegistryToken']) {
        fs.writeFileSync(configPath, JSON.stringify({ credsStore: 'ssh-tpm', auths: { 'registry.invalid': { [property]: 'inert-bearer' } } }));
        const beforeToken = calls();
        check('inline-' + property + '-rejected', run(dispatcher, ['version']).status !== 0 && startup('printf MUST_NOT_RUN').status !== 0 && calls() === beforeToken);
    }
    fs.writeFileSync(configPath, '{"credsStore":"ssh-tpm"}');
    const bootstrapExecuted = path.join(scratch, 'untrusted-bootstrap-executed');
    for (const name of ['Enter-DockerSshEnvironment.ps1', 'Get-TpmDockerEnvironment.ps1']) {
        const publicPath = path.join(hookDirectory, name);
        const original = fs.readFileSync(publicPath);
        fs.writeFileSync(publicPath, '[IO.File]::WriteAllText($env:ROUTING_BOOTSTRAP_EXECUTED,"bad"); [Console]::Write("forged`nexe`nbin`nconfig`nstore`nendpoint")');
        const beforeForged = calls();
        check('untrusted-public-' + name + '-never-executed', startup('printf MUST_NOT_RUN', { ROUTING_BOOTSTRAP_EXECUTED: bootstrapExecuted }).status !== 0 && !fs.existsSync(bootstrapExecuted) && calls() === beforeForged);
        fs.writeFileSync(publicPath, original);
    }
    const canonicalEnter = path.join(canonicalShell, 'Enter-DockerSshEnvironment.ps1');
    fs.renameSync(canonicalEnter, canonicalEnter + '.saved');
    check('missing-canonical-bootstrap-exits-parent', startup('printf MUST_NOT_RUN').status !== 0);
    fs.renameSync(canonicalEnter + '.saved', canonicalEnter);
    const publicEnter = path.join(hookDirectory, 'Enter-DockerSshEnvironment.ps1');
    const weakPublic = run(powershell, ['-NoProfile', '-CommandWithArgs', '$acl=Get-Acl -LiteralPath $args[0]; $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new(\'S-1-1-0\'),\'WriteData\',\'Allow\')); Set-Acl -LiteralPath $args[0] -AclObject $acl', publicEnter]);
    check('weakened-public-bootstrap-fixture', weakPublic.status === 0);
    const beforeWeakPublic = calls();
    check('cross-user-writable-public-bootstrap-rejected', startup('printf MUST_NOT_RUN').status !== 0 && calls() === beforeWeakPublic);
    check('fixture-weak-acl-applied', run(powershell, ['-NoProfile', '-CommandWithArgs', '$acl=Get-Acl -LiteralPath $args[0]; $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new(\'S-1-1-0\'),\'Read\',\'Allow\')); Set-Acl -LiteralPath $args[0] -AclObject $acl', configPath]).status === 0);
    const beforeAcl = calls();
    check('unsafe-config-acl-rejected', run(dispatcher, ['version']).status !== 0 && calls() === beforeAcl);
    console.log(`managed-routing : PASS; assertions=${results.length}; real-docker=0; tpm=0`);
} finally {
    fs.writeFileSync(path.join(scratch, 'results.json'), JSON.stringify(results));
    console.log('Evidence: ' + scratch);
}
