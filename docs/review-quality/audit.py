"""Verify frozen inputs, session isolation, phase order, and receipt cost arithmetic."""

from collections import Counter
import json
from pathlib import Path
import subprocess

import run as pilot


DIRECTORY = Path(__file__).resolve().parent


def read_json(path):
    """Load one structured experiment artifact."""
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    """Audit recorded observations without exposing checklist text or running models."""
    manifest = read_json(DIRECTORY / "manifest.json")
    preregistration = json.loads(subprocess.check_output([
        "git", "show", "2464f41:docs/review-quality/manifest.json"
    ]))
    assert manifest["fixtures"] == preregistration["fixtures"]
    assert manifest["fixture_file_sha256"] == preregistration["fixture_file_sha256"]
    assert manifest["codex_settings"] == preregistration["codex_settings"]
    assert pilot.digest((DIRECTORY / "fixtures.json").read_bytes()) == manifest["fixture_file_sha256"]
    assert pilot.digest((DIRECTORY / "run.py").read_bytes()) == manifest["runner_sha256"]
    checklist_bytes = pilot.CHECKLIST.read_bytes()
    assert pilot.digest(checklist_bytes) == manifest["checklist_sha256"]
    fixtures = {item["id"]: item for item in read_json(DIRECTORY / "fixtures.json")["fixtures"]}
    identities = {item["id"]: item for item in manifest["fixtures"]}
    envelope_audit = []
    for identifier, fixture in fixtures.items():
        evidence = json.loads(pilot.frozen_evidence(fixture))
        assert "ground_truth" not in evidence and "checklist_expectations" not in evidence
        for stage in ("free", "combined", "checklist"):
            prompt = pilot.make_prompt(fixture, stage, checklist_bytes.decode("utf-8"))
            assert pilot.digest(prompt) == identities[identifier][stage + "_prompt_sha256"]
            assert not any(item["id"] in prompt for item in fixture["ground_truth"])
            if stage == "free":
                assert "checklist" not in prompt.lower()
        envelope_audit.append({"fixture": identifier, "truth_excluded": True, "free_prompt_no_checklist": True})
    receipts = [read_json(path) for path in sorted((DIRECTORY / "receipts").glob("*.json")) if not path.name.endswith(".failure.json")]
    indexed = {item["label"]: item for item in receipts}
    assert len(indexed) == len(receipts)
    sessions = [item["session_id"] for item in receipts]
    assert len(set(sessions)) == len(sessions)
    order_checks = 0
    arithmetic_checks = 0
    for receipt in receipts:
        host, trial, fixture_id, arm, stage = receipt["label"].split("-")
        assert receipt["input_sha256"] == identities[fixture_id][stage + "_prompt_sha256"]
        assert receipt["tool_calls"] == []
        expected_files = [
            name for name in set(fixtures[fixture_id]["base_files"]) | set(fixtures[fixture_id]["candidate_files"])
            if fixtures[fixture_id]["base_files"].get(name) != fixtures[fixture_id]["candidate_files"].get(name)
        ]
        pilot.verify_coverage(receipt["result"]["coverage"], expected_files)
        if host == "codex":
            assert [receipt["configured_model"], receipt["configured_effort"]] == manifest["codex_settings"]
            usage = receipt["usage"]
            assert usage.get("cache_write_input_tokens", 0) == 0
            expected_cost = ((usage["input_tokens"] - usage.get("cached_input_tokens", 0)) * 2 + usage.get("cached_input_tokens", 0) * 0.1 + usage["output_tokens"] * 10) / 1_000_000
            assert abs(expected_cost - receipt["estimated_usd"]) < 1e-12
            arithmetic_checks += 1
        if arm == "C" and stage == "checklist":
            preceding = indexed[f"{host}-{trial}-{fixture_id}-C-free"]
            assert preceding["started_unix"] + preceding["elapsed_seconds"] <= receipt["started_unix"] + 0.05
            order_checks += 1
    diagnostics = [read_json(path) for path in (DIRECTORY / "diagnostics").glob("*.json")]
    assert not set(sessions) & {item["session_id"] for item in diagnostics}
    result = {
        "frozen_fixture_and_prompt_identities_preserved": True,
        "observations": len(receipts), "unique_sessions": len(set(sessions)),
        "observations_by_host": dict(Counter(item["host"] for item in receipts)),
        "no_reviewer_tool_calls": True, "complete_declared_coverage": True,
        "independent_C_order_checks": order_checks, "codex_cost_arithmetic_checks": arithmetic_checks,
        "reviewer_envelopes": envelope_audit,
        "excluded_paid_duplicates": len(diagnostics),
        "excluded_duplicate_estimated_usd": sum(item["estimated_usd"] for item in diagnostics),
        "canonical_prompt_hash_note": "Manifest hashes LF text; original Windows stdin writes CRLF. Canonical inputs and newline translation are constant across observations.",
        "limitations": ["Declared coverage and explicit completion do not prove every line received equal cognitive attention", "Effective backend effort is not independently emitted", "One recovered child exit code and two process durations are not exact"],
    }
    pilot.write_json(DIRECTORY / "audit-results.json", result)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
