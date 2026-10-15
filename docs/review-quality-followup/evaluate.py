"""Prepare anonymous scoring and audit fixed reviewer receipts offline."""

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import random


DIRECTORY = Path(__file__).resolve().parent


def read_json(path):
    """Read an entire structured evidence value."""
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    """Persist portable structured evaluation output."""
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def receipts(interval):
    """Select complete individual observations while excluding auxiliary event logs."""
    selected = []
    for path in sorted((DIRECTORY / "receipts").glob("*.json")):
        if path.name.endswith((".events.json", ".execution.json", ".failure.json")):
            continue
        receipt = read_json(path)
        if receipt["measurement"] == interval:
            selected.append(receipt)
    return selected


def blind(interval):
    """Remove treatment labels, host, costs and timing before independent scoring."""
    observations = receipts(interval)
    random.Random("issue138-frozen-shuffle-" + interval).shuffle(observations)
    packet = []
    mapping = {}
    for index, receipt in enumerate(observations, 1):
        anonymous_id = f"O{index:03d}"
        mapping[anonymous_id] = receipt["label"]
        findings = receipt["result"]["free_findings"] + receipt["result"]["checklist_findings"]
        packet.append({
            "anonymous_id": anonymous_id, "findings": findings,
            "limitations": receipt["result"]["limitations"],
        })
    write_json(DIRECTORY / (interval + "-blind-packet.json"), {"observations": packet})
    write_json(DIRECTORY / (interval + "-blinding-map.json"), mapping)
    print(json.dumps({"anonymous_observations": len(packet)}))


def audit(interval):
    """Verify complete sessions, exact prompts, staged order and usage calculations."""
    manifest = read_json(DIRECTORY / "manifest.json")
    observations = receipts(interval)
    all_sessions = [receipt["session_id"] for scope in ("pilot", "main") for receipt in receipts(scope)]
    assert len(all_sessions) == len(set(all_sessions)), "session reused"
    expected = 4 if interval == "pilot" else 16
    assert len(observations) == expected, "incomplete interval"
    expected_ids = {"CRQ-" + str(number).zfill(3) for number in range(1, 8)}
    by_label = {receipt["label"]: receipt for receipt in observations}
    for receipt in observations:
        assert receipt["cli_exit"] == 0 and not receipt["tool_calls"]
        assert receipt["input_sha256"] == manifest["prompts"][receipt["stage"]]
        assert receipt["stdin_sha256"] == receipt["input_sha256"]
        declarations = receipt["result"]["coverage"]
        for expected_file in manifest["changed_files"]:
            assert any(
                (declaration.get("file", declaration.get("path")) == expected_file)
                if isinstance(declaration, dict) else
                (declaration == expected_file or declaration.startswith(expected_file + ":"))
                for declaration in declarations
            ), "declared file coverage missing"
        if receipt["stage"] in ("combined", "checklist"):
            identifiers = [row["id"] for row in receipt["result"]["checklist_results"]]
            assert len(identifiers) == 7 and set(identifiers) == expected_ids
        if receipt["stage"] == "checklist":
            prior = by_label[receipt["label"].replace("-checklist", "-free")]
            assert prior["finished_unix"] <= receipt["started_unix"]
        if receipt["host"] == "codex":
            usage = receipt["usage"]
            estimate = ((usage["input_tokens"] - usage["cached_input_tokens"]) * 2
                        + usage["cached_input_tokens"] * 0.1 + usage["output_tokens"] * 10) / 1_000_000
            assert abs(estimate - receipt["estimated_usd"]) < 1e-10
    result = {
        "interval": interval, "observations": len(observations), "unique_sessions_all_intervals": len(all_sessions),
        "complete_prompt_and_file_coverage": True, "no_observed_tool_use": True,
        "checklist_inventory_complete": True, "sequential_c_phases": True,
        "codex_usage_estimates_recomputed": True,
        "evidence_sha256": hashlib.sha256((DIRECTORY / "artifacts/evidence.json").read_bytes()).hexdigest(),
        "limitations": ["Coverage is reviewer-declared; internal attention is unobservable.",
                        "Codex configured settings and Claude default effort are not effective-effort attestations."],
    }
    write_json(DIRECTORY / (interval + "-receipt-audit.json"), result)
    print(json.dumps(result))


def aggregate(interval):
    """Union independently matched causes only after anonymous scoring is complete."""
    observations = receipts(interval)
    mapping = read_json(DIRECTORY / (interval + "-blinding-map.json"))
    grades = read_json(DIRECTORY / (interval + "-grades.json"))["observations"]
    assert {grade["anonymous_id"] for grade in grades} == set(mapping)
    assert len(grades) == len(mapping)
    by_label = {mapping[grade["anonymous_id"]]: grade for grade in grades}
    cells = defaultdict(lambda: {"detected": set(), "stages": {}, "usd": 0, "seconds": 0, "usage": defaultdict(int),
                                "false_positives": 0, "severity_overstatements": 0, "optional_mandatory": 0})
    for receipt in observations:
        host, trial, arm, stage = receipt["label"].split("-")
        grade = by_label[receipt["label"]]
        detected = {match["defect_id"] for match in grade["matches"]}
        cell = cells[(host, trial, arm)]
        cell["detected"].update(detected)
        cell["stages"][stage] = sorted(detected)
        cell["usd"] += receipt["estimated_usd"]
        cell["seconds"] += receipt["elapsed_seconds"]
        for key, value in receipt["usage"].items():
            if isinstance(value, (int, float)):
                cell["usage"][key] += value
        for key in ("false_positives", "severity_overstatements", "optional_mandatory"):
            cell[key] += len(grade.get(key, []))
    output_cells = []
    for (host, trial, arm), cell in sorted(cells.items()):
        cell["detected"] = sorted(cell["detected"])
        cell["usage"] = dict(cell["usage"])
        output_cells.append({"host": host, "trial": trial, "arm": arm, **cell})
    host_totals = []
    for host in sorted({cell["host"] for cell in output_cells}):
        costs = {arm: sum(cell["usd"] for cell in output_cells if cell["host"] == host and cell["arm"] == arm)
                 for arm in ("A", "B", "C")}
        host_totals.append({"host": host, "costs_usd": costs, "c_over_b": costs["C"] / costs["B"]})
    write_json(DIRECTORY / (interval + "-summary.json"), {"cells": output_cells, "hosts": host_totals})
    print(json.dumps({"cells": output_cells, "hosts": host_totals}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("blind", "audit", "aggregate"))
    parser.add_argument("--interval", choices=("pilot", "main"), default="pilot")
    arguments = parser.parse_args()
    {"blind": blind, "audit": audit, "aggregate": aggregate}[arguments.operation](arguments.interval)
