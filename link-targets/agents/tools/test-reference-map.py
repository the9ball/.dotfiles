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
    """Create a minimal repository fixture for reference-map tests."""

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
    source: str,
    target: str,
    *,
    kind: str = "test",
    source_reference: bool = False,
    acyclic: bool = True,
    acyclic_reason: str | None = None,
) -> dict[str, str | bool]:
    """Create a valid fixture edge with optional source and cycle metadata."""

    result: dict[str, str | bool] = {
        "from": source,
        "to": target,
        "kind": kind,
        "when": "test",
        "purpose": "test",
    }
    if source_reference:
        result["source_reference"] = True
    if not acyclic:
        result["acyclic"] = False
    if acyclic_reason is not None:
        result["acyclic_reason"] = acyclic_reason
    return result


class ReferenceMapValidatorTests(unittest.TestCase):
    """Exercise graph, source-drift, discovery, and retirement invariants."""

    def run_validator(
        self, map_path: Path, cwd: Path | None = None
    ) -> subprocess.CompletedProcess[str]:
        """Run the validator against a fixture or the repository map."""

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

    def test_acyclic_false_on_workflow_dependency_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root,
                [
                    edge(".agents/caller.md", ".agents/guides/example.md"),
                    edge(
                        ".agents/caller.md",
                        ".agents/target.md",
                        kind="workflow-reference",
                        acyclic=False,
                        acyclic_reason="manual-navigation",
                    ),
                ],
            )
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "acyclic=false is not allowed for edge kind", result.stderr
            )

    def test_acyclic_false_requires_an_allowlisted_reason(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root,
                [
                    edge(".agents/caller.md", ".agents/guides/example.md"),
                    edge(
                        ".agents/caller.md",
                        ".agents/target.md",
                        kind="reference-index",
                        acyclic=False,
                    ),
                ],
            )
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("acyclic_reason must be one of", result.stderr)

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
        """Validate the checked-in repository map and its final counts."""

        result = self.run_validator((SCRIPT.parent.parent / "reference-map.json").resolve())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("declared edges", result.stdout)
        self.assertIn("acyclic edges", result.stdout)

    def test_first_wave_discovery_and_dependency_edges(self) -> None:
        """Check owner Skills, host discovery, and preserved conditional closure."""

        map_path = (SCRIPT.parent.parent / "reference-map.json").resolve()
        document = json.loads(map_path.read_text(encoding="utf-8"))
        first_wave = {
            "agent-output",
            "approval-request-workflow",
            "commit-message",
            "delegation",
            "dotnet-testing",
            "external-posting",
            "git-operations",
            "github",
            "structured-data",
        }
        nodes = {node["path"]: node for node in document["nodes"]}
        edges = {
            (edge["from"], edge["to"]): edge for edge in document["edges"]
        }
        for name in first_wave:
            skill_path = f"link-targets/agents/skills/{name}/SKILL.md"
            node = nodes[skill_path]
            self.assertEqual(node["kind"], "skill-entrypoint")
            self.assertEqual(
                set(node["discovery"]),
                {"positive", "negative", "conditional", "failure"},
            )
            self.assertIn(
                ("link-targets/agents/skills", skill_path), edges
            )
            skill_text = (map_path.parent / "skills" / name / "SKILL.md").read_text(
                encoding="utf-8"
            )
            for marker in (
                "## Discovery contract",
                "## Runtime contract",
                "## Guide",
                "Positive trigger:",
                "Negative trigger:",
                "Conditional dependency:",
                "Failure mode:",
            ):
                self.assertIn(marker, skill_text)

        expected_dependencies = {
            (
                "link-targets/agents/skills/agent-output/SKILL.md",
                "link-targets/agents/AGENTS.md",
            ),
            (
                "link-targets/agents/skills/approval-request-workflow/SKILL.md",
                "link-targets/agents/guides/external-operation-authorization.md",
            ),
            (
                "link-targets/agents/skills/approval-request-workflow/SKILL.md",
                "link-targets/agents/guides/approval-request-workflow.design.md",
            ),
            (
                "link-targets/agents/skills/delegation/SKILL.md",
                "link-targets/agents/guides/model-gpt-5.6.md",
            ),
            (
                "link-targets/agents/skills/delegation/SKILL.md",
                "link-targets/agents/guides/model-gpt-6-astra.md",
            ),
            (
                "link-targets/agents/skills/delegation/SKILL.md",
                "link-targets/agents/AGENTS.md",
            ),
            (
                "link-targets/agents/skills/delegation/SKILL.md",
                "link-targets/agents/reference-map.json",
            ),
            (
                "link-targets/agents/skills/external-posting/SKILL.md",
                "link-targets/agents/guides/external-operation-authorization.md",
            ),
            (
                "link-targets/agents/skills/git-operations/SKILL.md",
                "link-targets/agents/AGENTS.md",
            ),
            (
                "link-targets/agents/skills/git-operations/SKILL.md",
                "link-targets/agents/reference-map.json",
            ),
            (
                "link-targets/agents/skills/git-operations/SKILL.md",
                "link-targets/agents/skills/commit-message/SKILL.md",
            ),
            (
                "link-targets/agents/skills/github/SKILL.md",
                "link-targets/agents/guides/github.design.md",
            ),
            (
                "link-targets/agents/skills/github/SKILL.md",
                "link-targets/agents/AGENTS.md",
            ),
            (
                "link-targets/agents/skills/review-consolidation/SKILL.md",
                "link-targets/agents/skills/github/SKILL.md",
            ),
            (
                "link-targets/agents/skills/review-consolidation/SKILL.md",
                "link-targets/agents/skills/approval-request-workflow/SKILL.md",
            ),
            (
                "link-targets/agents/skills/review-consolidation/SKILL.md",
                "link-targets/agents/skills/external-posting/SKILL.md",
            ),
        }
        for dependency in expected_dependencies:
            self.assertIn(dependency, edges)
        self.assertEqual(
            set(document["retired_paths"]),
            {
                f"link-targets/agents/guides/{name}.md" for name in first_wave
            },
        )

    def test_edge_count_split_is_exact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            navigation_edge = edge(
                ".agents/caller.md",
                ".agents/target.md",
                kind="reference-index",
                acyclic=False,
                acyclic_reason="manual-navigation",
            )
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
        """Reject a source-reference edge whose literal evidence was removed."""

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

    def test_skill_discovery_contract_is_machine_checked(self) -> None:
        """Require discovery metadata and every runtime Guide contract section."""

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root,
                [
                    edge(".agents/caller.md", ".agents/guides/example.md"),
                    edge(".agents/caller.md", ".agents/target.md"),
                ],
            )
            skill_directory = root / ".agents" / "skills" / "example"
            skill_directory.mkdir(parents=True)
            skill_path = skill_directory / "SKILL.md"
            skill_path.write_text(
                "---\n"
                "name: example\n"
                "description: Example positive trigger.\n"
                "---\n\n"
                "# Example\n\n"
                "## Discovery contract\n\n"
                "- Positive trigger: example.\n"
                "- Negative trigger: unrelated.\n"
                "- Conditional dependency: none.\n"
                "- Failure mode: fail-safe.\n\n"
                "## Runtime contract\n\n"
                "Stop safely when unavailable.\n\n"
                "## Guide\n\n"
                "Normative contract.\n",
                encoding="utf-8",
            )
            document = json.loads(map_path.read_text(encoding="utf-8"))
            document["nodes"].append(
                {
                    "path": ".agents/skills/example/SKILL.md",
                    "kind": "skill-entrypoint",
                    "classification": "task-specific workflow",
                    "inbound_required": True,
                    "discovery": {
                        "positive": "example",
                        "negative": "unrelated",
                        "conditional": "none",
                        "failure": "fail-safe",
                    },
                }
            )
            document["edges"].append(
                edge(".agents/caller.md", ".agents/skills/example/SKILL.md")
            )
            map_path.write_text(json.dumps(document), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertEqual(result.returncode, 0, result.stderr)

            skill_path.write_text(
                skill_path.read_text(encoding="utf-8").replace("## Guide", "## Missing"),
                encoding="utf-8",
            )
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("## Guide", result.stderr)

    def test_skill_discovery_failure_mode_is_fail_safe(self) -> None:
        """Reject discovery metadata that permits a silent dependency omission."""

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root,
                [
                    edge(".agents/caller.md", ".agents/guides/example.md"),
                    edge(".agents/caller.md", ".agents/target.md"),
                ],
            )
            skill_directory = root / ".agents" / "skills" / "example"
            skill_directory.mkdir(parents=True)
            (skill_directory / "SKILL.md").write_text(
                "---\nname: example\ndescription: trigger\n---\n\n"
                "## Discovery contract\n\n"
                "- Positive trigger: example.\n"
                "- Negative trigger: unrelated.\n"
                "- Conditional dependency: none.\n"
                "- Failure mode: continue silently.\n\n"
                "## Runtime contract\n\nRuntime.\n\n## Guide\n\nGuide.\n",
                encoding="utf-8",
            )
            document = json.loads(map_path.read_text(encoding="utf-8"))
            document["nodes"].append(
                {
                    "path": ".agents/skills/example/SKILL.md",
                    "kind": "skill-entrypoint",
                    "classification": "task-specific workflow",
                    "inbound_required": True,
                    "discovery": {
                        "positive": "example",
                        "negative": "unrelated",
                        "conditional": "none",
                        "failure": "continue silently",
                    },
                }
            )
            document["edges"].append(
                edge(".agents/caller.md", ".agents/skills/example/SKILL.md")
            )
            map_path.write_text(json.dumps(document), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("fail-safe", result.stderr)

    def test_retired_path_literal_fails(self) -> None:
        """Reject a retired path that remains in a non-exempt tracked source."""

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
                "The retired path is .agents/retired.md.\n", encoding="utf-8"
            )
            document = json.loads(map_path.read_text(encoding="utf-8"))
            document["retired_paths"] = [".agents/retired.md"]
            map_path.write_text(json.dumps(document), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("retired path remains", result.stderr)


if __name__ == "__main__":
    unittest.main()
