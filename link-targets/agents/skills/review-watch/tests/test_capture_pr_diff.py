"""Exercise immutable acquisition and publication without network access."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "capture_pr_diff", Path(__file__).parents[1] / "scripts" / "capture-pr-diff.py")
snapshot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(snapshot)
BASE, HEAD, MERGE = "a" * 40, "b" * 40, "c" * 40
PAYLOAD = b"diff --git a/a.txt b/a.txt\nindex 7898192..6178079 100644\n--- a/a.txt\n+++ b/a.txt\n@@ -1 +1 @@\n-a\n+b\n"
# Select an explicit concrete Git executable through this variable on hosts with launchers.
GIT = os.environ.get("REVIEW_WATCH_TEST_GIT", "git")


class FakeAPI:
    """Supply fixed API fixtures while running the real read-only Git parser."""

    def __init__(self):
        """Initialize independently mutable responses and a request log."""
        self.pull = {"number": 7, "base": {"repo": {"full_name": "owner/repo"}, "sha": BASE},
                     "head": {"sha": HEAD}}
        self.comparison = {"base_commit": {"sha": BASE}, "merge_base_commit": {"sha": MERGE},
                           "files": [{"filename": "a.txt", "additions": 1, "deletions": 1}]}
        self.commit = {"sha": HEAD}
        self.payload = PAYLOAD
        self.media = None
        self.status = 200
        self.length = None
        self.calls = []

    def __call__(self, arguments, input=None):
        """Return mock official HTTP envelopes or actual local numstat output."""
        self.calls.append(arguments)
        if arguments[0] == GIT:
            return snapshot.run_process(arguments, input)
        endpoint = arguments[-1]
        requested = arguments[arguments.index("-H") + 1]
        is_diff = requested.endswith(".diff")
        if is_diff:
            body = self.payload
        elif "/pulls/" in endpoint:
            body = json.dumps(self.pull).encode()
        elif "/commits/" in endpoint:
            body = json.dumps(self.commit).encode()
        else:
            body = json.dumps(self.comparison).encode()
        media = self.media or ("application/vnd.github.diff" if is_diff else "application/json")
        length = len(body) if self.length is None else self.length
        envelope = f"HTTP/2.0 {self.status} OK\r\nContent-Type: {media}\r\nContent-Length: {length}\r\n\r\n".encode()
        return subprocess.CompletedProcess(arguments, 0, envelope + body, b"")


class SnapshotTests(unittest.TestCase):
    """Validate failure closure, immutable identities, and atomic publication."""

    def setUp(self):
        """Allocate an isolated output directory and mocked acquisition route."""
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.output = Path(self.directory.name) / "7.diff"
        self.api = FakeAPI()

    def capture(self):
        """Capture through fixture APIs and the selected concrete Git binary."""
        return snapshot.capture("owner/repo", 7, self.output, git=GIT, runner=self.api)

    def verify(self, data=None):
        """Verify an artifact against the original immutable identity."""
        return snapshot.verify_bytes(self.output.read_bytes() if data is None else data,
                                     "owner/repo", 7, BASE, HEAD, GIT, self.api)

    def test_fixed_tuple_and_exact_payload(self):
        """Every compare request retains the originally frozen commit pair."""
        metadata = self.capture()
        self.api.pull["head"]["sha"] = "d" * 40
        self.assertEqual(self.verify(), metadata)
        self.assertEqual(snapshot.decode_artifact(self.output.read_bytes())[1], PAYLOAD)
        compares = [call[-1] for call in self.api.calls if "/compare/" in call[-1]]
        self.assertEqual(compares, [f"repos/owner/repo/compare/{BASE}...{HEAD}"] * 2)
        self.assertEqual(sum("/pulls/" in call[-1] for call in self.api.calls), 1)
        self.assertTrue(any(call[-1] == f"repos/owner/repo/commits/{HEAD}" for call in self.api.calls))
        for call in self.api.calls:
            if call[0] != GIT:
                self.assertEqual(call[1:6], ["api", "--hostname", "github.com", "--include", "-H"])
                self.assertIn(call[6], ["Accept: application/vnd.github+json", "Accept: application/vnd.github.diff"])
                self.assertEqual(call[7:9], ["-H", "X-GitHub-Api-Version: 2022-11-28"])

    def test_missing_or_malformed_commits_stop_before_compare(self):
        """Missing or malformed frozen SHAs never enter a compare request."""
        for side in ("base", "head"):
            for invalid in (None, "main", "a" * 39, 42):
                with self.subTest(side=side, invalid=invalid):
                    self.api = FakeAPI()
                    self.api.pull[side]["sha"] = invalid
                    with self.assertRaises(snapshot.SnapshotError):
                        self.capture()
                    self.assertEqual(len(self.api.calls), 1)
                    self.assertIn("/pulls/", self.api.calls[0][-1])
        self.api = FakeAPI()
        self.capture()
        for base, head in ((None, HEAD), (BASE, None), (None, None)):
            with self.subTest(base=base, head=head), self.assertRaises(snapshot.SnapshotError):
                snapshot.verify_bytes(self.output.read_bytes(), "owner/repo", 7, base, head, GIT, self.api)

    def test_api_identity_and_envelope_failures_preserve_old(self):
        """Incorrect frozen identities and HTTP envelopes cannot replace old bytes."""
        mutations = ["head", "base", "status", "media", "length", "inventory", "cap", "truncated"]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.api = FakeAPI()
                self.output.write_bytes(b"legacy old")
                if mutation == "head":
                    self.api.commit["sha"] = "d" * 40
                elif mutation == "base":
                    self.api.comparison["base_commit"]["sha"] = "d" * 40
                elif mutation == "status":
                    self.api.status = 404
                elif mutation == "media":
                    self.api.media = "text/html"
                elif mutation == "length":
                    self.api.length = 99999
                elif mutation == "inventory":
                    self.api.comparison["files"][0]["additions"] = 2
                elif mutation == "cap":
                    self.api.comparison["files"] *= 300
                else:
                    self.api.payload = PAYLOAD[:-3]
                with self.assertRaises(snapshot.SnapshotError):
                    self.capture()
                self.assertEqual(self.output.read_bytes(), b"legacy old")

    def test_cache_rejection(self):
        """Legacy, malformed, changed payload and stale identity fail verification."""
        self.capture()
        good = self.output.read_bytes()
        for data in (b"legacy", snapshot.MAGIC + b"{}", good + b"changed"):
            with self.subTest(data=data[:30]), self.assertRaises(snapshot.SnapshotError):
                self.verify(data)
        with self.assertRaises(snapshot.SnapshotError):
            snapshot.verify_bytes(good, "owner/repo", 7, BASE, "d" * 40, GIT, self.api)
        metadata, payload = snapshot.decode_artifact(good)
        metadata["files"][0]["deletions"] = 2
        with self.assertRaises(snapshot.SnapshotError):
            self.verify(snapshot.MAGIC + json.dumps(metadata).encode() + b"\n\n" + payload)

    def test_missing_sections_and_error_body_fail_closed(self):
        """Omitted sections and an HTML body cannot become a trusted empty diff."""
        self.api.payload = b""
        with self.assertRaises(snapshot.SnapshotError):
            self.capture()
        self.api.comparison["files"] = []
        self.api.payload = b"<html>upstream failure</html>"
        with self.assertRaises(snapshot.SnapshotError):
            self.capture()
        self.assertFalse(self.output.exists())

    def test_invalid_routes_and_binary_coverage_are_rejected(self):
        """Route components are validated and coverage metadata cannot be altered."""
        for repo, number in (("owner/repo/extra", 7), ("owner/repo", True), ("../repo", 0)):
            with self.subTest(repo=repo, number=number), self.assertRaises(snapshot.SnapshotError):
                snapshot.capture(repo, number, self.output, git=GIT, runner=self.api)
        self.assertEqual(self.api.calls, [])
        self.capture()
        metadata, payload = snapshot.decode_artifact(self.output.read_bytes())
        metadata["binary_unreviewed"] = ["a.txt"]
        with self.assertRaises(snapshot.SnapshotError):
            self.verify(snapshot.MAGIC + json.dumps(metadata).encode() + b"\n\n" + payload)

    def test_unknown_cache_metadata_is_recaptured_atomically(self):
        """Malformed or unrecognized cache identity permits fresh verified capture."""
        unknown = [snapshot.MAGIC + b"{bad json}\n\nold",
                   snapshot.MAGIC + b"{incomplete",
                   snapshot.MAGIC + b"{}\n\nold",
                   snapshot.MAGIC + b'{"repo": "owner/repo", "number": "7"}\n\nold']
        for old in unknown:
            with self.subTest(old=old):
                self.api = FakeAPI()
                self.output.write_bytes(old)
                self.assertEqual(self.capture()["head"], HEAD)
                self.verify()
                self.output.write_bytes(old)
                self.api.commit["sha"] = "d" * 40
                with self.assertRaises(snapshot.SnapshotError):
                    self.capture()
                self.assertEqual(self.output.read_bytes(), old)

    def test_collision_does_not_fetch_or_overwrite(self):
        """A known different cache identity blocks acquisition before requests."""
        self.capture()
        good = self.output.read_bytes().replace(b'"number": 7', b'"number": 8')
        self.output.write_bytes(good)
        self.api.calls.clear()
        with self.assertRaises(snapshot.SnapshotError):
            self.capture()
        self.assertEqual(self.api.calls, [])
        self.assertEqual(self.output.read_bytes(), good)

    def test_write_and_replace_failure_preserve_only_owned_cleanup(self):
        """Prepublication failures preserve the old cache and unrelated partials."""
        unrelated = self.output.parent / "other.partial"
        unrelated.write_bytes(b"other")
        for operation in ("fsync", "replace"):
            self.output.write_bytes(b"old")
            with self.subTest(operation=operation), patch.object(snapshot.os, operation, side_effect=OSError):
                with self.assertRaisesRegex(snapshot.SnapshotError, "previous artifact preserved"):
                    self.capture()
            self.assertEqual(self.output.read_bytes(), b"old")
            self.assertEqual(list(self.output.parent.glob("*.partial")), [unrelated])

    def test_postpublication_failure_does_not_rollback(self):
        """Read-back failure reports unknown publication and retains new output."""
        self.output.write_bytes(b"old")
        original = snapshot.verify_bytes
        with patch.object(snapshot, "verify_bytes", side_effect=[{}, snapshot.SnapshotError("changed")]):
            with self.assertRaisesRegex(snapshot.SnapshotError, "unusable or unknown"):
                self.capture()
        self.assertTrue(self.output.read_bytes().startswith(snapshot.MAGIC))
        self.assertEqual(original(self.output.read_bytes(), "owner/repo", 7, BASE, HEAD, GIT, self.api)["head"], HEAD)

    def test_empty_binary_and_rename(self):
        """Empty, binary and rename diffs retain accurate inventory coverage."""
        fixtures = [(b"", [], []),
                    (b"diff --git a/image.bin b/image.bin\nindex 1111111..2222222 100644\nBinary files a/image.bin and b/image.bin differ\n",
                     [{"filename": "image.bin", "additions": 0, "deletions": 0}], ["image.bin"]),
                    (b"diff --git a/old.txt b/new.txt\nsimilarity index 100%\nrename from old.txt\nrename to new.txt\n",
                     [{"filename": "new.txt", "additions": 0, "deletions": 0}], [])]
        for payload, files, binary in fixtures:
            with self.subTest(files=files):
                self.api.payload, self.api.comparison["files"] = payload, files
                self.assertEqual(self.capture()["binary_unreviewed"], binary)
                self.verify()


if __name__ == "__main__":
    unittest.main()
