"""Pure capture predicates over frozen metadata and an explicitly owned file root.

No Git command, review dispatch, credentials or host configuration is accessed.
Readers and baseline must be supplied by an independently trusted caller.
"""

import re
import stat
from pathlib import Path, PurePosixPath, PureWindowsPath

from common import Denied, canonical, digest, parse_json
from reducer import require

KEYS = ("branch", "head", "index", "status", "candidate", "entries", "ignored", "protected")


def owned_file(root, name):
    """Resolve only canonical relative paths and never follow a symlink outside ownership."""
    require(isinstance(name, str) and name and "\\" not in name and "\x00" not in name, "Protected path invalid")
    relative = PurePosixPath(name)
    require(not relative.is_absolute() and not PureWindowsPath(name).drive
            and ".." not in relative.parts and relative.as_posix() == name and name != ".", "Protected path escape")
    base = Path(root).resolve()
    candidate = base / name
    require(candidate.resolve().is_relative_to(base), "Protected path escape")
    for part in [candidate, *candidate.parents]:
        if part == base:
            break
        require(not part.is_symlink(), "Protected symlink rejected")
    return candidate


def file_mode(path, git_mode):
    """Keep trusted Git executable mode separate from OS permissions and Windows attributes."""
    require(git_mode in {"100644", "100755"}, "Protected Git mode invalid")
    information = path.stat()
    return {"git": git_mode, "os": stat.S_IMODE(information.st_mode),
            "windows_attributes": getattr(information, "st_file_attributes", None)}


def capture_protected(root, existing, enumerate_paths, read_git_mode):
    """Hash only frozen protected files and record path membership without reading newcomers."""
    expected = [item["path"] for item in existing]
    require(len(expected) == len(set(expected)), "Protected duplicate baseline path")
    before = list(enumerate_paths())
    require(all(isinstance(name, str) for name in before) and len(before) == len(set(before)), "Protected invalid enumeration")
    entries = []
    for item in existing:
        require(isinstance(item.get("sha256"), str) and re.fullmatch("[0-9a-f]{64}", item["sha256"]), "Protected invalid baseline hash")
        file = owned_file(root, item["path"])
        entries.append({"path": item["path"], "exists": file.is_file(),
                        "sha256": digest(file.read_bytes()) if file.is_file() else None,
                        "mode": file_mode(file, read_git_mode(item["path"])) if file.is_file() else None})
    after = list(enumerate_paths())
    return {"paths": sorted(before), "entries": entries,
            "enumeration_stable": sorted(before) == sorted(after) and len(after) == len(set(after))}


def verify_protected(captured, existing):
    """Recompute all protected predicates rather than trusting a caller's success flag."""
    require(captured["enumeration_stable"], "Protected enumeration changed")
    expected = {item["path"]: item for item in existing}
    require(captured["paths"] == sorted(expected), "Protected membership mismatch")
    entries = captured["entries"]
    require(len(entries) == len(expected) and len({item["path"] for item in entries}) == len(entries), "Protected entries mismatch")
    for item in entries:
        require(item["path"] in expected and item["exists"] and item["sha256"] == expected[item["path"]]["sha256"], "Protected content changed")
        mode = expected[item["path"]].get("mode")
        require(isinstance(mode, dict) and set(mode) == {"git", "os", "windows_attributes"}
                and mode["git"] in {"100644", "100755"} and type(mode["os"]) is int
                and (mode["windows_attributes"] is None or type(mode["windows_attributes"]) is int), "Protected baseline mode invalid")
        require(item.get("mode") == mode, "Protected mode changed")


def frame(metadata, protected):
    """Combine already captured raw metadata with the protected-content snapshot."""
    require(set(metadata) == set(KEYS) - {"protected"}, "Capture metadata set mismatch")
    require(all(isinstance(value, bytes) for value in metadata.values()), "Capture metadata must be raw bytes")
    return {**metadata, "protected": canonical(protected).encode()}


def verify_baseline(snapshot, baseline):
    """Require exact branch/HEAD and SHA256 index/status baseline identity."""
    require(set(snapshot) == set(KEYS) and all(isinstance(value, bytes) for value in snapshot.values()), "Capture fields invalid")
    for field in ("branch", "head"):
        expected = baseline.get(field)
        require(isinstance(expected, str) and expected and "\r" not in expected and "\n" not in expected, "Invalid baseline " + field)
        raw = snapshot[field]
        raw = raw[:-2] if raw.endswith(b"\r\n") else raw[:-1] if raw.endswith(b"\n") else raw
        require(raw.decode("utf-8", errors="strict") == expected, "Baseline " + field + " mismatch")
    for field in ("index", "status"):
        expected = baseline.get(field)
        require(isinstance(expected, str) and re.fullmatch("[0-9a-f]{64}", expected), "Invalid baseline " + field)
        require(digest(snapshot[field]) == expected, "Baseline " + field + " mismatch")


def compare_captures(before, after):
    """Detect every raw field change and issue a non-dispatch predicate on any difference."""
    require(set(before) == set(after) == set(KEYS), "Capture comparison fields mismatch")
    require(all(isinstance(value, bytes) for value in [*before.values(), *after.values()]), "Capture comparison requires bytes")
    changed = [name for name in KEYS if before[name] != after[name]]
    return {"changed": changed, "capture_discarded": bool(changed), "dispatch_allowed": not changed}


def verify_pair(before, after, baseline, existing):
    """Check both baseline snapshots and protected manifests before accepting stability."""
    for snapshot in (before, after):
        verify_baseline(snapshot, baseline)
        verify_protected(parse_json(snapshot["protected"]), existing)
    verdict = compare_captures(before, after)
    require(verdict["dispatch_allowed"], "Capture changed; discard without dispatch")
    return verdict
