"""Portable old-case safety checks using injected metadata and private actual files."""

import copy
import tempfile
import unittest
from pathlib import Path

import test_v2
from capture_kernel import file_mode, capture_protected, compare_captures, frame, verify_baseline, verify_pair, verify_protected
from common import Denied, digest


class CaptureKernelTests(unittest.TestCase):
    """Exercise pure capture decisions without claiming a deployed Git/dispatch adapter."""

    def setUp(self):
        """Create the same two protected-file roles as the old synthetic fixtures."""
        self.directory = Path(tempfile.mkdtemp(prefix="capture-", dir=test_v2.RUN_ROOT))
        self.names = ["already-dirty.txt", "second.txt"]
        for name in self.names:
            (self.directory / name).write_text("dirty fixture " + name + "\n", encoding="utf-8")
        self.git_modes = {name: "100644" for name in self.names}
        self.existing = [{"path": name, "sha256": digest((self.directory / name).read_bytes()),
                          "mode": file_mode(self.directory / name, self.git_modes[name])} for name in self.names]
        self.paths = self.names[:]
        self.metadata = {"branch": b"fixed-branch\n", "head": ("a" * 40 + "\n").encode(), "index": b"DIRC\0\0\0\2\0",
                         "status": b"1 .M protected-fixture\0", "candidate": b"fixed-candidate", "entries": b"fixed-entries", "ignored": b"fixed-ignored"}
        self.baseline = {"branch": "fixed-branch", "head": "a" * 40,
                         "index": digest(self.metadata["index"]), "status": digest(self.metadata["status"])}

    def snapshot(self):
        """Capture only fixture-owned bytes and injected path enumeration."""
        return frame(self.metadata, capture_protected(self.directory, self.existing, lambda: self.paths[:], self.git_modes.__getitem__))

    def test_C11_baseline_branch_and_head_are_independent_of_stability(self):
        """Stable wrong branch or HEAD fails even if two snapshots agree byte for byte."""
        snapshot = self.snapshot()
        for changed in ({"branch": "other"}, {"head": "b" * 40}):
            with self.assertRaises(Denied):
                verify_baseline(snapshot, {**self.baseline, **changed})
        verify_baseline(snapshot, self.baseline)

    def test_S2_protected_content_change_detected_with_stable_metadata(self):
        """Same Git metadata cannot hide changed protected bytes."""
        before = self.snapshot()
        (self.directory / self.names[0]).write_text("changed during capture\n", encoding="utf-8")
        after = self.snapshot()
        verdict = compare_captures(before, after)
        self.assertEqual(verdict["changed"], ["protected"])
        self.assertFalse(verdict["dispatch_allowed"])
        with self.assertRaises(Denied):
            verify_pair(before, after, self.baseline, self.existing)

    def test_D07_new_dirty_path_is_not_read_as_source(self):
        """An unexpected path prevents acceptance and is absent from source byte entries."""
        before = self.snapshot()
        (self.directory / "new.txt").write_text("new dirty file\n", encoding="utf-8")
        self.paths.append("new.txt")
        after = self.snapshot()
        verdict = compare_captures(before, after)
        self.assertTrue(verdict["capture_discarded"])
        captured = capture_protected(self.directory, self.existing, lambda: self.paths[:], self.git_modes.__getitem__)
        self.assertEqual([item["path"] for item in captured["entries"]], self.names)
        with self.assertRaises(Denied):
            verify_protected(captured, self.existing)

    def test_D08_missing_file_is_rejected_despite_unchanged_path_list(self):
        """Deletion is detected even while injected status retains the old path."""
        before = self.snapshot()
        (self.directory / self.names[0]).unlink()
        after = self.snapshot()
        self.assertFalse(compare_captures(before, after)["dispatch_allowed"])
        with self.assertRaises(Denied):
            verify_protected(capture_protected(self.directory, self.existing, lambda: self.paths[:], self.git_modes.__getitem__), self.existing)

    def test_D10_membership_change_is_not_inferred_from_file_presence(self):
        """Changed dirty membership fails even if all physical bytes remain unchanged."""
        before = self.snapshot()
        self.paths = ["second.txt"]
        after = self.snapshot()
        self.assertTrue(compare_captures(before, after)["capture_discarded"])
        with self.assertRaises(Denied):
            verify_pair(before, after, self.baseline, self.existing)

    def test_E08_baseline_index_status_require_real_hashes(self):
        """Missing or malformed expected hashes are never inferred from current bytes."""
        snapshot = self.snapshot()
        for field in ("index", "status"):
            for invalid in (None, "", 1, "not-a-sha256", "missing"):
                baseline = copy.deepcopy(self.baseline)
                if invalid == "missing":
                    del baseline[field]
                else:
                    baseline[field] = invalid
                with self.assertRaises(Denied):
                    verify_baseline(snapshot, baseline)
        verify_baseline(snapshot, self.baseline)

    def test_E09_stable_index_or_status_drift_is_rejected(self):
        """A field can remain stable during capture and still violate the frozen baseline."""
        for field in ("index", "status"):
            original = self.metadata[field]
            self.metadata[field] += b"changed"
            before = self.snapshot()
            after = self.snapshot()
            self.assertTrue(compare_captures(before, after)["dispatch_allowed"])
            with self.assertRaises(Denied):
                verify_baseline(before, self.baseline)
            self.metadata[field] = original

    def test_stable_pair_accepts_and_every_raw_field_is_compared(self):
        """The kernel accepts valid evidence and detects each of the eight raw fields."""
        before = self.snapshot()
        after = self.snapshot()
        self.assertTrue(verify_pair(before, after, self.baseline, self.existing)["dispatch_allowed"])
        for field in before:
            changed = {**after, field: after[field] + b"changed"}
            self.assertTrue(compare_captures(before, changed)["capture_discarded"])

    def test_path_escape_and_torn_enumeration_fail_closed(self):
        """Only frozen owned files are readable and inconsistent enumerations are rejected."""
        for name in ("../outside.txt", "C:/outside.txt", "/outside.txt", "folder/../../outside.txt"):
            with self.assertRaises(Denied):
                capture_protected(self.directory, [{"path": name, "sha256": "a" * 64}], lambda: [name], self.git_modes.__getitem__)
        paths = iter([self.names[:], ["second.txt"]])
        captured = capture_protected(self.directory, self.existing, lambda: next(paths), self.git_modes.__getitem__)
        with self.assertRaises(Denied):
            verify_protected(captured, self.existing)


    def test_R4_git_mode_only_and_os_mode_only_changes_are_rejected(self):
        """Git executable intent and OS permissions are independently frozen even on Windows."""
        before = self.snapshot()
        self.git_modes[self.names[0]] = "100755"
        after = self.snapshot()
        with self.assertRaises(Denied):
            verify_pair(before, after, self.baseline, self.existing)
        self.git_modes[self.names[0]] = "100644"
        file = self.directory / self.names[0]
        original = file.stat().st_mode
        try:
            file.chmod(0o444)
            changed = self.snapshot()
            with self.assertRaises(Denied):
                verify_pair(before, changed, self.baseline, self.existing)
        finally:
            file.chmod(original)
        self.assertTrue(verify_pair(before, self.snapshot(), self.baseline, self.existing)["dispatch_allowed"])

    def test_R4_missing_or_invalid_mode_baseline_is_not_inferred(self):
        """Missing Git/OS mode evidence fails rather than substituting current observed state."""
        captured = capture_protected(self.directory, self.existing, lambda: self.paths[:], self.git_modes.__getitem__)
        for invalid in (None, {}, {"git": "100644", "os": True, "windows_attributes": None}):
            baseline = copy.deepcopy(self.existing)
            baseline[0]["mode"] = invalid
            with self.assertRaises(Denied):
                verify_protected(captured, baseline)
