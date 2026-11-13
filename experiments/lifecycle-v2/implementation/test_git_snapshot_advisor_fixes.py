"""Focused metadata-link, bounded-worker and executable-attribution negative controls."""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import test_git_snapshot_adapter
from common import Denied
from schema_worker_session import SchemaSession, persist_report, pinned_command


class AdvisorRegressionTests(unittest.TestCase):
    """Operate only on fresh private repos and child processes owned by this test."""

    run_root = None

    def setUp(self):
        """Allocate a unique evidence root without touching older cases."""
        self.directory = Path(tempfile.mkdtemp(prefix="advisor-case-", dir=self.run_root))

    def fixture(self):
        """Reuse existing setup assertions while retaining every original32 test."""
        case = test_git_snapshot_adapter.GitSnapshotTests("test_01_stable_and_no_writes")
        case.setUp()
        return case

    def junction_case(self, name):
        """Reject an actual metadata ancestor junction before any Git invocation."""
        case = self.fixture()
        selected = case.root / ".git" / name
        outside = self.directory / "outside"
        if selected.exists():
            backup = selected.with_name(selected.name + "-fixture-backup")
            self.assertTrue(selected.resolve().is_relative_to(case.root))
            self.assertTrue(backup.absolute().is_relative_to(case.root))
            shutil.copytree(selected, outside)
            selected.rename(backup)
        else:
            outside.mkdir()
        result = subprocess.run([str(Path("C:/Windows/System32/cmd.exe")), "/d", "/c", "mklink", "/J",
                                 str(selected), str(outside)], capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(selected.is_junction())
        self.addCleanup(selected.rmdir)
        with patch.object(case.adapter, "_git") as command:
            with self.assertRaises(Denied):
                case.adapter.capture(case.expected)
            command.assert_not_called()

    def test_01_info_link_rejected_before_git(self):
        """Exclusion and attribute namespace links cannot be delegated to Git."""
        self.junction_case("info")

    def test_02_refs_link_rejected_before_git(self):
        """Object identity cannot be redirected through a linked ref directory."""
        self.junction_case("refs")

    def test_03_objects_link_rejected_before_git(self):
        """Object reads cannot traverse an alternate directory junction."""
        self.junction_case("objects")

    def worker(self, script):
        """Start a fixed harmless Python stub and register owned cleanup immediately."""
        session = SchemaSession([sys.executable, "-I", "-u", "-c", script], self.directory,
                                response_timeout=1, shutdown_timeout=2)
        self.addCleanup(session.close)
        return session

    def test_04_initial_reply_timeout(self):
        """A silent live worker reaches a finite error and cannot count as schema success."""
        session = self.worker("import time; time.sleep(60)")
        with self.assertRaises(TimeoutError):
            session.exchange()
        self.assertTrue(session.failed)
        cleanup = session.close()
        self.assertIsNotNone(cleanup["exit_code"])
        self.assertFalse(cleanup["thread_alive"])

    def test_05_validation_reply_timeout(self):
        """A worker that stops replying after startup is bounded and reaped too."""
        session = self.worker("import sys,time; print('ready',flush=True); sys.stdin.readline(); time.sleep(60)")
        self.assertEqual(session.exchange(), b"ready" + os.linesep.encode("ascii"))
        with self.assertRaises(TimeoutError):
            session.exchange(b"{}\n")
        self.assertTrue(session.failed)
        self.assertIsNotNone(session.close()["exit_code"])

    def test_06_wait_exception_still_persists_failure(self):
        """A shutdown exception cannot skip report persistence or leave the owned stub live."""
        session = self.worker("import time; time.sleep(60)")
        original_wait = session.process.wait
        calls = 0

        def fail_first_wait(timeout=None):
            """Inject one local wait exception before allowing normal owned-process reaping."""
            nonlocal calls
            calls += 1
            if calls == 1:
                raise OSError("fixture shutdown failure")
            return original_wait(timeout=timeout)

        with patch.object(session.process, "wait", side_effect=fail_first_wait):
            report = persist_report(self.directory, {"success": True}, session)
        saved = json.loads((self.directory / "regression-report.json").read_text(encoding="utf-8"))
        self.assertFalse(saved["success"])
        self.assertIn("OSError", report["schema_cleanup"]["errors"])
        self.assertIsNotNone(session.process.poll())

    def test_07_cleanup_exception_still_persists_failure(self):
        """Even an unexpected close-method exception leaves an explicit failed report."""
        def fail_close():
            """Represent an unexpected cleanup failure without creating any child."""
            raise RuntimeError("fixture close exception")

        persist_report(self.directory, {"success": True}, SimpleNamespace(close=fail_close))
        saved = json.loads((self.directory / "regression-report.json").read_text(encoding="utf-8"))
        self.assertFalse(saved["success"])
        self.assertEqual(saved["cleanup_exception"], "RuntimeError")

    def test_08_pinned_image_ignores_hostile_path(self):
        """The symbolic old test command is bound explicitly, independently of PATH."""
        executable = Path(os.environ["LIFECYCLE_SCHEMA_PWSH"]).resolve()
        image = hashlib.sha256(executable.read_bytes()).hexdigest()
        hostile = self.directory / "bin"
        hostile.mkdir()
        (hostile / "pwsh.exe").write_bytes(b"resolution-only fixture")
        with patch.dict(os.environ, {"PATH": str(hostile)}):
            self.assertNotEqual(Path(shutil.which("pwsh.exe")).resolve(), executable)
            command = pinned_command(["pwsh.exe", "-NoProfile"], executable, image)
        self.assertEqual(Path(command[0]), executable)

    def test_09_different_executable_or_image_rejected(self):
        """Explicit image mismatches fail before a schema process can be started."""
        executable = Path(os.environ["LIFECYCLE_SCHEMA_PWSH"]).resolve()
        image = hashlib.sha256(executable.read_bytes()).hexdigest()
        with self.assertRaises(Denied):
            pinned_command([str(self.directory / "different.exe")], executable, image)
        with self.assertRaises(Denied):
            pinned_command(["pwsh.exe"], executable, "0" * 64)

    def protocol_worker(self, phase, reply):
        """Offer a normal reply after one violation in a uniquely owned worker fixture."""
        directory = Path(tempfile.mkdtemp(prefix="protocol-case-", dir=self.directory))
        readiness = b'{"ready":true,"metaschema":true,"format_assertion":true,"explicit_metaschema":true,"input_codepage":65001,"output_codepage":65001}\n'
        script = '''import sys
ready=bytes.fromhex(READY_HEX)
bad=bytes.fromhex(BAD_HEX)
valid=b'{"valid":true}\\n'
def send(reply):
    """Emit one synthetic reply without text newline translation."""
    sys.stdout.buffer.write(reply)
    sys.stdout.buffer.flush()
if PHASE == 'start':
    send(bad)
    send(ready)
    for line in sys.stdin.buffer:
        send(valid)
else:
    send(ready)
    for number,line in enumerate(sys.stdin.buffer):
        send(bad if number == 0 else valid)
'''.replace("READY_HEX", repr(readiness.hex())).replace("BAD_HEX", repr(reply.hex())).replace("PHASE", repr(phase))
        session = SchemaSession([sys.executable, "-I", "-u", "-c", script], directory,
                                response_timeout=5, shutdown_timeout=2)
        self.addCleanup(session.close)
        return session, directory

    def assert_protocol_failure_latched(self, phase):
        """Reject all further I/O and success persistence after each protocol violation."""
        replies = [("invalid-json", b"{\n"), ("list", b"[]\n"), ("null", b"null\n"),
                   ("duplicate-keys", b'{"ready":true,"ready":false,"valid":true,"valid":false}\n'),
                   ("invalid-object", b"{}\n"), ("invalid-utf8", b"\xff\n")]
        for label, reply in replies:
            with self.subTest(phase=phase, reply=label):
                session, directory = self.protocol_worker(phase, reply)
                if phase == "validate":
                    session.start()
                with self.assertRaises((ValueError, Denied)):
                    session.start() if phase == "start" else session.validate({})
                self.assertTrue(session.failed)
                previous_transfer = session.pending
                for operation, arguments in ((session.start, ()), (session.validate, ({},)), (session.exchange, ())):
                    with self.assertRaises(Denied):
                        operation(*arguments)
                    self.assertTrue(session.failed)
                    self.assertIs(session.pending, previous_transfer)
                persist_report(directory, {"success": True}, session)
                saved = json.loads((directory / "regression-report.json").read_text(encoding="utf-8"))
                self.assertFalse(saved["success"])
                self.assertTrue(saved["schema_cleanup"]["transport_failed"])
                self.assertEqual(saved["schema_exit_code"], 0)
                self.assertFalse(saved["schema_cleanup"]["thread_alive"])

    def test_10_startup_protocol_failure_is_permanent(self):
        """Bad readiness cannot recover through another start, verdict or direct exchange."""
        self.assert_protocol_failure_latched("start")

    def test_11_validation_protocol_failure_is_permanent(self):
        """Bad validation cannot recover even when the worker offers a later valid verdict."""
        self.assert_protocol_failure_latched("validate")
