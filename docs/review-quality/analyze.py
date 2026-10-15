"""Build treatment-blinded scoring packets and reproduce pilot aggregates."""

import argparse
from collections import defaultdict
import json
from pathlib import Path
import random


DIRECTORY = Path(__file__).resolve().parent


def read_json(path):
    """Load an experiment artifact as a structured UTF-8 value."""
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    """Write a deterministic, portable JSON artifact."""
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def admitted_receipts():
    """Read successful observations and exclude separately retained startup failures."""
    return [
        read_json(path)
        for path in sorted((DIRECTORY / "receipts").glob("*.json"))
        if not path.name.endswith(".failure.json")
    ]


def blind():
    """Remove host, treatment, stage, and timing labels before independent matching."""
    receipts = admitted_receipts()
    random.Random(138).shuffle(receipts)
    fixtures = read_json(DIRECTORY / "fixtures.json")["fixtures"]
    packet = {
        "fixtures": [
            {key: fixture[key] for key in (
                "id", "requirements", "base_files", "candidate_files", "ground_truth"
            )}
            for fixture in fixtures
        ],
        "observations": [],
    }
    mapping = []
    for position, receipt in enumerate(receipts, 1):
        observation_id = f"O{position:03d}"
        fixture_id = receipt["label"].split("-")[2]
        findings = []
        finding_mapping = {}
        for section in ("free_findings", "checklist_findings"):
            for finding in receipt["result"][section]:
                finding_id = f"f{len(findings) + 1:03d}"
                anonymous_finding = dict(finding)
                anonymous_finding["id"] = finding_id
                findings.append(anonymous_finding)
                finding_mapping[finding_id] = {"section": section, "original_id": finding.get("id")}
        packet["observations"].append({
            "id": observation_id, "fixture_id": fixture_id, "findings": findings,
        })
        mapping.append({
            "observation_id": observation_id, "label": receipt["label"],
            "finding_mapping": finding_mapping,
        })
    write_json(DIRECTORY / "blind-packet.json", packet)
    write_json(DIRECTORY / "blinding-map.json", mapping)
    print(json.dumps({"observations": len(receipts), "findings": sum(len(item["findings"]) for item in packet["observations"])}))


def aggregate():
    """Reconcile every scored finding and aggregate paired quality and reviewer cost."""
    packet = read_json(DIRECTORY / "blind-packet.json")
    mapping = {item["observation_id"]: item for item in read_json(DIRECTORY / "blinding-map.json")}
    grades = read_json(DIRECTORY / "grades.json")["observations"]
    if len({grade["observation_id"] for grade in grades}) != len(grades):
        raise ValueError("Duplicate scoring observation")
    grades = {grade["observation_id"]: grade for grade in grades}
    observations = {item["id"]: item for item in packet["observations"]}
    if set(grades) != set(observations):
        raise ValueError("Scoring observation inventory mismatch")
    fixtures = {item["id"]: item for item in read_json(DIRECTORY / "fixtures.json")["fixtures"]}
    receipts = {item["label"]: item for item in admitted_receipts()}
    sessions = [receipt["session_id"] for receipt in receipts.values()]
    if len(sessions) != len(set(sessions)):
        raise ValueError("Session reuse")
    # Combine independent phase observations into one paired treatment result.
    cells = defaultdict(lambda: {"matched": set(), "free_matched": set(), "checklist_matched": set(), "extras": [], "duplicates": [], "severity_overstatements": [], "optional_as_required": []})
    for observation_id, grade in grades.items():
        assignment = mapping[observation_id]
        label = assignment["label"]
        host, trial, fixture_id, arm, stage = label.split("-")
        cell = cells[(host, trial, fixture_id, arm)]
        truth = {item["id"]: item for item in fixtures[fixture_id]["ground_truth"]}
        finding_ids = {item["id"] for item in observations[observation_id]["findings"]}
        accounted = set()
        for match in grade["matches"]:
            truth_id = match["truth_id"]
            finding_id = match["finding_id"]
            if truth_id not in truth or finding_id not in finding_ids:
                raise ValueError("Invalid finding or ground-truth identity")
            cell["matched"].add(truth_id)
            section = assignment["finding_mapping"][finding_id]["section"]
            cell["free_matched" if section == "free_findings" else "checklist_matched"].add(truth_id)
            accounted.add(finding_id)
        for extra in grade["extras"]:
            if extra["finding_id"] not in finding_ids:
                raise ValueError("Unknown extra finding")
            accounted.add(extra["finding_id"])
            cell["extras"].append({"observation_id": observation_id, **extra})
        for duplicate in grade["duplicates"]:
            if duplicate["finding_id"] not in finding_ids:
                raise ValueError("Unknown duplicate finding")
            accounted.add(duplicate["finding_id"])
            cell["duplicates"].append({"observation_id": observation_id, **duplicate})
        if accounted != finding_ids:
            raise ValueError("Not every finding was scored: " + observation_id)
        for field in ("severity_overstatements", "optional_as_required"):
            cell[field].extend({"observation_id": observation_id, **item} for item in grade[field])
    paired = []
    quality = []
    for (host, trial, fixture_id, arm), cell in sorted(cells.items()):
        truth = fixtures[fixture_id]["ground_truth"]
        material = {item["id"] for item in truth if item["kind"] == "material"}
        outside = {item["id"] for item in truth if item["kind"] == "material" and item["checklist_relation"] == "outside"}
        severe = {item["id"] for item in truth if item["kind"] == "material" and item["severity"] == "P1"}
        minor = {item["id"] for item in truth if item["kind"] == "quality"}
        quality.append({
            "host": host, "trial": trial, "fixture": fixture_id, "arm": arm,
            "material_found": len(material & cell["matched"]), "material_total": len(material),
            "outside_found": len(outside & cell["matched"]), "outside_total": len(outside),
            "p1_misses": len(severe - cell["matched"]), "p1_total": len(severe),
            "quality_union_found": len(minor & cell["matched"]), "quality_total": len(minor),
            "quality_checklist_found": len(minor & cell["checklist_matched"]),
            "material_free_found": len(material & cell["free_matched"]),
            **{field: sorted(cell[field]) for field in ("matched", "free_matched", "checklist_matched")},
            **{field: cell[field] for field in ("extras", "duplicates", "severity_overstatements", "optional_as_required")},
        })
        if arm == "A":
            first = cell["matched"] & material
            combined = cells[(host, trial, fixture_id, "B")]["matched"] & material
            independent = cells[(host, trial, fixture_id, "C")]["matched"] & material
            paired.append({
                "host": host, "trial": trial, "fixture": fixture_id,
                "A_found_B_missed": sorted(first - combined),
                "B_missed_C_found": sorted(independent - combined),
                "B_found_C_missed": sorted(combined - independent),
                "A_found_C_missed": sorted(first - independent),
            })
    costs = []
    checklist_audit = []
    for host in ("codex", "claude"):
        for arm in ("A", "B", "C"):
            selected = [item for label, item in receipts.items() if label.startswith(host + "-") and label.split("-")[3] == arm]
            usage = defaultdict(int)
            for item in selected:
                for key, value in item["usage"].items():
                    if isinstance(value, (int, float)):
                        usage[key] += value
            costs.append({"host": host, "arm": arm, "launches": len(selected), "estimated_usd": sum(item["estimated_usd"] for item in selected), "elapsed_seconds": sum(item["elapsed_seconds"] for item in selected), "usage": dict(usage)})
    for label, receipt in sorted(receipts.items()):
        host, trial, fixture_id, arm, stage = label.split("-")
        if arm == "A" or stage == "free":
            continue
        expected = {item["id"]: item for item in fixtures[fixture_id]["checklist_expectations"]}
        actual_rows = receipt["result"]["checklist_results"]
        actual = {item["id"]: item for item in actual_rows}
        checklist_audit.append({
            "label": label, "row_count": len(actual_rows), "unique_ids": len(actual),
            "missing_ids": sorted(set(expected) - set(actual)), "extra_ids": sorted(set(actual) - set(expected)),
            "unverified_ids": sorted(identifier for identifier, item in actual.items() if "UNVERIFIED" in (item.get("result"), item.get("applicability"))),
            "applicability_disagreements": [identifier for identifier in expected.keys() & actual.keys() if expected[identifier]["applicability"] != actual[identifier].get("applicability")],
            "result_disagreements": [identifier for identifier in expected.keys() & actual.keys() if expected[identifier]["expected_result"] != actual[identifier].get("result")],
        })
    write_json(DIRECTORY / "summary.json", {"quality_cells": quality, "paired_material": paired, "costs": costs, "checklist_mechanical_audit": checklist_audit, "session_count": len(sessions), "unique_session_count": len(set(sessions))})
    print(json.dumps({"scored_observations": len(grades), "paired_cells": len(paired), "costs": costs}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("blind", "aggregate"))
    arguments = parser.parse_args()
    if arguments.operation == "blind":
        blind()
    else:
        aggregate()
