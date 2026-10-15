"""Run the preregistered frozen-change experiment without loading evaluator truth."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


DIRECTORY = Path(__file__).resolve().parent
REPOSITORY = DIRECTORY.parent.parent
CHECKLIST = REPOSITORY / "link-targets/agents/skills/code-review/checklist.md"
SPECIFICATION = importlib.util.spec_from_file_location(
    "prior_review_transport", DIRECTORY.parent / "review-quality/run.py"
)
TRANSPORT = importlib.util.module_from_spec(SPECIFICATION)
SPECIFICATION.loader.exec_module(TRANSPORT)


def digest(content):
    """Identify raw bytes or canonical UTF-8 text with SHA-256."""
    if isinstance(content, str):
        content = content.encode("utf-8")
    return hashlib.sha256(content).hexdigest()


def read_json(path):
    """Load a complete JSON value without interpreting text-search matches."""
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    """Write a readable portable UTF-8 artifact with LF and a final newline."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8", newline="\n",
    )


def make_prompt(stage):
    """Construct a reviewer request exclusively from public frozen evidence."""
    public_evidence = (DIRECTORY / "artifacts/evidence.json").read_text(encoding="utf-8")
    free_task = "Review the entire change freely for concrete defects and quality problems."
    if stage == "free":
        instruction = free_task + "\n" + TRANSPORT.FREE_OUTPUT_INSTRUCTION
    else:
        checklist_text = CHECKLIST.read_text(encoding="utf-8")
        if stage == "combined":
            instruction = (
                "Checklist available from the start:\n<checklist>\n"
                + checklist_text + "\n</checklist>\n" + free_task
                + " Also perform every checklist check in this same context. Report both sections."
            )
        else:
            instruction = (
                "Evaluate only the following checklist against the entire change. Do not restart "
                "unrestricted review. Report out-of-scope material observations in limitations "
                "with their cause, trigger and impact for routing.\n<checklist>\n"
                + checklist_text + "\n</checklist>"
            )
        instruction += "\n" + TRANSPORT.OUTPUT_INSTRUCTION
    return instruction + "\nFrozen evidence:\n" + public_evidence


def prepare():
    """Pin controller, transport, public inputs, settings and canonical prompts."""
    manifest_path = DIRECTORY / "manifest.json"
    if manifest_path.exists():
        raise RuntimeError("Refusing to replace a frozen manifest")
    public = read_json(DIRECTORY / "artifacts/evidence.json")
    manifest = {
        "series": "reservation-20261015-v1",
        "controller_sha256": digest(Path(__file__).read_bytes()),
        "transport_sha256": digest(Path(TRANSPORT.__file__).read_bytes()),
        "evidence_sha256": digest((DIRECTORY / "artifacts/evidence.json").read_bytes()),
        "checklist_sha256": digest(CHECKLIST.read_bytes()),
        "codex_settings": list(TRANSPORT.resolve_codex_settings()),
        "claude_settings": "unchanged host defaults; no override",
        "base_sha": public["base_sha"], "candidate_sha": public["candidate_sha"],
        "changed_files": public["changed_files"],
        "prompts": {}, "reviewer_launch_cap": 20, "estimated_usd_ceiling": 12,
        "per_next_call_reservation_usd": 0.75,
        "effective_settings_attestation": "Codex backend model/effort and Claude effort unavailable",
    }
    if manifest["codex_settings"][0] != "gpt-6.1-sol":
        raise RuntimeError("Configured model does not match the retained price calculation")
    for stage in ("free", "combined", "checklist"):
        prompt = make_prompt(stage)
        (DIRECTORY / (stage + ".prompt.txt")).write_text(prompt, encoding="utf-8", newline="\n")
        manifest["prompts"][stage] = digest(prompt)
    write_json(manifest_path, manifest)
    print(json.dumps({"prepared": manifest["series"], "settings": manifest["codex_settings"]}))


def validate_manifest():
    """Reject changed public evidence, configuration, transport or controller."""
    manifest = read_json(DIRECTORY / "manifest.json")
    pairs = (
        ("controller_sha256", Path(__file__)),
        ("transport_sha256", Path(TRANSPORT.__file__)),
        ("evidence_sha256", DIRECTORY / "artifacts/evidence.json"),
        ("checklist_sha256", CHECKLIST),
    )
    for key, path in pairs:
        if digest(path.read_bytes()) != manifest[key]:
            raise RuntimeError("Frozen input changed: " + key)
    if list(TRANSPORT.resolve_codex_settings()) != manifest["codex_settings"]:
        raise RuntimeError("Codex configured settings changed")
    for stage, identity in manifest["prompts"].items():
        if digest(make_prompt(stage)) != identity:
            raise RuntimeError("Prompt identity changed")
    return manifest


def invoke(host, label, stage, manifest):
    """Start one independent reviewer and retain its complete audited response."""
    receipt_directory = DIRECTORY / "receipts"
    receipt_directory.mkdir(exist_ok=True)
    completed_path = receipt_directory / (label + ".json")
    if completed_path.exists():
        raise RuntimeError("Refusing to rerun an existing observation")
    attempts = list(receipt_directory.glob("*.execution.json"))
    admitted = [read_json(path) for path in receipt_directory.glob("*.json")
                if not path.name.endswith((".execution.json", ".failure.json", ".events.json"))]
    if len(attempts) >= manifest["reviewer_launch_cap"]:
        raise RuntimeError("Launch allowance exhausted")
    spent = sum(receipt["estimated_usd"] for receipt in admitted)
    if spent + manifest["per_next_call_reservation_usd"] > manifest["estimated_usd_ceiling"]:
        raise RuntimeError("Reviewer estimate allowance exhausted")
    prompt = make_prompt(stage)
    temporary_directory = Path(tempfile.mkdtemp(prefix="issue138-probe-reservation-"))
    input_path = temporary_directory / "input.txt"
    output_path = temporary_directory / "output.jsonl"
    error_path = temporary_directory / "stderr.txt"
    input_path.write_text(prompt, encoding="utf-8", newline="\n")
    if host == "codex":
        model, effort = manifest["codex_settings"]
        arguments = [
            shutil.which("codex.exe"), "exec", "--json", "--ephemeral",
            "--approve-for-me", "--skip-git-repo-check", "--ignore-user-config",
            "--model", model, "-c", "model_reasoning_effort=" + effort,
            "-c", "project_doc_max_bytes=0", "-",
        ]
    else:
        arguments = [
            shutil.which("claude.exe"), "--safe-mode", "--no-session-persistence",
            "--permission-mode", "plan", "--permission-prompts", "none",
            "--disallowedTools", "*", "--max-budget-usd", "0.75",
            "--output-format", "stream-json", "--verbose", "--print",
        ]
    started = time.time()
    with input_path.open("rb") as input_file, output_path.open("wb") as output_file, error_path.open("wb") as error_file:
        process = subprocess.Popen(
            arguments, cwd=temporary_directory, stdin=input_file,
            stdout=output_file, stderr=error_file,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        exit_code = process.wait()
    execution = {
        "label": label, "host": host, "stage": stage,
        "cli_exit": exit_code, "started_unix": started,
        "finished_unix": time.time(), "elapsed_seconds": time.time() - started,
        "input_sha256": digest(prompt), "stdin_sha256": digest(input_path.read_bytes()),
        "raw_output_sha256": digest(output_path.read_bytes()),
        "arguments": arguments[1:],
    }
    write_json(receipt_directory / (label + ".execution.json"), execution)
    try:
        if exit_code:
            raise RuntimeError("CLI failed; raw receipt retained privately: " + str(temporary_directory))
        receipt = TRANSPORT.parse_receipt(host, output_path.read_text(encoding="utf-8-sig"))
        TRANSPORT.verify_coverage(receipt["result"]["coverage"], manifest["changed_files"])
        if receipt["session_id"] in {item["session_id"] for item in admitted}:
            raise RuntimeError("Reused session identity")
        if host == "claude":
            observed_models = receipt["effective_model"]
            prior_models = {tuple(item["effective_model"]) for item in admitted if item["host"] == host}
            if len(observed_models) != 1 or (prior_models and tuple(observed_models) not in prior_models):
                raise RuntimeError("Claude effective model changed or missing")
        receipt.update(execution)
        receipt["configured_model"] = manifest["codex_settings"][0] if host == "codex" else "host default"
        receipt["configured_effort"] = manifest["codex_settings"][1] if host == "codex" else "host default"
        receipt["effective_effort"] = None
        receipt["measurement"] = "pilot" if "pilot" in label else "main"
        write_json(completed_path, receipt)
        # Preserve response and usage events; omit initialization paths and unrelated host metadata.
        events = [json.loads(line) for line in output_path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
        retained_events = [event for event in events if event.get("type") != "system"]
        write_json(receipt_directory / (label + ".events.json"), {"events": retained_events})
    except Exception as error:
        write_json(receipt_directory / (label + ".failure.json"), {
            **execution, "error": str(error), "admitted": False,
        })
        raise
    if temporary_directory.parent.resolve() != Path(tempfile.gettempdir()).resolve():
        raise RuntimeError("Unexpected temporary parent")
    for path in (input_path, output_path, error_path):
        path.unlink()
    temporary_directory.rmdir()
    print(json.dumps({"completed": label, "usd": receipt["estimated_usd"], "seconds": receipt["elapsed_seconds"]}), flush=True)


def run_interval(interval):
    """Execute exactly the selected preregistered interval without automatic retries."""
    manifest = validate_manifest()
    if interval == "pilot":
        schedule = [("codex", "pilot", ("A", "B", "C"))]
    else:
        admission = read_json(DIRECTORY / "pilot-admission.json")
        if not admission.get("admit_main") or admission["evidence_sha256"] != manifest["evidence_sha256"]:
            raise RuntimeError("Main measurement has no matching pilot admission")
        schedule = [
            ("codex", "R1", ("A", "B", "C")),
            ("claude", "R1", ("C", "B", "A")),
            ("claude", "R2", ("A", "B", "C")),
            ("codex", "R2", ("C", "B", "A")),
        ]
    for host, trial, arms in schedule:
        for arm in arms:
            stages = ("free",) if arm == "A" else ("combined",) if arm == "B" else ("free", "checklist")
            for stage in stages:
                validate_manifest()
                invoke(host, host + "-" + trial + "-" + arm + "-" + stage, stage, manifest)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("prepare", "pilot", "main"))
    arguments = parser.parse_args()
    if arguments.operation == "prepare":
        prepare()
    else:
        run_interval(arguments.operation)
