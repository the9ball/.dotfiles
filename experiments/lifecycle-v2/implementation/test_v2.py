"""Independent expected-outcome traces for the isolated v2 implementation."""

import copy
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import unicodedata
from pathlib import Path

from common import Denied, ROOT, SchemaValidator, StorageFailure, artifact, canonical, digest, identity, parse_json
from coordinator import Coordinator
from os_adapter import capture, harmless_child, inventory
from reducer import apply_event, permissions
from store import EventStore

VALIDATOR = None
RUN_ROOT = None


class Fixture:
    """Create uniquely owned files and a mock-authority gate, never real credentials."""

    def __init__(self, roles=None):
        """Allocate one database and a deterministic controllable clock."""
        self.directory = Path(tempfile.mkdtemp(prefix="case-", dir=RUN_ROOT))
        self.now = 100
        self.boot = "simulated-boot"
        proof = artifact(b'{"simulation_only":true}')
        self.principals = {role: {"principal_ref": role.lower() + "-mock", "proof": proof} for role in ("OWNER", "BROKER")}
        self.contract = {"gate_id": identity(), "simulation_only": True, "required_checks": ["unit"],
                         "required_roles": roles or ["advisor"], "user_review_required": False}
        self.store = EventStore(self.directory, self.contract, VALIDATOR, self.principals)
        self.coordinator = Coordinator(self.store, self.clock)
        self.coordinator.open_gate()
        self.coordinator.begin()
        self.coordinator.seal()

    def clock(self):
        """Return a stable simulated monotonic clock with independently controlled UTC display."""
        return {"boot_id": self.boot, "uptime_ms": self.now, "observed_utc": "2026-11-12T00:00:00Z"}

    def close(self):
        """Retain evidence but release only this fixture's database and lock."""
        if self.store is not None:
            self.store.close()

    def restart(self):
        """Recover from the same files and advance writer fencing without budget resets."""
        self.store.close()
        self.store = EventStore(self.directory, self.contract, VALIDATOR, self.principals)
        self.coordinator = Coordinator(self.store, self.clock)
        self.coordinator.recover()

    def verify(self, passed=True):
        """Complete a mock verification with an independently selected expected outcome."""
        job = self.coordinator.verification()
        receipt = self.coordinator.complete_job(job, "CLEAR" if passed else "NEEDS_CHANGES")
        return job, receipt

    def repair(self, content="fixed"):
        """Propose correction of every existing issue and seal a new mock revision."""
        self.coordinator.begin(repair=True)
        for issue_id in self.store.state["issues"]:
            self.coordinator.propose(issue_id)
        self.coordinator.seal(content)

    def pass_review(self):
        """Collect current required roles and close only explicitly reviewed issues."""
        jobs = self.coordinator.review_round()
        receipts = [self.coordinator.complete_job(job) for job in jobs]
        verification = [key for key, value in self.store.state["receipts"].items() if value.get("result", {}).get("outcome") == "PASS"
                        and value["result"]["revision"] == self.store.state["revision"]]
        for issue_id in self.store.state["issues"]:
            self.coordinator.close_issue(issue_id, verification, receipts)
        self.coordinator.assess()
        return jobs, receipts


def finding(external_id="finding-A", anchor_id="invariant-A"):
    """Build a fully specified ordinary finding with an independent stable anchor."""
    return {"alias": {"issuer": "advisor", "external_id": external_id},
            "anchor": {"check_id": "review", "assertion_id": anchor_id, "resource_scope_id": "owned-source", "security_invariant_id": "ordinary"},
            "severity": "ORDINARY", "description": "Repair needed", "evidence": artifact(b'{"simulation_only":true}')}


class V2Tests(unittest.TestCase):
    """Assert observable safety boundaries and successful progress without external effects."""

    def setUp(self):
        """Keep all fixtures for evidence and register safe per-test release."""
        self.fixture = Fixture()
        self.addCleanup(self.fixture.close)

    def test_00_explicit_metaschema_rejects_invalid_schema(self):
        """Disabling recursive self-check cannot allow an invalid nested schema through."""
        schema_path = self.fixture.directory / "invalid-schema.json"
        schema_path.write_text(json.dumps({"$schema": "https://json-schema.org/draft/2020-12/schema",
            "$defs": {"invalid": {"type": 42}}, "type": "object"}), encoding="utf-8")
        command = ["pwsh.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-File",
                   str(ROOT / "schema-worker.ps1"), "-SchemaPath", str(schema_path)]
        result = subprocess.run(command, input=b"", capture_output=True, timeout=20)
        (self.fixture.directory / "invalid-schema.stdout.txt").write_bytes(result.stdout)
        (self.fixture.directory / "invalid-schema.stderr.txt").write_bytes(result.stderr)
        self.assertEqual(result.returncode, 1)
        response = parse_json(result.stdout)
        self.assertFalse(response["ready"])
        self.assertEqual(response["stage"], "evaluate-metaschema")

    def test_01_full_schema_24_event_payloads(self):
        """Validate the full metaschema and each discriminator, including negative shape tests."""
        schema = parse_json((ROOT.parent / "event-schema.schema.json").read_bytes())
        self.assertTrue(VALIDATOR.metadata["metaschema"])
        for variant in schema["allOf"]:
            kind = variant["if"]["properties"]["event_type"]["const"]
            payload = sample(variant["then"]["properties"]["payload"], schema)
            event = self.fixture.store.event(kind, payload, self.fixture.clock())
            self.assertTrue(VALIDATOR.validate(event), kind)
            event["payload"]["unexpected"] = True
            self.assertFalse(VALIDATOR.validate(event), kind)
        event = self.fixture.store.event("StopLatched", {"stop_id": identity(), "reason": "DEADLINE", "evidence": self.fixture.coordinator.proof}, self.fixture.clock())
        event["clock"]["observed_utc"] = "not-a-date"
        self.assertFalse(VALIDATOR.validate(event))

    def test_02_success_and_replay(self):
        """All required checks and independent mock roles can converge to simulated PASS."""
        fixture = self.fixture
        fixture.verify()
        fixture.pass_review()
        self.assertTrue(fixture.coordinator.rights()["pass"])
        before = copy.deepcopy(fixture.store.state)
        self.assertEqual(before, fixture.store.replay())
        fixture.restart()
        self.assertTrue(fixture.coordinator.rights()["pass"])

    def test_03_failure_keeps_gate_blocked_and_allows_repair(self):
        """A02/A03/B09: correct a failed check without deleting its unresolved history."""
        fixture = self.fixture
        fixture.verify(False)
        self.assertFalse(fixture.coordinator.rights()["pass"])
        self.assertTrue(fixture.coordinator.rights()["repair"])
        fixture.repair()
        fixture.verify()
        fixture.pass_review()
        self.assertTrue(fixture.coordinator.rights()["pass"])
        self.assertEqual(fixture.store.state["repair_spent"], 1)

    def test_04_deadline_boundary_and_first_receipt(self):
        """A20/F2/B02/P05: collect the first answer at the exact deadline but never PASS."""
        fixture = self.fixture
        job = fixture.coordinator.verification()
        fixture.coordinator.launch(job)
        fixture.coordinator.exit(job)
        raw = canonical(fixture.coordinator.result(job)).encode()
        fixture.now = 2700000
        receipt = fixture.coordinator.collect(job, raw)
        fixture.coordinator.apply_receipt(receipt)
        self.assertTrue(fixture.store.state["receipts"][receipt]["applied"])
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        with self.assertRaises(Denied):
            fixture.coordinator.verification()

    def test_05_pending_review_survives_restart(self):
        """R2/P06: restart retains identity, freezes edits and never launches twice."""
        fixture = self.fixture
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.launch(job)
        request_id = fixture.store.state["jobs"][job]["request_id"]
        fixture.restart()
        self.assertEqual(fixture.store.state["jobs"][job]["request_id"], request_id)
        self.assertIn("UNKNOWN_JOB", fixture.store.state["stops"].values())
        with self.assertRaises(Denied):
            fixture.coordinator.launch(job)

    def test_06_identical_receipt_is_idempotent(self):
        """P02: duplicate delivery does not create another receipt or another charge."""
        fixture = self.fixture
        job = fixture.coordinator.verification()
        fixture.coordinator.launch(job)
        fixture.coordinator.exit(job)
        raw = canonical(fixture.coordinator.result(job, "NEEDS_CHANGES")).encode()
        first = fixture.coordinator.collect(job, raw)
        fixture.coordinator.apply_receipt(first)
        count = len(fixture.store.state["issues"])
        self.assertEqual(fixture.coordinator.collect(job, raw), first)
        fixture.coordinator.apply_receipt(first)
        self.assertEqual(len(fixture.store.state["issues"]), count)

    def test_07_conflict_invalidates_pass(self):
        """P02/P08: a different final answer after completion revokes current PASS."""
        fixture = self.fixture
        fixture.verify()
        jobs, _ = fixture.pass_review()
        job = jobs[0]
        raw = canonical(fixture.coordinator.result(job, "NEEDS_CHANGES", [finding()])).encode()
        fixture.coordinator.collect(job, raw)
        self.assertFalse(fixture.coordinator.rights()["pass"])
        self.assertIn("EVIDENCE_CONFLICT", fixture.store.state["stops"].values())

    def test_08_malformed_rejection_survives_resume(self):
        """T1/E01: incomplete NEEDS_CHANGES remains durable unclassified debt."""
        fixture = self.fixture
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.launch(job)
        fixture.coordinator.exit(job)
        raw = canonical(fixture.coordinator.result(job, "NEEDS_CHANGES", None)).encode()
        receipt = fixture.coordinator.collect(job, raw)
        fixture.coordinator.apply_receipt(receipt)
        fixture.coordinator.approve(3000000)
        fixture.restart()
        self.assertTrue(fixture.store.state["receipts"][receipt]["rejected"])
        self.assertFalse(fixture.coordinator.rights()["can_pass"])

    def test_09_special_finding_identifiers(self):
        """T2: arbitrary aliases cannot escape durable canonical issue accounting."""
        fixture = self.fixture
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        variants = [finding(name, name) for name in ("__proto__", "constructor", "prototype", "é", "é")]
        fixture.coordinator.complete_job(job, "NEEDS_CHANGES", variants)
        self.assertEqual(len(fixture.store.state["issues"]), 5)
        fixture.restart()
        self.assertEqual(len(fixture.store.state["issues"]), 5)
        self.assertFalse(fixture.coordinator.rights()["can_pass"])

    def test_10_last_attempt_and_same_issue_budget(self):
        """P04: distinct issues permit the third admitted repair to complete normally."""
        fixture = self.fixture
        fixture.verify(False)
        fixture.repair("first")
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.complete_job(job, "NEEDS_CHANGES", [finding("second", "second")])
        fixture.repair("second")
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.complete_job(job, "NEEDS_CHANGES", [finding("third", "third")])
        fixture.repair("third")
        fixture.verify()
        fixture.pass_review()
        self.assertEqual(fixture.store.state["repair_spent"], 3)
        self.assertTrue(fixture.coordinator.rights()["pass"])
        self.assertFalse(fixture.coordinator.rights()["repair"])

    def test_11_transaction_failure_keeps_t1_debt(self):
        """P01/P18: T2 rollback cannot acknowledge or partially apply findings."""
        fixture = self.fixture
        job = fixture.coordinator.verification()
        fixture.coordinator.launch(job)
        fixture.coordinator.exit(job)
        raw = canonical(fixture.coordinator.result(job, "NEEDS_CHANGES")).encode()
        receipt = fixture.coordinator.collect(job, raw)
        with self.assertRaises(StorageFailure):
            fixture.coordinator.apply_receipt(receipt, fault="after_events")
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        fixture.restart()
        self.assertFalse(fixture.store.state["receipts"][receipt]["applied"])
        self.assertEqual(fixture.store.state["issues"], {})
        fixture.coordinator.apply_receipt(receipt)
        self.assertEqual(len(fixture.store.state["issues"]), 1)

    def test_12_lost_ack_recovery(self):
        """P01: a committed T1 without ACK is reconstructed without duplicate debt."""
        fixture = self.fixture
        job = fixture.coordinator.verification()
        fixture.coordinator.launch(job)
        fixture.coordinator.exit(job)
        raw = canonical(fixture.coordinator.result(job)).encode()
        with self.assertRaises(StorageFailure):
            fixture.coordinator.collect(job, raw, fault="after_commit")
        fixture.restart()
        self.assertEqual(len(fixture.store.state["receipts"]), 1)
        receipt = fixture.coordinator.collect(job, raw)
        fixture.coordinator.apply_receipt(receipt)
        self.assertEqual(len(fixture.store.state["receipts"]), 1)

    def test_13_append_only_and_writer_lock(self):
        """P18: SQL UPDATE/DELETE and a concurrent writer cannot mutate the ledger."""
        fixture = self.fixture
        with self.assertRaises(sqlite3.IntegrityError):
            fixture.store.connection.execute("DELETE FROM events")
        with self.assertRaises(sqlite3.IntegrityError):
            fixture.store.connection.execute("UPDATE events SET body='{}'")
        with self.assertRaises(Denied):
            EventStore(fixture.directory, fixture.contract, VALIDATOR, fixture.principals)

    def test_14_capture_pre_and_during_changes(self):
        """T3/S2/P09: detect pre-baseline drift and actual content changes during capture."""
        directory = self.fixture.directory / "capture"
        directory.mkdir()
        file = directory / "owned.txt"
        file.write_text("before", encoding="utf-8")
        expected = inventory(directory)
        file.write_text("changed-before", encoding="utf-8")
        with self.assertRaises(Denied):
            capture(directory, expected)
        file.write_text("before", encoding="utf-8")
        with self.assertRaises(Denied):
            capture(directory, expected, lambda: file.write_text("changed-during", encoding="utf-8"))
        self.assertEqual(file.read_text(encoding="utf-8"), "changed-during")

    def test_15_clock_and_actor_fail_closed(self):
        """P11/P12: clock rollback and forged owner identity cannot start work."""
        fixture = self.fixture
        fixture.now = 99
        self.assertFalse(fixture.coordinator.rights()["verify"])
        fixture.now = 100
        event = fixture.store.event("ApprovalRecorded", copy.deepcopy(fixture.store.state["approval"]), fixture.clock(), "OWNER")
        event["actor"]["principal_ref"] = "forged"
        with self.assertRaises(Denied):
            fixture.store.append([event])

    def test_16_hard_stops_and_no_live_authority(self):
        """P12/P15: security stops and operational profile never degrade to local repair."""
        fixture = self.fixture
        for reason in ("AUTHENTICATION", "SECRETS", "AUTHORIZATION", "DESTRUCTIVE_OPERATION", "SCOPE_ESCAPE", "EVIDENCE_MISMATCH", "UNCLASSIFIABLE"):
            fixture.coordinator.emit("StopLatched", {"stop_id": identity(), "reason": reason, "evidence": fixture.coordinator.proof})
        self.assertFalse(fixture.coordinator.rights()["verify"])
        self.assertEqual(len(fixture.store.state["stops"]), 7)
        self.assertFalse(fixture.coordinator.rights()["pass"])

    def test_17_strict_json(self):
        """Reject duplicate keys, unsafe numbers and invalid Unicode before normalization."""
        for raw in ('{"id":1,"id":2}', '{"value":1.25}', '{"value":9007199254740992}', '"\\ud800"'):
            with self.assertRaises((Denied, UnicodeError)):
                parse_json(raw)
        self.assertEqual(canonical({"😀": 1, "\ue000": 2}), '{"😀":1,"\ue000":2}')

    def test_18_harmless_windows_process(self):
        """M4: confirm local child execution and exit without claiming guardian identity proof."""
        result = harmless_child()
        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(result["stdout"], "lifecycle-v2-stub")
        self.assertTrue(result["stderr_empty"])
        self.assertFalse(result["live_identity_or_group_proof"])


    def test_19_unicode_controls_and_normalization_collisions(self):
        """Preserve opaque Unicode/control IDs and NFC/NFKC collisions across replay."""
        fixture = self.fixture
        self.assertEqual(VALIDATOR.metadata["input_codepage"], 65001)
        self.assertEqual(VALIDATOR.metadata["output_codepage"], 65001)
        self.assertEqual(unicodedata.normalize("NFC", "é"), "é")
        self.assertEqual(unicodedata.normalize("NFKC", "Ａ"), "A")
        identifiers = ["__proto__", "constructor", "prototype", "é", "é", "A", "Ａ",
                       "\x00", "\t", "\n", "\x1f", "😀", "\ufeff"]
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.complete_job(job, "NEEDS_CHANGES", [finding(value, value) for value in identifiers])
        self.assertEqual(len(fixture.store.state["issues"]), len(identifiers))
        observed = {parse_json(alias)["external_id"] for alias in fixture.store.state["aliases"]}
        self.assertEqual(observed, set(identifiers))
        fixture.restart()
        self.assertEqual(len(fixture.store.state["issues"]), len(identifiers))
        self.assertEqual({parse_json(alias)["external_id"] for alias in fixture.store.state["aliases"]}, set(identifiers))
        self.assertFalse(fixture.coordinator.rights()["can_pass"])

    def test_20_duplicate_alias_retains_raw_and_unresolved_debt(self):
        """Reject exact duplicate IDs atomically and retain their raw final after resume."""
        fixture = self.fixture
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        findings = [finding("duplicate", "one"), finding("duplicate", "two")]
        receipt = fixture.coordinator.complete_job(job, "NEEDS_CHANGES", findings)
        saved = fixture.store.state["receipts"][receipt]
        self.assertEqual(len(parse_json(fixture.store.get_blob(saved["final_artifact"]))["findings"]), 2)
        self.assertTrue(saved["rejected"])
        self.assertFalse(saved["applied"])
        self.assertEqual(fixture.store.state["issues"], {})
        fixture.coordinator.approve(3000000)
        fixture.restart()
        self.assertIn("UNCLASSIFIABLE", fixture.store.state["stops"].values())
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        self.assertFalse(fixture.coordinator.rights()["repair"])
        self.assertTrue(fixture.store.state["receipts"][receipt]["rejected"])

    def test_21_invalid_ids_and_duplicate_json_are_not_discarded(self):
        """Malformed ID types, empty IDs and duplicate JSON keys preserve original bytes."""
        for invalid in ([], "", "duplicate-json"):
            with self.subTest(invalid=invalid):
                fixture = Fixture()
                self.addCleanup(fixture.close)
                fixture.verify()
                job = fixture.coordinator.review_round()[0]
                fixture.coordinator.launch(job)
                fixture.coordinator.exit(job)
                result = fixture.coordinator.result(job, "NEEDS_CHANGES", [finding()])
                if invalid != "duplicate-json":
                    result["findings"][0]["alias"]["external_id"] = invalid
                raw = canonical(result).encode()
                if invalid == "duplicate-json":
                    raw = raw.replace(b'"external_id":"finding-A"', b'"external_id":"finding-A","external_id":"other"')
                receipt = fixture.coordinator.collect(job, raw)
                fixture.coordinator.apply_receipt(receipt)
                saved = fixture.store.state["receipts"][receipt]
                self.assertEqual(fixture.store.get_blob(saved["final_artifact"]), raw)
                self.assertTrue(saved["rejected"])
                self.assertFalse(saved["applied"])
                self.assertIn("UNCLASSIFIABLE", fixture.store.state["stops"].values())
                self.assertFalse(fixture.coordinator.rights()["can_pass"])

    def test_22_conflicting_alias_anchor_is_unclassified(self):
        """Conflicting existing identities cannot merge issues or erase their evidence."""
        fixture = self.fixture
        fixture.verify()
        job = fixture.coordinator.review_round()[0]
        fixture.coordinator.complete_job(job, "NEEDS_CHANGES", [finding("A", "anchor-A"), finding("B", "anchor-B")])
        fixture.repair()
        fixture.verify()
        before = copy.deepcopy(fixture.store.state["issues"])
        job = fixture.coordinator.review_round()[0]
        receipt = fixture.coordinator.complete_job(job, "NEEDS_CHANGES", [finding("A", "anchor-B")])
        self.assertEqual(fixture.store.state["issues"], before)
        self.assertTrue(fixture.store.state["receipts"][receipt]["rejected"])
        self.assertIn("UNCLASSIFIABLE", fixture.store.state["stops"].values())
        self.assertFalse(fixture.coordinator.rights()["can_pass"])


    def crash_recovery(self, mode):
        """Verify T2 atomicity and charge idempotency after a real child process exit."""
        fixture = self.fixture
        fixture.verify(False)
        fixture.repair("repair-before-crash")
        job = fixture.coordinator.verification()
        fixture.coordinator.launch(job)
        fixture.coordinator.exit(job)
        receipt = fixture.coordinator.collect(job, canonical(fixture.coordinator.result(job, "NEEDS_CHANGES")).encode())
        issue_id = next(iter(fixture.store.state["issues"]))
        context = {"contract": fixture.contract, "principals": fixture.principals,
                   "clock": fixture.clock(), "receipt_id": receipt}
        context_path = fixture.directory / "crash-context.json"
        context_path.write_text(json.dumps(context), encoding="utf-8")
        fixture.store.close()
        fixture.store = None
        command = [sys.executable, "-u", str(ROOT / "crash_probe.py"), str(context_path), mode]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
        (fixture.directory / "crash.stdout.txt").write_bytes(result.stdout)
        (fixture.directory / "crash.stderr.txt").write_bytes(result.stderr)
        (fixture.directory / "crash-result.json").write_text(json.dumps({"command": command,
            "expected_exit": 91 if mode == "before" else 92, "exit_code": result.returncode}), encoding="utf-8")
        fixture.store = EventStore(fixture.directory, fixture.contract, VALIDATOR, fixture.principals)
        fixture.coordinator = Coordinator(fixture.store, fixture.clock)
        fixture.coordinator.recover()
        self.assertEqual(result.returncode, 91 if mode == "before" else 92)
        self.assertEqual(fixture.store.state["receipts"][receipt]["applied"], mode == "after")
        self.assertEqual(fixture.store.state["issues"][issue_id]["failed"], 1 if mode == "after" else 0)
        self.assertEqual(len(fixture.store.state["charges"]), 1 if mode == "after" else 0)
        fixture.coordinator.apply_receipt(receipt)
        fixture.coordinator.apply_receipt(receipt)
        self.assertEqual(fixture.store.state["issues"][issue_id]["failed"], 1)
        self.assertEqual(len(fixture.store.state["charges"]), 1)
        fixture.coordinator.approve(3000000)
        fixture.restart()
        self.assertEqual(fixture.store.state["repair_spent"], 1)
        self.assertEqual(fixture.store.state["issues"][issue_id]["failed"], 1)
        self.assertEqual(len(fixture.store.state["charges"]), 1)

    def test_23_process_crash_before_t2_commit(self):
        """A real precommit crash leaves raw receipt debt and no partial failure charge."""
        self.crash_recovery("before")

    def test_24_process_crash_after_t2_commit(self):
        """A real postcommit crash preserves all effects once despite lost acknowledgement."""
        self.crash_recovery("after")

    def test_25_lifetime_failure_budget_survives_restarts(self):
        """Repeated failed repairs retain issue identity and cumulative caps across resumes."""
        fixture = self.fixture
        fixture.verify(False)
        issue_id = next(iter(fixture.store.state["issues"]))
        for number in (1, 2):
            fixture.repair("failed-repair-" + str(number))
            fixture.verify(False)
            self.assertEqual(fixture.store.state["issues"][issue_id]["failed"], number)
            fixture.coordinator.approve(3000000 + number)
            fixture.restart()
            self.assertEqual(fixture.store.state["repair_spent"], number)
            self.assertEqual(fixture.store.state["issues"][issue_id]["failed"], number)
            self.assertEqual(len(fixture.store.state["charges"]), number)
        self.assertFalse(fixture.coordinator.rights()["repair"])
        self.assertFalse(fixture.coordinator.rights()["can_pass"])
        with self.assertRaises(Denied):
            fixture.coordinator.begin(repair=True)


def sample(schema, root):
    """Generate structural witnesses from the approved schema, not expected reducer results."""
    if "$ref" in schema:
        return sample(root["$defs"][schema["$ref"].split("/")[-1]], root)
    if "const" in schema:
        return schema["const"]
    if "enum" in schema:
        return schema["enum"][0]
    if "anyOf" in schema or "oneOf" in schema:
        return sample((schema.get("anyOf") or schema["oneOf"])[0], root)
    kind = schema.get("type")
    if kind == "object":
        return {key: sample(schema["properties"][key], root) for key in schema["required"]}
    if kind == "array":
        return [sample(schema["items"], root) for _ in range(schema.get("minItems", 0))]
    if kind == "integer":
        return schema.get("minimum", 0)
    if kind == "null":
        return None
    if kind == "string":
        if schema.get("format") == "date-time":
            return "2026-11-12T00:00:00Z"
        if schema.get("pattern", "").startswith("^[0-9a-f]{8}"):
            return identity()
        if schema.get("pattern"):
            return "0" * 64
        return "fixture"
    raise AssertionError("No structural fixture for schema keyword")


def run():
    """Run fail-fast once and persist observed results; never auto-repair a failure."""
    global VALIDATOR, RUN_ROOT
    RUN_ROOT = ROOT / "results" / ("run-" + identity())
    RUN_ROOT.mkdir()
    report = {"execution_scope": "ISOLATED_SIMULATION_ONLY", "legacy75": "NOT_FULLY_TRANSLATED",
              "legacy13": "NOT_FULLY_TRANSLATED", "trace18": "PARTIAL", "tests": [], "external_review": "NOT_RUN"}
    try:
        VALIDATOR = SchemaValidator()
        report["schema_engine"] = VALIDATOR.metadata
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(V2Tests)
        # Run the diagnosed boundary first without removing any existing integration cases.
        priority = {name: index for index, name in enumerate((
            "test_00_explicit_metaschema_rejects_invalid_schema", "test_01_full_schema_24_event_payloads",
            "test_09_special_finding_identifiers", "test_19_unicode_controls_and_normalization_collisions",
            "test_20_duplicate_alias_retains_raw_and_unresolved_debt",
            "test_21_invalid_ids_and_duplicate_json_are_not_discarded",
            "test_22_conflicting_alias_anchor_is_unclassified"))}
        suite = unittest.TestSuite(sorted(suite, key=lambda test: priority.get(test._testMethodName, len(priority))))
        runner = unittest.TextTestRunner(verbosity=2, failfast=True)
        result = runner.run(suite)
        report.update(tests_run=result.testsRun, failures=len(result.failures), errors=len(result.errors),
                      success=result.wasSuccessful(), diagnostics=[text for _, text in result.failures + result.errors])
    except Exception as error:
        report.update(success=False, initialization_error=type(error).__name__ + ": " + str(error))
    finally:
        if VALIDATOR is not None:
            VALIDATOR.close()
        (RUN_ROOT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"success": report["success"], "report": str(RUN_ROOT / "report.json")}, ensure_ascii=False))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(run())
