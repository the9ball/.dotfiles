"""Deterministically validate seeded fixture behavior without reviewer calls."""

import ast
import json
import tempfile
from pathlib import Path


def load_module(source, filename):
    """Compile a trusted local fixture into an isolated namespace."""
    namespace = {"__name__": "fixture_module"}
    exec(compile(source, filename, "exec"), namespace)
    return namespace


class Transport:
    """Capture batches or raise a configured transport exception."""

    def __init__(self, error=None):
        """Initialize recorded calls and the optional failure."""
        self.error = error
        self.batches = []

    def send(self, batch):
        """Record an atomic send unless the configured error is raised."""
        if self.error is not None:
            raise self.error
        self.batches.append(list(batch))


class Database:
    """Supply deterministic tenant-specific report metadata."""

    def __init__(self, records):
        """Retain records indexed by tenant and report identifier."""
        self.records = records
        self.calls = []

    def get_report(self, tenant, report_id):
        """Record an ownership-scoped lookup and return a fresh record."""
        self.calls.append((tenant, report_id))
        return dict(self.records[(tenant, report_id)])


class AuditRepository:
    """Return an ordered copy of one tenant's audit events."""

    def __init__(self, records):
        """Retain event lists indexed by tenant."""
        self.records = records

    def events_for(self, tenant):
        """Read only the requested tenant's events."""
        return [dict(event) for event in self.records[tenant]]


def observe(identifier, baseline, candidate, expected):
    """Verify a deterministic regression and emit a machine-readable result."""
    assert baseline == expected, (identifier, "baseline", baseline, expected)
    assert candidate != expected, (identifier, "candidate did not fail", candidate)
    print(json.dumps({
        "id": identifier,
        "status": "expected_failure_observed",
        "baseline": baseline,
        "candidate": candidate,
        "expected": expected,
    }, sort_keys=True))


def check_dispatch(fixture):
    """Reproduce interface, tail-batch, and exception regressions separately."""
    modules = [
        load_module(fixture[version]["dispatch.py"], "dispatch.py")
        for version in ("base_files", "candidate_files")
    ]
    interface_results = []
    boundary_results = []
    exception_results = []
    for module in modules:
        queue = module["NoticeQueue"](Transport(), batch_size=2)
        service = module["DeliveryService"](queue)
        interface_results.append(module["command_response"](
            service, [{"to": "a@example.test", "body": "one"},
                      {"to": "b@example.test", "body": "two"}]
        ))
        queue = module["NoticeQueue"](Transport(), batch_size=2)
        queue.enqueue("a@example.test", "one")
        queue.flush()
        boundary_results.append(module["pending_count"](queue))
        queue = module["NoticeQueue"](Transport(ValueError("invalid payload")), 1)
        queue.enqueue("a@example.test", "invalid")
        try:
            queue.flush()
        except ValueError:
            exception_results.append("ValueError")
        else:
            exception_results.append("no exception")
    observe("F1-M1", *interface_results, {"count": 2, "ids": [1, 2]})
    observe("F1-M2", *boundary_results, 0)
    observe("F1-M3", *exception_results, "ValueError")


def check_reports(fixture):
    """Reproduce tenant leakage, sibling traversal, and stale rotation state."""
    tenant_results = []
    containment_results = []
    rotation_results = []
    with tempfile.TemporaryDirectory(prefix="review-fixture-") as directory:
        storage = Path(directory) / "exports"
        sibling = Path(directory) / "exports-private"
        storage.mkdir()
        sibling.mkdir()
        (storage / "alpha.csv").write_text("alpha", encoding="utf-8")
        (storage / "beta.csv").write_text("beta", encoding="utf-8")
        (sibling / "secret.csv").write_text("secret", encoding="utf-8")
        records = {
            ("alpha", 7): {"path": "alpha.csv", "filename": "alpha.csv"},
            ("beta", 7): {"path": "beta.csv", "filename": "beta.csv"},
            ("alpha", 8): {
                "path": "../exports-private/secret.csv", "filename": "secret.csv"
            },
        }
        for version in ("base_files", "candidate_files"):
            module = load_module(fixture[version]["reports.py"], "reports.py")
            database = Database(records)
            service = module["ReportService"](
                module["ReportRepository"](database), storage
            )
            module["download_response"](service, {"tenant": "alpha"}, 7)
            response = module["download_response"](service, {"tenant": "beta"}, 7)
            tenant_results.append(response["body"].decode("utf-8"))
            try:
                escaped = service.download("alpha", 8)
            except PermissionError:
                containment_results.append("PermissionError")
            else:
                containment_results.append(escaped["body"].decode("utf-8"))
            service = module["ReportService"](
                module["ReportRepository"](Database(records)), storage
            )
            service.download("alpha", 7)
            replacement = Database({
                ("alpha", 7): {"path": "beta.csv", "filename": "beta.csv"}
            })
            module["rotate_connection"](service, replacement)
            rotation_results.append(service.download("alpha", 7)["body"].decode())
    observe("F3-M1", *tenant_results, "beta")
    observe("F3-M2", *containment_results, "PermissionError")
    observe("F3-M3", *rotation_results, "beta")


def check_quality(fixture, mixed_fixture):
    """Confirm behavior stability and structural presence of quality seeds."""
    records = [
        {"sku": " A ", "warehouse": "east", "quantity": 4},
        {"sku": "A", "warehouse": "east", "quantity": -1},
        {"sku": "B", "warehouse": "west", "quantity": 0},
        {"sku": "C", "warehouse": "east", "quantity": -2},
    ]
    expected = "warehouse\\tsku\\tquantity\\neast\\tA\\t3\\neast\\tC\\t-2\\n"
    expected = expected.replace("\\t", "\t").replace("\\n", "\n")
    results = []
    for version in ("base_files", "candidate_files"):
        module = load_module(fixture[version]["inventory.py"], "inventory.py")
        results.append(module["format_digest"](module["build_digest"](records)))
    assert results == [expected, expected], results
    source = fixture["candidate_files"]["inventory.py"]
    tree = ast.parse(source)
    functions = {
        node.name: node for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef)
    }
    digest_names = {
        node.id for node in ast.walk(functions["build_digest"])
        if isinstance(node, ast.Name)
    }
    assert "x" in digest_names
    assert "comma-separated" in ast.get_docstring(functions["format_digest"])
    assert not any(
        isinstance(node, ast.Name) and node.id == "_legacy_header"
        for node in ast.walk(tree)
    )
    mixed_tree = ast.parse(mixed_fixture["candidate_files"]["reports.py"])
    assert any(
        isinstance(node, ast.Name) and node.id == "zz"
        for node in ast.walk(mixed_tree)
    )
    assert not any(
        isinstance(node, ast.Name) and node.id == "_format_content_disposition"
        for node in ast.walk(mixed_tree)
    )
    for identifier in ("F2-Q1", "F2-Q2", "F2-Q3", "F3-Q1", "F3-Q2"):
        print(json.dumps({"id": identifier, "status": "quality_seed_confirmed"}))
    print(json.dumps({"id": "F2-behavior", "status": "pass"}))


def check_clean(fixture):
    """Exercise filtered pagination, compatibility, isolation, and boundaries."""
    records = {
        "alpha": [
            {"id": 1, "type": "login", "message": "one"},
            {"id": 2, "type": "export", "message": "two"},
            {"id": 3, "type": "login", "message": "three"},
            {"id": 4, "type": "export", "message": "four"},
            {"id": 5, "type": "login", "message": "five"},
        ],
        "beta": [{"id": 9, "type": "login", "message": "private"}],
    }
    base = load_module(fixture["base_files"]["audit.py"], "audit.py")
    candidate = load_module(fixture["candidate_files"]["audit.py"], "audit.py")
    endpoints = []
    for module in (base, candidate):
        reader = module["AuditReader"](AuditRepository(records))
        endpoints.append(module["AuditEndpoint"](reader))
    session = {"tenant": "alpha"}
    assert endpoints[0].get(session, {}) == endpoints[1].get(session, {})
    endpoint = endpoints[1]
    first = endpoint.get(session, {"event_type": "login", "page_size": "2"})
    assert [event["id"] for event in first["events"]] == [1, 3]
    assert first["next_cursor"] == 3
    last = endpoint.get(session, {
        "event_type": "login", "page_size": "2", "after_id": "3"
    })
    assert [event["id"] for event in last["events"]] == [5]
    assert last["next_cursor"] is None
    assert endpoint.get(session, {"event_type": "unknown"})["events"] == []
    exact = endpoint.get(session, {"event_type": "export", "page_size": "2"})
    assert exact["next_cursor"] is None
    assert endpoint.get({"tenant": "beta"}, {})["events"][0]["id"] == 9
    exported = candidate["export_page"](
        endpoint, session, {"event_type": "export"}
    )
    assert exported == {"body": "two\nfour", "next_cursor": None}
    for value in (0, 101, True, 1.5):
        try:
            candidate["validate_page_size"](value)
        except ValueError:
            pass
        else:
            raise AssertionError(("invalid page size accepted", value))
    print(json.dumps({"id": "F4-clean", "status": "pass"}))


def main():
    """Load the fixed local fixtures and verify all evaluator claims."""
    fixture_path = Path(__file__).with_name("fixtures.json")
    data = json.loads(fixture_path.read_text(encoding="utf-8"))
    fixtures = {fixture["id"]: fixture for fixture in data["fixtures"]}
    assert data["schema_version"] == 1
    assert set(fixtures) == {"F1", "F2", "F3", "F4"}
    for fixture in fixtures.values():
        expectations = fixture["checklist_expectations"]
        assert [item["id"] for item in expectations] == [
            f"CRQ-{index:03d}" for index in range(1, 8)
        ]
        assert all(item["evidence"] for item in expectations)
        for version in ("base_files", "candidate_files"):
            for filename, source in fixture[version].items():
                tree = ast.parse(source, filename=filename)
                for node in ast.walk(tree):
                    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        assert ast.get_docstring(node), (fixture["id"], node.name)
    check_dispatch(fixtures["F1"])
    check_reports(fixtures["F3"])
    check_quality(fixtures["F2"], fixtures["F3"])
    check_clean(fixtures["F4"])
    print(json.dumps({"status": "pass", "material_defects": 6, "quality_seeds": 5}))


if __name__ == "__main__":
    main()
