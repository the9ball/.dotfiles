"""Append-only SQLite ledger with atomic batches, raw receipt blobs and replay."""

import copy
import json
import os
import sqlite3
from pathlib import Path

from common import Denied, StorageFailure, artifact, canonical, digest, identity, parse_json, receipt_findings
from reducer import apply_event, initial_state, require


class EventStore:
    """Single-host prototype; same-user malicious tampering is not authenticated."""

    def __init__(self, directory, contract, validator, principals):
        """Acquire an OS lock before opening the private local database."""
        self.directory = Path(directory).resolve()
        self.directory.mkdir(parents=True, exist_ok=True)
        self.contract, self.validator, self.principals = copy.deepcopy(contract), validator, copy.deepcopy(principals)
        self.healthy = True
        self.closed = False
        self.lock_file = open(self.directory / "writer.lock", "a+b")
        if self.lock_file.seek(0, os.SEEK_END) == 0:
            self.lock_file.write(b"0")
            self.lock_file.flush()
        self.lock_file.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(self.lock_file.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            self.lock_file.close()
            raise Denied("Existing live writer") from error
        try:
            self.connection = sqlite3.connect(self.directory / "events.sqlite", isolation_level=None)
            require(self.connection.execute("PRAGMA journal_mode=WAL").fetchone()[0] == "wal", "WAL unavailable")
            self.connection.execute("PRAGMA synchronous=FULL")
            self.connection.execute("PRAGMA foreign_keys=ON")
            self.connection.executescript('''
                CREATE TABLE IF NOT EXISTS events (
                    sequence INTEGER PRIMARY KEY, event_id TEXT NOT NULL UNIQUE,
                    gate_id TEXT NOT NULL, command_id TEXT NOT NULL, body TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS commands (
                    command_id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, event_ids TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS blobs (
                    sha256 TEXT PRIMARY KEY, body BLOB NOT NULL);
                CREATE TABLE IF NOT EXISTS runtime (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TRIGGER IF NOT EXISTS events_no_update BEFORE UPDATE ON events
                    BEGIN SELECT RAISE(ABORT, 'append-only event'); END;
                CREATE TRIGGER IF NOT EXISTS events_no_delete BEFORE DELETE ON events
                    BEGIN SELECT RAISE(ABORT, 'append-only event'); END;
                CREATE TRIGGER IF NOT EXISTS commands_no_update BEFORE UPDATE ON commands
                    BEGIN SELECT RAISE(ABORT, 'append-only command'); END;
                CREATE TRIGGER IF NOT EXISTS commands_no_delete BEFORE DELETE ON commands
                    BEGIN SELECT RAISE(ABORT, 'append-only command'); END;
                CREATE TRIGGER IF NOT EXISTS blobs_no_update BEFORE UPDATE ON blobs
                    BEGIN SELECT RAISE(ABORT, 'immutable blob'); END;
                CREATE TRIGGER IF NOT EXISTS blobs_no_delete BEFORE DELETE ON blobs
                    BEGIN SELECT RAISE(ABORT, 'immutable blob'); END;
            ''')
            require(self.connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "Database integrity failure")
            self.state = self.replay()
            marker = self.connection.execute("SELECT value FROM runtime WHERE key='run_open'").fetchone()
            self.prior_unclean = marker is not None and marker[0] != "false"
            previous = self.connection.execute("SELECT value FROM runtime WHERE key='fence'").fetchone()
            self.fence = int(previous[0]) + 1 if previous else 0
            self.recovery_pending = self.prior_unclean or self.state["writer_generation"] != self.fence
            self.connection.execute("BEGIN IMMEDIATE")
            self.connection.execute("INSERT OR REPLACE INTO runtime VALUES ('fence', ?)", (str(self.fence),))
            self.connection.execute("INSERT OR REPLACE INTO runtime VALUES ('run_open', 'true')")
            self.connection.execute("COMMIT")
        except Exception:
            if hasattr(self, "connection"):
                self.connection.close()
            self.lock_file.close()
            raise

    def ready(self):
        """Withhold operational rights until this locked writer has reconciled durable history."""
        return self.healthy and not self.closed and not self.recovery_pending and self.state["writer_generation"] == self.fence

    def finish_recovery(self):
        """Reconcile local committed effects and latch uncertain jobs before releasing permissions."""
        require(self.healthy and not self.closed, "Recovery store unavailable")
        require(self.state["writer_generation"] == self.fence, "Recovery fence not reconciled")
        require(self.replay() == self.state, "Recovery projection differs from durable history")
        for job_id, job in self.state["jobs"].items():
            require(job["status"] != "LAUNCHING", "Launch uncertainty not reconciled")
            require(job["status"] != "RUNNING" or self.state["stops"].get(job_id) == "UNKNOWN_JOB",
                    "Running job uncertainty not latched")
        try:
            self.connection.execute("INSERT OR REPLACE INTO runtime VALUES ('reconciled_fence', ?)", (str(self.fence),))
        except sqlite3.Error as error:
            self.healthy = False
            raise StorageFailure("Recovery reconciliation save failed") from error
        self.recovery_pending = False

    def close(self):
        """Release only this writer; unverified recovery and storage failures retain the marker."""
        if self.closed:
            return
        try:
            if self.healthy and not self.recovery_pending:
                self.connection.execute("INSERT OR REPLACE INTO runtime VALUES ('run_open', 'false')")
        finally:
            self.healthy = False
            self.closed = True
            self.connection.close()
            self.lock_file.close()

    def get_blob(self, reference):
        """Load exact bytes and require both byte length and content hash to match."""
        row = self.connection.execute("SELECT body FROM blobs WHERE sha256=?", (reference["sha256"],)).fetchone()
        require(row is not None and len(row[0]) == reference["bytes"] and digest(row[0]) == reference["sha256"], "Artifact unavailable or corrupt")
        return row[0]

    def put_blob(self, raw, media_type="application/json"):
        """Persist a non-receipt artifact; receipt bytes use the T1 batch instead."""
        require(self.healthy and not self.closed, "Store is fail-closed")
        reference = artifact(raw, media_type)
        try:
            self.connection.execute("INSERT OR IGNORE INTO blobs VALUES (?,?)", (reference["sha256"], raw))
        except sqlite3.Error as error:
            self.healthy = False
            raise StorageFailure("Artifact save failed") from error
        self.get_blob(reference)
        return reference

    def event(self, event_type, payload, clock, role="BROKER", revision=None):
        """Build an unsigned draft; its actor is bound to the local test registry."""
        principal = self.principals[role]
        return {"schema_version": 2, "event_id": identity(), "gate_id": self.state["gate_id"] or self.contract["gate_id"],
                "command_id": identity(), "sequence": 1, "transaction_id": identity(), "transaction_ordinal": 0,
                "writer_generation": self.state["writer_generation"], "previous_event_sha256": None,
                "event_sha256": "0" * 64, "revision": copy.deepcopy(self.state["revision"] if revision is None else revision),
                "clock": copy.deepcopy(clock), "actor": {"role": role, "principal_ref": principal["principal_ref"], "proof": principal["proof"]},
                "event_type": event_type, "payload": copy.deepcopy(payload)}

    def authenticate(self, event):
        """Reject actor substitution against injected test authority, not a real login."""
        principal = self.principals.get(event["actor"]["role"])
        require(principal is not None and event["actor"]["principal_ref"] == principal["principal_ref"]
                and event["actor"]["proof"] == principal["proof"], "Actor channel mismatch")

    def check_effects(self, events, prior):
        """Reject incomplete T2 batches using raw findings, exact attribution and projected charges."""
        applied = [event for event in events if event["event_type"] == "ReceiptApplied"]
        if not applied:
            require(not any(event["event_type"] in {"FindingClassified", "RepairFailureCharged"} for event in events),
                    "Orphan receipt effect")
            return
        require(len(applied) == 1 and events[-1] == applied[0], "One final receipt marker required")
        payload = applied[0]["payload"]
        receipt_id = payload["receipt_id"]
        receipt = prior["receipts"][receipt_id]
        raw_result = parse_json(self.get_blob(receipt["final_artifact"]))
        require(raw_result == payload["result"], "Applied result differs from raw final")
        findings = receipt_findings(raw_result, receipt["final_artifact"])
        aliases = [canonical(finding["alias"]) for finding in findings]
        require(len(aliases) == len(set(aliases)), "Duplicate raw finding alias")
        projected = copy.deepcopy(prior)
        job = next(job for job in prior["jobs"].values() if job["request_id"] == receipt["request_id"])
        cursor, effect_ids = 0, []
        for finding in findings:
            require(cursor < len(events) - 1, "Missing classification")
            event = events[cursor]
            require(event["event_type"] == "FindingClassified", "Classification ordering mismatch")
            alias, anchor = canonical(finding["alias"]), canonical(finding["anchor"])
            alias_id, anchor_id = projected["aliases"].get(alias), projected["anchors"].get(anchor)
            require(not (alias_id and anchor_id and alias_id != anchor_id), "Ambiguous raw finding")
            issue_id = alias_id or anchor_id or event["payload"]["issue_id"]
            old = projected["issues"].get(issue_id)
            require(alias_id or anchor_id or old is None, "New finding reused another issue")
            expected = {"issue_id": issue_id, "episode": old["episode"] + (old["state"] != "OPEN") if old else 0,
                        "alias": finding["alias"], "anchor": finding["anchor"], "source_receipt_id": receipt_id,
                        "classification_proof": finding["evidence"]}
            require(event["payload"] == expected, "Classification differs from raw finding")
            projected = apply_event(projected, event)
            effect_ids.append(event["event_id"])
            cursor += 1
            if projected["attempts"][job["attempt_id"]]["repair"] and [job["attempt_id"], issue_id] not in projected["charges"]:
                require(cursor < len(events) - 1, "Missing repair failure charge")
                event = events[cursor]
                expected = {"issue_id": issue_id, "attempt_id": job["attempt_id"], "source_receipt_id": receipt_id,
                            "issue_failed_after": projected["issues"][issue_id]["failed"] + 1}
                require(event["event_type"] == "RepairFailureCharged" and event["payload"] == expected,
                        "Required repair charge differs")
                projected = apply_event(projected, event)
                effect_ids.append(event["event_id"])
                cursor += 1
        if any(finding["severity"] != "ORDINARY" for finding in findings):
            require(cursor < len(events) - 1, "Missing required safety stop")
            event = events[cursor]
            require(event["event_type"] == "StopLatched" and event["payload"]["reason"] == "UNCLASSIFIABLE"
                    and event["payload"]["evidence"] == receipt["final_artifact"]
                    and event["payload"]["stop_id"] not in prior["stops"]
                    and event["payload"]["stop_id"] not in prior["jobs"], "Required safety stop differs")
            cursor += 1
        require(cursor == len(events) - 1, "Unexpected T2 effects")
        require(payload["effect_event_ids"] == effect_ids, "Effect manifest mismatch")

    def append(self, drafts, command_id=None, blobs=(), fault=None):
        """Atomically commit authenticated, schema-valid events and deduplicate commands."""
        require(self.healthy and not self.closed, "Store is fail-closed")
        durable_fence = self.connection.execute("SELECT value FROM runtime WHERE key='fence'").fetchone()
        require(durable_fence is not None and int(durable_fence[0]) == self.fence, "Stale writer fence")
        if self.recovery_pending:
            require(len(drafts) == 1 and (drafts[0]["event_type"] == "OwnershipTransferred"
                    or (drafts[0]["event_type"] == "StopLatched" and drafts[0]["payload"]["reason"] == "UNKNOWN_JOB")
                    or (drafts[0]["event_type"] == "LaunchOutcomeRecorded" and drafts[0]["payload"]["outcome"] == "UNKNOWN")),
                    "Recovery must finish before normal commands")
        command_id = command_id or identity()
        fingerprint = digest(canonical(drafts).encode())
        existing = self.connection.execute("SELECT fingerprint,event_ids FROM commands WHERE command_id=?", (command_id,)).fetchone()
        if existing:
            require(existing[0] == fingerprint, "Command ID reused with different content")
            return parse_json(existing[1])
        transfer = len(drafts) == 1 and drafts[0]["event_type"] == "OwnershipTransferred"
        require(self.state["writer_generation"] == self.fence or (transfer and drafts[0]["payload"]["new_generation"] == self.fence),
                "Writer must reconcile fencing before commands")
        transaction_id, normalized = identity(), []
        tail = self.connection.execute("SELECT sequence,body FROM events ORDER BY sequence DESC LIMIT 1").fetchone()
        sequence, previous_hash = (tail[0], parse_json(tail[1])["event_sha256"]) if tail else (0, None)
        candidate = copy.deepcopy(self.state)
        for ordinal, draft in enumerate(drafts):
            event = copy.deepcopy(draft)
            sequence += 1
            event.update(command_id=command_id, sequence=sequence, transaction_id=transaction_id,
                         transaction_ordinal=ordinal, previous_event_sha256=previous_hash)
            event["event_sha256"] = digest(canonical({key: value for key, value in event.items() if key != "event_sha256"}).encode())
            self.authenticate(event)
            require(self.validator.validate(event), "Full event schema rejection")
            candidate = apply_event(candidate, event)
            previous_hash = event["event_sha256"]
            normalized.append(event)
        self.check_effects(normalized, self.state)
        try:
            self.connection.execute("BEGIN IMMEDIATE")
            for raw in blobs:
                self.connection.execute("INSERT OR IGNORE INTO blobs VALUES (?,?)", (digest(raw), raw))
            for event in normalized:
                if event["event_type"] == "ReceiptStored":
                    self.get_blob(event["payload"]["final_artifact"])
                self.connection.execute("INSERT INTO events VALUES (?,?,?,?,?)", (
                    event["sequence"], event["event_id"], event["gate_id"], command_id, canonical(event)))
            if fault in {"after_events", "before_commit"}:
                raise StorageFailure("Injected transaction failure")
            event_ids = [event["event_id"] for event in normalized]
            self.connection.execute("INSERT INTO commands VALUES (?,?,?)", (command_id, fingerprint, canonical(event_ids)))
            self.connection.execute("COMMIT")
            if fault == "after_commit":
                raise StorageFailure("Injected loss of commit acknowledgement")
        except (sqlite3.Error, StorageFailure) as error:
            if self.connection.in_transaction:
                self.connection.execute("ROLLBACK")
            self.healthy = False
            raise StorageFailure("Ledger write uncertain; no ACK") from error
        self.state = candidate
        return event_ids

    def replay(self):
        """Validate the complete immutable history before reconstructing any permissions."""
        state, previous_hash, transactions = initial_state(self.contract), None, []
        rows = self.connection.execute("SELECT sequence,event_id,gate_id,command_id,body FROM events ORDER BY sequence").fetchall()
        for expected, row in enumerate(rows, 1):
            event = parse_json(row[4])
            require((row[0], row[1], row[2], row[3]) == (event["sequence"], event["event_id"], event["gate_id"], event["command_id"]), "Index/body mismatch")
            require(event["sequence"] == expected and event["previous_event_sha256"] == previous_hash, "History gap or chain corruption")
            require(event["event_sha256"] == digest(canonical({key: value for key, value in event.items() if key != "event_sha256"}).encode()), "Event hash corruption")
            require(self.validator.validate(event), "Stored event schema invalid")
            self.authenticate(event)
            if not transactions or transactions[-1][0]["transaction_id"] != event["transaction_id"]:
                transactions.append([])
            transactions[-1].append(event)
            previous_hash = event["event_sha256"]
        for batch in transactions:
            require([item["transaction_ordinal"] for item in batch] == list(range(len(batch))), "Partial transaction")
            command = self.connection.execute("SELECT event_ids FROM commands WHERE command_id=?", (batch[0]["command_id"],)).fetchone()
            require(command is not None and parse_json(command[0]) == [item["event_id"] for item in batch], "Command coverage missing")
            self.check_effects(batch, state)
            for event in batch:
                if event["event_type"] == "ReceiptStored":
                    self.get_blob(event["payload"]["final_artifact"])
                state = apply_event(state, event)
        return state
