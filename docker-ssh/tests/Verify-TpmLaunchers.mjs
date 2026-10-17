import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const moduleRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const shell = path.join(moduleRoot, 'chezmoi/AppData/Local/Dotfiles/DockerSsh');
const scratch = fs.mkdtempSync(path.join(process.env.LOCALAPPDATA, 'docker-ssh-issue142-lab-launcher-review-'));
const deployment = path.join(scratch, '日本語 環境');
const marker = path.join(scratch, 'mock-process-calls.jsonl');
const bash = path.join(process.env.ProgramFiles, 'Git/usr/bin/bash.exe');
const results = [];
const originalConfig = path.join(os.homedir(), '.docker/config.json');
const originalHash = fs.existsSync(originalConfig) ? digest(originalConfig) : null;
const settingsPath = path.join(deployment, 'settings.json');
const configPath = path.join(deployment, 'docker-config/config.json');

/** Hash public fixture or configuration bytes without logging their contents. */
function digest(file) { return createHash('sha256').update(fs.readFileSync(file)).digest('hex').toUpperCase(); }

/** Run only a bounded mock, compiler, reader or isolated shell; timeout is never retried. */
function run(executable, arguments_, timeout = 60000, extraEnvironment = {}) {
    const child = spawnSync(executable, arguments_, { encoding: 'utf8', windowsHide: true, timeout, maxBuffer: 1048576,
        env: { ...process.env, DOCKER_TLS_VERIFY: '', DOCKER_CERT_PATH: '', DOCKER_SSH_LAUNCHER_TEST_MARKER: marker, ...extraEnvironment } });
    assert.equal(child.error, undefined, 'Mock subprocess failed or timed out; no retry');
    return child;
}

/** Log fixed assertion names only; child output remains private evidence. */
function check(name, passed) {
    results.push({ name, status: passed ? 'PASS' : 'FAIL' });
    assert.equal(passed, true, name);
    console.log(name + ' : PASS');
}

/** Invoke a tracked PowerShell entrypoint with explicit arguments. */
function powershell(file, arguments_) { return run('pwsh.exe', ['-NoProfile', '-File', file, ...arguments_]); }

/** Run the real Bash entrypoint while replacing Docker with the compiled inert fixture. */
function bashLaunch(extraBody = '', extraArguments = []) {
    return run(bash, ['--noprofile', '--norc', '-c', 'source "$1" || exit; DOCKER_SSH_DEPLOYMENT=$2; ' + extraBody + '\ndocker-ssh login registry.invalid',
        'launcher-test', path.join(shell, 'docker-ssh.bash').replaceAll('\\', '/'), deployment.replaceAll('\\', '/'), ...extraArguments]);
}

/** Count only mock process launches, never a real Docker or TPM operation. */
function invocationCount() { return fs.existsSync(marker) ? fs.readFileSync(marker, 'utf8').trim().split('\n').filter(Boolean).length : 0; }

/** Require all ordinary entrypoints to reject unsafe fixtures before process execution or secret prompting. */
function rejectedEverywhere(name) {
    const before = invocationCount();
    const responses = [bashLaunch(), powershell(path.join(shell, 'Invoke-DockerSshTpm.ps1'), ['-DeploymentRoot', deployment, 'version']),
        powershell(path.join(shell, 'Manage-TpmCredential.ps1'), ['-DeploymentRoot', deployment, '-Operation', 'list'])];
    check(name + '/bash-powershell-manager-rejected', responses.every(response => response.status !== 0));
    check(name + '/no-child-started', invocationCount() === before);
    const store = powershell(path.join(shell, 'Manage-TpmCredential.ps1'), ['-DeploymentRoot', deployment, '-Operation', 'store', '-Registry', 'registry.invalid', '-Username', 'mock-user']);
    check(name + '/store-rejected-before-prompt', store.status !== 0 && !store.stdout.includes('Token/password') && invocationCount() === before);
    const erase = powershell(path.join(shell, 'Manage-TpmCredential.ps1'), ['-DeploymentRoot', deployment, '-Operation', 'erase', '-Registry', 'registry.invalid']);
    check(name + '/erase-rejected-before-child', erase.status !== 0 && invocationCount() === before);
}

try {
    const fixtureSetup = path.join(scratch, 'create-private-fixture.ps1');
    fs.writeFileSync(fixtureSetup, `param([string] $Path)
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
$security=[Security.AccessControl.DirectorySecurity]::new()
$security.SetOwner($owner)
$security.SetAccessRuleProtection($true,$false)
$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
[void][IO.FileSystemAclExtensions]::CreateDirectory($security,$Path)
`);
    check('private-unicode-fixture', powershell(fixtureSetup, ['-Path', deployment]).status === 0);
    const project = path.join(scratch, 'probe');
    fs.mkdirSync(project);
    fs.writeFileSync(path.join(project, 'Probe.csproj'), '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0-windows</TargetFramework><AssemblyName>docker-credential-ssh-tpm</AssemblyName><ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>');
    // The inert probe records public arguments and routing only; it has no Docker, TPM or credential implementation.
    fs.writeFileSync(path.join(project, 'Program.cs'), `using System.Text.Json;
var marker = Environment.GetEnvironmentVariable("DOCKER_SSH_LAUNCHER_TEST_MARKER");
if (marker is null) return 9;
File.AppendAllText(marker, JsonSerializer.Serialize(new { Arguments = args, Config = Environment.GetEnvironmentVariable("DOCKER_CONFIG"), Store = Environment.GetEnvironmentVariable("DOCKER_SSH_HELPER_ROOT") }) + "\\n");
Console.Write(args.Length == 1 && args[0] == "list" ? "{}" : "mock-process : PASS");
return 0;
`);
    check('build-inert-probe', run('dotnet.exe', ['build', path.join(project, 'Probe.csproj'), '-c', 'Release', '--nologo'], 300000).status === 0);
    const binary = path.join(deployment, 'bin/0.4.0');
    fs.mkdirSync(binary, { recursive: true });
    fs.mkdirSync(path.dirname(configPath));
    const manifest = {};
    for (const extension of ['.exe', '.dll', '.deps.json', '.runtimeconfig.json']) {
        const name = 'docker-credential-ssh-tpm' + extension;
        fs.copyFileSync(path.join(project, 'bin/Release/net10.0-windows', name), path.join(binary, name));
        manifest[name] = digest(path.join(binary, name));
    }
    fs.writeFileSync(path.join(deployment, 'installed-manifest.json'), JSON.stringify(manifest));
    const settings = { Version: 1, State: 'STAGED', HelperKind: 'tpm', HelperVersion: '0.4.0', InstallationId: randomUUID().replaceAll('-', ''),
        DockerExecutable: path.join(binary, 'docker-credential-ssh-tpm.exe'), EngineEndpoint: 'npipe:////./pipe/mockDockerOnly' };
    fs.writeFileSync(settingsPath, JSON.stringify(settings));
    fs.writeFileSync(configPath, '{"credsStore":"ssh-tpm"}');
    const reader = path.join(shell, 'Get-TpmDockerEnvironment.ps1');
    const metadata = run('pwsh.exe', ['-NoProfile', '-CommandWithArgs',
        '[Console]::OutputEncoding=[Text.Encoding]::GetEncoding(932); & $args[0] -DeploymentRoot $args[1]', reader, deployment]);
    const fields = metadata.stdout.split('\n');
    check('unicode-metadata-explicit-utf8-after-cp932', metadata.status === 0 && fields.length === 5 && fields[0] === settings.DockerExecutable && fields[2] === path.dirname(configPath) && !metadata.stdout.includes('\ufffd') && !metadata.stdout.includes('\r'));
    check('unicode-git-bash-login-mock', bashLaunch().status === 0);
    const call = JSON.parse(fs.readFileSync(marker, 'utf8').trim().split('\n').at(-1));
    check('unicode-config-and-env-match', call.Arguments.includes('--config=' + path.dirname(configPath).replaceAll('\\', '/')) && call.Config === path.dirname(configPath).replaceAll('\\', '/'));
    check('powershell-launcher-mock', powershell(path.join(shell, 'Invoke-DockerSshTpm.ps1'), ['-DeploymentRoot', deployment, 'version']).status === 0);
    check('credential-manager-list-mock', powershell(path.join(shell, 'Manage-TpmCredential.ps1'), ['-DeploymentRoot', deployment, '-Operation', 'list']).status === 0);
    const wrongDirectory = path.join(scratch, '文字化けした別設定');
    fs.mkdirSync(wrongDirectory);
    fs.writeFileSync(path.join(wrongDirectory, 'config.json'), '{"credsStore":"ssh-tpm"}');
    const beforeWrong = invocationCount();
    const altered = bashLaunch(`wrong_config=$3
pwsh.exe() {
    if [[ " $* " == *" -NoOutput "* ]]; then command pwsh.exe "$@"; return; fi
    local response; response=$(command pwsh.exe "$@") || return
    local -a output; mapfile -t output <<< "$response"
    output[2]=$(cygpath -am -- "$wrong_config") || return
    printf '%s\\n' "\${output[@]}"
}`, [wrongDirectory.replaceAll('\\', '/')]);
    check('different-existing-config-rejected-before-docker', altered.status !== 0 && altered.stderr.includes('TPM Docker deployment validation failed') && invocationCount() === beforeWrong);
    for (const [name, config] of [['missing-helper-routing', '{}'], ['wrong-helper-routing', '{"credsStore":"desktop"}'],
        ['per-registry-routing', '{"credsStore":"ssh-tpm","credHelpers":{"registry.invalid":"desktop"}}']]) {
        fs.writeFileSync(configPath, config);
        rejectedEverywhere(name);
    }
    fs.unlinkSync(configPath);
    rejectedEverywhere('missing-config');
    fs.writeFileSync(configPath, '{"credsStore":"ssh-tpm"}');
    fs.writeFileSync(settingsPath, JSON.stringify({ ...settings, State: 'DISABLED' }));
    rejectedEverywhere('disabled-state');
    check('disabled-reader-still-available-for-removal', powershell(reader, ['-DeploymentRoot', deployment, '-AllowDisabled', '-NoOutput']).status === 0);
    fs.writeFileSync(settingsPath, JSON.stringify({ ...settings, HelperVersion: '99.0.0' }));
    rejectedEverywhere('unsupported-helper-version');
    fs.writeFileSync(settingsPath, JSON.stringify(settings));
    fs.writeFileSync(path.join(deployment, 'installed-manifest.json'), JSON.stringify({ ...manifest, 'docker-credential-ssh-tpm.dll': '0'.repeat(64) }));
    rejectedEverywhere('helper-hash-mismatch');
    fs.writeFileSync(path.join(deployment, 'installed-manifest.json'), JSON.stringify(manifest));
    const aclScript = path.join(scratch, 'weaken-fixture-acl.ps1');
    fs.writeFileSync(aclScript, `param([string] $Path)
$acl=Get-Acl -LiteralPath $Path
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'Read','Allow'))
Set-Acl -LiteralPath $Path -AclObject $acl
`);
    check('fixture-only-untrusted-read-grant', powershell(aclScript, ['-Path', configPath]).status === 0);
    rejectedEverywhere('unsafe-config-acl');
    for (const invalidId of ['A'.repeat(32), 'a'.repeat(31), 'g'.repeat(32), 'a'.repeat(32) + '\n']) {
        const invalidDestination = path.join(scratch, 'must-not-be-created');
        const init = powershell(path.join(moduleRoot, 'scripts/Initialize-DockerSshTpm.ps1'), ['-PackageRoot', path.join(scratch, 'nonexistent-package'), '-DestinationRoot', invalidDestination,
            '-InstallationId', invalidId, '-Mode', 'permanent', '-EngineEndpoint', 'npipe:////./pipe/mockDockerOnly', '-Execute', '-AcknowledgePermanent']);
        const remove = powershell(path.join(moduleRoot, 'scripts/Remove-DockerSshTpm.ps1'), ['-DestinationRoot', invalidDestination, '-InstallationId', invalidId, '-Mode', 'permanent', '-Execute']);
        check('invalid-id-' + results.length + '/init-and-remove-rejected-before-placement', init.status !== 0 && remove.status !== 0 && !fs.existsSync(invalidDestination));
        if (invalidId === 'A'.repeat(32)) check('uppercase-id-explicit-case-sensitive-rejection', init.stderr.includes('32 lowercase hexadecimal') && remove.stderr.includes('32 lowercase hexadecimal'));
    }
    const legacy = run(bash, ['--noprofile', '--norc', '-c', `id=$(pwsh.exe -NoProfile -Command '[Guid]::NewGuid().ToString("N")'); printf 'Length=%s;CR=' "\${#id}"; [[ "$id" == *$'\\r'* ]] && printf YES || printf NO`]);
    check('legacy-guid-command-measured', legacy.status === 0 && /^Length=\d+;CR=(YES|NO)$/.test(legacy.stdout));
    console.log('legacy-guid-observation : ' + legacy.stdout);
    const robust = run(bash, ['--noprofile', '--norc', '-c', `id=$(pwsh.exe -NoProfile -Command '[Console]::Write([Guid]::NewGuid().ToString("N"))'); [[ "$id" =~ ^[a-f0-9]{32}$ ]]`]);
    check('newline-independent-guid-command', robust.status === 0);
    check('original-desktop-config-preserved', (fs.existsSync(originalConfig) ? digest(originalConfig) : null) === originalHash);
    console.log('tpm-launcher-regression : PASS; assertions=' + results.length + '; actual-docker=0; native-key-operations=0; registry=NONE');
} finally {
    fs.writeFileSync(path.join(scratch, 'results.json'), JSON.stringify({ results, docker: 0, nativeKeyOperations: 0, registry: 'NONE', otherMachine: 'UNTESTED' }, null, 2));
    console.log('Evidence: ' + scratch);
}
