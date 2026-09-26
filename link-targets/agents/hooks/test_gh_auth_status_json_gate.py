#!/usr/bin/env python3
"""Regression tests for gh_auth_status_json_gate.py."""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path


HOOK_SCRIPT = Path(__file__).with_name("gh_auth_status_json_gate.py")


def run_hook(
    command: str,
    *,
    event_name: str = "PreToolUse",
    tool_name: str = "Bash",
) -> subprocess.CompletedProcess[str]:
    """Run the hook with one synthetic Codex event."""

    event = {
        "hook_event_name": event_name,
        "tool_name": tool_name,
        "tool_input": {"command": command},
    }
    return subprocess.run(
        [sys.executable, str(HOOK_SCRIPT)],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        input=json.dumps(event),
    )


def denial_reason(result: subprocess.CompletedProcess[str]) -> str | None:
    """Return the PreToolUse denial reason when the hook emits one."""

    if not result.stdout:
        return None
    response = json.loads(result.stdout)
    return response["hookSpecificOutput"]["permissionDecisionReason"]


class GhAuthStatusGateTests(unittest.TestCase):
    """Verify the gate blocks human-readable output and permits scoped JSON."""

    def test_human_readable_status_is_denied(self) -> None:
        """The unscoped command must direct diagnosis to host-scoped JSON."""

        result = run_hook("gh auth status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--json hosts", denial_reason(result) or "")

    def test_denial_json_is_ascii_safe(self) -> None:
        """The denial response must decode as UTF-8 on code-page-based hosts."""

        result = run_hook("gh auth status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.isascii(), result.stdout)
        self.assertIn("--json hosts", denial_reason(result) or "")

    def test_host_scoped_json_status_is_allowed(self) -> None:
        """The canonical JSON command must pass without rewriting."""

        result = run_hook("gh auth status -h github.com --json hosts")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_equals_json_option_is_allowed(self) -> None:
        """The equivalent equals form is allowed when its host is explicit."""

        result = run_hook("gh auth status --hostname github.com --json=hosts")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_json_without_host_scope_is_denied(self) -> None:
        """JSON output without github.com selection must not mix host state."""

        result = run_hook("gh auth status --json hosts")
        self.assertIsNotNone(denial_reason(result))

    def test_conflicting_host_selectors_are_denied(self) -> None:
        """A later selector must not override the explicit github.com host."""

        result = run_hook("gh auth status -h github.com --hostname example.org --json hosts")
        self.assertIsNotNone(denial_reason(result))

    def test_repeated_json_options_are_denied(self) -> None:
        """Repeated JSON flags are ambiguous and must not satisfy the gate."""

        result = run_hook("gh auth status -h github.com --json hosts --json hosts")
        self.assertIsNotNone(denial_reason(result))

    def test_human_output_with_host_scope_is_denied(self) -> None:
        """A host selector alone does not replace the JSON output requirement."""

        result = run_hook("gh auth status -h github.com")
        self.assertIsNotNone(denial_reason(result))

    def test_chained_command_is_denied(self) -> None:
        """A status command after a shell separator must still be detected."""

        result = run_hook("printf ready; gh auth status")
        self.assertIsNotNone(denial_reason(result))

    def test_quoted_documentation_text_is_allowed(self) -> None:
        """A string that mentions the command without invoking it is allowed."""

        result = run_hook("printf '%s' 'gh auth status'")
        self.assertEqual(result.stdout, "")

    def test_quoted_shell_keywords_and_operators_are_arguments(self) -> None:
        """Quoted text must not be mistaken for shell control syntax."""

        result = run_hook("printf '%s\\n' 'if' ';' gh auth status")
        self.assertEqual(result.stdout, "")

    def test_status_after_shell_if_is_denied(self) -> None:
        """A direct status call remains visible inside simple shell control flow."""

        result = run_hook("if true; then gh auth status; fi")
        self.assertIsNotNone(denial_reason(result))

    def test_redirection_target_is_not_treated_as_json_option(self) -> None:
        """A filename that resembles an option must not permit human output."""

        result = run_hook("gh auth status > --json hosts")
        self.assertIsNotNone(denial_reason(result))

    def test_quoted_heredoc_body_is_not_treated_as_a_command(self) -> None:
        """Quoted here-document text is data, not an executable command."""

        result = run_hook("cat <<'EOF'\ngh auth status\nEOF")
        self.assertEqual(result.stdout, "")

    def test_status_after_heredoc_is_still_denied(self) -> None:
        """Parsing resumes after a literal here-document's closing delimiter."""

        result = run_hook("cat <<'EOF'\nexample text\nEOF\ngh auth status")
        self.assertIsNotNone(denial_reason(result))

    def test_non_bash_tool_is_ignored(self) -> None:
        """Events for tools outside the Bash matcher do not get blocked."""

        result = run_hook("gh auth status", tool_name="apply_patch")
        self.assertEqual(result.stdout, "")

    def test_non_pretool_event_is_ignored(self) -> None:
        """Events other than PreToolUse do not get blocked."""

        result = run_hook("gh auth status", event_name="PostToolUse")
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
