"""Test rendered chezmoi policy guards without changing aqua's real trust store."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
SCRIPT_DIRECTORY = REPOSITORY / "chezmoi" / ".chezmoiscripts"
REVIEWED_SHA256 = "c778ce202758b7a5f9c5942140f685ddc814dfa946af35aa0886ec459513e72f"


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

    def render(self, platform):
        """Render a platform-specific guard with the real chezmoi template engine."""
        extension = "ps1" if platform == "windows" else "sh"
        template = SCRIPT_DIRECTORY / f"run_before_aqua-policy.{extension}.tmpl"
        result = subprocess.run(
            [
                self.chezmoi,
                "--source", str(self.source),
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
        script = self.root / f"policy-{platform}.{extension}"
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

    def test_apply_rejects_policy_before_changing_files(self):
        """Run real chezmoi apply and ensure a rejected policy prevents file writes."""
        platform = "windows" if os.name == "nt" else "linux"
        extension = "ps1" if platform == "windows" else "sh"
        scripts = self.source / ".chezmoiscripts"
        scripts.mkdir()
        shutil.copyfile(
            SCRIPT_DIRECTORY / f"run_before_aqua-policy.{extension}.tmpl",
            scripts / f"run_before_aqua-policy.{extension}.tmpl",
        )
        (self.source / "dot_guard-marker").write_text("after\n", encoding="utf-8")
        marker = self.home / ".guard-marker"
        marker.write_text("before\n", encoding="utf-8")
        self.policy.write_bytes(self.policy.read_bytes() + b"# changed\n")
        result = subprocess.run(
            [
                self.chezmoi,
                "--source", str(self.source),
                "--destination", str(self.home),
                "--config", str(self.configuration),
                "--persistent-state", str(self.root / "chezmoi-state.boltdb"),
                "apply", "--force",
            ],
            env=self.environment,
            capture_output=True,
            timeout=30,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"reviewed SHA-256", result.stderr)
        self.assertEqual(marker.read_text(encoding="utf-8"), "before\n")
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
