"""Regression for legal UUID equality, durable conflicting receipts and PASS invalidation."""

import copy
import unittest

import test_v2
from common import Denied, StorageFailure, canonical, identity


class T1IdentityTests(unittest.TestCase):
    """Keep identity domains separate without banning accepted request/job equality."""

    def passed_fixture(self, request_is_job=True):
        """Reach PASS with either equal request/job UUIDs or a previously resolved safety identity."""
        fixture = test_v2.Fixture()
        self.addCleanup(fixture.close)
        request = identity()
        job = request if request_is_job else identity()
        if not request_is_job:
            fixture.coordinator.emit("StopLatched", {"stop_id": request, "reason": "AUTHORIZATION", "evidence": fixture.coordinator.proof})
            fixture.coordinator.emit("StopResolved", {"stop_id": request, "owner_proof": fixture.coordinator.proof,
                "resolution_proof": fixture.coordinator.proof}, "OWNER")
        fixture.coordinator.emit("VerificationIntentRecorded", {"attempt_id": fixture.store.state["attempt"],
            "request_id": request, "job_id": job, "oracle_manifest": fixture.coordinator.proof,
            "invocation_manifest": fixture.coordinator.proof})
        fixture.coordinator.complete_job(job)
        fixture.pass_review()
        self.assertTrue(fixture.coordinator.rights()["pass"])
        return fixture, request, job

    def assert_conflict(self, fixture, request, job, receipt, raw):
        """Require exact raw evidence, durable debt, an isolated stop and no effective PASS."""
        saved = fixture.store.state["receipts"][receipt]
        self.assertEqual(fixture.store.get_blob(saved["final_artifact"]), raw)
        self.assertEqual(saved["request_id"], request)
        self.assertFalse(saved["applied"])
        self.assertIsNone(fixture.store.state["pass_assessed"])
        self.assertFalse(fixture.coordinator.rights()["pass"])
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        conflicts = [key for key, value in fixture.store.state["stops"].items() if value == "EVIDENCE_CONFLICT"]
        self.assertEqual(len(conflicts), 1)
        self.assertNotIn(conflicts[0], fixture.store.state["jobs"])
        self.assertNotEqual(conflicts[0], request)
        self.assertEqual(fixture.store.state["stop_owners"][conflicts[0]], {"kind": "safety"})
        self.assertEqual(fixture.store.state["jobs"][job]["status"], "EXITED")
        self.assertEqual(fixture.store.replay(), fixture.store.state)

    def test_legal_equal_and_previously_owned_ids_preserve_raw_and_revoke_pass(self):
        """Previously accepted identity relationships survive conflict collection and restart."""
        for same_id in (True, False):
            with self.subTest(request_equals_job=same_id):
                fixture, request, job = self.passed_fixture(same_id)
                raw = canonical(fixture.coordinator.result(job, "NEEDS_CHANGES")).encode()
                count = len(fixture.store.state["receipts"])
                receipt = fixture.coordinator.collect(job, raw)
                self.assertEqual(len(fixture.store.state["receipts"]), count + 1)
                self.assertTrue(fixture.store.healthy)
                self.assert_conflict(fixture, request, job, receipt, raw)
                before = copy.deepcopy(fixture.store.state)
                self.assertEqual(fixture.coordinator.collect(job, raw), receipt)
                self.assertEqual(fixture.store.state, before)
                fixture.restart()
                self.assert_conflict(fixture, request, job, receipt, raw)
                self.assertEqual(fixture.coordinator.collect(job, raw), receipt)
                fixture.coordinator.approve(3000000)
                self.assertFalse(fixture.coordinator.rights()["pass"])
                with self.assertRaises(Denied):
                    fixture.coordinator.apply_receipt(receipt)
                self.assert_conflict(fixture, request, job, receipt, raw)

    def test_conflicting_t1_commit_lost_ack_is_durable_and_idempotent(self):
        """A committed conflicting T1 survives a lost ACK without restoring PASS or duplicating debt."""
        fixture, request, job = self.passed_fixture()
        raw = canonical(fixture.coordinator.result(job, "NEEDS_CHANGES")).encode()
        count = len(fixture.store.state["receipts"])
        with self.assertRaises(StorageFailure):
            fixture.coordinator.collect(job, raw, fault="after_commit")
        self.assertFalse(fixture.coordinator.rights()["pass"])
        fixture.restart()
        receipt = fixture.coordinator.collect(job, raw)
        self.assertEqual(len(fixture.store.state["receipts"]), count + 1)
        self.assert_conflict(fixture, request, job, receipt, raw)
        before = copy.deepcopy(fixture.store.state)
        self.assertEqual(fixture.coordinator.collect(job, raw), receipt)
        self.assertEqual(fixture.store.state, before)
