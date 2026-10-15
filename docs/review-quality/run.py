"""Run a bounded, blinded review pilot using fresh Codex and Claude processes."""

import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import tomllib


DIRECTORY = Path(__file__).resolve().parent
REPOSITORY = DIRECTORY.parent.parent
CHECKLIST = REPOSITORY / "link-targets/agents/skills/code-review/checklist.md"
OUTPUT_INSTRUCTION = """
Return one JSON object, without Markdown fences, with these keys:
free_findings: array of findings from unrestricted review (empty when not requested).
checklist_findings: array of findings from the checklist (empty when not requested).
Each finding: id (local unique identifier), severity (P1/P2/P3), category
(material/quality/optional), location (file and line or symbol), cause, impact,
trigger (concrete failing condition), evidence. Deduplicate by underlying cause.
checklist_results: array (empty when not requested), each with id (stable checklist
ID only; do not reproduce its title/text), applicability (APPLICABLE,
NOT_APPLICABLE, UNVERIFIED), result (PASS/FINDING/NOT_APPLICABLE/UNVERIFIED),
reason (case-specific), evidence, finding_ids.
coverage: array of every inspected changed file. limitations: array.
Use the given requirements and repository evidence; distinguish mandatory fixes
from optional preferences. Do not infer missing requirements. Do not claim tests
were executed. All evidence is embedded; do not use tools, inspect files, spawn
agents, access external services, or modify anything. This is a single inspection
of a frozen change, not permission to advance a production workflow.
"""


def digest(content):
    """Return the SHA-256 identity of bytes or UTF-8 text."""
    if isinstance(content, str):
        content = content.encode("utf-8")
    return hashlib.sha256(content).hexdigest()


def write_json(path, value):
    """Persist a portable UTF-8 JSON artifact with stable indentation."""
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def frozen_evidence(fixture):
    """Materialize only allowed source, requirements, and complete change evidence."""
    base_files = fixture["base_files"]
    candidate_files = fixture["candidate_files"]
    evidence = {
        "requirements": fixture["requirements"],
        "base_identity": digest(json.dumps(base_files, sort_keys=True)),
        "candidate_identity": digest(json.dumps(candidate_files, sort_keys=True)),
        "comparison": "complete base-to-candidate diff; all text files mode 100644",
        "base_files": base_files,
        "candidate_files": candidate_files,
        "commits": fixture["commits"],
        "diff": "".join(
            line
            for name in sorted(set(base_files) | set(candidate_files))
            for line in difflib.unified_diff(
                base_files.get(name, "").splitlines(keepends=True),
                candidate_files.get(name, "").splitlines(keepends=True),
                fromfile="a/" + name,
                tofile="b/" + name,
            )
        ),
    }
    return json.dumps(evidence, ensure_ascii=False, indent=2)


def make_prompt(fixture, stage, checklist_text):
    """Build arm-specific inputs without exposing evaluator-only fixture metadata."""
    evidence = frozen_evidence(fixture)
    free_task = "Review the entire change freely for concrete defects and quality problems."
    if stage == "free":
        instruction = free_task
    elif stage == "combined":
        instruction = (
            "Checklist available from the start:\n<checklist>\n"
            + checklist_text
            + "\n</checklist>\n"
            + free_task
            + " Also perform every checklist check in this same context. Report both sections."
        )
    else:
        instruction = (
            "Evaluate only the following checklist against the entire change. Do not restart "
            "unrestricted review. Record out-of-scope evidence only as a routing limitation.\n"
            "<checklist>\n" + checklist_text + "\n</checklist>"
        )
    return instruction + "\n" + OUTPUT_INSTRUCTION + "\nFrozen evidence:\n" + evidence


def extract_object(text):
    """Parse a final JSON answer, tolerating a single surrounding Markdown fence."""
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()
    return json.loads(text)


def parse_receipt(host, content):
    """Extract final answer, session, tool audit, and usage from a CLI event stream."""
    events = [json.loads(line) for line in content.splitlines() if line.strip()]
    tools = []
    if host == "codex":
        final_messages = []
        usage = None
        session = None
        for event in events:
            if event["type"] == "thread.started":
                session = event["thread_id"]
            if event["type"] == "turn.completed":
                usage = event["usage"]
            if event["type"] in ("turn.failed", "error"):
                raise RuntimeError("Codex returned a failed event")
            item = event.get("item", {})
            if event["type"] == "item.completed" and item.get("type") == "agent_message":
                final_messages.append(item["text"])
            if item and item.get("type") not in ("agent_message", "reasoning"):
                tools.append(item.get("type"))
        if not usage or not final_messages or not session:
            raise RuntimeError("Incomplete Codex receipt")
        result = extract_object(final_messages[-1])
        cached = usage.get("cached_input_tokens", 0)
        estimate = (
            (usage["input_tokens"] - cached) * 2
            + cached * 0.1
            + usage["output_tokens"] * 10
        ) / 1_000_000
        model_usage = None
        effective_model = None
    else:
        completed = [event for event in events if event.get("type") == "result"]
        if len(completed) != 1 or completed[0].get("is_error"):
            raise RuntimeError("Incomplete or failed Claude receipt")
        receipt = completed[0]
        usage = receipt["usage"]
        model_usage = receipt.get("modelUsage", {})
        effective_model = list(model_usage)
        session = receipt["session_id"]
        result = extract_object(receipt["result"])
        estimate = receipt["total_cost_usd"]
        for event in events:
            for block in event.get("message", {}).get("content", []):
                if isinstance(block, dict) and block.get("type") == "tool_use":
                    tools.append(block.get("name"))
    for key in ("free_findings", "checklist_findings", "checklist_results", "coverage", "limitations"):
        if not isinstance(result.get(key), list):
            raise RuntimeError("Missing or invalid response field: " + key)
    if tools:
        raise RuntimeError("Forbidden tool invocation: " + repr(tools))
    return {
        "session_id": session, "usage": usage, "model_usage": model_usage,
        "effective_model": effective_model, "estimated_usd": estimate,
        "tool_calls": tools, "result": result,
    }


def resolve_codex_settings():
    """Carry the externally configured Codex model and effort into isolated calls."""
    codex_home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
    configuration = tomllib.loads((codex_home / "config.toml").read_text(encoding="utf-8-sig"))
    return configuration["model"], configuration["model_reasoning_effort"]


def invoke(host, label, prompt, output_directory, settings):
    """Run one fresh reviewer with file-based input and a private raw receipt."""
    private_directory = Path(tempfile.mkdtemp(prefix="issue138-probe-quality-"))
    input_path = private_directory / "input.txt"
    output_path = private_directory / "output.jsonl"
    error_path = private_directory / "stderr.txt"
    input_path.write_text(prompt, encoding="utf-8")
    if host == "codex":
        model, effort = settings
        arguments = [
            shutil.which("codex"), "exec", "--json", "--ephemeral", "--approve-for-me",
            "--skip-git-repo-check", "--ignore-user-config", "--model", model,
            "-c", "model_reasoning_effort=" + effort,
            "-c", "project_doc_max_bytes=0", "-",
        ]
    else:
        arguments = [
            shutil.which("claude"), "--safe-mode", "--no-session-persistence",
            "--permission-mode", "plan", "--permission-prompts", "none",
            "--disallowedTools", "*", "--max-budget-usd", "0.40",
            "--output-format", "stream-json", "--verbose", "--print",
        ]
    started = time.time()
    with input_path.open("rb") as input_file, output_path.open("wb") as output_file, error_path.open("wb") as error_file:
        process = subprocess.Popen(
            arguments, stdin=input_file, stdout=output_file, stderr=error_file,
            cwd=private_directory, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        exit_code = process.wait()
    elapsed = time.time() - started
    if exit_code:
        write_json(output_directory / (label + ".failure.json"), {
            "label": label, "host": host, "cli_exit": exit_code,
            "elapsed_seconds": elapsed, "input_sha256": digest(prompt),
            "raw_output_sha256": digest(output_path.read_bytes()),
            "status": "failed_not_admitted", "retained_private_receipt": True,
        })
        raise RuntimeError(f"{label}: exit {exit_code}; inspect private receipt {private_directory}")
    content = output_path.read_text(encoding="utf-8-sig")
    try:
        receipt = parse_receipt(host, content)
    except (ValueError, KeyError, RuntimeError) as error:
        write_json(output_directory / (label + ".failure.json"), {
            "label": label, "host": host, "cli_exit": exit_code,
            "elapsed_seconds": elapsed, "input_sha256": digest(prompt),
            "raw_output_sha256": digest(output_path.read_bytes()),
            "status": "invalid_not_admitted", "error": str(error),
            "retained_private_receipt": True,
        })
        raise
    receipt.update({
        "label": label, "host": host, "cli_exit": exit_code,
        "started_unix": started, "elapsed_seconds": elapsed,
        "input_sha256": digest(prompt), "raw_output_sha256": digest(output_path.read_bytes()),
        "configured_model": settings[0] if host == "codex" else "host default (no override)",
        "configured_effort": settings[1] if host == "codex" else "host default (no override)",
        "effective_effort": None,
    })
    write_json(output_directory / (label + ".json"), receipt)
    # The only private directory removed is the just-created invocation directory.
    if private_directory.parent.resolve() != Path(tempfile.gettempdir()).resolve():
        raise RuntimeError("Unexpected temporary directory parent")
    for path in (input_path, output_path, error_path):
        path.unlink()
    private_directory.rmdir()
    return receipt


def prepare():
    """Freeze public evidence and identities without printing the checklist body."""
    fixtures = json.loads((DIRECTORY / "fixtures.json").read_text(encoding="utf-8"))["fixtures"]
    checklist_bytes = CHECKLIST.read_bytes()
    manifest = {
        "fixture_file_sha256": digest((DIRECTORY / "fixtures.json").read_bytes()),
        "checklist_sha256": digest(checklist_bytes),
        "runner_sha256": digest(Path(__file__).read_bytes()),
        "fixtures": [],
    }
    evidence_directory = DIRECTORY / "evidence"
    evidence_directory.mkdir(exist_ok=True)
    for fixture in fixtures:
        evidence = frozen_evidence(fixture)
        (evidence_directory / (fixture["id"] + ".json")).write_text(evidence + "\n", encoding="utf-8")
        manifest["fixtures"].append({
            "id": fixture["id"], "evidence_sha256": digest(evidence),
            "free_prompt_sha256": digest(make_prompt(fixture, "free", "")),
            "combined_prompt_sha256": digest(make_prompt(fixture, "combined", checklist_bytes.decode("utf-8"))),
            "checklist_prompt_sha256": digest(make_prompt(fixture, "checklist", checklist_bytes.decode("utf-8"))),
        })
    write_json(DIRECTORY / "manifest.json", manifest)
    print(json.dumps(manifest, indent=2))


def run(host, round_number):
    """Execute one counterbalanced round and stop before exceeding the host allowance."""
    manifest = json.loads((DIRECTORY / "manifest.json").read_text(encoding="utf-8"))
    fixture_bytes = (DIRECTORY / "fixtures.json").read_bytes()
    if digest(fixture_bytes) != manifest["fixture_file_sha256"]:
        raise RuntimeError("Fixture changed after preregistration")
    if digest(Path(__file__).read_bytes()) != manifest["runner_sha256"]:
        raise RuntimeError("Runner changed after preregistration")
    checklist_bytes = CHECKLIST.read_bytes()
    if digest(checklist_bytes) != manifest["checklist_sha256"]:
        raise RuntimeError("Checklist changed")
    fixtures = json.loads(fixture_bytes)["fixtures"]
    output_directory = DIRECTORY / "receipts"
    output_directory.mkdir(exist_ok=True)
    settings = resolve_codex_settings()
    if settings[0] != "gpt-6.1-sol":
        raise RuntimeError("Pricing has not been validated for configured model")
    previous = list(output_directory.glob(host + "-*.json"))
    spent = sum(json.loads(path.read_text(encoding="utf-8"))["estimated_usd"] for path in previous)
    calls = len(previous)
    if round_number == 2:
        fixtures.reverse()
    rotations = (["A", "B", "C"], ["B", "C", "A"], ["C", "A", "B"])
    for fixture_index, fixture in enumerate(fixtures):
        order = rotations[(fixture_index + round_number - 1 + (host == "claude")) % 3]
        for arm in order:
            stages = ["free"] if arm == "A" else ["combined"] if arm == "B" else ["free", "checklist"]
            for stage in stages:
                label = f"{host}-R{round_number}-{fixture['id']}-{arm}-{stage}"
                if (output_directory / (label + ".json")).exists():
                    raise RuntimeError("Refusing to overwrite or rerun a completed observation")
                if calls >= 32 or spent + 0.40 > 5.0:
                    raise RuntimeError("Preregistered per-host launch/cost allowance exhausted")
                receipt = invoke(host, label, make_prompt(fixture, stage, checklist_bytes.decode("utf-8")), output_directory, settings)
                spent += receipt["estimated_usd"]
                calls += 1
                if host == "claude" and receipt["effective_model"] != ["claude-opus-5-5"]:
                    raise RuntimeError("Unexpected effective Claude model; do not pool")
                print(json.dumps({"completed": label, "seconds": round(receipt["elapsed_seconds"], 2), "estimated_usd": receipt["estimated_usd"], "host_total_usd": spent}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("prepare", "run"))
    parser.add_argument("--host", choices=("codex", "claude"))
    parser.add_argument("--round", type=int, choices=(1, 2), default=1)
    arguments = parser.parse_args()
    if arguments.operation == "prepare":
        prepare()
    elif arguments.host:
        run(arguments.host, arguments.round)
    else:
        parser.error("run requires --host")
