import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const powershell = process.env.ISSUE185_PWSH;
assert.ok(process.platform === 'win32' && powershell, 'Windows and explicit PowerShell 7.5+ ISSUE185_PWSH required');
const runtimeProbe = spawnSync(powershell, ['-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()'],
    { encoding: 'utf8', windowsHide: true, timeout: 10000, maxBuffer: 65536 });
assert.equal(runtimeProbe.error, undefined, 'PowerShell runtime probe must finish');
assert.equal(runtimeProbe.status, 0, 'PowerShell runtime probe must succeed');
const runtimeVersion = runtimeProbe.stdout.trim();
assert.match(runtimeVersion, /^\d+\.\d+\.\d+(?:[-+].*)?$/, 'PowerShell runtime version required');
const [runtimeMajor, runtimeMinor] = runtimeVersion.split('.').map(Number);
assert.ok(runtimeMajor > 7 || (runtimeMajor === 7 && runtimeMinor >= 5), 'PowerShell 7.5 or newer is required');
console.log(`PowerShell runtime: ${runtimeVersion}`);
const bash = path.join(process.env.ProgramFiles, 'Git/usr/bin/bash.exe');
// Deployment validation rejects replaceable Temp ancestors; use a private root beneath LocalAppData.
const scratch = fs.mkdtempSync(path.join(process.env.LOCALAPPDATA, 'docker-ssh-managed-bootstrap-'));
const home = path.join(scratch, 'Home with spaces');
const local = path.join(scratch, 'Local');
const deployment = path.join(local, 'fixture 日本語 deployment');
const publicRoot = path.join(local, 'Dotfiles/DockerSsh');
const sourceRoot = path.join(repository, 'docker-ssh/chezmoi/AppData/Local/Dotfiles/DockerSsh');
const checkout = path.join(home, '.dotfiles');
const canonical = path.join(checkout, 'docker-ssh/chezmoi/AppData/Local/Dotfiles/DockerSsh');
const binary = path.join(deployment, 'bin/0.5.0');
const environment = { ...process.env, HOME: home.replaceAll('\\', '/'), USERPROFILE: home, LOCALAPPDATA: local,
    TEMP: scratch, TMP: scratch, DOCKER_CONFIG: '', DOCKER_HOST: '', DOCKER_CONTEXT: '', DOCKER_AUTH_CONFIG: '',
    DOCKER_TLS_VERIFY: '', DOCKER_CERT_PATH: '', DOCKER_SSH_HELPER_ROOT: '', DOCKER_SSH_MANAGED: '',
    DOCKER_SSH_DEPLOYMENT: '', SSH_CONNECTION: 'synthetic ssh', DOTFILES_DOCKER_SSH: '',
    GH_TOKEN: '', GITHUB_TOKEN: '', TMUX: '', PSMUX_SSH_AUTOATTACH: '', MSYS2_ENV_CONV_EXCL: '' };
let assertions = 0;

/** Run a bounded shell or parser with synthetic metadata, never Docker or credential operations. */
function run(executable, arguments_, overrides = {}, timeout = 60000) {
    const child = spawnSync(executable, arguments_, { env: { ...environment, ...overrides },
        encoding: 'utf8', windowsHide: true, timeout, maxBuffer: 1048576 });
    assert.equal(child.error, undefined, 'Fixture process must finish');
    return child;
}

/** Require a named property without printing process output or environment values. */
function check(name, condition) {
    assert.equal(condition, true, name);
    assertions++;
    console.log(name + ' : PASS');
}

/** Exercise the actual checkout startup under a synthetic SSH home. */
function startup(body = 'printf READY', interactive = false, overrides = {}) {
    return run(bash, ['--noprofile', '--norc', interactive ? '-ic' : '-c',
        'source "$HOME/.dotfiles/.bashrc"; ' + body], overrides);
}

/** Hash only inert fixture files for the synthetic installation manifest. */
function digest(file) {
    return createHash('sha256').update(fs.readFileSync(file)).digest('hex').toUpperCase();
}

/** Compare only drive-absolute Windows paths; separators and case follow the fixture volume's Windows semantics. */
function windowsPathIdentity(value) {
    assert.equal(typeof value, 'string');
    assert.match(value, /^[A-Za-z]:[\\/]/);
    assert.doesNotMatch(value, /["\r\n\0]/);
    return path.win32.normalize(value).toLowerCase();
}

/** Decode exactly one fixed endpoint, one config and the expected verb, rejecting duplicates or unrelated options. */
function fixedRoutingArguments(arguments_) {
    const routing = {};
    for (let index = 0; index < arguments_.length; index++) {
        const argument = arguments_[index];
        if (argument === 'version' && index === arguments_.length - 1) continue;
        const match = /^(--host|--config)(?:=(.*))?$/.exec(argument);
        assert.ok(match, 'Only explicit routing options and version are permitted');
        assert.equal(Object.hasOwn(routing, match[1]), false, 'Duplicate routing option');
        const value = match[2] ?? arguments_[++index];
        assert.ok(value, 'Routing value is required');
        routing[match[1]] = value;
    }
    assert.equal(arguments_.at(-1), 'version');
    assert.deepEqual(Object.keys(routing).sort(), ['--config', '--host']);
    return routing;
}

/** Verify the actual child environment and parsed arguments refer to one exact synthetic deployment. */
function assertChildRouting(observed, deploymentRoot, endpoint) {
    assert.equal(observed.hostPresent || observed.contextPresent || observed.authPresent, false);
    const expectedConfig = windowsPathIdentity(path.join(deploymentRoot, 'docker-config'));
    assert.equal(windowsPathIdentity(observed.config), expectedConfig);
    assert.equal(windowsPathIdentity(observed.store), windowsPathIdentity(path.join(deploymentRoot, 'store')));
    const routing = fixedRoutingArguments(observed.arguments);
    assert.equal(routing['--host'], endpoint);
    assert.equal(windowsPathIdentity(routing['--config']), expectedConfig);
}
/** Temporarily remove a fixture file to model a checkout losing a required dependency. */
function without(file, name) {
    const bytes = fs.readFileSync(file);
    fs.unlinkSync(file);
    try {
        const child = startup('printf MUST_NOT_RUN');
        check(name, child.status !== 0 && !child.stdout.includes('MUST_NOT_RUN'));
    } finally {
        fs.writeFileSync(file, bytes);
    }
}

try {
    const protection = run(powershell, ['-NoProfile', '-CommandWithArgs',
        '$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User; $acl=[Security.AccessControl.DirectorySecurity]::new(); $acl.SetOwner($owner); $acl.SetAccessRuleProtection($true,$false); $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner,"FullControl","ContainerInherit,ObjectInherit","None","Allow")); Set-Acl -LiteralPath $args[0] -AclObject $acl', scratch]);
    check('private-synthetic-root', protection.status === 0);
    for (const directory of [canonical, publicRoot, binary, path.join(deployment, 'shell'), path.join(deployment, 'docker-config')]) {
        fs.mkdirSync(directory, { recursive: true });
    }
    for (const name of ['.bashrc', '.bashrc.docker-ssh']) fs.copyFileSync(path.join(repository, name), path.join(checkout, name));
    fs.writeFileSync(path.join(home, '.bashrc.local'), 'export DOTFILES_DOCKER_SSH=required\n');
    fs.writeFileSync(path.join(checkout, '.bashrc.ssh-psmux'), '[[ ${PSMUX_SSH_AUTOATTACH-} == 0 ]] || printf ATTACHED\n');
    for (const name of ['Enter-DockerSshEnvironment.ps1', 'Get-TpmDockerEnvironment.ps1', 'Invoke-DockerSshTpm.ps1']) {
        for (const destination of [canonical, publicRoot, path.join(deployment, 'shell')]) {
            fs.copyFileSync(path.join(sourceRoot, name), path.join(destination, name));
        }
    }
    // Compile a credential-free native fixture so actual invocation can prove command selection.
    const project = path.join(scratch, 'native-probe');
    const competing = path.join(scratch, 'competing-bin');
    fs.mkdirSync(project);
    fs.mkdirSync(competing);
    fs.mkdirSync(path.join(project, 'empty-feed'));
    fs.writeFileSync(path.join(project, 'Probe.csproj'), '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0-windows</TargetFramework><AssemblyName>docker</AssemblyName><ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>');
    fs.writeFileSync(path.join(project, 'NuGet.Config'), '<configuration><packageSources><clear /></packageSources></configuration>');
    fs.writeFileSync(path.join(project, 'Program.cs'), 'using System.Text; using System.Text.Json;\nConsole.OpenStandardOutput().Write(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new { path = Environment.ProcessPath, arguments = args, config = Environment.GetEnvironmentVariable("DOCKER_CONFIG"), store = Environment.GetEnvironmentVariable("DOCKER_SSH_HELPER_ROOT"), hostPresent = Environment.GetEnvironmentVariables().Contains("DOCKER_HOST"), contextPresent = Environment.GetEnvironmentVariables().Contains("DOCKER_CONTEXT"), authPresent = Environment.GetEnvironmentVariables().Contains("DOCKER_AUTH_CONFIG") })));\n');
    const build = run(path.join(process.env.ProgramFiles, 'dotnet/dotnet.exe'), ['build', path.join(project, 'Probe.csproj'),
        '-c', 'Release', '--source', path.join(project, 'empty-feed'), '--nologo',
        '-p:ImportDirectoryBuildProps=false', '-p:ImportDirectoryBuildTargets=false'],
        { DOTNET_CLI_TELEMETRY_OPTOUT: '1', DOTNET_SKIP_FIRST_TIME_EXPERIENCE: '1' }, 300000);
    check('inert-native-fixture-build', build.status === 0);
    const manifest = {};
    for (const base of ['docker-credential-ssh-tpm', 'docker']) {
        for (const extension of ['.exe', '.dll', '.deps.json', '.runtimeconfig.json']) {
            const name = base + extension;
            if (base === 'docker') {
                const artifact = path.join(project, 'bin/Release/net10.0-windows', name);
                fs.copyFileSync(artifact, path.join(binary, name));
                fs.copyFileSync(artifact, path.join(competing, name));
            } else {
                fs.writeFileSync(path.join(binary, name), 'validator fixture; helper never executed\n');
            }
            manifest[name] = digest(path.join(binary, name));
        }
    }
    for (const name of ['Get-TpmDockerEnvironment.ps1', 'Invoke-DockerSshTpm.ps1']) {
        manifest['shell/' + name] = digest(path.join(deployment, 'shell', name));
    }
    fs.writeFileSync(path.join(deployment, 'installed-manifest.json'), JSON.stringify(manifest));
    fs.writeFileSync(path.join(deployment, 'settings.json'), JSON.stringify({ Version: 1, State: 'READY', HelperKind: 'tpm',
        HelperVersion: '0.5.0', PowerShellExecutable: powershell, DockerExecutable: path.join(competing, 'docker.exe'), EngineEndpoint: 'npipe:////./pipe/inertFixture' }));
    fs.writeFileSync(path.join(deployment, 'docker-config/config.json'), '{"credsStore":"ssh-tpm"}');
    const selector = path.join(publicRoot, 'ssh-environment.json');
    fs.writeFileSync(selector, JSON.stringify({ Version: 1, DeploymentRoot: deployment }));
    const probe = path.join(scratch, 'inheritance.ps1');
    fs.writeFileSync(probe, `param([switch] $Grandchild, [string] $Mode = 'normal')
if ($env:DOCKER_SSH_MANAGED -ne '1' -or $env:DOCKER_CONFIG -ne $env:EXPECTED_CONFIG -or $env:DOCKER_SSH_HELPER_ROOT -ne $env:EXPECTED_STORE -or $env:PSMUX_SSH_AUTOATTACH -ne '0') { exit 2 }
if ($Mode -eq 'alias') { Set-Alias -Name docker -Value Write-Output }
if ($Mode -eq 'function') {
    function docker { <# .SYNOPSIS Provides a harmless same-name command to test function precedence. #> 'SHADOWED' }
}
if ($Mode -eq 'path') { $env:PATH = $env:COMPETING_BIN + [IO.Path]::PathSeparator + $env:PATH }
$selected = @(Get-Command -Name docker -ErrorAction Stop)
if ($selected.Count -ne 1) { exit 8 }
if ($Mode -eq 'alias' -or $Mode -eq 'function') {
    if ($selected[0].CommandType.ToString() -ine $Mode) { exit 8 }
    [Console]::Write('SHADOW_PRECEDENCE_VERIFIED')
    exit 3
}
if ($selected[0].CommandType -ne 'Application') { exit 3 }
if ($Mode -eq 'path') {
    if ($selected[0].Source -ine (Join-Path $env:COMPETING_BIN 'docker.exe')) { exit 8 }
    $executed = docker | ConvertFrom-Json
    if ($executed.path -ine $selected[0].Source) { exit 8 }
    [Console]::Write('PATH_PRECEDENCE_VERIFIED')
    exit 3
}
if ($selected[0].Source -ine $env:EXPECTED_DISPATCHER) { exit 3 }
$candidates = @(Get-Command -Name docker -All -CommandType Application)
if (-not ($candidates.Source -icontains $env:EXPECTED_DISPATCHER) -or -not ($candidates.Source -icontains (Join-Path $env:COMPETING_BIN 'docker.exe'))) { exit 4 }
$executed = docker | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $executed.path -ine $env:EXPECTED_DISPATCHER) { exit 5 }
$explicit = @(Get-Command -Name docker.exe -ErrorAction Stop)
if ($explicit.Count -ne 1 -or $explicit[0].CommandType -ne 'Application' -or $explicit[0].Source -ine $env:EXPECTED_DISPATCHER) { exit 6 }
$executed = docker.exe | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $executed.path -ine $env:EXPECTED_DISPATCHER) { exit 6 }
if (-not $Grandchild) { & $env:ISSUE185_PWSH -NoProfile -File $PSCommandPath -Grandchild; exit $LASTEXITCODE }
[Console]::Write('INHERITED_AND_EXECUTED')
`);
    const expected = { PROBE_SCRIPT: probe, EXPECTED_CONFIG: path.join(deployment, 'docker-config'),
        EXPECTED_STORE: path.join(deployment, 'store'), EXPECTED_DISPATCHER: path.join(binary, 'docker.exe'), COMPETING_BIN: competing };
    const pathName = Object.keys(environment).find(name => name.toUpperCase() === 'PATH');
    environment[pathName] = competing + path.delimiter + environment[pathName];
    for (const interactive of [false, true]) {
        const child = startup('printf BOOTSTRAP_READY; pwsh.exe -NoProfile -File "$PROBE_SCRIPT"', interactive, expected);
        check((interactive ? 'interactive' : 'noninteractive') + '-bootstrap-success', child.stdout.includes('BOOTSTRAP_READY'));
        check((interactive ? 'interactive' : 'noninteractive') + '-resolved-invoked-pwsh-grandchild',
            child.status === 0 && child.stdout.includes('INHERITED_AND_EXECUTED') && !child.stdout.includes('ATTACHED'));
    }
    const managedNames = ['PATH', 'DOCKER_CONFIG', 'DOCKER_SSH_HELPER_ROOT', 'DOCKER_SSH_DEPLOYMENT', 'DOCKER_SSH_MANAGED', 'PSMUX_SSH_AUTOATTACH', 'MSYS2_ENV_CONV_EXCL'];
    const localFile = path.join(home, '.bashrc.local');
    const optIn = 'export DOTFILES_DOCKER_SSH=required\n';
    const routingSnapshot = 'declare -p ' + managedNames.join(' ') + ' 2>/dev/null';
    const verifyUnchangedOnExit = 'before=$(' + routingSnapshot + '); trap \'after=$(' + routingSnapshot + '); [[ $before == "$after" ]] && printf ENVIRONMENT_UNCHANGED\' EXIT\n';
    /** Require the real startup gate to stop before success, native execution or psmux. */
    function rejectedManagedStartup(name, setup, unchanged = true) {
        fs.writeFileSync(localFile, optIn + setup + (unchanged ? verifyUnchangedOnExit : ''));
        const child = startup('printf MUST_NOT_RUN; docker; docker.exe; printf AFTER_COMMANDS');
        check(name, child.status !== 0 && !child.stdout.includes('MUST_NOT_RUN') && !child.stdout.includes('AFTER_COMMANDS')
            && !child.stdout.includes('"path"') && !child.stdout.includes('ATTACHED')
            && (!unchanged || child.stdout.includes('ENVIRONMENT_UNCHANGED')));
        fs.writeFileSync(localFile, optIn);
    }
    for (const name of managedNames) {
        rejectedManagedStartup('managed-readonly-' + name + '-blocks-execution-preserves-parent', 'readonly ' + name + '\n');
        for (const attribute of ['i', 'a', 'n', 'l']) {
            const declaration = attribute === 'n' ? 'declare -n ' + name + '=fixture_reference\n' : 'declare -' + attribute + ' ' + name + '\n';
            rejectedManagedStartup('managed-rejects-' + attribute + '-attribute-' + name, declaration);
        }
    }
    for (const name of ['_dotfiles_docker_ssh_saved', '_dotfiles_docker_ssh_values', '_dotfiles_docker_ssh_set', '_dotfiles_docker_ssh_exported', '_dotfiles_docker_ssh_restore_definition']) {
        rejectedManagedStartup('managed-internal-state-collision-' + name, name + '=collision\n');
    }
    for (const name of ['_dotfiles_docker_ssh_initialize', 'docker-ssh-restore-environment', 'docker', 'docker.exe']) {
        rejectedManagedStartup('managed-function-collision-' + name, name + '() { :; }\n');
    }
    for (const name of ['docker', 'docker.exe']) {
        rejectedManagedStartup('managed-alias-collision-' + name, 'alias ' + name + '=true\n');
    }
    // Inject one operation failure, then permit independent rollback operations to finish.
    for (const name of managedNames) {
        for (const operation of ['assignment', 'export']) {
            const condition = operation === 'assignment' ? '[[ $1 == printf && $2 == -v && $3 == ' + name + ' ]]' : '[[ $1 == export && $2 == ' + name + ' ]]';
            const injection = 'fixture_failed=0\nbuiltin() { if [[ $fixture_failed == 0 ]] && ' + condition + '; then fixture_failed=1; return 87; fi; command builtin "$@"; }\n';
            rejectedManagedStartup('managed-' + operation + '-failure-' + name + '-rolls-back', injection);
        }
    }
    rejectedManagedStartup('managed-hash-reset-failure-rolls-back', 'fixture_failed=0\nbuiltin() { if [[ $fixture_failed == 0 && $1 == hash && $2 == -r ]]; then fixture_failed=1; return 87; fi; command builtin "$@"; }\n');
    // Retain recovery data and attempt later keys when a rollback operation itself fails.
    const rollbackInjection = 'fixture_failed=0\nbuiltin() { if [[ $1 == printf && $2 == -v ]]; then if [[ $fixture_failed == 0 && $3 == DOCKER_SSH_MANAGED ]]; then fixture_failed=1; return 87; fi; if [[ $fixture_failed == 1 && $3 == DOCKER_CONFIG ]]; then return 88; fi; fi; command builtin "$@"; }\n'
        + 'trap \'[[ ${_dotfiles_docker_ssh_saved-} == 1 && ${PSMUX_SSH_AUTOATTACH-} == "" && ${_dotfiles_docker_ssh_values[DOCKER_CONFIG]+x} ]] && printf RECOVERY_RETAINED\' EXIT\n';
    fs.writeFileSync(localFile, optIn + rollbackInjection);
    const incompleteRollback = startup('printf MUST_NOT_RUN; docker; docker.exe');
    check('managed-incomplete-rollback-retains-state-attempts-later-keys-blocks-execution', incompleteRollback.status !== 0
        && incompleteRollback.stdout.includes('RECOVERY_RETAINED') && !incompleteRollback.stdout.includes('MUST_NOT_RUN')
        && !incompleteRollback.stdout.includes('"path"') && incompleteRollback.stderr.includes('rollback incomplete'));
    fs.writeFileSync(localFile, optIn);
    const extensionlessCompetitor = path.join(binary, 'docker');
    fs.writeFileSync(extensionlessCompetitor, '#!/usr/bin/env bash\nprintf COMPETITOR_EXECUTED\n');
    fs.chmodSync(extensionlessCompetitor, 0o755);
    try {
        const shadowed = startup('printf MUST_NOT_RUN; docker; docker.exe');
        check('managed-selected-extensionless-competitor-fails-closed', shadowed.status !== 0
            && !shadowed.stdout.includes('MUST_NOT_RUN') && !shadowed.stdout.includes('COMPETITOR_EXECUTED')
            && !shadowed.stdout.includes('"path"'));
    } finally {
        fs.unlinkSync(extensionlessCompetitor);
    }
    const repeated = startup('before=$(declare -p PATH DOCKER_CONFIG); source "$HOME/.dotfiles/.bashrc.docker-ssh" || exit; [[ $(declare -p PATH DOCKER_CONFIG) == "$before" ]] && printf REPEATED; docker; docker.exe');
    check('managed-repeated-source-keeps-snapshot-and-executes-only-dispatcher', repeated.status === 0 && repeated.stdout.includes('REPEATED')
        && repeated.stdout.split('"path"').length === 3 && !repeated.stdout.includes(competing.replaceAll('\\', '\\\\')));
    fs.writeFileSync(localFile, optIn + 'hash -p "' + competing.replaceAll('\\', '/') + '/docker.exe" docker\n');
    const staleHash = startup('docker; docker.exe');
    check('managed-stale-hash-cleared-before-selection-and-invocation', staleHash.status === 0
        && !staleHash.stdout.includes(competing.replaceAll('\\', '\\\\')) && staleHash.stdout.split('"path"').length === 3);
    fs.writeFileSync(localFile, optIn);
    for (const mode of ['alias', 'function', 'path']) {
        const child = startup('printf BOOTSTRAP_READY; pwsh.exe -NoProfile -File "$PROBE_SCRIPT" -Mode ' + mode, false, expected);
        check(mode + '-competition-observed-without-hiding-bootstrap', child.stdout.includes('BOOTSTRAP_READY') && child.status === 3
            && child.stdout.includes(mode === 'path' ? 'PATH_PRECEDENCE_VERIFIED' : 'SHADOW_PRECEDENCE_VERIFIED'));
    }
    without(path.join(checkout, '.bashrc.docker-ssh'), 'branch-with-missing-overlay-fails-closed');
    without(path.join(canonical, 'Enter-DockerSshEnvironment.ps1'), 'missing-canonical-entry-fails-closed');
    without(selector, 'missing-selector-fails-closed');
    fs.writeFileSync(selector, '{"Version":0}');
    const invalid = startup('printf MUST_NOT_RUN');
    check('invalid-selector-fails-closed', invalid.status !== 0 && !invalid.stdout.includes('MUST_NOT_RUN'));
    check('invalid-selector-diagnostic', invalid.stderr.includes('[DSSH_SELECTOR_INVALID]'));
    fs.writeFileSync(selector, JSON.stringify({ Version: 1, DeploymentRoot: deployment }));
    const publicEntry = path.join(publicRoot, 'Enter-DockerSshEnvironment.ps1');
    fs.appendFileSync(publicEntry, '\n# divergent public bootstrap\n');
    const mismatch = startup('printf MUST_NOT_RUN');
    check('public-canonical-mismatch-fails-closed', mismatch.status !== 0 && !mismatch.stdout.includes('MUST_NOT_RUN'));
    check('public-canonical-mismatch-diagnostic', mismatch.stderr.includes('[DSSH_PUBLIC_COPY_MISMATCH]'));
    fs.copyFileSync(path.join(canonical, 'Enter-DockerSshEnvironment.ps1'), publicEntry);
    // A checkout that loses the gate must fail this suite's positive contract, even if its shell exits successfully.
    const startupFile = path.join(checkout, '.bashrc');
    const original = fs.readFileSync(startupFile, 'utf8');
    const start = original.indexOf('# Host-local opt-in');
    const end = original.indexOf('# Select the SSH overlay', start);
    assert.ok(start >= 0 && end > start, 'Managed gate anchors must exist');
    fs.writeFileSync(startupFile, original.slice(0, start) + original.slice(end));
    const lostGate = startup('pwsh.exe -NoProfile -File "$PROBE_SCRIPT"', false, expected);
    check('branch-losing-gate-detected-by-positive-contract', lostGate.status !== 0 && !lostGate.stdout.includes('INHERITED_AND_EXECUTED'));
    fs.writeFileSync(startupFile, original);
    for (const [name, ssh, mode] of [['gui', '', 'required'], ['unmanaged-ssh', 'synthetic ssh', 'disabled']]) {
        fs.writeFileSync(path.join(home, '.bashrc.local'), 'export DOTFILES_DOCKER_SSH=' + mode + '\n');
        const unmanaged = startup('[[ -z ${DOCKER_SSH_MANAGED-} ]] && printf UNMANAGED', false, { SSH_CONNECTION: ssh });
        check(name + '-unchanged', unmanaged.status === 0 && unmanaged.stdout.includes('UNMANAGED'));
    }
    fs.writeFileSync(path.join(home, '.bashrc.local'), 'export DOTFILES_DOCKER_SSH=invalid\n');
    const invalidMode = startup('printf MUST_NOT_RUN');
    check('invalid-opt-in-fails-closed', invalidMode.status !== 0 && !invalidMode.stdout.includes('MUST_NOT_RUN'));
    fs.writeFileSync(path.join(home, '.bashrc.local'), 'export DOTFILES_DOCKER_SSH=required\nDOCKER_CONFIG=\nexport -n DOCKER_CONFIG\n');
    const restored = startup('docker-ssh-restore-environment; [[ $(declare -p DOCKER_CONFIG) == \'declare -- DOCKER_CONFIG=""\' && $(declare -p DOCKER_SSH_MANAGED) == \'declare -x DOCKER_SSH_MANAGED=""\' && ! ${DOCKER_SSH_HELPER_ROOT+x} ]] && printf RESTORED',
        false, { DOCKER_SSH_HELPER_ROOT: undefined });
    check('restore-correct-names-values-and-export-flags', restored.status === 0 && restored.stdout.includes('RESTORED'));
    // The legacy fixture uses only the inert executable and never opens a vault or invokes a helper.
    const legacy = path.join(local, 'legacy deployment');
    const legacyBinary = path.join(legacy, 'bin/0.4.0');
    fs.mkdirSync(legacyBinary, { recursive: true });
    fs.mkdirSync(path.join(legacy, 'docker-config'));
    const legacyManifest = {};
    for (const extension of ['.exe', '.dll', '.deps.json', '.runtimeconfig.json']) {
        const name = 'docker-credential-ssh-tpm' + extension;
        fs.copyFileSync(path.join(binary, name), path.join(legacyBinary, name));
        legacyManifest[name] = digest(path.join(legacyBinary, name));
    }
    fs.writeFileSync(path.join(legacy, 'installed-manifest.json'), JSON.stringify(legacyManifest));
    fs.writeFileSync(path.join(legacy, 'settings.json'), JSON.stringify({ Version: 1, State: 'READY', HelperKind: 'tpm',
        HelperVersion: '0.4.0', DockerExecutable: path.join(binary, 'docker.exe'), EngineEndpoint: 'npipe:////./pipe/inertLegacy' }));
    fs.writeFileSync(path.join(legacy, 'docker-config/config.json'), '{"credsStore":"ssh-tpm"}');
    const launcher = path.join(sourceRoot, 'Invoke-DockerSshTpm.ps1');
    const conflicts = { DOCKER_HOST: 'npipe:////./pipe/mustNotUse', DOCKER_CONTEXT: 'must-not-use', DOCKER_AUTH_CONFIG: 'synthetic-not-a-credential' };
    const powershellLegacy = run(powershell, ['-NoProfile', '-File', launcher, '-DeploymentRoot', legacy, 'version'], conflicts);
    const bashLegacy = run(bash, ['--noprofile', '--norc', '-c', 'source "$1" || exit; DOCKER_SSH_DEPLOYMENT=$2; docker-ssh version',
        'legacy-fixture', path.join(sourceRoot, 'docker-ssh.bash').replaceAll('\\', '/'), legacy.replaceAll('\\', '/')], conflicts);
    for (const [name, response] of [['powershell', powershellLegacy], ['bash', bashLegacy]]) {
        check('legacy-' + name + '-normalizes-before-validation', response.status === 0);
        const observed = JSON.parse(response.stdout);
        assertChildRouting(observed, legacy, 'npipe:////./pipe/inertLegacy');
        check('legacy-' + name + '-fixed-child-routing-without-inherited-auth', true);
    }
    check('windows-path-comparison-rejects-another-directory', windowsPathIdentity(path.join(legacy, 'docker-config')) !== windowsPathIdentity(path.join(local, 'other/docker-config')));
    assert.throws(() => windowsPathIdentity('C:relative'), /Assertion/);
    assert.throws(() => windowsPathIdentity('"C:/quoted"'), /Assertion/);
    assert.throws(() => fixedRoutingArguments(['--host=wrong', '--host=duplicate', '--config=C:/fixture', 'version']), /Duplicate/);
    check('routing-comparison-rejects-relative-quoted-and-duplicate-options', true);
    const bashParentBody = 'source "$1" || exit; before=$(declare -p DOCKER_HOST DOCKER_CONTEXT DOCKER_AUTH_CONFIG DOCKER_CONFIG DOCKER_SSH_HELPER_ROOT); docker-ssh-activate "$2" || exit; [[ $(declare -p DOCKER_HOST DOCKER_CONTEXT DOCKER_AUTH_CONFIG DOCKER_CONFIG DOCKER_SSH_HELPER_ROOT) == "$before" ]] || exit 21; docker version || exit; docker-ssh-deactivate || exit; [[ $(declare -p DOCKER_HOST DOCKER_CONTEXT DOCKER_AUTH_CONFIG DOCKER_CONFIG DOCKER_SSH_HELPER_ROOT) == "$before" ]] || exit 22';
    const activated = run(bash, ['--noprofile', '--norc', '-c', bashParentBody, 'legacy-fixture',
        path.join(sourceRoot, 'docker-ssh.bash').replaceAll('\\', '/'), legacy.replaceAll('\\', '/')], conflicts);
    check('legacy-activation-run-deactivation-preserves-parent-routing', activated.status === 0);
    assertChildRouting(JSON.parse(activated.stdout), legacy, 'npipe:////./pipe/inertLegacy');
    check('legacy-activation-fixed-child-routing', true);
    const bashFailureBody = 'source "$1" || exit; before=$(declare -p DOCKER_HOST DOCKER_CONTEXT DOCKER_AUTH_CONFIG DOCKER_CONFIG DOCKER_SSH_HELPER_ROOT); if docker-ssh-activate "$2"; then exit 31; fi; if declare -F docker >/dev/null || alias docker >/dev/null 2>&1; then exit 32; fi; if [[ ${_docker_ssh_active-} == 1 || -n ${_docker_ssh_function_definition-} || -n ${DOCKER_SSH_DEPLOYMENT-} ]]; then exit 33; fi; [[ $(declare -p DOCKER_HOST DOCKER_CONTEXT DOCKER_AUTH_CONFIG DOCKER_CONFIG DOCKER_SSH_HELPER_ROOT) == "$before" ]] && printf SAFE_REJECTED';
    const rejectedActivation = run(bash, ['--noprofile', '--norc', '-c', bashFailureBody, 'legacy-fixture',
        path.join(sourceRoot, 'docker-ssh.bash').replaceAll('\\', '/'), legacy.replaceAll('\\', '/')], { ...conflicts, DOCKER_CONFIG: path.join(scratch, 'invalid-config') });
    check('legacy-activation-failure-preserves-parent-and-no-docker-function', rejectedActivation.status === 0 && rejectedActivation.stdout === 'SAFE_REJECTED');
    const readonlyBody = 'source "$1" || exit; readonly DOCKER_SSH_DEPLOYMENT; before=$(declare -p PATH DOCKER_HOST DOCKER_CONTEXT DOCKER_AUTH_CONFIG DOCKER_CONFIG DOCKER_SSH_HELPER_ROOT DOCKER_SSH_DEPLOYMENT); if docker-ssh-activate "$2"; then exit 34; fi; if declare -F docker >/dev/null || alias docker >/dev/null 2>&1; then exit 35; fi; [[ $(declare -p PATH DOCKER_HOST DOCKER_CONTEXT DOCKER_AUTH_CONFIG DOCKER_CONFIG DOCKER_SSH_HELPER_ROOT DOCKER_SSH_DEPLOYMENT) == "$before" && ${_docker_ssh_active-} != 1 && -z ${_docker_ssh_function_definition-} ]] && printf NO_PARTIAL_STATE';
    const readonlyActivation = run(bash, ['--noprofile', '--norc', '-c', readonlyBody, 'legacy-fixture',
        path.join(sourceRoot, 'docker-ssh.bash').replaceAll('\\', '/'), legacy.replaceAll('\\', '/')], conflicts);
    check('legacy-activation-immutable-selection-has-no-partial-state', readonlyActivation.status === 0 && readonlyActivation.stdout === 'NO_PARTIAL_STATE');
    const restoreProbe = path.join(scratch, 'legacy-restore.ps1');
    fs.writeFileSync(restoreProbe, `param([string] $Launcher,[string] $Reader,[string] $Deployment,[string] $InvalidConfig)
$tokens=$null; $errors=$null
$tree=[Management.Automation.Language.Parser]::ParseFile($Launcher,[ref]$tokens,[ref]$errors)
if ($errors.Count) { exit 40 }
# Extract only the trusted function under test; main process launching is outside this restoration probe.
foreach($functionName in @('Get-LauncherEnvironmentState','Set-LauncherEnvironmentState','Read-LauncherDeployment')) {
    $definition=$tree.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName},$false)
    if($null -eq $definition) { exit 50 }
    . ([ScriptBlock]::Create($definition.Extent.Text))
}
function Snapshot-Routing {
    <# .SYNOPSIS Captures only synthetic routing values and unset/empty distinctions for parent-environment assertions. #>
    $result=[ordered]@{}
    foreach($name in @('PATH','DOCKER_CONFIG','DOCKER_SSH_HELPER_ROOT','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH','DOCKER_HOST','DOCKER_CONTEXT','DOCKER_AUTH_CONFIG')) {
        $result[$name]=@((Test-Path ('Env:'+ $name)),[Environment]::GetEnvironmentVariable($name,'Process'))
    }
    return ($result|ConvertTo-Json -Compress)
}
$names=@('DOCKER_HOST','DOCKER_CONTEXT','DOCKER_AUTH_CONFIG')
for($combination=0;$combination -lt 27;$combination++) {
    $digits=$combination
    foreach($name in $names) {
        $state=$digits % 3; $digits=[int][Math]::Floor($digits / 3)
        if($state -eq 0) { Remove-Item -LiteralPath ('Env:'+$name) -ErrorAction SilentlyContinue }
        elseif($state -eq 1) { Set-Item -LiteralPath ('Env:'+$name) -Value '' }
        else { Set-Item -LiteralPath ('Env:'+$name) -Value ('synthetic-'+$name+'-空白 "quoted"') }
    }
    $before=Snapshot-Routing
    $global:LASTEXITCODE=29
    $null=Read-LauncherDeployment -Reader $Reader -Deployment $Deployment -Strict:$false
    if((Snapshot-Routing) -cne $before -or $global:LASTEXITCODE -ne 29) { exit 41 }
    $env:DOCKER_CONFIG=$InvalidConfig
    $failureBefore=Snapshot-Routing
    $failed=$false
    try { $null=Read-LauncherDeployment -Reader $Reader -Deployment $Deployment -Strict:$false } catch { $failed=$true }
    if(-not $failed -or (Snapshot-Routing) -cne $failureBefore -or $global:LASTEXITCODE -ne 29) { exit 42 }
    $env:DOCKER_CONFIG=''
}
[Console]::Write('RESTORED_SUCCESS_AND_FAILURE')
`);
    const parentRestored = run(powershell, ['-NoProfile', '-File', restoreProbe, '-Launcher', launcher,
        '-Reader', path.join(sourceRoot, 'Get-TpmDockerEnvironment.ps1'), '-Deployment', legacy, '-InvalidConfig', path.join(scratch, 'invalid-config')], conflicts, 300000);
    check('legacy-powershell-27-state-matrix-success-failure-and-exit-restoration', parentRestored.status === 0 && parentRestored.stdout === 'RESTORED_SUCCESS_AND_FAILURE');
    // Both activation outcomes must preserve all 27 original parent routing states, including absent keys.
    for (let combination = 0; combination < 27; combination++) {
        let digits = combination;
        const states = {};
        for (const name of ['DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_AUTH_CONFIG']) {
            const state = digits % 3;
            digits = Math.floor(digits / 3);
            states[name] = state === 0 ? undefined : state === 1 ? '' : 'synthetic-' + name + '-空白 "quoted"';
        }
        const success = run(bash, ['--noprofile', '--norc', '-c', bashParentBody.replaceAll('DOCKER_SSH_HELPER_ROOT)', 'DOCKER_SSH_HELPER_ROOT 2>/dev/null)'),
            'matrix-fixture', path.join(sourceRoot, 'docker-ssh.bash').replaceAll('\\', '/'), legacy.replaceAll('\\', '/')], states);
        check('bash-state-matrix-' + combination + '-activation-execution-deactivation', success.status === 0);
        assertChildRouting(JSON.parse(success.stdout), legacy, 'npipe:////./pipe/inertLegacy');
        const failure = run(bash, ['--noprofile', '--norc', '-c', bashFailureBody.replaceAll('DOCKER_SSH_HELPER_ROOT)', 'DOCKER_SSH_HELPER_ROOT 2>/dev/null)'),
            'matrix-fixture', path.join(sourceRoot, 'docker-ssh.bash').replaceAll('\\', '/'), legacy.replaceAll('\\', '/')], { ...states, DOCKER_CONFIG: path.join(scratch, 'invalid-config') });
        check('bash-state-matrix-' + combination + '-failure-preserves-state', failure.status === 0 && failure.stdout === 'SAFE_REJECTED');
    }
    const readerStub = path.join(scratch, 'reader-errors.ps1');
    fs.writeFileSync(readerStub, `[CmdletBinding()]
param([string] $DeploymentRoot,[switch] $NoOutput,[switch] $RequireReady)
if (-not $NoOutput) { throw 'Sourced reader must suppress all metadata.' }
$configuration=[pscustomobject]@{HelperVersion='0.5.0'}
switch($env:SYNTHETIC_READER_MODE) {
    'nonterminating' { Write-Error 'Synthetic reader error.' -ErrorAction Continue }
    'native-exit' { & $env:ComSpec /d /c exit 7 }
    'exception' { throw 'Synthetic reader exception.' }
}
`);
    const errorProbe = path.join(scratch, 'reader-propagation.ps1');
    fs.writeFileSync(errorProbe, `param([string] $Launcher,[string] $Reader,[string] $Deployment)
$tokens=$null; $errors=$null
$tree=[Management.Automation.Language.Parser]::ParseFile($Launcher,[ref]$tokens,[ref]$errors)
# Isolate the trusted validator function; no launcher main or Docker process runs in this probe.
foreach($functionName in @('Get-LauncherEnvironmentState','Set-LauncherEnvironmentState','Read-LauncherDeployment')) {
    $definition=$tree.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName},$false)
    if($null -eq $definition) { exit 50 }
    . ([ScriptBlock]::Create($definition.Extent.Text))
}
foreach($exitState in @('absent','zero','nonzero')) {
    foreach($mode in @('success','nonterminating','native-exit','exception')) {
        if($exitState -eq 'absent') { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
        elseif($exitState -eq 'zero') { $global:LASTEXITCODE=0 } else { $global:LASTEXITCODE=29 }
        $env:SYNTHETIC_READER_MODE=$mode
        $failed=$false
        try { $null=Read-LauncherDeployment -Reader $Reader -Deployment $Deployment -Strict:$true } catch { $failed=$true }
        if($failed -ne ($mode -ne 'success')) { exit 51 }
        $after=Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        if($exitState -eq 'absent') { if($null -ne $after) { exit 52 } }
        elseif($null -eq $after -or $after.Value -ne $(if($exitState -eq 'zero'){0}else{29})) { exit 53 }
    }
}
[Console]::Write('ALL_READER_FAILURES_PROPAGATED')
`);
    const errorPropagation = run(powershell, ['-NoProfile', '-File', errorProbe, '-Launcher', launcher, '-Reader', readerStub, '-Deployment', legacy]);
    check('nonterminating-native-exit-exception-propagate-and-restore-exit-state', errorPropagation.status === 0 && errorPropagation.stdout === 'ALL_READER_FAILURES_PROPAGATED');
    const faultProbe = path.join(scratch, 'restoration-faults.ps1');
    fs.writeFileSync(faultProbe, `param([string] $Launcher,[string] $Reader,[string] $Deployment)
$tokens=$null;$errors=$null
$tree=[Management.Automation.Language.Parser]::ParseFile($Launcher,[ref]$tokens,[ref]$errors)
foreach($functionName in @('Get-LauncherEnvironmentState','Set-LauncherEnvironmentState','Read-LauncherDeployment')) {
    # Extract just the approved process-state functions; no main launcher code executes.
    $definition=$tree.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName},$false)
    . ([ScriptBlock]::Create($definition.Extent.Text))
}
$script:realSet=(Get-Item -LiteralPath 'Function:Set-LauncherEnvironmentState').ScriptBlock
function Set-LauncherEnvironmentState {
    <# .SYNOPSIS Injects one synthetic process-state failure and records key/presence operations only. #>
    param([pscustomobject] $State)
    $script:calls.Add($State.Name+':'+$State.Exists)
    $matches=if($script:phase -eq 'normalize'){-not $State.Exists}else{$State.Exists}
    if(-not $script:faulted -and $matches -and $State.Name -eq $script:faultKey) {
        $script:faulted=$true;$global:LASTEXITCODE=7;throw 'Synthetic state operation failure.'
    }
    & $script:realSet -State $State
}
$names=@('DOCKER_HOST','DOCKER_CONTEXT','DOCKER_AUTH_CONFIG')
foreach($scenario in @('normalize:DOCKER_CONTEXT','restore:DOCKER_HOST','restore:DOCKER_CONTEXT','restore:DOCKER_AUTH_CONFIG')) {
    foreach($name in $names){Set-Item -LiteralPath ('Env:'+$name) -Value ('synthetic-'+$name)}
    $parts=$scenario.Split(':');$script:phase=$parts[0];$script:faultKey=$parts[1];$script:faulted=$false
    $script:calls=[Collections.Generic.List[string]]::new();$global:LASTEXITCODE=29;$failed=$false
    try{$null=Read-LauncherDeployment -Reader $Reader -Deployment $Deployment -Strict:$false}catch{$failed=$true}
    if(-not $failed -or -not $script:faulted -or $global:LASTEXITCODE -ne 29){exit 61}
    foreach($name in $names){
        if(-not $script:calls.Contains($name+':True')){exit 62}
        $state=Get-LauncherEnvironmentState -Name $name
        if($script:phase -eq 'restore' -and $name -eq $script:faultKey){if($state.Exists){exit 63}}
        elseif(-not $state.Exists -or $state.Value -cne ('synthetic-'+$name)){exit 64}
    }
}
[Console]::Write('ALL_ROLLBACKS_ATTEMPTED')
`);
    const faultResult = run(powershell, ['-NoProfile', '-File', faultProbe, '-Launcher', launcher,
        '-Reader', path.join(sourceRoot, 'Get-TpmDockerEnvironment.ps1'), '-Deployment', legacy], {}, 300000);
    check('partial-normalization-and-each-restore-fault-attempt-all-keys-and-exit', faultResult.status === 0 && faultResult.stdout === 'ALL_ROLLBACKS_ATTEMPTED');
    const faultDirectory = path.join(scratch, 'fault-launcher');
    fs.mkdirSync(faultDirectory);
    fs.copyFileSync(path.join(sourceRoot, 'Get-TpmDockerEnvironment.ps1'), path.join(faultDirectory, 'Get-TpmDockerEnvironment.ps1'));
    const launcherSource = fs.readFileSync(launcher, 'utf8');
    const mainAnchor = '\ntry {\n    if ($PSBoundParameters.ContainsKey';
    const mainPosition = launcherSource.indexOf(mainAnchor);
    assert.ok(mainPosition >= 0, 'Fault injection must precede only the launcher main');
    // Override only the private setter inside a synthetic copy; the deployed/canonical sources remain untouched.
    const faultSetter = `
$script:realSet=(Get-Item -LiteralPath 'Function:Set-LauncherEnvironmentState').ScriptBlock
$script:faulted=$false
function Set-LauncherEnvironmentState {
    <# .SYNOPSIS Refuses one synthetic rollback so the real launcher main must remain fail-closed. #>
    param([pscustomobject] $State)
    if($State.Exists -and $State.Name -eq $env:SYNTHETIC_RESTORE_KEY -and -not $script:faulted){$script:faulted=$true;throw 'Synthetic rollback failure.'}
    & $script:realSet -State $State
}
`;
    const faultLauncher = path.join(faultDirectory, 'Invoke-DockerSshTpm.ps1');
    fs.writeFileSync(faultLauncher, launcherSource.slice(0, mainPosition) + faultSetter + launcherSource.slice(mainPosition));
    for (const name of ['DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_AUTH_CONFIG']) {
        for (const metadataOnly of [false, true]) {
            const response = run(powershell, ['-NoProfile', '-File', faultLauncher, '-DeploymentRoot', legacy,
                ...(metadataOnly ? ['-MetadataOnly'] : ['version'])], { ...conflicts, SYNTHETIC_RESTORE_KEY: name });
            check('rollback-failure-' + name + (metadataOnly ? '-no-metadata' : '-no-child'), response.status !== 0 && response.stdout === '');
        }
    }
    const badMetadata = run(powershell, ['-NoProfile', '-File', launcher, '-DeploymentRoot', legacy, '-MetadataOnly'],
        { ...conflicts, DOCKER_CONFIG: path.join(scratch, 'invalid-config') });
    check('metadata-validation-failure-exits-nonzero-with-no-partial-output', badMetadata.status !== 0 && badMetadata.stdout === '');
    const standaloneReader = run(powershell, ['-NoProfile', '-File', path.join(sourceRoot, 'Get-TpmDockerEnvironment.ps1'), '-DeploymentRoot', legacy],
        { DOCKER_CONFIG: path.join(scratch, 'invalid-config') });
    check('standalone-reader-exit-distinct-from-sourced-exception', standaloneReader.status !== 0 && standaloneReader.stdout === '');
    for (const name of ['DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH', 'DOCKER_CONFIG', 'DOCKER_SSH_HELPER_ROOT']) {
        const response = run(powershell, ['-NoProfile', '-File', launcher, '-DeploymentRoot', legacy, 'version'],
            { ...conflicts, [name]: path.join(scratch, 'invalid-routing') });
        check('legacy-invalid-after-normalization-' + name, response.status !== 0 && !response.stdout.includes('"path"'));
    }
    for (const name of Object.keys(conflicts)) {
        const response = run(powershell, ['-NoProfile', '-File', launcher, '-DeploymentRoot', deployment, '-RequireReady', '-MetadataOnly'], { [name]: conflicts[name] });
        check('managed-strict-rejects-' + name, response.status !== 0 && response.stdout === '');
    }
    for (const name of ['DOCKER_CONFIG', 'DOCKER_SSH_HELPER_ROOT', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH']) {
        const response = run(powershell, ['-NoProfile', '-File', launcher, '-DeploymentRoot', deployment, '-RequireReady', 'version'], { [name]: path.join(scratch, 'invalid-routing') });
        check('managed-rejects-config-tls-without-fallback-' + name, response.status !== 0 && !response.stdout.includes('"path"'));
    }
    for (const name of Object.keys(conflicts)) {
        const response = run(powershell, ['-NoProfile', '-File', launcher, '-DeploymentRoot', deployment, '-MetadataOnly'], { [name]: conflicts[name] });
        check('unmanaged-05-cannot-use-legacy-normalization-' + name, response.status !== 0 && response.stdout === '');
    }
    for (const argument of ['--host=npipe:////./pipe/wrong', '--context=wrong', '--config=C:/wrong']) {
        const response = run(powershell, ['-NoProfile', '-File', launcher, '-DeploymentRoot', deployment, '-RequireReady', 'version', argument]);
        check('managed-rejects-routing-argument-' + argument.split('=')[0], response.status !== 0 && !response.stdout.includes('"path"'));
    }
    const managedChild = run(powershell, ['-NoProfile', '-File', launcher, '-DeploymentRoot', deployment, '-RequireReady', 'version']);
    check('managed-fixed-routing-inert-child-started', managedChild.status === 0);
    assertChildRouting(JSON.parse(managedChild.stdout), deployment, 'npipe:////./pipe/inertFixture');
    check('managed-fixed-child-routing-after-validation', true);
    const managedMetadata = run(powershell, ['-NoProfile', '-File', launcher, '-DeploymentRoot', deployment, '-RequireReady', '-MetadataOnly']);
    check('managed-ready-metadata-without-process-launch', managedMetadata.status === 0 && managedMetadata.stdout.split('\n').length === 5);
    const settingsFile = path.join(deployment, 'settings.json');
    const readySettings = fs.readFileSync(settingsFile);
    const staged = JSON.parse(readySettings.toString());
    staged.State = 'STAGED';
    fs.writeFileSync(settingsFile, JSON.stringify(staged));
    const notReady = run(powershell, ['-NoProfile', '-File', launcher, '-DeploymentRoot', deployment, '-RequireReady', '-MetadataOnly']);
    check('managed-staged-still-fails-closed', notReady.status !== 0 && notReady.stdout === '');
    fs.writeFileSync(settingsFile, readySettings);
    console.log('managed-bootstrap : PASS; assertions=' + assertions + '; registry=NONE; credentials=NONE; real-SSH=UNTESTED');
} finally {
    // Retain this unique synthetic fixture for bounded diagnosis; it contains no credentials.
    console.log('Fixture: ' + scratch);
}
