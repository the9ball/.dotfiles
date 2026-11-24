"""Check template expansion and settings syntax without applying dotfiles.

Run: python3 -B tests/chezmoi-templates.py
"""

import json
import os
from pathlib import Path
import re
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


def codex_hook_arguments(executable, source, environment, configuration, root, data_file, path):
    """Return the chezmoi execute-template arguments for one Codex modify_hooks.json."""
    return [
        str(executable), "--source", str(source),
        "--destination", environment["HOME"],
        "--config", str(configuration),
        "--persistent-state", str(root / "state.boltdb"),
        "--cache", str(root / "cache"),
        "--override-data-file", str(data_file), "--no-tty", "--no-pager",
        "execute-template", "--with-stdin", "--file", str(path),
    ]


def handlers_with(groups, command_fragment):
    """Return the handlers in the given matcher groups whose command contains the fragment."""
    return [
        handler
        for group in groups
        for handler in group.get("hooks", [])
        if command_fragment in handler.get("command", "")
    ]


def check_codex_hook_preservation(checkout, root, executable, environment):
    """Preserve unrelated hooks, manage the guard only in Windows homes, and reapply stably."""
    source = checkout / "chezmoi"
    configuration = root / "hook-preservation.toml"
    configuration.write_text("", encoding="utf-8")
    unrelated_stop = {"hooks": [{"type": "command", "command": "fixture-stop"}]}
    baseline = {
        "fixtureMetadata": {"keep": True},
        "hooks": {
            "Stop": [unrelated_stop],
            "PreToolUse": [{
                "matcher": "^fixture$",
                "hooks": [{"type": "command", "command": "fixture-tool"}],
            }],
        },
    }
    guard_homes = {("windows", "dot_codex"), ("windows", "dot_codex-personal")}
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
            arguments = codex_hook_arguments(
                executable, source, environment, configuration, root, data_file, path,
            )
            label = f"{home} hook preservation [{operating_system}]"
            first = run_checked(
                arguments, checkout, environment, label, json.dumps(baseline), binary=True,
            )
            rendered = json.loads(first.stdout)
            if (rendered.get("fixtureMetadata") != baseline["fixtureMetadata"]
                    or baseline["hooks"]["PreToolUse"][0]
                    not in rendered["hooks"].get("PreToolUse", [])):
                raise ValueError(f"{label}: unrelated configuration changed")
            expected_auth_group = {"matcher": "^Bash$", "hooks": [{
                "type": "command", "timeout": 10,
                "command": "uv run --managed-python --no-project --no-python-downloads --python 3.13"
                           " ~/.agents/hooks/gh_auth_status_json_gate.py",
                "commandWindows": "uv run --managed-python --no-project --no-python-downloads --python 3.13"
                                  f' "{environment["HOME"]}/.agents/hooks/gh_auth_status_json_gate.py"',
            }]}
            if rendered["hooks"]["PreToolUse"] != [baseline["hooks"]["PreToolUse"][0], expected_auth_group]:
                raise ValueError(f"{label}: expected the existing group and then the exact auth gate group")
            stop_groups = rendered["hooks"].get("Stop")
            if (operating_system, home) in guard_homes:
                guard_handlers = handlers_with(stop_groups, "japanese_guard.py")
                if (stop_groups[:-1] != [unrelated_stop] or len(guard_handlers) != 1
                        or not guard_handlers[0]["command"].endswith("--agent codex")
                        or not guard_handlers[0]["commandWindows"].endswith("--agent codex")
                        or "matcher" in stop_groups[-1]):
                    raise ValueError(f"{label}: expected the existing Stop and one guard group at the end")
            elif stop_groups != baseline["hooks"]["Stop"]:
                raise ValueError(f"{label}: Stop changed in a home without the guard")
            second = run_checked(
                arguments, checkout, environment, label + " reapply", first.stdout, binary=True,
            )
            if second.stdout != first.stdout:
                raise ValueError(f"{label}: reapply was not byte-stable")
            if (operating_system, home) == ("windows", "dot_codex"):
                check_codex_managed_input_patterns(
                    checkout, environment, arguments, label, json.loads(first.stdout),
                )
    print("Codex homes: Stop preservation, guard placement, and stable reapplication passed")


def check_codex_managed_input_patterns(checkout, environment, arguments, label, complete):
    """Check duplicate detection, partial updates, and byte-for-byte write-back of complete input."""
    auth_group = next(
        group for group in complete["hooks"]["PreToolUse"]
        if handlers_with([group], "gh_auth_status_json_gate.py")
    )
    guard_group = complete["hooks"]["Stop"][-1]

    # A complete file written with its own whitespace must come back byte for byte.
    custom_text = json.dumps(complete, indent=1, separators=(",", " : ")) + "\n\n"
    custom_result = run_checked(
        arguments, checkout, environment, label + " custom formatting", custom_text, binary=True,
    )
    if custom_result.stdout != custom_text.encode("utf-8"):
        raise ValueError(f"{label}: a complete file was not written back byte for byte")

    # Only the guard is outdated: it is updated in place and the auth handler stays as it was.
    partial = json.loads(json.dumps(complete))
    partial["hooks"]["Stop"][-1]["hooks"][0]["timeout"] = 1
    partial_rendered = json.loads(run_checked(
        arguments, checkout, environment, label + " partial update", json.dumps(partial), binary=True,
    ).stdout)
    if (partial_rendered["hooks"]["Stop"] != complete["hooks"]["Stop"]
            or partial_rendered["hooks"]["PreToolUse"] != complete["hooks"]["PreToolUse"]):
        raise ValueError(f"{label}: a partly outdated file was not repaired in place")

    # Only the auth gate is outdated: it is updated in place and the guard's Stop stays as it was.
    auth_outdated = json.loads(json.dumps(complete))
    for group in auth_outdated["hooks"]["PreToolUse"]:
        for handler in handlers_with([group], "gh_auth_status_json_gate.py"):
            handler["timeout"] = 1
    auth_outdated_rendered = json.loads(run_checked(
        arguments, checkout, environment, label + " auth partial update",
        json.dumps(auth_outdated), binary=True,
    ).stdout)
    if (auth_outdated_rendered["hooks"]["PreToolUse"] != complete["hooks"]["PreToolUse"]
            or auth_outdated_rendered["hooks"]["Stop"] != complete["hooks"]["Stop"]):
        raise ValueError(f"{label}: an outdated auth gate was not repaired in place")

    # The auth gate under another matcher moves to its own group at the end; Stop is untouched.
    auth_moved = json.loads(json.dumps(complete))
    auth_moved["hooks"]["PreToolUse"] = [
        group for group in auth_moved["hooks"]["PreToolUse"] if group != auth_group
    ] + [{"matcher": "^Other$", "hooks": auth_group["hooks"] + [
        {"type": "command", "command": "fixture-auth-neighbor"},
    ]}]
    auth_moved_rendered = json.loads(run_checked(
        arguments, checkout, environment, label + " auth matcher move",
        json.dumps(auth_moved), binary=True,
    ).stdout)
    expected_tool = [group for group in complete["hooks"]["PreToolUse"] if group != auth_group] + [
        {"matcher": "^Other$", "hooks": [{"type": "command", "command": "fixture-auth-neighbor"}]},
        auth_group,
    ]
    if (auth_moved_rendered["hooks"]["PreToolUse"] != expected_tool
            or auth_moved_rendered["hooks"]["Stop"] != complete["hooks"]["Stop"]):
        raise ValueError(f"{label}: the auth gate was not moved out of the other matcher group")

    # The guard under a matcher group is moved to its own group without a matcher.
    moved = json.loads(json.dumps(complete))
    moved["hooks"]["Stop"][-1] = {"matcher": "^fixture$", "hooks": guard_group["hooks"] + [
        {"type": "command", "command": "fixture-neighbor"},
    ]}
    moved_rendered = json.loads(run_checked(
        arguments, checkout, environment, label + " matcher move", json.dumps(moved), binary=True,
    ).stdout)
    expected_stop = complete["hooks"]["Stop"][:-1] + [
        {"matcher": "^fixture$", "hooks": [{"type": "command", "command": "fixture-neighbor"}]},
        guard_group,
    ]
    if moved_rendered["hooks"]["Stop"] != expected_stop:
        raise ValueError(f"{label}: the guard was not moved out of the matcher group")

    # Adding only the missing guard must not add a description or touch anything but Stop.
    without_guard = json.loads(json.dumps(complete))
    del without_guard["description"]
    without_guard["hooks"]["Stop"] = without_guard["hooks"]["Stop"][:-1]
    added_rendered = json.loads(run_checked(
        arguments, checkout, environment, label + " guard only", json.dumps(without_guard), binary=True,
    ).stdout)
    expected_added = json.loads(json.dumps(without_guard))
    expected_added["hooks"]["Stop"].append(guard_group)
    if added_rendered != expected_added:
        raise ValueError(f"{label}: adding the guard changed more than Stop")

    # An empty-string matcher is not the same as no matcher: the guard moves to its own group.
    empty_matcher = json.loads(json.dumps(complete))
    empty_matcher["hooks"]["Stop"][-1] = dict(guard_group, matcher="")
    empty_matcher_rendered = json.loads(run_checked(
        arguments, checkout, environment, label + " empty matcher", json.dumps(empty_matcher), binary=True,
    ).stdout)
    if empty_matcher_rendered["hooks"]["Stop"] != complete["hooks"]["Stop"]:
        raise ValueError(f"{label}: the guard under an empty matcher was not moved")

    # The guard alone in a group with other keys stops the apply instead of dropping those keys.
    keyed_group = json.loads(json.dumps(complete))
    keyed_group["hooks"]["Stop"][-1] = dict(guard_group, matcher="^old$", note="keep")
    try:
        run_checked(
            arguments, checkout, environment, label + " keyed group", json.dumps(keyed_group), binary=True,
        )
    except ValueError as error:
        if "sits alone in a group with other keys" not in str(error):
            raise
    else:
        raise ValueError(f"{label}: a keyed group holding only the guard did not stop the apply")

    # Duplicates of one managed command stop the apply, even across different matchers.
    for event_name, group in (("Stop", guard_group), ("PreToolUse", auth_group)):
        duplicated = json.loads(json.dumps(complete))
        duplicated["hooks"][event_name].append(dict(group, matcher="^other$"))
        try:
            run_checked(
                arguments, checkout, environment, f"{label} duplicate {event_name}",
                json.dumps(duplicated), binary=True,
            )
        except ValueError as error:
            if "found in hooks." + event_name not in str(error):
                raise
        else:
            raise ValueError(f"{label}: duplicate {event_name} handlers did not stop the apply")


def check_claude_japanese_guard_hooks(checkout, root, executable, environment):
    """Register the Japanese guard once per event and keep unrelated Claude hooks."""
    source = checkout / "chezmoi"
    path = source / "dot_claude" / "modify_settings.json"
    configuration = root / "claude-guard.toml"
    configuration.write_text("", encoding="utf-8")
    script_marker = "/.agents/hooks/japanese_guard.py"
    runner = "uv run --managed-python --no-project --no-python-downloads --python 3.13"
    # The managed shape: the runner and one bare or double-quoted script argument, nothing after it.
    managed_pattern = re.compile(
        "^" + re.escape(runner) + ' ("[^"$`\\\\]*' + re.escape(script_marker)
        + '"|[-A-Za-z0-9_.~/:]*' + re.escape(script_marker) + ")$"
    )
    unrelated_stop = {"hooks": [{"type": "command", "command": "fixture-stop"}]}
    # Commands that mention the guard's path but are not the managed shape must be kept.
    kept_lookalikes = [
        {"type": "command", "command": "python ~" + script_marker + ".bak"},
        {"type": "command", "command": "python audit.py ~" + script_marker},
        {"type": "command", "command": runner + " '/home/old user" + script_marker + "'"},
        {"type": "command", "command": runner + " audit.py</tmp" + script_marker},
        {"type": "command", "command": runner + ' "$(fixture)' + script_marker + '"'},
    ]
    unrelated_tool = {"matcher": "^fixture$", "hooks": [{"type": "command", "command": "fixture-tool"}]}
    baseline = {
        "fixtureMetadata": {"keep": True},
        "hooks": {
            "Stop": [
                unrelated_stop,
                {"hooks": [
                    {"type": "command", "command": "fixture-shared"},
                    {"type": "command", "command": runner + ' "C:/old home' + script_marker + '"'},
                    *kept_lookalikes,
                ]},
            ],
            "PreToolUse": [unrelated_tool],
        },
    }
    # A home directory with a space checks that the Windows command quotes the script path.
    home_directory = str(root / "home with space").replace("\\", "/")
    for operating_system in ("linux", "windows"):
        data_file = root / "claude-guard-data.json"
        data_file.write_text(json.dumps({
            "chezmoi": {"os": operating_system, "sourceDir": str(source), "homeDir": home_directory},
        }), encoding="utf-8")
        arguments = [
            str(executable), "--source", str(source),
            "--destination", environment["HOME"],
            "--config", str(configuration),
            "--persistent-state", str(root / "state.boltdb"),
            "--cache", str(root / "cache"),
            "--override-data-file", str(data_file), "--no-tty", "--no-pager",
            "execute-template", "--with-stdin", "--file", str(path),
        ]
        label = f"Claude Japanese guard [{operating_system}]"
        first = run_checked(arguments, checkout, environment, label, json.dumps(baseline), binary=True)
        rendered = json.loads(first.stdout)
        hooks = rendered["hooks"]
        if rendered.get("fixtureMetadata") != baseline["fixtureMetadata"]:
            raise ValueError(f"{label}: unrelated configuration changed")
        kept_shared_group = {"hooks": [{"type": "command", "command": "fixture-shared"}, *kept_lookalikes]}
        if hooks["Stop"][:2] != [unrelated_stop, kept_shared_group]:
            raise ValueError(f"{label}: unrelated Stop handlers changed")
        if hooks["PreToolUse"][0] != unrelated_tool:
            raise ValueError(f"{label}: unrelated PreToolUse handlers changed")
        if not any("dotfiles:language-reminder" in handler.get("command", "")
                   for group in hooks.get("UserPromptSubmit", []) for handler in group.get("hooks", [])):
            raise ValueError(f"{label}: language reminder is missing")
        expected_command = (
            f'uv run --managed-python --no-project --no-python-downloads --python 3.13 "{home_directory}{script_marker}"'
            if operating_system == "windows"
            else "uv run --managed-python --no-project --no-python-downloads --python 3.13 ~/.agents/hooks/japanese_guard.py"
        )
        expected_handler = {"type": "command", "command": expected_command, "timeout": 15}
        expected_groups = {
            "Stop": {"hooks": [expected_handler]},
            "PreToolUse": {"matcher": "mcp__.*__wrap_up", "hooks": [expected_handler]},
        }
        for event_name, expected_group in expected_groups.items():
            managed = [
                handler for group in hooks[event_name] for handler in group.get("hooks", [])
                if managed_pattern.match(handler.get("command", ""))
            ]
            if len(managed) != 1 or hooks[event_name][-1] != expected_group:
                raise ValueError(f"{label}: expected one guard group at the end of {event_name}")
        second = run_checked(arguments, checkout, environment, label + " reapply", first.stdout, binary=True)
        if second.stdout != first.stdout:
            raise ValueError(f"{label}: reapply was not byte-stable")
    print("Claude settings: Japanese guard registration passed")


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
        check_claude_japanese_guard_hooks(checkout, root, executable, environment)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"chezmoi check failed: {error}", file=sys.stderr)
        sys.exit(1)
