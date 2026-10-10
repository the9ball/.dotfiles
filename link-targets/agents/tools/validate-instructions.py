#!/usr/bin/env python3
"""Check canonical instruction references without a separate caller registry."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath


AGENTS = "link-targets/agents"
GUIDES = f"{AGENTS}/guides"
SKILLS = f"{AGENTS}/skills"
ROUTER = "chezmoi/dot_claude/CLAUDE.md"
HOST_LOCAL = f"{AGENTS}/AGENTS.local.md"
LOGICAL_REFERENCE = re.compile(
    r"(?<![A-Za-z0-9_.-])((?:link-targets/agents|\.agents|codex-wsl)/[A-Za-z0-9][A-Za-z0-9._/-]*)"
)
MARKDOWN_LINK = re.compile(r"\]\(\s*([^\s)]+)")
ANNOTATION = re.compile(
    r"<!-- reference-kind: ([a-z-]+); target: ([^\s]+) -->"
)
PREFIXED_ALIAS = re.compile(rb"\.agents[/\\]+link-targets(?![A-Za-z0-9_.-])")
HOST_ALIAS_MAPPING = (
    "~/.agents is the link-targets/agents directory itself: drop the leading "
    "link-targets/agents/ from a logical path to reach it under ~/.agents"
)
RETIREMENT_START = "<!-- retired-paths:start -->"
RETIREMENT_END = "<!-- retired-paths:end -->"


class ValidationError(ValueError):
    """Report an unresolved or inconsistent instruction reference."""


def instruction_root(loaded_path: Path) -> Path:
    """Derive one canonical root from an existing loaded entity, never CWD."""
    try:
        entity = loaded_path.resolve(strict=True)
        if not entity.is_file():
            raise ValidationError(f"loaded instruction is not a file: {loaded_path}")
        candidates = []
        for ancestor in entity.parents:
            if ancestor.name != "agents" or ancestor.parent.name != "link-targets":
                continue
            sentinels = [ancestor / "AGENTS.md", ancestor / "guides/README.md"]
            if not all(path.is_file() for path in sentinels):
                continue
            for sentinel in sentinels:
                sentinel.resolve(strict=True).relative_to(ancestor)
            candidates.append(ancestor)
        if len(candidates) != 1:
            raise ValidationError(
                f"instruction root must be unique (found {len(candidates)}): {loaded_path}"
            )
        entity.relative_to(candidates[0])
        return candidates[0].parent.parent
    except (OSError, RuntimeError, ValueError) as error:
        if isinstance(error, ValidationError):
            raise
        raise ValidationError(f"cannot resolve canonical instruction: {loaded_path}: {error}") from error


def canonical_path(value: str) -> str:
    """Normalize a published agents alias into its canonical logical path."""
    if value.startswith(".agents/"):
        return AGENTS + value[len(".agents"):]
    return value


def resolve_target(root: Path, value: str) -> str:
    """Check a logical target exists inside the fixed root after link resolution."""
    logical = PurePosixPath(canonical_path(value))
    if logical.is_absolute() or re.match(r"^[A-Za-z]:", value) or ".." in logical.parts or "\\" in value:
        raise ValidationError(f"invalid logical reference: {value}")
    try:
        target = (root / logical).resolve(strict=True)
        target.relative_to(root)
    except (OSError, RuntimeError, ValueError) as error:
        raise ValidationError(f"missing or escaping reference: {value}") from error
    return logical.as_posix()


def source_paths(root: Path) -> list[str]:
    """Preserve Git ignore boundaries or enumerate an explicitly Git-free tree."""
    if os.path.lexists(root / ".git"):
        try:
            result = subprocess.run(
                ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                capture_output=True,
                check=False,
            )
        except OSError as error:
            raise ValidationError("git inventory unavailable in worktree") from error
        if result.returncode != 0:
            raise ValidationError("git inventory unavailable in worktree")
        return sorted(set(result.stdout.decode("utf-8").split("\0")) - {"", HOST_LOCAL})
    return sorted(
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and ".git" not in path.parts and path.relative_to(root).as_posix() != HOST_LOCAL
    )


def read_source(root: Path, path: str) -> str:
    """Read a bounded source only after verifying its real-path containment."""
    resolve_target(root, path)
    return (root / path).read_text(encoding="utf-8-sig")


def retirement_record(text: str) -> tuple[list[str], str]:
    """Extract the sole retirement history block while leaving active prose intact."""
    if text.count(RETIREMENT_START) != 1 or text.count(RETIREMENT_END) != 1:
        raise ValidationError("placement policy must contain exactly one retirement record")
    prefix, remainder = text.split(RETIREMENT_START)
    history, suffix = remainder.split(RETIREMENT_END)
    paths = re.findall(r"^- `([^`]+)`$", history, re.MULTILINE)
    if not paths or len(paths) != len(set(paths)):
        raise ValidationError("retirement record must name unique paths")
    for path in paths:
        if not path.startswith(AGENTS + "/") or ".." in PurePosixPath(path).parts:
            raise ValidationError(f"invalid retired path: {path}")
    return paths, prefix + suffix


def frontmatter_value(text: str, key: str) -> str | None:
    """Read a simple scalar from the existing Skill frontmatter convention."""
    if not text.startswith("---\n") or "\n---\n" not in text[4:]:
        return None
    header = text[4:].split("\n---\n", 1)[0]
    values = list(re.finditer(rf"^{re.escape(key)}:[ \t]*(.+)$", header, re.MULTILINE))
    if len(values) != 1:
        return None
    value = values[0].group(1).strip()
    if value in {">", "|", ">-", "|-", ">+", "|+"}:
        continuation = re.match(r"\n((?:[ \t]+[^\n]*\n?)+)", header[values[0].end():])
        return continuation.group(1).strip() if continuation and continuation.group(1).strip() else None
    return value


def check_frontmatter(path: str, text: str) -> None:
    """Require discovery metadata on every canonical direct Skill entrypoint."""
    if frontmatter_value(text, "name") != PurePosixPath(path).parent.name or not frontmatter_value(text, "description"):
        raise ValidationError(f"invalid Skill frontmatter: {path}")


def markdown_target(root: Path, source: str, destination: str) -> str | None:
    """Resolve a local Markdown destination, excluding only the private overlay."""
    destination = destination.strip("<>").split("#", 1)[0].split("?", 1)[0]
    if not destination or destination.startswith(("/", "~")) or destination == "URL":
        return None
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", destination):
        return None
    requested = (root / source).parent.joinpath(destination)
    if Path(os.path.normpath(requested)) == root / HOST_LOCAL:
        return None
    try:
        return requested.resolve(strict=True).relative_to(root).as_posix()
    except (OSError, RuntimeError, ValueError) as error:
        raise ValidationError(f"invalid Markdown target: {source} -> {destination}") from error


def references(root: Path, source: str, text: str) -> set[str]:
    """Extract real references independently of graph-exemption annotations."""
    text = ANNOTATION.sub("", text)
    targets: set[str] = set()
    for match in MARKDOWN_LINK.finditer(text):
        target = markdown_target(root, source, match.group(1))
        if target is not None and target != source:
            targets.add(target)
    for match in LOGICAL_REFERENCE.finditer(text):
        target = canonical_path(match.group(1).rstrip("/"))
        if target == HOST_LOCAL:
            continue
        # Logical runtime state (logs and generated settings) is not an
        # instruction asset; local Markdown links still validate any file type.
        if PurePosixPath(target).suffix not in {".md", ".py", ".ps1", ".sh", ".tmpl"}:
            if PurePosixPath(target).suffix or not os.path.lexists(root / target):
                continue
        resolve_target(root, target)
        if target != source:
            targets.add(target)
    return targets


def non_dependencies(root: Path, source: str, text: str, targets: set[str]) -> set[str]:
    """Accept narrow documented navigation/precedence edges, never new loaders."""
    if "<!-- reference-kind:" in ANNOTATION.sub("", text):
        raise ValidationError(f"malformed reference annotation: {source}")
    excluded: set[str] = set()
    for kind, target in ANNOTATION.findall(text):
        if target not in targets or target in excluded:
            raise ValidationError(f"unbacked or duplicate reference annotation: {source} -> {target}")
        if kind == "policy-precedence":
            allowed = source.endswith("/SKILL.md") and target == f"{AGENTS}/AGENTS.md"
        elif kind == "owner-precedence":
            owner = PurePosixPath(target)
            allowed = (
                target.startswith(SKILLS + "/") and owner.name == "SKILL.md" and len(owner.parts) == 5
                and source == (owner.parent / "references/design.md").as_posix()
                and (root / source).resolve(strict=True) == (root / target).resolve(strict=True).parent / "references/design.md"
            )
            if allowed:
                links = [markdown_target(root, source, match.group(1)) for match in MARKDOWN_LINK.finditer(ANNOTATION.sub("", text))]
                allowed = links.count(target) == 1
        elif kind == "manual-navigation":
            allowed = source in {f"{GUIDES}/README.md", "codex-wsl/SETUP.md", "codex-wsl/CODEX_HOME.md"}
        else:
            allowed = False
        if not allowed:
            raise ValidationError(f"invalid non-dependency kind: {source}: {kind}")
        # An exemption documents an existing non-loading reference, not permission
        # to hide a read command added in an otherwise navigational source.
        for paragraph in re.split(r"\n\s*\n", ANNOTATION.sub("", text)):
            for statement in re.split(r"(?<=[.!?])\s+|\n(?=- )", paragraph):
                if not re.search(r"\b(read|load|apply|invoke|resolve|use|follow|run)\b", statement, re.IGNORECASE):
                    continue
                if target not in references(root, source, statement):
                    continue
                raise ValidationError(f"runtime loader cannot be exempted: {source} -> {target}")
        excluded.add(target)
    return excluded


def check_cycles(graph: dict[str, set[str]]) -> None:
    """Reject a circular read dependency, including its reproducible path."""
    visited: set[str] = set()
    active: list[str] = []

    def visit(node: str) -> None:
        """Traverse one source while retaining the current dependency stack."""
        if node in active:
            raise ValidationError("dependency cycle: " + " -> ".join(active + [node]))
        if node in visited:
            return
        active.append(node)
        for target in sorted(graph.get(node, set())):
            visit(target)
        active.pop()
        visited.add(node)

    for source in sorted(graph):
        visit(source)


def check_discovery(path: str, text: str) -> str:
    """Validate one managed Skill's canonical discovery and fallback contract."""
    check_frontmatter(path, text)
    for heading in ("Discovery contract", "Runtime contract", "Guide"):
        if not re.search(rf"^## {heading}$", text, re.MULTILINE):
            raise ValidationError(f"missing Skill section {heading}: {path}")
    discovery = text.split("## Discovery contract\n", 1)[1].split("\n## ", 1)[0]
    for label in ("Positive trigger", "Negative trigger", "Conditional dependency", "Failure mode"):
        values = re.findall(rf"^- {label}: (.+)$", discovery, re.MULTILINE)
        if len(values) != 1 or not values[0].strip():
            raise ValidationError(f"invalid discovery {label}: {path}")
        if label == "Failure mode":
            positive = re.search(r"\bstop\b|fail[- ]?safe", values[0], re.IGNORECASE)
            negative = re.search(r"\b(never|not|don't|do not|without)\s+(stop|fail)\b", values[0], re.IGNORECASE)
            if not positive or negative:
                raise ValidationError(f"discovery must fail closed: {path}")
    values = re.findall(r"^- Host fallback: (.+)$", discovery, re.MULTILINE)
    if len(values) != 1:
        raise ValidationError(f"missing unique host fallback declaration: {path}")
    value = values[0]
    if value != "required" and not re.fullmatch(r"exempt; .+", value):
        raise ValidationError(f"invalid host fallback declaration: {path}")
    return value


def has_contract_signal(text: str) -> bool:
    """Detect #75 participation while excluding ordinary Runtime/Guide bullets."""
    if "## Discovery contract" in text or re.search(r"^- Host fallback:", text, re.MULTILINE):
        return True
    preamble = re.split(r"^## (?:Runtime contract|Guide)[ \t]*$", text, maxsplit=1, flags=re.MULTILINE)[0]
    return bool(re.search(
        r"^- (Positive trigger|Negative trigger|Conditional dependency|Failure mode):", preamble, re.MULTILINE
    ))


def check_fallbacks(texts: dict[str, str], edges: dict[str, set[str]]) -> None:
    """Derive router/shim/owner coverage and enforce the Issue 75 thin template."""
    shims = {
        path: text for path, text in texts.items()
        if path.startswith(GUIDES + "/") and text.startswith("# Claude Code compatibility shim:")
    }
    owners: dict[str, str] = {}
    for path, text in shims.items():
        name = PurePosixPath(path).stem
        owner = f"{SKILLS}/{name}/SKILL.md"
        expected = (
            f"# Claude Code compatibility shim: {name} "
            "This temporary host fallback exists for Issue #75. The normative runtime "
            f"contract is {owner}. Resolve that logical path against the instruction "
            "root: the directory that contains the real link-targets directory enclosing "
            "this shim, after resolving every symlink/junction. Do not append it to a "
            "link that points at link-targets/agents itself, because the logical path "
            "already includes link-targets/agents. Read that Skill and apply its "
            "## Guide section; this shim defines no runtime rules of its own. If the "
            "Skill cannot be resolved, stop and report."
        )
        normalized = " ".join(text.replace("`", "").split())
        if normalized != expected:
            raise ValidationError(f"invalid shim owner/runtime rules/retirement: {path}")
        if owner in owners or owner not in texts:
            raise ValidationError(f"duplicate or missing shim owner: {path}")
        owners[owner] = path
        if path not in edges.get(ROUTER, set()) or owner not in edges.get(path, set()):
            raise ValidationError(f"missing router/shim/owner route: {path}")
        if name + ".md" in texts[owner]:
            raise ValidationError(f"hidden Skill-to-legacy loader: {owner}")
    # Host table rows remain authoritative even if a shim loses its heading.
    router_rows = "\n".join(line for line in texts.get(ROUTER, "").splitlines() if line.startswith("|"))
    routed_shims = {canonical_path(match.group(1)) for match in LOGICAL_REFERENCE.finditer(router_rows)}
    routed_shims = {target for target in routed_shims if target.startswith(GUIDES + "/")}
    if routed_shims != set(shims):
        raise ValidationError("host table and compatibility shims disagree")
    direct_owners = {
        target for source in (ROUTER, f"{AGENTS}/AGENTS.md")
        for target in edges.get(source, set()) if target.endswith("/SKILL.md")
    }
    for path, text in texts.items():
        if not path.endswith("/SKILL.md"):
            continue
        if path not in owners and path not in direct_owners and not has_contract_signal(text):
            continue
        fallback = check_discovery(path, text)
        if fallback == "required":
            if path not in owners:
                raise ValidationError(f"required discovery Skill has no single shim: {path}")
        else:
            if path in owners:
                raise ValidationError(f"exempt discovery Skill has a shim: {path}")
            direct_sources = {source for source, targets in edges.items() if path in targets}
            if not direct_sources.intersection({ROUTER, f"{AGENTS}/AGENTS.md"}):
                raise ValidationError(f"exempt discovery Skill has no direct host/kernel route: {path}")
    if ROUTER in texts and "Until Issue #75 is completed" not in texts[ROUTER]:
        raise ValidationError(f"host fallback retirement condition missing: {ROUTER}")
    if ROUTER in texts and HOST_ALIAS_MAPPING not in " ".join(texts[ROUTER].replace("`", "").split()):
        raise ValidationError(f"host alias mapping missing: {ROUTER}")


def validate(root: Path) -> tuple[dict[str, str], dict[str, set[str]]]:
    """Validate source-derived integrity and return evidence for regression checks."""
    root = root.resolve(strict=True)
    if instruction_root(root / AGENTS / "AGENTS.md") != root:
        raise ValidationError("requested root does not match canonical instruction root")
    paths = source_paths(root)
    policy = read_source(root, f"{GUIDES}/README.md")
    retired, active_policy = retirement_record(policy)
    existing_names = {PurePosixPath(path).name for path in paths if (root / path).is_file()}
    retired_names = {PurePosixPath(path).name for path in retired} - existing_names
    for path in retired:
        if (root / path).exists() or (root / path).is_symlink():
            raise ValidationError(f"retired path still exists: {path}")
    for path in paths:
        if not (root / path).is_file():
            continue
        if path.startswith(f"{AGENTS}/tools/") and PurePosixPath(path).name in {
            "validate-instructions.py", "test-instructions.py"
        }:
            continue
        resolve_target(root, path)
        content = (root / path).read_bytes()
        if PREFIXED_ALIAS.search(content):
            raise ValidationError(f"published alias prefixed with link-targets: {path}")
        if path == f"{GUIDES}/README.md":
            content = active_policy.encode("utf-8")
        for retired_path in retired:
            alias = ".agents" + retired_path[len(AGENTS):]
            filename = PurePosixPath(retired_path).name
            if retired_path.encode("utf-8") in content or alias.encode("utf-8") in content or (
                filename in retired_names and re.search(rb"(?<![A-Za-z0-9_.-])" + re.escape(filename.encode()) + rb"(?![A-Za-z0-9_.-])", content)
            ):
                raise ValidationError(f"retired path used by active source: {path} -> {retired_path}")
    entrypoints = {
        path: read_source(root, path) for path in paths
        if path.startswith(SKILLS + "/") and path.endswith("/SKILL.md")
        and len(PurePosixPath(path).parts) == 5
    }
    for path, text in entrypoints.items():
        check_frontmatter(path, text)
    sources = {
        path for path in paths
        if (path.startswith(GUIDES + "/") and path.endswith(".md"))
        or (path.startswith(AGENTS + "/") and PurePosixPath(path).name == "AGENTS.md")
        or path in {"AGENTS.md", ROUTER, "README.manual.md", "codex-wsl/SETUP.md", "codex-wsl/CODEX_HOME.md"}
        or (path.startswith("link-targets/claude/agents/") and path.endswith(".md"))
        or (path.startswith("chezmoi/.chezmoiscripts/run_after_junctions.") and path.endswith(".tmpl"))
    }
    sources.update(entrypoints)
    texts: dict[str, str] = {}
    edges: dict[str, set[str]] = {}
    graph: dict[str, set[str]] = {}
    pending = sorted(sources)
    while pending:
        source = pending.pop()
        if source in texts:
            continue
        text = active_policy if source == f"{GUIDES}/README.md" else read_source(root, source)
        targets = references(root, source, text)
        exclusions = non_dependencies(root, source, text, targets)
        texts[source] = text
        edges[source] = targets
        graph[source] = targets - exclusions
        pending.extend(target for target in targets if target.endswith(".md") and target not in texts)
    check_cycles(graph)
    check_fallbacks(texts, edges)
    for path, text in texts.items():
        if not path.startswith(GUIDES + "/") or path.endswith("/README.md"):
            continue
        external = re.search(r"^> \*\*External consumer:\*\* ([^;]+); purpose: (.+)$", text, re.MULTILINE)
        if external:
            if external.group(1) != "GPT-Chat" or not external.group(2).strip():
                raise ValidationError(f"invalid external consumer record: {path}")
            continue
        callers = {source for source, targets in graph.items() if path in targets}
        if not callers:
            raise ValidationError(f"shared guide has no runtime caller or external consumer: {path}")
    for owner, text in texts.items():
        if owner.endswith("/SKILL.md") and "## Discovery contract" in text:
            if instruction_root(root / owner) != root:
                raise ValidationError(f"Skill escapes canonical instruction tree: {owner}")
    return texts, edges


def main() -> int:
    """Run the source checks from the validator location or an explicit fixture root."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, help="explicit canonical tree to validate")
    arguments = parser.parse_args()
    try:
        root = arguments.root if arguments.root is not None else instruction_root(Path(__file__))
        texts, edges = validate(root)
    except (ValidationError, OSError, UnicodeError) as error:
        print(f"instruction validation failed: {error}", file=sys.stderr)
        return 1
    print(f"instructions OK: {len(texts)} sources, {sum(map(len, edges.values()))} derived references")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
