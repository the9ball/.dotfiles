"""Check template expansion and settings syntax without applying dotfiles.

Run: python3 -B tests/chezmoi-templates.py
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def installed_chezmoi():
    """Return the native chezmoi from CHEZMOI_TEST_BINARY, else from `aqua which`.

    Raises ValueError when neither source yields a native chezmoi.
    """
    executable = os.environ.get("CHEZMOI_TEST_BINARY")
    if not executable:
        # Local runs default to the aqua-managed binary; CI always sets the
        # variable during tool installation, so this lookup never runs there.
        aqua = shutil.which("aqua")
        if not aqua:
            raise ValueError("set CHEZMOI_TEST_BINARY or install aqua to locate chezmoi")
        executable = subprocess.check_output(
            [aqua, "which", "chezmoi"], text=True, timeout=30
        ).strip()
    executable = Path(executable).resolve(strict=True)
    if not executable.is_file() or executable.name.lower() in (
        "aqua-proxy", "aqua-proxy.exe",
    ):
        raise ValueError("CHEZMOI_TEST_BINARY must be a native chezmoi, not aqua-proxy")
    return executable


def copy_inputs(repository, checkout):
    """Copy tracked working-tree inputs, excluding host-local overlays and escapes."""
    tracked = subprocess.check_output(
        ["git", "ls-files", "-z"], cwd=repository, timeout=30
    )
    inputs = []
    for encoded_path in tracked.split(b"\0"):
        relative = os.fsdecode(encoded_path)
        if not relative or not (
            relative.startswith(("chezmoi/", "docker-ssh/chezmoi/"))
            or relative in (
                "aqua.yaml", "aqua-registry.yaml", ".pre-commit-config.yaml",
                "winget.json",
            )
        ):
            continue
        original = (repository / relative).resolve(strict=True)
        if not original.is_relative_to(repository):
            raise ValueError(f"input escapes repository: {relative}")
        destination = checkout / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, destination)
        inputs.append(destination)
    return inputs


def isolated_environment(root, executable):
    """Build the child environment without inherited credentials or HOME settings."""
    environment = {
        name: os.environ[name]
        for name in ("SystemRoot", "WINDIR", "COMSPEC", "PATHEXT")
        if name in os.environ
    }
    for name in (
        "HOME", "USERPROFILE", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
        "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA", "TEMP", "TMP",
    ):
        directory = root / name.lower()
        directory.mkdir()
        environment[name] = str(directory)
    environment["PATH"] = str(executable.parent)
    environment["CHEZMOI_TEST_BINARY"] = str(executable)
    environment["AQUA_DISABLE_LAZY_INSTALL"] = "true"
    environment["PYTHONUTF8"] = "1"
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    return environment


def run_checked(arguments, checkout, environment, label, stdin="", binary=False):
    """Capture bounded text or raw-byte output and sanitize failure paths."""
    result = subprocess.run(
        arguments, cwd=checkout, env=environment,
        input=stdin.encode("utf-8") if binary and isinstance(stdin, str) else stdin,
        text=not binary, encoding=None if binary else "utf-8",
        capture_output=True, timeout=120,
    )
    if result.returncode:
        diagnostic = result.stderr or result.stdout
        if isinstance(diagnostic, bytes):
            diagnostic = diagnostic.decode("utf-8", errors="replace")
        diagnostic = diagnostic.replace(str(checkout.parent), "<temporary>")
        raise ValueError(f"{label}: exit {result.returncode}\n{diagnostic}")
    return result


def check_templates(inputs, checkout, root, executable, environment):
    """Render Linux/Windows dummy data and parse JSON/TOML outputs only."""
    import tomllib

    source = checkout / "chezmoi"
    configuration = root / "chezmoi.toml"
    configuration.write_text("", encoding="utf-8")
    targets = [
        path for path in inputs
        if path.is_relative_to(source)
        and ".chezmoitemplates" not in path.relative_to(source).parts
        and (path.suffix == ".tmpl" or path.name.startswith("modify_")
             or path.name in (".chezmoiignore", ".chezmoiexternal.toml"))
    ]
    for operating_system in ("linux", "windows"):
        data_file = root / "data.json"
        data_file.write_text(json.dumps({
            "chezmoi": {
                "os": operating_system, "sourceDir": str(source),
                "homeDir": environment["HOME"],
            },
            "downloadsAgentGuards": True,
        }), encoding="utf-8")
        for path in targets:
            label = f"{path.relative_to(checkout)} [{operating_system}]"
            suffix = Path(path.name.removesuffix(".tmpl")).suffix
            # The config template uses init-only prompt functions, which
            # execute-template defines only in --init mode, where an
            # unanswered prompt returns its zero value instead of asking.
            init_arguments = ["--init"] if path.name == ".chezmoi.toml.tmpl" else []
            result = run_checked([
                str(executable), "--source", str(source),
                "--destination", environment["HOME"],
                "--config", str(configuration),
                "--persistent-state", str(root / "state.boltdb"),
                "--cache", str(root / "cache"),
                "--override-data-file", str(data_file), "--no-tty", "--no-pager",
                "execute-template", *init_arguments, "--with-stdin", "--file", str(path),
            ], checkout, environment, f"{label} expansion",
                "{}" if suffix == ".json" else "")
            try:
                if suffix == ".json":
                    json.loads(result.stdout)
                elif suffix == ".toml":
                    tomllib.loads(result.stdout)
            except ValueError as error:
                raise ValueError(f"{label} {suffix} parse: {error}") from error
        print(f"{operating_system}: {len(targets)} templates expanded; JSON/TOML parsed")


def check_codex_hook_preservation(checkout, root, executable, environment):
    """Preserve unrelated hooks and make reapplication stable for every Codex home."""
    source = checkout / "chezmoi"
    configuration = root / "hook-preservation.toml"
    configuration.write_text("", encoding="utf-8")
    baseline = {
        "fixtureMetadata": {"keep": True},
        "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "fixture-stop"}]}],
            "PreToolUse": [{
                "matcher": "^fixture$",
                "hooks": [{"type": "command", "command": "fixture-tool"}],
            }],
        },
    }
    for operating_system in ("linux", "windows"):
        data_file = root / "hook-preservation-data.json"
        data_file.write_text(json.dumps({
            "chezmoi": {
                "os": operating_system, "sourceDir": str(source),
                "homeDir": environment["HOME"],
            },
        }), encoding="utf-8")
        for home in ("dot_codex", "dot_codex-personal", "dot_codex-wsl"):
            path = source / home / "modify_hooks.json"
            arguments = [
                str(executable), "--source", str(source),
                "--destination", environment["HOME"],
                "--config", str(configuration),
                "--persistent-state", str(root / "state.boltdb"),
                "--cache", str(root / "cache"),
                "--override-data-file", str(data_file), "--no-tty", "--no-pager",
                "execute-template", "--with-stdin", "--file", str(path),
            ]
            label = f"{home} hook preservation [{operating_system}]"
            first = run_checked(
                arguments, checkout, environment, label, json.dumps(baseline), binary=True,
            )
            rendered = json.loads(first.stdout)
            if (rendered.get("fixtureMetadata") != baseline["fixtureMetadata"]
                    or rendered["hooks"].get("Stop") != baseline["hooks"]["Stop"]
                    or baseline["hooks"]["PreToolUse"][0]
                    not in rendered["hooks"].get("PreToolUse", [])):
                raise ValueError(f"{label}: unrelated configuration changed")
            managed = [
                handler
                for group in rendered["hooks"]["PreToolUse"]
                for handler in group.get("hooks", [])
                if "gh_auth_status_json_gate.py" in handler.get("command", "")
            ]
            if len(managed) != 1:
                raise ValueError(f"{label}: expected one managed auth handler")
            second = run_checked(
                arguments, checkout, environment, label + " reapply", first.stdout, binary=True,
            )
            if second.stdout != first.stdout:
                raise ValueError(f"{label}: reapply was not byte-stable")
    print("Codex homes: Stop preservation and stable reapplication passed")


def main():
    """Run template expansion and settings syntax checks with temporary state only."""
    if sys.version_info < (3, 11):
        raise ValueError("Python 3.11 or newer is required")
    repository = Path(__file__).resolve().parents[1]
    executable = installed_chezmoi()
    print(f"Python {sys.version.split()[0]}", flush=True)
    with tempfile.TemporaryDirectory(prefix="chezmoi-template-check-") as temporary:
        root = Path(temporary)
        checkout = root / "checkout"
        inputs = copy_inputs(repository, checkout)
        environment = isolated_environment(root, executable)
        check_templates(inputs, checkout, root, executable, environment)
        check_codex_hook_preservation(checkout, root, executable, environment)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"chezmoi check failed: {error}", file=sys.stderr)
        sys.exit(1)
