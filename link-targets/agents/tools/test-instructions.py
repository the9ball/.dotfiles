#!/usr/bin/env python3
"""Regression evidence for canonical root resolution and derived source checks."""

from __future__ import annotations

import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path


SCRIPT = Path(__file__).resolve().with_name("validate-instructions.py")
SPEC = importlib.util.spec_from_file_location("instructions", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
VALIDATOR = importlib.util.module_from_spec(SPEC)
sys.dont_write_bytecode = True
SPEC.loader.exec_module(VALIDATOR)


ROOT_PROCEDURE = (
    "Strictly resolve the loaded Skill entrypoint through every symlink/junction to its existing final file; "
    "enumerate its real ancestors whose last two components are `link-targets/agents` and which contain both "
    "`AGENTS.md` and `guides/README.md`; require exactly one candidate, with the entrypoint and both sentinels "
    "still contained after real-path resolution, and use that candidate's grandparent as the instruction root. "
    "Stop on a missing, broken, escaping, malformed, or ambiguous location; never substitute CWD, the work root, "
    "`.git`, home defaults, or a machine-specific absolute path. Resolve requested logical paths against this "
    "fixed root and verify existence and real-path containment before reading. Fix the work root and Git target "
    "from the request and current Git state, independently of the instruction root."
)
SHIM_ROOT_SENTENCE = (
    "Resolve that\nlogical path against the instruction root: the directory that contains the real\n"
    "`link-targets` directory enclosing this shim, after resolving every\n"
    "symlink/junction. Do not append it to a link that points at\n"
    "`link-targets/agents` itself, because the logical path already includes\n"
    "`link-targets/agents`. "
)
ROUTER_PREAMBLE = (
    "Until Issue #75 is completed\n"
    "`~/.agents` is the `link-targets/agents` directory itself: drop the leading\n"
    "`link-targets/agents/` from a logical path to reach it under `~/.agents`.\n"
)
RESOLVER_NAMES = ("advisor-review", "delegation", "git-operations", "implementation-planning", "review-consolidation")
# Runtime rules that once lived only in Discovery or Runtime contract text (Issue #158); the Guide must carry them.
GUIDE_RUNTIME_RULES = {
    "structured-data": ("If the structured parser cannot interpret the data, stop and report instead of falling back to text guessing.",),
    "dotnet-testing": ("If the build/test configuration or execution conditions cannot be determined, do not force execution; stop and report.",),
    "implementation-planning": (
        "The ability to execute the plan, approval status, external operations, and acceptance/rejection are left to each existing execution/authorization gate.",
        "Stop in fail-safe mode if the plan's targets, constraints, estimate basis, or applicable contract cannot be determined.",
    ),
    "approval-request-workflow": (
        "Apply the common contract for execution authorization, `link-targets/agents/skills/external-operation-authorization/SKILL.md`, only when an authorization obligation occurs.",
        "If this or another required dependency contract cannot be resolved, do not rely on guesswork; stop in a fail-safe manner and report.",
    ),
    "commit-message": (
        "This fallback applies to history that was retrieved and checked, including history that is empty, short, mixed, or inconclusive.",
        "If an existing convention source or the history that the Application order requires cannot be read or retrieved",
        "do not assume the defaults; check and stop.",
    ),
    "advisor-review": ("Advisor output is treated as attributable advice, not as a ruling or implementation approval.",),
}
EXTERNAL_OPERATION_RULES = {
    "external-operation-authorization": (
        "`INDETERMINATE` never permits execution.",
        "Obtain all required physical evidence for identity, selector membership, remaining quantities, boundary validity, and execution outcomes; neither existing nor new approval can substitute for that evidence.",
        "before execution, revalidate all required items against the new boundary and obtain `WITHIN_BOUNDARY`.",
        "If any required evidence remains unavailable, keep execution stopped.",
        "| New approval obtained but target identity, selector membership or counts remain unconfirmed | `INDETERMINATE` | Stop; approval does not replace missing operational evidence |",
        "If there are both known out-of-range items and unconfirmed items, set it to `OUTSIDE_BOUNDARY`",
        "Pause until new approval and also obtain evidence of unconfirmed items",
        "If it cannot be confirmed by read-back that it has not been applied, stop even if authorization remains.",
        "The approval request workflow does not supply or replace those execution guarantees.",
        'When authoring or maintaining this authorization instruction layout, apply the mandatory rule in "Instruction-layout authoring rule" below.',
        "Stop until both boundary revalidation yields `WITHIN_BOUNDARY` and the required new review or verification is complete",
        "existing or new authorization, review evidence, or unrelated evidence cannot replace the required validity or identity evidence",
        "Do not change targets, services, accounts, credentials, permissions, remotes, refs, public scope, or routes due to retry.",
        "403, 404, authentication change, scope addition, and switching to another CLI/API are not included in automatic retry.",
    ),
    "external-posting": (
        "If an existing explicit instruction already covers that inclusion, destination, and disclosure scope, do not request the same confirmation again.",
        "Merely providing local information does not instruct the agent to publish it.",
        "This editorial discretion does not enlarge the authorized target, operation, content, or disclosure scope.",
        "the user has supplied the information, and an explicit user instruction authorizes publishing that information to the identified destination and disclosure scope.",
        "Supplying the information alone is not publication authorization; publication authorization alone does not supply the information.",
        "Publication authorization does not establish factual accuracy.",
    ),
    "github": (
        "An unexpected sandbox failure is not covered by the automatic diagnostic retry below:",
        'obtain the user confirmation required by the common policy kernel\'s "Permission errors and alternatives" rule before any further read-only attempt, in addition to satisfying host execution permissions.',
        "Technical auto-approval does not replace that user confirmation.",
        "It does not authorize retrying a write, even when a write reports an access error.",
        "For every write failure, including a sandbox failure, authorization, retransmission, ambiguous outcome, read-back, and consumption follow `link-targets/agents/skills/external-operation-authorization/SKILL.md`.",
    ),
    "approval-request-workflow": (
        "When the user explicitly rejects a presented approval item, do not additionally display a withdrawal for that rejection.",
        "This exception concerns the user's answer, not an agent's refusal to perform an operation.",
    ),
}


def guide_section(text: str) -> str:
    """Return the normative Guide section, ending at the next level-two heading."""
    match = re.search(r"^## Guide[ \t]*$", text, re.MULTILINE)
    if match is None:
        return ""
    following = re.search(r"^## ", text[match.end():], re.MULTILINE)
    return text[match.end():] if following is None else text[match.end():match.end() + following.start()]


def write(root: Path, path: str, text: str) -> Path:
    """Write one isolated UTF-8 fixture source and return its location."""
    destination = root / path
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8")
    return destination


def fixture(root: Path) -> None:
    """Build a Git-free canonical tree with one required host fallback."""
    write(root, "link-targets/agents/AGENTS.md", "# Kernel\n")
    write(root, "link-targets/agents/guides/README.md", """# Placement
<!-- retired-paths:start -->
- `link-targets/agents/guides/removed.md`
<!-- retired-paths:end -->
""")
    write(root, "link-targets/agents/skills/example/SKILL.md", """---
name: example
description: Run the example workflow.
---
# Example
## Discovery contract
- Host fallback: required
- Positive trigger: Example work.
- Negative trigger: Unrelated work.
- Conditional dependency: None.
- Failure mode: Stop fail-safe.
## Runtime contract
Apply the Guide when selected.
## Guide
Perform the example work.
""")
    write(root, "link-targets/agents/guides/example.md", """# Claude Code compatibility shim: example

This temporary host fallback exists for Issue #75. The normative runtime
contract is `link-targets/agents/skills/example/SKILL.md`. """ + SHIM_ROOT_SENTENCE + """Read that Skill
and apply its `## Guide` section; this shim defines no runtime rules of its
own. If the Skill cannot be resolved, stop and report.
""")
    write(root, "chezmoi/dot_claude/CLAUDE.md", ROUTER_PREAMBLE + """| Request family | Compatibility shim (canonical source) |
| --- | --- |
| Example work | `link-targets/agents/guides/example.md` |
""")


class InstructionTests(unittest.TestCase):
    """Exercise positive and negative migrations independently of registry data."""

    def setUp(self) -> None:
        """Create an isolated canonical source tree for each test."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        fixture(self.root)
        self.owner = self.root / "link-targets/agents/skills/example/SKILL.md"

    def change(self, path: str, before: str, after: str) -> None:
        """Replace an asserted fixture fragment without hiding setup mistakes."""
        destination = self.root / path
        text = destination.read_text(encoding="utf-8")
        self.assertIn(before, text)
        destination.write_text(text.replace(before, after), encoding="utf-8")

    def rejects(self, pattern: str) -> None:
        """Require full validation to fail with an attributable diagnostic."""
        with self.assertRaisesRegex(VALIDATOR.ValidationError, pattern):
            VALIDATOR.validate(self.root)

    def test_valid_git_free_tree_and_alias(self) -> None:
        """Accept canonical source and normalize the published logical alias."""
        texts, edges = VALIDATOR.validate(self.root)
        self.assertIn("link-targets/agents/skills/example/SKILL.md", texts)
        self.assertIn("link-targets/agents/guides/example.md", edges[VALIDATOR.ROUTER])
        self.assertEqual(VALIDATOR.instruction_root(self.owner), self.root)
        self.assertEqual(
            VALIDATOR.resolve_target(self.root, ".agents/skills/example/SKILL.md"),
            "link-targets/agents/skills/example/SKILL.md",
        )

    def test_missing_loaded_file_and_nonfile(self) -> None:
        """Reject nonexistent entrypoints and directories posing as instructions."""
        for path in (self.owner.with_name("missing.md"), self.owner.parent):
            with self.subTest(path=path), self.assertRaises(VALIDATOR.ValidationError):
                VALIDATOR.instruction_root(path)

    def test_missing_and_malformed_root(self) -> None:
        """Reject missing sentinels and lookalike directory components."""
        (self.root / "link-targets/agents/guides/README.md").unlink()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "unique"):
            VALIDATOR.instruction_root(self.owner)
        other = write(self.root, "different/agents/skills/example/SKILL.md", "# Other\n")
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "unique"):
            VALIDATOR.instruction_root(other)

    def test_ambiguous_nested_root(self) -> None:
        """Reject two canonical layouts enclosing the same loaded entity."""
        nested = self.root / "link-targets/agents/skills/nested"
        fixture(nested)
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "found 2"):
            VALIDATOR.instruction_root(nested / "link-targets/agents/skills/example/SKILL.md")

    def test_symlink_loaded_path_and_broken_link(self) -> None:
        """Resolve a published link and reject it after the target disappears."""
        published = self.root / "published"
        try:
            published.symlink_to(self.owner.parent, target_is_directory=True)
        except OSError as error:
            self.skipTest(f"symlink creation unavailable: {error}")
        self.assertEqual(VALIDATOR.instruction_root(published / "SKILL.md"), self.root)
        self.owner.unlink()
        with self.assertRaises(VALIDATOR.ValidationError):
            VALIDATOR.instruction_root(published / "SKILL.md")

    @unittest.skipUnless(os.name == "nt", "Windows junction check")
    def test_windows_junction(self) -> None:
        """Resolve an actual Windows publication junction in an isolated fixture."""
        junction = self.root / "published-junction"
        environment = os.environ.copy()
        environment["INSTRUCTION_TEST_JUNCTION"] = str(junction)
        environment["INSTRUCTION_TEST_TARGET"] = str(self.owner.parent)
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command",
             "New-Item -ItemType Junction -Path $env:INSTRUCTION_TEST_JUNCTION -Target $env:INSTRUCTION_TEST_TARGET | Out-Null"],
            capture_output=True, check=False, env=environment,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(VALIDATOR.instruction_root(junction / "SKILL.md"), self.root)
        self.owner.unlink()
        with self.assertRaises(VALIDATOR.ValidationError):
            VALIDATOR.instruction_root(junction / "SKILL.md")

    def test_escaping_sentinel(self) -> None:
        """Reject a canonical-looking root whose sentinel points outside it."""
        sentinel = self.root / "link-targets/agents/AGENTS.md"
        sentinel.unlink()
        outside = write(self.root, "outside.md", "# Outside\n")
        try:
            sentinel.symlink_to(outside)
        except OSError as error:
            self.skipTest(f"symlink creation unavailable: {error}")
        with self.assertRaises(VALIDATOR.ValidationError):
            VALIDATOR.instruction_root(self.owner)

    def test_escaping_requested_path(self) -> None:
        """Reject traversal and links that resolve outside the fixed root."""
        with self.assertRaises(VALIDATOR.ValidationError):
            VALIDATOR.resolve_target(self.root, "../outside.md")
        link = self.root / "escape.md"
        try:
            link.symlink_to(SCRIPT)
        except OSError as error:
            self.skipTest(f"symlink creation unavailable: {error}")
        with self.assertRaises(VALIDATOR.ValidationError):
            VALIDATOR.resolve_target(self.root, "escape.md")

    def test_drive_qualified_and_existing_absolute_paths(self) -> None:
        """Reject drive forms and an existing absolute target even inside root."""
        for value in ("C:/example.md", "C:example.md", self.owner.as_posix()):
            with self.subTest(value=value), self.assertRaisesRegex(VALIDATOR.ValidationError, "invalid logical"):
                VALIDATOR.resolve_target(self.root, value)

    def test_missing_logical_and_markdown_targets(self) -> None:
        """Reject missing concrete targets through both reference spellings."""
        for reference in ("`link-targets/agents/guides/missing.md`", "[missing](missing.md)"):
            with self.subTest(reference=reference):
                write(self.root, "link-targets/agents/guides/extra.md", reference)
                self.rejects("reference|Markdown")

    def test_orphan_guide_and_external_consumer(self) -> None:
        """Require actual callers, permitting documented external-only material."""
        path = "link-targets/agents/guides/external.md"
        write(self.root, path, "# External\n")
        self.rejects("no runtime caller")
        write(self.root, path, "> **External consumer:** GPT-Chat; purpose: provide outside reference.\n")
        VALIDATOR.validate(self.root)

    def test_dependency_cycle(self) -> None:
        """Reject circular dependencies derived from the actual guide sources."""
        write(self.root, "link-targets/agents/guides/one.md", "[two](two.md)\n")
        write(self.root, "link-targets/agents/guides/two.md", "[one](one.md)\n")
        self.rejects("dependency cycle")

    def test_docs_backlink_is_terminal(self) -> None:
        """Allow operational docs to link back without forming read cycles."""
        source = "README.manual.md"
        document = "docs/operations.md"
        write(self.root, source, "[operations](docs/operations.md)\n")
        write(self.root, document, "[manual](../README.manual.md)\n")
        texts, edges = VALIDATOR.validate(self.root)
        self.assertIn(document, edges[source])
        self.assertEqual(edges[document], set())
        self.assertIn(document, texts)

    def test_missing_docs_target_is_rejected(self) -> None:
        """Keep existence checks for references into terminal documentation."""
        write(self.root, "README.manual.md", "[missing](docs/missing.md)\n")
        self.rejects("invalid Markdown target")

    def test_annotation_cannot_manufacture_edge(self) -> None:
        """Reject an exemption with no independent source reference."""
        with (self.root / "link-targets/agents/guides/README.md").open("a", encoding="utf-8") as stream:
            stream.write("<!-- reference-kind: manual-navigation; target: link-targets/agents/AGENTS.md -->\n")
        self.rejects("unbacked")

    def test_annotation_cannot_hide_loader(self) -> None:
        """Reject an explicit read even from an eligible navigational document."""
        with (self.root / "link-targets/agents/guides/README.md").open("a", encoding="utf-8") as stream:
            stream.write("Read `link-targets/agents/AGENTS.md`.\n")
            stream.write("<!-- reference-kind: manual-navigation; target: link-targets/agents/AGENTS.md -->\n")
        self.rejects("runtime loader cannot be exempted")

    def test_annotation_cannot_hide_relative_multiline_loader(self) -> None:
        """Reject a read paragraph using a file-relative Markdown destination."""
        with (self.root / "link-targets/agents/guides/README.md").open("a", encoding="utf-8") as stream:
            stream.write("\nRead\n[kernel](../AGENTS.md).\n\n")
            stream.write("<!-- reference-kind: manual-navigation; target: link-targets/agents/AGENTS.md -->\n")
        self.rejects("runtime loader cannot be exempted")

    def test_unknown_and_duplicate_annotation(self) -> None:
        """Reject invented exclusion kinds and repeated exclusions."""
        for annotation in (
            "<!-- reference-kind: ignore; target: link-targets/agents/AGENTS.md -->",
            "<!-- reference-kind: manual-navigation; target: link-targets/agents/AGENTS.md -->\n" * 2,
        ):
            with self.subTest(annotation=annotation):
                write(self.root, "codex-wsl/SETUP.md", "`link-targets/agents/AGENTS.md`\n" + annotation)
                self.rejects("non-dependency|duplicate")

    def test_removed_discovery_contract_still_managed(self) -> None:
        """Keep routed shim owners managed when their entire discovery is removed."""
        text = self.owner.read_text(encoding="utf-8")
        self.owner.write_text(re.sub(r"## Discovery contract\n.*?## Runtime", "## Runtime", text, flags=re.DOTALL), encoding="utf-8")
        self.rejects("missing Skill section")

    def test_invalid_discovery_and_fallback_metadata(self) -> None:
        """Reject missing discovery, frontmatter, failure and coverage declarations."""
        original = self.owner.read_text(encoding="utf-8")
        for before, after in (
            ("name: example", "name: other"),
            ("description: Run the example workflow.", ""),
            ("- Positive trigger: Example work.", "- Positive trigger: "),
            ("- Failure mode: Stop fail-safe.", "- Failure mode: Continue."),
            ("- Host fallback: required", "- Host fallback: exempt"),
            ("## Guide", "## Details"),
        ):
            with self.subTest(before=before):
                self.owner.write_text(original.replace(before, after), encoding="utf-8")
                self.rejects("frontmatter|discovery|fallback|closed|section")

    def test_shim_owner_rules_and_retirement(self) -> None:
        """Reject owner drift, invented shim runtime rules and changed retirement."""
        path = self.root / "link-targets/agents/guides/example.md"
        original = path.read_text(encoding="utf-8")
        for modified in (
            original.replace("skills/example/", "skills/other/"),
            original + "Always authorize writes.\n",
            original.replace("Issue #75", "Issue #128"),
        ):
            with self.subTest(modified=modified):
                path.write_text(modified, encoding="utf-8")
                self.rejects("shim|reference")

    def test_shim_requires_instruction_root_sentence(self) -> None:
        """Reject a shim that drops the instruction-root resolution sentence."""
        self.change("link-targets/agents/guides/example.md", SHIM_ROOT_SENTENCE, "")
        self.rejects("invalid shim owner/runtime rules/retirement")

    def test_shim_root_sentence_rejects_home_alias_rewrite(self) -> None:
        """Reject a shim that replaces root resolution with a host alias rule."""
        self.change(
            "link-targets/agents/guides/example.md",
            "the directory that contains the real",
            "the home alias, never the directory that contains the real",
        )
        self.rejects("invalid shim owner/runtime rules/retirement")

    def test_alias_prefixed_logical_path_is_rejected_explicitly(self) -> None:
        """Reject a link-targets path appended to a published alias in either separator form."""
        for fragment in (
            ".agents/link-targets/agents/skills/example/SKILL.md",
            ".agents\\link-targets\\agents\\skills\\example\\SKILL.md",
        ):
            with self.subTest(fragment=fragment):
                write(self.root, "link-targets/agents/guides/ordinary.md", f"# Ordinary guide\n`~/{fragment}`\n")
                self.rejects("published alias prefixed with link-targets")

    def test_alias_mapping_neighbours_are_not_flagged(self) -> None:
        """Accept the published alias used with a path that is not prefixed by link-targets."""
        write(self.root, "link-targets/agents/guides/ordinary.md", "# Ordinary guide\nSee `.agents/guides/example.md` and `.agents/link-targets-old`.\n")
        with (self.root / VALIDATOR.ROUTER).open("a", encoding="utf-8") as stream:
            stream.write("Read `link-targets/agents/guides/ordinary.md`.\n")
        VALIDATOR.validate(self.root)

    def test_router_requires_alias_mapping(self) -> None:
        """Require the host router to state how the published alias maps to the root."""
        self.change(VALIDATOR.ROUTER, ROUTER_PREAMBLE.split("\n", 1)[1], "")
        self.rejects("host alias mapping missing")

    def test_duplicate_owner_and_hidden_legacy_loader(self) -> None:
        """Reject a second shim and an owner that reloads its legacy basename."""
        original = (self.root / "link-targets/agents/guides/example.md").read_text(encoding="utf-8")
        duplicate = write(self.root, "link-targets/agents/guides/alternate/example.md", original)
        self.rejects("duplicate or missing shim owner")
        duplicate.unlink()
        with self.owner.open("a", encoding="utf-8") as stream:
            stream.write("Read example.md.\n")
        self.rejects("hidden Skill-to-legacy")

    def test_missing_router_and_required_coverage(self) -> None:
        """Reject broken routes and a required Skill with no shim."""
        self.change(VALIDATOR.ROUTER, "`link-targets/agents/guides/example.md`", "Example")
        self.rejects("missing router")
        fixture(self.root)
        self.change("link-targets/agents/guides/example.md", "# Claude Code compatibility shim:", "# Guide:")
        self.rejects("host table")

    def test_exemption_needs_direct_route(self) -> None:
        """Require an exempt Skill to be reached directly from host or kernel."""
        self.change("link-targets/agents/skills/example/SKILL.md", "Host fallback: required", "Host fallback: exempt; direct kernel routing")
        self.rejects("exempt discovery Skill has a shim")
        (self.root / "link-targets/agents/guides/example.md").unlink()
        write(self.root, VALIDATOR.ROUTER, ROUTER_PREAMBLE)
        self.rejects("no direct host/kernel route")
        write(self.root, "link-targets/agents/AGENTS.md", "Read `link-targets/agents/skills/example/SKILL.md`.\n")
        VALIDATOR.validate(self.root)

    def test_removed_exempt_contract_still_managed(self) -> None:
        """Keep directly routed exemptions managed without discovery headings."""
        (self.root / "link-targets/agents/guides/example.md").unlink()
        write(self.root, VALIDATOR.ROUTER, ROUTER_PREAMBLE)
        write(self.root, "link-targets/agents/AGENTS.md", "Read `link-targets/agents/skills/example/SKILL.md`.\n")
        text = self.owner.read_text(encoding="utf-8")
        self.owner.write_text(re.sub(r"## Discovery contract\n.*?## Runtime", "## Runtime", text, flags=re.DOTALL), encoding="utf-8")
        self.rejects("missing Skill section")

    def test_history_bounds_and_retirement_condition(self) -> None:
        """Reject malformed history and host prose that loses the retirement gate."""
        self.change(VALIDATOR.ROUTER, "Until Issue #75 is completed", "Until another issue")
        self.rejects("retirement condition missing")
        fixture(self.root)
        self.change("link-targets/agents/guides/README.md", "<!-- retired-paths:end -->", "")
        self.rejects("exactly one retirement record")

    def test_host_state_is_not_a_repository_reference(self) -> None:
        """Distinguish generated host state and generic URL examples from assets."""
        write(self.root, "codex-wsl/SETUP.md", "Host `~/.codex-wsl/hooks.json`; [example](URL).\n")
        VALIDATOR.validate(self.root)

    def test_retired_path_exists_or_is_used(self) -> None:
        """Reject reintroduced files and active uses outside the bounded history."""
        retired = write(self.root, "link-targets/agents/guides/removed.md", "# Removed\n")
        self.rejects("retired path still exists")
        retired.unlink()
        write(self.root, "active.txt", "link-targets/agents/guides/removed.md")
        self.rejects("retired path used")

    def test_private_host_overlay_is_optional_and_never_imported(self) -> None:
        """Keep the exact shared host overlay outside the repository contract."""
        with (self.root / VALIDATOR.ROUTER).open("a", encoding="utf-8") as stream:
            stream.write("@~/.agents/AGENTS.local.md\n")
        with (self.root / "link-targets/agents/AGENTS.md").open("a", encoding="utf-8") as stream:
            stream.write("[optional local](AGENTS.local.md)\n")
        for present in (False, True):
            with self.subTest(present=present):
                if present:
                    write(self.root, VALIDATOR.HOST_LOCAL, "Private overlay\n").write_bytes(b"\xff")
                texts, edges = VALIDATOR.validate(self.root)
                self.assertNotIn(VALIDATOR.HOST_LOCAL, texts)
                self.assertFalse(any(VALIDATOR.HOST_LOCAL in targets for targets in edges.values()))

    def test_optional_overlay_exemption_is_exact(self) -> None:
        """Require ordinary local instructions outside the exact private path."""
        with (self.root / VALIDATOR.ROUTER).open("a", encoding="utf-8") as stream:
            stream.write("Read `link-targets/agents/other/AGENTS.local.md`.\n")
        self.rejects("missing or escaping reference")

    def test_unreferenced_standard_skill_is_seeded(self) -> None:
        """Validate standard Skill metadata and references without #75 expansion."""
        path = "link-targets/agents/skills/standard/SKILL.md"
        text = "---\nname: standard\ndescription: Standard work.\n---\n# Standard\n"
        write(self.root, path, text)
        texts, _ = VALIDATOR.validate(self.root)
        self.assertIn(path, texts)
        for invalid in (
            "# No metadata\n", text.replace("name: standard", "name: other"),
            text.replace("description: Standard work.", ""),
            text.replace("description: Standard work.", "description: >"),
        ):
            with self.subTest(invalid=invalid):
                write(self.root, path, invalid)
                self.rejects("invalid Skill frontmatter")
        write(self.root, path, text + "[broken](missing.md)\n")
        self.rejects("invalid Markdown target")
        write(self.root, path, text.replace("description: Standard work.", "description: >\n  Standard work."))
        VALIDATOR.validate(self.root)

    def test_standard_guide_and_runtime_bullets_do_not_declare_discovery(self) -> None:
        """Keep ordinary workflow examples outside the #75 participation signal."""
        path = "link-targets/agents/skills/standard/SKILL.md"
        text = "---\nname: standard\ndescription: Standard work.\n---\n# Standard\n"
        for heading in ("Guide", "Runtime contract"):
            for label in ("Positive trigger", "Negative trigger", "Conditional dependency", "Failure mode"):
                with self.subTest(heading=heading, label=label):
                    write(self.root, path, text + f"## {heading}\n- {label}: Example workflow.\n")
                    VALIDATOR.validate(self.root)
        write(self.root, path, text + "- Failure mode: Stop.\n## Guide\nExample workflow.\n")
        self.rejects("missing Skill section Discovery contract")
        write(self.root, path, text + "## Guide\n- Host fallback: required\n")
        self.rejects("missing Skill section Discovery contract")
        write(self.root, path, self.owner.read_text(encoding="utf-8").replace("name: example", "name: standard")
              .replace("## Discovery contract", "## Discovery"))
        self.rejects("missing Skill section Discovery contract")

    def test_frontmatter_supported_scalar_subset(self) -> None:
        """Fix the documented raw-scalar subset without claiming full YAML parsing."""
        path = "link-targets/agents/skills/standard/SKILL.md"
        template = "---\nname: standard\ndescription: Standard work.\n---\n# Standard\n"
        write(self.root, path, "\ufeff" + template)
        VALIDATOR.validate(self.root)
        for description in ('Standard work.', '"Standard work."', '""', '>2', '| # note',
                            ">\n  Standard work.", "|\n  Standard work.", ">-\n  Standard work.",
                            "|-\n  Standard work.", ">+\n  Standard work.", "|+\n  Standard work."):
            with self.subTest(description=description):
                write(self.root, path, template.replace("Standard work.", description))
                VALIDATOR.validate(self.root)
        for indicator in (">", "|", ">-", "|-", ">+", "|+"):
            with self.subTest(name_indicator=indicator):
                write(self.root, path, template.replace("name: standard", f"name: {indicator}\n  standard"))
                VALIDATOR.validate(self.root)
        write(self.root, path, template.replace("name: standard", "name:standard"))
        VALIDATOR.validate(self.root)
        write(self.root, path, template.replace("name: standard", "name: standard\nname:"))
        VALIDATOR.validate(self.root)
        invalid_headers = (
            template.replace("name: standard", 'name: "standard"'),
            template.replace("name: standard", "name:\n  standard"),
            template.replace("description: Standard work.", "description:\n  Standard work."),
            template.replace("name: standard", "name: standard\nname: standard"),
            template.replace("description: Standard work.", "description: Standard work.\ndescription: More work."),
            template.replace("name: standard", "name: standard # comment"),
            template.replace("name: standard", "name: standard\nname: "),
            template.replace("name: standard", "name: standard\nname:\t"),
            template.replace("---\nname:", "--- \nname:", 1),
            template.replace("---\n# Standard\n", "---"),
        )
        for text in invalid_headers:
            with self.subTest(text=text):
                write(self.root, path, text)
                self.rejects("invalid Skill frontmatter")

    def test_unreferenced_partial_discovery_contract_is_rejected(self) -> None:
        """Detect partial migrated contracts independently of inbound routes."""
        path = "link-targets/agents/skills/standard/SKILL.md"
        text = "---\nname: standard\ndescription: Standard work.\n---\n# Standard\n"
        for marker in ("- Host fallback: required", "- Positive trigger: Work."):
            with self.subTest(marker=marker):
                write(self.root, path, text + marker + "\n")
                self.rejects("missing Skill section Discovery contract")

    def test_required_owner_without_shim_has_specific_diagnostic(self) -> None:
        """Exercise the required-owner coverage branch after routes are removed."""
        (self.root / "link-targets/agents/guides/example.md").unlink()
        write(self.root, VALIDATOR.ROUTER, ROUTER_PREAMBLE)
        self.rejects("required discovery Skill has no single shim")

    def test_missing_shim_on_new_required_skill(self) -> None:
        """Require an unreferenced complete #75 contract to have a shim."""
        text = self.owner.read_text(encoding="utf-8").replace("name: example", "name: additional")
        write(self.root, "link-targets/agents/skills/additional/SKILL.md", text)
        self.rejects("required discovery Skill has no single shim")

    def test_unreachable_markdown_boundary(self) -> None:
        """Exclude unrelated orphan Markdown but validate it once referenced."""
        write(self.root, "unrelated/notes.md", "[broken](missing.md)\n")
        VALIDATOR.validate(self.root)
        with (self.root / "link-targets/agents/AGENTS.md").open("a", encoding="utf-8") as stream:
            stream.write("[notes](../../unrelated/notes.md)\n")
        self.rejects("invalid Markdown target")

    def test_existing_directory_reference_and_generated_placeholder(self) -> None:
        """Derive real publication directory edges without requiring generated paths."""
        path = "chezmoi/.chezmoiscripts/run_after_junctions.sh.tmpl"
        write(self.root, path, '`link-targets/agents/skills` and `link-targets/agents/generated-state`\n')
        _, edges = VALIDATOR.validate(self.root)
        self.assertIn(VALIDATOR.SKILLS, edges[path])
        self.assertNotIn("link-targets/agents/generated-state", edges[path])

    def test_directory_reference_escape_is_rejected(self) -> None:
        """Keep an existing extensionless directory reference inside the root."""
        link = self.root / "link-targets/agents/outside"
        try:
            link.symlink_to(SCRIPT.parent, target_is_directory=True)
        except OSError as error:
            self.skipTest(f"symlink creation unavailable: {error}")
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "missing or escaping"):
            VALIDATOR.references(self.root, VALIDATOR.ROUTER, "`link-targets/agents/outside`")

    def test_retirement_alias_and_unambiguous_filename(self) -> None:
        """Detect published aliases and basenames without rejecting moved assets."""
        for reference in (".agents/guides/removed.md", "~/.agents/guides/removed.md", "removed.md"):
            with self.subTest(reference=reference):
                write(self.root, "active.txt", reference)
                self.rejects("retired path used")
        write(self.root, "other/removed.md", "Historical name reused elsewhere.\n")
        write(self.root, "active.txt", "removed.md")
        VALIDATOR.validate(self.root)

    def test_failure_mode_negation_is_rejected(self) -> None:
        """Reject a negated stop even when it contains a positive-looking token."""
        original = self.owner.read_text(encoding="utf-8")
        for phrase in ("Never stop.", "Do not stop.", "Don't stop.", "Without stop.", "Continue."):
            with self.subTest(phrase=phrase):
                self.owner.write_text(original.replace("Stop fail-safe.", phrase), encoding="utf-8")
                self.rejects("discovery must fail closed")

    def test_annotation_guards_use_follow_and_run(self) -> None:
        """Reject additional English loading commands on navigational edges."""
        for verb in ("Use", "Follow", "Run"):
            with self.subTest(verb=verb):
                write(self.root, "codex-wsl/SETUP.md", f"{verb} `link-targets/agents/AGENTS.md`.\n"
                      "<!-- reference-kind: manual-navigation; target: link-targets/agents/AGENTS.md -->\n")
                self.rejects("runtime loader cannot be exempted")

    def test_router_prose_is_distinct_from_shim_table(self) -> None:
        """Allow ordinary guide references outside the compatibility table."""
        write(self.root, "link-targets/agents/guides/ordinary.md", "# Ordinary guide\n")
        with (self.root / VALIDATOR.ROUTER).open("a", encoding="utf-8") as stream:
            stream.write("Read `link-targets/agents/guides/ordinary.md`.\n")
        VALIDATOR.validate(self.root)
        with (self.root / VALIDATOR.ROUTER).open("a", encoding="utf-8") as stream:
            stream.write("| Other | `link-targets/agents/guides/ordinary.md` |\n")
        self.rejects("host table and compatibility shims disagree")

    def test_git_free_root_uses_filesystem_inventory_without_private_overlay(self) -> None:
        """Enumerate a Git-free tree without invoking Git or importing the overlay."""
        write(self.root, VALIDATOR.HOST_LOCAL, "Private data\n").write_bytes(b"\xff")
        with patch.object(VALIDATOR.subprocess, "run", side_effect=FileNotFoundError) as invocation:
            texts, _ = VALIDATOR.validate(self.root)
            invocation.assert_not_called()
        self.assertNotIn(VALIDATOR.HOST_LOCAL, texts)

    def test_git_worktree_inventory_failures_do_not_import_private_candidates(self) -> None:
        """Fail closed when Git cannot enforce the ignore boundary of a worktree."""
        write(self.root, "private/unreadable.md", "Private data\n").write_bytes(b"\xff")
        marker = self.root / ".git"
        marker.mkdir()
        failures = (subprocess.CompletedProcess([], 128, b"", b""), FileNotFoundError())
        for failure in failures:
            with self.subTest(failure=failure):
                options = {"side_effect": failure} if isinstance(failure, OSError) else {"return_value": failure}
                with patch.object(VALIDATOR.subprocess, "run", **options):
                    self.rejects("git inventory unavailable in worktree")
        marker.rmdir()
        with patch.object(VALIDATOR.subprocess, "run", side_effect=FileNotFoundError) as invocation:
            VALIDATOR.source_paths(self.root)
            invocation.assert_not_called()

    def test_owner_drift_is_not_a_missing_target_diagnostic(self) -> None:
        """Reject wrong ownership after the alternative owner actually exists."""
        write(self.root, "link-targets/agents/skills/other/SKILL.md",
              self.owner.read_text(encoding="utf-8").replace("name: example", "name: other"))
        self.change("link-targets/agents/guides/example.md", "skills/example/", "skills/other/")
        self.rejects("invalid shim owner/runtime rules/retirement")

    def owner_design(self) -> tuple[str, str]:
        """Create a design-owner backlink with one explicit precedence annotation."""
        source = "link-targets/agents/skills/example/references/design.md"
        target = "link-targets/agents/skills/example/SKILL.md"
        write(self.root, source, "# Design record\n[owner](../SKILL.md)\n"
              f"<!-- reference-kind: owner-precedence; target: {target} -->\n")
        with self.owner.open("a", encoding="utf-8") as stream:
            stream.write("[design](references/design.md)\n")
        return source, target

    def test_design_owner_precedence_preserves_reference_integrity(self) -> None:
        """Classify only the owner reminder while retaining both actual links."""
        source, target = self.owner_design()
        texts, edges = VALIDATOR.validate(self.root)
        self.assertIn(source, edges[target])
        self.assertIn(target, edges[source])
        self.assertEqual(VALIDATOR.non_dependencies(self.root, source, texts[source], edges[source]), {target})
        self.owner.unlink()
        self.rejects("Markdown target|missing or escaping")

    def test_design_owner_annotation_rejects_foreign_or_misplaced_sources(self) -> None:
        """Enforce the exact same-owner layout and direction for precedence."""
        source, target = self.owner_design()
        original = (self.root / source).read_text(encoding="utf-8")
        for location in ("references/other.md", "scripts/design.md", "references/nested/design.md"):
            with self.subTest(location=location):
                wrong = "link-targets/agents/skills/example/" + location
                write(self.root, wrong, original)
                with self.assertRaisesRegex(VALIDATOR.ValidationError, "invalid non-dependency"):
                    VALIDATOR.non_dependencies(self.root, wrong, original, {target})
        other = "link-targets/agents/skills/other/SKILL.md"
        write(self.root, other, "# Other\n")
        foreign = original.replace("../SKILL.md", "../../other/SKILL.md").replace(target, other)
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "invalid non-dependency"):
            VALIDATOR.non_dependencies(self.root, source, foreign, {other})
        reverse = f"[design](references/design.md)\n<!-- reference-kind: owner-precedence; target: {source} -->\n"
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "invalid non-dependency"):
            VALIDATOR.non_dependencies(self.root, target, reverse, {source})

    def test_design_owner_annotation_requires_unique_link(self) -> None:
        """Require exactly one independent Markdown owner reference."""
        source, target = self.owner_design()
        original = (self.root / source).read_text(encoding="utf-8")
        for invalid, diagnostic in (
            (original.replace("[owner](../SKILL.md)", "Owner"), "unbacked"),
            (original + "[owner](../SKILL.md)\n", "invalid non-dependency"),
            (original + f"<!-- reference-kind: owner-precedence; target: {target} -->\n", "duplicate"),
        ):
            with self.subTest(invalid=invalid):
                write(self.root, source, invalid)
                self.rejects(diagnostic)

    def test_design_owner_annotation_cannot_hide_loaders_or_indirect_cycles(self) -> None:
        """Keep loader instructions and third-party read cycles non-exempt."""
        source, target = self.owner_design()
        original = (self.root / source).read_text(encoding="utf-8")
        for verb in ("Read", "Load", "Apply", "Invoke", "Resolve", "Use", "Follow", "Run"):
            with self.subTest(verb=verb):
                write(self.root, source, original.replace("[owner]", f"{verb} [owner]"))
                self.rejects("runtime loader cannot be exempted")
        write(self.root, source, original + "[other](other.md)\n")
        write(self.root, "link-targets/agents/skills/example/references/other.md", "[owner](../SKILL.md)\n")
        self.rejects("dependency cycle")

    def test_design_owner_annotation_cannot_allow_escape(self) -> None:
        """Reject an annotated backlink whose target leaves the instruction tree."""
        source, _ = self.owner_design()
        self.owner.unlink()
        try:
            self.owner.symlink_to(SCRIPT)
        except OSError as error:
            self.skipTest(f"symlink creation unavailable: {error}")
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "Markdown target|missing or escaping"):
            VALIDATOR.references(self.root, source, (self.root / source).read_text(encoding="utf-8"))

    def test_repository_inventory_without_private_host_configuration(self) -> None:
        """Run the current tracked/candidate tree from an unrelated CWD without overlays."""
        root = VALIDATOR.instruction_root(SCRIPT)
        with tempfile.TemporaryDirectory() as directory:
            checkout = Path(directory).resolve()
            for path in VALIDATOR.source_paths(root):
                source = root / path
                if not source.is_file():
                    continue
                destination = checkout / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                if source.is_symlink():
                    try:
                        destination.symlink_to(os.readlink(source))
                    except OSError as error:
                        self.skipTest(f"tracked symlink reproduction unavailable: {error}")
                else:
                    shutil.copyfile(source, destination)
            self.assertFalse((checkout / VALIDATOR.HOST_LOCAL).exists())
            result = subprocess.run([sys.executable, "-B", str(checkout / VALIDATOR.AGENTS / "tools/validate-instructions.py")],
                                    cwd=self.root, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            architect = checkout / "link-targets/claude/agents/architect.md"
            original = architect.read_text(encoding="utf-8")
            self.assertIn("implementation-planning/SKILL.md", original)
            architect.write_text(original.replace("implementation-planning/SKILL.md", "unreferenced-placeholder"), encoding="utf-8")
            regression = subprocess.run(
                [sys.executable, "-B", str(checkout / VALIDATOR.AGENTS / "tools/test-instructions.py"),
                 "InstructionTests.test_repository_dependency_and_model_composition"],
                cwd=self.root, capture_output=True, text=True, check=False,
            )
            self.assertNotEqual(regression.returncode, 0)
            self.assertIn("link-targets/claude/agents/architect.md", regression.stderr)

    def test_default_root_outside_cwd(self) -> None:
        """Run the real validator from an unrelated working directory."""
        result = subprocess.run([sys.executable, "-B", str(SCRIPT)], cwd=self.root, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)

    def assert_resolver_procedures(self, texts: dict[str, str]) -> None:
        """Require the full strict-root procedure inside the normative Guide of every self-contained resolver."""
        for name in RESOLVER_NAMES:
            path = f"{VALIDATOR.SKILLS}/{name}/SKILL.md"
            self.assertIn(ROOT_PROCEDURE, " ".join(guide_section(texts[path]).split()), path)

    def test_resolver_procedure_detects_relocation_outside_guide(self) -> None:
        """Reject an intact procedure that only sits outside the normative Guide section."""
        root = VALIDATOR.instruction_root(SCRIPT)
        texts, _ = VALIDATOR.validate(root)
        for name in RESOLVER_NAMES:
            path = f"{VALIDATOR.SKILLS}/{name}/SKILL.md"
            guide = guide_section(texts[path])
            normalized_guide = " ".join(guide.split())
            self.assertIn(ROOT_PROCEDURE, normalized_guide)
            # Rebuild the Guide without the procedure and keep the procedure verbatim before the heading.
            procedure_start = normalized_guide.index(ROOT_PROCEDURE)
            remaining_guide = normalized_guide[:procedure_start] + normalized_guide[procedure_start + len(ROOT_PROCEDURE):]
            prefix = texts[path][:texts[path].index(guide)]
            placements = {
                "before Guide": prefix.replace("## Guide", ROOT_PROCEDURE + "\n\n## Guide", 1) + remaining_guide + "\n",
                "after Guide": prefix + remaining_guide + "\n\n## Other\n\n" + ROOT_PROCEDURE + "\n",
            }
            for placement, relocated in placements.items():
                changed = dict(texts)
                changed[path] = relocated
                with self.subTest(owner=name, placement=placement), self.assertRaises(AssertionError):
                    self.assert_resolver_procedures(changed)

    def test_guide_carries_relocated_runtime_rules(self) -> None:
        """Keep runtime rules from Issue #158 inside the normative Guide section."""
        root = VALIDATOR.instruction_root(SCRIPT)
        texts, _ = VALIDATOR.validate(root)
        for name, rules in GUIDE_RUNTIME_RULES.items():
            path = f"{VALIDATOR.SKILLS}/{name}/SKILL.md"
            normalized_guide = " ".join(guide_section(texts[path]).split())
            for rule in rules:
                with self.subTest(owner=name, rule=rule[:40]):
                    self.assertIn(" ".join(rule.split()), normalized_guide)

    def test_resolver_procedure_detects_containment_clause_removal(self) -> None:
        """Reject losing containment even when all old keyword checks still pass."""
        root = VALIDATOR.instruction_root(SCRIPT)
        texts, _ = VALIDATOR.validate(root)
        clause = ", with the entrypoint and both sentinels still contained after real-path resolution"
        for name in RESOLVER_NAMES:
            path = f"{VALIDATOR.SKILLS}/{name}/SKILL.md"
            changed = dict(texts)
            self.assertIn(clause, changed[path])
            changed[path] = changed[path].replace(clause, "", 1)
            with self.subTest(owner=name), self.assertRaises(AssertionError):
                self.assert_resolver_procedures(changed)

    def assert_external_operation_rules(self, texts: dict[str, str]) -> None:
        """Require the safety clauses and ownership boundaries in the runtime Guide text."""
        for name, rules in EXTERNAL_OPERATION_RULES.items():
            path = f"{VALIDATOR.SKILLS}/{name}/SKILL.md"
            normalized_guide = " ".join(guide_section(texts[path]).split())
            for rule in rules:
                self.assertIn(" ".join(rule.split()), normalized_guide, path)
        authorization = texts[f"{VALIDATOR.SKILLS}/external-operation-authorization/SKILL.md"]
        self.assertNotIn("Place only the minimum authorization boundaries", guide_section(authorization))
        authoring_heading = "## Instruction-layout authoring rule\n"
        self.assertIn(authoring_heading, authorization)
        authoring_section = re.split(r"^## ", authorization.split(authoring_heading, 1)[1], maxsplit=1, flags=re.MULTILINE)[0]
        self.assertIn("Place only the minimum authorization boundaries", authoring_section)
        self.assertIn("This is a mandatory authoring rule when maintaining the instruction layout", authoring_section)
        discovery = authorization.split("## Discovery contract", 1)[1].split("## Runtime contract", 1)[0]
        self.assertIn("or author or maintain the placement of these authorization rules in the instruction layout.", discovery)
        self.assertIn("no authoring or maintenance of this authorization instruction layout.", discovery)

    def test_external_operation_runtime_contract(self) -> None:
        """Check source-contract safeguards without claiming to execute an authorization engine."""
        root = VALIDATOR.instruction_root(SCRIPT)
        texts, _ = VALIDATOR.validate(root)
        self.assert_external_operation_rules(texts)

    def test_external_operation_rules_reject_missing_or_nonruntime_safeguards(self) -> None:
        """Reject deletion or nonruntime relocation of each required execution safeguard."""
        root = VALIDATOR.instruction_root(SCRIPT)
        texts, _ = VALIDATOR.validate(root)
        for name, rules in EXTERNAL_OPERATION_RULES.items():
            path = f"{VALIDATOR.SKILLS}/{name}/SKILL.md"
            for rule in rules:
                for placement in ("removed", "nonruntime"):
                    changed = dict(texts)
                    self.assertIn(rule, changed[path])
                    changed[path] = changed[path].replace(rule, "", 1)
                    if placement == "nonruntime":
                        changed[path] += "\n\n## Test nonruntime placement\n\n" + rule + "\n"
                    with self.subTest(owner=name, rule=rule, placement=placement), self.assertRaises(AssertionError):
                        self.assert_external_operation_rules(changed)

    def test_external_operation_authoring_rule_requires_its_authoring_section(self) -> None:
        """Reject relocating the authoring obligation into runtime metadata or design rationale."""
        root = VALIDATOR.instruction_root(SCRIPT)
        texts, _ = VALIDATOR.validate(root)
        path = f"{VALIDATOR.SKILLS}/external-operation-authorization/SKILL.md"
        rule = "Place only the minimum authorization boundaries necessary at all times in AGENTS.md."
        for heading in ("Guide", "Discovery contract", "Runtime contract", "Design"):
            changed = dict(texts)
            changed[path] = changed[path].replace(rule, "", 1)
            if heading == "Design":
                changed[path] += "\n\n## Design\n\n" + rule + "\n"
            else:
                changed[path] = changed[path].replace(f"## {heading}\n", f"## {heading}\n\n{rule}\n", 1)
            with self.subTest(heading=heading), self.assertRaises(AssertionError):
                self.assert_external_operation_rules(changed)

    def test_external_operation_authoring_route_is_discoverable(self) -> None:
        """Reject deleting the local authoring trigger or reinstating its contradictory exclusion."""
        root = VALIDATOR.instruction_root(SCRIPT)
        texts, _ = VALIDATOR.validate(root)
        path = f"{VALIDATOR.SKILLS}/external-operation-authorization/SKILL.md"
        mutations = (
            ("; or author or maintain the placement of these authorization rules in the instruction layout.", "."),
            ("no authoring or maintenance of this authorization instruction layout.", "only local work/verification is performed."),
        )
        for before, after in mutations:
            changed = dict(texts)
            self.assertIn(before, changed[path])
            changed[path] = changed[path].replace(before, after, 1)
            with self.subTest(before=before), self.assertRaises(AssertionError):
                self.assert_external_operation_rules(changed)

    def test_external_posting_requires_both_provision_and_publication_permission(self) -> None:
        """Reject weakening the two independent prerequisites to an either-or condition."""
        root = VALIDATOR.instruction_root(SCRIPT)
        texts, _ = VALIDATOR.validate(root)
        path = f"{VALIDATOR.SKILLS}/external-posting/SKILL.md"
        changed = dict(texts)
        before = "the user has supplied the information, and an explicit user instruction"
        self.assertIn(before, changed[path])
        changed[path] = changed[path].replace(before, "the user has supplied the information, or an explicit user instruction", 1)
        with self.assertRaises(AssertionError):
            self.assert_external_operation_rules(changed)

    def test_repository_dependency_and_model_composition(self) -> None:
        """Preserve actual ownership, conditional closure and model combinations."""
        root = VALIDATOR.instruction_root(SCRIPT)
        texts, edges = VALIDATOR.validate(root)
        expected_names = {
            "agent-output", "approval-request-workflow", "commit-message", "delegation",
            "dotnet-testing", "external-posting", "git-operations", "github", "structured-data",
            "advisor-review", "implementation-planning", "external-operation-authorization",
            "review-consolidation", "code-commenting",
        }
        actual_names = {Path(path).parent.name for path, text in texts.items() if path.endswith("/SKILL.md") and "## Discovery contract" in text}
        self.assertEqual(actual_names, expected_names)
        expected_profiles = {name: "required" for name in expected_names - {"code-commenting", "review-consolidation"}}
        expected_profiles.update({"code-commenting": "exempt", "review-consolidation": "exempt"})
        actual_profiles = {
            Path(path).parent.name: VALIDATOR.check_discovery(path, text).split(";", 1)[0]
            for path, text in texts.items() if path.endswith("/SKILL.md") and "## Discovery contract" in text
        }
        self.assertEqual(actual_profiles, expected_profiles)
        expected_shims = {f"{VALIDATOR.GUIDES}/{name}.md" for name, profile in expected_profiles.items() if profile == "required"}
        actual_shims = {path for path, text in texts.items() if text.startswith("# Claude Code compatibility shim:")}
        self.assertEqual(actual_shims, expected_shims)
        self.assertTrue(expected_shims.issubset(edges[VALIDATOR.ROUTER]))
        entrypoints = {path for path in VALIDATOR.source_paths(root) if path.startswith(VALIDATOR.SKILLS + "/")
                       and path.endswith("/SKILL.md") and len(Path(path).parts) == 5}
        self.assertEqual({path for path in texts if path in entrypoints}, entrypoints)
        required_routes = {
            "approval-request-workflow": {"external-operation-authorization"},
            "external-posting": {"external-operation-authorization"},
            "git-operations": {"commit-message"},
            "review-consolidation": {"github", "approval-request-workflow", "external-posting", "external-operation-authorization"},
            "execution-lifecycle-gate": {"advisor-review", "external-operation-authorization"},
            "rigorous-review": {"advisor-review", "implementation-planning"},
        }
        for source, targets in required_routes.items():
            for target in targets:
                self.assertIn(f"{VALIDATOR.SKILLS}/{target}/SKILL.md", edges[f"{VALIDATOR.SKILLS}/{source}/SKILL.md"])
        source_routes = {
            "link-targets/claude/agents/architect.md": {f"{VALIDATOR.SKILLS}/implementation-planning/SKILL.md"},
            f"{VALIDATOR.GUIDES}/github-cli-without-clone.md": {
                f"{VALIDATOR.SKILLS}/github/SKILL.md", f"{VALIDATOR.SKILLS}/external-operation-authorization/SKILL.md"},
            "README.manual.md": {"codex-wsl/SETUP.md", "codex-wsl/CODEX_HOME.md", VALIDATOR.SKILLS},
            "chezmoi/.chezmoiscripts/run_after_junctions.sh.tmpl": {VALIDATOR.SKILLS},
            f"{VALIDATOR.SKILLS}/wsl-codex-exec/SKILL.md": {"codex-wsl/SETUP.md", "codex-wsl/CODEX_HOME.md"},
            f"{VALIDATOR.AGENTS}/AGENTS.md": {f"{VALIDATOR.GUIDES}/README.md", f"{VALIDATOR.SKILLS}/code-commenting/SKILL.md"},
            VALIDATOR.ROUTER: {f"{VALIDATOR.SKILLS}/review-consolidation/SKILL.md"},
            f"{VALIDATOR.SKILLS}/cognitive-rhythm-writing/SKILL.md": {f"{VALIDATOR.SKILLS}/japanese-tech-writing/SKILL.md"},
        }
        for source, targets in source_routes.items():
            self.assertTrue(targets.issubset(edges[source]), source)
        self.assertIn("require the loaded file and both sentinels to remain inside that candidate after real-path resolution",
                      texts[f"{VALIDATOR.GUIDES}/README.md"])
        self.assert_resolver_procedures(texts)
        for name in RESOLVER_NAMES:
            path = f"{VALIDATOR.SKILLS}/{name}/SKILL.md"
            self.assertNotIn(f"{VALIDATOR.GUIDES}/README.md", edges[path])
        design = f"{VALIDATOR.SKILLS}/task-complete-notify/references/design.md"
        owner = f"{VALIDATOR.SKILLS}/task-complete-notify/SKILL.md"
        self.assertIn(design, edges[owner])
        self.assertIn(owner, edges[design])
        self.assertEqual(VALIDATOR.non_dependencies(root, design, texts[design], edges[design]), {owner})
        delegation_path = f"{VALIDATOR.SKILLS}/delegation/SKILL.md"
        compositions = {}
        for line in texts[delegation_path].splitlines():
            model = re.match(r"\| `(gpt-[a-z0-9.-]+)` \|", line)
            if model:
                compositions[model.group(1)] = set(re.findall(r"\]\(([^)]+)\)", line))
        prefix = "references/model-guides/"
        for model, variant in {"gpt-6-astra": "astra", "gpt-6-sol": "sol", "gpt-6.1-sol": "sol", "gpt-6-luna": "luna"}.items():
            self.assertEqual(compositions[model], {prefix + "model-gpt-6.md", prefix + f"model-{variant}.md"})
        for model in ("gpt-5.6", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"):
            self.assertEqual(compositions[model], {prefix + "model-gpt-5.6.md"})
        family_path = f"{VALIDATOR.SKILLS}/delegation/references/model-guides/model-gpt-6.md"
        for variant in ("astra", "sol", "luna"):
            variant_path = f"{VALIDATOR.SKILLS}/delegation/references/model-guides/model-{variant}.md"
            self.assertNotIn(family_path, edges[variant_path], "variant guides remain generation-independent")
        for filename in (
            "model-gpt-5.6.md", "model-gpt-6.md", "model-astra.md", "model-sol.md", "model-luna.md",
            "model-gpt-6-astra.md", "model-gpt-6-sol.md", "model-gpt-6-luna.md",
        ):
            self.assertFalse((root / VALIDATOR.GUIDES / filename).exists(), filename)


if __name__ == "__main__":
    unittest.main()
