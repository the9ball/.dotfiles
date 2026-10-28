import { spawn } from 'node:child_process';
import { createHash, randomUUID, randomBytes } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const source = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const artifacts = path.join(source, 'artifacts');
const authorizationSelfTest = process.argv[2] === '--authorization-self-test';
const authorizationPath = authorizationSelfTest ? null : process.argv[2];
const authorization = authorizationPath ? JSON.parse(fs.readFileSync(authorizationPath, 'utf8')) : null;
const installationId = authorization?.InstallationId ?? randomUUID().replaceAll('-', '');
if (!/^[a-f0-9]{32}$/.test(installationId)) throw new Error('Invalid installation identity');
const destination = path.join(process.env.LOCALAPPDATA, 'docker-ssh-issue142-lab-install-' + installationId);
const packageRoot = path.join(process.env.LOCALAPPDATA, 'docker-ssh-issue142-lab-package-' + installationId);
const results = [];
const original = path.join(process.env.USERPROFILE, '.docker/config.json');
const originalHash = fs.existsSync(original) ? digest(original) : null;
let created = false;
let indeterminate = false;
const reviewedFiles = [
    'src/TpmKeySetup/Program.cs', 'src/TpmKeySetup/TpmKeySetup.csproj', 'poc-tpm-v2/Policy.cs',
    'src/DockerCredentialTpm/Program.cs', 'src/DockerCredentialTpm/CredentialKey.cs', 'src/DockerCredentialTpm/TpmCipher.cs', 'src/DockerCredentialTpm/AclChecks.cs', 'src/DockerCredentialTpm/DockerCredentialTpm.csproj',
    'scripts/Build-TpmDockerPackage.ps1', 'scripts/Initialize-DockerSshTpm.ps1', 'scripts/Remove-DockerSshTpm.ps1', 'scripts/TpmSetupRuntime.ps1',
    'src/DockerSshDispatcher/Program.cs', 'src/DockerSshDispatcher/DockerSshDispatcher.csproj', 'tests/ColdBootEnvironment.ps1', 'tests/Verify-TpmSetup.mjs',
    'chezmoi/AppData/Local/Dotfiles/DockerSsh/docker-ssh.bash', 'chezmoi/AppData/Local/Dotfiles/DockerSsh/Get-TpmDockerEnvironment.ps1', 'chezmoi/AppData/Local/Dotfiles/DockerSsh/Invoke-DockerSshTpm.ps1', 'chezmoi/AppData/Local/Dotfiles/DockerSsh/Enter-DockerSshEnvironment.ps1', 'global.json',
];

/** Reject incomplete, duplicate, escaping or changed source sets before any attempt claim, build or persistent key operation. */
function validateAuthorization(value, sid) {
    if (value.State !== 'APPROVED_ONE_TRIAL' || value.Mode !== 'poc' || value.MaxKeys !== 1 || value.AllowCreateAndExactDelete !== true || value.UserSid !== sid ||
        value.InstallationId !== installationId || value.KeyName !== 'docker-ssh-issue142-poc-' + installationId || typeof value.DestinationRoot !== 'string' ||
        path.resolve(value.DestinationRoot).toLowerCase() !== destination.toLowerCase() || !Array.isArray(value.Files) || value.Files.length !== reviewedFiles.length) throw new Error('Authorization boundary mismatch');
    const seen = new Set();
    for (const entry of value.Files) {
        if (typeof entry.Path !== 'string' || entry.Path.includes('\\') || path.posix.normalize(entry.Path) !== entry.Path || !reviewedFiles.includes(entry.Path) || seen.has(entry.Path) ||
            typeof entry.SHA256 !== 'string' || !/^[A-F0-9]{64}$/.test(entry.SHA256) || digest(path.join(source, entry.Path)) !== entry.SHA256) throw new Error('Reviewed source manifest mismatch');
        seen.add(entry.Path);
    }
    if (seen.size !== reviewedFiles.length) throw new Error('Incomplete source set');
}

/** Resolve only the supported installed helper from verified settings, never an obsolete fixed path. */
function installedHelperPath(settings, root) {
    if (settings.Version !== 1 || settings.HelperKind !== 'tpm' || settings.HelperVersion !== '0.5.0') throw new Error('Unsupported installed helper');
    const helper = path.join(root, 'bin', settings.HelperVersion, 'docker-credential-ssh-tpm.exe');
    if (!fs.statSync(helper).isFile() || fs.lstatSync(helper).isSymbolicLink()) throw new Error('Installed helper missing or redirected');
    return helper;
}

/** Hash file bytes without reading credential values or printing contents. */
function digest(file) { return createHash('sha256').update(fs.readFileSync(file)).digest('hex').toUpperCase(); }

/** Capture child output only in memory; UI/stall handling remains inside the setup wrappers and unknown completion stops this test. */
function run(executable, args, input = '', extra = {}) {
    // Own one foreground child's bounded lifetime and keep all protocol payloads in this process's memory.
    return new Promise((resolve, reject) => {
        const child = spawn(executable, args, { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, DOCKER_TLS_VERIFY: '', DOCKER_CERT_PATH: '', ...extra } });
        let output = '', errors = '';
        const timer = setTimeout(() => {
            indeterminate = true;
            if (created) {
                try { fs.writeFileSync(path.join(destination, 'key/stop-request.json'), 'STOP', { flag: 'wx' }); } catch { }
            }
            reject(new Error('Child outcome indeterminate'));
        }, 300000);
        child.stdout.on('data', bytes => { if (output.length > 1048576) { indeterminate = true; reject(new Error('Output exceeded bound')); } else output += bytes.toString(); });
        child.stderr.on('data', bytes => { if (errors.length < 65536) errors += bytes.toString(); });
        child.on('error', () => { clearTimeout(timer); reject(new Error('Child start failed')); });
        child.on('close', code => { clearTimeout(timer); resolve({ code, output, errors }); });
        child.stdin.on('error', () => {});
        child.stdin.end(input);
    });
}

/** Run a fixed repository script using explicit nonsecret arguments. */
function script(relative, args) { return run('pwsh.exe', ['-NoProfile', '-File', path.join(source, relative), ...args]); }

/** Record only fixed public assertions, never helper protocol contents. */
function check(name, passed) {
    results.push({ name, status: passed ? 'PASS' : 'FAIL' });
    console.log(`setup-${name} : ${passed ? 'PASS' : 'FAIL'}`);
    if (!passed) throw new Error('Setup assertion failed');
}

/** Prepare explicit arguments for this one disposable installation; permanent mode is never used in this harness. */
function setupArgs() { return ['-PackageRoot', packageRoot, '-DestinationRoot', destination, '-InstallationId', installationId, '-Mode', 'poc', '-EngineEndpoint', 'npipe:////./pipe/dockerSshSetupValidationOnly']; }

if (authorizationSelfTest) {
    const valid = { State: 'APPROVED_ONE_TRIAL', Mode: 'poc', MaxKeys: 1, AllowCreateAndExactDelete: true, UserSid: 'test-user', InstallationId: installationId,
        KeyName: 'docker-ssh-issue142-poc-' + installationId, DestinationRoot: destination, Files: reviewedFiles.map(Path => ({ Path, SHA256: digest(path.join(source, Path)) })) };
    validateAuthorization(valid, 'test-user');
    const cases = [[], undefined, valid.Files.slice(1), [...valid.Files.slice(1), valid.Files[1]],
        [{ ...valid.Files[0], Path: '../escape' }, ...valid.Files.slice(1)], [{ ...valid.Files[0], SHA256: '0' }, ...valid.Files.slice(1)]];
    for (const Files of cases) {
        let rejected = false;
        try { validateAuthorization({ ...valid, Files }, 'test-user'); } catch { rejected = true; }
        if (!rejected) throw new Error('Unsafe manifest accepted');
    }
    const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'docker-ssh-issue185-path-'));
    try {
        const expected = path.join(fixture, 'bin/0.5.0/docker-credential-ssh-tpm.exe');
        fs.mkdirSync(path.dirname(expected), { recursive: true });
        fs.writeFileSync(expected, 'inert path fixture; never executable');
        const settings = { Version: 1, HelperKind: 'tpm', HelperVersion: '0.5.0' };
        if (installedHelperPath(settings, fixture) !== expected) throw new Error('Current helper path mismatch');
        for (const HelperVersion of ['0.4.0', '../escape']) {
            let rejected = false;
            try { installedHelperPath({ ...settings, HelperVersion }, fixture); } catch { rejected = true; }
            if (!rejected) throw new Error('Obsolete or escaping helper path accepted');
        }
    } finally {
        if (path.dirname(path.resolve(fixture)) !== path.resolve(os.tmpdir()) || !path.basename(fixture).startsWith('docker-ssh-issue185-path-')) throw new Error('Fixture cleanup boundary mismatch');
        fs.rmSync(fixture, { recursive: true });
    }
    console.log('setup-authorization : PASS; assertions=10; key-operations=0; builds=0');
    process.exit(0);
}

try {
    fs.mkdirSync(artifacts, { recursive: true });
    check('new-target', !fs.existsSync(destination) && !fs.existsSync(packageRoot));
    if (authorization) {
        const identity = await run('pwsh.exe', ['-NoProfile', '-Command', '[Security.Principal.WindowsIdentity]::GetCurrent().User.Value']);
        if (identity.code !== 0) throw new Error('Cannot verify execution identity');
        validateAuthorization(authorization, identity.output.trim());
        check('explicit-dummy-authorization', true);
        for (const entry of authorization.Files) check('source-bound/' + entry.Path, digest(path.join(source, entry.Path)) === entry.SHA256);
        fs.writeFileSync(path.join(artifacts, `setup-${installationId}-claim.json`), JSON.stringify({ state: 'CLAIMED_NO_RETRY', installationId }), { flag: 'wx' });
    }
    check('build-package', (await script('scripts/Build-TpmDockerPackage.ps1', ['-OutputRoot', packageRoot])).code === 0);
    check('check-only', (await script('scripts/Initialize-DockerSshTpm.ps1', [...setupArgs(), '-CheckOnly'])).code === 0);
    check('check-only-no-directory', !fs.existsSync(destination));
    const partialId = randomUUID().replaceAll('-', '');
    const partial = path.join(process.env.LOCALAPPDATA, 'docker-ssh-issue142-lab-install-' + partialId);
    fs.mkdirSync(partial);
    check('partial-state-rejected-without-key', (await script('scripts/Initialize-DockerSshTpm.ps1', ['-PackageRoot', packageRoot, '-DestinationRoot', partial, '-InstallationId', partialId, '-Mode', 'poc', '-EngineEndpoint', 'npipe:////./pipe/dockerSshSetupValidationOnly', '-CheckOnly'])).code !== 0 && !fs.existsSync(path.join(partial, 'key')));
    const privateFixtureScript = path.join(artifacts, `setup-${installationId}-fake-private.ps1`);
    fs.writeFileSync(privateFixtureScript, `param([string] $Path)
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
$security=[Security.AccessControl.DirectorySecurity]::new()
$security.SetOwner($owner)
$security.SetAccessRuleProtection($true,$false)
$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
[void][IO.FileSystemAclExtensions]::CreateDirectory($security,$Path)
`);
    const partialKey = path.join(partial, 'key');
    check('private-fake-key-directory', (await run('pwsh.exe', ['-NoProfile', '-File', privateFixtureScript, '-Path', partialKey])).code === 0);
    fs.writeFileSync(path.join(partialKey, 'create-intent.json'), '{}', { flag: 'wx' });
    const interrupted = await run(path.join(packageRoot, 'key-tool/docker-ssh-tpm-key.exe'), ['create', partialKey, partialId, 'poc']);
    check('incomplete-intent-rejected-before-provider', interrupted.code === 1 && interrupted.output.includes('Stage=create-intent-preconditions') && !fs.existsSync(path.join(partialKey, 'created-public.json')));
    // Remove only the exact fake files and empty directories just created; never recurse into unknown contents.
    fs.unlinkSync(path.join(partialKey, 'create-intent.json'));
    const eventScript = path.join(artifacts, `setup-${installationId}-stop-only.ps1`);
    fs.writeFileSync(eventScript, `param([string] $Runtime,[string] $Tool,[string] $Root,[string] $Id)
. $Runtime
$event=New-TpmBootStopEvent -FixtureId $Id
try {
    [TpmBootStop]::Signal($event)
    $start=[Diagnostics.ProcessStartInfo]::new($Tool)
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    foreach($argument in @('create',$Root,$Id,'poc')){$start.ArgumentList.Add($argument)}
    $child=[Diagnostics.Process]::Start($start)
    try {
        $text=$child.StandardOutput.ReadToEndAsync()
        if(-not $child.WaitForExit(10000)){throw 'Stop-only child indeterminate'}
        if($child.ExitCode -ne 1 -or $text.GetAwaiter().GetResult() -notmatch 'Stage=create-intent-preconditions; HRESULT=0x8013153B' -or (Test-Path -LiteralPath (Join-Path $Root 'create-intent.json'))){throw 'Transient stop gate failed'}
    }finally{$child.Dispose()}
}finally{$event.Dispose()}
`);
    check('transient-stop-without-disk-marker-before-provider', (await run('pwsh.exe', ['-NoProfile', '-File', eventScript, '-Runtime', path.join(source, 'scripts/TpmSetupRuntime.ps1'), '-Tool', path.join(packageRoot, 'key-tool/docker-ssh-tpm-key.exe'), '-Root', partialKey, '-Id', partialId])).code === 0);
    fs.rmdirSync(partialKey);
    fs.rmdirSync(partial);
    if (!authorization) {
        console.log('setup-preflight : PASS; key-operations=0; real-registry=NONE');
    } else {
        created = true;
        check('initialize-empty-encrypted-store', (await script('scripts/Initialize-DockerSshTpm.ps1', [...setupArgs(), '-Execute'])).code === 0);
        const receipt = JSON.parse(fs.readFileSync(path.join(destination, 'key/receipt.json'), 'utf8'));
        check('verified-poc-receipt', receipt.Mode === 'poc' && receipt.InstallationId === installationId && receipt.Identity.Binding.KeyName === 'docker-ssh-issue142-poc-' + installationId);
        const settingsBefore = digest(path.join(destination, 'settings.json'));
        check('idempotent-verify-no-rewrite', (await script('scripts/Initialize-DockerSshTpm.ps1', [...setupArgs(), '-Execute'])).code === 0 && digest(path.join(destination, 'settings.json')) === settingsBefore);
        const environment = { DOCKER_SSH_HELPER_ROOT: path.join(destination, 'store') };
        const helper = installedHelperPath(JSON.parse(fs.readFileSync(path.join(destination, 'settings.json'), 'utf8')), destination);
        const secret = randomBytes(32).toString('hex');
        const request = JSON.stringify({ ServerURL: 'setup.invalid', Username: 'setup-user', Secret: secret });
        check('dummy-store', (await run(helper, ['store'], request, environment)).code === 0);
        const get = await run(helper, ['get'], 'setup.invalid', environment);
        check('dummy-decrypt', get.code === 0 && JSON.parse(get.output).Secret === secret);
        check('dummy-list', JSON.parse((await run(helper, ['list'], '', environment)).output)['https://setup.invalid'] === 'setup-user');
        check('dummy-update', (await run(helper, ['store'], JSON.stringify({ ServerURL: 'setup.invalid', Username: 'updated-user', Secret: secret }), environment)).code === 0 && JSON.parse((await run(helper, ['get'], 'setup.invalid', environment)).output).Username === 'updated-user');
        check('dummy-erase', (await run(helper, ['erase'], 'setup.invalid', environment)).code === 0 && (await run(helper, ['get'], 'setup.invalid', environment)).code === 1);
        check('ciphertext-not-plaintext', !fs.readFileSync(path.join(destination, 'store/vault.tpm'), 'utf8').includes(secret));
        const bash = path.join(process.env.ProgramFiles, 'Git/usr/bin/bash.exe');
        const shell = path.join(destination, 'shell/docker-ssh.bash').replaceAll('\\', '/');
        check('packaged-bash-activation', (await run(bash, ['--noprofile', '--norc', '-c', 'source "$1"; docker-ssh-activate "$2" || exit; [[ $(type -t docker) == function ]] || exit 9; docker-ssh-deactivate', 'setup-check', shell, destination.replaceAll('\\', '/')])).code === 0);
        check('wrong-removal-id-rejected', (await script('scripts/Remove-DockerSshTpm.ps1', ['-DestinationRoot', destination, '-InstallationId', '0'.repeat(32), '-Mode', 'poc', '-Execute', '-DeleteKey', '-ConfirmIrreversibleKeyDeletion'])).code !== 0);
        check('read-only-removal', (await script('scripts/Remove-DockerSshTpm.ps1', ['-DestinationRoot', destination, '-InstallationId', installationId, '-Mode', 'poc'])).code === 0 && fs.existsSync(destination));
        check('disable-retains-key-and-store', (await script('scripts/Remove-DockerSshTpm.ps1', ['-DestinationRoot', destination, '-InstallationId', installationId, '-Mode', 'poc', '-Execute'])).code === 0 && fs.existsSync(path.join(destination, 'store/vault.tpm')));
        check('disabled-bash-refuses-activation', (await run(bash, ['--noprofile', '--norc', '-c', 'source "$1"; docker-ssh-activate "$2"', 'setup-check', shell, destination.replaceAll('\\', '/')])).code !== 0);
        check('exact-removal', (await script('scripts/Remove-DockerSshTpm.ps1', ['-DestinationRoot', destination, '-InstallationId', installationId, '-Mode', 'poc', '-Execute', '-DeleteKey', '-ConfirmIrreversibleKeyDeletion'])).code === 0 && !fs.existsSync(destination));
        const audit = JSON.parse(fs.readFileSync(path.join(process.env.LOCALAPPDATA, installationId + '-removed.json'), 'utf8'));
        check('delete-and-independent-absence', audit.DeleteApi.Status === '0x00000000' && audit.Existence.Status === '0x80090016' && audit.Existence.Absent === true);
        created = false;
    }
    check('desktop-config-preserved', (fs.existsSync(original) ? digest(original) : null) === originalHash);
} catch {
    console.log(`setup : FAIL_OR_INDETERMINATE; preserve-partial=${created}; do-not-retry; no-secret-diagnostics`);
    process.exitCode = 1;
} finally {
    fs.writeFileSync(path.join(artifacts, `setup-${installationId}-result.json`), JSON.stringify({ results, indeterminate, keyMayRemain: created, installationId, realRegistry: 'NOT_ACCESSED', otherMachine: 'UNTESTED', coldBoot: 'UNTESTED' }, null, 2));
}
