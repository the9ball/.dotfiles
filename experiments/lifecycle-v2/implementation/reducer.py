"""Pure event reducer and permission derivation for isolated, simulated authority."""

import copy
from common import Denied, canonical, digest, parse_json

TERMINAL = {"PROVED_NOT_STARTED", "RETIRED"}
OWNER_EVENTS = {"GateOpened", "ApprovalRecorded", "StopResolved", "JobRetirementAccepted"}


def initial_state(contract):
    """Create a detached projection without granting runtime or owner capabilities."""
    return {"contract": copy.deepcopy(contract), "opened": False, "gate_id": None,
            "revision": None, "generation": 0, "approval": None, "last_clock": None,
            "attempts": {}, "attempt": None, "repair_spent": 0, "review_spent": 0,
            "rounds": {}, "jobs": {}, "receipts": {}, "issues": {}, "aliases": {},
            "anchors": {}, "charges": [], "checks": {}, "clears": {}, "stops": {},
            "writer_generation": 0, "pass_assessed": None, "ever_passed": False, "stop_owners": {}}


def revision_key(revision):
    """Bind evidence to all revision fields including the assessment generation."""
    return canonical(revision)


def terminal(job):
    """Require a final applied answer as well as exit for a normally started job."""
    return job["status"] in TERMINAL or (job["status"] == "EXITED" and job.get("applied"))


def invalidate(state, advance=False):
    """Revoke current evidence without erasing findings, jobs or cumulative budgets."""
    state["checks"] = {}
    state["clears"] = {}
    state["pass_assessed"] = None
    if advance:
        state["generation"] += 1
        if state["revision"] is not None:
            state["revision"]["assessment_generation"] = state["generation"]


def require(condition, reason):
    """Reject an inadmissible event before its projection is returned."""
    if not condition:
        raise Denied(reason)


def latch_owned_stop(state, stop_id, reason):
    """Preserve stop ownership and reject reason replacement or cross-domain identity reuse."""
    if reason == "UNKNOWN_JOB":
        require(stop_id in state["jobs"] and state["jobs"][stop_id]["status"] in {"RUNNING", "LAUNCHING", "UNKNOWN"},
                "Unknown-job stop lacks its uncertain job")
        owner = {"kind": "job", "job_id": stop_id}
    else:
        require(stop_id not in state["jobs"], "Safety stop cannot reuse a job identity")
        owner = {"kind": "safety"}
    require(stop_id not in state["stop_owners"] or state["stop_owners"][stop_id] == owner, "Stop owner cannot change")
    require(stop_id not in state["stops"] or state["stops"][stop_id] == reason, "Stop reason cannot be overwritten")
    state["stop_owners"][stop_id] = owner
    state["stops"][stop_id] = reason


def permissions(state, clock, healthy=True):
    """Derive operation permissions; BLOCKED does not itself prohibit local repair."""
    approval = state["approval"]
    timely = bool(approval and clock["boot_id"] == approval["boot_id"]
                  and clock["uptime_ms"] < approval["deadline_uptime_ms"])
    stable_clock = state["last_clock"] is None or (
        clock["boot_id"] == state["last_clock"]["boot_id"]
        and clock["uptime_ms"] >= state["last_clock"]["uptime_ms"])
    authority = bool(healthy and state["opened"] and timely and stable_clock and not state["stops"])
    frozen = any(not terminal(job) for job in state["jobs"].values())
    debt = any(not item.get("applied") or item.get("rejected") for item in state["receipts"].values())
    caps = approval["cumulative_caps"] if approval else {}
    issue_limit = any(issue["failed"] >= caps.get("same_issue_failure_cap", 0)
                      for issue in state["issues"].values() if issue["state"] != "CLOSED")
    attempt = state["attempts"].get(state["attempt"])
    current = revision_key(state["revision"])
    verified = bool(state["revision"] and all(state["checks"].get(check) == current
                    for check in state["contract"]["required_checks"]))
    clear = all(state["clears"].get(role) == current for role in state["contract"]["required_roles"])
    closed = all(issue["state"] == "CLOSED" and issue.get("closure") == current
                 for issue in state["issues"].values())
    eligible = bool(authority and verified and clear and closed and not frozen and not debt)
    repair = bool(authority and not frozen and not debt and not issue_limit
                  and state["repair_spent"] < caps.get("repair_cap", 0)
                  and any(issue["state"] != "CLOSED" for issue in state["issues"].values()))
    editable = bool(authority and not frozen and attempt and attempt["phase"] == "EDITING")
    return {"initial": bool(authority and not state["attempts"] and not frozen),
            "repair": repair, "edit": editable,
            "verify": bool(authority and not frozen and attempt and attempt["phase"] == "SEALED"),
            "capture": bool(authority and verified and not frozen),
            "review": bool(authority and verified and not frozen and not debt
                           and state["review_spent"] < caps.get("review_round_cap", 0)
                           and all(issue["state"] != "OPEN" for issue in state["issues"].values())),
            "dispatch": authority, "collect": healthy, "can_pass": eligible,
            "pass": bool(eligible and state["pass_assessed"] == current),
            "label": "COMPLETE" if eligible and state["pass_assessed"] == current else (
                "LOCAL_REPAIR" if repair or editable else "COLLECT_ONLY" if not authority else "BLOCKED")}


def apply_event(previous, event):
    """Reduce one schema-valid event with semantic guards and no external effects."""
    state = copy.deepcopy(previous)
    kind, payload, clock = event["event_type"], event["payload"], event["clock"]
    rights = permissions(state, clock)
    require(event["writer_generation"] == state["writer_generation"], "Writer generation mismatch")
    if state["opened"]:
        require(event["gate_id"] == state["gate_id"], "Gate identity changed")
    if kind in OWNER_EVENTS:
        require(event["actor"]["role"] == "OWNER", "Owner channel required")
    else:
        require(event["actor"]["role"] == "BROKER", "Broker channel required")
    if state["last_clock"] and kind != "ApprovalRecorded":
        if clock["boot_id"] != state["last_clock"]["boot_id"] or clock["uptime_ms"] < state["last_clock"]["uptime_ms"]:
            latch_owned_stop(state, "clock", "CLOCK_DISCONTINUITY")
            require(kind in {"ReceiptStored", "ReceiptApplied", "ReceiptRejected", "StopLatched", "JobExitObserved"},
                    "Clock discontinuity")
    state["last_clock"] = copy.deepcopy(clock)
    if kind == "GateOpened":
        require(not state["opened"], "Gate already opened")
        require(payload["scope_manifest"]["sha256"] == digest(canonical(state["contract"]).encode()),
                "Trusted contract hash mismatch")
        state["opened"], state["gate_id"] = True, event["gate_id"]
    elif kind == "ApprovalRecorded":
        require(state["opened"], "Gate not open")
        require(payload["boot_id"] == clock["boot_id"] and payload["deadline_uptime_ms"] > clock["uptime_ms"],
                "Invalid approval deadline")
        old = state["approval"]
        if old:
            require(all(payload["cumulative_caps"][key] >= old["cumulative_caps"][key]
                        for key in old["cumulative_caps"]), "Cumulative caps cannot shrink")
            invalidate(state, advance=True)
        state["approval"] = copy.deepcopy(payload)
    elif kind in {"InitialAttemptAdmitted", "RepairAdmitted"}:
        require(rights["initial" if kind == "InitialAttemptAdmitted" else "repair"], "Attempt admission denied")
        require(payload["interval_id"] == state["approval"]["interval_id"], "Wrong interval")
        require(payload["attempt_id"] not in state["attempts"], "Attempt identity reused")
        if kind == "RepairAdmitted":
            require(payload["issue_ids"] and all(key in state["issues"] for key in payload["issue_ids"]),
                    "Unclassified repair")
            state["repair_spent"] += 1
            require(payload["repair_spent_after"] == state["repair_spent"], "Repair count mismatch")
        state["attempt"] = payload["attempt_id"]
        state["attempts"][state["attempt"]] = {"repair": kind == "RepairAdmitted", "phase": "EDITING"}
        invalidate(state)
    elif kind == "CandidateRecorded":
        require(rights["edit"] and payload["attempt_id"] == state["attempt"], "Candidate not editable")
        revision = event["revision"]
        require(revision is not None and revision["assessment_generation"] == state["generation"], "Wrong assessment generation")
        fields = {key: value for key, value in revision.items() if key not in {"revision_id", "assessment_generation"}}
        require(digest(canonical(fields).encode()) == revision["revision_id"], "Invalid revision hash")
        if state["revision"]:
            require(all(revision[key] == state["revision"][key] for key in fields if key != "content_sha256"),
                    "Protected contract or oracle changed")
        state["revision"] = copy.deepcopy(revision)
        state["snapshot_hash"] = payload["snapshot"]["sha256"]
        state["attempts"][state["attempt"]]["phase"] = "SEALED"
        invalidate(state)
    elif kind == "VerificationIntentRecorded":
        require(rights["verify"], "Verification denied")
        require(event["revision"] == state["revision"] and payload["attempt_id"] == state["attempt"], "Verification revision mismatch")
        require(payload["job_id"] not in state["jobs"], "Job identity reused")
        require(payload["job_id"] not in state["stop_owners"] and payload["job_id"] not in state["stops"],
                "Job identity belongs to a stop")
        state["jobs"][payload["job_id"]] = {"kind": "VERIFICATION", "request_id": payload["request_id"],
            "attempt_id": state["attempt"], "revision": copy.deepcopy(event["revision"]), "status": "PENDING"}
    elif kind == "ReviewRoundAdmitted":
        require(rights["review"] and event["revision"] == state["revision"], "Review admission denied")
        require(payload["round_id"] not in state["rounds"] and payload["attempt_id"] == state["attempt"], "Round reused")
        slots = payload["slots"]
        require(sorted(slot["role_id"] for slot in slots) == sorted(state["contract"]["required_roles"]), "Required roles differ")
        require(len({slot["request_id"] for slot in slots}) == len(slots), "Duplicate request slot")
        state["review_spent"] += 1
        require(state["review_spent"] == payload["review_spent_after"], "Round count mismatch")
        state["rounds"][payload["round_id"]] = copy.deepcopy(payload)
        for slot in slots:
            require(slot["job_id"] not in state["jobs"], "Duplicate job slot")
            require(slot["job_id"] not in state["stop_owners"] and slot["job_id"] not in state["stops"],
                    "Review job identity belongs to a stop")
            state["jobs"][slot["job_id"]] = {**copy.deepcopy(slot), "kind": "REVIEW", "round_id": payload["round_id"],
                "attempt_id": state["attempt"], "revision": copy.deepcopy(event["revision"]), "status": "RESERVED"}
    elif kind == "ReviewIntentRecorded":
        job = state["jobs"][payload["job_id"]]
        require(rights["dispatch"] and job["status"] == "RESERVED", "Review intent duplicate or blocked")
        require(all(job[key] == payload[key] for key in ("request_id", "role_id", "round_id")), "Review slot mismatch")
        require(event["revision"] == job["revision"] == state["revision"], "Stale review input")
        require(payload["input"]["sha256"] == state["snapshot_hash"], "Review input changed")
        job["status"] = "PENDING"
        job["external_grant_id"] = payload["external_grant_id"]
    elif kind == "LaunchStarted":
        job = state["jobs"][payload["job_id"]]
        require(rights["dispatch"] and job["status"] == "PENDING", "Launch denied or already attempted")
        require(job["request_id"] == payload["request_id"], "Request mismatch")
        job["status"], job["nonce"] = "LAUNCHING", payload["nonce"]
    elif kind == "LaunchOutcomeRecorded":
        job = state["jobs"][payload["job_id"]]
        require(job["status"] == "LAUNCHING", "No launch to reconcile")
        job["status"] = {"STARTED": "RUNNING", "PROVED_NOT_STARTED": "PROVED_NOT_STARTED", "UNKNOWN": "UNKNOWN"}[payload["outcome"]]
        job["identity"] = copy.deepcopy(payload["process_evidence"])
        if payload["outcome"] == "UNKNOWN":
            latch_owned_stop(state, payload["job_id"], "UNKNOWN_JOB")
    elif kind == "JobExitObserved":
        job = state["jobs"][payload["job_id"]]
        require(job["status"] in {"RUNNING", "UNKNOWN", "LAUNCHING"}, "Unexpected exit")
        job["status"], job["exit_code"] = "EXITED", payload["exit_code"]
        owner = state["stop_owners"].get(payload["job_id"])
        if owner == {"kind": "job", "job_id": payload["job_id"]} and state["stops"].get(payload["job_id"]) == "UNKNOWN_JOB":
            del state["stops"][payload["job_id"]]
    elif kind == "ReceiptStored":
        require(payload["receipt_id"] not in state["receipts"], "Receipt identity reused")
        jobs = [job for job in state["jobs"].values() if job["request_id"] == payload["request_id"]]
        require(len(jobs) == 1, "Receipt request unknown")
        state["receipts"][payload["receipt_id"]] = {**copy.deepcopy(payload), "applied": False}
        state["pass_assessed"] = None
        for receipt in state["receipts"].values():
            if receipt["request_id"] == payload["request_id"] and receipt["final_artifact"]["sha256"] != payload["final_artifact"]["sha256"]:
                # Internal conflict keys cannot collide with UUID job or public stop identities.
                latch_owned_stop(state, "receipt-conflict:" + payload["request_id"], "EVIDENCE_CONFLICT")
                invalidate(state)
    elif kind == "ReceiptRejected":
        receipt = state["receipts"][payload["receipt_id"]]
        receipt["rejected"] = True
        latch_owned_stop(state, payload["unclassified_debt_id"], payload["reason"])
        invalidate(state)
    elif kind == "FindingClassified":
        require(payload["source_receipt_id"] in state["receipts"], "Missing finding receipt")
        alias, anchor = canonical(payload["alias"]), canonical(payload["anchor"])
        issue_id = payload["issue_id"]
        require(state["aliases"].get(alias, issue_id) == issue_id and state["anchors"].get(anchor, issue_id) == issue_id,
                "Ambiguous issue identity")
        state["aliases"][alias], state["anchors"][anchor] = issue_id, issue_id
        old = state["issues"].get(issue_id)
        expected_episode = old["episode"] + (old["state"] != "OPEN") if old else 0
        require(payload["episode"] == expected_episode, "Issue episode mismatch")
        state["issues"][issue_id] = {"state": "OPEN", "episode": expected_episode,
            "failed": old["failed"] if old else 0, "anchor": copy.deepcopy(payload["anchor"])}
        invalidate(state, advance=True)
        if state["ever_passed"]:
            latch_owned_stop(state, "late", "POST_COMPLETION_REOPEN")
    elif kind == "RepairFailureCharged":
        require(state["attempts"][payload["attempt_id"]]["repair"], "Initial attempt is not a failed repair")
        key = [payload["attempt_id"], payload["issue_id"]]
        require(key not in state["charges"], "Failure already charged")
        issue = state["issues"][payload["issue_id"]]
        issue["failed"] += 1
        require(issue["failed"] == payload["issue_failed_after"], "Issue failure count mismatch")
        state["charges"].append(key)
    elif kind == "FixProposed":
        require(rights["edit"] and payload["attempt_id"] == state["attempt"], "Fix proposal outside editing")
        issue = state["issues"][payload["issue_id"]]
        issue["state"], issue["correction_proof"] = "FIX_PROPOSED", copy.deepcopy(payload["correction_proof"])
    elif kind == "ReceiptApplied":
        receipt = state["receipts"][payload["receipt_id"]]
        require(not receipt["applied"] and not receipt.get("rejected"), "Receipt not applicable")
        job = next(job for job in state["jobs"].values() if job["request_id"] == receipt["request_id"])
        result = payload["result"]
        require(result["request_id"] == job["request_id"] and result["revision"] == job["revision"], "Answer identity mismatch")
        adverse = result.get("verdict") in {"NEEDS_CHANGES", "NEEDS_EVIDENCE", "REQUIRES_USER_DECISION"} or result.get("outcome") == "FAIL"
        require(adverse or (job.get("exit_code") == 0 and job["status"] == "EXITED"), "Exit not successfully proved")
        receipt["applied"], receipt["result"] = True, copy.deepcopy(result)
        job["applied"] = True
        if result.get("outcome") == "PASS":
            require(job["kind"] == "VERIFICATION" and job["revision"] == state["revision"], "Stale verification")
            require(sorted(result["check_ids"]) == sorted(state["contract"]["required_checks"]), "Incomplete checks")
            for check in result["check_ids"]:
                state["checks"][check] = revision_key(state["revision"])
        elif result.get("verdict") == "CLEAR":
            require(job["kind"] == "REVIEW", "CLEAR belongs to a non-review job")
            # Receipt identity was checked against the immutable original job above.
            # A late answer can terminate that job without approving the current revision.
            receipt["approval_eligible"] = job["revision"] == state["revision"]
            if receipt["approval_eligible"]:
                state["clears"][job["role_id"]] = revision_key(state["revision"])
        else:
            invalidate(state)
            if result.get("verdict") in {"NEEDS_EVIDENCE", "REQUIRES_USER_DECISION"}:
                latch_owned_stop(state, payload["receipt_id"], "UNCLASSIFIABLE")
    elif kind == "ClosureAccepted":
        issue = state["issues"][payload["issue_id"]]
        require(event["revision"] == state["revision"] and payload["attempt_id"] == state["attempt"], "Closure target mismatch")
        require(issue["state"] in {"FIX_PROPOSED", "CLOSED"}
                and issue.get("correction_proof") == payload["correction_proof"], "No correction proof")
        current = revision_key(state["revision"])
        if issue["state"] == "CLOSED":
            require(rights["capture"], "Requalification requires current authority and verification")
            prior_closure = parse_json(issue["closure"])
            # Generation changes invalidate approval, not an unchanged recorded correction.
            # Changed content must instead carry an explicit new FixProposed record.
            require(prior_closure["revision_id"] == state["revision"]["revision_id"], "Changed revision needs fresh correction proof")
            require(prior_closure["assessment_generation"] < state["revision"]["assessment_generation"], "Closure is not stale")
        require(all(state["checks"].get(check) == current for check in state["contract"]["required_checks"]), "Closure lacks verification")
        require(all(state["clears"].get(role) == current for role in state["contract"]["required_roles"]), "Closure lacks independent CLEAR")
        covered_roles = set()
        for receipt_id in payload["verification_receipt_ids"] + payload["clear_receipt_ids"]:
            require(receipt_id in state["receipts"], "Closure evidence unavailable")
            require(state["receipts"][receipt_id]["applied"] and not state["receipts"][receipt_id].get("rejected"), "Closure references unapplied evidence")
            result = state["receipts"][receipt_id]["result"]
            require(result["revision"] == state["revision"], "Closure evidence stale")
            if receipt_id in payload["clear_receipt_ids"]:
                require(result.get("verdict") == "CLEAR" and payload["issue_id"] in result["covered_issue_ids"], "Issue not reviewed")
                require(state["receipts"][receipt_id].get("approval_eligible") is True, "Closure CLEAR is not eligible")
                job = next((job for job in state["jobs"].values() if job["request_id"] == result["request_id"]), None)
                require(job is not None and job["kind"] == "REVIEW", "Closure review identity unavailable")
                covered_roles.add(job["role_id"])
            else:
                require(result.get("outcome") == "PASS", "Closure evidence not successful")
        require(payload["verification_receipt_ids"] and payload["clear_receipt_ids"], "Closure references empty")
        require(covered_roles == set(state["contract"]["required_roles"]), "Closure review coverage incomplete")
        issue["state"], issue["closure"] = "CLOSED", current
    elif kind == "StopLatched":
        latch_owned_stop(state, payload["stop_id"], payload["reason"])
        state["pass_assessed"] = None
    elif kind == "StopResolved":
        require(payload["stop_id"] in state["stops"], "No such stop")
        require(state["stop_owners"].get(payload["stop_id"]) == {"kind": "safety"}, "Stop is not owner-resolvable")
        require(state["stops"][payload["stop_id"]] not in {"UNKNOWN_JOB", "EVIDENCE_CONFLICT", "UNCLASSIFIABLE"},
                "Irreducible stop requires separate evidence reconciliation")
        del state["stops"][payload["stop_id"]]
        invalidate(state, advance=True)
    elif kind == "ClockExpired":
        approval = state["approval"]
        require(approval and payload["interval_id"] == approval["interval_id"]
                and payload["deadline_uptime_ms"] == approval["deadline_uptime_ms"]
                and clock["boot_id"] == approval["boot_id"]
                and clock["uptime_ms"] >= approval["deadline_uptime_ms"], "Expiry does not match current approval")
        latch_owned_stop(state, payload["interval_id"], "DEADLINE")
        state["pass_assessed"] = None
    elif kind == "OwnershipTransferred":
        require(payload["previous_generation"] == state["writer_generation"] and payload["new_generation"] > state["writer_generation"],
                "Writer fencing invalid")
        state["writer_generation"] = payload["new_generation"]
    elif kind == "JobRetirementAccepted":
        raise Denied("UNKNOWN retirement disabled until isolation is independently verified")
    elif kind == "PassAssessed":
        require(rights["can_pass"] and event["revision"] == state["revision"], "Final PASS requirements not satisfied")
        require(payload["interval_id"] == state["approval"]["interval_id"], "PASS interval mismatch")
        require(not state["contract"].get("user_review_required") or payload["user_review_proof"] is not None, "Missing user review")
        state["pass_assessed"], state["ever_passed"] = revision_key(state["revision"]), True
    else:
        raise Denied("Unsupported event")
    return state
