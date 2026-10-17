import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const lab = path.join(process.env.LOCALAPPDATA, 'docker-ssh-issue142-lab-setup-' + randomUUID());
fs.mkdirSync(lab);
const results = [];
const originalConfig = path.join(process.env.USERPROFILE, '.docker/config.json');
const originalHash = fs.existsSync(originalConfig) ? digest(originalConfig) : null;
const packageDirectory = path.join(root, 'src/DockerCredentialTpm/bin/Release/net10.0-windows');
const names = ['docker-credential-ssh-tpm.exe', 'docker-credential-ssh-tpm.dll', 'docker-credential-ssh-tpm.deps.json', 'docker-credential-ssh-tpm.runtimeconfig.json'];
const manifest = path.join(lab, 'package.json');
fs.writeFileSync(manifest, JSON.stringify(Object.fromEntries(names.map(name => [name, digest(path.join(packageDirectory, name))]))));

/** Hash only artifact bytes; never read any credential store. */
function digest(file) { return createHash('sha256').update(fs.readFileSync(file)).digest('hex').toUpperCase(); }

/** Capture metadata-only subprocess output; a timeout stops this run without killing or retrying a child. */
function run(executable, args) {
    return new Promise((resolve, reject) => {
        const child = spawn(executable, args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, DOCKER_TLS_VERIFY: '', DOCKER_CERT_PATH: '' } });
        let output = '';
        const timer = setTimeout(() => reject(new Error('Metadata child indeterminate; stop and establish quiescence')), 60000);
        fs.writeFileSync(path.join(lab, `child-${child.pid}-started.json`), JSON.stringify({ pid: child.pid, startedUtc: new Date().toISOString() }));
        child.stdout.on('data', chunk => { if (output.length < 65536) output += chunk.toString(); });
        child.stderr.on('data', () => {});
        child.on('error', () => { clearTimeout(timer); reject(new Error('Metadata child start failed')); });
        child.on('close', code => { clearTimeout(timer); fs.writeFileSync(path.join(lab, `child-${child.pid}-exited.json`), JSON.stringify({ code })); resolve({ code, output }); });
    });
}

/** Execute a PowerShell script without adding arbitrary body text to a command string. */
function script(file, args = []) { return run('pwsh.exe', ['-NoProfile', '-File', path.join(root, file), ...args]); }

/** Emit fixed assertion names only. */
function check(name, passed) {
    results.push({ name, status: passed ? 'PASS' : 'FAIL' });
    console.log(`${name} : ${passed ? 'PASS' : 'FAIL'}`);
    if (!passed) throw new Error('Staging check failed');
}

try {
    const sid = await run('pwsh.exe', ['-NoProfile', '-Command', '[Security.Principal.WindowsIdentity]::GetCurrent().User.Value']);
    check('current-user-metadata', sid.code === 0 && /^S-1-/.test(sid.output.trim()));
    const binding = path.join(lab, 'public-fixture.json');
    // This intentionally nonexistent key tests staging only; no key or credential is initialized.
    fs.writeFileSync(binding, JSON.stringify({ ProviderName: 'Microsoft Platform Crypto Provider', KeyName: 'docker-ssh-issue142-poc-nonexistent-' + randomUUID(), UserSid: sid.output.trim(), UniqueNameSHA256: '0'.repeat(64), PublicSpkiSHA256: '1'.repeat(64) }));
    for (const number of [1, 2]) {
        const home = path.join(lab, `home-${number}`);
        fs.mkdirSync(home);
        const config = path.join(lab, `chezmoi-${number}.toml`);
        fs.writeFileSync(config, '');
        const common = ['--source', path.join(root, 'chezmoi'), '--destination', home, '--config', config, '--cache', path.join(lab, `cache-${number}`), '--persistent-state', path.join(lab, `state-${number}.db`), '--no-tty'];
        const nonWindows = await run('chezmoi.exe', [...common, '--override-data', '{"chezmoi":{"os":"linux"}}', 'managed']);
        check(`home-${number}/non-windows-excluded`, nonWindows.code === 0 && !nonWindows.output.includes('Invoke-DockerSshTpm'));
        check(`home-${number}/apply`, (await run('chezmoi.exe', [...common, 'apply'])).code === 0);
        check(`home-${number}/verify`, (await run('chezmoi.exe', [...common, 'verify'])).code === 0);
        check(`home-${number}/reapply`, (await run('chezmoi.exe', [...common, 'apply'])).code === 0);
        check(`home-${number}/tpm-launcher-delivered`, fs.existsSync(path.join(home, 'AppData/Local/Dotfiles/DockerSsh/Invoke-DockerSshTpm.ps1')));
        const bashLauncher = path.join(home, 'AppData/Local/Dotfiles/DockerSsh/docker-ssh.bash');
        check(`home-${number}/bash-launcher-and-reader-delivered`, fs.existsSync(bashLauncher) && fs.existsSync(path.join(path.dirname(bashLauncher), 'Get-TpmDockerEnvironment.ps1')));
        const destination = path.join(home, `docker-ssh-issue142-lab-package-${number}`);
        const args = ['-DestinationRoot', destination, '-PackageDirectory', packageDirectory, '-ManifestPath', manifest, '-BindingPath', binding, '-EngineEndpoint', 'npipe:////./pipe/dockerSshValidationOnly'];
        check(`home-${number}/check-only`, (await script('scripts/Install-DockerSshTpmLab.ps1', [...args, '-CheckOnly'])).code === 0 && !fs.existsSync(destination));
        check(`home-${number}/stage`, (await script('scripts/Install-DockerSshTpmLab.ps1', args)).code === 0);
        check(`home-${number}/no-store-or-key-initialization`, !fs.existsSync(path.join(destination, 'store')));
        const bash = path.join(process.env.ProgramFiles, 'Git/usr/bin/bash.exe');
        const bashPaths = [bashLauncher, destination].map(value => value.replaceAll('\\', '/'));
        const activation = await run(bash, ['--noprofile', '--norc', '-c', 'source "$1"; docker-ssh-activate "$2" || exit; [[ $(type -t docker) == function ]] || exit 9; docker-ssh-deactivate; [[ $(type -t docker) != function ]]', 'staging-check', ...bashPaths]);
        check(`home-${number}/bash-activation-deactivation-without-key`, activation.code === 0 && !fs.existsSync(path.join(destination, 'store')));
        const settings = fs.readFileSync(path.join(destination, 'settings.json'), 'utf8');
        check(`home-${number}/repeat-no-changes`, (await script('scripts/Install-DockerSshTpmLab.ps1', args)).code === 0 && fs.readFileSync(path.join(destination, 'settings.json'), 'utf8') === settings);
        const installationId = JSON.parse(settings).InstallationId;
        check(`home-${number}/wrong-remove-id-rejected`, (await script('scripts/Remove-DockerSshTpmLab.ps1', ['-DestinationRoot', destination, '-InstallationId', '0'.repeat(32), '-Execute'])).code !== 0 && fs.existsSync(destination));
        check(`home-${number}/remove-check-only`, (await script('scripts/Remove-DockerSshTpmLab.ps1', ['-DestinationRoot', destination, '-InstallationId', installationId])).code === 0 && fs.existsSync(destination));
        check(`home-${number}/remove`, (await script('scripts/Remove-DockerSshTpmLab.ps1', ['-DestinationRoot', destination, '-InstallationId', installationId, '-Execute'])).code === 0 && !fs.existsSync(destination));
        check(`home-${number}/restage`, (await script('scripts/Install-DockerSshTpmLab.ps1', args)).code === 0);
        const renewedId = JSON.parse(fs.readFileSync(path.join(destination, 'settings.json'), 'utf8')).InstallationId;
        check(`home-${number}/restage-fresh-identity`, renewedId !== installationId);
        check(`home-${number}/final-remove`, (await script('scripts/Remove-DockerSshTpmLab.ps1', ['-DestinationRoot', destination, '-InstallationId', renewedId, '-Execute'])).code === 0 && !fs.existsSync(destination));
    }
    check('original-desktop-config-preserved', (fs.existsSync(originalConfig) ? digest(originalConfig) : null) === originalHash);
    console.log(`tpm-staging : PASS; assertions=${results.length}; native-key-operations=0; credential-initialization=NONE`);
} catch {
    console.log('tpm-staging : FAIL; no native key operation requested; inspect retained public test evidence');
    process.exitCode = 1;
} finally {
    fs.writeFileSync(path.join(lab, 'results.json'), JSON.stringify({ results, nativeKeyOperations: 0, coldBoot: 'UNTESTED', otherMachine: 'UNTESTED' }, null, 2));
}
