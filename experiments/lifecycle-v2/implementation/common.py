"""Strict JSON and deterministic event encoding for the isolated v2 prototype."""

import hashlib
import os
import shutil
import json
import subprocess
import uuid
from pathlib import Path

MAX_INTEGER = 9007199254740991
ROOT = Path(__file__).resolve().parent
SCHEMA_PATH = ROOT.parent / "event-schema.schema.json"


class Denied(RuntimeError):
    """An operation has no admissible authority or violates a model invariant."""


class StorageFailure(RuntimeError):
    """Durability is uncertain and the current runtime must remain fail-closed."""


def unique_pairs(pairs):
    """Reject duplicate object keys before JSON parser normalization loses evidence."""
    result = {}
    for key, value in pairs:
        if key in result:
            raise Denied("Duplicate JSON key")
        result[key] = value
    return result


def check_json(value):
    """Constrain JSON to valid Unicode and the integer-only canonical profile."""
    if value is None or isinstance(value, bool):
        return
    if isinstance(value, str):
        value.encode("utf-8", errors="strict")
    elif isinstance(value, int):
        if abs(value) > MAX_INTEGER:
            raise Denied("Unsafe integer")
    elif isinstance(value, list):
        for item in value:
            check_json(item)
    elif isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str):
                raise Denied("Non-string JSON key")
            check_json(key)
            check_json(item)
    else:
        raise Denied("Unsupported JSON value")


def parse_json(raw):
    """Parse strict JSON bytes without tolerating duplicate keys or invalid scalars."""
    result = json.loads(raw, object_pairs_hook=unique_pairs)
    check_json(result)
    return result


def canonical(value):
    """Encode the integer-only RFC8785 profile with UTF-16 property ordering."""
    check_json(value)
    if isinstance(value, dict):
        # RFC8785 orders properties by UTF-16 code units, not Python code points.
        keys = sorted(value, key=lambda key: key.encode("utf-16-be"))
        return "{" + ",".join(canonical(key) + ":" + canonical(value[key]) for key in keys) + "}"
    if isinstance(value, list):
        return "[" + ",".join(canonical(item) for item in value) + "]"
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def digest(raw):
    """Return SHA256 of exact artifact bytes."""
    return hashlib.sha256(raw).hexdigest()


def identity():
    """Allocate an internal opaque UUID v4."""
    return str(uuid.uuid4())


def artifact(raw, media_type="application/json"):
    """Describe a blob without exposing its body or filesystem path."""
    return {"sha256": digest(raw), "bytes": len(raw), "media_type": media_type}


def revision(content="initial", generation=0):
    """Build a deterministic revision fixture; live source capture is separate."""
    fields = {name: digest((content if name == "content_sha256" else name).encode()) for name in (
        "content_sha256", "dependencies_sha256", "oracle_sha256", "protected_sha256",
        "source_contract_sha256", "review_contract_sha256")}
    return {"revision_id": digest(canonical(fields).encode()), **fields, "assessment_generation": generation}


class SchemaValidator:
    """Use the preinstalled full Draft2020-12 engine through a local-only worker."""

    def __init__(self, results_directory=None):
        """Require explicit metaschema success and retain bounded startup evidence."""
        destination = results_directory or os.environ.get("LIFECYCLE_V2_EVIDENCE_ROOT")
        if not destination:
            raise Denied("Explicit isolated schema evidence directory required")
        evidence_root = Path(destination).resolve()
        if not evidence_root.is_relative_to((ROOT / "results").resolve()):
            raise Denied("Schema evidence directory outside isolated results")
        self.directory = evidence_root / "workers" / identity()
        self.directory.mkdir(parents=True)
        self.stderr_log = open(self.directory / "stderr.txt", "wb")
        self.stdout_log = open(self.directory / "stdout.txt", "wb")
        executable = shutil.which("pwsh.exe")
        self.command = [executable or "pwsh.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-File",
                        str(ROOT / "schema-worker.ps1"), "-SchemaPath", str(SCHEMA_PATH)]
        self.process = None
        self.metadata = {}
        self.launch_error = None
        try:
            self.process = subprocess.Popen(
                self.command, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=self.stderr_log, text=True, encoding="utf-8")
            response = self.process.stdout.readline()
            self.stdout_log.write(response.encode("utf-8"))
            self.stdout_log.flush()
            self.metadata = parse_json(response)
            if not self.metadata.get("ready") or not self.metadata.get("metaschema"):
                raise Denied("Full JSON Schema engine unavailable")
            if self.metadata.get("input_codepage") != 65001 or self.metadata.get("output_codepage") != 65001:
                raise Denied("Schema worker transport is not UTF-8")
            self.save_diagnostics()
        except Exception as error:
            self.launch_error = type(error).__name__
            self.close()
            raise Denied("Schema worker initialization failed; evidence in " + str(self.directory)) from error

    def save_diagnostics(self):
        """Save fixed command and parser status without logging request bodies or environment."""
        report = {"command": self.command, "cwd": str(ROOT), "schema_sha256": digest(SCHEMA_PATH.read_bytes()),
                  "exit_code": self.process.poll() if self.process else None,
                  "runtime": self.metadata, "launch_error": self.launch_error,
                  "output_scope": "Only fixed parser replies and parser stderr; input bodies and environment excluded"}
        (self.directory / "launch.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    def validate(self, event):
        """Apply full instance validation; parser exit or malformed protocol is never success."""
        self.process.stdin.write(canonical(event) + "\n")
        self.process.stdin.flush()
        response = self.process.stdout.readline()
        self.stdout_log.write(response.encode("utf-8"))
        self.stdout_log.flush()
        if not response:
            self.save_diagnostics()
            raise Denied("Schema worker terminated; see " + str(self.directory))
        return parse_json(response).get("valid") is True

    def close(self):
        """Reap only this local parser and persist its exit code, including initialization failure."""
        if self.process is not None:
            if self.process.stdin and not self.process.stdin.closed:
                try:
                    self.process.stdin.close()
                except BrokenPipeError:
                    pass
            try:
                self.process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.wait(timeout=5)
            self.process.stdout.close()
        self.save_diagnostics()
        self.stdout_log.close()
        self.stderr_log.close()


def receipt_findings(result, reference):
    """Derive every required finding from exact receipt bytes without assigning issue IDs."""
    if result.get("outcome") == "FAIL":
        return [{"alias": {"issuer": "check-adapter", "external_id": check},
                 "anchor": {"check_id": check, "assertion_id": "required-result", "resource_scope_id": "owned-source", "security_invariant_id": "ordinary"},
                 "severity": "ORDINARY", "description": "Required check failed", "evidence": reference}
                for check in result["check_ids"]]
    return result.get("findings", [])
