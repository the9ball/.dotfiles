"""Observable-contract translations of selected legacy cases; never execute old fixtures."""

import copy
import unittest

from common import Denied, canonical, identity, parse_json
from test_v2 import Fixture, finding
from verify_state_space import seed


class LegacyContractTests(unittest.TestCase):
    """Compare explicit legacy observables after adapting event representation only."""

    def fixture(self):
        """Own each new v2 fixture independently of all legacy files."""
        fixture = Fixture()
        self.addCleanup(fixture.close)
        return fixture

    def review_result(self, fixture, result):
        """Deliver specified synthetic final JSON through the actual T1/T2 path."""
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.launch(job)
        fixture.coordinator.exit(job)
        raw = canonical(result(fixture.coordinator, job)).encode()
        receipt = fixture.coordinator.collect(job, raw)
        fixture.coordinator.apply_receipt(receipt)
        return job, receipt, raw

    def expire_and_extend(self, fixture, deadline=3000000):
        """Map old resume.resolves to separate explicit v2 approval and stop resolution."""
        fixture.now = fixture.store.state["approval"]["deadline_uptime_ms"]
        stop_id = fixture.store.state["approval"]["interval_id"]
        fixture.coordinator.emit("ClockExpired", {"interval_id": stop_id, "deadline_uptime_ms": fixture.now})
        fixture.coordinator.approve(deadline)
        fixture.coordinator.emit("StopResolved", {"stop_id": stop_id, "owner_proof": fixture.coordinator.proof,
            "resolution_proof": fixture.coordinator.proof}, "OWNER")

    def test_A02_B09_failed_evidence_and_fresh_convergence(self):
        """A02/B09 retain failed evidence and require real repair plus current CLEAR."""
        fixture = self.fixture()
        fixture.verify(False)
        self.assertTrue(fixture.coordinator.rights()["repair"])
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        fixture.repair()
        fixture.verify()
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        self.assertTrue(any(item.get("result", {}).get("outcome") == "FAIL" for item in fixture.store.state["receipts"].values()))
        fixture.pass_review()
        self.assertTrue(fixture.coordinator.rights()["pass"])
        self.assertTrue(all(item["state"] == "CLOSED" for item in fixture.store.state["issues"].values()))

    def test_A10_A15_guard_categories(self):
        """A10/A15 map old risk labels to the corresponding v2 hard-stop meanings."""
        for reason in ("AUTHENTICATION", "AUTHORIZATION", "SECRETS", "SCOPE_ESCAPE",
                       "DESTRUCTIVE_OPERATION", "EVIDENCE_MISMATCH", "EVIDENCE_MISMATCH", "UNCLASSIFIABLE"):
            with self.subTest(reason=reason):
                fixture = self.fixture()
                fixture.coordinator.emit("StopLatched", {"stop_id": identity(), "reason": reason, "evidence": fixture.coordinator.proof})
                self.assertIn(reason, fixture.store.state["stops"].values())
                self.assertFalse(fixture.coordinator.rights()["repair"])
                self.assertFalse(fixture.coordinator.rights()["can_pass"])
                self.assertEqual(fixture.store.state["repair_spent"], 0)

    def test_A16_review_rejection_requires_fresh_round(self):
        """A16 ordinary rejection permits repair but never inherits the prior final review."""
        fixture = self.fixture()
        self.review_result(fixture, lambda coordinator, job: coordinator.result(job, "NEEDS_CHANGES", [finding()]))
        self.assertTrue(fixture.coordinator.rights()["repair"])
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        fixture.repair()
        self.assertEqual(fixture.store.state["clears"], {})
        fixture.verify()
        fixture.pass_review()
        self.assertEqual(fixture.store.state["review_spent"], 2)
        self.assertTrue(fixture.coordinator.rights()["pass"])

    def test_A20_F2_B01_C05_review_deadlines(self):
        """Original and extended time boundaries collect once and never grant late PASS."""
        for offset in (-1, 0, 1):
            with self.subTest(offset=offset):
                fixture = self.fixture()
                fixture.verify()
                job = fixture.coordinator.review_round()[0]
                fixture.coordinator.launch(job)
                fixture.coordinator.exit(job)
                raw = canonical(fixture.coordinator.result(job)).encode()
                fixture.now = 2700000 + offset
                receipt = fixture.coordinator.collect(job, raw)
                fixture.coordinator.apply_receipt(receipt)
                self.assertTrue(fixture.store.state["receipts"][receipt]["applied"])
                self.assertEqual(fixture.coordinator.collect(job, raw), receipt)
                self.assertEqual(fixture.store.state["review_spent"], 1)
                if offset < 0:
                    fixture.coordinator.assess()
                    self.assertTrue(fixture.coordinator.rights()["pass"])
                else:
                    self.assertFalse(fixture.coordinator.rights()["can_pass"])
        fixture = self.fixture()
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.launch(job)
        self.expire_and_extend(fixture)
        fixture.now = 3000000
        fixture.coordinator.exit(job)
        raw = canonical(fixture.coordinator.result(job)).encode()
        receipt = fixture.coordinator.collect(job, raw)
        fixture.coordinator.apply_receipt(receipt)
        self.assertEqual(fixture.coordinator.collect(job, raw), receipt)
        self.assertTrue(fixture.store.state["jobs"][job]["applied"])
        self.assertFalse(fixture.coordinator.rights()["can_pass"])

    def test_A29_explicit_cap_extension_preserves_usage(self):
        """A29 a new cumulative cap allows only the additional admitted repair."""
        fixture = self.fixture()
        seed(fixture, 3)
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.complete_job(job, "NEEDS_CHANGES", [finding("fourth", "fourth")])
        with self.assertRaises(Denied):
            fixture.coordinator.begin(repair=True)
        approval = copy.deepcopy(fixture.store.state["approval"])
        approval.update(interval_id=identity(), deadline_uptime_ms=3000000)
        approval["cumulative_caps"]["repair_cap"] = 4
        fixture.coordinator.emit("ApprovalRecorded", approval, "OWNER")
        fixture.restart()
        self.assertEqual(fixture.store.state["repair_spent"], 3)
        fixture.coordinator.begin(repair=True)
        self.assertEqual(fixture.store.state["repair_spent"], 4)
        self.assertEqual(fixture.store.state["gate_id"], fixture.contract["gate_id"])

    def test_B05_B08_B11_F3_open_failure_survives_success_and_resume(self):
        """Fresh successful checks, replay and extension cannot erase an uncorrected failure."""
        fixture = self.fixture()
        fixture.verify(False)
        issue = next(iter(fixture.store.state["issues"]))
        self.assertEqual(fixture.store.state["checks"], {})
        fixture.verify()
        fixture.restart()
        self.assertEqual(fixture.store.state["issues"][issue]["state"], "OPEN")
        with self.assertRaises(Denied):
            fixture.coordinator.review_round()
        self.expire_and_extend(fixture)
        fixture.restart()
        fixture.verify()
        self.assertEqual(fixture.store.state["issues"][issue]["state"], "OPEN")
        self.assertFalse(fixture.coordinator.rights()["can_pass"])

    def test_B07_partial_correction_cannot_close_other_findings(self):
        """B07 only a specifically proposed correction can progress toward closure."""
        fixture = self.fixture()
        self.review_result(fixture, lambda coordinator, job: coordinator.result(job, "NEEDS_CHANGES", [finding("A", "A"), finding("B", "B")]))
        first, second = list(fixture.store.state["issues"])
        fixture.coordinator.begin(repair=True)
        fixture.coordinator.propose(second)
        fixture.coordinator.seal("partial")
        fixture.verify()
        with self.assertRaises(Denied):
            fixture.coordinator.review_round()
        self.assertEqual(fixture.store.state["issues"][first]["state"], "OPEN")
        self.assertFalse(fixture.coordinator.rights()["can_pass"])

    def test_R2_C03_pending_identity_and_nonapproving_collection(self):
        """Resume and replay retain the pending identity, then require new checks and review."""
        fixture = self.fixture()
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.launch(job)
        request = fixture.store.state["jobs"][job]["request_id"]
        self.expire_and_extend(fixture)
        fixture.restart()
        self.assertEqual(fixture.store.state["jobs"][job]["request_id"], request)
        self.assertEqual(fixture.store.state["review_spent"], 1)
        with self.assertRaises(Denied):
            fixture.coordinator.review_round()
        fixture.coordinator.exit(job)
        receipt = fixture.coordinator.collect(job, canonical(fixture.coordinator.result(job)).encode())
        fixture.coordinator.apply_receipt(receipt)
        self.assertFalse(fixture.store.state["receipts"][receipt]["approval_eligible"])
        self.assertEqual(fixture.store.state["checks"], {})
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        fixture.verify()
        fixture.pass_review()
        self.assertEqual(fixture.store.state["review_spent"], 2)
        self.assertTrue(fixture.coordinator.rights()["pass"])

    def test_R3_C07_malformed_deadlines_do_not_consume_grants(self):
        """Missing, nonnumeric or nonfinite owner deadlines leave the old interval intact."""
        fixture = self.fixture()
        fixture.now = 2700000
        stop_id = fixture.store.state["approval"]["interval_id"]
        fixture.coordinator.emit("ClockExpired", {"interval_id": stop_id, "deadline_uptime_ms": fixture.now})
        original = copy.deepcopy(fixture.store.state["approval"])
        count = fixture.store.connection.execute("SELECT COUNT(*) FROM events").fetchone()[0]
        for value in (None, "6000000", "invalid", float("nan"), float("inf"), -float("inf"), -1, 0, "missing"):
            payload = copy.deepcopy(original)
            if value == "missing":
                del payload["deadline_uptime_ms"]
            else:
                payload["deadline_uptime_ms"] = value
            with self.assertRaises(Denied):
                fixture.coordinator.emit("ApprovalRecorded", payload, "OWNER")
            self.assertEqual(fixture.store.state["approval"], original)
            self.assertEqual(fixture.store.connection.execute("SELECT COUNT(*) FROM events").fetchone()[0], count)
        self.assertFalse(fixture.coordinator.rights()["dispatch"])

    def test_C01_failed_candidate_charged_once(self):
        """C01 repeated failed checks of one repair produce exactly one failure charge."""
        fixture = self.fixture()
        fixture.verify(False)
        issue = next(iter(fixture.store.state["issues"]))
        fixture.repair()
        fixture.verify()
        fixture.verify(False)
        fixture.verify(False)
        fixture.restart()
        self.assertEqual(fixture.store.state["issues"][issue]["failed"], 1)
        self.assertEqual(fixture.store.state["repair_spent"], 1)
        self.assertEqual(len(fixture.store.state["charges"]), 1)

    def test_C09_resume_deadline_is_strict(self):
        """An equal-time deadline is rejected and the first valid later instant expires exactly."""
        fixture = self.fixture()
        fixture.now = 2700000
        old = copy.deepcopy(fixture.store.state["approval"])
        with self.assertRaises(Denied):
            fixture.coordinator.emit("ApprovalRecorded", {**old, "deadline_uptime_ms": fixture.now}, "OWNER")
        fixture.coordinator.approve(fixture.now + 1)
        self.assertTrue(fixture.coordinator.rights()["verify"])
        fixture.now += 1
        self.assertFalse(fixture.coordinator.rights()["verify"])

    def test_S1_D02_D05_late_rejection_counts_and_converges(self):
        """Late rejection retains its issue and failed repair across owner resume and replay."""
        for after_extension in (False, True):
            fixture = self.fixture()
            self.review_result(fixture, lambda coordinator, job: coordinator.result(job, "NEEDS_CHANGES", [finding()]))
            issue = next(iter(fixture.store.state["issues"]))
            fixture.repair("attempt-1")
            fixture.verify()
            job = fixture.coordinator.review_round()[0]
            fixture.coordinator.launch(job)
            fixture.coordinator.exit(job)
            fixture.now = 2700000
            if after_extension:
                fixture.coordinator.approve(3000000)
            receipt = fixture.coordinator.collect(job, canonical(fixture.coordinator.result(job, "NEEDS_CHANGES", [finding()])).encode())
            fixture.coordinator.apply_receipt(receipt)
            fixture.coordinator.approve(4000000)
            fixture.restart()
            self.assertEqual(fixture.store.state["issues"][issue]["state"], "OPEN")
            self.assertEqual(fixture.store.state["issues"][issue]["failed"], 1)
            self.assertFalse(fixture.coordinator.rights()["can_pass"])
            fixture.repair("attempt-2")
            fixture.verify()
            fixture.pass_review()
            self.assertTrue(fixture.coordinator.rights()["pass"])
            self.assertEqual(fixture.store.state["repair_spent"], 2)
            self.assertEqual(fixture.store.state["issues"][issue]["failed"], 1)

    def test_D06_T1_E01_malformed_results_remain_unresolved(self):
        """Every original incomplete-finding family keeps raw evidence and unresolved debt."""
        for malformed in (None, "missing", {}, {"alias": {"issuer": "advisor", "external_id": "A"}}, {**finding(), "evidence": ""}):
            fixture = self.fixture()
            def answer(coordinator, job):
                """Map absent and incomplete legacy facts to the equivalent invalid v2 fields."""
                result = coordinator.result(job, "NEEDS_CHANGES", None if malformed is None else [malformed])
                if malformed == "missing":
                    del result["findings"]
                return result
            job, receipt, raw = self.review_result(fixture, answer)
            fixture.coordinator.approve(3000000)
            fixture.restart()
            with self.assertRaises(Denied):
                fixture.coordinator.verification()
            self.assertTrue(fixture.store.state["receipts"][receipt]["rejected"])
            self.assertEqual(fixture.store.get_blob(fixture.store.state["receipts"][receipt]["final_artifact"]), raw)
            self.assertFalse(fixture.coordinator.rights()["can_pass"])
            other = fixture.coordinator.collect(job, canonical(fixture.coordinator.result(job)).encode())
            self.assertNotEqual(other, receipt)
            self.assertEqual(sum(bool(item.get("rejected")) for item in fixture.store.state["receipts"].values()), 1)
            self.assertFalse(fixture.coordinator.rights()["can_pass"])

    def test_T2_E02_exact_special_aliases_survive_replay(self):
        """All original special-string fixtures remain OPEN under exact alias lookup."""
        identifiers = ["__proto__", "constructor", "prototype", "toString", "hasOwnProperty", "valueOf", "日本語", "a.b", "nul\0key"]
        fixture = self.fixture()
        self.review_result(fixture, lambda coordinator, job: coordinator.result(job, "NEEDS_CHANGES", [finding(value, value) for value in identifiers]))
        fixture.restart()
        aliases = {parse_json(key)["external_id"]: issue for key, issue in fixture.store.state["aliases"].items()}
        self.assertEqual(set(aliases), set(identifiers))
        self.assertTrue(all(fixture.store.state["issues"][aliases[value]]["state"] == "OPEN" for value in identifiers))
        fixture.verify()
        with self.assertRaises(Denied):
            fixture.coordinator.review_round()

    def test_E04_special_alias_actual_repairs_converge(self):
        """Each original special-key finding requires correction and fresh complete review."""
        for value in ("__proto__", "constructor", "prototype"):
            fixture = self.fixture()
            self.review_result(fixture, lambda coordinator, job: coordinator.result(job, "NEEDS_CHANGES", [finding(value, value)]))
            fixture.repair()
            fixture.verify()
            fixture.pass_review()
            self.assertTrue(fixture.coordinator.rights()["pass"])
            self.assertFalse(any(issue["state"] != "CLOSED" for issue in fixture.store.state["issues"].values()))

    def test_E05_invalid_ids_and_evidence_rejected_without_coercion(self):
        """All original invalid identity types are rejected without key coercion or loss."""
        for field in ("external_id", "evidence"):
            for invalid in (None, 1, True, {}, [], "", "missing"):
                fixture = self.fixture()
                item = finding()
                target = item["alias"] if field == "external_id" else item
                if invalid == "missing":
                    del target[field]
                else:
                    target[field] = invalid
                _, receipt, raw = self.review_result(fixture, lambda coordinator, job: coordinator.result(job, "NEEDS_CHANGES", [item]))
                self.assertTrue(fixture.store.state["receipts"][receipt]["rejected"])
                self.assertEqual(fixture.store.get_blob(fixture.store.state["receipts"][receipt]["final_artifact"]), raw)
                self.assertFalse(fixture.coordinator.rights()["can_pass"])
