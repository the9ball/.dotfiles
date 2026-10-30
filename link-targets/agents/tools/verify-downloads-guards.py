#!/usr/bin/env python3
"""Read-only, point-in-time integrity check; never repair or evaluate chezmoi."""

from __future__ import annotations

import ctypes
import hashlib
import os
from pathlib import Path
import stat
import sys
import types


ROOT = Path(__file__).resolve().parents[3]
NAMES = ("AGENTS.md", "AGENTS.override.md", "CLAUDE.md")
EXPECTED_SIZE = 554
EXPECTED_SHA256 = "752f5b04f25729c3c8f962ed30a5668bd9e447714a852418f83cdf200a4ae0f0"
PATH_HELPER_SHA256 = "f19f37e98624b41e151b8a02631c579c935643f8f73c196bb1930b05bb85172d"


def plain_parents(directory):
    """Reject observed ancestor links before reading their descendants."""
    for path in (*reversed(directory.parents), directory):
        metadata = path.lstat()
        if (not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode)
                or getattr(metadata, "st_file_attributes", 0) & 0x400
                or getattr(metadata, "st_reparse_tag", 0)):
            raise ValueError("UNSAFE_ANCESTOR")


def open_readonly(path):
    """Open an existing regular entry without following the final link.

    Windows handles permit shared readers only. POSIX flags support isolated
    tests without blocking on a concurrently substituted special file.
    """
    if os.name != "nt":
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            return os.fdopen(descriptor, "rb")
        except BaseException:
            os.close(descriptor)
            raise
    import msvcrt

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    create = kernel.CreateFileW
    create.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
                       ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
    create.restype = ctypes.c_void_p
    close = kernel.CloseHandle
    close.argtypes = [ctypes.c_void_p]
    close.restype = ctypes.c_int
    information = kernel.GetFileInformationByHandleEx
    information.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    information.restype = ctypes.c_int
    file_type = kernel.GetFileType
    file_type.argtypes = [ctypes.c_void_p]
    file_type.restype = ctypes.c_uint32
    # GENERIC_READ, FILE_SHARE_READ, OPEN_EXISTING, OPEN_REPARSE_POINT.
    handle = create(str(path), 0x80000000, 1, None, 3, 0x00200000, None)
    if handle in (None, ctypes.c_void_p(-1).value):
        raise OSError("READ_HANDLE_UNAVAILABLE")
    try:
        attributes = (ctypes.c_uint32 * 2)()
        if (file_type(handle) != 1
                or not information(handle, 9, ctypes.byref(attributes), ctypes.sizeof(attributes))
                or attributes[0] & (0x10 | 0x400) or attributes[1]):
            raise ValueError("OPENED_ENTRY_NOT_PLAIN")
        descriptor = msvcrt.open_osfhandle(handle, os.O_RDONLY | os.O_BINARY)
        handle = None  # The CRT descriptor now owns the same native handle.
        try:
            return os.fdopen(descriptor, "rb")
        except BaseException:
            os.close(descriptor)
            raise
    finally:
        if handle is not None:
            close(handle)


def bounded_regular_bytes(path, limit):
    """Read at most limit bytes and confirm the name still identifies that file."""
    metadata = path.lstat()
    if (not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode)
            or getattr(metadata, "st_file_attributes", 0) & 0x400
            or getattr(metadata, "st_reparse_tag", 0)):
        raise ValueError("NOT_PLAIN_FILE")
    with open_readonly(path) as stream:
        opened = os.fstat(stream.fileno())
        if not stat.S_ISREG(opened.st_mode) or not opened.st_ino:
            raise ValueError("NOT_REGULAR_HANDLE")
        data = stream.read(limit)
        after = os.fstat(stream.fileno())
        named = path.lstat()
        if ((opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino)
                or not stat.S_ISREG(named.st_mode)
                or getattr(named, "st_file_attributes", 0) & 0x400
                or getattr(named, "st_reparse_tag", 0)
                or (opened.st_size, opened.st_mtime_ns) != (after.st_size, after.st_mtime_ns)):
            raise ValueError("ENTRY_CHANGED_DURING_READ")
        return data


def load_path_helper():
    """Execute only the same bounded source bytes whose approved hash matched."""
    path = Path(__file__).resolve().with_name("check-downloads-guards.py")
    plain_parents(path.parent)
    source = bounded_regular_bytes(path, 65537)
    if len(source) > 65536 or hashlib.sha256(source).hexdigest() != PATH_HELPER_SHA256:
        raise ValueError("PATH_HELPER_CHANGED")
    module = types.ModuleType("guard_paths")
    module.__file__ = str(path)
    exec(compile(source, str(path), "exec"), module.__dict__)
    return module


def resolve_downloads(helper):
    """Resolve the known folder privately; reject redirects, links and SUBST."""
    downloads, profile, registration = helper.local_paths()
    if any(not path.is_absolute() or str(path).startswith(("\\\\", "//"))
           for path in (downloads, profile, registration)):
        raise ValueError("NONLOCAL_LOCATION")
    if downloads != registration or downloads != profile / "Downloads":
        raise ValueError("LOCATION_MISMATCH")
    if not helper.fixed_local_drive(downloads):
        raise ValueError("DRIVE_UNKNOWN")
    query = ctypes.WinDLL("kernel32").QueryDosDeviceW
    query.argtypes = [ctypes.c_wchar_p, ctypes.c_wchar_p, ctypes.c_uint32]
    query.restype = ctypes.c_uint32
    buffer = ctypes.create_unicode_buffer(32768)
    import re

    if (not query(downloads.drive, buffer, len(buffer))
            or re.fullmatch(r"\\Device\\HarddiskVolume[0-9]+", buffer.value) is None):
        raise ValueError("DIRECT_VOLUME_UNCONFIRMED")
    plain_parents(downloads)
    return downloads


def unknown_rows(reason):
    """Keep every member unresolved if a shared prerequisite is unavailable."""
    return [(name, "UNKNOWN", reason) for name in NAMES]


def verify_directory(directory, canonical):
    """Compare bounded target bytes with the pinned canonical source, without writes."""
    try:
        plain_parents(canonical.parent)
        expected = bounded_regular_bytes(canonical, EXPECTED_SIZE + 1)
        if len(expected) != EXPECTED_SIZE or hashlib.sha256(expected).hexdigest() != EXPECTED_SHA256:
            return unknown_rows("CANONICAL_SOURCE_MISMATCH")
    except (OSError, ValueError):
        return unknown_rows("CANONICAL_SOURCE_UNAVAILABLE")
    try:
        plain_parents(directory)
    except (OSError, ValueError):
        return unknown_rows("LOCATION_NOT_CONFIRMED")
    rows = []
    for name in NAMES:
        try:
            data = bounded_regular_bytes(directory / name, EXPECTED_SIZE + 1)
            rows.append((name, "PASS" if data == expected else "MODIFIED",
                         "BYTES_MATCH" if data == expected else "BYTES_DIFFER"))
        except FileNotFoundError:
            rows.append((name, "MISSING", "NO_ENTRY"))
        except (OSError, ValueError):
            rows.append((name, "UNKNOWN", "ENTRY_NOT_READABLE_OR_PLAIN"))
    return rows


def main():
    """Print fixed verdicts only; do not expose path, content, or exception values."""
    if sys.platform != "win32" or sys.argv[1:]:
        rows = unknown_rows("WINDOWS_NO_ARGUMENTS_REQUIRED")
    else:
        try:
            helper = load_path_helper()
            directory = resolve_downloads(helper)
            rows = verify_directory(directory, ROOT / "chezmoi/.chezmoitemplates/downloads-agent-instructions.md")
        except (Exception, KeyboardInterrupt):
            rows = unknown_rows("PREREQUISITE_UNAVAILABLE")
    # An unresolved member must dominate the summary, even if others were read.
    verdict = next((status for status in ("UNKNOWN", "MODIFIED", "MISSING")
                    if any(row[1] == status for row in rows)), "PASS")
    for item, status, reason in rows:
        print(f"{item}|{status}|{reason}")
    print(f"summary|{verdict}|POINT_IN_TIME_ONLY")
    return 0 if verdict == "PASS" else 2 if verdict == "UNKNOWN" else 1


if __name__ == "__main__":
    raise SystemExit(main())
