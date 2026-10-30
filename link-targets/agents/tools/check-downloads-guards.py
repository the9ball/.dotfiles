#!/usr/bin/env python3
"""Report Downloads guard prerequisites without printing paths or private values.

Run manually with Python 3.11+ using -I -S -B. This never invokes chezmoi,
evaluates templates, or changes configuration or destination files.
"""

from __future__ import annotations

import ctypes
import json
import os
from pathlib import Path
import stat
import sys
import tomllib
import uuid


NAMES = ("AGENTS.md", "AGENTS.override.md", "CLAUDE.md")


def known_folder(identifier: str) -> Path:
    """Read one Windows Known Folder with DONT_VERIFY, without creating it."""
    folder_identifier = (ctypes.c_ubyte * 16).from_buffer_copy(uuid.UUID(identifier).bytes_le)
    folder_pointer = ctypes.c_void_p()
    query = ctypes.WinDLL("shell32").SHGetKnownFolderPath
    query.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p,
                      ctypes.POINTER(ctypes.c_void_p)]
    query.restype = ctypes.c_long
    release = ctypes.WinDLL("ole32").CoTaskMemFree
    release.argtypes = [ctypes.c_void_p]
    release.restype = None
    try:
        if query(ctypes.byref(folder_identifier), 0x4000, None,
                 ctypes.byref(folder_pointer)) != 0:
            raise OSError("KNOWN_FOLDER_UNAVAILABLE")
        return Path(ctypes.wstring_at(folder_pointer))
    finally:
        if folder_pointer.value:
            release(folder_pointer)


def local_paths() -> tuple[Path, Path, Path]:
    """Read Downloads API, Profile API and Downloads registration privately."""
    import winreg

    downloads = known_folder("374de290-123f-4565-9164-39c4925e467b")
    profile = known_folder("5e6c858f-0e22-4760-9afe-ea3317b67173")
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                        r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders") as key:
        registration, kind = winreg.QueryValueEx(key, "{374DE290-123F-4565-9164-39C4925E467B}")
    if kind not in (winreg.REG_SZ, winreg.REG_EXPAND_SZ) or not registration:
        raise ValueError("INVALID_REGISTRATION")
    return downloads, profile, Path(os.path.expandvars(registration))


def fixed_local_drive(path: Path) -> bool:
    """Reject remote/unknown Windows drives before accessing directory metadata."""
    if os.name != "nt":
        return True  # Only the synthetic tests use these helpers on POSIX.
    query = ctypes.WinDLL("kernel32").GetDriveTypeW
    query.argtypes = [ctypes.c_wchar_p]
    query.restype = ctypes.c_uint32
    return query(path.anchor) == 3


def plain_directory_chain(path: Path) -> bool:
    """Inspect parents before children, stopping at a missing or linked ancestor."""
    for directory in (*reversed(path.parents), path):
        try:
            metadata = directory.lstat()
        except FileNotFoundError:
            return False
        if (not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode)
                or getattr(metadata, "st_file_attributes", 0) & 0x400
                or getattr(metadata, "st_reparse_tag", 0)):
            raise ValueError("ANCESTOR_NOT_PLAIN_DIRECTORY")
    return True


def path_checks(downloads: Path, profile: Path, registration: Path) -> list[tuple[str, str, str]]:
    """Check metadata only; reject redirects, UNC, ancestor links and collisions."""
    rows = []
    expected = profile / "Downloads"
    paths = (downloads, profile, registration)
    if any(not path.is_absolute() or str(path).startswith(("\\\\", "//")) for path in paths):
        return [("location", "BLOCKED", "NONLOCAL_OR_RELATIVE")]
    if downloads != registration or downloads != expected:
        return [("location", "BLOCKED", "REDIRECT_OR_REGISTRATION_MISMATCH")]
    if not fixed_local_drive(downloads):
        return [("location", "BLOCKED", "NONLOCAL_OR_UNCONFIRMED_DRIVE")]
    try:
        if not plain_directory_chain(downloads):
            return [("location", "UNKNOWN", "DIRECTORY_MISSING")]
    except ValueError:
        return [("location", "BLOCKED", "ANCESTOR_NOT_PLAIN_DIRECTORY")]
    rows.append(("location", "PASS", "API_REGISTRATION_DEFAULT_TARGET_MATCH"))
    # Enumerate names, including dangling links, without opening their contents.
    with os.scandir(downloads) as entries:
        existing = {entry.name.casefold() for entry in entries}
    for name in NAMES:
        collision = name.casefold() in existing
        if not collision:
            try:
                (downloads / name).lstat()
                collision = True
            except FileNotFoundError:
                pass
            except OSError:
                rows.append((name, "UNKNOWN", "ENTRY_METADATA_UNAVAILABLE"))
                continue
        rows.append((name, "BLOCKED" if collision else "PASS",
                     "ENTRY_EXISTS" if collision else "NO_ENTRY"))
    return rows


def normalized_keys(value):
    """Case-fold config keys recursively, rejecting ambiguous case collisions."""
    if isinstance(value, dict):
        keys = [key.casefold() for key in value]
        if len(set(keys)) != len(keys):
            raise ValueError("AMBIGUOUS_CONFIG_KEYS")
        return {key.casefold(): normalized_keys(item) for key, item in value.items()}
    if isinstance(value, list):
        return [normalized_keys(item) for item in value]
    return value


def unique_json_object(pairs):
    """Reject both exact and case-variant JSON duplicates before dict creation."""
    keys = [key.casefold() for key, _ in pairs]
    if len(set(keys)) != len(keys):
        raise ValueError("AMBIGUOUS_JSON_KEYS")
    return dict(pairs)


def configuration_checks(profile: Path, repository: Path) -> list[tuple[str, str, str]]:
    """Parse supported default config as data; never execute config or source tools.

    Arbitrary wrappers/explicit CLI flags are outside this check. The future
    command must use a separately confirmed direct executable and exact paths.
    """
    if any(name.upper().startswith("CHEZMOI_") for name in os.environ):
        return [("configuration", "UNKNOWN", "ENVIRONMENT_OVERRIDE_PRESENT")]
    home = os.environ.get("USERPROFILE")
    if not home or Path(home) != profile:
        return [("configuration", "UNKNOWN", "HOME_ENVIRONMENT_MISMATCH")]
    if os.environ.get("XDG_CONFIG_DIRS"):
        return [("configuration", "UNKNOWN", "ADDITIONAL_CONFIG_SEARCH_ROOTS")]
    directory = Path(os.environ.get("XDG_CONFIG_HOME", str(profile / ".config"))) / "chezmoi"
    if not directory.is_absolute() or str(directory).startswith(("\\\\", "//")):
        return [("configuration", "UNKNOWN", "NONLOCAL_OR_RELATIVE_CONFIG_ROOT")]
    if not fixed_local_drive(directory):
        return [("configuration", "UNKNOWN", "NONLOCAL_OR_UNCONFIRMED_DRIVE")]
    candidates = [directory / ("chezmoi." + extension)
                  for extension in ("toml", "json", "jsonc", "yaml", "yml")]
    present = []
    try:
        directory_exists = plain_directory_chain(directory)
    except ValueError:
        return [("configuration", "BLOCKED", "CONFIG_ANCESTOR_NOT_PLAIN_DIRECTORY")]
    if directory_exists:
        for path in candidates:
            try:
                path.lstat()
            except FileNotFoundError:
                continue
            present.append(path)
    if len(present) > 1:
        return [("configuration", "BLOCKED", "MULTIPLE_CONFIGS")]
    configuration = {}
    if present:
        path = present[0]
        metadata = path.lstat()
        if (not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode)
                or getattr(metadata, "st_file_attributes", 0) & 0x400):
            return [("configuration", "UNKNOWN", "CONFIG_NOT_PLAIN_FILE")]
        if path.suffix not in (".toml", ".json") or metadata.st_size > 1024 * 1024:
            return [("configuration", "UNKNOWN", "CONFIG_FORMAT_OR_SIZE_UNSUPPORTED")]
        with path.open("rb") as stream:
            configuration = (tomllib.load(stream) if path.suffix == ".toml"
                             else json.load(stream, object_pairs_hook=unique_json_object))
        if not isinstance(configuration, dict):
            return [("configuration", "UNKNOWN", "CONFIG_NOT_OBJECT")]
    configuration = normalized_keys(configuration)
    destination = Path(configuration.get("destdir", str(profile))).expanduser()
    source_default = Path(os.environ.get("XDG_DATA_HOME", str(profile / ".local/share"))) / "chezmoi"
    source = Path(configuration.get("sourcedir", str(source_default))).expanduser()
    if source == repository:
        # This repository's tracked .chezmoiroot selects its chezmoi subdirectory.
        source = source / "chezmoi"
    rows = [("chezmoi_target", "PASS" if destination == profile else "BLOCKED",
             "DEFAULT_TARGET_MATCH" if destination == profile else "DESTINATION_OVERRIDE"),
            ("chezmoi_source", "PASS" if source == repository / "chezmoi" else "UNKNOWN",
             "EXPECTED_SOURCE" if source == repository / "chezmoi" else "SOURCE_NOT_CONFIRMED")]
    opt_in = configuration.get("data", {}).get("downloadsagentguards", False)
    rows.append(("config_opt_in", "PASS" if opt_in is False else "BLOCKED",
                 "CONFIG_DATA_NOT_ENABLED" if opt_in is False else "ENABLED_OR_INVALID_TYPE"))
    hooks = bool(configuration.get("hooks"))
    rows.append(("hooks", "BLOCKED" if hooks else "PASS", "PRESENT" if hooks else "ABSENT"))
    # Full source evaluation can read local data or fetch externals even for
    # apparently harmless commands. Do not infer safety from --exclude=scripts.
    rows.extend([("configuration_scope", "UNKNOWN", "EXACT_CLI_SEARCH_SCOPE_UNCONFIRMED"),
                 ("persistent_opt_in", "UNKNOWN", "SOURCE_DATA_NOT_CHECKED"),
                 ("storage", "UNKNOWN", "SUBST_DRIVE_MAPPING_NOT_CHECKED"),
                 ("scripts", "UNKNOWN", "REQUIRE_EXACT_COMMAND_SCOPE"),
                 ("externals", "UNKNOWN", "REQUIRE_SOURCE_EVALUATION_REVIEW"),
                 ("diff_verify", "UNKNOWN", "NOT_EXECUTED_CONFIG_EFFECTS_UNPROVEN")])
    return rows


def main() -> int:
    """Print fixed status codes only; exceptions never expose private values."""
    if sys.platform != "win32":
        print("environment|UNKNOWN|WINDOWS_REQUIRED")
        return 2
    profile = None
    try:
        downloads, profile, registration = local_paths()
        rows = path_checks(downloads, profile, registration)
    except Exception:
        rows = [("location", "UNKNOWN", "METADATA_QUERY_FAILED")]
    try:
        if profile is None:
            raise ValueError("PROFILE_UNAVAILABLE")
        rows.extend(configuration_checks(profile, Path(__file__).resolve().parents[3]))
    except Exception:
        rows.append(("configuration", "UNKNOWN", "CONFIG_QUERY_OR_PARSE_FAILED"))
    for item, status, reason in rows:
        print(f"{item}|{status}|{reason}")
    blocked = any(status == "BLOCKED" for _, status, _ in rows)
    print(f"summary|{'BLOCKED' if blocked else 'UNKNOWN'}|PREFLIGHT_INCOMPLETE")
    return 1 if blocked else 2


if __name__ == "__main__":
    raise SystemExit(main())
