"""Focused expiry and stop-write regressions for the epoch9 reason-laundering finding."""

import copy
import unittest

import test_v2
from common import Denied, canonical, identity


class StopWriteTests(unittest.TestCase):
    """Preserve stop reason/ownership across expiry, event ordering and valid recovery."""

    def fixture(self):
        """Allocate one isolated fixture and retain its evidence after releasing the writer."""
        fixture = test_v2.Fixture()
        self.addCleanup(fixture.close)
        return fixture

    def pending_safety(self, fixture):
        """Persist a SAFETY receipt while leaving the review job running."""
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.launch(job)
        finding = test_v2.finding()
        finding["severity"] = "SAFETY"
        receipt = fixture.coordinator.collect(job, canonical(
            fixture.coordinator.result(job, "NEEDS_CHANGES", [finding])).encode())
        return job, receipt

    def drafts(self, fixture, receipt):
        """Obtain normal complete T2 drafts at the fixture's current clock without committing."""
        batches = []
        original = fixture.store.append
        fixture.store.append = lambda drafts, **keywords: batches.append(copy.deepcopy(drafts))
        try:
            fixture.coordinator.apply_receipt(receipt)
        finally:
            fixture.store.append = original
        return batches[0]

    def test_forged_expiry_is_ineffective_and_real_expiry_cannot_release_safety(self):
        """Exact approval identity/deadline is required, and resolving expiry never resolves SAFETY."""
        fixture = self.fixture()
        job, receipt = self.pending_safety(fixture)
        fixture.coordinator.apply_receipt(receipt)
        safety = next(key for key, reason in fixture.store.state["stops"].items() if reason == "UNCLASSIFIABLE")
        approval = copy.deepcopy(fixture.store.state["approval"])
        for interval, deadline in [(safety, 0), (approval["interval_id"], 0),
                                   (safety, approval["deadline_uptime_ms"]),
                                   (approval["interval_id"], approval["deadline_uptime_ms"])]:
            before = copy.deepcopy(fixture.store.state)
            with self.assertRaises(Denied):
                fixture.coordinator.emit("ClockExpired", {"interval_id": interval, "deadline_uptime_ms": deadline})
            self.assertEqual(fixture.store.state, before)
            self.assertEqual(fixture.store.replay(), before)
        fixture.now = approval["deadline_uptime_ms"]
        payload = {"interval_id": approval["interval_id"], "deadline_uptime_ms": fixture.now}
        event = fixture.store.event("ClockExpired", payload, fixture.clock())
        command = identity()
        fixture.store.append([event], command_id=command)
        before = copy.deepcopy(fixture.store.state)
        fixture.store.append([event], command_id=command)
        self.assertEqual(before, fixture.store.state)
        fixture.coordinator.emit("ClockExpired", payload)
        fixture.restart()
        fixture.coordinator.exit(job)
        fixture.coordinator.approve(fixture.now + 1000)
        fixture.coordinator.emit("StopResolved", {"stop_id": approval["interval_id"],
            "owner_proof": fixture.coordinator.proof, "resolution_proof": fixture.coordinator.proof}, "OWNER")
        self.assertEqual(fixture.store.state["stops"][safety], "UNCLASSIFIABLE")
        self.assertFalse(fixture.coordinator.rights()["repair"])
        with self.assertRaises(Denied):
            fixture.coordinator.emit("ClockExpired", payload)
        self.assertEqual(fixture.store.replay(), fixture.store.state)

    def test_same_id_order_permutations_keep_safety_or_unresolved_receipt(self):
        """Neither ordering launders an irreducible reason or discards unapplied adverse evidence."""
        for safety_first in (False, True):
            with self.subTest(safety_first=safety_first):
                fixture = self.fixture()
                job, receipt = self.pending_safety(fixture)
                approval = copy.deepcopy(fixture.store.state["approval"])
                stop_id = approval["interval_id"]
                if safety_first:
                    complete = self.drafts(fixture, receipt)
                    next(event for event in complete if event["event_type"] == "StopLatched")["payload"]["stop_id"] = stop_id
                    fixture.store.append(complete)
                fixture.now = approval["deadline_uptime_ms"]
                expiry = {"interval_id": stop_id, "deadline_uptime_ms": fixture.now}
                if safety_first:
                    with self.assertRaises(Denied):
                        fixture.coordinator.emit("ClockExpired", expiry)
                    self.assertEqual(fixture.store.state["stops"][stop_id], "UNCLASSIFIABLE")
                else:
                    fixture.coordinator.emit("ClockExpired", expiry)
                    complete = self.drafts(fixture, receipt)
                    next(event for event in complete if event["event_type"] == "StopLatched")["payload"]["stop_id"] = stop_id
                    with self.assertRaises(Denied):
                        fixture.store.append(complete)
                    self.assertFalse(fixture.store.state["receipts"][receipt]["applied"])
                    fixture.coordinator.approve(fixture.now + 1000)
                    fixture.coordinator.emit("StopResolved", {"stop_id": stop_id, "owner_proof": fixture.coordinator.proof,
                        "resolution_proof": fixture.coordinator.proof}, "OWNER")
                    self.assertFalse(fixture.coordinator.rights()["can_pass"])
                    fixture.coordinator.apply_receipt(receipt)
                    self.assertIn("UNCLASSIFIABLE", fixture.store.state["stops"].values())
                fixture.restart()
                fixture.coordinator.exit(job)
                self.assertIn("UNCLASSIFIABLE", fixture.store.state["stops"].values())
                self.assertEqual(fixture.store.replay(), fixture.store.state)

    def test_other_stop_writes_reject_reason_replacement_and_valid_expiry_recovers(self):
        """Receipt rejection cannot alter a security reason; legitimate deadline resolution still converges."""
        fixture = self.fixture()
        job, receipt = self.pending_safety(fixture)
        stop_id = identity()
        fixture.coordinator.emit("StopLatched", {"stop_id": stop_id, "reason": "AUTHORIZATION", "evidence": fixture.coordinator.proof})
        before = copy.deepcopy(fixture.store.state)
        with self.assertRaises(Denied):
            fixture.coordinator.emit("ReceiptRejected", {"receipt_id": receipt, "reason": "UNCLASSIFIABLE",
                "unclassified_debt_id": stop_id, "evidence": fixture.coordinator.proof})
        self.assertEqual(fixture.store.state, before)
        self.assertFalse(fixture.store.state["receipts"][receipt]["applied"])
        self.assertEqual(fixture.store.replay(), before)
        normal = self.fixture()
        normal.verify()
        normal.pass_review()
        approval = copy.deepcopy(normal.store.state["approval"])
        normal.now = approval["deadline_uptime_ms"]
        normal.coordinator.emit("ClockExpired", {"interval_id": approval["interval_id"], "deadline_uptime_ms": normal.now})
        normal.restart()
        normal.coordinator.approve(normal.now + 1000)
        normal.coordinator.emit("StopResolved", {"stop_id": approval["interval_id"], "owner_proof": normal.coordinator.proof,
            "resolution_proof": normal.coordinator.proof}, "OWNER")
        self.assertFalse(normal.coordinator.rights()["pass"])
        normal.verify()
        normal.pass_review()
        self.assertTrue(normal.coordinator.rights()["pass"])
        self.assertEqual(normal.store.replay(), normal.store.state)
