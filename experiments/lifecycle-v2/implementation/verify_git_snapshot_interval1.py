"""Run bounded Git/capture/schema checks with one pinned PowerShell image."""

import hashlib
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import test_git_snapshot_adapter
import test_v2
from common import ROOT
from schema_worker_session import SchemaSession, persist_report, pinned_command
from test_capture_kernel import CaptureKernelTests
from verify_epoch11 import RecordedResult


class BoundSchemaTests(test_v2.V2Tests):
    """Preserve existing assertions while binding the negative schema subprocess explicitly."""

    executable = None
    executable_sha256 = None

    def negative_worker(self, command, **keywords):
        """Run the unchanged invalid-schema oracle on the same pinned executable."""
        fixed = pinned_command(command, self.executable, self.executable_sha256)
        if fixed[1:6] != ["-NoLogo", "-NoProfile", "-NonInteractive", "-File", str(ROOT / "schema-worker.ps1")]:
            raise ValueError("Unexpected negative-schema invocation")
        result = subprocess.run(fixed, **keywords)
        (self.fixture.directory / "pinned-negative-worker.json").write_text(json.dumps(
            {"argv": fixed, "image_sha256": self.executable_sha256, "exit_code": result.returncode}, indent=2) + "\n", encoding="utf-8")
        return result

    def test_00_explicit_metaschema_rejects_invalid_schema(self):
        """Execute the original negative assertions with only its process binding adapted."""
        with patch.object(test_v2, "subprocess", SimpleNamespace(run=self.negative_worker)):
            super().test_00_explicit_metaschema_rejects_invalid_schema()


def main():
    """Persist every verification failure and release only this run's owned worker."""
    allowed = ROOT.parents[2] / ".local/lifecycle-v2-integration-results/git-snapshot/interval1"
    output = Path(sys.argv[1]).resolve()
    if not output.is_relative_to(allowed.resolve()) or output == allowed.resolve():
        raise ValueError("Explicit new interval output directory required")
    if not output.is_dir() or (output / "regression-report.json").exists():
        raise ValueError("New run directory with no prior regression report required")
    fixtures = output / "fixtures"
    fixtures.mkdir()
    test_v2.RUN_ROOT = fixtures
    test_git_snapshot_adapter.RUN_ROOT = fixtures
    report = {"adoption_gate": "BLOCKED", "success": False,
              "scope": "Existing32 plus focused Advisor metadata/timeout/reporting/executable controls"}
    worker = None
    try:
        from test_git_snapshot_advisor_fixes import AdvisorRegressionTests
        AdvisorRegressionTests.run_root = fixtures
        executable = Path(os.environ["LIFECYCLE_SCHEMA_PWSH"]).resolve(strict=True)
        image_sha256 = hashlib.sha256(executable.read_bytes()).hexdigest()
        command = pinned_command([str(executable), "-NoLogo", "-NoProfile", "-NonInteractive", "-File",
                                  str(ROOT / "schema-worker.ps1"), "-SchemaPath",
                                  str(ROOT.parent / "event-schema.schema.json")], executable, image_sha256)
        BoundSchemaTests.executable, BoundSchemaTests.executable_sha256 = executable, image_sha256
        worker = SchemaSession(command, output)
        test_v2.VALIDATOR = worker
        report["schema_engine"] = worker.start()
        report["schema_image_sha256"] = image_sha256
        report["schema_executable"] = str(executable)
        suite = unittest.TestSuite()
        for kind in (test_git_snapshot_adapter.GitSnapshotTests, CaptureKernelTests, AdvisorRegressionTests):
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(kind))
        for method in ("test_00_explicit_metaschema_rejects_invalid_schema", "test_01_full_schema_24_event_payloads",
                       "test_16_hard_stops_and_no_live_authority"):
            suite.addTest(BoundSchemaTests(method))
        report["planned"] = suite.countTestCases()
        result = unittest.TextTestRunner(verbosity=2, failfast=True, resultclass=RecordedResult).run(suite)
        report.update(run=result.testsRun, passed=sum(item["result"] == "PASS" for item in result.outcomes),
                      failed=len(result.failures), errors=len(result.errors), not_run=report["planned"] - result.testsRun,
                      cases=result.outcomes, success=result.wasSuccessful(),
                      diagnostics=[text for _, text in result.failures + result.errors])
    except BaseException as error:
        report.update(success=False, initialization_or_harness_error=type(error).__name__, error=str(error))
        raise
    finally:
        persist_report(output, report, worker)
    print(json.dumps({key: report.get(key) for key in ("planned", "run", "passed", "failed", "errors", "not_run", "success")}))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
