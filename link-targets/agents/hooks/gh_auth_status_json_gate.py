#!/usr/bin/env python3
"""Require host-scoped JSON for GitHub CLI authentication status checks."""

from __future__ import annotations

import json
import re
import sys
from collections.abc import Iterator, Sequence
from dataclasses import dataclass


SHELL_BOUNDARIES = frozenset(
    {";", "&&", "||", "|", "|&", "&", "(", ")", "{", "}", "\n"}
)
SHELL_KEYWORDS = frozenset(
    {
        "!",
        "case",
        "coproc",
        "do",
        "done",
        "elif",
        "else",
        "esac",
        "fi",
        "for",
        "function",
        "if",
        "select",
        "then",
        "until",
        "while",
    }
)
SHELL_WRAPPERS = frozenset(
    {"builtin", "command", "env", "exec", "nohup", "sudo", "time"}
)
REDIRECTION_OPERATORS = frozenset(
    {"<", ">", "<<", "<<-", "<<<", ">>", "<&", ">&", "<>", ">|", "&>", "&>>"}
)
ASSIGNMENT_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$", re.DOTALL)
DENIAL_REASON = (
    "通常表示だけでは認証失敗と判断できません。"
    "`gh auth status -h github.com --json hosts` を実行し、"
    "active: true の github.com entry の state と error を確認してください。"
    "この hook は状態の分類や login / refresh を行いません。"
)


@dataclass(frozen=True)
class ShellToken:
    """Represent one shell word or operator and retain quote provenance."""

    value: str
    is_operator: bool = False
    is_unquoted: bool = False


def _skip_heredoc_bodies(
    command: str,
    body_start: int,
    heredocs: Sequence[tuple[str, bool]],
) -> int | None:
    """Skip literal here-document bodies and return the next shell-text offset."""

    position = body_start
    for delimiter, strip_tabs in heredocs:
        if "$" in delimiter or "`" in delimiter:
            return None
        while position <= len(command):
            newline = command.find("\n", position)
            line_end = len(command) if newline < 0 else newline
            line = command[position:line_end]
            candidate = line.lstrip("\t") if strip_tabs else line
            if candidate == delimiter:
                position = len(command) if newline < 0 else newline + 1
                break
            if newline < 0:
                return None
            position = newline + 1
        else:
            return None
    return position


def _tokenize_command(command: str) -> list[ShellToken] | None:
    """Tokenize common shell words and operators, or fail on unclosed quoting."""

    tokens: list[ShellToken] = []
    word: list[str] = []
    word_started = False
    word_is_unquoted = True
    quote: str | None = None
    expecting_heredoc_delimiter = False
    heredoc_strip_tabs = False
    pending_heredocs: list[tuple[str, bool]] = []

    def flush_word() -> None:
        """Append the current word and reset the word buffer."""

        nonlocal word_started, word_is_unquoted, expecting_heredoc_delimiter
        if word_started:
            token = ShellToken("".join(word), is_unquoted=word_is_unquoted)
            tokens.append(token)
            if expecting_heredoc_delimiter:
                pending_heredocs.append((token.value, heredoc_strip_tabs))
                expecting_heredoc_delimiter = False
            word.clear()
            word_started = False
            word_is_unquoted = True

    index = 0
    while index < len(command):
        character = command[index]

        if quote == "'":
            if character == "'":
                quote = None
            else:
                word.append(character)
            index += 1
            continue

        if quote == '"':
            if character == '"':
                quote = None
                index += 1
                continue
            if character == "\\" and index + 1 < len(command):
                following = command[index + 1]
                if following == "\n":
                    index += 2
                    continue
                if following in '$`"\\':
                    word.append(following)
                else:
                    word.extend((character, following))
                index += 2
                continue
            word.append(character)
            index += 1
            continue

        if character in " \t\r":
            flush_word()
            index += 1
            continue

        if character == "#" and not word_started:
            newline = command.find("\n", index)
            if newline < 0:
                break
            index = newline
            continue

        if character == "\\":
            if index + 1 >= len(command):
                return None
            following = command[index + 1]
            word_started = True
            word_is_unquoted = False
            if following != "\n":
                word.append(following)
            index += 2
            continue

        if character in "'\"":
            quote = character
            word_started = True
            word_is_unquoted = False
            index += 1
            continue

        if character == "\n":
            flush_word()
            if expecting_heredoc_delimiter:
                return None
            tokens.append(ShellToken(character, is_operator=True))
            index += 1
            if pending_heredocs:
                next_shell_text = _skip_heredoc_bodies(command, index, pending_heredocs)
                if next_shell_text is None:
                    return None
                index = next_shell_text
                pending_heredocs.clear()
            continue

        if character in "{}":
            previous = command[index - 1] if index > 0 else None
            following = command[index + 1] if index + 1 < len(command) else None
            before_boundary = previous is None or previous.isspace() or previous in ";|&()"
            after_boundary = following is None or following.isspace() or following in ";|&()"
            if not (before_boundary and after_boundary):
                word.append(character)
                word_started = True
                index += 1
                continue

        if character in ";&|<>(){}\n":
            if expecting_heredoc_delimiter:
                return None
            flush_word()
            operator = character
            index += 1
            if character in "&|" and index < len(command) and command[index] == character:
                operator += command[index]
                index += 1
            elif character == "|" and index < len(command) and command[index] == "&":
                operator += command[index]
                index += 1
            elif character in "<>":
                if index < len(command) and command[index] == character:
                    operator += command[index]
                    index += 1
                    if character == "<" and index < len(command) and command[index] in "<-":
                        operator += command[index]
                        index += 1
                if index < len(command) and command[index] in "&|":
                    operator += command[index]
                    index += 1
            elif character == "&" and index < len(command) and command[index] == ">":
                operator += command[index]
                index += 1
                if index < len(command) and command[index] == ">":
                    operator += command[index]
                    index += 1
            tokens.append(ShellToken(operator, is_operator=True))
            if operator in {"<<", "<<-"}:
                expecting_heredoc_delimiter = True
                heredoc_strip_tabs = operator == "<<-"
            continue

        word.append(character)
        word_started = True
        index += 1

    if quote is not None or expecting_heredoc_delimiter or pending_heredocs:
        return None
    flush_word()
    return tokens


def _command_segments(tokens: Sequence[ShellToken]) -> Iterator[list[ShellToken]]:
    """Yield simple command segments while honoring quoted operators and keywords."""

    segment: list[ShellToken] = []
    for token in tokens:
        if token.is_operator and token.value in SHELL_BOUNDARIES:
            if segment:
                yield segment
                segment = []
            continue
        if (
            not segment
            and not token.is_operator
            and token.is_unquoted
            and token.value.casefold() in SHELL_KEYWORDS
        ):
            continue
        segment.append(token)
    if segment:
        yield segment


def _executable_name(token: str) -> str:
    """Return an executable's basename with Windows separators normalized."""

    return token.rsplit("/", 1)[-1].rsplit("\\", 1)[-1].casefold()


def _arguments_without_redirections(tokens: Sequence[ShellToken]) -> list[str]:
    """Remove shell redirections from command arguments."""

    arguments: list[str] = []
    position = 0
    while position < len(tokens):
        token = tokens[position]
        if (
            token.value.isdigit()
            and position + 1 < len(tokens)
            and tokens[position + 1].is_operator
            and tokens[position + 1].value in REDIRECTION_OPERATORS
        ):
            position += 3
            continue
        if token.is_operator and token.value in REDIRECTION_OPERATORS:
            position += 2
            continue
        arguments.append(token.value)
        position += 1
    return arguments


def _status_arguments(segment: Sequence[ShellToken]) -> list[str] | None:
    """Return arguments after a direct gh auth status invocation, if present."""

    position = 0
    while position < len(segment):
        shell_token = segment[position]
        token = shell_token.value
        if shell_token.is_unquoted and ASSIGNMENT_PATTERN.fullmatch(token):
            position += 1
            continue
        if token.casefold() in SHELL_WRAPPERS:
            position += 1
            continue
        if (
            token.isdigit()
            and position + 1 < len(segment)
            and segment[position + 1].is_operator
            and segment[position + 1].value in REDIRECTION_OPERATORS
        ):
            position += 3
            continue
        if shell_token.is_operator and token in REDIRECTION_OPERATORS:
            position += 2
            continue

        if _executable_name(token) not in {"gh", "gh.exe"}:
            return None
        if [item.value for item in segment[position + 1 : position + 3]] != ["auth", "status"]:
            return None
        return _arguments_without_redirections(segment[position + 3 :])
    return None


def _option_values(arguments: Sequence[str], option_names: set[str]) -> list[str | None]:
    """Collect explicit values for options in split or equals form."""

    values: list[str | None] = []
    for index, argument in enumerate(arguments):
        if argument == "--":
            break
        if argument in option_names:
            values.append(arguments[index + 1] if index + 1 < len(arguments) else None)
            continue
        for option in option_names:
            prefix = f"{option}="
            if argument.startswith(prefix):
                values.append(argument[len(prefix) :])
                break
    return values


def _requests_scoped_json(arguments: Sequence[str]) -> bool:
    """Require one unambiguous github.com selector and one hosts JSON field."""

    host_values = _option_values(arguments, {"-h", "--hostname"})
    json_values = _option_values(arguments, {"--json"})
    return host_values == ["github.com"] and json_values == ["hosts"]


def _is_unscoped_status_command(command: str) -> bool:
    """Identify direct human-readable gh auth status calls in shell segments."""

    tokens = _tokenize_command(command)
    if tokens is None:
        return False
    for segment in _command_segments(tokens):
        arguments = _status_arguments(segment)
        if arguments is not None and not _requests_scoped_json(arguments):
            return True
    return False


def _deny_response() -> dict[str, object]:
    """Return Codex's supported PreToolUse denial response."""

    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": DENIAL_REASON,
        }
    }


def main() -> int:
    """Read one Codex hook event and deny unscoped authentication status calls."""

    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return 0

    if not isinstance(event, dict):
        return 0
    if event.get("hook_event_name") != "PreToolUse" or event.get("tool_name") != "Bash":
        return 0

    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0
    command = tool_input.get("command")
    if not isinstance(command, str) or not _is_unscoped_status_command(command):
        return 0

    json.dump(_deny_response(), sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
