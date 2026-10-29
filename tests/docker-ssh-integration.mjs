import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const moduleRoot = path.join(repository, 'docker-ssh');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'docker-ssh-dotfiles-integration-'));
const results = [];
const publicFiles = ['docker-ssh.bash', 'Get-TpmDockerEnvironment.ps1', 'Invoke-DockerSshTpm.ps1', 'Manage-TpmCredential.ps1', 'Enter-DockerSshEnvironment.ps1'];
const originalDocker = path.join(os.homedir(), '.docker/config.json');
const originalHash = fs.existsSync(originalDocker) ? digest(fs.readFileSync(originalDocker)) : null;

/** Hash bytes only; no credential contents are returned or logged. */
function digest(bytes) {
    return createHash('sha256').update(bytes).digest('hex').toUpperCase();
}

/** Run a bounded metadata or isolated-home child; never invoke Docker or a key operation. */
function run(executable, arguments_) {
    const child = spawnSync(executable, arguments_, { windowsHide: true, encoding: 'utf8', timeout: 60000, maxBuffer: 1048576 });
    assert.equal(child.error, undefined, 'Child failed or timed out; no retry');
    return child;
}

/** Record a named assertion without exposing child output or file contents. */
function check(name, passed) {
    results.push({ name, status: passed ? 'PASS' : 'FAIL' });
    assert.equal(passed, true, name);
    console.log(name + ' : PASS');
}

/** Enumerate only public source files and ignore local build products. */
function sourceFiles(directory) {
    // Traverse the bounded module while excluding local build and runtime directories.
    return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
        if (['bin', 'obj', 'artifacts', 'runtime'].includes(entry.name)) return [];
        const absolute = path.join(directory, entry.name);
        assert.equal(entry.isSymbolicLink(), false, 'Source links require separate review');
        return entry.isDirectory() ? sourceFiles(absolute) : [absolute];
    });
}

try {
    const inventory = JSON.parse(fs.readFileSync(path.join(moduleRoot, 'SOURCE-INVENTORY.json'), 'utf8'));
    check('origin-manifest-unique', new Set(inventory.Files.map(entry => entry.Path)).size === inventory.Files.length);
    for (const entry of inventory.Files) {
        assert.equal(path.posix.normalize(entry.Path), entry.Path);
        assert.equal(entry.Path.startsWith('../') || path.isAbsolute(entry.Path), false);
        if (entry.OriginalSHA256) {
            assert.match(entry.OriginalSHA256, /^[A-F0-9]{64}$/);
            assert.equal(typeof entry.Adaptation, 'string');
        }
        const normalized = fs.readFileSync(path.join(moduleRoot, entry.Path), 'utf8').replaceAll('\r\n', '\n');
        check('verified-current-source/' + entry.Path, digest(Buffer.from(normalized)) === entry.SHA256);
    }
    for (const absolute of sourceFiles(moduleRoot)) {
        const relative = path.relative(moduleRoot, absolute).replaceAll('\\', '/');
        const content = fs.readFileSync(absolute, 'utf8');
        assert.doesNotMatch(relative, /\.(?:exe|dll|tpm|dpapi|kdbx|pem|pfx|key|log)$/i);
        assert.doesNotMatch(content, /C:[/\\]Users[/\\]|syasui|997005746ce446eab9f6655bfbac6332/);
        assert.doesNotMatch(content, /gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}|-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----/);
    }
    check('portable-source-and-private-marker-scan', true);
    for (const relative of ['store/vault.tpm', 'key/receipt.json', 'key/key-binding.json', 'docker-config/config.json', 'settings.json', 'bin/tool.exe']) {
        const ignored = run('git', ['-C', repository, 'check-ignore', '--no-index', '--quiet', 'docker-ssh/' + relative]);
        check('git-private-exclusion/' + relative, ignored.status === 0);
    }
    for (const name of publicFiles) {
        const template = fs.readFileSync(path.join(repository, 'chezmoi/AppData/Local/Dotfiles/DockerSsh', name + '.tmpl'), 'utf8');
        check('public-only-template/' + name, template.includes('include (joinPath') && !template.includes('output'));
    }
    for (const number of [1, 2]) {
        const home = path.join(scratch, 'home with spaces-' + number);
        const destination = path.join(home, 'AppData/Local/Dotfiles/DockerSsh');
        fs.mkdirSync(path.join(home, '.docker'), { recursive: true });
        fs.mkdirSync(path.dirname(destination), { recursive: true });
        const marker = path.join(home, '.docker/config.json');
        fs.writeFileSync(marker, '{"publicMarker":"preserve-existing-desktop-config"}\n');
        const markerHash = digest(fs.readFileSync(marker));
        const config = path.join(scratch, 'empty-' + number + '.toml');
        fs.writeFileSync(config, '');
        const common = ['--source', repository, '--destination', home, '--config', config, '--cache', path.join(scratch, 'cache-' + number),
            '--persistent-state', path.join(scratch, 'state-' + number + '.db'), '--no-tty'];
        for (const command of ['apply', 'verify', 'apply']) {
            const response = run('chezmoi', [...common, command, '--exclude=scripts', destination]);
            check('home-' + number + '/' + command + '/' + results.length, response.status === 0);
        }
        check('home-' + number + '/exact-five-public-files', JSON.stringify(fs.readdirSync(destination).sort()) === JSON.stringify([...publicFiles].sort()));
        for (const name of publicFiles) {
            check('home-' + number + '/render/' + name,
                fs.readFileSync(path.join(destination, name), 'utf8').replaceAll('\r\n', '\n').trimEnd() ===
                fs.readFileSync(path.join(moduleRoot, 'chezmoi/AppData/Local/Dotfiles/DockerSsh', name), 'utf8').replaceAll('\r\n', '\n').trimEnd());
        }
        check('home-' + number + '/desktop-config-preserved', digest(fs.readFileSync(marker)) === markerHash);
        check('home-' + number + '/no-installation-initialized', !fs.existsSync(path.join(destination, 'Installations')));
        const ignored = run('chezmoi', [...common, '--override-data', '{"chezmoi":{"os":"linux"}}', 'managed', '--exclude=scripts']);
        check('home-' + number + '/non-windows-excluded', ignored.status === 0 && !ignored.stdout.includes('DockerSsh'));
    }
    const powershellFiles = sourceFiles(moduleRoot).filter(file => file.endsWith('.ps1'));
    const fileList = path.join(scratch, 'powershell-files.json');
    fs.writeFileSync(fileList, JSON.stringify(powershellFiles));
    const parser = run('pwsh', ['-NoProfile', '-CommandWithArgs',
        '$paths=Get-Content -LiteralPath $args[0] -Raw|ConvertFrom-Json;foreach($file in $paths){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors);if($errors.Count){exit 1}}',
        fileList]);
    check('powershell-syntax', parser.status === 0);
    check('original-host-docker-config-preserved', (fs.existsSync(originalDocker) ? digest(fs.readFileSync(originalDocker)) : null) === originalHash);
    console.log('dotfiles-docker-ssh-integration : PASS; assertions=' + results.length + '; keys=0; registry=NONE; other-machine=UNTESTED');
} finally {
    fs.writeFileSync(path.join(scratch, 'results.json'), JSON.stringify({ results, keys: 0, registry: 'NONE', otherMachine: 'UNTESTED' }, null, 2));
    console.log('Evidence: ' + scratch);
}
