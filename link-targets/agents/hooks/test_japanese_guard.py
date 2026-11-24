#!/usr/bin/env python3
"""Regression tests for japanese_guard.py.

Run: uv run --managed-python --no-project --no-python-downloads --python 3.13
     -m unittest discover -s link-targets/agents/hooks -p "test_japanese_guard.py"
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


HOOK_SCRIPT = Path(__file__).with_name("japanese_guard.py")

ENGLISH_ANSWER = (
    "I updated the configuration and verified that every check passes. "
    "The remaining work is to publish the branch and open a pull request."
)
JAPANESE_ANSWER = "設定を更新し、すべてのチェックが通ることを確かめました。残りはブランチの公開と PR の作成です。"
MIXED_ANSWER = ENGLISH_ANSWER + " 補足: 設定ファイルを確認しました。"


def run_hook(
    event: dict,
    *,
    arguments: tuple[str, ...] = (),
    extra_environment: dict[str, str] | None = None,
    input_prefix: bytes = b"",
) -> subprocess.CompletedProcess[bytes]:
    """Run the hook in a child process with one event encoded as UTF-8 bytes.

    The guard reads its environment variables at import time, so each case runs
    in its own process. The wait for the Claude transcript is disabled to keep
    the tests fast. input_prefix is written before the JSON, for example a
    UTF-8 byte order mark.
    """

    environment = dict(os.environ)
    environment.pop("JAPANESE_GUARD_DISABLE", None)
    environment["JAPANESE_GUARD_WAIT"] = "0"
    environment.update(extra_environment or {})
    return subprocess.run(
        [sys.executable, str(HOOK_SCRIPT), *arguments],
        check=False,
        capture_output=True,
        input=input_prefix + json.dumps(event, ensure_ascii=False).encode("utf-8"),
        env=environment,
        timeout=30,
    )


def stop_event(message: str | None, **fields: object) -> dict:
    """Return a synthetic Stop hook event with the given final answer."""

    event = {"hook_event_name": "Stop", "stop_hook_active": False, "last_assistant_message": message}
    event.update(fields)
    return event


def wrap_up_event(recap: str) -> dict:
    """Return a synthetic PreToolUse event for the desktop app's wrap_up tool."""

    return {
        "hook_event_name": "PreToolUse",
        "tool_name": "mcp__ccd_turn__wrap_up",
        "tool_input": {"recap": recap},
    }


def decoded_response(result: subprocess.CompletedProcess[bytes]) -> dict | None:
    """Return the hook's JSON response, or None when it printed nothing.

    Decoding as ASCII also asserts that the response has no raw non-ASCII bytes.
    """

    output = result.stdout.decode("ascii").strip()
    return json.loads(output) if output else None


class ClaudeModeTests(unittest.TestCase):
    """Verify the upstream Claude Code behavior is kept apart from the encoding changes."""

    def test_english_final_answer_is_blocked_with_japanese_reason(self) -> None:
        """An English final answer must be sent back with the Japanese rewrite request."""

        result = run_hook(stop_event(ENGLISH_ANSWER))
        self.assertEqual(result.returncode, 0, result.stderr)
        response = decoded_response(result)
        self.assertEqual(response["decision"], "block")
        self.assertIn("日本語に書き直して", response["reason"])

    def test_japanese_final_answer_passes(self) -> None:
        """A Japanese final answer must not produce any response."""

        result = run_hook(stop_event(JAPANESE_ANSWER))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(decoded_response(result))

    def test_active_stop_hook_passes(self) -> None:
        """A rewrite that is still English must not be sent back a second time."""

        result = run_hook(stop_event(ENGLISH_ANSWER, stop_hook_active=True))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(decoded_response(result))

    def test_json_only_answer_passes(self) -> None:
        """A JSON-only answer is machine output and must not be sent back."""

        result = run_hook(stop_event('{"status": "completed", "message": "' + ENGLISH_ANSWER + '"}'))
        self.assertIsNone(decoded_response(result))

    def test_disable_variable_turns_the_guard_off(self) -> None:
        """JAPANESE_GUARD_DISABLE=1 must make the guard do nothing."""

        result = run_hook(stop_event(ENGLISH_ANSWER), extra_environment={"JAPANESE_GUARD_DISABLE": "1"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"")

    def test_english_wrap_up_is_denied(self) -> None:
        """An English wrap_up box must be denied before it is shown."""

        response = decoded_response(run_hook(wrap_up_event(ENGLISH_ANSWER)))
        self.assertEqual(response["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIn("日本語", response["hookSpecificOutput"]["permissionDecisionReason"])

    def test_japanese_wrap_up_passes(self) -> None:
        """A Japanese wrap_up box must be allowed."""

        self.assertIsNone(decoded_response(run_hook(wrap_up_event(JAPANESE_ANSWER))))


class CodexModeTests(unittest.TestCase):
    """Verify the Codex Stop mode selected with `--agent codex`."""

    def test_english_final_answer_is_blocked_with_codex_reason(self) -> None:
        """Codex mode must ask for the whole final answer to be rewritten."""

        result = run_hook(stop_event(ENGLISH_ANSWER), arguments=("--agent", "codex"))
        self.assertEqual(result.returncode, 0, result.stderr)
        response = decoded_response(result)
        self.assertEqual(response["decision"], "block")
        self.assertIn("最終回答全体", response["reason"])

    def test_missing_or_empty_final_answer_passes(self) -> None:
        """A null or empty final answer must be allowed in Codex mode."""

        for message in (None, "", "   "):
            with self.subTest(message=message):
                result = run_hook(stop_event(message), arguments=("--agent", "codex"))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIsNone(decoded_response(result))

    def test_active_stop_hook_passes(self) -> None:
        """Codex mode must also send an answer back at most once per turn."""

        result = run_hook(stop_event(ENGLISH_ANSWER, stop_hook_active=True), arguments=("--agent", "codex"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(decoded_response(result))

    def test_json_only_answer_passes(self) -> None:
        """Codex mode must not send back a JSON-only answer, which is machine output."""

        result = run_hook(
            stop_event('{"status": "completed", "message": "' + ENGLISH_ANSWER + '"}'),
            arguments=("--agent", "codex"),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(decoded_response(result))

    def test_disable_variable_turns_the_guard_off(self) -> None:
        """JAPANESE_GUARD_DISABLE=1 must also turn off Codex mode."""

        result = run_hook(
            stop_event(ENGLISH_ANSWER), arguments=("--agent", "codex"),
            extra_environment={"JAPANESE_GUARD_DISABLE": "1"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"")

    def test_transcript_is_not_read(self) -> None:
        """Codex mode must judge only last_assistant_message, even when a transcript path is given."""

        with tempfile.TemporaryDirectory() as directory:
            transcript = Path(directory) / "transcript.jsonl"
            english_entry = {"type": "assistant", "message": {"content": [{"type": "text", "text": ENGLISH_ANSWER}]}}
            transcript.write_text(json.dumps(english_entry) + "\n", encoding="utf-8")
            claude_result = run_hook(stop_event(JAPANESE_ANSWER, transcript_path=str(transcript)))
            codex_result = run_hook(
                stop_event(JAPANESE_ANSWER, transcript_path=str(transcript)), arguments=("--agent", "codex"),
            )
        self.assertEqual(claude_result.returncode, 0, claude_result.stderr)
        self.assertEqual(codex_result.returncode, 0, codex_result.stderr)
        self.assertIsNotNone(decoded_response(claude_result))
        self.assertIsNone(decoded_response(codex_result))

    def test_codex_mode_never_calls_open(self) -> None:
        """Codex mode must not open any file, even when the result of a read would be discarded.

        The guard runs in this process with builtins.open replaced by a function
        that raises AssertionError, which an `except OSError` around a read
        cannot swallow.
        """

        event = stop_event(ENGLISH_ANSWER, transcript_path="transcript.jsonl")
        standard_input = io.TextIOWrapper(io.BytesIO(json.dumps(event).encode("utf-8")), encoding="utf-8")
        standard_output = io.StringIO()
        environment = {"JAPANESE_GUARD_WAIT": "0"}
        with mock.patch.dict(os.environ, environment), mock.patch.object(sys, "argv", [str(HOOK_SCRIPT), "--agent", "codex"]):
            os.environ.pop("JAPANESE_GUARD_DISABLE", None)
            specification = importlib.util.spec_from_file_location("japanese_guard_under_test", HOOK_SCRIPT)
            guard_module = importlib.util.module_from_spec(specification)
            specification.loader.exec_module(guard_module)
            with mock.patch("builtins.open", side_effect=AssertionError("open() was called in Codex mode")), \
                    mock.patch.object(sys, "stdin", standard_input), \
                    contextlib.redirect_stdout(standard_output):
                guard_module.main()
        self.assertEqual(json.loads(standard_output.getvalue())["decision"], "block")

    def test_unknown_agent_is_rejected(self) -> None:
        """An unknown agent name must fail instead of silently picking a mode."""

        result = run_hook(stop_event(ENGLISH_ANSWER), arguments=("--agent", "other"))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")


class EncodingTests(unittest.TestCase):
    """Verify UTF-8 input and ASCII output under a non-UTF-8 default encoding."""

    def test_utf8_input_under_code_page_932_defaults(self) -> None:
        """Japanese UTF-8 input must decode and the response must stay ASCII under cp932 defaults."""

        environment = {"PYTHONIOENCODING": "cp932", "PYTHONUTF8": "0"}
        for arguments in ((), ("--agent", "codex")):
            with self.subTest(arguments=arguments):
                result = run_hook(stop_event(MIXED_ANSWER), arguments=arguments, extra_environment=environment)
                self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", "replace"))
                response = decoded_response(result)
                self.assertEqual(response["decision"], "block")
                self.assertIn("日本語", response["reason"])

    def test_input_with_utf8_byte_order_mark(self) -> None:
        """Input that starts with a UTF-8 byte order mark must still be judged in both modes."""

        for arguments in ((), ("--agent", "codex")):
            with self.subTest(arguments=arguments):
                result = run_hook(stop_event(ENGLISH_ANSWER), arguments=arguments, input_prefix=b"\xef\xbb\xbf")
                self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", "replace"))
                self.assertEqual(decoded_response(result)["decision"], "block")


if __name__ == "__main__":
    unittest.main()
