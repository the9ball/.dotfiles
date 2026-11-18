"""Run bounded mock owner checks and the unchanged published Git/capture/schema suite."""

import hashlib
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

import test_mock_owner_grants
from common import ROOT, identity
from schema_worker_session import SchemaSession, persist_report, pinned_command
from verify_epoch11 import RecordedResult


def main():
    """Require a unique evidence directory, persist failures and reap owned processes."""
    allowed = (ROOT.parents[2] / ".local/lifecycle-v2-owner-grants/interval1").resolve()
    output = Path(sys.argv[1]).resolve()
    if not output.is_relative_to(allowed) or output == allowed or output.exists():
        raise ValueError("Explicit new unique owner evidence directory required")
    output.mkdir(parents=True)
    fixtures = output / "fixtures"
    fixtures.mkdir()
    test_mock_owner_grants.RUN_ROOT = fixtures
    report = {"adoption_gate": "BLOCKED", "production_enabled": False, "success": False,
              "scope": "Cooperative mock-owner admission plus unchanged published43 Git/capture/schema checks"}
    worker = None
    try:
        executable = Path(os.environ["LIFECYCLE_SCHEMA_PWSH"]).resolve(strict=True)
        image_sha256 = hashlib.sha256(executable.read_bytes()).hexdigest()
        command = pinned_command([str(executable), "-NoLogo", "-NoProfile", "-NonInteractive", "-File",
                                  str(ROOT / "schema-worker.ps1"), "-SchemaPath",
                                  str(ROOT.parent / "event-schema.schema.json")], executable, image_sha256)
        report["schema_image_sha256"] = image_sha256
        worker = SchemaSession(command, output)
        report["schema_engine"] = worker.start()
        test_mock_owner_grants.VALIDATOR = worker
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(test_mock_owner_grants.MockOwnerGrantTests)
        report["planned"] = suite.countTestCases()
        result = unittest.TextTestRunner(verbosity=2, failfast=True, resultclass=RecordedResult).run(suite)
        report.update(run=result.testsRun, passed=sum(item["result"] == "PASS" for item in result.outcomes),
                      failed=len(result.failures), errors=len(result.errors), not_run=report["planned"] - result.testsRun,
                      cases=result.outcomes, success=result.wasSuccessful(),
                      diagnostics=[message for _, message in result.failures + result.errors])
        if report["success"]:
            cleanup = worker.close()
            worker = None
            report["owner_schema_cleanup"] = cleanup
            if cleanup["errors"] or cleanup["transport_failed"] or cleanup["exit_code"] != 0:
                raise RuntimeError("Owner schema worker shutdown failed")
            regression = ROOT.parents[2] / ".local/lifecycle-v2-integration-results/git-snapshot/interval1" / identity()
            regression.mkdir(parents=True)
            report["published_regression_directory"] = str(regression)
            with (output / "published.stdout.txt").open("xb") as stdout, (output / "published.stderr.txt").open("xb") as stderr:
                completed = subprocess.run([sys.executable, "-B", str(ROOT / "verify_git_snapshot_interval1.py"), str(regression)],
                                           cwd=ROOT, stdout=stdout, stderr=stderr, timeout=240)
            published = json.loads((regression / "regression-report.json").read_text(encoding="utf-8"))
            report["published_regressions"] = {key: published.get(key) for key in ("planned", "run", "passed", "failed", "errors", "not_run", "success")}
            report["success"] = completed.returncode == 0 and published.get("success") is True and published.get("run") == 43
    except BaseException as error:
        report.update(success=False, initialization_or_harness_error=type(error).__name__, error=str(error))
        raise
    finally:
        persist_report(output, report, worker)
    print(json.dumps({key: report.get(key) for key in ("planned", "run", "passed", "failed", "errors", "not_run", "success")}))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
