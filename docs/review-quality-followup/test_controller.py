"""Exercise paid-launch guards with mocked processes and isolated test files."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPECIFICATION = importlib.util.spec_from_file_location("review_controller", Path(__file__).with_name("run.py"))
CONTROLLER = importlib.util.module_from_spec(SPECIFICATION)
SPECIFICATION.loader.exec_module(CONTROLLER)


class ControllerGuards(unittest.TestCase):
    """Verify that uncertain or repeated attempts cannot silently spend again."""

    def setUp(self):
        """Give each test a private ledger and a process mock that fails if reached."""
        self.temporary = tempfile.TemporaryDirectory(prefix="issue138-probe-guard-")
        self.directory = Path(self.temporary.name)
        self.receipts = self.directory / "receipts"
        self.receipts.mkdir()
        self.directory_patch = patch.object(CONTROLLER, "DIRECTORY", self.directory)
        self.directory_patch.start()
        self.manifest = {"reviewer_launch_cap": 20, "estimated_usd_ceiling": 12,
                         "per_next_call_reservation_usd": 0.75,
                         "codex_settings": ["gpt-6.1-sol", "medium"]}

    def tearDown(self):
        """Restore the controller and remove only this test's isolated files."""
        self.directory_patch.stop()
        self.temporary.cleanup()

    def assert_blocked(self, label):
        """Require refusal before any process creation attempt."""
        with patch.object(CONTROLLER.subprocess, "Popen") as process:
            with self.assertRaises(RuntimeError):
                CONTROLLER.invoke("codex", label, "free", self.manifest)
            process.assert_not_called()

    def test_existing_label_is_never_overwritten(self):
        """A prior execution artifact reserves its label even without a final receipt."""
        path = self.receipts / "codex-pilot-A-free.execution.json"
        path.write_text("{}", encoding="utf-8")
        self.assert_blocked("codex-pilot-A-free")
        self.assertEqual(path.read_text(encoding="utf-8"), "{}")

    def test_failed_observation_blocks_new_label(self):
        """Unknown charged failures stop all subsequent observations."""
        (self.receipts / "old.failure.json").write_text("{}", encoding="utf-8")
        self.assert_blocked("codex-pilot-B-combined")

    def test_pending_reservation_blocks_new_label(self):
        """An interrupted launch cannot disappear from accounting."""
        CONTROLLER.write_json(self.receipts / "old.launch.json", {"state": "RESERVED"})
        self.assert_blocked("codex-pilot-B-combined")

    def test_reservation_precedes_process_creation(self):
        """Even a process-start exception leaves a durable blocking reservation."""
        invocation = self.directory / "invocation"
        invocation.mkdir()
        with patch.object(CONTROLLER, "make_prompt", return_value="public evidence"), \
                patch.object(CONTROLLER.tempfile, "mkdtemp", return_value=str(invocation)), \
                patch.object(CONTROLLER.subprocess, "Popen", side_effect=RuntimeError("mock startup failure")):
            with self.assertRaisesRegex(RuntimeError, "mock startup failure"):
                CONTROLLER.invoke("codex", "codex-pilot-A-free", "free", self.manifest)
        ledger = CONTROLLER.read_json(self.receipts / "codex-pilot-A-free.launch.json")
        self.assertEqual(ledger["state"], "RESERVED")
        self.assert_blocked("codex-pilot-B-combined")

    def test_shared_coverage_accepts_transport_formats(self):
        """The shared validator supports all documented coverage declaration shapes."""
        for declaration in ("api.py", "api.py:1", "api.py (lines 1–10)",
                            "api.py — API", {"path": "api.py"}):
            CONTROLLER.TRANSPORT.verify_coverage([declaration], ["api.py"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
