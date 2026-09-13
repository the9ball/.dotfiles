#!/usr/bin/env python3
"""Regression tests for validate-reference-map.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("validate-reference-map.py")


def write_fixture(root: Path, edges: list[dict[str, str | bool]]) -> Path:
    agents_dir = root / ".agents"
    guides_dir = agents_dir / "guides"
    guides_dir.mkdir(parents=True)
    (guides_dir / "example.md").write_text("# example\n", encoding="utf-8")
    (agents_dir / "caller.md").write_text(
        "# caller\n\nSee `.agents/target.md`.\n", encoding="utf-8"
    )
    (agents_dir / "target.md").write_text("# target\n", encoding="utf-8")
    document = {
        "schema_version": 1,
        "repository_root": "..",
        "path_convention": "repository-root-relative",
        "nodes": [
            {
                "path": ".agents/guides/example.md",
                "kind": "shared-reference",
                "classification": "task-specific workflow",
                "inbound_required": True,
            },
            {
                "path": ".agents/caller.md",
                "kind": "caller",
                "classification": "repository / safety / operational policy",
                "inbound_required": False,
            },
            {
                "path": ".agents/target.md",
                "kind": "target",
                "classification": "task-specific workflow",
                "inbound_required": True,
            },
        ],
        "edges": edges,
    }
    map_path = agents_dir / "reference-map.json"
    map_path.write_text(json.dumps(document), encoding="utf-8")
    return map_path


def edge(
    source: str, target: str, *, source_reference: bool = False
) -> dict[str, str | bool]:
    result: dict[str, str | bool] = {
        "from": source,
        "to": target,
        "kind": "test",
        "when": "test",
        "purpose": "test",
    }
    if source_reference:
        result["source_reference"] = True
    return result


class ReferenceMapValidatorTests(unittest.TestCase):
    def run_validator(
        self, map_path: Path, cwd: Path | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--map", str(map_path)],
            check=False,
            capture_output=True,
            text=True,
            cwd=cwd,
        )

    def test_valid_map(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root,
                [
                    edge(".agents/caller.md", ".agents/guides/example.md"),
                    edge(".agents/caller.md", ".agents/target.md"),
                ],
            )
            result = self.run_validator(map_path)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_inbound_caller_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root, [edge(".agents/caller.md", ".agents/guides/example.md")]
            )
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("no inbound caller", result.stderr)

    def test_cycle_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root,
                [
                    edge(".agents/caller.md", ".agents/guides/example.md"),
                    edge(".agents/caller.md", ".agents/target.md"),
                    edge(".agents/target.md", ".agents/caller.md"),
                ],
            )
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("reference cycle", result.stderr)

    def test_missing_node_path_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root,
                [
                    edge(".agents/caller.md", ".agents/guides/example.md"),
                    edge(".agents/caller.md", ".agents/target.md"),
                ],
            )
            document = json.loads(map_path.read_text(encoding="utf-8"))
            document["nodes"].append(
                {
                    "path": ".agents/missing.md",
                    "kind": "target",
                    "classification": "task-specific workflow",
                    "inbound_required": False,
                }
            )
            map_path.write_text(json.dumps(document), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("does not exist", result.stderr)

    def test_source_edge_drift_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root, [edge(".agents/caller.md", ".agents/guides/example.md")]
            )
            document = json.loads(map_path.read_text(encoding="utf-8"))
            document["nodes"][2]["inbound_required"] = False
            map_path.write_text(json.dumps(document), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("source reference is missing from edges", result.stderr)

    def test_nested_markdown_destination_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root,
                [
                    edge(".agents/caller.md", ".agents/guides/example.md"),
                    edge(".agents/caller.md", ".agents/target.md"),
                ],
            )
            (root / ".agents" / "caller.md").write_text(
                "[target](.agents/target.md)\n", encoding="utf-8"
            )
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Markdown destination does not resolve", result.stderr)

    def test_file_relative_markdown_edge_drift_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root, [edge(".agents/caller.md", ".agents/guides/example.md")]
            )
            document = json.loads(map_path.read_text(encoding="utf-8"))
            document["nodes"][2]["inbound_required"] = False
            map_path.write_text(json.dumps(document), encoding="utf-8")
            (root / ".agents" / "caller.md").write_text(
                "[target](target.md)\n", encoding="utf-8"
            )
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Markdown reference is missing from edges", result.stderr)

    def test_repository_map_passes(self) -> None:
        result = self.run_validator((SCRIPT.parent.parent / "reference-map.json").resolve())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("declared edges", result.stdout)
        self.assertIn("acyclic edges", result.stdout)

    def test_edge_count_split_is_exact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            navigation_edge = edge(
                ".agents/caller.md", ".agents/target.md"
            )
            navigation_edge["acyclic"] = False
            map_path = write_fixture(
                root,
                [
                    edge(".agents/caller.md", ".agents/guides/example.md"),
                    navigation_edge,
                ],
            )
            result = self.run_validator(map_path)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("3 nodes, 2 declared edges, 1 acyclic edges", result.stdout)

    def test_repository_map_passes_from_outside_repository(self) -> None:
        map_path = (SCRIPT.parent.parent / "reference-map.json").resolve()
        with tempfile.TemporaryDirectory() as temporary_directory:
            result = self.run_validator(map_path, cwd=Path(temporary_directory))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_stale_source_reference_edge_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root,
                [
                    edge(".agents/caller.md", ".agents/guides/example.md"),
                    edge(
                        ".agents/caller.md",
                        ".agents/target.md",
                        source_reference=True,
                    ),
                ],
            )
            document = json.loads(map_path.read_text(encoding="utf-8"))
            document["nodes"][2]["inbound_required"] = False
            map_path.write_text(json.dumps(document), encoding="utf-8")
            (root / ".agents" / "caller.md").write_text(
                "# caller\n", encoding="utf-8"
            )
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("no source evidence", result.stderr)


if __name__ == "__main__":
    unittest.main()
