"""Bounded schedule exploration against the actual isolated SQLite Coordinator."""

import copy
import itertools
import json
import time
from pathlib import Path

import test_v2
from common import Denied, ROOT, SchemaValidator, StorageFailure, canonical, digest
from reducer import permissions
from store import EventStore
from test_v2 import Fixture, finding

OUTPUT = ROOT / "results" / "epoch6"
STATS = {"unique_literal_states": 0, "acknowledged_commit_transitions": 0, "external_clock_observations": 0,
         "rejected_commands": 0, "safety_checks": 0, "schedules_completed": 0,
         "schedules_planned": 432, "max_committed_depth": 0, "recovery_exercises": 0,
         "duplicate_exercises": 0, "conflict_exercises": 0, "pass_witnesses": 0}
STATES = set()
ORIGINAL_APPEND = EventStore.append
CURRENT_LABEL = "initialization"


def observe(store, clock, previous=None):
    """Check independent safety predicates after each real committed transaction."""
    state = store.state
    rights = permissions(state, clock, store.healthy)
    signature = digest(canonical({"projection": state, "clock": clock, "healthy": store.healthy}).encode())
    STATES.add(signature)
    STATS["unique_literal_states"] = len(STATES)
    STATS["safety_checks"] += 1
    assert len(state["charges"]) == len({tuple(charge) for charge in state["charges"]}), "Duplicate failure charge"
    approval = state["approval"]
    if approval:
        assert state["repair_spent"] <= approval["cumulative_caps"]["repair_cap"], "Repair cap exceeded"
        assert state["review_spent"] <= approval["cumulative_caps"]["review_round_cap"], "Review cap exceeded"
    if previous:
        assert state["repair_spent"] >= previous["repair_spent"], "Repair budget reset"
        assert state["review_spent"] >= previous["review_spent"], "Review budget reset"
        for key, issue in previous["issues"].items():
            assert key in state["issues"], "Finding disappeared"
            assert state["issues"][key]["failed"] >= issue["failed"], "Failure count reset"
    pending = any(job["status"] not in {"PROVED_NOT_STARTED", "RETIRED"}
                  and not (job["status"] == "EXITED" and job.get("applied")) for job in state["jobs"].values())
    debt = any(not receipt.get("applied") or receipt.get("rejected") for receipt in state["receipts"].values())
    if pending:
        assert not rights["edit"] and not rights["repair"], "Editing while a final job is pending"
    expired = not approval or clock["boot_id"] != approval["boot_id"] or clock["uptime_ms"] >= approval["deadline_uptime_ms"]
    if expired or state["stops"] or not store.healthy:
        assert not any(rights[key] for key in ("edit", "verify", "review", "dispatch", "can_pass", "pass")), "Action escaped stop or deadline"
    if debt:
        assert not rights["can_pass"] and not rights["pass"], "PASS with unapplied receipt"
    if rights["pass"] or rights["can_pass"]:
        current = canonical(state["revision"])
        assert not pending and not debt and not state["stops"] and store.healthy, "PASS with unresolved debt"
        assert all(state["checks"].get(check) == current for check in state["contract"]["required_checks"]), "PASS without current checks"
        assert all(state["clears"].get(role) == current for role in state["contract"]["required_roles"]), "PASS without current role coverage"
        assert all(issue["state"] == "CLOSED" and issue.get("closure") == current for issue in state["issues"].values()), "PASS with stale or open findings"


def observed_append(store, drafts, *arguments, **keywords):
    """Instrument the test process only, preserving the production append implementation."""
    previous = copy.deepcopy(store.state)
    try:
        result = ORIGINAL_APPEND(store, drafts, *arguments, **keywords)
    except Denied:
        STATS["rejected_commands"] += 1
        raise
    except StorageFailure:
        observe(store, drafts[-1]["clock"], previous)
        raise
    STATS["acknowledged_commit_transitions"] += 1
    observe(store, drafts[-1]["clock"], previous)
    depth = store.connection.execute("SELECT COUNT(DISTINCT transaction_id) FROM (SELECT json_extract(body,'$.transaction_id') AS transaction_id FROM events)").fetchone()[0]
    STATS["max_committed_depth"] = max(STATS["max_committed_depth"], depth)
    return result


def seed(fixture, repair_count):
    """Reach valid zero, one, or last-admitted-repair boundary states via actual commands."""
    if repair_count == 0:
        fixture.verify()
        return
    fixture.verify(False)
    fixture.repair("first")
    fixture.verify()
    if repair_count == 1:
        return
    for number in (2, 3):
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.complete_job(job, "NEEDS_CHANGES", [finding(str(number), str(number))])
        fixture.repair("repair-" + str(number))
        fixture.verify()


def schedule(parameters):
    """Explore one bounded combination of budget, job, time, fault, duplicate and conflict."""
    repair_count, job_kind, at, fault, duplicate, outcome = parameters
    fixture = Fixture()
    try:
        seed(fixture, repair_count)
        job = fixture.coordinator.verification() if job_kind == "check" else fixture.coordinator.review_round()[0]
        fixture.coordinator.launch(job)
        fixture.coordinator.exit(job)
        verdict = "NEEDS_CHANGES" if outcome == "reject" else "CLEAR"
        result = fixture.coordinator.result(job, verdict, [finding()])
        raw = canonical(result).encode()
        fixture.now = at
        observe(fixture.store, fixture.clock())
        STATS["external_clock_observations"] += 1
        receipt = fixture.coordinator.collect(job, raw)
        if duplicate:
            before = canonical(fixture.store.state)
            assert fixture.coordinator.collect(job, raw) == receipt
            assert canonical(fixture.store.state) == before, "Duplicate changed projection"
            STATS["duplicate_exercises"] += 1
        try:
            fixture.coordinator.apply_receipt(receipt, fault=fault)
        except StorageFailure:
            assert fault is not None, "Unexpected storage failure"
            fixture.restart()
            fixture.coordinator.apply_receipt(receipt)
            STATS["recovery_exercises"] += 1
        if verdict == "CLEAR" and job_kind == "review":
            verify_ids = [key for key, value in fixture.store.state["receipts"].items()
                          if value.get("result", {}).get("outcome") == "PASS"
                          and value["result"]["revision"] == fixture.store.state["revision"]]
            for issue_id in fixture.store.state["issues"]:
                fixture.coordinator.close_issue(issue_id, verify_ids, [receipt])
            if fixture.coordinator.rights()["can_pass"]:
                fixture.coordinator.assess()
                STATS["pass_witnesses"] += 1
        if outcome == "conflict":
            conflicting = fixture.coordinator.result(job, "NEEDS_CHANGES", [finding("late", "late")])
            fixture.coordinator.collect(job, canonical(conflicting).encode())
            assert "EVIDENCE_CONFLICT" in fixture.store.state["stops"].values()
            assert not fixture.coordinator.rights()["pass"]
            STATS["conflict_exercises"] += 1
        fixture.coordinator.apply_receipt(receipt) if outcome != "conflict" else None
        assert fixture.store.state == fixture.store.replay(), "Replay diverged"
        observe(fixture.store, fixture.clock())
        STATS["schedules_completed"] += 1
    finally:
        fixture.close()


def parallel_review_witness():
    """Check delayed peer completion and crash recovery under a parallel rejection."""
    fixture = Fixture(roles=["advisor", "peer"])
    try:
        fixture.verify()
        first, second = fixture.coordinator.review_round()
        fixture.coordinator.complete_job(first, "NEEDS_CHANGES", [finding()])
        fixture.coordinator.launch(second)
        assert not fixture.coordinator.rights()["repair"], "Peer still running allowed edit"
        fixture.restart()
        assert not fixture.coordinator.rights()["repair"], "Crash discarded pending peer"
        fixture.coordinator.exit(second)
        receipt = fixture.coordinator.collect(second, canonical(fixture.coordinator.result(second)).encode())
        try:
            fixture.coordinator.apply_receipt(receipt)
        except Denied as error:
            evidence = {"expected": "Collect the original peer answer without granting stale CLEAR authority; terminate the peer so bounded repair can proceed",
                        "observed": str(error), "rights": fixture.coordinator.rights(),
                        "original_job_revision": fixture.store.state["jobs"][second]["revision"],
                        "current_revision": fixture.store.state["revision"],
                        "projection": fixture.store.state,
                        "events": [json.loads(row[0]) for row in fixture.store.connection.execute("SELECT body FROM events ORDER BY sequence")],
                        "classification": "IMPLEMENTATION_LIVENESS_COUNTEREXAMPLE: original parallel snapshot is preserved but valid peer result cannot finalize"}
            (OUTPUT / "counterexample-parallel-review.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
            raise AssertionError("Peer rejection plus late original CLEAR prevents review finalization and bounded repair") from error
        assert not fixture.coordinator.rights()["can_pass"], "Late peer CLEAR erased rejection"
        assert any(issue["state"] == "OPEN" for issue in fixture.store.state["issues"].values())
        observe(fixture.store, fixture.clock())
    finally:
        fixture.close()


def requalification_witness():
    """Require previously corrected stale evidence to requalify without meaningless edits."""
    fixture = Fixture()
    try:
        fixture.verify(False)
        fixture.repair()
        fixture.verify()
        fixture.pass_review()
        fixture.coordinator.approve(3000000)
        _, verification = fixture.verify()
        jobs = fixture.coordinator.review_round()
        clears = [fixture.coordinator.complete_job(job) for job in jobs]
        issue_id = next(iter(fixture.store.state["issues"]))
        observe(fixture.store, fixture.clock())
        before = copy.deepcopy(fixture.store.state)
        try:
            fixture.coordinator.close_issue(issue_id, [verification], clears)
        except Denied as error:
            evidence = {"contract": "findings-evidence.md:38 and permissions.md closure/requalification",
                        "expected": "Previously corrected CLOSED/STALE issue can accept current checks and independent CLEAR without source edit",
                        "observed": str(error), "rights": fixture.coordinator.rights(), "projection": before,
                        "events": [json.loads(row[0]) for row in fixture.store.connection.execute("SELECT body FROM events ORDER BY sequence")],
                        "classification": "IMPLEMENTATION_LIVENESS_COUNTEREXAMPLE; no intentional v2 specification difference established"}
            (OUTPUT / "counterexample-requalification.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
            raise AssertionError("Previously corrected CLOSED/STALE finding cannot requalify despite fresh checks and CLEAR") from error
        assert fixture.coordinator.rights()["can_pass"], "Fresh requalification cannot progress to PASS"
    finally:
        fixture.close()


def bounded_parallel_interleavings():
    """Explore all legal store/apply orders for two roles under bounded fault/time variants."""
    tokens = ("A-store", "A-apply", "P-store", "P-apply")
    orders = [order for order in itertools.permutations(tokens)
              if order.index("A-store") < order.index("A-apply") and order.index("P-store") < order.index("P-apply")]
    STATS["parallel_interleavings_planned"] = 144
    STATS["parallel_interleavings_completed"] = 0
    records = []
    for order, results, restart_at, now in itertools.product(
            orders, (("CLEAR", "CLEAR"), ("CLEAR", "NEEDS_CHANGES"), ("NEEDS_CHANGES", "CLEAR"), ("NEEDS_CHANGES", "NEEDS_CHANGES")),
            ("none", "first-store", "first-apply"), (100, 2700000)):
        (OUTPUT / "current-interleaving.json").write_text(json.dumps({"order": order, "results": results,
            "restart": restart_at, "time": now})+"\n", encoding="utf-8")
        fixture = Fixture(roles=["advisor", "peer"])
        try:
            fixture.verify()
            jobs = dict(zip(("A", "P"), fixture.coordinator.review_round()))
            raw = {}
            for role, verdict in zip(("A", "P"), results):
                fixture.coordinator.launch(jobs[role])
                fixture.coordinator.exit(jobs[role])
                raw[role] = canonical(fixture.coordinator.result(jobs[role], verdict, [finding(role, role)])).encode()
            fixture.now = now
            observe(fixture.store, fixture.clock())
            receipts, stores, applications, restarted = {}, 0, 0, False
            for token in order:
                role, operation = token.split("-")
                if operation == "store":
                    receipts[role] = fixture.coordinator.collect(jobs[role], raw[role])
                    previous = canonical(fixture.store.state)
                    assert fixture.coordinator.collect(jobs[role], raw[role]) == receipts[role]
                    assert canonical(fixture.store.state) == previous, "Interleaved duplicate changed state"
                    stores += 1
                else:
                    fixture.coordinator.apply_receipt(receipts[role])
                    previous = canonical(fixture.store.state)
                    fixture.coordinator.apply_receipt(receipts[role])
                    assert canonical(fixture.store.state) == previous, "Repeated interleaved application changed state"
                    applications += 1
                if not restarted and ((restart_at == "first-store" and stores == 1) or
                                      (restart_at == "first-apply" and applications == 1)):
                    fixture.restart()
                    restarted = True
            if "NEEDS_CHANGES" in results:
                assert not fixture.coordinator.rights()["can_pass"], "Parallel CLEAR erased a rejection"
                assert sum(issue["state"] == "OPEN" for issue in fixture.store.state["issues"].values()) == results.count("NEEDS_CHANGES")
                assert fixture.coordinator.rights()["repair"] == (now < 2700000), "Completed peer still freezes repair or expiry was ignored"
            else:
                assert fixture.coordinator.rights()["can_pass"] == (now < 2700000), "Fair complete CLEAR schedule failed progress or bypassed expiry"
                if now < 2700000:
                    fixture.coordinator.assess()
                    STATS["pass_witnesses"] += 1
            assert fixture.store.state == fixture.store.replay(), "Interleaving replay diverged"
            observe(fixture.store, fixture.clock())
            STATS["parallel_interleavings_completed"] += 1
            records.append({"order": order, "results": results, "restart": restart_at, "time": now, "result": "PASS"})
        finally:
            fixture.close()
    (OUTPUT / "parallel-interleavings.json").write_text(json.dumps({"roles": 2, "operations": 4,
        "legal_orders": len(orders), "orders": orders, "cases": records, "scope": "All6 topological orders times4 outcomes times3 replay points times2 clocks; not all internal process interleavings"}, indent=2)+"\n", encoding="utf-8")


def main():
    """Explore a finite schedule product once; stop on the first genuine assertion failure."""
    global CURRENT_LABEL
    test_v2.RUN_ROOT = OUTPUT / "schedule-fixtures"
    test_v2.RUN_ROOT.mkdir()
    validator = SchemaValidator()
    test_v2.VALIDATOR = validator
    EventStore.append = observed_append
    started = time.monotonic()
    report = {"adoption_gate": "BLOCKED", "method": "Finite actual-Coordinator schedule product, not exhaustive interleaving model checking",
              "bounds": {"repair_seed_counts": [0, 1, 3], "roles_grid": 1, "roles_parallel_witness": 2,
                         "clock_values": [100, 2699999, 2700000, 2700001], "faults": [None, "after_events", "after_commit"],
                         "duplicate": [False, True], "outcome": ["clear", "reject", "conflict"], "wall_budget_seconds": 180},
              "state_identity": "Exact projection including UUIDs; no alpha/symmetry reduction. Counts are literal observed states; transitions count acknowledged commits, excluding lost-ACK commits until replay.",
              "unexplored": ["Unbounded event sequences", "All command interleavings", "External authority and live process identity", "Old88:38 limited observable matches,12 intentional differences,38 unsupported; no general equivalence proof"]}
    try:
        parameters = itertools.product((0, 1, 3), ("check", "review"), (100, 2699999, 2700000, 2700001),
                                       (None, "after_events", "after_commit"), (False, True), ("clear", "reject", "conflict"))
        previous = json.loads((ROOT / "results" / "epoch5" / "stop.json").read_text(encoding="utf-8"))["exploration"]["remaining_grid_cases"]
        priority = {(item["budget"], item["kind"], item["at"], item["fault"], item["duplicate"], item["outcome"]) for item in previous}
        parameters = sorted(list(parameters), key=lambda values: values not in priority)
        STATS["previous_remaining_planned"] = len(priority)
        STATS["previous_remaining_retested"] = 0
        # Every combination is finite; retain an explicit cutoff instead of treating missing traces as passed.
        for values in parameters:
            if time.monotonic()-started > 180:
                report["grid_cutoff"] = "wall budget reached; remaining combinations untested"
                break
            CURRENT_LABEL = "grid:" + repr(values)
            schedule(values)
            if values in priority:
                STATS["previous_remaining_retested"] += 1
        CURRENT_LABEL = "parallel-review-witness"
        parallel_review_witness()
        CURRENT_LABEL = "stale-closed-requalification-witness"
        requalification_witness()
        CURRENT_LABEL = "bounded-parallel-store-apply-interleavings"
        bounded_parallel_interleavings()
        report["success"] = True
    except Exception as error:
        report.update(success=False, failed_phase=CURRENT_LABEL, error_type=type(error).__name__, error=str(error))
    finally:
        EventStore.append = ORIGINAL_APPEND
        validator.close()
        report.update(stats=STATS, elapsed_seconds=round(time.monotonic()-started, 3), schema_engine=validator.metadata)
        (OUTPUT / "state-space-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
