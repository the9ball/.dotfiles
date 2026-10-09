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
contract is `link-targets/agents/skills/example/SKILL.md`. Read that Skill
and apply its `## Guide` section; this shim defines no runtime rules of its
own. If the Skill cannot be resolved, stop and report.
""")
    write(root, "chezmoi/dot_claude/CLAUDE.md", """Until Issue #75 is completed
| Request family | Compatibility shim (canonical source) |
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
        write(self.root, VALIDATOR.ROUTER, "Until Issue #75 is completed\n")
        self.rejects("no direct host/kernel route")
        write(self.root, "link-targets/agents/AGENTS.md", "Read `link-targets/agents/skills/example/SKILL.md`.\n")
        VALIDATOR.validate(self.root)

    def test_removed_exempt_contract_still_managed(self) -> None:
        """Keep directly routed exemptions managed without discovery headings."""
        (self.root / "link-targets/agents/guides/example.md").unlink()
        write(self.root, VALIDATOR.ROUTER, "Until Issue #75 is completed\n")
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
        write(self.root, VALIDATOR.ROUTER, "Until Issue #75 is completed\n")
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

    def test_git_binary_absence_uses_private_free_fixture_inventory(self) -> None:
        """Fall back to filesystem inventory without importing the host overlay."""
        write(self.root, VALIDATOR.HOST_LOCAL, "Private data\n").write_bytes(b"\xff")
        with patch.object(VALIDATOR.subprocess, "run", side_effect=FileNotFoundError):
            texts, _ = VALIDATOR.validate(self.root)
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
        for name in ("advisor-review", "delegation", "git-operations", "implementation-planning", "review-consolidation"):
            path = f"{VALIDATOR.SKILLS}/{name}/SKILL.md"
            self.assertNotIn(f"{VALIDATOR.GUIDES}/README.md", edges[path])
            for required_word in ("symlink/junction", "AGENTS.md", "guides/README.md", "exactly one", "grandparent"):
                self.assertIn(required_word, texts[path])
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
