"""Test rendered chezmoi policy guards without changing aqua's real trust store."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
SCRIPT_DIRECTORY = REPOSITORY / "chezmoi" / ".chezmoiscripts"
REVIEWED_SHA256 = "8c97ba57b40cd27bee28bbd0de7e958a3a9da6113dea1f3cdc7ce6f0a83c42e7"


class AquaPolicyTests(unittest.TestCase):
    """Exercise the actual rendered scripts with an isolated aqua executable."""

    def setUp(self):
        """Create a repository fixture and mock executables outside the real home."""
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="aqua-policy-test-")
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name) / "repository with spaces"
        self.source = self.root / "chezmoi"
        self.source.mkdir(parents=True)
        self.home = self.root / "home"
        self.home.mkdir()
        self.policy = self.root / "aqua-policy.yaml"
        self.policy.write_bytes((REPOSITORY / "aqua-policy.yaml").read_bytes())
        self.configuration = self.root / "chezmoi.toml"
        self.configuration.write_text("", encoding="utf-8")
        self.mock_directory = self.root / "bin"
        self.mock_directory.mkdir()
        self.log = self.root / "aqua-calls"
        self.environment = os.environ.copy()
        self.environment["PATH"] = str(self.mock_directory) + os.pathsep + os.environ["PATH"]
        self.environment["AQUA_TEST_LOG"] = self.log.as_posix()
        self.environment["AQUA_TEST_EXIT"] = "0"
        mock_shell_path = self.mock_directory.as_posix()
        if os.name == "nt":
            mock_shell_path = "/" + mock_shell_path[0].lower() + mock_shell_path[2:]
        self.environment["AQUA_TEST_BIN"] = mock_shell_path
        self.environment["AQUA_TEST_ONLY_BIN"] = "0"
        self.write_shell_command(
            "aqua",
            'printf "%s\\n" "$*" >> "$AQUA_TEST_LOG"\nexit "$AQUA_TEST_EXIT"\n',
        )
        (self.mock_directory / "aqua.cmd").write_text(
            '@echo off\necho %*>>"%AQUA_TEST_LOG%"\nexit /b %AQUA_TEST_EXIT%\n',
            encoding="utf-8",
        )
        aqua = shutil.which("aqua")
        self.assertIsNotNone(aqua, "aqua is required to resolve the installed chezmoi binary")
        # Resolve the native binary before injecting mock aqua into PATH; the
        # aqua proxy otherwise delegates chezmoi itself to the mock executable.
        self.chezmoi = subprocess.check_output(
            [aqua, "which", "chezmoi"], encoding="utf-8", timeout=30
        ).strip()
        self.powershell = shutil.which("pwsh")
        self.shell = shutil.which("sh")
        if os.name == "nt" and not self.shell:
            git = Path(shutil.which("git"))
            candidate = git.parent.parent / "usr" / "bin" / "sh.exe"
            if candidate.is_file():
                self.shell = str(candidate)

    def write_shell_command(self, name, body):
        """Write an executable POSIX mock with explicit LF line endings."""
        command = self.mock_directory / name
        command.write_text("#!/bin/sh\n" + body, encoding="utf-8", newline="\n")
        command.chmod(0o755)

    def render(self, platform, template=None, source=None):
        """Render a source script for an OS selector and optional repository fixture."""
        extension = "ps1" if platform == "windows" else "sh"
        template = template or SCRIPT_DIRECTORY / f"run_before_00-aqua-policy.{extension}.tmpl"
        result = subprocess.run(
            [
                self.chezmoi,
                "--source", str(source or self.source),
                "--destination", str(self.home),
                "--config", str(self.configuration),
                "--persistent-state", str(self.root / "chezmoi-state.boltdb"),
                "--override-data", json.dumps({"chezmoi": {"os": platform}}),
                "execute-template", "--file", str(template),
            ],
            capture_output=True,
            check=True,
            timeout=30,
        )
        script = self.root / f"{platform}-{template.stem}"
        script.write_bytes(result.stdout)
        return script

    def run_guard(self, platform):
        """Execute a rendered guard, recording only calls to the mock aqua."""
        script = self.render(platform)
        self.log.unlink(missing_ok=True)
        if platform == "windows":
            if not self.powershell:
                self.skipTest("pwsh is required to execute the Windows guard")
            command = [self.powershell, "-NoProfile", "-File", str(script)]
        else:
            if not self.shell:
                self.skipTest("a POSIX shell is required to execute the shell guard")
            # Git for Windows' shell launcher prepends directories to PATH.
            # Set the mock search path after startup to keep real aqua out.
            command = [
                self.shell, "-c",
                'if [ "$AQUA_TEST_ONLY_BIN" = 1 ]; then PATH="$AQUA_TEST_BIN"; '
                'else PATH="$AQUA_TEST_BIN:$PATH"; fi; export PATH; . "$1"',
                "policy-test", str(script),
            ]
        return subprocess.run(
            command,
            env=self.environment,
            capture_output=True,
            timeout=30,
        )

    def test_reviewed_policy_matches_pin(self):
        """Keep the reviewed fixture independent from the scripts' literal digests."""
        self.assertEqual(hashlib.sha256(self.policy.read_bytes()).hexdigest(), REVIEWED_SHA256)

    def test_before_script_names_reserve_guard_slot(self):
        """Reserve 00- for both guards and require later numbers only for before scripts."""
        guard_names = {
            "run_before_00-aqua-policy.ps1.tmpl",
            "run_before_00-aqua-policy.sh.tmpl",
        }
        found_guards = set()
        for script in SCRIPT_DIRECTORY.rglob("*"):
            if not script.is_file():
                continue
            match = re.fullmatch(r"run_(?:(?:once|onchange)_)?before_(.+)", script.name)
            if not match:
                continue
            relative_name = script.relative_to(SCRIPT_DIRECTORY).as_posix()
            with self.subTest(script=relative_name):
                if relative_name in guard_names:
                    found_guards.add(relative_name)
                else:
                    self.assertRegex(
                        match.group(1), r"^[1-9][0-9]-",
                        "00- is reserved for the policy guards; use 10-, 20-, etc.",
                    )
        self.assertEqual(found_guards, guard_names)

    def test_matching_policy_is_approved(self):
        """Approve the matching policy on Windows, Linux, and macOS selectors."""
        for platform in ("windows", "linux", "darwin"):
            with self.subTest(platform=platform):
                result = self.run_guard(platform)
                self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
                calls = self.log.read_text(encoding="utf-8").splitlines()
                self.assertEqual(len(calls), 1)
                self.assertEqual(
                    calls[0].replace("\\", "/").replace('"', ""),
                    f"policy allow {self.policy.as_posix()}",
                )

    def test_changed_policy_is_rejected_before_approval(self):
        """Reject even a comment-only policy change without invoking aqua."""
        self.policy.write_bytes(self.policy.read_bytes() + b"# changed\n")
        for platform in ("windows", "linux", "darwin"):
            with self.subTest(platform=platform):
                result = self.run_guard(platform)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"reviewed SHA-256", result.stderr)
                self.assertFalse(self.log.exists())

    def test_missing_policy_is_rejected_before_approval(self):
        """Stop on a missing policy instead of approving or continuing."""
        self.policy.unlink()
        for platform in ("windows", "linux", "darwin"):
            with self.subTest(platform=platform):
                self.assertNotEqual(self.run_guard(platform).returncode, 0)
                self.assertFalse(self.log.exists())

    def test_approval_failure_is_propagated(self):
        """Fail the script when aqua cannot persist its approval."""
        self.environment["AQUA_TEST_EXIT"] = "23"
        for platform in ("windows", "linux", "darwin"):
            with self.subTest(platform=platform):
                self.assertNotEqual(self.run_guard(platform).returncode, 0)
                self.assertTrue(self.log.exists())

    def test_checksum_command_failure_is_propagated(self):
        """Stop when sha256sum fails even if another hash tool might be available."""
        self.write_shell_command("sha256sum", "exit 17\n")
        for platform in ("linux", "darwin"):
            with self.subTest(platform=platform):
                self.assertNotEqual(self.run_guard(platform).returncode, 0)
                self.assertFalse(self.log.exists())

    def test_shasum_fallback(self):
        """Use the macOS-compatible hash command when sha256sum is unavailable."""
        self.environment["AQUA_TEST_ONLY_BIN"] = "1"
        self.write_shell_command(
            "shasum",
            '[ "$1" = "-a" ] && [ "$2" = "256" ] || exit 19\n'
            f'printf "%s  %s\\n" "{REVIEWED_SHA256}" "$3"\n',
        )
        result = self.run_guard("darwin")
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertTrue(self.log.exists())

    def test_missing_hash_tools_are_rejected(self):
        """Never approve a policy when neither supported hash tool exists."""
        self.environment["AQUA_TEST_ONLY_BIN"] = "1"
        result = self.run_guard("linux")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"sha256sum or shasum is required", result.stderr)
        self.assertFalse(self.log.exists())

    def make_apply_fixture(self, platform, outcome):
        """Render the real script inventory and replace non-guard effects with markers."""
        fixture = self.root / f"{platform}-{outcome}"
        source = fixture / "chezmoi"
        scripts = source / ".chezmoiscripts"
        scripts.mkdir(parents=True)
        home = fixture / "home"
        home.mkdir()
        for repository_file in ("AGENTS.md", ".chezmoiignore"):
            shutil.copyfile(REPOSITORY / "chezmoi" / repository_file, source / repository_file)
        for dependency in ("aqua.yaml", "aqua-registry.yaml", "winget.json", ".pre-commit-config.yaml"):
            shutil.copyfile(REPOSITORY / dependency, fixture / dependency)
        policy = fixture / "aqua-policy.yaml"
        policy.write_bytes(self.policy.read_bytes())
        if outcome == "mismatch":
            policy.write_bytes(policy.read_bytes() + b"# changed\n")
        self.environment["AQUA_TEST_EXIT"] = "23" if outcome == "approval-failure" else "0"
        self.log.unlink(missing_ok=True)
        active_scripts = []
        for template in sorted(SCRIPT_DIRECTORY.rglob("*")):
            if not template.is_file():
                continue
            relative = template.relative_to(SCRIPT_DIRECTORY)
            destination = scripts / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            rendered = self.render(platform, template, source).read_bytes()
            if not rendered.strip():
                destination.write_bytes(b"")
                continue
            active_scripts.append(relative.as_posix())
            if relative.name.startswith("run_before_00-aqua-policy."):
                destination.write_bytes(rendered)
            else:
                self.write_effect_marker(destination, relative.as_posix(), platform)
        extension = "ps1" if platform == "windows" else "sh"
        sentinel = scripts / f"run_before_10-test-side-effect.{extension}"
        self.write_effect_marker(sentinel, "additional-before", platform)
        (source / "dot_guard-marker").write_text("after\n", encoding="utf-8")
        marker = home / ".guard-marker"
        marker.write_text("before\n", encoding="utf-8")
        configuration = fixture / "chezmoi.toml"
        if platform == "windows":
            interpreter = self.powershell
            arguments = ["-NoProfile", "-File"]
        else:
            interpreter = self.shell
            arguments = [
                "-c", 'PATH="$AQUA_TEST_BIN:$PATH"; export PATH; . "$1"', "policy-test"
            ]
        if not interpreter:
            self.skipTest(f"interpreter for {platform} is required")
        configuration.write_text(
            f"[interpreters.{extension}]\ncommand = {json.dumps(interpreter)}\n"
            f"args = {json.dumps(arguments)}\n",
            encoding="utf-8",
        )
        return fixture, source, home, configuration, marker, active_scripts

    def write_effect_marker(self, destination, label, platform):
        """Replace a script's external effects with a trace while preserving its name."""
        if platform == "windows":
            content = f"Add-Content -LiteralPath $env:AQUA_TEST_LOG -Value 'script:{label}'\n"
        else:
            content = f'#!/bin/sh\nprintf "%s\\n" "script:{label}" >> "$AQUA_TEST_LOG"\n'
        destination.write_text(content, encoding="utf-8", newline="\n")

    def run_apply_fixture(self, platform, fixture, source, home, configuration):
        """Apply an isolated platform fixture with chezmoi's actual script scheduler."""
        return subprocess.run(
            [
                self.chezmoi,
                "--source", str(source),
                "--destination", str(home),
                "--config", str(configuration),
                "--persistent-state", str(fixture / "chezmoi-state.boltdb"),
                "--override-data", json.dumps({"chezmoi": {"os": platform}}),
                "apply", "--force",
            ],
            env=self.environment,
            capture_output=True,
            timeout=30,
        )
    def test_apply_orders_actual_scripts_before_any_effects(self):
        """Stop before other scripts and writes, and prove those effects run on success."""
        for platform in ("windows", "linux", "darwin"):
            for outcome in ("mismatch", "approval-failure", "match"):
                with self.subTest(platform=platform, outcome=outcome):
                    fixture, source, home, config, marker, active = self.make_apply_fixture(platform, outcome)
                    result = self.run_apply_fixture(platform, fixture, source, home, config)
                    self.assertFalse((home / "AGENTS.md").exists())
                    calls = self.log.read_text(encoding="utf-8").splitlines() if self.log.exists() else []
                    if outcome == "match":
                        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
                        self.assertTrue(calls[0].startswith("policy allow "), calls)
                        expected = {f"script:{name}" for name in active if "00-aqua-policy" not in name}
                        expected.add("script:additional-before")
                        self.assertEqual(set(calls[1:]), expected)
                        self.assertEqual(len(calls) - 1, len(expected))
                        self.assertEqual(marker.read_text(encoding="utf-8"), "after\n")
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(marker.read_text(encoding="utf-8"), "before\n")
                        if outcome == "mismatch":
                            self.assertIn(b"reviewed SHA-256", result.stderr)
                            self.assertEqual(calls, [])
                        else:
                            self.assertEqual(len(calls), 1)
                            self.assertTrue(calls[0].startswith("policy allow "), calls)


if __name__ == "__main__":
    unittest.main()
