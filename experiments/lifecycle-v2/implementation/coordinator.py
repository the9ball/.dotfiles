"""Deterministic simulated review outbox; no model, registry or credential access."""

import copy
from common import Denied, artifact, canonical, digest, identity, parse_json, receipt_findings, revision
from reducer import apply_event, permissions, require


class Coordinator:
    """Manage durable intents and receipts with explicitly simulated authority only."""

    def __init__(self, store, clock):
        """Bind injected clock and store; refuse any operational authority profile."""
        require(store.contract.get("simulation_only") is True, "Live authority adapter not verified")
        self.store, self.clock = store, clock
        self.proof = store.put_blob(b'{"simulation_only":true}')

    def emit(self, kind, payload, role="BROKER", target=None):
        """Commit a single guarded event with the current injected clock."""
        event = self.store.event(kind, payload, self.clock(), role, target)
        self.store.append([event])
        return event

    def rights(self):
        """Expose derived permissions, never an independent mutable PASS flag."""
        return permissions(self.store.state, self.clock(), self.store.ready())

    def recover(self):
        """Fence the previous writer and latch all uncertain surviving process states."""
        state = self.store.state
        if state["writer_generation"] != self.store.fence:
            self.emit("OwnershipTransferred", {"previous_generation": state["writer_generation"],
                "new_generation": self.store.fence, "termination_proof": self.proof})
        for job_id, job in list(self.store.state["jobs"].items()):
            if job["status"] == "LAUNCHING":
                self.emit("LaunchOutcomeRecorded", {"job_id": job_id, "outcome": "UNKNOWN", "process_evidence": self.proof})
            elif job["status"] == "RUNNING":
                self.emit("StopLatched", {"stop_id": job_id, "reason": "UNKNOWN_JOB", "evidence": self.proof})

        self.store.finish_recovery()

    def open_gate(self, deadline=2700000):
        """Create a mock gate and its explicit bounded owner interval."""
        manifest = self.store.put_blob(canonical(self.store.contract).encode())
        self.emit("GateOpened", {"owner_proof": self.proof, "scope_manifest": manifest, "review_contract": manifest}, "OWNER")
        self.approve(deadline)

    def approve(self, deadline):
        """Append a new mock-owner interval without resetting counters or findings."""
        self.emit("ApprovalRecorded", {"interval_id": identity(), "owner_proof": self.proof,
            "boot_id": self.clock()["boot_id"], "deadline_uptime_ms": deadline,
            "cumulative_caps": {"repair_cap": 3, "same_issue_failure_cap": 2, "review_round_cap": 4},
            "external_grants": self.proof}, "OWNER")

    def begin(self, repair=False):
        """Admit an initial implementation or consume one bounded repair attempt."""
        state = self.store.state
        payload = {"attempt_id": identity(), "interval_id": state["approval"]["interval_id"], "scope": self.proof}
        if repair:
            payload.update(issue_ids=list(state["issues"]), repair_spent_after=state["repair_spent"] + 1)
        self.emit("RepairAdmitted" if repair else "InitialAttemptAdmitted", payload)
        return payload["attempt_id"]

    def propose(self, issue_id):
        """Record a synthetic correction proof before candidate sealing."""
        self.emit("FixProposed", {"issue_id": issue_id, "attempt_id": self.store.state["attempt"], "correction_proof": self.proof})

    def seal(self, content="initial"):
        """Seal an immutable simulated candidate for checks and review."""
        target = revision(content, self.store.state["generation"])
        self.emit("CandidateRecorded", {"attempt_id": self.store.state["attempt"], "snapshot": self.proof, "phase": "SEALED"}, target=target)

    def verification(self):
        """Persist a verification intent without executing a real project test."""
        payload = {"attempt_id": self.store.state["attempt"], "request_id": identity(), "job_id": identity(),
                   "oracle_manifest": self.proof, "invocation_manifest": self.proof}
        self.emit("VerificationIntentRecorded", payload)
        return payload["job_id"]

    def review_round(self):
        """Reserve all required independent mock roles before starting any job."""
        slots = [{"role_id": role, "request_id": identity(), "job_id": identity(), "independence_proof": self.proof}
                 for role in self.store.contract["required_roles"]]
        round_id = identity()
        self.emit("ReviewRoundAdmitted", {"round_id": round_id, "attempt_id": self.store.state["attempt"],
            "review_spent_after": self.store.state["review_spent"] + 1, "slots": slots})
        for slot in slots:
            self.emit("ReviewIntentRecorded", {"round_id": round_id, "request_id": slot["request_id"],
                "job_id": slot["job_id"], "role_id": slot["role_id"], "input": self.proof, "external_grant_id": identity()})
        return [slot["job_id"] for slot in slots]

    def launch(self, job_id, outcome="STARTED"):
        """Record a mock launch once; never invoke an external CLI or network adapter."""
        job = self.store.state["jobs"][job_id]
        self.emit("LaunchStarted", {"job_id": job_id, "request_id": job["request_id"], "nonce": identity(), "admission_proof": self.proof})
        self.emit("LaunchOutcomeRecorded", {"job_id": job_id, "outcome": outcome, "process_evidence": self.proof})

    def exit(self, job_id, exit_code=0):
        """Record simulated job-group termination; live identity proof remains unimplemented."""
        self.emit("JobExitObserved", {"job_id": job_id, "exit_code": exit_code, "identity_and_group_exit_proof": self.proof})

    def result(self, job_id, verdict="CLEAR", findings=None):
        """Construct a strict synthetic final answer for an identified mock job."""
        job = self.store.state["jobs"][job_id]
        common = {"request_id": job["request_id"], "revision": copy.deepcopy(job["revision"])}
        if job["kind"] == "VERIFICATION":
            return {**common, "kind": "VERIFICATION", "outcome": "PASS" if verdict == "CLEAR" else "FAIL",
                    "check_ids": self.store.contract["required_checks"], "evidence": self.proof}
        if verdict == "CLEAR":
            return {**common, "verdict": verdict, "covered_issue_ids": list(self.store.state["issues"]), "report": self.proof}
        return {**common, "verdict": verdict, "findings": findings, "report": self.proof}

    def collect(self, job_id, raw, fault=None):
        """T1: durably save final bytes and debt; identical deliveries have no new effect."""
        require(len(raw) <= 1048576, "Prototype receipt size cap")
        job = self.store.state["jobs"][job_id]
        reference = artifact(raw)
        for receipt_id, receipt in self.store.state["receipts"].items():
            if receipt["request_id"] == job["request_id"] and receipt["final_artifact"] == reference:
                return receipt_id
        payload = {"receipt_id": identity(), "request_id": job["request_id"], "final_artifact": reference, "spool_proof": self.proof}
        event = self.store.event("ReceiptStored", payload, self.clock())
        self.store.append([event], blobs=[raw], fault=fault)
        return payload["receipt_id"]

    def apply_receipt(self, receipt_id, fault=None):
        """T2: atomically classify issues, charge failed repairs, and mark applied."""
        prior = self.store.state
        receipt = prior["receipts"][receipt_id]
        if receipt.get("applied"):
            return
        require(not any(reason == "EVIDENCE_CONFLICT" for reason in prior["stops"].values()), "Conflicting final answers")
        try:
            result = parse_json(self.store.get_blob(receipt["final_artifact"]))
            applied = self.store.event("ReceiptApplied", {"receipt_id": receipt_id, "result": result, "effect_event_ids": []}, self.clock())
            require(self.store.validator.validate(applied), "Malformed final result")
            findings = result.get("findings", [])
            # Alias identity is issuer-scoped and exact; never Unicode-fold opaque IDs.
            aliases = [canonical(finding["alias"]) for finding in findings]
            require(len(aliases) == len(set(aliases)), "Duplicate finding alias in final result")
            for finding in findings:
                alias_issue = prior["aliases"].get(canonical(finding["alias"]))
                anchor_issue = prior["anchors"].get(canonical(finding["anchor"]))
                require(not (alias_issue and anchor_issue and alias_issue != anchor_issue),
                        "Finding alias and stable anchor identify different issues")
        except (Denied, ValueError, UnicodeError):
            self.emit("ReceiptRejected", {"receipt_id": receipt_id, "reason": "UNCLASSIFIABLE",
                "unclassified_debt_id": identity(), "evidence": receipt["final_artifact"]})
            return
        job = next(job for job in prior["jobs"].values() if job["request_id"] == receipt["request_id"])
        findings = receipt_findings(result, receipt["final_artifact"])
        effects, projected = [], copy.deepcopy(prior)
        for finding in findings:
            alias, anchor = canonical(finding["alias"]), canonical(finding["anchor"])
            issue_id = projected["aliases"].get(alias) or projected["anchors"].get(anchor) or identity()
            old = projected["issues"].get(issue_id)
            payload = {"issue_id": issue_id, "episode": old["episode"] + (old["state"] != "OPEN") if old else 0,
                "alias": finding["alias"], "anchor": finding["anchor"], "source_receipt_id": receipt_id,
                "classification_proof": finding["evidence"]}
            event = self.store.event("FindingClassified", payload, self.clock())
            projected = apply_event(projected, event)
            effects.append(event)
            charge = [job["attempt_id"], issue_id]
            if projected["attempts"][job["attempt_id"]]["repair"] and charge not in projected["charges"]:
                event = self.store.event("RepairFailureCharged", {"issue_id": issue_id, "attempt_id": job["attempt_id"],
                    "source_receipt_id": receipt_id, "issue_failed_after": projected["issues"][issue_id]["failed"] + 1}, self.clock())
                projected = apply_event(projected, event)
                effects.append(event)
        applied["payload"]["effect_event_ids"] = [event["event_id"] for event in effects]
        if any(finding["severity"] != "ORDINARY" for finding in findings):
            effects.append(self.store.event("StopLatched", {"stop_id": identity(), "reason": "UNCLASSIFIABLE", "evidence": receipt["final_artifact"]}, self.clock()))
        self.store.append([*effects, applied], fault=fault)

    def complete_job(self, job_id, verdict="CLEAR", findings=None):
        """Drive a mock job to exit and apply its final answer for isolated tests."""
        self.launch(job_id)
        self.exit(job_id)
        result = self.result(job_id, verdict, findings)
        receipt_id = self.collect(job_id, canonical(result).encode())
        self.apply_receipt(receipt_id)
        return receipt_id

    def close_issue(self, issue_id, verification_ids, clear_ids):
        """Request closure with explicit current verification and review receipts."""
        self.emit("ClosureAccepted", {"issue_id": issue_id, "attempt_id": self.store.state["attempt"],
            "verification_receipt_ids": verification_ids, "clear_receipt_ids": clear_ids, "correction_proof": self.proof})

    def assess(self):
        """Emit a simulated PASS only after current permission derivation allows it."""
        require(self.rights()["can_pass"], "PASS is blocked")
        receipts = self.store.state["receipts"]
        current = self.store.state["revision"]
        verification = [key for key, value in receipts.items() if value.get("result", {}).get("outcome") == "PASS"
                        and value["result"]["revision"] == current]
        clears = [key for key, value in receipts.items() if value.get("result", {}).get("verdict") == "CLEAR"
                  and value["result"]["revision"] == current and value.get("approval_eligible") is True]
        self.emit("PassAssessed", {"interval_id": self.store.state["approval"]["interval_id"], "eligible": True,
            "verification_receipt_ids": verification, "clear_receipt_ids": clears, "user_review_proof": None,
            "projection_sha256": digest(canonical(self.store.state).encode())})
