"""Focused stop-ownership regressions for the epoch8 safety/job collision finding."""

import copy
import sqlite3
import unittest

import test_v2
from common import Denied, StorageFailure, canonical, identity
from coordinator import Coordinator
from store import EventStore


class StopOwnershipTests(unittest.TestCase):
    """Preserve security stops across job lifecycle without changing owner resolution policy."""

    def fixture(self):
        """Allocate a private gate and release only its current fixture writer."""
        fixture = test_v2.Fixture()
        self.addCleanup(fixture.close)
        return fixture

    def pending_safety(self, fixture):
        """Collect a valid SAFETY response while the identified review job is still running."""
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.launch(job)
        finding = test_v2.finding()
        finding["severity"] = "SAFETY"
        receipt = fixture.coordinator.collect(job, canonical(
            fixture.coordinator.result(job, "NEEDS_CHANGES", [finding])).encode())
        batches = []
        original = fixture.store.append
        fixture.store.append = lambda drafts, **keywords: batches.append(copy.deepcopy(drafts))
        try:
            fixture.coordinator.apply_receipt(receipt)
        finally:
            fixture.store.append = original
        return job, receipt, batches[0]

    def test_collision_rejected_and_safety_survives_exit_replay_and_duplicates(self):
        """Both Advisor paths reject colliding T2 and retain valid safety stops through job exit."""
        for restart in (False, True):
            with self.subTest(restart=restart):
                fixture = self.fixture()
                job, receipt, complete = self.pending_safety(fixture)
                colliding = copy.deepcopy(complete)
                next(event for event in colliding if event["event_type"] == "StopLatched")["payload"]["stop_id"] = job
                with self.assertRaises(Denied):
                    fixture.store.append(colliding)
                self.assertFalse(fixture.store.state["receipts"][receipt]["applied"])
                fixture.store.append(complete)
                safety = next(event["payload"] for event in complete if event["event_type"] == "StopLatched")
                stop_id = safety["stop_id"]
                fixture.coordinator.emit("StopLatched", safety)
                with self.assertRaises(Denied):
                    fixture.coordinator.emit("StopLatched", {**safety, "reason": "UNKNOWN_JOB"})
                if restart:
                    fixture.restart()
                    fixture.coordinator.recover()
                event = fixture.store.event("JobExitObserved", {"job_id": job, "exit_code": 0,
                                            "identity_and_group_exit_proof": fixture.coordinator.proof}, fixture.clock())
                command = identity()
                fixture.store.append([event], command_id=command)
                state = copy.deepcopy(fixture.store.state)
                fixture.store.append([event], command_id=command)
                self.assertEqual(fixture.store.state, state)
                self.assertEqual(fixture.store.state["stops"][stop_id], "UNCLASSIFIABLE")
                self.assertEqual(fixture.store.state["stop_owners"][stop_id], {"kind": "safety"})
                self.assertNotIn(job, fixture.store.state["stops"])
                self.assertFalse(fixture.coordinator.rights()["repair"])
                with self.assertRaises(Denied):
                    fixture.coordinator.emit("StopResolved", {"stop_id": stop_id, "owner_proof": fixture.coordinator.proof,
                        "resolution_proof": fixture.coordinator.proof}, "OWNER")
                self.assertEqual(fixture.store.replay(), fixture.store.state)
                fixture.restart()
                fixture.store.append([event], command_id=command)
                self.assertEqual(fixture.store.state["stops"][stop_id], "UNCLASSIFIABLE")

    def test_unclean_marker_and_repeated_startup_cannot_reassign_safety_owner(self):
        """Storage uncertainty and multiple unreconciled opens retain safety ownership and evidence."""
        fixture = self.fixture()
        job, receipt, complete = self.pending_safety(fixture)
        fixture.store.append(complete)
        stop_id = next(event["payload"]["stop_id"] for event in complete if event["event_type"] == "StopLatched")
        fixture.store.connection.set_authorizer(
            # Deny only the fixture blob insertion to leave a real unclean-storage marker.
            lambda action, *arguments: sqlite3.SQLITE_DENY
            if action == sqlite3.SQLITE_INSERT and arguments[0] == "blobs" else sqlite3.SQLITE_OK)
        with self.assertRaises(StorageFailure):
            fixture.store.put_blob(b"uncertain-artifact")
        for iteration in range(2):
            fixture.store.close()
            fixture.store = EventStore(fixture.directory, fixture.contract, test_v2.VALIDATOR, fixture.principals)
            fixture.coordinator = Coordinator(fixture.store, fixture.clock)
            self.assertTrue(fixture.store.prior_unclean)
            self.assertFalse(fixture.coordinator.rights()["dispatch"])
            self.assertEqual(fixture.store.state["stops"][stop_id], "UNCLASSIFIABLE")
        fixture.coordinator.recover()
        fixture.coordinator.recover()
        self.assertEqual(fixture.store.state["stops"][job], "UNKNOWN_JOB")
        self.assertEqual(fixture.store.state["stops"][stop_id], "UNCLASSIFIABLE")
        fixture.coordinator.exit(job)
        self.assertNotIn(job, fixture.store.state["stops"])
        self.assertEqual(fixture.store.state["stops"][stop_id], "UNCLASSIFIABLE")
        self.assertEqual(fixture.store.replay(), fixture.store.state)

    def test_authorized_resolution_restores_work_but_never_frees_stop_id_for_a_job(self):
        """Existing owner-resolvable reasons resume only after owner proof and fresh checks/review."""
        fixture = self.fixture()
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.launch(job)
        stop_id = identity()
        payload = {"stop_id": stop_id, "reason": "AUTHORIZATION", "evidence": fixture.coordinator.proof}
        fixture.coordinator.emit("StopLatched", payload)
        fixture.coordinator.emit("StopLatched", payload)
        fixture.restart()
        fixture.coordinator.exit(job)
        receipt = fixture.coordinator.collect(job, canonical(fixture.coordinator.result(job)).encode())
        fixture.coordinator.apply_receipt(receipt)
        self.assertEqual(fixture.store.state["stops"][stop_id], "AUTHORIZATION")
        resolution = {"stop_id": stop_id, "owner_proof": fixture.coordinator.proof,
                      "resolution_proof": fixture.coordinator.proof}
        with self.assertRaises(Denied):
            fixture.coordinator.emit("StopResolved", resolution)
        fixture.coordinator.emit("StopResolved", resolution, "OWNER")
        self.assertFalse(fixture.coordinator.rights()["pass"])
        self.assertTrue(fixture.coordinator.rights()["verify"])
        with self.assertRaises(Denied):
            fixture.coordinator.emit("VerificationIntentRecorded", {"attempt_id": fixture.store.state["attempt"],
                "request_id": identity(), "job_id": stop_id, "oracle_manifest": fixture.coordinator.proof,
                "invocation_manifest": fixture.coordinator.proof})
        fixture.verify()
        fixture.pass_review()
        self.assertTrue(fixture.coordinator.rights()["pass"])
        self.assertEqual(fixture.store.state["stop_owners"][stop_id], {"kind": "safety"})
        self.assertEqual(fixture.store.replay(), fixture.store.state)
