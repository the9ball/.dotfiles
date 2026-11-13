"""Expected-outcome tests for the isolated cooperative owner-grant profile."""

import copy
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from common import Denied, MAX_INTEGER, StorageFailure, artifact, canonical, digest, identity, parse_json
from coordinator import Coordinator
from mock_owner_grants import MockOwnerProfile, VERSION, intent_sha256
from store import EventStore

VALIDATOR = None
RUN_ROOT = None


class GrantFixture:
    """Own an isolated database, immutable authority inputs and controllable observations."""

    def __init__(self, directory=None, bootstrap=True):
        """Build fixture-only sessions and grants before opening an empty protected store."""
        self.directory = Path(directory or tempfile.mkdtemp(prefix="owner-", dir=RUN_ROOT))
        self.now, self.boot = 100, "fixture-boot"
        self.clock_calls, self.target_calls = 0, 0
        self.proof = artifact(b'{"simulation_only":true}')
        self.contract = {"gate_id": identity(), "simulation_only": True, "required_checks": ["unit"],
                         "required_roles": ["advisor"], "user_review_required": False}
        self.principals = {role: {"principal_ref": role.lower() + "-mock", "proof": self.proof} for role in ("OWNER", "BROKER")}
        self.session = {"session_ref": "session-a", "requester_ref": "requester-a", "executor_ref": "executor-a",
                        "actor_ref": "owner-mock", "allowed_owner_refs": ["owner-mock"],
                        "operations": ["GateOpened", "ApprovalRecorded", "StopResolved", "JobRetirementAccepted"]}
        self.other_session = {**self.session, "session_ref": "session-b"}
        self.issuers = {"issuer-a": {"allowed_owner_refs": ["owner-mock"], "operations": self.session["operations"][:]}}
        manifest = artifact(canonical(self.contract).encode())
        self.open_draft = self.draft("GateOpened", {"owner_proof": self.proof, "scope_manifest": manifest, "review_contract": manifest})
        self.approval_draft = self.draft("ApprovalRecorded", {"interval_id": identity(), "owner_proof": self.proof,
            "boot_id": self.boot, "deadline_uptime_ms": 900,
            "cumulative_caps": {"repair_cap": 3, "same_issue_failure_cap": 2, "review_round_cap": 4}, "external_grants": self.proof})
        self.resolve_draft = self.draft("StopResolved", {"stop_id": "00000000-0000-4000-8000-000000000010", "owner_proof": self.proof, "resolution_proof": self.proof})
        self.grants = {name: self.grant(name, event) for name, event in (
            ("open", self.open_draft), ("approval", self.approval_draft), ("resolve", self.resolve_draft))}
        self.observation = {"target": self.contract["gate_id"], "scope_sha256": digest(canonical(self.contract).encode()), "revision": None}
        self.handle, self.other_handle = object(), object()
        self.store = None
        if bootstrap:
            self.start()

    def draft(self, kind, payload, role="OWNER"):
        """Build complete schema-shaped original drafts without store-owned normalization."""
        principal = self.principals[role]
        return {"schema_version": 2, "event_id": identity(), "gate_id": self.contract["gate_id"], "command_id": identity(),
                "sequence": 1, "transaction_id": identity(), "transaction_ordinal": 0,
                "writer_generation": self.store.state["writer_generation"] if getattr(self, "store", None) else 0,
                "previous_event_sha256": None, "event_sha256": "0" * 64, "revision": None,
                "clock": {"boot_id": self.boot, "uptime_ms": self.now, "observed_utc": "2026-11-13T00:00:00Z"},
                "actor": {"role": role, **principal}, "event_type": kind, "payload": copy.deepcopy(payload)}

    def grant(self, grant_id, event):
        """Bind one fixed full intent while allowing two distinct command consumptions."""
        target = {"gate_id": event["gate_id"], "stop_id": event["payload"]["stop_id"]} if event["event_type"] == "StopResolved" else event["gate_id"]
        return {"profile_version": VERSION, "simulation_only": True, "grant_id": grant_id, "issuer_ref": "issuer-a",
                "requester_ref": "requester-a", "owner_ref": "owner-mock", "executor_ref": "executor-a",
                "gate_id": event["gate_id"], "operation": event["event_type"], "target": target,
                "scope_sha256": digest(canonical(self.contract).encode()), "revision": None,
                "intent_sha256": intent_sha256(event), "boot_id": self.boot,
                "not_before_uptime_ms": 50, "deadline_uptime_ms": 1000, "max_uses": 2}

    def clock(self):
        """Count live reads to prove ACK-only paths never consult current observations."""
        self.clock_calls += 1
        return {"boot_id": self.boot, "uptime_ms": self.now, "observed_utc": "2026-11-13T00:00:00Z"}

    def target(self):
        """Return a detached owned fixture target observation."""
        self.target_calls += 1
        return copy.deepcopy(self.observation)

    def profile(self, clock=None, target=None):
        """Rebuild the same pinned registry with fresh bootstrap handle objects when requested."""
        return MockOwnerProfile(self.issuers, self.grants,
            [(self.handle, self.session), (self.other_handle, self.other_session)], clock or self.clock, target or self.target)

    def start(self, profile=None):
        """Open a newly created or exact-profile existing fixture database."""
        self.store = EventStore(self.directory, self.contract, VALIDATOR, self.principals, mock_profile=profile or self.profile())
        return self.store

    def open(self):
        """Commit only the gate owner event; grants do not synthesize approval effects."""
        return self.store.append([self.open_draft], "00000000-0000-4000-8000-000000000001", authorization=("open", self.handle))

    def approve(self, command="00000000-0000-4000-8000-000000000002", fault=None, event=None):
        """Submit the fixed owner approval through the direct store authorization boundary."""
        return self.store.append([event or self.approval_draft], command, fault=fault, authorization=("approval", self.handle))

    def uses(self, grant_id="approval"):
        """Read the durable append-only use count for an expected fixture grant."""
        return self.store.connection.execute("SELECT COUNT(*) FROM owner_uses WHERE grant_id=?", (grant_id,)).fetchone()[0]

    def close(self):
        """Release only the database and lock owned by this fixture."""
        if self.store is not None:
            self.store.close()
            self.store = None

    def restart(self):
        """Reissue handles in trusted bootstrap and reconcile using existing broker recovery."""
        self.close()
        self.handle, self.other_handle = object(), object()
        self.start()
        Coordinator(self.store, self.clock).recover()


class SQLFault:
    """Forward one owned SQLite connection while injecting precise storage failures."""

    def __init__(self, connection, statement, rollback=False, crash=False, before_exit=None):
        """Configure one statement prefix plus an optional failing rollback or owned-child exit."""
        self.connection, self.statement = connection, statement
        self.rollback, self.crash = rollback, crash
        self.before_exit = before_exit

    @property
    def in_transaction(self):
        """Expose the actual connection transaction state to error cleanup."""
        return self.connection.in_transaction

    def execute(self, sql, parameters=()):
        """Inject before a matching statement, or after durable COMMIT for crash evidence."""
        if sql.startswith(self.statement):
            if self.crash:
                if self.before_exit is not None:
                    self.before_exit()
                if sql == "COMMIT":
                    self.connection.execute(sql, parameters)
                os._exit(73)
            raise sqlite3.OperationalError("Owned injected database failure")
        if self.rollback and sql == "ROLLBACK":
            raise sqlite3.OperationalError("Owned injected rollback failure")
        return self.connection.execute(sql, parameters)

    def close(self):
        """Close the underlying owned connection without changing host state."""
        return self.connection.close()


class MockOwnerGrantTests(unittest.TestCase):
    """Exercise independent observable safety outcomes for owner admissions and replay."""

    def setUp(self):
        """Allocate one isolated protected fixture and retain evidence until runner cleanup."""
        self.fixture = GrantFixture()
        self.addCleanup(self.fixture.close)
        self.fixture.open()

    def test_admission_normalizes_clock_and_replay_preserves_use(self):
        """A valid direct append records final fixture time and exactly one durable consumption."""
        fixture = self.fixture
        fixture.now = 200
        result = fixture.approve()
        self.assertEqual(result.status, "COMMITTED_ADMISSION")
        self.assertFalse(result.execution_permitted)
        self.assertEqual(fixture.uses(), 1)
        event = parse_json(fixture.store.connection.execute("SELECT body FROM events ORDER BY sequence DESC LIMIT 1").fetchone()[0])
        self.assertEqual(event["clock"]["uptime_ms"], 200)
        self.assertEqual(fixture.approval_draft["clock"]["uptime_ms"], 100)
        self.assertEqual(fixture.store.replay(), fixture.store.state)
        fixture.restart()
        self.assertEqual(fixture.uses(), 1)

    def test_expired_exact_retry_is_ack_only_without_live_readers(self):
        """Exact committed retries survive expiry without reads or a second consumption."""
        fixture = self.fixture
        admitted = fixture.approve()
        fixture.now = 1000
        counts = fixture.clock_calls, fixture.target_calls
        acknowledgement = fixture.approve()
        self.assertEqual(acknowledgement.status, "COMMITTED_ACK_ONLY")
        self.assertEqual(acknowledgement.event_ids, admitted.event_ids)
        self.assertFalse(acknowledgement.execution_permitted)
        self.assertEqual((fixture.clock_calls, fixture.target_calls), counts)
        self.assertEqual(fixture.uses(), 1)

    def test_altered_retry_and_other_session_are_rejected(self):
        """Original envelopes and stable session context remain part of retry identity."""
        fixture = self.fixture
        fixture.approve()
        for field in ("event_id", "command_id", "transaction_id", "event_sha256", "clock", "payload"):
            event = copy.deepcopy(fixture.approval_draft)
            if field == "clock":
                event[field]["uptime_ms"] += 1
            elif field == "payload":
                event[field]["cumulative_caps"]["repair_cap"] += 1
            else:
                event[field] = identity()
            with self.subTest(field=field), self.assertRaises(Denied):
                fixture.approve(event=event)
        with self.assertRaises(Denied):
            fixture.store.append([fixture.approval_draft], "00000000-0000-4000-8000-000000000002", authorization=("approval", fixture.other_handle))
        self.assertEqual(fixture.uses(), 1)

    def test_fabricated_handle_missing_authorization_and_mixed_batches(self):
        """Direct store access cannot bypass handle membership or isolated owner batching."""
        fixture = self.fixture
        for authorization in (None, ("approval", object()), ("approval", {"session_ref": "session-a"}),
                              ("unknown", fixture.handle), {"grant_id": "approval", "session_ref": "session-a"}):
            with self.subTest(authorization=type(authorization).__name__), self.assertRaises(Denied):
                fixture.store.append([fixture.approval_draft], authorization=authorization)
        broker = fixture.draft("StopLatched", {"stop_id": "00000000-0000-4000-8000-000000000011", "reason": "DEADLINE", "evidence": fixture.proof}, "BROKER")
        for drafts in ([fixture.approval_draft, broker], [fixture.approval_draft, fixture.approval_draft]):
            with self.assertRaises(Denied):
                fixture.store.append(drafts, authorization=("approval", fixture.handle))
        with self.assertRaises(Denied):
            fixture.store.append([broker], authorization=("approval", fixture.handle))
        self.assertEqual(fixture.uses(), 0)
        self.assertTrue(fixture.store.healthy)

    def test_registry_input_mutation_does_not_change_authority(self):
        """Nested caller-owned registries cannot replace constructor-frozen authority."""
        fixture = self.fixture
        fixture.grants["approval"]["max_uses"] = 100
        fixture.session["requester_ref"] = "substituted"
        fixture.issuers["issuer-a"]["allowed_owner_refs"].clear()
        fixture.approve()
        second = copy.deepcopy(fixture.approval_draft)
        second["event_id"] = identity()
        fixture.approve("00000000-0000-4000-8000-000000000003", event=second)
        third = copy.deepcopy(second)
        third["event_id"] = identity()
        with self.assertRaises(Denied):
            fixture.approve("00000000-0000-4000-8000-000000000004", event=third)
        self.assertEqual(fixture.uses(), 2)

    def test_every_intent_and_observation_binding(self):
        """Identity, gate, operation, target, scope, revision and complete payload substitutions fail."""
        fixture = self.fixture
        for field in ("target", "scope_sha256", "revision"):
            original = copy.deepcopy(fixture.observation)
            fixture.observation[field] = "changed" if field != "revision" else {"changed": True}
            with self.subTest(observation=field), self.assertRaises(Denied):
                fixture.approve()
            fixture.observation = original
        for field in ("gate_id", "actor", "revision", "event_type", "payload"):
            event = copy.deepcopy(fixture.approval_draft)
            if field == "actor":
                event[field]["principal_ref"] = "other-owner"
            elif field == "payload":
                event[field]["cumulative_caps"]["repair_cap"] = 99
            elif field == "revision":
                event[field] = {"changed": True}
            else:
                event[field] = "other"
            with self.subTest(event=field), self.assertRaises(Denied):
                fixture.approve(event=event)
        self.assertEqual(fixture.uses(), 0)

    def test_all_registry_identity_substitutions(self):
        """Pinned issuer, requester, executor and session owner/operation bindings are independent."""
        for field in ("requester_ref", "executor_ref", "owner_ref", "issuer_ref", "gate_id", "operation", "boot_id", "intent_sha256"):
            fixture = GrantFixture(bootstrap=False)
            self.addCleanup(fixture.close)
            fixture.grants["approval"][field] = "other" if field != "intent_sha256" else "0" * 64
            with self.subTest(field=field):
                try:
                    fixture.start()
                except Denied:
                    continue
                fixture.open()
                with self.assertRaises(Denied):
                    fixture.approve()
        for field in ("actor_ref", "allowed_owner_refs", "operations"):
            fixture = GrantFixture(bootstrap=False)
            self.addCleanup(fixture.close)
            fixture.session[field] = "other" if field == "actor_ref" else (["other-owner"] if field == "allowed_owner_refs" else ["GateOpened"])
            fixture.start()
            with self.subTest(session=field), self.assertRaises(Denied):
                fixture.approve()

    def test_closed_registry_shapes_and_strict_integer_types(self):
        """Unknown fields, booleans, unsafe integers and invalid intervals cannot bootstrap."""
        for field, value in (("max_uses", True), ("max_uses", 0), ("max_uses", MAX_INTEGER + 1),
                             ("not_before_uptime_ms", True), ("not_before_uptime_ms", 1000),
                             ("deadline_uptime_ms", -1), ("deadline_uptime_ms", MAX_INTEGER + 1),
                             ("unexpected", 1), ("simulation_only", False), ("scope_sha256", "invalid")):
            fixture = GrantFixture(bootstrap=False)
            with self.subTest(field=field, value=value), self.assertRaises(Denied):
                fixture.grants["approval"][field] = value
                fixture.profile()

    def test_deadline_not_before_boot_and_clock_types(self):
        """Boundary expiry, early admission, boot changes, reversal and unsafe clock values deny use."""
        fixture = self.fixture
        for value in (49, 99, 1000, True, MAX_INTEGER + 1):
            fixture.now = value
            with self.subTest(now=value), self.assertRaises(Denied):
                fixture.approve()
            self.assertTrue(fixture.store.healthy)
        fixture.now = 100
        fixture.boot = "other-boot"
        with self.assertRaises(Denied):
            fixture.approve()
        self.assertEqual(fixture.uses(), 0)

    def test_target_and_clock_rechecked_before_insert(self):
        """A target change or expiry observed between admission reads consumes nothing."""
        fixture = self.fixture
        fixture.close()
        calls = []
        def changing_target():
            """Substitute only the second target observation in this owned fixture."""
            calls.append(True)
            result = fixture.target()
            if len(calls) == 2:
                result["scope_sha256"] = "0" * 64
            return result
        fixture.start(fixture.profile(target=changing_target))
        Coordinator(fixture.store, fixture.clock).recover()
        fixture.approval_draft["writer_generation"] = fixture.store.state["writer_generation"]
        with self.assertRaises(Denied):
            fixture.approve()
        self.assertEqual(fixture.uses(), 0)
        fixture.close()
        clock_calls = []
        expiry_enabled = [False]
        def expiring_clock():
            """Expire the second clock observation while preserving the first valid sample."""
            clock_calls.append(True)
            result = fixture.clock()
            if expiry_enabled[0] and len(clock_calls) == 2:
                result["uptime_ms"] = 1000
            return result
        fixture.start(fixture.profile(clock=expiring_clock))
        Coordinator(fixture.store, fixture.clock).recover()
        fixture.approval_draft["writer_generation"] = fixture.store.state["writer_generation"]
        clock_calls.clear()
        expiry_enabled[0] = True
        with self.assertRaises(Denied):
            fixture.approve()
        self.assertEqual(fixture.uses(), 0)

    def test_owned_file_capture_rejects_changes_before_and_during_capture(self):
        """Unchanged capture_kernel verification rejects actual owned-file drift before admission."""
        from capture_kernel import capture_protected, file_mode, frame, verify_pair
        for phase in ("before", "during"):
            fixture = GrantFixture(bootstrap=False)
            self.addCleanup(fixture.close)
            source = fixture.directory / "scope.txt"
            source.write_bytes(b"owned scope\n")
            existing = [{"path": "scope.txt", "sha256": digest(source.read_bytes()), "mode": file_mode(source, "100644")}]
            metadata = {"branch": b"fixture\n", "head": ("a" * 40 + "\n").encode(), "index": b"fixture-index",
                        "status": b"fixture-status", "candidate": b"fixture-candidate", "entries": b"fixture-entries", "ignored": b"fixture-ignored"}
            baseline = {"branch": "fixture", "head": "a" * 40, "index": digest(metadata["index"]), "status": digest(metadata["status"])}
            mutation_enabled = [False]
            def snapshot():
                """Read only the single source file owned by this capture fixture."""
                return frame(metadata, capture_protected(fixture.directory, existing, lambda: ["scope.txt"], lambda name: "100644"))
            def captured_target():
                """Verify both snapshots using the unchanged capture kernel before supplying identity."""
                before = snapshot()
                if mutation_enabled[0] and phase == "during":
                    source.write_bytes(b"changed during capture\n")
                after = snapshot()
                verify_pair(before, after, baseline, existing)
                return fixture.target()
            fixture.start(fixture.profile(target=captured_target))
            fixture.open()
            mutation_enabled[0] = True
            if phase == "before":
                source.write_bytes(b"changed before capture\n")
            with self.subTest(phase=phase), self.assertRaises(Denied):
                fixture.approve()
            self.assertEqual(fixture.uses(), 0)
    def test_distinct_command_consumes_budget_and_reopen_does_not_reset_it(self):
        """Grant accounting counts committed commands independently of identical intent."""
        fixture = self.fixture
        fixture.approve()
        second = copy.deepcopy(fixture.approval_draft)
        second["event_id"] = identity()
        fixture.approve("00000000-0000-4000-8000-000000000003", event=second)
        fixture.restart()
        third = copy.deepcopy(second)
        third["event_id"] = identity()
        third["writer_generation"] = fixture.store.state["writer_generation"]
        with self.assertRaises(Denied):
            fixture.approve("00000000-0000-4000-8000-000000000004", event=third)
        self.assertEqual(fixture.uses(), 2)

    def test_ack_loss_closes_until_reopen_and_then_returns_ack_only(self):
        """Durable consumption survives an uncertain COMMIT without granting automatic execution."""
        fixture = self.fixture
        with self.assertRaises(StorageFailure):
            fixture.approve(fault="after_commit")
        self.assertFalse(fixture.store.healthy)
        with self.assertRaises(Denied):
            fixture.approve()
        fixture.restart()
        self.assertEqual(fixture.uses(), 1)
        fixture.now = 1000
        before = fixture.clock_calls, fixture.target_calls
        result = fixture.approve()
        self.assertEqual(result.status, "COMMITTED_ACK_ONLY")
        self.assertEqual((fixture.clock_calls, fixture.target_calls), before)

    def test_transaction_failure_consumes_nothing_and_requires_reopen(self):
        """A precommit storage failure rolls back events, requests and uses together."""
        fixture = self.fixture
        for fault in ("after_events", "before_commit"):
            with self.subTest(fault=fault), self.assertRaises(StorageFailure):
                fixture.approve(fault=fault)
            self.assertFalse(fixture.store.healthy)
            fixture.restart()
            self.assertEqual(fixture.uses(), 0)
            fixture.approval_draft["writer_generation"] = fixture.store.state["writer_generation"]

    def test_read_begin_fence_and_commit_database_errors_close_before_cleanup(self):
        """Every injected database boundary fails without an ACK and preserves fail-closed health."""
        fixture = self.fixture
        for statement in ("BEGIN IMMEDIATE", "SELECT value FROM runtime WHERE key='fence'", "SELECT command_id,fingerprint", "COMMIT"):
            real = fixture.store.connection
            fixture.store.connection = SQLFault(real, statement)
            with self.subTest(statement=statement), self.assertRaises(StorageFailure):
                fixture.approve()
            self.assertFalse(fixture.store.healthy)
            fixture.store.connection = real
            fixture.restart()
            fixture.approval_draft["writer_generation"] = fixture.store.state["writer_generation"]
            self.assertEqual(fixture.uses(), 0)

    def test_rollback_failure_and_ordinary_rejection_reuse(self):
        """Only a successful rollback permits reuse after ordinary policy rejection."""
        fixture = self.fixture
        fixture.now = 1000
        with self.assertRaises(Denied):
            fixture.approve()
        self.assertTrue(fixture.store.healthy)
        fixture.now = 100
        real = fixture.store.connection
        fixture.store.connection = SQLFault(real, "NEVER", rollback=True)
        fixture.now = 1000
        with self.assertRaises(StorageFailure):
            fixture.approve()
        self.assertFalse(fixture.store.healthy)
        self.assertTrue(fixture.store.cleanup_failures)
        fixture.store.connection = real

    def test_live_writer_lock_and_second_connection_fence(self):
        """A second store cannot steal ownership and a changed durable fence blocks admission."""
        fixture = self.fixture
        with self.assertRaises(Denied):
            EventStore(fixture.directory, fixture.contract, VALIDATOR, fixture.principals, mock_profile=fixture.profile())
        connection = sqlite3.connect(fixture.directory / "events.sqlite", isolation_level=None)
        self.addCleanup(connection.close)
        connection.execute("INSERT OR REPLACE INTO runtime VALUES ('fence','999')")
        with self.assertRaises(Denied):
            fixture.approve()
        self.assertEqual(fixture.uses(), 0)

    def test_sidecar_tables_are_immutable(self):
        """SQLite update/delete triggers protect policy, request and use evidence."""
        fixture = self.fixture
        fixture.approve()
        for table in ("owner_policy", "owner_requests", "owner_uses"):
            for sql in ("UPDATE " + table + " SET body=body", "DELETE FROM " + table):
                with self.subTest(sql=sql), self.assertRaises(sqlite3.DatabaseError):
                    fixture.store.connection.execute(sql)
        self.assertEqual(fixture.store.replay(), fixture.store.state)

    def test_profile_downgrade_registry_change_and_legacy_migration_are_forbidden(self):
        """Protected histories require the exact bootstrap policy and legacy populations stay unprotected."""
        fixture = self.fixture
        fixture.close()
        with self.assertRaises(Denied):
            EventStore(fixture.directory, fixture.contract, VALIDATOR, fixture.principals)
        fixture.grants["approval"]["max_uses"] = 3
        with self.assertRaises(Denied):
            fixture.start()
        legacy = GrantFixture(bootstrap=False)
        self.addCleanup(legacy.close)
        legacy.store = EventStore(legacy.directory, legacy.contract, VALIDATOR, legacy.principals)
        result = legacy.store.append([legacy.open_draft], "00000000-0000-4000-8000-000000000006")
        self.assertIsInstance(result, list)
        legacy.close()
        with self.assertRaises(Denied):
            legacy.start()

    def test_broker_request_dedup_and_no_owner_use(self):
        """Broker commands retain canonical originals without requiring or consuming owner grants."""
        fixture = self.fixture
        draft = fixture.draft("StopLatched", {"stop_id": "00000000-0000-4000-8000-000000000011", "reason": "DEADLINE", "evidence": fixture.proof}, "BROKER")
        result = fixture.store.append([draft], "00000000-0000-4000-8000-000000000005")
        self.assertEqual(result.status, "COMMITTED_ADMISSION")
        fixture.now = 1000
        before = fixture.clock_calls, fixture.target_calls
        retry = fixture.store.append([draft], "00000000-0000-4000-8000-000000000005")
        self.assertEqual(retry.status, "COMMITTED_ACK_ONLY")
        self.assertEqual((fixture.clock_calls, fixture.target_calls), before)
        self.assertEqual(fixture.uses(), 0)
        request = parse_json(fixture.store.connection.execute("SELECT body FROM owner_requests WHERE command_id='00000000-0000-4000-8000-000000000005'").fetchone()[0])
        self.assertIsNone(request["request"]["authorization"])

    def test_replay_rejects_orphan_rows_and_fingerprint_corruption(self):
        """Reopen rejects each independently corrupted immutable evidence relationship."""
        for corruption in ("request", "use", "command", "event", "fingerprint", "transaction"):
            fixture = GrantFixture()
            self.addCleanup(fixture.close)
            fixture.open()
            fixture.approve()
            fixture.close()
            connection = sqlite3.connect(fixture.directory / "events.sqlite", isolation_level=None)
            try:
                for table in ("events", "commands", "owner_requests", "owner_uses"):
                    for operation in ("update", "delete"):
                        connection.execute("DROP TRIGGER IF EXISTS " + table + "_no_" + operation)
                if corruption == "request":
                    connection.execute("DELETE FROM owner_requests WHERE command_id='00000000-0000-4000-8000-000000000002'")
                elif corruption == "use":
                    connection.execute("DELETE FROM owner_uses WHERE grant_id='approval'")
                elif corruption == "command":
                    connection.execute("INSERT INTO commands VALUES ('orphan',?, '[]')", ("0" * 64,))
                elif corruption == "event":
                    connection.execute("DELETE FROM events WHERE command_id='00000000-0000-4000-8000-000000000002'")
                elif corruption == "fingerprint":
                    connection.execute("UPDATE commands SET fingerprint=? WHERE command_id='00000000-0000-4000-8000-000000000002'", ("0" * 64,))
                else:
                    row = connection.execute("SELECT body FROM owner_requests WHERE command_id='00000000-0000-4000-8000-000000000002'").fetchone()
                    record = parse_json(row[0])
                    record["transaction_id"] = "changed-transaction"
                    connection.execute("UPDATE owner_requests SET body=? WHERE command_id='00000000-0000-4000-8000-000000000002'", (canonical(record),))
            finally:
                connection.close()
            with self.subTest(corruption=corruption), self.assertRaises(Denied):
                fixture.start()

    def test_owned_child_crash_before_and_after_commit(self):
        """An owned process exit preserves the all-or-nothing transaction boundary on reopen."""
        for point, expected in (("before", 0), ("after", 1)):
            fixture = GrantFixture()
            self.addCleanup(fixture.close)
            fixture.open()
            fixture.close()
            request = fixture.directory / "child-request.json"
            request.write_text(canonical({"contract": fixture.contract, "principals": fixture.principals,
                "issuers": fixture.issuers, "grants": fixture.grants, "session": fixture.session,
                "other_session": fixture.other_session, "approval": fixture.approval_draft,
                "observation": fixture.observation}), encoding="utf-8")
            completed = subprocess.run([sys.executable, "-B", str(Path(__file__).resolve()), "--crash", str(request), point],
                                       capture_output=True, timeout=30)
            (fixture.directory / (point + "-child.stderr.txt")).write_bytes(completed.stderr)
            self.assertEqual(completed.returncode, 73)
            fixture.start()
            self.assertEqual(fixture.uses(), expected)
            self.assertFalse(fixture.store.ready())


def crash_child(request_path, point):
    """Exit only this explicitly spawned fixture child at its owned transaction boundary."""
    from schema_worker_session import SchemaSession, pinned_command
    import hashlib
    import test_mock_owner_grants
    request_path = Path(request_path)
    data = parse_json(request_path.read_bytes())
    executable = Path(os.environ["LIFECYCLE_SCHEMA_PWSH"]).resolve(strict=True)
    command = pinned_command([str(executable), "-NoLogo", "-NoProfile", "-NonInteractive", "-File",
        str(Path(__file__).parent / "schema-worker.ps1"), "-SchemaPath", str(Path(__file__).parent.parent / "event-schema.schema.json")],
        executable, hashlib.sha256(executable.read_bytes()).hexdigest())
    worker = SchemaSession(command, request_path.parent)
    worker.start()
    test_mock_owner_grants.VALIDATOR = worker
    fixture = test_mock_owner_grants.GrantFixture(request_path.parent, bootstrap=False)
    for field in ("contract", "principals", "issuers", "grants", "session", "other_session", "observation"):
        setattr(fixture, field, data[field])
    fixture.approval_draft = data["approval"]
    fixture.start()
    Coordinator(fixture.store, fixture.clock).recover()
    fixture.approval_draft["writer_generation"] = fixture.store.state["writer_generation"]
    real = fixture.store.connection
    def stop_owned_worker():
        """Reap the owned schema subprocess before intentionally exiting this child."""
        report = worker.close()
        if report["errors"] or report["transport_failed"] or report["exit_code"] != 0:
            raise RuntimeError("Owned crash schema worker cleanup failed")
    fixture.store.connection = SQLFault(real, "INSERT INTO events" if point == "before" else "COMMIT",
                                        crash=True, before_exit=stop_owned_worker)
    fixture.approve()
    raise RuntimeError("Owned crash point was not reached")


if __name__ == "__main__" and len(sys.argv) == 4 and sys.argv[1] == "--crash":
    crash_child(sys.argv[2], sys.argv[3])
