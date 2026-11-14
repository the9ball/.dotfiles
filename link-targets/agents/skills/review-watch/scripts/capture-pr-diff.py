"""Capture and validate a GitHub PR diff bound to immutable commit identities."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

MAGIC = b"# review-watch snapshot v1\n"
API_VERSION = "2022-11-28"
SHA = re.compile(r"[0-9a-f]{40}\Z")
REPOSITORY = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")


class SnapshotError(Exception):
    """Indicate a sanitized capture or verification failure."""


def require(condition, message):
    """Reject invalid input without including untrusted response content."""
    if not condition:
        raise SnapshotError(message)


def run_process(arguments, input=None):
    """Run an explicit executable with binary pipes and no shell."""
    return subprocess.run(arguments, input=input, capture_output=True, check=False)


def validate_identity(repo, number, base=None, head=None):
    """Validate route components and optional immutable commit identities."""
    require(isinstance(repo, str) and REPOSITORY.fullmatch(repo), "invalid repository")
    require(all(part not in (".", "..") for part in repo.split("/")), "invalid repository")
    require(type(number) is int and number > 0, "invalid PR number")
    for commit in (base, head):
        require(commit is None or isinstance(commit, str) and SHA.fullmatch(commit),
                "invalid commit identity")


def api_get(endpoint, media, gh, runner):
    """Fetch one official API response and validate its HTTP envelope."""
    result = runner([gh, "api", "--hostname", "github.com", "--include",
                     "-H", "Accept: " + media, "-H",
                     "X-GitHub-Api-Version: " + API_VERSION, endpoint])
    require(result.returncode == 0, "GitHub API request failed")
    response = result.stdout
    require(isinstance(response, bytes), "invalid API byte response")
    separator = b"\r\n\r\n" if b"\r\n\r\n" in response else b"\n\n"
    header, found, body = response.partition(separator)
    require(found and len(header) <= 65536, "invalid HTTP envelope")
    lines = header.splitlines()
    require(lines and re.fullmatch(rb"HTTP/\S+ 200(?: .*)?", lines[0]), "unexpected HTTP status")
    headers = {}
    for line in lines[1:]:
        name, delimiter, value = line.partition(b":")
        require(delimiter and name.lower() not in headers, "invalid HTTP headers")
        headers[name.lower()] = value.strip().lower()
    content_type = headers.get(b"content-type", b"").split(b";", 1)[0]
    allowed = {b"application/json", b"application/vnd.github+json"} if media.endswith("+json") else {
        b"application/vnd.github.diff", b"application/vnd.github.v3.diff"}
    require(content_type in allowed, "unexpected HTTP media type")
    if b"content-length" in headers:
        require(headers[b"content-length"].isdigit() and
                int(headers[b"content-length"]) == len(body), "HTTP length mismatch")
    if media.endswith("+json"):
        try:
            return json.loads(body)
        except (ValueError, UnicodeError):
            raise SnapshotError("invalid API JSON") from None
    return body


def inventory(files):
    """Normalize complete compare file metadata, rejecting ambiguous inventories."""
    require(isinstance(files, list) and len(files) < 300, "incomplete file inventory")
    normalized = []
    names = set()
    for item in files:
        require(isinstance(item, dict), "invalid file inventory")
        name = item.get("filename")
        additions, deletions = item.get("additions"), item.get("deletions")
        require(isinstance(name, str) and name and "\x00" not in name and name not in names,
                "invalid file inventory")
        require(type(additions) is int and additions >= 0 and
                type(deletions) is int and deletions >= 0, "invalid file counts")
        names.add(name)
        normalized.append({"filename": name, "additions": additions, "deletions": deletions})
    return normalized


def validate_payload(payload, files, git, runner):
    """Parse diff read-only and bind every destination and text count to inventory."""
    require(isinstance(payload, bytes) and (not payload or payload.startswith(b"diff --git ")),
            "invalid diff payload")
    result = runner([git, "--no-optional-locks", "apply", "--numstat", "-z",
                     "--allow-empty", "-"], input=payload)
    require(result.returncode == 0, "invalid or truncated diff")
    tokens = result.stdout.split(b"\x00")
    require(tokens.pop() == b"", "invalid diff statistics")
    actual = {}
    binary = []
    while tokens:
        fields = tokens.pop(0).split(b"\t", 2)
        require(len(fields) == 3, "invalid diff statistics")
        added, deleted, name = fields
        if not name:
            require(len(tokens) >= 2, "invalid rename statistics")
            tokens.pop(0)
            name = tokens.pop(0)
        try:
            name = name.decode("utf-8", "strict")
        except UnicodeError:
            raise SnapshotError("unsupported filename encoding") from None
        require(name and name not in actual, "duplicate diff destination")
        if added == deleted == b"-":
            actual[name] = None
            binary.append(name)
        else:
            require(added.isdigit() and deleted.isdigit(), "invalid diff statistics")
            actual[name] = (int(added), int(deleted))
    expected = {item["filename"]: (item["additions"], item["deletions"]) for item in files}
    require(actual.keys() == expected.keys(), "diff inventory mismatch")
    for name, counts in actual.items():
        require(counts == expected[name] if counts is not None else expected[name] == (0, 0),
                "diff count mismatch")
    return sorted(binary)


def decode_artifact(data):
    """Read a bounded versioned metadata header and preserve payload bytes exactly."""
    require(data.startswith(MAGIC), "missing snapshot header")
    end = data.find(b"\n\n", len(MAGIC))
    require(0 <= end <= 1048576, "invalid snapshot header")
    try:
        metadata = json.loads(data[len(MAGIC):end])
    except (ValueError, UnicodeError):
        raise SnapshotError("invalid snapshot metadata") from None
    require(isinstance(metadata, dict), "invalid snapshot metadata")
    return metadata, data[end + 2:]


def verify_bytes(data, repo, number, base, head, git="git", runner=run_process):
    """Validate identity, digest, schema and inventory of an acquired artifact."""
    validate_identity(repo, number, base, head)
    require(base is not None and head is not None, "missing commit identity")
    metadata, payload = decode_artifact(data)
    require(metadata.get("schema") == 1 and type(metadata.get("schema")) is int,
            "unsupported snapshot schema")
    require(all(metadata.get(key) == value for key, value in
                {"repo": repo, "number": number, "base": base, "head": head}.items())
            and type(metadata.get("number")) is int, "snapshot identity mismatch")
    require(isinstance(metadata.get("merge_base"), str) and SHA.fullmatch(metadata["merge_base"]),
            "invalid merge base")
    require(metadata.get("definition") == "merge-base-to-head" and
            metadata.get("api_version") == API_VERSION and
            metadata.get("endpoint") == f"repos/{repo}/compare/{base}...{head}",
            "snapshot endpoint mismatch")
    require(type(metadata.get("payload_bytes")) is int and metadata["payload_bytes"] == len(payload)
            and metadata.get("payload_sha256") == hashlib.sha256(payload).hexdigest(),
            "snapshot payload mismatch")
    files = inventory(metadata.get("files"))
    require(files == metadata["files"], "invalid normalized inventory")
    binary = validate_payload(payload, files, git, runner)
    require(metadata.get("binary_unreviewed") == binary, "binary coverage mismatch")
    return metadata


def capture(repo, number, output, gh="gh", git="git", runner=run_process):
    """Acquire a frozen tuple and atomically publish only a fully validated artifact."""
    validate_identity(repo, number)
    output = Path(output)
    require(output.is_absolute() and output.suffix == ".diff" and output.parent.is_dir(),
            "output requires an existing parent and absolute .diff path")
    if output.exists():
        old = output.read_bytes()
        if old.startswith(MAGIC):
            try:
                previous, _ = decode_artifact(old)
                validate_identity(previous.get("repo"), previous.get("number"))
            except SnapshotError:
                previous = None
            if previous is not None:
                require(previous["repo"] == repo and previous["number"] == number,
                        "cache identity collision")
    pull = api_get(f"repos/{repo}/pulls/{number}", "application/vnd.github+json", gh, runner)
    try:
        require(type(pull["number"]) is int and pull["number"] == number and
                pull["base"]["repo"]["full_name"] == repo,
                "PR identity mismatch")
        base, head = pull["base"]["sha"], pull["head"]["sha"]
        validate_identity(repo, number, base, head)
        require(base is not None and head is not None, "missing commit identity")
        endpoint = f"repos/{repo}/compare/{base}...{head}"
        comparison = api_get(endpoint, "application/vnd.github+json", gh, runner)
        commit = api_get(f"repos/{repo}/commits/{head}", "application/vnd.github+json", gh, runner)
        require(comparison["base_commit"]["sha"] == base and commit["sha"] == head,
                "commit identity mismatch")
        merge_base = comparison["merge_base_commit"]["sha"]
        require(isinstance(merge_base, str) and SHA.fullmatch(merge_base), "invalid merge base")
        files = inventory(comparison["files"])
    except (KeyError, TypeError):
        raise SnapshotError("malformed API identity metadata") from None
    payload = api_get(endpoint, "application/vnd.github.diff", gh, runner)
    metadata = {"schema": 1, "repo": repo, "number": number, "base": base, "head": head,
                "merge_base": merge_base, "definition": "merge-base-to-head",
                "endpoint": endpoint, "api_version": API_VERSION, "files": files,
                "payload_bytes": len(payload), "payload_sha256": hashlib.sha256(payload).hexdigest(),
                "binary_unreviewed": validate_payload(payload, files, git, runner)}
    artifact = MAGIC + json.dumps(metadata, sort_keys=True).encode("utf-8") + b"\n\n" + payload
    verify_bytes(artifact, repo, number, base, head, git, runner)
    partial = None
    published = False
    try:
        descriptor, partial = tempfile.mkstemp(prefix=output.name + ".", suffix=".partial", dir=output.parent)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(artifact)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(partial, output)
        published = True
        return verify_bytes(output.read_bytes(), repo, number, base, head, git, runner)
    except (OSError, SnapshotError):
        raise SnapshotError("published artifact unusable or unknown" if published else
                            "publication failed; previous artifact preserved") from None
    finally:
        if partial is not None and not published:
            Path(partial).unlink(missing_ok=True)


def main():
    """Dispatch capture or offline verification and print sanitized metadata only."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("capture", "verify"):
        command = commands.add_parser(name)
        command.add_argument("--repo", required=True)
        command.add_argument("--number", required=True, type=int)
        command.add_argument("--git", default="git")
        if name == "capture":
            command.add_argument("--output", required=True)
            command.add_argument("--gh", default="gh")
        else:
            command.add_argument("--input", required=True)
            command.add_argument("--base", required=True)
            command.add_argument("--head", required=True)
    arguments = parser.parse_args()
    try:
        if arguments.command == "capture":
            metadata = capture(arguments.repo, arguments.number, arguments.output, arguments.gh, arguments.git)
        else:
            metadata = verify_bytes(Path(arguments.input).read_bytes(), arguments.repo, arguments.number,
                                    arguments.base, arguments.head, arguments.git)
        print(json.dumps(metadata, sort_keys=True))
        return 0
    except SnapshotError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 1
    except (OSError, ValueError):
        print(json.dumps({"error": "snapshot capture or verification failed"}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
