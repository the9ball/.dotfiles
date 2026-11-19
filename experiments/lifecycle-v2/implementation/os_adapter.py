"""Harmless local conformance probes; no live authority or external CLI dispatch."""

import os
import subprocess
import sys
from pathlib import Path
from common import Denied, canonical, digest


def inventory(root):
    """Hash exact local fixture files and reject symbolic-link traversal."""
    result = []
    for path in sorted(Path(root).rglob("*")):
        if path.is_symlink():
            raise Denied("Capture symlink rejected")
        if path.is_file():
            result.append({"path": path.relative_to(root).as_posix(), "mode": path.stat().st_mode,
                           "sha256": digest(path.read_bytes()), "bytes": path.stat().st_size})
    return result


def capture(root, expected, mutation=None):
    """Require a fixed pre-baseline and pre/post identity; return no failed evidence."""
    before = inventory(root)
    if before != expected:
        raise Denied("Capture baseline changed; discard and stop")
    frozen = canonical(before).encode()
    if mutation:
        mutation()
    if inventory(root) != before:
        raise Denied("Capture changed during read; discard and stop")
    return digest(frozen)


def harmless_child():
    """Run one fixed local Python child with a restricted noncredential environment."""
    environment = {key: os.environ[key] for key in ("SystemRoot", "WINDIR", "TEMP", "TMP") if key in os.environ}
    process = subprocess.Popen([sys.executable, "-I", "-c", "print('lifecycle-v2-stub')"],
                               stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=environment, text=True, encoding="utf-8")
    output, errors = process.communicate(timeout=10)
    return {"pid": process.pid, "exit_code": process.returncode,
            "stdout": output.strip(), "stderr_empty": errors == "", "windows": os.name == "nt",
            "live_identity_or_group_proof": False}
