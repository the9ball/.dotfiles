"""Real isolated Git fixtures and negative controls for the snapshot-only adapter."""

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from common import Denied, digest
from git_snapshot_adapter import GIT_EXECUTABLE, GitSnapshot

RUN_ROOT = None


class GitSnapshotTests(unittest.TestCase):
    """Exercise only fixture-owned Git objects and refs; never touch a shared worktree."""

    def git(self, *arguments, raw=None):
        """Set up this private fixture using fixed test commands and synthetic author data."""
        environment = {"SystemRoot": "C:/Windows", "WINDIR": "C:/Windows", "PATH": str(GIT_EXECUTABLE.parent),
                       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "NUL", "GIT_CONFIG_SYSTEM": "NUL",
                       "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
                       "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"}
        result = subprocess.run([str(GIT_EXECUTABLE), "-C", str(self.root), *arguments],
                                input=raw, capture_output=True, env=environment, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", errors="replace"))
        return result.stdout.strip()

    def setUp(self):
        """Create a new standalone repository with tracked, untracked and ignored files."""
        self.root = Path(tempfile.mkdtemp(prefix="git-case-", dir=RUN_ROOT))
        self.git("init", "--template=", "--initial-branch=fixture")
        (self.root / "tracked.txt").write_bytes(b"first\n")
        (self.root / ".gitignore").write_bytes(b"ignored.txt\n")
        (self.root / "untracked.txt").write_bytes(b"untracked\n")
        (self.root / "ignored.txt").write_bytes(b"ignored\n")
        self.git("add", "--", "tracked.txt", ".gitignore")
        self.tree = self.git("write-tree").decode()
        self.commit = self.git("commit-tree", self.tree, raw=b"fixture object only\n").decode()
        self.git("update-ref", "refs/heads/fixture", self.commit)
        self.names = ["tracked.txt", ".gitignore", "untracked.txt", "ignored.txt"]
        self.adapter = GitSnapshot(self.root, self.names)
        self.expected = self.adapter.freeze()

    def fingerprint(self):
        """Hash Git metadata and all existing fixture file bytes for side-effect checks."""
        return {path.relative_to(self.root).as_posix(): digest(path.read_bytes())
                for path in self.root.rglob("*") if path.is_file()}

    def test_01_stable_and_no_writes(self):
        """Accept a stable real Git tuple while preserving every fixture file and Git byte."""
        before = self.fingerprint()
        result = self.adapter.capture(self.expected)
        self.assertTrue(result["capture_consistent"])
        self.assertFalse(result["dispatch_allowed"])
        self.assertEqual(result["adoption_gate"], "BLOCKED")
        self.assertEqual(before, self.fingerprint())

    def test_02_branch_change(self):
        """Reject a stable new branch even when its commit and protected files match."""
        self.git("update-ref", "refs/heads/other", self.commit)
        self.git("symbolic-ref", "HEAD", "refs/heads/other")
        with self.assertRaises(Denied):
            self.adapter.capture(self.expected)

    def test_03_head_change(self):
        """Reject a new commit with an identical tree on the same branch."""
        other = self.git("commit-tree", self.tree, "-p", self.commit, raw=b"second fixture object\n").decode()
        self.git("update-ref", "refs/heads/fixture", other)
        with self.assertRaises(Denied):
            self.adapter.capture(self.expected)

    def test_04_index_and_git_mode_change(self):
        """Freeze both the real index bytes and its executable-bit intent on Windows."""
        self.git("update-index", "--chmod=+x", "tracked.txt")
        with self.assertRaises(Denied):
            self.adapter.capture(self.expected)

    def test_05_content_change(self):
        """Detect equal-length bytes changing without a change in path membership."""
        (self.root / "tracked.txt").write_bytes(b"other\n")
        with self.assertRaises(Denied):
            self.adapter.capture(self.expected)

    def test_06_os_mode_change(self):
        """Reject changed OS permissions separately from the Git executable bit."""
        path = self.root / "tracked.txt"
        original = path.stat().st_mode
        try:
            path.chmod(stat.S_IREAD)
            with self.assertRaises(Denied):
                self.adapter.capture(self.expected)
        finally:
            path.chmod(original)

    def test_07_unknown_path_is_not_read_or_passed_to_git(self):
        """Refuse a newly appearing ignore file before Git can consume its content."""
        (self.root / "unknown.txt").write_bytes(b"not authorized for capture\n")
        with patch.object(self.adapter, "_git") as command:
            with self.assertRaises(Denied):
                self.adapter.capture(self.expected)
            command.assert_not_called()

    def test_08_missing_path(self):
        """Reject deletion of a known protected file instead of updating the baseline."""
        (self.root / "ignored.txt").unlink()
        with self.assertRaises(Denied):
            self.adapter.capture(self.expected)

    def test_09_junction_outside_scope(self):
        """Reject an actual Windows junction without reading its target content."""
        outside = Path(tempfile.mkdtemp(prefix="link-target-", dir=RUN_ROOT))
        (outside / "outside.txt").write_bytes(b"out of scope\n")
        link = self.root / "escape"
        # cmd.exe parses its native command line; keep its executable spelling native too.
        command = [str(Path("C:/Windows/System32/cmd.exe")), "/d", "/c", "mklink", "/J", str(link), str(outside)]
        probe = {"argv": command, "link_existed": os.path.lexists(link), "target_exists": outside.is_dir()}
        result = subprocess.run(command, capture_output=True, timeout=15)
        probe.update(exit_code=result.returncode, stdout=result.stdout.decode("oem", errors="replace"),
                     stderr=result.stderr.decode("oem", errors="replace"), is_junction=link.is_junction())
        (RUN_ROOT / (self.root.name + "-junction.json")).write_text(json.dumps(probe, indent=2) + "\n", encoding="utf-8")
        self.assertEqual(result.returncode, 0, probe)
        self.assertTrue(link.is_junction())
        self.addCleanup(link.rmdir)
        with patch.object(self.adapter, "_git") as command:
            with self.assertRaises(Denied):
                self.adapter.capture(self.expected)
            command.assert_not_called()

    def test_10_git_failure(self):
        """A nonzero Git acquisition discards the capture and is not retried."""
        failed = subprocess.CompletedProcess([], 128, b"", b"fixture error")
        with patch("git_snapshot_adapter.subprocess.run", return_value=failed) as command:
            with self.assertRaises(Denied):
                self.adapter.capture(self.expected)
            self.assertEqual(command.call_count, 1)

    def test_11_include_config_refused(self):
        """Reject includes before invoking Git rather than following a supplied host path."""
        with (self.root / ".git/config").open("ab") as stream:
            stream.write(b"\n[include]\n\tpath = outside-config\n")
        with patch.object(self.adapter, "_git") as command:
            with self.assertRaises(Denied):
                self.adapter.capture(self.expected)
            command.assert_not_called()

    def test_12_inherited_environment_not_used(self):
        """Inherited routing, command-line config and trace paths never enter the child."""
        injected = {"GIT_DIR": "invalid", "GIT_INDEX_FILE": "invalid", "GIT_CONFIG_COUNT": "1",
                    "GIT_CONFIG_KEY_0": "core.fsmonitor", "GIT_CONFIG_VALUE_0": "bad-command",
                    "GIT_TRACE": str(self.root / "unapproved-trace")}
        with patch.dict(os.environ, injected):
            self.assertTrue(self.adapter.capture(self.expected)["capture_consistent"])
        self.assertFalse((self.root / "unapproved-trace").exists())

    def test_13_scope_escape_and_alias_rejected(self):
        """Reject parent, drive and case-colliding file scopes before content acquisition."""
        for names in (["../outside"], ["C:/outside"], ["tracked.txt", "TRACKED.txt"], [".git/config"]):
            with self.assertRaises(Denied):
                GitSnapshot(self.root, names)

    def test_14_gitlink_refused(self):
        """A gitlink cannot be treated as an ordinary file even if bytes exist there."""
        self.git("update-index", "--cacheinfo", "160000," + self.commit + ",tracked.txt")
        with self.assertRaises(Denied):
            self.adapter.capture(self.expected)

    def test_15_active_config_refused(self):
        """Do not execute a config-provided fsmonitor command or accept its capture."""
        with (self.root / ".git/config").open("ab") as stream:
            stream.write(b"\n[core]\n\tfsmonitor = unexpected-command\n")
        with patch.object(self.adapter, "_git") as command:
            with self.assertRaises(Denied):
                self.adapter.capture(self.expected)
            command.assert_not_called()

    def test_16_change_between_reads(self):
        """Detect a real protected-file change between the two complete snapshots."""
        original = self.adapter.snapshot
        calls = 0

        def acquire():
            """Mutate this fixture only after returning the first real snapshot."""
            nonlocal calls
            result = original()
            calls += 1
            if calls == 1:
                (self.root / "tracked.txt").write_bytes(b"other\n")
            return result

        with patch.object(self.adapter, "snapshot", side_effect=acquire):
            with self.assertRaises(Denied):
                self.adapter.capture(self.expected)
        self.assertEqual(calls, 2)

    def test_17_index_version_refused(self):
        """Reject unsupported index structure without running Git against it."""
        path = self.root / ".git/index"
        path.write_bytes(path.read_bytes()[:7] + b"\x04" + path.read_bytes()[8:])
        with patch.object(self.adapter, "_git") as command:
            with self.assertRaises(Denied):
                self.adapter.capture(self.expected)
            command.assert_not_called()

    def test_18_no_arbitrary_git_arguments(self):
        """The command selector accepts only fixed operation identifiers."""
        with self.assertRaises(Denied):
            self.adapter._git("--config-env=credential.helper=UNSAFE")
