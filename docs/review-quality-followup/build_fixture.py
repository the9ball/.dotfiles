"""Build an offline reservation review fixture and isolated evaluator evidence."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap


BASE_FILES = {
    "catalog.py": '''
"""Resolve customer product references to inventory identifiers."""


class Catalog:
    def __init__(self, aliases):
        """Copy the supported product aliases."""
        self.aliases = dict(aliases)

    def resolve(self, product):
        """Return the inventory identifier or raise KeyError for unknown products."""
        return self.aliases[product]
''',
    "repository.py": '''
"""SQLite persistence for stock, reservations, and scheduled releases."""
import sqlite3


class Repository:
    def __init__(self, stock):
        """Initialize an in-memory store with the supplied available inventory."""
        self.connection = sqlite3.connect(":memory:")
        self.connection.executescript("""
            CREATE TABLE stock(sku TEXT PRIMARY KEY, available INTEGER NOT NULL);
            CREATE TABLE reservations(
                id INTEGER PRIMARY KEY, sku TEXT, quantity INTEGER,
                expires_at INTEGER, active INTEGER DEFAULT 1);
            CREATE TABLE releases(
                reservation_id INTEGER PRIMARY KEY, quantity INTEGER, due INTEGER);
        """)
        self.connection.executemany("INSERT INTO stock VALUES (?, ?)", stock.items())
        self.connection.commit()

    def available(self, sku):
        """Read the current available units for one inventory identifier."""
        return self.connection.execute(
            "SELECT available FROM stock WHERE sku = ?", (sku,)
        ).fetchone()[0]

    def move_stock(self, sku, quantity):
        """Apply a signed inventory movement in the caller's transaction."""
        self.connection.execute(
            "UPDATE stock SET available = available + ? WHERE sku = ?",
            (quantity, sku),
        )

    def create(self, sku, quantity, expires_at):
        """Store a reservation and its scheduled release, returning its identifier."""
        cursor = self.connection.execute(
            "INSERT INTO reservations(sku, quantity, expires_at) VALUES (?, ?, ?)",
            (sku, quantity, expires_at),
        )
        reservation_id = cursor.lastrowid
        self.connection.execute(
            "INSERT INTO releases VALUES (?, ?, ?)",
            (reservation_id, quantity, expires_at),
        )
        return reservation_id

    def get(self, reservation_id):
        """Return a reservation record, raising KeyError when it does not exist."""
        row = self.connection.execute(
            "SELECT id, sku, quantity, expires_at, active FROM reservations WHERE id = ?",
            (reservation_id,),
        ).fetchone()
        if row is None:
            raise KeyError(reservation_id)
        return dict(zip(("id", "sku", "quantity", "expires_at", "active"), row))

    def close(self, reservation_id):
        """Deactivate a reservation and remove its outstanding release."""
        self.connection.execute(
            "UPDATE reservations SET active = 0 WHERE id = ?", (reservation_id,)
        )
        self.connection.execute(
            "DELETE FROM releases WHERE reservation_id = ?", (reservation_id,)
        )

    def replacement_capacity(self, reservation_id):
        """Return total units available when replacing an existing reservation."""
        reservation = self.get(reservation_id)
        return self.available(reservation["sku"]) + reservation["quantity"]
''',
    "expiry.py": '''
"""Process scheduled inventory releases on the service dispatch thread."""


def expire(repository, now):
    """Return units for active reservations due at the supplied integer timestamp."""
    with repository.connection:
        due = repository.connection.execute(
            "SELECT reservation_id, quantity FROM releases WHERE due <= ?", (now,)
        ).fetchall()
        for reservation_id, quantity in due:
            reservation = repository.get(reservation_id)
            if reservation["active"]:
                repository.move_stock(reservation["sku"], quantity)
            repository.close(reservation_id)
    return len(due)
''',
    "allocation.py": '''
"""Inventory allocation operations sharing one dispatch boundary."""


class Allocator:
    def __init__(self, repository):
        """Bind allocation operations to a repository."""
        self.repository = repository

    def reserve(self, sku, quantity, expires_at):
        """Reserve positive units or raise ValueError when stock is insufficient."""
        if quantity <= 0 or quantity > self.repository.available(sku):
            raise ValueError("quantity unavailable")
        self.repository.move_stock(sku, -quantity)
        return self.repository.create(sku, quantity, expires_at)

    def reserve_many(self, lines, expires_at):
        """Reserve resolved lines together, rolling back every line on failure."""
        with self.repository.connection:
            identifiers = []
            for sku, quantity in lines:
                identifiers.append(self.reserve(sku, quantity, expires_at))
            return identifiers

    def replace(self, reservation_id, quantity):
        """Replace an active reservation with a newly allocated quantity."""
        with self.repository.connection:
            reservation = self.repository.get(reservation_id)
            if not reservation["active"]:
                raise ValueError("reservation inactive")
            if quantity <= 0 or quantity > self.repository.replacement_capacity(reservation_id):
                raise ValueError("quantity unavailable")
            self.repository.move_stock(reservation["sku"], reservation["quantity"])
            self.repository.close(reservation_id)
            return self.reserve(reservation["sku"], quantity, reservation["expires_at"])
''',
    "api.py": '''
"""Validate external requests and resolve catalog references."""
from allocation import Allocator


class ReservationAPI:
    def __init__(self, repository, catalog):
        """Connect request handling to catalog and inventory services."""
        self.repository = repository
        self.catalog = catalog
        self.allocator = Allocator(repository)

    def reserve(self, product, quantity, expires_at):
        """Return a reservation object for one customer product reference."""
        with self.repository.connection:
            identifier = self.allocator.reserve(
                self.catalog.resolve(product), quantity, expires_at
            )
            return self.repository.get(identifier)

    def replace(self, reservation_id, quantity):
        """Return the replacement reservation with the requested positive quantity."""
        identifier = self.allocator.replace(reservation_id, quantity)
        return self.repository.get(identifier)
''',
    "README.md": '''
# Inventory reservations

The service uses Python's standard-library SQLite driver. A single dispatch
thread calls requests and the expiry worker; timestamps are integer seconds.
Catalog aliases may map several customer product references to one stock SKU.

`reserve(product, quantity, expires_at)` returns a reservation object with
`id`, `sku`, `quantity`, `expires_at`, and `active` fields.
`replace(id, quantity)` returns the replacement reservation object.

''',
    "test_reservations.py": '''
"""Public regression coverage for inventory reservation workflows."""
import unittest
from api import ReservationAPI
from catalog import Catalog
from expiry import expire
from repository import Repository


class ReservationTests(unittest.TestCase):
    def setUp(self):
        """Create a catalog and inventory for each independent test."""
        self.repository = Repository({"A": 10, "B": 7})
        self.api = ReservationAPI(self.repository, Catalog({"red": "A", "blue": "B"}))

    def tearDown(self):
        """Close the test database."""
        self.repository.connection.close()

    def test_single_reservation(self):
        """Single requests retain their object response and inventory movement."""
        reservation = self.api.reserve("red", 3, 100)
        self.assertEqual(reservation["quantity"], 3)
        self.assertEqual(self.repository.available("A"), 7)

    def test_expiry_is_repeatable(self):
        """A due reservation returns inventory only once."""
        self.api.reserve("red", 3, 100)
        self.assertEqual(expire(self.repository, 99), 0)
        self.assertEqual(expire(self.repository, 100), 1)
        self.assertEqual(expire(self.repository, 101), 0)
        self.assertEqual(self.repository.available("A"), 10)

    def test_distinct_products(self):
        """Resolved distinct products reserve their respective inventory."""
        identifiers = self.api.allocator.reserve_many([("A", 2), ("B", 3)], 100)
        self.assertEqual(len(identifiers), 2)
        self.assertEqual(self.repository.available("A"), 8)
        self.assertEqual(self.repository.available("B"), 4)

    def test_batch_rolls_back(self):
        """Failure leaves all inventory and reservations unchanged."""
        with self.assertRaises(ValueError):
            self.api.allocator.reserve_many([("A", 2), ("B", 8)], 100)
        self.assertEqual(self.repository.available("A"), 10)
        self.assertEqual(self.repository.connection.execute(
            "SELECT COUNT(*) FROM reservations"
        ).fetchone()[0], 0)

    def test_replace_quantity(self):
        """Changing a reservation updates its quantity and available units."""
        original = self.api.reserve("red", 4, 100)
        replacement = self.api.replace(original["id"], 2)
        self.assertEqual(replacement["quantity"], 2)
        self.assertEqual(self.repository.available("A"), 8)

    def test_invalid_quantity(self):
        """Nonpositive quantities leave inventory unchanged."""
        with self.assertRaises(ValueError):
            self.api.reserve("red", 0, 100)
        self.assertEqual(self.repository.available("A"), 10)
''',
}

REQUIREMENTS = """Add customer-facing batch reservation requests and allow quantities to be
adjusted while preserving the reservation identifier. Batch input is an ordered
list of {product, quantity} lines with one expires_at timestamp. Return an items
array containing each reservation and its input line position. Requests are
all-or-nothing. Preserve the existing single-reservation API and replacement
entry point. Keep the standard-library SQLite implementation and existing
catalog alias contract. Requests and scheduled expiry run on a single dispatch
thread, with integer timestamps. Quantity changes apply to active reservations
before their expiry; retain their deadline. Existing callers can continue using
the expiry worker and reading available inventory.
Every named Python function and method, including private helpers and tests,
must have a docstring describing its role and relevant caller contract.
"""

PRIVATE_TESTS = '''
"""Evaluator-only invariant checks, never included in the review repository."""
import unittest
from api import ReservationAPI
from catalog import Catalog
from expiry import expire
from repository import Repository


class InvariantTests(unittest.TestCase):
    def test_alias_inventory(self):
        """Aggregate alias demand cannot exceed inventory."""
        repository = Repository({"A": 5})
        api = ReservationAPI(repository, Catalog({"red": "A", "scarlet": "A"}))
        with self.assertRaises(ValueError):
            if hasattr(api, "reserve_batch"):
                api.reserve_batch([{"product": "red", "quantity": 3},
                                   {"product": "scarlet", "quantity": 3}], 100)
            else:
                api.allocator.reserve_many([("A", 3), ("A", 3)], 100)
        self.assertEqual(repository.available("A"), 5)

    def test_adjusted_expiry(self):
        """Expiry restores the current reservation quantity."""
        repository = Repository({"A": 10})
        api = ReservationAPI(repository, Catalog({"red": "A"}))
        original = api.reserve("red", 4, 100)
        api.replace(original["id"], 2)
        expire(repository, 100)
        self.assertEqual(repository.available("A"), 10)
'''


def normalized(source):
    """Return embedded source as UTF-8-compatible LF text with a final newline."""
    return textwrap.dedent(source).lstrip("\n").rstrip() + "\n"


def candidate_files(base):
    """Construct the batch and in-place adjustment implementation."""
    files = dict(base)
    files["README.md"] += "\nBatch responses use a top-level `reservations` array of reservation objects.\n"
    old = '''        with self.repository.connection:
            identifiers = []
            for sku, quantity in lines:
                identifiers.append(self.reserve(sku, quantity, expires_at))
            return identifiers'''
    new = '''        with self.repository.connection:
            available = {sku: self.repository.available(sku) for sku, _ in lines}
            for sku, quantity in lines:
                if quantity <= 0 or quantity > available[sku]:
                    raise ValueError("quantity unavailable")
            identifiers = []
            for sku, quantity in lines:
                self.repository.move_stock(sku, -quantity)
                identifiers.append(self.repository.create(sku, quantity, expires_at))
            return identifiers'''
    files["allocation.py"] = files["allocation.py"].replace(old, new)
    start = files["allocation.py"].index("    def replace(")
    files["allocation.py"] = files["allocation.py"][:start] + normalized('''
    def replace(self, reservation_id, quantity):
        """Adjust positive units on an active reservation while retaining its identity."""
        with self.repository.connection:
            reservation = self.repository.get(reservation_id)
            if not reservation["active"]:
                raise ValueError("reservation inactive")
            difference = quantity - reservation["quantity"]
            if quantity <= 0 or difference > self.repository.available(reservation["sku"]):
                raise ValueError("quantity unavailable")
            self.repository.move_stock(reservation["sku"], -difference)
            self.repository.connection.execute(
                "UPDATE reservations SET quantity = ? WHERE id = ?",
                (quantity, reservation_id),
            )
            return reservation_id
''')
    # Preserve class indentation after normalizing the standalone method block.
    prefix, method = files["allocation.py"].split("def replace(", 1)
    files["allocation.py"] = prefix + "    def replace(" + method.replace("\n", "\n    ").rstrip() + "\n"
    files["api.py"] += '\n' + textwrap.indent(normalized('''
def reserve_batch(self, lines, expires_at):
    """Return reserved items in request order with their original line positions."""
    resolved = [(self.catalog.resolve(line["product"]), line["quantity"]) for line in lines]
    identifiers = self.allocator.reserve_many(resolved, expires_at)
    return {"items": [dict(self.repository.get(identifier), line=position)
                      for position, identifier in enumerate(identifiers)]}
'''), "    ")
    files["test_reservations.py"] += '\n' + textwrap.indent(normalized('''
def test_batch_response(self):
    """Public batch requests retain line positions and reservation records."""
    response = self.api.reserve_batch(
        [{"product": "red", "quantity": 2}, {"product": "blue", "quantity": 3}], 100
    )
    self.assertEqual([item["line"] for item in response["items"]], [0, 1])
    self.assertEqual([item["quantity"] for item in response["items"]], [2, 3])

def test_quantity_identity(self):
    """In-place quantity changes retain the original reservation identifier."""
    original = self.api.reserve("red", 4, 100)
    changed = self.api.replace(original["id"], 5)
    self.assertEqual(changed["id"], original["id"])
    self.assertEqual(self.repository.available("A"), 5)
'''), "    ")
    return files


def execute(arguments, directory, environment, check=True):
    """Run an explicit command, retaining output for artifact verification."""
    result = subprocess.run(arguments, cwd=directory, env=environment, text=True,
                            capture_output=True, encoding="utf-8")
    if check and result.returncode:
        raise RuntimeError(f"{arguments}: {result.stdout}\n{result.stderr}")
    recorded = ["python" if value == sys.executable else value for value in arguments]
    stdout, stderr = result.stdout, result.stderr
    for spelling in {str(directory), str(directory).replace("\\", "/"),
                     str(directory).replace("/", "\\")}:
        stdout = stdout.replace(spelling, "<fixture>")
        stderr = stderr.replace(spelling, "<fixture>")
    return {"command": recorded, "returncode": result.returncode,
            "stdout": stdout, "stderr": stderr}


def write_files(directory, files):
    """Write only fixture-owned files into the isolated repository."""
    for name, source in files.items():
        (directory / name).write_text(source, encoding="utf-8", newline="\n")


def write_json(path, value):
    """Serialize an artifact deterministically using UTF-8 and LF."""
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8", newline="\n")


def build(output):
    """Create real commit history, public evidence, and isolated private results."""
    output.mkdir(parents=True, exist_ok=True)
    base = {name: normalized(source) for name, source in BASE_FILES.items()}
    candidate = candidate_files(base)
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith("GIT_") and key != "PYTHONPATH"}
    environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                       GIT_AUTHOR_NAME="Inventory Team", GIT_AUTHOR_EMAIL="inventory@example.test",
                       GIT_COMMITTER_NAME="Inventory Team",
                       GIT_COMMITTER_EMAIL="inventory@example.test",
                       GIT_AUTHOR_DATE="2026-01-15T10:00:00+0000",
                       GIT_COMMITTER_DATE="2026-01-15T10:00:00+0000",
                       PYTHONDONTWRITEBYTECODE="1")
    verification = []
    reproduction = {}
    with tempfile.TemporaryDirectory(prefix="inventory-review-") as temporary:
        directory = Path(temporary)
        execute(["git", "init", "--initial-branch=main", "--template="], directory, environment)
        execute(["git", "config", "core.autocrlf", "false"], directory, environment)
        execute(["git", "config", "core.hooksPath", str(directory / "no-hooks")], directory, environment)
        commits = []
        for revision, files, subject in (
            ("base", base, "feat: add inventory reservations and scheduled expiry"),
            ("candidate", candidate, "feat: add batch requests and retain reservation identity"),
        ):
            write_files(directory, files)
            public = execute([sys.executable, "-B", "-m", "unittest", "-v", "test_reservations"], directory, environment)
            public["revision"] = revision
            verification.append(public)
            execute(["git", "add", "--", *files], directory, environment)
            execute(["git", "-c", "commit.gpgsign=false", "commit", "-m", subject], directory, environment)
            sha = execute(["git", "rev-parse", "HEAD"], directory, environment)["stdout"].strip()
            patch = execute(["git", "show", "--format=fuller", "--no-ext-diff", sha], directory, environment)["stdout"]
            commits.append({"sha": sha, "subject": subject, "patch": patch})
            (directory / "private_checks.py").write_text(normalized(PRIVATE_TESTS), encoding="utf-8", newline="\n")
            checks = {}
            for name in ("test_alias_inventory", "test_adjusted_expiry"):
                result = execute([sys.executable, "-B", "-m", "unittest", "-v",
                                  "private_checks.InvariantTests." + name], directory, environment, False)
                assert result["returncode"] == (0 if revision == "base" else 1), result
                assert "ERROR" not in result["stderr"], result
                checks[name] = result
            reproduction[revision] = checks
            (directory / "private_checks.py").unlink()
        base_sha, candidate_sha = [commit["sha"] for commit in commits]
        diff = execute(["git", "diff", "--no-ext-diff", base_sha, candidate_sha], directory, environment)["stdout"]
        bundle = output / "reservation.bundle"
        execute(["git", "bundle", "create", str(bundle.resolve()), "--all"], directory, environment)
        execute(["git", "bundle", "verify", str(bundle.resolve())], directory, environment)
    evidence = {"requirements": REQUIREMENTS, "base_sha": base_sha,
                "candidate_sha": candidate_sha,
                "changed_files": [name for name in base if base[name] != candidate[name]],
                "base_files": base, "candidate_files": candidate, "commits": commits,
                "diff": diff, "verification": {"commands": [item["command"] for item in verification],
                                             "results": verification}}
    write_json(output / "evidence.json", evidence)
    write_json(output / "reproduction-results.json", reproduction)
    entries = [
        ("M1", "P1", "correctness", "allocation.py", "Independent line validation against initial stock ignores shared canonical SKU demand",
         "Two distinct aliases resolve to A, stock 5, quantities 3 and 3", "Request succeeds and available inventory becomes -1", "test_alias_inventory", "OUTSIDE",
         "Must connect catalog alias resolution with aggregate demand and identify accepted oversubscription; generic validation complaints do not match"),
        ("M2", "P2", "correctness", "allocation.py", "In-place quantity update leaves releases.quantity at its creation snapshot",
         "Reserve 4, adjust to 2, expire at the retained deadline", "Expiry restores 4 instead of 2, leaving available stock 12 from initial 10", "test_adjusted_expiry", "OUTSIDE",
         "Must connect quantity update with expiry snapshot and incorrect inventory restoration; unsupported concurrency concerns do not match"),
        ("Q1", "P3", "documentation", "README.md", "Batch response documentation specifies reservations key while API returns items",
         "Consumer follows documented batch response key", "Consumer cannot locate returned reservations", None, "CRQ-004",
         "Must identify concrete reservations/items mismatch; general documentation requests do not match"),
        ("Q2", "P3", "dead-code", "repository.py", "replacement_capacity is an internal helper with no call sites or export mechanism",
         "Inspect all modules for replacement_capacity references", "Unused maintenance surface after replacement flow moved to quantity deltas", None, "CRQ-005",
         "Must name the unused helper and absence of references; speculative dead-code claims do not match"),
    ]
    truth = {"base_sha": base_sha, "candidate_sha": candidate_sha,
             "fixed_denominator": {"material": ["M1", "M2"], "quality": ["Q1", "Q2"]},
             "severity_semantics": {"P1": "Valid ordinary inputs can immediately oversell stock", "P2": "Supported adjustment followed by expiry corrupts inventory", "P3": "Documentation or maintainability issue without demonstrated inventory corruption"},
             "deduplication": "Deduplicate by causal mechanism; alias spellings and increase/decrease expiry cases are variants, not new findings. Record verified novel findings separately without changing the frozen denominator.",
             "entries": [], "private_reproduction_source": normalized(PRIVATE_TESTS),
             "bundle_sha256": hashlib.sha256(bundle.read_bytes()).hexdigest(),
             "source_sha256": hashlib.sha256(json.dumps(candidate, sort_keys=True).encode()).hexdigest()}
    for identifier, severity, category, path, cause, trigger, impact, test, checklist, matching in entries:
        truth["entries"].append({"id": identifier, "severity": severity, "category": category,
                                 "cause": cause, "trigger": trigger, "impact": impact,
                                 "reproduction": test or "Static full-repository inspection",
                                 "affected_code": path, "commit": candidate_sha,
                                 "checklist_relation": checklist,
                                 "checklist_rationale": (
                                     "The checklist covers naming, structure, dependencies, documentation, "
                                     "and unused code; this inventory invariant requires behavioral reasoning "
                                     "across modules and is outside those quality rows."
                                     if checklist == "OUTSIDE" else
                                     "The finding directly concerns the documentation row."
                                     if checklist == "CRQ-004" else
                                     "The finding directly concerns the unused-code row."
                                 ),
                                 "expected_finding": cause + "; " + impact,
                                 "matching_rules_and_near_misses": matching})
    write_json(output / "truth.json", truth)
    return {"base_sha": base_sha, "candidate_sha": candidate_sha, "output": str(output)}


def main():
    """Parse an explicit output location and build the fixture on request."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).parent / "artifacts")
    arguments = parser.parse_args()
    print(json.dumps(build(arguments.output)))


if __name__ == "__main__":
    main()
