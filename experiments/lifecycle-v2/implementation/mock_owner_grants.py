"""Pinned cooperative mock owner admissions; no real authentication or execution."""

import copy
import functools
import re
import sqlite3
from dataclasses import dataclass

from common import MAX_INTEGER, Denied, StorageFailure, canonical, digest, identity, parse_json
from reducer import OWNER_EVENTS, apply_event, require

VERSION = "mock-owner-grants-v1"
GRANT_FIELDS = set("profile_version simulation_only grant_id issuer_ref requester_ref owner_ref executor_ref gate_id operation target scope_sha256 revision intent_sha256 boot_id not_before_uptime_ms deadline_uptime_ms max_uses".split())
SESSION_FIELDS = set("session_ref requester_ref executor_ref actor_ref allowed_owner_refs operations".split())
DRAFT_FIELDS = set("schema_version event_id gate_id command_id sequence transaction_id transaction_ordinal writer_generation previous_event_sha256 event_sha256 revision clock actor event_type payload".split())
INTENT_FIELDS = ("schema_version", "gate_id", "revision", "actor", "event_type", "payload")


def encoded(value):
    """Detach strict canonical JSON as immutable UTF-8 bytes."""
    return canonical(value).encode("utf-8")


def integer(value):
    """Accept only nonnegative canonical-safe integers, excluding booleans."""
    return type(value) is int and 0 <= value <= MAX_INTEGER


def text(value):
    """Require a nonempty exact mock identifier."""
    require(type(value) is str and bool(value), "Invalid mock identifier")


def sha256(value):
    """Require a lowercase hexadecimal SHA256 identifier."""
    require(type(value) is str and re.fullmatch("[0-9a-f]{64}", value), "Invalid mock digest")


def intent_sha256(event):
    """Hash the fixed intent projection including every payload field."""
    require(set(event) == DRAFT_FIELDS, "Original draft field set differs")
    return digest(encoded({key: event[key] for key in INTENT_FIELDS}))


def event_target(event):
    """Derive the owner operation target from the actual event."""
    if event["event_type"] == "StopResolved":
        return {"gate_id": event["gate_id"], "stop_id": event["payload"]["stop_id"]}
    return event["gate_id"]


def clock_value(value):
    """Detach a closed, strictly typed mock clock observation."""
    require(type(value) is dict and set(value) == {"boot_id", "uptime_ms", "observed_utc"}, "Clock fields differ")
    text(value["boot_id"])
    text(value["observed_utc"])
    require(integer(value["uptime_ms"]), "Invalid clock uptime")
    return parse_json(encoded(value))


def guarded(function):
    """Close protected storage before cleanup and preserve the original storage error."""
    @functools.wraps(function)
    def call(store, *arguments, **keywords):
        """Guard every protected database read, write and rollback boundary."""
        if getattr(store, "mock_profile", None) is None:
            return function(store, *arguments, **keywords)
        require(store.healthy and not store.closed, "Store is fail-closed")
        try:
            return function(store, *arguments, **keywords)
        except (sqlite3.Error, OSError, StorageFailure) as error:
            store.healthy = False
            cleanup(store)
            raise StorageFailure("Protected ledger uncertain; no ACK") from error
        except Denied:
            if function.__name__ in {"replay", "finish_recovery", "get_blob"}:
                store.healthy = False
            try:
                if hasattr(store, "connection") and store.connection.in_transaction:
                    store.connection.execute("ROLLBACK")
            except (sqlite3.Error, OSError) as error:
                store.healthy = False
                cleanup(store)
                raise StorageFailure("Protected rejection rollback failed; no ACK") from error
            raise
    return call


def cleanup(store):
    """Attempt rollback without masking the original error or restoring health."""
    try:
        if hasattr(store, "connection") and store.connection.in_transaction:
            store.connection.execute("ROLLBACK")
    except Exception as error:
        store.cleanup_failures.append(type(error).__name__)


@dataclass(frozen=True)
class CommitResult:
    """Describe durable admission or readback without granting effect execution."""

    status: str
    event_ids: tuple
    execution_permitted: bool = False


class MockOwnerProfile:
    """Freeze fixture authority and accept only bootstrap-issued handle identities."""

    def __init__(self, issuers, grants, sessions, clock_reader, target_reader):
        """Copy registries; callbacks are constructor-only cooperative fixture inputs."""
        require(callable(clock_reader) and callable(target_reader), "Fixture readers required")
        issuer_bytes, grant_bytes = encoded(issuers), encoded(grants)
        issuer_map, grant_map = parse_json(issuer_bytes), parse_json(grant_bytes)
        require(type(issuer_map) is dict and type(grant_map) is dict, "Registry objects required")
        for issuer_ref, issuer in issuer_map.items():
            text(issuer_ref)
            require(type(issuer) is dict and set(issuer) == {"allowed_owner_refs", "operations"}, "Issuer fields differ")
            self._allowlists(issuer)
        descriptions, handles = {}, []
        for handle, session in sessions:
            require(type(handle) is object and not any(handle is item[0] for item in handles), "Opaque unique fixture handle required")
            detached = parse_json(encoded(session))
            require(type(detached) is dict and set(detached) == SESSION_FIELDS, "Session fields differ")
            for field in ("session_ref", "requester_ref", "executor_ref", "actor_ref"):
                text(detached[field])
            self._allowlists(detached)
            require(detached["session_ref"] not in descriptions, "Duplicate session reference")
            descriptions[detached["session_ref"]] = detached
            handles.append((handle, detached["session_ref"]))
        for grant_id, grant in grant_map.items():
            require(type(grant) is dict and set(grant) == GRANT_FIELDS, "Grant fields differ")
            require(grant["profile_version"] == VERSION and grant["simulation_only"] is True, "Mock profile required")
            require(grant_id == grant["grant_id"], "Grant key differs")
            for field in ("grant_id", "issuer_ref", "requester_ref", "owner_ref", "executor_ref", "gate_id", "boot_id"):
                text(grant[field])
            require(grant["operation"] in OWNER_EVENTS, "Unknown owner operation")
            for field in ("scope_sha256", "intent_sha256"):
                sha256(grant[field])
            require(all(integer(grant[field]) for field in ("not_before_uptime_ms", "deadline_uptime_ms", "max_uses")), "Invalid grant integer")
            require(0 <= grant["not_before_uptime_ms"] < grant["deadline_uptime_ms"] and grant["max_uses"] > 0, "Invalid grant interval or budget")
            issuer = issuer_map.get(grant["issuer_ref"])
            require(issuer is not None and grant["owner_ref"] in issuer["allowed_owner_refs"]
                    and grant["operation"] in issuer["operations"], "Issuer owner/operation denied")
        self._registry = encoded({"issuers": issuer_map, "grants": grant_map, "sessions": descriptions})
        self._handles = tuple(handles)
        self._clock_reader, self._target_reader = clock_reader, target_reader

    @staticmethod
    def _allowlists(description):
        """Require explicit nonempty unique owner and operation allowlists."""
        for field in ("allowed_owner_refs", "operations"):
            values = description[field]
            require(type(values) is list and bool(values), "Invalid authority allowlist")
            for value in values:
                text(value)
            require(len(values) == len(set(values)), "Duplicate authority allowlist")
        require(set(description["operations"]) <= OWNER_EVENTS, "Unknown allowed operation")

    def _registries(self):
        """Return detached registries without exposing mutable authority state."""
        return parse_json(self._registry)

    def authorization(self, drafts, authorization):
        """Resolve known handle identity before any command or effect lookup."""
        require(type(drafts) is list and bool(drafts), "Nonempty draft list required")
        for draft in drafts:
            require(type(draft) is dict and set(draft) == DRAFT_FIELDS, "Original draft field set differs")
            encoded(draft)
        owners = [event for event in drafts if event["event_type"] in OWNER_EVENTS]
        if not owners:
            require(authorization is None, "Broker authorization forbidden")
            return None
        require(len(drafts) == len(owners) == 1, "Exactly one isolated owner event required")
        require(type(authorization) is tuple and len(authorization) == 2, "Grant ID and opaque session handle required")
        grant_id, handle = authorization
        text(grant_id)
        session_ref = next((reference for known, reference in self._handles if known is handle), None)
        require(session_ref is not None, "Unknown session handle")
        require(grant_id in self._registries()["grants"], "Unknown grant")
        return {"grant_id": grant_id, "session_ref": session_ref}

    def initialize(self, store):
        """Pin an empty database or verify the exact existing protected profile."""
        connection = store.connection
        metadata = {"profile_version": VERSION, "registry_sha256": digest(self._registry),
                    "registry": parse_json(self._registry),
                    "contract_principals_sha256": digest(encoded({"contract": store.contract, "principals": store.principals}))}
        require(store.contract.get("simulation_only") is True, "Simulation-only contract required")
        marker = connection.execute("SELECT value FROM runtime WHERE key='mock_owner_profile'").fetchone()
        exists = connection.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='owner_policy'").fetchone()
        if marker is not None or exists is not None:
            require(marker == (VERSION,) and exists is not None, "Protected profile marker mismatch")
            require(connection.execute("SELECT body FROM owner_policy").fetchall() == [(canonical(metadata),)], "Pinned mock policy differs")
            return
        require(all(connection.execute("SELECT COUNT(*) FROM " + table).fetchone()[0] == 0
                    for table in ("events", "commands", "blobs", "runtime")), "Populated legacy migration forbidden")
        connection.execute("BEGIN IMMEDIATE")
        connection.execute("CREATE TABLE owner_policy (singleton INTEGER PRIMARY KEY CHECK(singleton=1), body TEXT NOT NULL)")
        connection.execute("CREATE TABLE owner_requests (command_id TEXT PRIMARY KEY REFERENCES commands(command_id) DEFERRABLE INITIALLY DEFERRED, body TEXT NOT NULL)")
        connection.execute("CREATE TABLE owner_uses (event_id TEXT PRIMARY KEY REFERENCES events(event_id) DEFERRABLE INITIALLY DEFERRED, command_id TEXT NOT NULL UNIQUE REFERENCES commands(command_id) DEFERRABLE INITIALLY DEFERRED, grant_id TEXT NOT NULL, ordinal INTEGER NOT NULL, body TEXT NOT NULL, UNIQUE(grant_id,ordinal))")
        for table in ("owner_policy", "owner_requests", "owner_uses"):
            for operation in ("UPDATE", "DELETE"):
                connection.execute("CREATE TRIGGER " + table + "_no_" + operation.lower() + " BEFORE " + operation + " ON " + table + " BEGIN SELECT RAISE(ABORT, 'immutable mock policy evidence'); END")
        connection.execute("INSERT INTO owner_policy VALUES (1,?)", (canonical(metadata),))
        connection.execute("INSERT INTO runtime VALUES ('mock_owner_profile',?)", (VERSION,))
        connection.execute("COMMIT")

    def _binding(self, store, event, authorization, clock, observation):
        """Validate recorded or current admission against every pinned grant binding."""
        registries = self._registries()
        require(type(authorization) is dict and set(authorization) == {"grant_id", "session_ref"}, "Authorization fields differ")
        grant = registries["grants"].get(authorization["grant_id"])
        session = registries["sessions"].get(authorization["session_ref"])
        require(grant is not None and session is not None, "Unknown grant/session")
        require(type(observation) is dict and set(observation) == {"target", "scope_sha256", "revision"}, "Target observation fields differ")
        require(event["actor"]["role"] == "OWNER" and event["actor"]["principal_ref"] == session["actor_ref"] == grant["owner_ref"], "Owner actor differs")
        require(grant["owner_ref"] in session["allowed_owner_refs"] and grant["operation"] in session["operations"], "Session owner/operation denied")
        require(grant["requester_ref"] == session["requester_ref"] and grant["executor_ref"] == session["executor_ref"], "Requester/executor differs")
        require(grant["gate_id"] == event["gate_id"] == store.contract["gate_id"] and grant["operation"] == event["event_type"], "Gate/operation differs")
        require(encoded(grant["target"]) == encoded(observation["target"]) == encoded(event_target(event))
                and grant["scope_sha256"] == observation["scope_sha256"]
                and encoded(grant["revision"]) == encoded(observation["revision"]) == encoded(event["revision"]), "Target/scope/revision differs")
        require(grant["intent_sha256"] == intent_sha256(event), "Complete intent differs")
        clock = clock_value(clock)
        require(clock["boot_id"] == grant["boot_id"] and grant["not_before_uptime_ms"] <= clock["uptime_ms"] < grant["deadline_uptime_ms"], "Grant clock interval denied")
        if event["event_type"] == "ApprovalRecorded":
            require(event["payload"]["boot_id"] == grant["boot_id"] and type(event["payload"]["deadline_uptime_ms"]) is int
                    and event["payload"]["deadline_uptime_ms"] <= grant["deadline_uptime_ms"], "Approval exceeds grant interval")
        store.authenticate(event)
        return grant

    @staticmethod
    def _clock_order(clock, previous):
        """Reject boot substitution and uptime reversal across committed observations."""
        if previous is not None:
            require(clock["boot_id"] == previous["boot_id"] and clock["uptime_ms"] >= previous["uptime_ms"], "Admission clock reversed")

    @staticmethod
    def _normalize(drafts, command_id, record):
        """Reconstruct the exact normalized batch using immutable original evidence."""
        normalized, previous = [], record["previous_event_sha256"]
        for ordinal, draft in enumerate(drafts):
            event = copy.deepcopy(draft)
            event.update(command_id=command_id, sequence=record["first_sequence"] + ordinal,
                         transaction_id=record["transaction_id"], transaction_ordinal=ordinal,
                         previous_event_sha256=previous, clock=copy.deepcopy(record["clock"]))
            event["event_sha256"] = digest(encoded({key: value for key, value in event.items() if key != "event_sha256"}))
            previous = event["event_sha256"]
            normalized.append(event)
        return normalized

    def validate_history(self, store):
        """Check bidirectional command/request/use/effect coverage without live readers."""
        self.initialize(store)
        connection = store.connection
        commands = connection.execute("SELECT command_id,fingerprint,event_ids FROM commands").fetchall()
        requests = dict(connection.execute("SELECT command_id,body FROM owner_requests").fetchall())
        require(len(commands) == len(requests) and {row[0] for row in commands} == set(requests), "Command/request coverage differs")
        use_rows = connection.execute("SELECT event_id,command_id,grant_id,ordinal,body FROM owner_uses").fetchall()
        uses = {row[1]: row for row in use_rows}
        require(len(uses) == len(use_rows), "Duplicate use command")
        rows = connection.execute("SELECT body FROM events ORDER BY sequence").fetchall()
        batches, transaction_ids = [], set()
        for row in rows:
            event = parse_json(row[0])
            if not batches or batches[-1][0]["transaction_id"] != event["transaction_id"]:
                require(event["transaction_id"] not in transaction_ids, "Transaction ID reused")
                transaction_ids.add(event["transaction_id"])
                batches.append([])
            batches[-1].append(event)
        by_command = {batch[0]["command_id"]: batch for batch in batches}
        require(len(by_command) == len(batches) == len(commands), "Command/transaction coverage differs")
        spent, last_clock, covered_uses = {}, None, set()
        command_map = {command_id: (fingerprint, event_ids) for command_id, fingerprint, event_ids in commands}
        for batch in batches:
            command_id = batch[0]["command_id"]
            require(command_id in command_map and command_id in requests, "Orphan transaction")
            fingerprint, event_ids = command_map[command_id]
            record = parse_json(requests[command_id])
            require(set(record) == {"request", "clock", "transaction_id", "first_sequence", "previous_event_sha256", "observation"}, "Request record fields differ")
            require(canonical(record) == requests[command_id], "Request record not canonical")
            request = record["request"]
            require(type(request) is dict and set(request) == {"drafts", "authorization"}, "Original request fields differ")
            drafts, authorization = request["drafts"], request["authorization"]
            require(type(drafts) is list and bool(drafts) and all(type(draft) is dict and set(draft) == DRAFT_FIELDS for draft in drafts), "Original drafts incomplete")
            for draft in drafts:
                store.authenticate(draft)
                require(store.validator.validate(draft), "Original draft schema invalid")
            require(fingerprint == digest(encoded(request)), "Original fingerprint differs")
            require(integer(record["first_sequence"]) and record["first_sequence"] > 0, "Invalid recorded first sequence")
            require(encoded(self._normalize(drafts, command_id, record)) == encoded(batch), "Original request reconstruction differs")
            require(parse_json(event_ids) == [event["event_id"] for event in batch], "Command event manifest differs")
            require(all(event["command_id"] == command_id and event["gate_id"] == batch[0]["gate_id"]
                        and event["writer_generation"] == batch[0]["writer_generation"] for event in batch), "Mixed transaction identity")
            clock = clock_value(record["clock"])
            self._clock_order(clock, last_clock)
            owners = [event for event in batch if event["event_type"] in OWNER_EVENTS]
            if owners:
                require(len(batch) == len(owners) == 1 and command_id in uses, "Owner/use coverage differs")
                grant = self._binding(store, drafts[0], authorization, clock, record["observation"])
                ordinal = spent.get(grant["grant_id"], 0) + 1
                require(ordinal <= grant["max_uses"], "Grant budget exceeded")
                expected_use = self._use(grant, authorization, batch[0], ordinal, record)
                row = uses[command_id]
                require(row[:4] == (batch[0]["event_id"], command_id, grant["grant_id"], ordinal)
                        and row[4] == canonical(expected_use), "Grant-use evidence differs")
                spent[grant["grant_id"]] = ordinal
                covered_uses.add(command_id)
            else:
                require(authorization is None and record["observation"] is None and command_id not in uses, "Broker carries owner evidence")
            last_clock = clock
        require(covered_uses == set(uses), "Orphan grant use")
        return spent, last_clock

    @staticmethod
    def _use(grant, authorization, event, ordinal, record):
        """Build the exact append-only consumption evidence for one owner effect."""
        return {"grant_id": grant["grant_id"], "grant_sha256": digest(encoded(grant)),
                "session_ref": authorization["session_ref"], "command_id": event["command_id"],
                "transaction_id": event["transaction_id"], "event_id": event["event_id"],
                "ordinal": ordinal, "clock": record["clock"], "observation": record["observation"]}

    def append(self, store, drafts, command_id, blobs, fault, authorization):
        """Admit once in the existing connection transaction, or return ACK-only readback."""
        resolved = self.authorization(drafts, authorization)
        request = {"drafts": parse_json(encoded(drafts)), "authorization": resolved}
        command_id = command_id or identity()
        text(command_id)
        connection = store.connection
        connection.execute("BEGIN IMMEDIATE")
        require(connection.execute("SELECT value FROM runtime WHERE key='fence'").fetchone() == (str(store.fence),), "Stale writer fence")
        require(store.replay() == store.state, "Projection differs from committed history")
        spent, last_clock = self.validate_history(store)
        existing = connection.execute("SELECT fingerprint,event_ids FROM commands WHERE command_id=?", (command_id,)).fetchone()
        if existing:
            recorded = parse_json(connection.execute("SELECT body FROM owner_requests WHERE command_id=?", (command_id,)).fetchone()[0])
            require(encoded(recorded["request"]) == encoded(request) and existing[0] == digest(encoded(request)), "Command retry differs")
            connection.execute("ROLLBACK")
            return CommitResult("COMMITTED_ACK_ONLY", tuple(parse_json(existing[1])))
        if store.recovery_pending:
            require(len(drafts) == 1 and (drafts[0]["event_type"] == "OwnershipTransferred"
                    or (drafts[0]["event_type"] == "StopLatched" and drafts[0]["payload"]["reason"] == "UNKNOWN_JOB")
                    or (drafts[0]["event_type"] == "LaunchOutcomeRecorded" and drafts[0]["payload"]["outcome"] == "UNKNOWN")), "Recovery must finish before commands")
        transfer = len(drafts) == 1 and drafts[0]["event_type"] == "OwnershipTransferred"
        require(store.state["writer_generation"] == store.fence or (transfer and drafts[0]["payload"]["new_generation"] == store.fence), "Writer fence not reconciled")
        for draft in drafts:
            store.authenticate(draft)
            require(store.validator.validate(draft), "Original draft schema invalid")
        first_clock = clock_value(self._clock_reader())
        self._clock_order(first_clock, last_clock)
        self._clock_order(first_clock, store.state["last_clock"])
        observation, grant = None, None
        if resolved:
            observation = parse_json(encoded(self._target_reader()))
            grant = self._binding(store, drafts[0], resolved, first_clock, observation)
            require(spent.get(grant["grant_id"], 0) < grant["max_uses"], "Grant exhausted")
        if resolved:
            final_observation = parse_json(encoded(self._target_reader()))
            require(encoded(final_observation) == encoded(observation), "Target changed during admission")
        final_clock = clock_value(self._clock_reader())
        self._clock_order(final_clock, first_clock)
        if resolved:
            self._binding(store, drafts[0], resolved, final_clock, final_observation)
        tail = connection.execute("SELECT sequence,body FROM events ORDER BY sequence DESC LIMIT 1").fetchone()
        record = {"request": request, "clock": final_clock, "transaction_id": identity(),
                  "first_sequence": tail[0] + 1 if tail else 1,
                  "previous_event_sha256": parse_json(tail[1])["event_sha256"] if tail else None,
                  "observation": observation}
        normalized = self._normalize(request["drafts"], command_id, record)
        candidate = copy.deepcopy(store.state)
        for event in normalized:
            store.authenticate(event)
            require(store.validator.validate(event), "Full event schema rejection")
            candidate = apply_event(candidate, event)
        store.check_effects(normalized, store.state)
        for raw in blobs:
            connection.execute("INSERT OR IGNORE INTO blobs VALUES (?,?)", (digest(raw), raw))
        for event in normalized:
            if event["event_type"] == "ReceiptStored":
                store.get_blob(event["payload"]["final_artifact"])
            connection.execute("INSERT INTO events VALUES (?,?,?,?,?)", (event["sequence"], event["event_id"], event["gate_id"], command_id, canonical(event)))
        if fault in {"after_events", "before_commit"}:
            raise StorageFailure("Injected transaction failure")
        event_ids = [event["event_id"] for event in normalized]
        connection.execute("INSERT INTO commands VALUES (?,?,?)", (command_id, digest(encoded(request)), canonical(event_ids)))
        connection.execute("INSERT INTO owner_requests VALUES (?,?)", (command_id, canonical(record)))
        if grant:
            ordinal = spent.get(grant["grant_id"], 0) + 1
            use = self._use(grant, resolved, normalized[0], ordinal, record)
            connection.execute("INSERT INTO owner_uses VALUES (?,?,?,?,?)", (event_ids[0], command_id, grant["grant_id"], ordinal, canonical(use)))
        connection.execute("COMMIT")
        if fault == "after_commit":
            raise StorageFailure("Injected loss of commit acknowledgement")
        store.state = candidate
        return CommitResult("COMMITTED_ADMISSION", tuple(event_ids))
