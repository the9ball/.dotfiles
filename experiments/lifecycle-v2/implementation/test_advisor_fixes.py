"""Focused counterexamples for the four mandatory independent Advisor findings."""

import copy
import json
import sqlite3
import subprocess
import sys
import unittest

import test_v2
from common import Denied, StorageFailure, ROOT, canonical
from coordinator import Coordinator
from store import EventStore


class AdvisorFixTests(unittest.TestCase):
    """Reject missing guarantees while preserving the existing repair and receipt lifecycle."""

    def setUp(self):
        """Allocate one new private fixture and release only its own writer."""
        self.fixture = test_v2.Fixture()
        self.addCleanup(self.fixture.close)

    def reopen_without_recovery(self):
        """Open a new locked writer without transferring event ownership yet."""
        fixture = self.fixture
        fixture.store.close()
        fixture.store = EventStore(fixture.directory, fixture.contract, test_v2.VALIDATOR, fixture.principals)
        fixture.coordinator = Coordinator(fixture.store, fixture.clock)

    def test_R1_repeated_starts_stale_writer_and_double_writer(self):
        """Skipped runtime generations are recoverable only by the current exclusive writer."""
        fixture = self.fixture
        old = fixture.store
        for iteration in range(3):
            self.reopen_without_recovery()
            self.assertFalse(fixture.coordinator.rights()["verify"])
        with self.assertRaises(Denied):
            EventStore(fixture.directory, fixture.contract, test_v2.VALIDATOR, fixture.principals)
        with self.assertRaises(Denied):
            old.append([old.event("StopLatched", {"stop_id": test_v2.identity(), "reason": "UNKNOWN_JOB",
                                                 "evidence": fixture.coordinator.proof}, fixture.clock())])
        fixture.coordinator.recover()
        self.assertEqual(fixture.store.state["writer_generation"], fixture.store.fence)
        self.assertTrue(fixture.coordinator.rights()["verify"])
        fixture.verify()
        fixture.pass_review()
        self.assertTrue(fixture.coordinator.rights()["pass"])

    def test_R1_process_crashes_after_fence_before_transfer(self):
        """Two actual child crashes at the fence commit cannot strand the durable projection."""
        fixture = self.fixture
        context = fixture.directory / "crash-context.json"
        context.write_text(json.dumps({"contract": fixture.contract, "principals": fixture.principals,
                                       "clock": fixture.clock()}), encoding="utf-8")
        fixture.store.close()
        fixture.store = None
        for iteration in range(2):
            result = subprocess.run([sys.executable, str(ROOT / "crash_probe.py"), str(context), "fence"],
                                    capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 93, result.stderr.decode("utf-8", errors="replace"))
        fixture.store = EventStore(fixture.directory, fixture.contract, test_v2.VALIDATOR, fixture.principals)
        fixture.coordinator = Coordinator(fixture.store, fixture.clock)
        self.assertTrue(fixture.store.prior_unclean)
        self.assertFalse(fixture.coordinator.rights()["dispatch"])
        fixture.coordinator.recover()
        self.assertTrue(fixture.coordinator.rights()["verify"])

    def test_R2_unclean_storage_failure_requires_explicit_reconciliation(self):
        """Old PASS remains unusable until the newly opened store verifies durable effects."""
        fixture = self.fixture
        fixture.verify()
        fixture.pass_review()
        fixture.store.connection.set_authorizer(
            # Reject only this fixture's blob write to exercise the real SQLite failure path.
            lambda action, *arguments: sqlite3.SQLITE_DENY
            if action == sqlite3.SQLITE_INSERT and arguments[0] == "blobs" else sqlite3.SQLITE_OK)
        with self.assertRaises(StorageFailure):
            fixture.store.put_blob(b"not-saved")
        self.reopen_without_recovery()
        self.assertTrue(fixture.store.prior_unclean)
        self.assertTrue(fixture.store.recovery_pending)
        self.assertFalse(fixture.coordinator.rights()["pass"])
        self.assertFalse(fixture.coordinator.rights()["dispatch"])
        with self.assertRaises(Denied):
            fixture.coordinator.approve(3000000)
        fixture.coordinator.recover()
        self.assertFalse(fixture.store.recovery_pending)
        self.assertTrue(fixture.coordinator.rights()["pass"])

    def test_R2_uncertain_job_is_latched_without_relaunch(self):
        """Reconciliation of a running job blocks work rather than repeating its unknown effects."""
        fixture = self.fixture
        job = fixture.coordinator.verification()
        fixture.coordinator.launch(job)
        self.reopen_without_recovery()
        fixture.coordinator.recover()
        self.assertEqual(fixture.store.state["stops"][job], "UNKNOWN_JOB")
        self.assertFalse(fixture.coordinator.rights()["dispatch"])
        with self.assertRaises(Denied):
            fixture.coordinator.launch(job)
        self.assertEqual(len(fixture.store.state["jobs"]), 1)

    def pending_failure(self, safety=False):
        """Prepare an unapplied valid receipt and return its normal complete T2 drafts."""
        fixture = self.fixture
        if safety:
            fixture.verify()
            job = fixture.coordinator.review_round()[0]
            finding = test_v2.finding()
            finding["severity"] = "SAFETY"
            findings = [finding]
        else:
            job = fixture.coordinator.verification()
            findings = None
        fixture.coordinator.launch(job)
        fixture.coordinator.exit(job)
        receipt = fixture.coordinator.collect(job, canonical(
            fixture.coordinator.result(job, "NEEDS_CHANGES", findings)).encode())
        batches = []
        original = fixture.store.append
        fixture.store.append = lambda drafts, **keywords: batches.append(copy.deepcopy(drafts))
        try:
            fixture.coordinator.apply_receipt(receipt)
        finally:
            fixture.store.append = original
        return receipt, batches[0]

    def test_R3_charge_and_raw_finding_substitution_are_rejected(self):
        """Classification, exact raw identity and each required repair charge form one T2 contract."""
        fixture = self.fixture
        fixture.verify(False)
        fixture.repair()
        receipt, complete = self.pending_failure()
        for mutation in ("missing-charge", "alias", "anchor", "proof"):
            with self.subTest(mutation=mutation):
                drafts = copy.deepcopy(complete)
                classified = next(event for event in drafts if event["event_type"] == "FindingClassified")
                if mutation == "missing-charge":
                    drafts = [event for event in drafts if event["event_type"] != "RepairFailureCharged"]
                    drafts[-1]["payload"]["effect_event_ids"] = [event["event_id"] for event in drafts
                        if event["event_type"] == "FindingClassified"]
                elif mutation == "alias":
                    classified["payload"]["alias"]["external_id"] = "substitute"
                elif mutation == "anchor":
                    classified["payload"]["anchor"]["assertion_id"] = "substitute"
                else:
                    classified["payload"]["classification_proof"] = test_v2.artifact(b"different")
                before = copy.deepcopy(fixture.store.state)
                with self.assertRaises(Denied):
                    fixture.store.append(drafts)
                self.assertEqual(fixture.store.state, before)
                self.assertFalse(fixture.store.state["receipts"][receipt]["applied"])
        fixture.store.append(complete)
        self.assertEqual(len(fixture.store.state["charges"]), 1)
        self.assertEqual(fixture.store.replay(), fixture.store.state)
        fixture.restart()
        self.assertEqual(len(fixture.store.state["charges"]), 1)

    def test_R3_required_safety_stop_cannot_be_omitted(self):
        """A SAFETY result cannot become an applied ordinary classification without its stop."""
        fixture = self.fixture
        receipt, complete = self.pending_failure(safety=True)
        incomplete = [event for event in complete if event["event_type"] != "StopLatched"]
        with self.assertRaises(Denied):
            fixture.store.append(incomplete)
        self.assertFalse(fixture.store.state["receipts"][receipt]["applied"])
        fixture.store.append(complete)
        self.assertIn("UNCLASSIFIABLE", fixture.store.state["stops"].values())
        self.assertFalse(fixture.coordinator.rights()["repair"])
        self.assertEqual(fixture.store.replay(), fixture.store.state)
