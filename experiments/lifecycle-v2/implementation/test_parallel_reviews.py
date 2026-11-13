"""Parallel-review receipt regression tests using private simulated fixtures."""

import unittest

from common import Denied, StorageFailure, canonical, parse_json
from test_v2 import Fixture, finding


class ParallelReviewTests(unittest.TestCase):
    """Separate original-job finalization from eligibility to approve the current target."""

    def setUp(self):
        """Allocate a two-role immutable review round in a new private database."""
        self.fixture = Fixture(roles=["advisor", "peer"])
        self.addCleanup(self.fixture.close)
        self.fixture.verify()
        self.first, self.second = self.fixture.coordinator.review_round()

    def delayed(self):
        """Keep the original peer's CLEAR after the first role reports a finding."""
        coordinator = self.fixture.coordinator
        coordinator.complete_job(self.first, "NEEDS_CHANGES", [finding()])
        coordinator.launch(self.second)
        coordinator.exit(self.second)
        raw = canonical(coordinator.result(self.second)).encode()
        receipt = coordinator.collect(self.second, raw)
        return receipt, raw

    def assert_repairable_without_pass(self, receipt):
        """Require preserved rejection and terminal stale peer without current approval."""
        state = self.fixture.store.state
        self.assertTrue(state["receipts"][receipt]["applied"])
        self.assertFalse(state["receipts"][receipt]["approval_eligible"])
        self.assertTrue(state["jobs"][self.second]["applied"])
        self.assertTrue(any(issue["state"] == "OPEN" for issue in state["issues"].values()))
        self.assertEqual(state["clears"], {})
        self.assertTrue(self.fixture.coordinator.rights()["repair"])
        self.assertFalse(self.fixture.coordinator.rights()["can_pass"])

    def test_rejection_then_delayed_clear_and_fresh_convergence(self):
        """A stale peer terminates safely and only a fresh repaired round enables PASS."""
        receipt, _ = self.delayed()
        self.assertFalse(self.fixture.coordinator.rights()["repair"])
        self.fixture.coordinator.apply_receipt(receipt)
        self.assert_repairable_without_pass(receipt)
        self.fixture.repair()
        self.fixture.verify()
        self.fixture.pass_review()
        self.assertTrue(self.fixture.coordinator.rights()["pass"])
        self.assertEqual(self.fixture.store.state["review_spent"], 2)
        latest = self.fixture.store.connection.execute("SELECT body FROM events ORDER BY sequence DESC LIMIT 1").fetchone()[0]
        self.assertNotIn(receipt, parse_json(latest)["payload"]["clear_receipt_ids"])

    def test_clear_before_rejection_cannot_survive_as_approval(self):
        """Reverse result order cannot let an earlier CLEAR erase a later finding."""
        self.fixture.coordinator.complete_job(self.first)
        self.fixture.coordinator.complete_job(self.second, "NEEDS_CHANGES", [finding()])
        self.assertEqual(self.fixture.store.state["clears"], {})
        self.assertTrue(self.fixture.coordinator.rights()["repair"])
        self.assertFalse(self.fixture.coordinator.rights()["can_pass"])

    def test_uncollected_and_unterminated_jobs_remain_frozen(self):
        """The fix cannot finalize a peer before its own physical completion evidence."""
        coordinator = self.fixture.coordinator
        coordinator.complete_job(self.first, "NEEDS_CHANGES", [finding()])
        coordinator.launch(self.second)
        receipt = coordinator.collect(self.second, canonical(coordinator.result(self.second)).encode())
        with self.assertRaises(Denied):
            coordinator.apply_receipt(receipt)
        self.assertFalse(coordinator.rights()["repair"])
        self.fixture.restart()
        self.assertIn("UNKNOWN_JOB", self.fixture.store.state["stops"].values())
        self.fixture.coordinator.exit(self.second)
        self.fixture.coordinator.apply_receipt(receipt)
        self.assert_repairable_without_pass(receipt)

    def test_duplicate_and_conflicting_late_receipts(self):
        """Same bytes are idempotent, while conflicting bytes remain blocking evidence."""
        receipt, raw = self.delayed()
        coordinator = self.fixture.coordinator
        coordinator.apply_receipt(receipt)
        before = canonical(self.fixture.store.state)
        self.assertEqual(coordinator.collect(self.second, raw), receipt)
        coordinator.apply_receipt(receipt)
        self.assertEqual(canonical(self.fixture.store.state), before)
        other = coordinator.collect(self.second, canonical(coordinator.result(self.second, "NEEDS_CHANGES", [finding("other", "other")])).encode())
        self.assertNotEqual(other, receipt)
        self.assertIn("EVIDENCE_CONFLICT", self.fixture.store.state["stops"].values())
        self.fixture.restart()
        self.assertTrue(self.fixture.store.state["receipts"][receipt]["applied"])
        self.assertFalse(self.fixture.coordinator.rights()["repair"])
        self.assertFalse(self.fixture.coordinator.rights()["can_pass"])
        with self.assertRaises(Denied):
            self.fixture.coordinator.apply_receipt(other)

    def test_stale_finalization_is_atomic_across_failures(self):
        """T2 rollback and lost ACK preserve rejection and finalize stale peers once."""
        for mode in ("after_events", "after_commit"):
            with self.subTest(mode=mode):
                fixture = Fixture(roles=["advisor", "peer"])
                self.addCleanup(fixture.close)
                fixture.verify()
                first, second = fixture.coordinator.review_round()
                fixture.coordinator.complete_job(first, "NEEDS_CHANGES", [finding()])
                fixture.coordinator.launch(second)
                fixture.coordinator.exit(second)
                receipt = fixture.coordinator.collect(second, canonical(fixture.coordinator.result(second)).encode())
                with self.assertRaises(StorageFailure):
                    fixture.coordinator.apply_receipt(receipt, fault=mode)
                fixture.restart()
                self.assertEqual(fixture.store.state["receipts"][receipt]["applied"], mode == "after_commit")
                fixture.coordinator.apply_receipt(receipt)
                fixture.coordinator.apply_receipt(receipt)
                self.assertFalse(fixture.store.state["receipts"][receipt]["approval_eligible"])
                self.assertEqual(len(fixture.store.state["issues"]), 1)
                self.assertTrue(fixture.coordinator.rights()["repair"])
                self.assertFalse(fixture.coordinator.rights()["can_pass"])
                self.assertEqual(fixture.store.state, fixture.store.replay())
