"""Read-only Git metadata adapter for regular-file, SHA-1, non-sparse repositories.

The deployment pins the executable; callers supply only a trusted root and complete
known-file scope. This is evidence acquisition, never authority or review dispatch.
Same-user malicious races and operating-system isolation are outside this profile.
"""

import os
import re
import stat
import subprocess
from pathlib import Path

from capture_kernel import capture_protected, file_mode, frame, owned_file, verify_pair
from common import Denied, canonical, digest
from reducer import require

GIT_EXECUTABLE = Path("C:/Program Files/Git/ucrt64/bin/git.exe")
GIT_SHA256 = "9c75f3f41eb5686bacde4b7c4fdfcd7970e8b699ee05c8d7a0cc9c8a7ddaffe8"
OPERATIONS = {
    "branch": ("symbolic-ref", "--short", "HEAD"),
    "head": ("rev-parse", "--verify", "HEAD"),
    "entries": ("ls-files", "--stage", "-z"),
    "untracked": ("ls-files", "--others", "--exclude-standard", "-z"),
    "ignored": ("ls-files", "--others", "--ignored", "--exclude-standard", "-z"),
    "status": ("status", "--porcelain=v2", "-z", "--untracked-files=all", "--ignore-submodules=none"),
}


def regular_bytes(path):
    """Read bounded regular metadata after rejecting every reparse ancestor."""
    path = Path(path).absolute()
    for ancestor in (path, *path.parents):
        information = ancestor.lstat()
        require(not stat.S_ISLNK(information.st_mode)
                and not getattr(information, "st_file_attributes", 0) & 1024, "Reparse path unsupported")
    require(path.is_file() and path.stat().st_size <= 16777216, "Regular bounded file required")
    return path.read_bytes()


def validate_config(raw):
    """Accept a narrow Git config grammar; reject includes, escapes and active extensions."""
    section = None
    for line in raw.decode("utf-8", errors="strict").splitlines():
        line = line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        require(not any(character in line for character in ('\\', '\x00', '\"')) or line.startswith("["),
                "Config escape or quoted value unsupported")
        if line.startswith("["):
            match = re.fullmatch(r'\[(core|extensions|remote "[^"\\\x00-\x1f]+"|branch "[^"\\\x00-\x1f]+")\]', line, re.I)
            require(match is not None, "Config section unsupported")
            section = match[1].split(" ")[0].lower()
            continue
        match = re.fullmatch(r"([A-Za-z][A-Za-z0-9-]*)\s*=\s*([^\x00-\x1f]*)", line)
        require(section is not None and match is not None, "Config syntax unsupported")
        key, value = match[1].lower(), match[2].strip().lower()
        if section == "core":
            require(key in {"repositoryformatversion", "filemode", "bare", "logallrefupdates", "symlinks", "ignorecase", "autocrlf"},
                    "Core config unsupported")
            require(value in ({"0"} if key == "repositoryformatversion" else {"false"} if key == "bare" else {"true", "false", "input"}),
                    "Core config value unsupported")
        elif section == "extensions":
            require(key == "worktreeconfig" and value == "true", "Repository extension unsupported")


def metadata_inventory(root):
    """Inspect Git-consumed namespace types without following links or reading unknown bodies."""
    root = Path(root).absolute()
    for ancestor in root.parents:
        information = ancestor.lstat()
        require(not stat.S_ISLNK(information.st_mode)
                and not getattr(information, "st_file_attributes", 0) & 1024, "Metadata ancestor link unsupported")
    entries = []
    pending = [root]
    while pending:
        path = pending.pop()
        if not os.path.lexists(path):
            entries.append({"path": str(path), "kind": "missing"})
            continue
        information = path.lstat()
        require(not stat.S_ISLNK(information.st_mode)
                and not getattr(information, "st_file_attributes", 0) & 1024, "Git metadata link unsupported")
        require(stat.S_ISREG(information.st_mode) or stat.S_ISDIR(information.st_mode), "Git metadata type unsupported")
        record = {"path": str(path), "mode": stat.S_IMODE(information.st_mode),
                  "attributes": getattr(information, "st_file_attributes", None)}
        if stat.S_ISDIR(information.st_mode):
            children = sorted(path.iterdir(), key=lambda child: child.name)
            record.update(kind="directory", children=[child.name for child in children])
            pending.extend(reversed(children))
        else:
            record.update(kind="file", size=information.st_size, mtime_ns=str(information.st_mtime_ns))
        entries.append(record)
    return entries


class GitSnapshot:
    """Freeze real Git evidence without writing refs, index, objects or settings."""

    def __init__(self, root, known_paths):
        """Bind an absolute root and complete immutable regular-file allowlist."""
        self.root = Path(root).absolute()
        require(self.root == self.root.resolve() and self.root.is_dir(), "Canonical root required")
        self.known = tuple(sorted(known_paths, key=lambda name: name.encode("utf-8")))
        require(self.known and len({name.casefold() for name in self.known}) == len(self.known), "Duplicate or empty scope")
        for name in self.known:
            require(isinstance(name, str) and ":" not in name and not any(part.casefold() == ".git" for part in name.split("/")),
                    "Git control path outside file scope")
            owned_file(self.root, name)
        marker = self.root / ".git"
        if marker.is_file():
            match = re.fullmatch(r"gitdir: ([^\r\n]+)\r?\n?", regular_bytes(marker).decode("utf-8"))
            require(match is not None, "Worktree marker unsupported")
            self.git_dir = (self.root / match[1]).resolve()
        else:
            self.git_dir = marker
        require(self.git_dir.is_dir(), "Git directory required")
        common_marker = self.git_dir / "commondir"
        self.common_dir = ((self.git_dir / regular_bytes(common_marker).decode("utf-8").strip()).resolve()
                           if common_marker.exists() else self.git_dir)
        self.index_path = self.git_dir / "index"
        self.configs = (self.common_dir / "config", self.git_dir / "config.worktree")
        self._control()
        require(digest(regular_bytes(GIT_EXECUTABLE)) == GIT_SHA256, "Git executable changed")

    def _control(self):
        """Validate control files before Git can interpret config or redirect object reads."""
        control = {}
        # These namespaces are implicit Git inputs even when all argv paths are closed.
        for directory in {self.git_dir, self.common_dir}:
            for name in ("info", "refs", "objects"):
                control[str(directory / name)] = metadata_inventory(directory / name)
            for name in ("packed-refs", "info/exclude", "info/attributes"):
                path = directory / name
                if os.path.lexists(path):
                    control[str(path)] = digest(regular_bytes(path))
            require(not os.path.lexists(directory / "info/grafts"), "Git graft input unsupported")
        for path in self.configs:
            if path.exists():
                raw = regular_bytes(path)
                validate_config(raw)
                control[str(path)] = digest(raw)
        for path in (self.git_dir / "HEAD", self.root / ".git", self.git_dir / "commondir"):
            if path.is_file():
                control[str(path)] = digest(regular_bytes(path))
        for directory in {self.git_dir, self.common_dir}:
            require(not any((directory / name).exists() for name in ("shallow", "info/sparse-checkout", "objects/info/alternates", "objects/info/http-alternates")),
                    "Shallow, sparse or alternate repository unsupported")
            require(not list(directory.glob("sharedindex.*")), "Split index unsupported")
        raw = regular_bytes(self.index_path)
        require(raw[:8] == b"DIRC\x00\x00\x00\x02" and len(raw) >= 32, "Only index v2 supported")
        return control

    def _git(self, operation):
        """Run one closed command with no inherited Git, shell or credential environment."""
        require(operation in OPERATIONS, "Git operation outside allowlist")
        self._control()
        self._paths()
        environment = {"SystemRoot": "C:/Windows", "WINDIR": "C:/Windows", "PATH": str(GIT_EXECUTABLE.parent),
                       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_SYSTEM": "NUL", "GIT_CONFIG_GLOBAL": "NUL",
                       "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0", "GIT_NO_LAZY_FETCH": "1",
                       "GIT_ATTR_NOSYSTEM": "1", "GIT_NO_REPLACE_OBJECTS": "1", "LC_ALL": "C"}
        command = [str(GIT_EXECUTABLE), "--no-optional-locks", "--literal-pathspecs",
                   "--git-dir=" + str(self.git_dir), "--work-tree=" + str(self.root),
                   "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false",
                   "-c", "core.preloadIndex=false", "-c", "submodule.recurse=false", *OPERATIONS[operation]]
        try:
            result = subprocess.run(command, cwd=self.root, env=environment, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15, shell=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise Denied("Git acquisition failed: " + type(error).__name__) from error
        require(result.returncode == 0 and not result.stderr, "Git acquisition failed; no evidence accepted")
        return result.stdout

    def _paths(self):
        """Enumerate names only and reject unknown files, links and nested repositories."""
        found = []
        parents = {str(Path(name).parent).replace("\\", "/") for name in self.known}
        for parent in tuple(parents):
            parents.update(str(path).replace("\\", "/") for path in Path(parent).parents)
        for directory, directories, files in os.walk(self.root, followlinks=False):
            for name in list(directories) + files:
                path = Path(directory) / name
                relative = path.relative_to(self.root).as_posix()
                if relative == ".git":
                    if name in directories:
                        directories.remove(name)
                    continue
                information = path.lstat()
                require(not stat.S_ISLNK(information.st_mode)
                        and not getattr(information, "st_file_attributes", 0) & 1024, "File link unsupported")
                if name in directories:
                    require(relative in parents and name.casefold() != ".git", "Directory outside known scope")
                else:
                    require(stat.S_ISREG(information.st_mode) and relative in self.known, "File outside known scope")
                    found.append(relative)
        require(set(found) == set(self.known), "Known file missing")
        return sorted(found)

    def snapshot(self):
        """Read both Git metadata and only predeclared file bytes; reject any torn read."""
        control = self._control()
        names = self._paths()
        index = regular_bytes(self.index_path)
        entries = self._git("entries")
        modes = {}
        for row in entries.split(b"\x00")[:-1]:
            match = re.fullmatch(rb"(100644|100755) [0-9a-f]{40} 0\t(.+)", row)
            require(match is not None, "Unmerged, symlink or gitlink index unsupported")
            name = match[2].decode("utf-8", errors="strict")
            require(name in self.known and name not in modes, "Index path outside scope")
            modes[name] = match[1].decode()
        untracked, ignored = self._git("untracked"), self._git("ignored")
        listed = list(modes) + [name.decode("utf-8", errors="strict") for name in (untracked + ignored).split(b"\x00") if name]
        require(len(listed) == len(set(listed)) and set(listed) == set(names), "Git and filesystem scope differ")
        modes.update({name: "100644" for name in self.known if name not in modes})
        existing = [{"path": name, "sha256": digest(regular_bytes(owned_file(self.root, name))),
                     "mode": file_mode(owned_file(self.root, name), modes[name])} for name in self.known]
        protected = capture_protected(self.root, existing, self._paths, modes.__getitem__)
        metadata = {"branch": self._git("branch"), "head": self._git("head"), "index": index,
                    "status": self._git("status"), "entries": entries, "ignored": ignored,
                    "candidate": canonical({"root": str(self.root), "real_index": str(self.index_path),
                                             "files": existing, "controls": control}).encode()}
        require(control == self._control() and index == regular_bytes(self.index_path), "Control changed during capture")
        return frame(metadata, protected), existing

    def freeze(self):
        """Return a proposed baseline for explicit caller fixation, never operational approval."""
        snapshot, existing = self.snapshot()
        baseline = {field: snapshot[field].decode("utf-8").rstrip("\r\n") for field in ("branch", "head")}
        baseline.update({field: digest(snapshot[field]) for field in ("index", "status")})
        return {"snapshot": snapshot, "baseline": baseline, "existing": existing}

    def capture(self, expected):
        """Require the complete expected baseline and two matching kernel-verified snapshots."""
        before, _ = self.snapshot()
        require(before == expected["snapshot"], "Expected snapshot changed; discard and stop")
        after, _ = self.snapshot()
        verify_pair(before, after, expected["baseline"], expected["existing"])
        return {"capture_consistent": True, "snapshot_sha256": digest(canonical({key: digest(value) for key, value in before.items()}).encode()),
                "dispatch_allowed": False, "adoption_gate": "BLOCKED"}
