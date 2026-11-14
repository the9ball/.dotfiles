"""Requalification tests for corrected findings with current evidence and unchanged authority."""

import copy
import unittest

from common import Denied, canonical
from test_v2 import Fixture, finding
from verify_state_space import seed


class RequalificationTests(unittest.TestCase):
    """Old proof cannot grant approval; current verification and complete review are required."""

    def fixture(self, roles=None):
        """Own a fresh private gate for each negative or positive path."""
        fixture = Fixture(roles=roles)
        self.addCleanup(fixture.close)
        return fixture

    def closed(self, fixture, assess=True):
        """Record a corrected issue and current closure, optionally without final PASS."""
        fixture.verify(False)
        fixture.repair()
        fixture.verify()
        jobs = fixture.coordinator.review_round()
        clears = [fixture.coordinator.complete_job(job) for job in jobs]
        checks = [key for key, receipt in fixture.store.state["receipts"].items()
                  if receipt.get("result", {}).get("outcome") == "PASS"]
        issue = next(iter(fixture.store.state["issues"]))
        fixture.coordinator.close_issue(issue, checks, clears)
        if assess:
            fixture.coordinator.assess()
        return issue, checks, clears

    def fresh(self, fixture):
        """Provide a complete current verification and all independently modeled roles."""
        _, check = fixture.verify()
        jobs = fixture.coordinator.review_round()
        clears = [fixture.coordinator.complete_job(job) for job in jobs]
        return check, clears

    def test_closed_stale_requalifies_without_new_repair(self):
        """The known counterexample converges only after fresh proofs, with budgets preserved."""
        fixture = self.fixture()
        issue, _, _ = self.closed(fixture)
        fixture.coordinator.approve(3000000)
        before = copy.deepcopy(fixture.store.state)
        check, clears = self.fresh(fixture)
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        fixture.coordinator.close_issue(issue, [check], clears)
        fixture.coordinator.assess()
        self.assertTrue(fixture.coordinator.rights()["pass"])
        self.assertEqual(fixture.store.state["repair_spent"], before["repair_spent"])
        self.assertEqual(fixture.store.state["charges"], before["charges"])
        self.assertEqual(fixture.store.state["approval"], before["approval"])
        self.assertEqual(fixture.store.state["issues"][issue]["episode"], before["issues"][issue]["episode"])
        fixture.restart()
        self.assertTrue(fixture.coordinator.rights()["pass"])

    def test_old_checks_clears_and_incomplete_role_references_rejected(self):
        """Stale evidence or missing role references cannot close a current-generation finding."""
        fixture = self.fixture(roles=["advisor", "peer"])
        issue, old_checks, old_clears = self.closed(fixture)
        fixture.coordinator.approve(3000000)
        with self.assertRaises(Denied):
            fixture.coordinator.close_issue(issue, old_checks, old_clears)
        check, clears = self.fresh(fixture)
        for checks, reviews in ((old_checks, clears), ([check], old_clears), ([check], clears[:1])):
            with self.assertRaises(Denied):
                fixture.coordinator.close_issue(issue, checks, reviews)
            self.assertFalse(fixture.coordinator.rights()["can_pass"])
        wrong = fixture.coordinator.store.put_blob(b'"wrong-proof"')
        with self.assertRaises(Denied):
            fixture.coordinator.emit("ClosureAccepted", {"issue_id": issue, "attempt_id": fixture.store.state["attempt"],
                "verification_receipt_ids": [check], "clear_receipt_ids": clears, "correction_proof": wrong})
        fixture.coordinator.close_issue(issue, [check], clears)
        self.assertTrue(fixture.coordinator.rights()["can_pass"])

    def test_requalification_does_not_revive_expired_or_exhausted_permissions(self):
        """Expiry is binding, and the last admitted repair can finish without refunding limits."""
        fixture = self.fixture()
        issue, _, _ = self.closed(fixture)
        fixture.coordinator.approve(3000000)
        check, clears = self.fresh(fixture)
        prior = copy.deepcopy(fixture.store.state)
        fixture.now = 3000000
        with self.assertRaises(Denied):
            fixture.coordinator.close_issue(issue, [check], clears)
        self.assertEqual(fixture.store.state["approval"], prior["approval"])
        self.assertEqual(fixture.store.state["repair_spent"], prior["repair_spent"])
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        last = self.fixture()
        seed(last, 3)
        last.pass_review()
        last.coordinator.approve(3000000)
        check, clears = self.fresh(last)
        for issue in last.store.state["issues"]:
            last.coordinator.close_issue(issue, [check], clears)
        last.coordinator.assess()
        self.assertEqual(last.store.state["repair_spent"], 3)
        self.assertEqual(last.store.state["review_spent"], 4)
        self.assertFalse(last.coordinator.rights()["repair"])
        self.assertFalse(last.coordinator.rights()["review"])
        self.assertTrue(last.coordinator.rights()["pass"])

    def test_open_adverse_finding_cannot_reuse_closed_proof(self):
        """A newly adverse current review reopens the issue and removes closure eligibility."""
        fixture = self.fixture()
        issue, checks, clears = self.closed(fixture)
        fixture.coordinator.approve(3000000)
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        adverse = finding("review-unit", "unit")
        adverse["anchor"] = {"check_id": "unit", "assertion_id": "required-result",
                             "resource_scope_id": "owned-source", "security_invariant_id": "ordinary"}
        fixture.coordinator.complete_job(job, "NEEDS_CHANGES", [adverse])
        self.assertEqual(fixture.store.state["issues"][issue]["state"], "OPEN")
        with self.assertRaises(Denied):
            fixture.coordinator.close_issue(issue, checks, clears)
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        fixture.coordinator.approve(4000000)
        self.assertEqual(fixture.store.state["issues"][issue]["state"], "OPEN")

    def test_changed_content_requires_explicit_new_correction_record(self):
        """Old proof is insufficient for changed content; a new proposal can qualify fresh proof."""
        for refresh in (False, True):
            with self.subTest(refresh=refresh):
                fixture = self.fixture()
                issue, _, _ = self.closed(fixture, assess=False)
                job = fixture.coordinator.review_round()[0]
                fixture.coordinator.complete_job(job, "NEEDS_CHANGES", [finding("other", "other")])
                other = next(key for key in fixture.store.state["issues"] if key != issue)
                fixture.coordinator.begin(repair=True)
                fixture.coordinator.propose(other)
                if refresh:
                    fixture.coordinator.propose(issue)
                fixture.coordinator.seal("changed-content")
                check, clears = self.fresh(fixture)
                if refresh:
                    fixture.coordinator.close_issue(issue, [check], clears)
                    fixture.coordinator.close_issue(other, [check], clears)
                    self.assertTrue(fixture.coordinator.rights()["can_pass"])
                else:
                    with self.assertRaises(Denied):
                        fixture.coordinator.close_issue(issue, [check], clears)
                    self.assertFalse(fixture.coordinator.rights()["can_pass"])
