"""Run the affected existing61 and focused Advisor regressions with fail-fast evidence."""

import json
import unittest

import test_v2
from common import ROOT, SchemaValidator, identity
from test_legacy_contracts import LegacyContractTests
from test_parallel_reviews import ParallelReviewTests
from test_requalification import RequalificationTests
from test_capture_kernel import CaptureKernelTests
from test_advisor_fixes import AdvisorFixTests
from test_stop_ownership import StopOwnershipTests
from test_stop_writes import StopWriteTests
from test_t1_identity import T1IdentityTests


class RecordedResult(unittest.TextTestResult):
    """Record each actual test outcome without turning unexecuted tests into successes."""

    def __init__(self, *arguments, **keywords):
        """Initialize unittest reporting and a separate durable-result list."""
        super().__init__(*arguments, **keywords)
        self.outcomes = []

    def addSuccess(self, test):
        """Record only tests that completed their assertions successfully."""
        super().addSuccess(test)
        self.outcomes.append({"id": test.id(), "result": "PASS"})

    def addFailure(self, test, error):
        """Preserve assertion failures and allow the fail-fast runner to stop."""
        super().addFailure(test, error)
        self.outcomes.append({"id": test.id(), "result": "FAIL"})

    def addError(self, test, error):
        """Distinguish harness/runtime errors from assertion counterexamples."""
        super().addError(test, error)
        self.outcomes.append({"id": test.id(), "result": "ERROR"})


def main():
    """Execute all selected tests once and leave the adoption gate BLOCKED."""
    output = ROOT / "results" / "epoch11"
    test_v2.RUN_ROOT = output / ("regression-fixtures-" + identity())
    test_v2.RUN_ROOT.mkdir()
    validator = SchemaValidator(output)
    test_v2.VALIDATOR = validator
    report = {"adoption_gate": "BLOCKED", "schema_engine": validator.metadata}
    try:
        suite = unittest.TestSuite()
        for kind in (T1IdentityTests, StopWriteTests, StopOwnershipTests, AdvisorFixTests, RequalificationTests, ParallelReviewTests, test_v2.V2Tests, LegacyContractTests, CaptureKernelTests):
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(kind))
        total = suite.countTestCases()
        result = unittest.TextTestRunner(verbosity=2, failfast=True, resultclass=RecordedResult).run(suite)
        report.update(planned=total, run=result.testsRun, passed=sum(item["result"] == "PASS" for item in result.outcomes),
                      failed=len(result.failures), errors=len(result.errors), not_run=total-result.testsRun,
                      success=result.wasSuccessful(), cases=result.outcomes,
                      diagnostics=[text for _, text in result.failures + result.errors])
    finally:
        validator.close()
        (output / "regression-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({key: report.get(key) for key in ("planned", "run", "passed", "failed", "errors", "not_run", "success")}))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
