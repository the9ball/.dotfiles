#!/usr/bin/env python3
"""Validate the repository's shared-reference caller map.

The map is intentionally small and data-only.  This validator keeps path
resolution and graph checks outside the agent instructions so a stale or dead
reference fails deterministically before a host integration is changed.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Any


SCHEMA_VERSION = 1
WINDOWS_ABSOLUTE_PATH = re.compile(r"^[A-Za-z]:[\\/]")
ROOT_RELATIVE_REFERENCE = re.compile(
    r"(?<![A-Za-z0-9_])((?:\.agents|link-targets/agents|codex-wsl)/[A-Za-z0-9][A-Za-z0-9._/-]*)"
)
MARKDOWN_DESTINATION = re.compile(r"\]\(\s*([^)\s]+)")
EXTERNAL_DESTINATION = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")

# The inventory and its executable checks contain path literals as test data,
# not runtime references. Scanning them would make the source/map drift check
# report the validator's own implementation as a caller.
SOURCE_SCAN_EXCLUDED_KINDS = {
    "reference-inventory",
    "validation-tool",
    "validation-test",
}

# `acyclic: false` is reserved for edges that document a non-dependency.  The
# reason is part of the allowlist so a real workflow or contract dependency
# cannot silently opt out of cycle detection.
NON_DEPENDENCY_EDGE_REASONS: dict[str, frozenset[str]] = {
    "reference-index": frozenset({"manual-navigation"}),
    "host-reference": frozenset({"manual-navigation"}),
    "policy-reference": frozenset({"policy-precedence"}),
}


class ValidationError(Exception):
    """A user-facing map validation failure."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    default_map = Path(__file__).resolve().parent.parent / "reference-map.json"
    parser.add_argument(
        "--map",
        dest="map_path",
        type=Path,
        default=default_map,
        help="reference map to validate (default: link-targets/agents/reference-map.json)",
    )
    return parser.parse_args()


def read_json(map_path: Path) -> dict[str, Any]:
    try:
        with map_path.open(encoding="utf-8") as map_file:
            document = json.load(map_file)
    except FileNotFoundError as error:
        raise ValidationError(f"map does not exist: {map_path}") from error
    except json.JSONDecodeError as error:
        raise ValidationError(f"map is not valid JSON: {map_path}: {error}") from error
    except OSError as error:
        raise ValidationError(f"cannot read map {map_path}: {error}") from error

    if not isinstance(document, dict):
        raise ValidationError("map root must be a JSON object")
    return document


def repository_root(map_path: Path, document: dict[str, Any]) -> Path:
    root_spec = document.get("repository_root")
    if not isinstance(root_spec, str) or not root_spec:
        raise ValidationError("repository_root must be a non-empty string")
    if "\\" in root_spec or WINDOWS_ABSOLUTE_PATH.match(root_spec) or root_spec.startswith("/"):
        raise ValidationError("repository_root must be a local relative path")
    root = (map_path.resolve().parent / Path(root_spec)).resolve()
    if not root.is_dir():
        raise ValidationError(f"repository_root is not a directory: {root}")
    return root


def parse_relative_path(value: Any, field: str) -> PurePosixPath:
    if not isinstance(value, str) or not value:
        raise ValidationError(f"{field} must be a non-empty repository-relative path")
    if "\\" in value or WINDOWS_ABSOLUTE_PATH.match(value) or value.startswith("/"):
        raise ValidationError(f"{field} must use a POSIX repository-relative path: {value!r}")

    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts:
        raise ValidationError(f"{field} must not escape the repository root: {value!r}")
    return path


def resolve_repository_path(root: Path, value: Any, field: str) -> Path:
    relative = parse_relative_path(value, field)
    candidate = (root / Path(*relative.parts)).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise ValidationError(f"{field} resolves outside the repository: {value!r}") from error
    if not candidate.exists():
        raise ValidationError(f"{field} does not exist: {value!r}")
    return candidate


def validate_nodes(
    document: dict[str, Any], root: Path, map_path: Path
) -> dict[str, dict[str, Any]]:
    nodes = document.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        raise ValidationError("nodes must be a non-empty array")

    by_path: dict[str, dict[str, Any]] = {}
    for index, node in enumerate(nodes):
        if not isinstance(node, dict):
            raise ValidationError(f"nodes[{index}] must be an object")
        path_value = node.get("path")
        if not isinstance(path_value, str):
            raise ValidationError(f"nodes[{index}].path must be a string")
        parse_relative_path(path_value, f"nodes[{index}].path")
        if path_value in by_path:
            raise ValidationError(f"duplicate node path: {path_value}")
        resolve_repository_path(root, path_value, f"nodes[{index}].path")
        kind = node.get("kind")
        classification = node.get("classification")
        if not isinstance(kind, str) or not kind:
            raise ValidationError(f"nodes[{index}].kind must be a non-empty string")
        if not isinstance(classification, str) or not classification:
            raise ValidationError(
                f"nodes[{index}].classification must be a non-empty string"
            )
        inbound_required = node.get("inbound_required", True)
        if not isinstance(inbound_required, bool):
            raise ValidationError(f"nodes[{index}].inbound_required must be boolean")
        by_path[path_value] = node

    instruction_root = map_path.resolve().parent
    guides_dir = instruction_root / "guides"
    if guides_dir.is_dir():
        instruction_root_relative = instruction_root.relative_to(root).as_posix()
        listed_guides = {
            path
            for path in by_path
            if path.startswith(f"{instruction_root_relative}/guides/")
        }
        for guide_path in sorted(guides_dir.glob("*.md")):
            if guide_path.name.endswith(".history.md"):
                continue
            relative = guide_path.relative_to(root).as_posix()
            if relative not in listed_guides:
                raise ValidationError(f"guide is missing from nodes: {relative}")

    return by_path


def validate_edges(
    document: dict[str, Any],
    root: Path,
    nodes: dict[str, dict[str, Any]],
) -> tuple[list[tuple[str, str]], int]:
    edges = document.get("edges")
    if not isinstance(edges, list):
        raise ValidationError("edges must be an array")

    graph: list[tuple[str, str]] = []
    seen_edges: set[tuple[str, str, str]] = set()
    inbound: dict[str, int] = {path: 0 for path in nodes}
    for index, edge in enumerate(edges):
        if not isinstance(edge, dict):
            raise ValidationError(f"edges[{index}] must be an object")
        source = edge.get("from")
        target = edge.get("to")
        kind = edge.get("kind")
        if source not in nodes:
            raise ValidationError(f"edges[{index}].from is not a node: {source!r}")
        if target not in nodes:
            raise ValidationError(f"edges[{index}].to is not a node: {target!r}")
        if not isinstance(kind, str) or not kind:
            raise ValidationError(f"edges[{index}].kind must be a non-empty string")
        if "when" not in edge or not isinstance(edge["when"], str) or not edge["when"]:
            raise ValidationError(f"edges[{index}].when must be a non-empty string")
        if "purpose" not in edge or not isinstance(edge["purpose"], str) or not edge["purpose"]:
            raise ValidationError(f"edges[{index}].purpose must be a non-empty string")
        acyclic = edge.get("acyclic", True)
        if not isinstance(acyclic, bool):
            raise ValidationError(f"edges[{index}].acyclic must be boolean")
        acyclic_reason = edge.get("acyclic_reason")
        if acyclic_reason is not None and (
            not isinstance(acyclic_reason, str) or not acyclic_reason
        ):
            raise ValidationError(
                f"edges[{index}].acyclic_reason must be a non-empty string"
            )
        if acyclic:
            if acyclic_reason is not None:
                raise ValidationError(
                    f"edges[{index}].acyclic_reason requires acyclic=false"
                )
        else:
            allowed_reasons = NON_DEPENDENCY_EDGE_REASONS.get(kind, frozenset())
            if not allowed_reasons:
                raise ValidationError(
                    "edges[{}].acyclic=false is not allowed for edge kind {!r}; "
                    "only explicitly allowlisted non-dependency edges may opt "
                    "out of cycle detection".format(index, kind)
                )
            if acyclic_reason not in allowed_reasons:
                allowed = ", ".join(sorted(allowed_reasons))
                raise ValidationError(
                    f"edges[{index}].acyclic_reason must be one of {allowed!r} "
                    f"for edge kind {kind!r}"
                )
        source_reference = edge.get("source_reference", False)
        if not isinstance(source_reference, bool):
            raise ValidationError(
                f"edges[{index}].source_reference must be boolean"
            )
        resolve_repository_path(root, source, f"edges[{index}].from")
        resolve_repository_path(root, target, f"edges[{index}].to")

        identity = (source, target, kind)
        if identity in seen_edges:
            raise ValidationError(f"duplicate edge: {source} -> {target} ({kind})")
        seen_edges.add(identity)
        if acyclic:
            graph.append((source, target))
        inbound[target] += 1

    missing_callers = sorted(
        path
        for path, node in nodes.items()
        if node.get("inbound_required", True) and inbound[path] == 0
    )
    if missing_callers:
        raise ValidationError(
            "required nodes have no inbound caller: " + ", ".join(missing_callers)
        )
    return graph, len(edges)


def detect_cycles(nodes: dict[str, dict[str, Any]], edges: list[tuple[str, str]]) -> None:
    graph: dict[str, list[str]] = {path: [] for path in nodes}
    for source, target in edges:
        graph[source].append(target)

    state: dict[str, int] = {path: 0 for path in nodes}
    stack: list[str] = []

    def visit(path: str) -> None:
        state[path] = 1
        stack.append(path)
        for target in graph[path]:
            if state[target] == 0:
                visit(target)
            elif state[target] == 1:
                cycle_start = stack.index(target)
                cycle = stack[cycle_start:] + [target]
                raise ValidationError("reference cycle: " + " -> ".join(cycle))
        stack.pop()
        state[path] = 2

    for path in nodes:
        if state[path] == 0:
            visit(path)


def source_text(root: Path, relative_path: str) -> str | None:
    path = root / Path(*parse_relative_path(relative_path, "source path").parts)
    if not path.is_file():
        return None
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None
    except OSError as error:
        raise ValidationError(f"cannot read source {relative_path!r}: {error}") from error


def validate_source_references(
    root: Path,
    nodes: dict[str, dict[str, Any]],
    document: dict[str, Any],
) -> None:
    """Check that source path references agree with the inventory."""

    edges = document.get("edges", [])
    registered_pairs = {
        (edge.get("from"), edge.get("to"))
        for edge in edges
        if isinstance(edge, dict)
    }
    discovered_pairs: set[tuple[str, str]] = set()

    for source_path, node in nodes.items():
        if node.get("kind") in SOURCE_SCAN_EXCLUDED_KINDS:
            continue
        text = source_text(root, source_path)
        if text is None:
            continue

        # Resolve every local destination as Markdown would. A repository-root
        # logical path is not a portable destination from a nested source, so
        # this catches both broken root-relative links and missing file-relative
        # caller edges. Code-span logical paths remain portable references.
        for match in MARKDOWN_DESTINATION.finditer(text):
            destination = match.group(1)
            if (
                destination.startswith(("#", "/", "~"))
                or EXTERNAL_DESTINATION.match(destination)
            ):
                continue
            destination = destination.split("#", 1)[0].split("?", 1)[0]
            if not destination:
                continue
            source_parent = (
                root / Path(*PurePosixPath(source_path).parent.parts)
            ).resolve()
            resolved = (
                source_parent / Path(*PurePosixPath(destination).parts)
            ).resolve()
            try:
                resolved.relative_to(root)
            except ValueError as error:
                raise ValidationError(
                    "Markdown destination escapes repository: "
                    f"{source_path!r} -> {destination!r}"
                ) from error
            if not resolved.exists():
                raise ValidationError(
                    "Markdown destination does not resolve from source "
                    f"{source_path!r}: {destination!r}; use a file-relative "
                    "destination or a code-span logical path"
                )
            normalized = resolved.relative_to(root).as_posix()
            if normalized in nodes and normalized != source_path:
                discovered_pairs.add((source_path, normalized))
                if (source_path, normalized) not in registered_pairs:
                    raise ValidationError(
                        "Markdown reference is missing from edges: "
                        f"{source_path} -> {normalized}"
                    )

        for match in ROOT_RELATIVE_REFERENCE.finditer(text):
            destination = match.group(1).rstrip("/")
            if destination not in nodes or destination == source_path:
                continue
            discovered_pairs.add((source_path, destination))
            if (source_path, destination) not in registered_pairs:
                raise ValidationError(
                    "source reference is missing from edges: "
                    f"{source_path} -> {destination}"
                )

    stale_source_references = sorted(
        (edge.get("from"), edge.get("to"))
        for edge in edges
        if isinstance(edge, dict)
        and edge.get("source_reference", False)
        and (edge.get("from"), edge.get("to")) not in discovered_pairs
    )
    if stale_source_references:
        formatted = ", ".join(
            f"{source} -> {target}"
            for source, target in stale_source_references
        )
        raise ValidationError(
            "source-reference edges have no source evidence: " + formatted
        )


def frontmatter_value(text: str, key: str) -> str | None:
    """Return one simple frontmatter value from a Skill document."""

    if not text.startswith("---\n"):
        return None
    closing_marker = text.find("\n---", 4)
    if closing_marker == -1:
        return None
    frontmatter = text[4:closing_marker]
    prefix = f"{key}:"
    for line in frontmatter.splitlines():
        if line.startswith(prefix):
            value = line[len(prefix) :].strip()
            return value or None
    return None


def validate_skill_discovery(
    root: Path, nodes: dict[str, dict[str, Any]]
) -> None:
    """Validate discovery metadata and runtime Guide sections for migrated Skills."""

    required_metadata = {"positive", "negative", "conditional", "failure"}
    required_sections = {
        "## Discovery contract",
        "Positive trigger:",
        "Negative trigger:",
        "Conditional dependency:",
        "Failure mode:",
        "## Runtime contract",
        "## Guide",
    }
    for node_path, node in nodes.items():
        metadata = node.get("discovery")
        if metadata is None:
            continue
        if node.get("kind") != "skill-entrypoint":
            raise ValidationError(
                f"discovery metadata requires a skill-entrypoint node: {node_path}"
            )
        if not isinstance(metadata, dict):
            raise ValidationError(f"discovery metadata must be an object: {node_path}")
        if set(metadata) != required_metadata:
            missing = sorted(required_metadata - set(metadata))
            extra = sorted(set(metadata) - required_metadata)
            details: list[str] = []
            if missing:
                details.append("missing " + ", ".join(missing))
            if extra:
                details.append("unexpected " + ", ".join(extra))
            raise ValidationError(
                f"discovery metadata keys invalid for {node_path}: "
                + "; ".join(details)
            )
        for key, value in metadata.items():
            if not isinstance(value, str) or not value.strip():
                raise ValidationError(
                    f"discovery metadata {key!r} must be non-empty: {node_path}"
                )
        if "fail-safe" not in metadata["failure"].lower():
            raise ValidationError(
                f"discovery failure metadata must require fail-safe handling: {node_path}"
            )

        skill_path = root / Path(*parse_relative_path(node_path, "Skill path").parts)
        skill_text = source_text(root, node_path)
        if skill_text is None:
            raise ValidationError(f"Skill source is unreadable: {node_path}")
        expected_name = skill_path.parent.name
        if frontmatter_value(skill_text, "name") != expected_name:
            raise ValidationError(
                f"Skill frontmatter name must match directory {expected_name!r}: "
                f"{node_path}"
            )
        if frontmatter_value(skill_text, "description") is None:
            raise ValidationError(f"Skill description is missing: {node_path}")
        missing_sections = sorted(
            section for section in required_sections if section not in skill_text
        )
        if missing_sections:
            raise ValidationError(
                f"Skill discovery/runtime sections missing from {node_path}: "
                + ", ".join(missing_sections)
            )


def tracked_paths(root: Path) -> list[Path]:
    """Return tracked repository paths, falling back to files for fixture roots."""

    try:
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            check=False,
            capture_output=True,
        )
    except OSError:
        result = None
    if result is not None and result.returncode == 0:
        return [
            root / Path(*PurePosixPath(path).parts)
            for path in result.stdout.decode("utf-8").split("\0")
            if path
        ]
    return [path for path in root.rglob("*") if path.is_file() and ".git" not in path.parts]


def validate_retired_paths(
    root: Path, map_path: Path, document: dict[str, Any]
) -> None:
    """Ensure retired guide paths are absent from tracked source references."""

    retired = document.get("retired_paths", [])
    if not isinstance(retired, list):
        raise ValidationError("retired_paths must be an array")
    retired_paths: list[str] = []
    for index, value in enumerate(retired):
        parse_relative_path(value, f"retired_paths[{index}]")
        if (root / Path(*PurePosixPath(value).parts)).exists():
            raise ValidationError(f"retired path still exists: {value}")
        retired_paths.append(value)

    exclusions = document.get("retired_path_exclusions", [])
    if not isinstance(exclusions, list):
        raise ValidationError("retired_path_exclusions must be an array")
    try:
        map_relative = map_path.resolve().relative_to(root).as_posix()
    except ValueError as error:
        raise ValidationError("map path must be inside repository_root") from error
    exclusion_paths = {map_relative}
    for index, value in enumerate(exclusions):
        parse_relative_path(value, f"retired_path_exclusions[{index}]")
        resolve_repository_path(root, value, f"retired_path_exclusions[{index}]")
        exclusion_paths.add(value)

    if not retired_paths:
        return
    for candidate in tracked_paths(root):
        if not candidate.is_file():
            continue
        try:
            relative = candidate.resolve().relative_to(root).as_posix()
        except ValueError:
            continue
        if relative in exclusion_paths:
            continue
        try:
            content = candidate.read_bytes()
        except OSError as error:
            raise ValidationError(f"cannot read tracked source {relative!r}: {error}") from error
        for retired_path in retired_paths:
            if retired_path.encode("utf-8") in content:
                raise ValidationError(
                    f"retired path remains in tracked source {relative}: {retired_path}"
                )


def validate(document: dict[str, Any], map_path: Path) -> tuple[int, int, int, Path]:
    """Validate schema, graph, source evidence, discovery, and retirement state."""

    if document.get("schema_version") != SCHEMA_VERSION:
        raise ValidationError(
            f"unsupported schema_version: {document.get('schema_version')!r}"
        )
    if document.get("path_convention") != "repository-root-relative":
        raise ValidationError("path_convention must be repository-root-relative")

    root = repository_root(map_path, document)
    nodes = validate_nodes(document, root, map_path)
    edges, declared_edge_count = validate_edges(document, root, nodes)
    detect_cycles(nodes, edges)
    validate_source_references(root, nodes, document)
    validate_skill_discovery(root, nodes)
    validate_retired_paths(root, map_path, document)
    return len(nodes), declared_edge_count, len(edges), root


def main() -> int:
    arguments = parse_args()
    map_path = arguments.map_path.resolve()
    try:
        document = read_json(map_path)
        node_count, declared_edge_count, acyclic_edge_count, root = validate(
            document, map_path
        )
    except ValidationError as error:
        print(f"reference map invalid: {error}", file=sys.stderr)
        return 1

    print(
        "reference map OK: "
        f"{node_count} nodes, {declared_edge_count} declared edges, "
        f"{acyclic_edge_count} acyclic edges, repository root {root}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
