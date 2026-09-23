#!/usr/bin/env python3
"""Regression tests for validate-reference-map.py."""

from __future__ import annotations

import json
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("validate-reference-map.py")
VALIDATOR_SPEC = importlib.util.spec_from_file_location("reference_map_validator", SCRIPT)
assert VALIDATOR_SPEC is not None and VALIDATOR_SPEC.loader is not None
VALIDATOR = importlib.util.module_from_spec(VALIDATOR_SPEC)
previous_bytecode_setting = sys.dont_write_bytecode
sys.dont_write_bytecode = True
try:
    VALIDATOR_SPEC.loader.exec_module(VALIDATOR)
finally:
    sys.dont_write_bytecode = previous_bytecode_setting


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

    def test_external_consumer_does_not_satisfy_inbound_caller(self) -> None:
        """External consumption must not masquerade as repository activation."""

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root, [edge(".agents/caller.md", ".agents/guides/example.md")]
            )
            document = json.loads(map_path.read_text(encoding="utf-8"))
            document["external_consumers"] = [
                {
                    "consumer": "GPT-Chat",
                    "target": ".agents/target.md",
                    "purpose": "external reference",
                }
            ]
            map_path.write_text(json.dumps(document), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("no inbound caller", result.stderr)

    def test_external_consumer_target_must_be_a_node(self) -> None:
        """External consumers must point at a tracked reference-map node."""

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
            document["external_consumers"] = [
                {
                    "consumer": "GPT-Chat",
                    "target": ".agents/missing.md",
                    "purpose": "external reference",
                }
            ]
            map_path.write_text(json.dumps(document), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("target is not a node", result.stderr)

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

    def test_normative_owner_registry_rejects_duplicate_and_drift(self) -> None:
        """Require one declared Skill owner for each migrated runtime contract."""

        map_path = (SCRIPT.parent.parent / "reference-map.json").resolve()
        document = VALIDATOR.read_json(map_path)
        root = VALIDATOR.repository_root(map_path, document)
        nodes = VALIDATOR.validate_nodes(document, root, map_path)

        duplicate_document = json.loads(json.dumps(document))
        duplicate_document["normative_owners"].append(
            dict(duplicate_document["normative_owners"][0])
        )
        with self.assertRaisesRegex(
            VALIDATOR.ValidationError, "duplicate normative source"
        ):
            VALIDATOR.validate_normative_owners(root, nodes, duplicate_document)

        drifted_document = json.loads(json.dumps(document))
        drifted_document["normative_owners"][0]["owner"] = (
            "link-targets/agents/skills/implementation-planning/SKILL.md"
        )
        with self.assertRaisesRegex(
            VALIDATOR.ValidationError, "normative contract owner drift"
        ):
            VALIDATOR.validate_normative_owners(root, nodes, drifted_document)

    def test_normative_skill_cannot_load_legacy_guide(self) -> None:
        """Reject an owner Skill that reaches back to its legacy guide path."""

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            owner_path = ".agents/skills/advisor-review/SKILL.md"
            legacy_path = ".agents/guides/advisor-review.md"
            owner_file = root / owner_path
            owner_file.parent.mkdir(parents=True)
            owner_file.write_text(
                "---\nname: advisor-review\ndescription: review\n---\n\n"
                "## Guide\n\nLoad .agents/guides/advisor-review.md.\n",
                encoding="utf-8",
            )
            (root / legacy_path).parent.mkdir(parents=True)
            (root / legacy_path).write_text("shim\n", encoding="utf-8")
            nodes = {
                owner_path: {"kind": "skill-entrypoint"},
                legacy_path: {"kind": "compatibility-fallback"},
            }
            document = {
                "normative_owners": [
                    {
                        "contract": "advisor-review",
                        "owner": owner_path,
                        "legacy_path": legacy_path,
                    }
                ],
                "compatibility_fallbacks": [
                    {"path": legacy_path, "owner": owner_path}
                ],
            }
            with self.assertRaisesRegex(
                VALIDATOR.ValidationError, "hidden Skill-to-legacy-guide loader"
            ):
                VALIDATOR.validate_normative_owners(root, nodes, document)

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
        second_wave = {
            "advisor-review",
            "external-operation-authorization",
            "implementation-planning",
        }
        discovery_skills = first_wave | second_wave
        nodes = {node["path"]: node for node in document["nodes"]}
        edges = {
            (edge["from"], edge["to"]): edge for edge in document["edges"]
        }
        for name in discovery_skills:
            skill_path = f"link-targets/agents/skills/{name}/SKILL.md"
            node = nodes[skill_path]
            self.assertEqual(node["kind"], "skill-entrypoint")
            self.assertEqual(node["host_fallback"], "required")
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
                "link-targets/agents/skills/external-operation-authorization/SKILL.md",
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
                "link-targets/agents/guides/model-gpt-6-sol.md",
            ),
            (
                "link-targets/agents/skills/delegation/SKILL.md",
                "link-targets/agents/guides/model-gpt-6-luna.md",
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
                "link-targets/agents/skills/external-operation-authorization/SKILL.md",
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
            (
                "link-targets/agents/skills/execution-lifecycle-gate/SKILL.md",
                "link-targets/agents/skills/advisor-review/SKILL.md",
            ),
            (
                "link-targets/agents/skills/execution-lifecycle-gate/SKILL.md",
                "link-targets/agents/skills/external-operation-authorization/SKILL.md",
            ),
            (
                "link-targets/agents/skills/rigorous-review/SKILL.md",
                "link-targets/agents/skills/advisor-review/SKILL.md",
            ),
            (
                "link-targets/agents/skills/rigorous-review/SKILL.md",
                "link-targets/agents/skills/implementation-planning/SKILL.md",
            ),
            (
                "link-targets/agents/skills/review-consolidation/SKILL.md",
                "link-targets/agents/skills/external-operation-authorization/SKILL.md",
            ),
            (
                "link-targets/agents/skills/approval-request-workflow/SKILL.md",
                "link-targets/agents/skills/external-operation-authorization/SKILL.md",
            ),
            (
                "link-targets/agents/guides/github-cli-without-clone.md",
                "link-targets/agents/skills/external-operation-authorization/SKILL.md",
            ),
            (
                "link-targets/agents/AGENTS.md",
                "link-targets/agents/skills/advisor-review/SKILL.md",
            ),
            (
                "link-targets/agents/AGENTS.md",
                "link-targets/agents/skills/implementation-planning/SKILL.md",
            ),
            (
                "link-targets/agents/AGENTS.md",
                "link-targets/agents/skills/external-operation-authorization/SKILL.md",
            ),
            (
                "link-targets/claude/agents/architect.md",
                "link-targets/agents/skills/implementation-planning/SKILL.md",
            ),
        }
        for dependency in expected_dependencies:
            self.assertIn(dependency, edges)
        fallback_paths = {
            fallback["path"] for fallback in document["compatibility_fallbacks"]
        }
        self.assertEqual(
            fallback_paths,
            {f"link-targets/agents/guides/{name}.md" for name in discovery_skills},
        )
        for fallback in document["compatibility_fallbacks"]:
            path = fallback["path"]
            owner = fallback["owner"]
            router = fallback["router"]
            fallback_text = (map_path.parent.parent.parent / path).read_text(
                encoding="utf-8"
            )
            self.assertEqual(nodes[path]["kind"], "compatibility-fallback")
            self.assertEqual(fallback["host"], "Claude Code")
            self.assertIn((router, path), edges)
            self.assertIn((path, owner), edges)
            self.assertIn(owner, fallback_text)
            self.assertIn("no runtime rules", " ".join(fallback_text.lower().split()))
            self.assertEqual(router, "chezmoi/dot_claude/CLAUDE.md")
        self.assertEqual(
            set(document["retired_paths"]),
            {
                "link-targets/agents/guides/approval-request-workflow.design.md",
                "link-targets/agents/guides/github.design.md",
            },
        )
        self.assertEqual(
            {record["contract"] for record in document["normative_owners"]},
            second_wave,
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
                    "host_fallback": "exempt",
                    "host_fallback_reason": "fixture is not testing host fallback",
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

            del document["nodes"][-1]["host_fallback"]
            map_path.write_text(json.dumps(document), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("host_fallback", result.stderr)
            document["nodes"][-1]["host_fallback"] = "exempt"

            document["nodes"][-1]["host_fallback"] = "required"
            map_path.write_text(json.dumps(document), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("exactly one compatibility fallback", result.stderr)
            document["nodes"][-1]["host_fallback"] = "exempt"
            map_path.write_text(json.dumps(document), encoding="utf-8")

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
                    "host_fallback": "exempt",
                    "host_fallback_reason": "fixture is not testing host fallback",
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

    def test_compatibility_fallback_requires_a_single_skill_owner(self) -> None:
        """Reject malformed host shims and preserve their single Skill owner."""

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            map_path = write_fixture(
                root,
                [
                    edge(".agents/caller.md", ".agents/guides/example.md"),
                    edge(".agents/caller.md", ".agents/target.md"),
                ],
            )
            router_path = root / ".agents" / "CLAUDE.md"
            router_path.write_text(
                "Use `.agents/guides/example.md` as the fallback.\n",
                encoding="utf-8",
            )
            skill_directory = root / ".agents" / "skills" / "example"
            skill_directory.mkdir(parents=True)
            owner_path = skill_directory / "SKILL.md"
            owner_path.write_text("# example skill\n", encoding="utf-8")
            shim_path = root / ".agents" / "guides" / "example.md"
            backtick = chr(96)
            valid_shim = (
                "# Claude Code compatibility shim: example\n\n"
                "This temporary host fallback exists for Issue #75. The normative runtime\n"
                f"contract is {backtick}.agents/skills/example/SKILL.md{backtick}. "
                f"Read that Skill and apply its {backtick}## Guide{backtick} section;\n"
                "this shim defines no runtime rules of its own.\n"
                "If the Skill cannot be resolved, stop and report.\n"
            )
            shim_path.write_text(valid_shim, encoding="utf-8")
            document = json.loads(map_path.read_text(encoding="utf-8"))
            document["nodes"].append(
                {
                    "path": ".agents/CLAUDE.md",
                    "kind": "host-integration",
                    "classification": "host integration",
                    "inbound_required": False,
                }
            )
            document["nodes"][0]["kind"] = "compatibility-fallback"
            document["nodes"].append(
                {
                    "path": ".agents/skills/example/SKILL.md",
                    "kind": "skill-entrypoint",
                    "classification": "task-specific workflow",
                    "inbound_required": True,
                }
            )
            document["edges"].extend(
                [
                    edge(
                        ".agents/CLAUDE.md",
                        ".agents/guides/example.md",
                        kind="host-fallback",
                        source_reference=True,
                    ),
                    edge(
                        ".agents/guides/example.md",
                        ".agents/skills/example/SKILL.md",
                        kind="compatibility-fallback",
                    ),
                ]
            )
            document["compatibility_fallbacks"] = [
                {
                    "path": ".agents/guides/example.md",
                    "owner": ".agents/skills/example/SKILL.md",
                    "router": ".agents/CLAUDE.md",
                    "host": "Claude Code",
                    "retire_after": "Issue #75",
                }
            ]
            map_path.write_text(json.dumps(document), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertEqual(result.returncode, 0, result.stderr)

            valid_document = json.loads(json.dumps(document))
            valid_router = router_path.read_text(encoding="utf-8")
            valid_shim = shim_path.read_text(encoding="utf-8")

            def restore_valid() -> None:
                """Restore the valid fixture before the next negative case."""

                map_path.write_text(json.dumps(valid_document), encoding="utf-8")
                router_path.write_text(valid_router, encoding="utf-8")
                shim_path.write_text(valid_shim, encoding="utf-8")

            shim_path.write_text("fallback without owner\n", encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("does not name its Skill owner", result.stderr)

            restore_valid()
            shim_path.write_text(
                valid_shim + "Run an additional operation-specific rule.\n",
                encoding="utf-8",
            )
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("compatibility fallback may contain only", result.stderr)

            restore_valid()
            invalid_owner_kind = json.loads(json.dumps(valid_document))
            for node in invalid_owner_kind["nodes"]:
                if node["path"] == ".agents/skills/example/SKILL.md":
                    node["kind"] = "shared-reference"
            map_path.write_text(json.dumps(invalid_owner_kind), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("owner is not a Skill entrypoint", result.stderr)

            restore_valid()
            missing_router_edge = json.loads(json.dumps(valid_document))
            missing_router_edge["edges"] = [
                edge_value
                for edge_value in missing_router_edge["edges"]
                if not (
                    edge_value["from"] == ".agents/CLAUDE.md"
                    and edge_value["to"] == ".agents/guides/example.md"
                    and edge_value["kind"] == "host-fallback"
                )
            ]
            router_path.write_text("fallback registry entry\n", encoding="utf-8")
            map_path.write_text(json.dumps(missing_router_edge), encoding="utf-8")
            result = self.run_validator(map_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("router edge is missing", result.stderr)

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
