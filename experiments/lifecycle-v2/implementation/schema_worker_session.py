"""Bounded, owned schema transport and report persistence for the Git adapter runner."""

import hashlib
import json
import queue
import subprocess
import threading
from pathlib import Path

from common import Denied, ROOT, canonical, parse_json


def pinned_command(command, executable, expected_sha256):
    """Bind the explicit schema alias to one image and refuse any other executable."""
    selected = Path(executable).resolve(strict=True)
    if hashlib.sha256(selected.read_bytes()).hexdigest() != expected_sha256:
        raise Denied("Pinned PowerShell image changed")
    if not command or (command[0] != "pwsh.exe" and Path(command[0]).resolve() != selected):
        raise Denied("Schema executable mismatch")
    return [str(selected), *command[1:]]


class SchemaSession:
    """Own one bounded protocol process; transport failure never becomes schema success."""

    def __init__(self, command, output, response_timeout=20, shutdown_timeout=2):
        """Start only the supplied local worker and record its exact invocation."""
        self.output = Path(output)
        self.response_timeout, self.shutdown_timeout = response_timeout, shutdown_timeout
        self.failed, self.pending = False, None
        self.errors = (self.output / "schema.stderr.txt").open("xb")
        self.replies = (self.output / "schema.stdout.txt").open("xb")
        self.metadata = {}
        (self.output / "schema-command.json").write_text(json.dumps({"argv": command, "cwd": str(ROOT)}, indent=2) + "\n", encoding="utf-8")
        try:
            self.process = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.errors)
        except BaseException:
            self.errors.close()
            self.replies.close()
            raise

    def exchange(self, raw=None):
        """Bound both pipe write and newline read; preserve only protocol replies."""
        if self.failed or (self.pending is not None and self.pending.is_alive()):
            raise Denied("Schema transport is fail-closed")
        if raw is not None and len(raw) > 1048576:
            self.failed = True
            raise Denied("Schema request exceeds bound")
        completed = queue.Queue(maxsize=1)

        def transfer():
            """Run blocking pipe operations off the controller's deadline path."""
            try:
                if raw is not None:
                    self.process.stdin.write(raw)
                    self.process.stdin.flush()
                reply = self.process.stdout.readline(1048577)
                completed.put((reply, None))
            except BaseException as error:
                completed.put((None, error))

        self.pending = threading.Thread(target=transfer, daemon=True)
        self.pending.start()
        try:
            reply, error = completed.get(timeout=self.response_timeout)
            if error is not None:
                raise Denied("Schema pipe failed: " + type(error).__name__)
            if not reply or len(reply) > 1048576 or not reply.endswith(b"\n"):
                raise Denied("Schema response missing or oversized")
            self.pending.join(timeout=self.shutdown_timeout)
            self.replies.write(reply)
            self.replies.flush()
            return reply
        except queue.Empty as error:
            self.failed = True
            raise TimeoutError("Schema response deadline exceeded") from error
        except BaseException:
            self.failed = True
            raise

    def start(self):
        """Require full metaschema and UTF-8 readiness from the same owned worker."""
        self.metadata = parse_json(self.exchange())
        if not all(self.metadata.get(key) is True for key in ("ready", "metaschema", "format_assertion", "explicit_metaschema")):
            self.failed = True
            raise Denied("Full schema initialization failed")
        if self.metadata.get("input_codepage") != 65001 or self.metadata.get("output_codepage") != 65001:
            self.failed = True
            raise Denied("Schema transport is not UTF-8")
        return self.metadata

    def validate(self, event):
        """Require a boolean schema verdict; malformed replies are harness failures."""
        response = parse_json(self.exchange(canonical(event).encode("utf-8") + b"\n"))
        if type(response.get("valid")) is not bool:
            self.failed = True
            raise Denied("Invalid schema verdict")
        return response["valid"]

    def close(self):
        """Reap only this owned process with finite waits and explicit shutdown failures."""
        errors = []
        try:
            if self.pending is not None and self.pending.is_alive():
                self.process.terminate()
            else:
                self.process.stdin.close()
            self.process.wait(timeout=self.shutdown_timeout)
        except Exception as error:
            errors.append(type(error).__name__)
            try:
                self.process.kill()
                self.process.wait(timeout=self.shutdown_timeout)
            except Exception as final_error:
                errors.append(type(final_error).__name__)
        if self.pending is not None:
            self.pending.join(timeout=self.shutdown_timeout)
        thread_alive = self.pending is not None and self.pending.is_alive()
        if thread_alive:
            errors.append("TransportThreadUnresolved")
        else:
            for stream in (self.process.stdin, self.process.stdout):
                try:
                    stream.close()
                except Exception as error:
                    errors.append(type(error).__name__)
        for stream in (self.errors, self.replies):
            try:
                stream.close()
            except Exception as error:
                errors.append(type(error).__name__)
        return {"exit_code": self.process.poll(), "errors": errors,
                "transport_failed": self.failed, "thread_alive": thread_alive}


def persist_report(output, report, worker):
    """Persist failure evidence even when worker shutdown raises; never promote it to PASS."""
    try:
        if worker is not None:
            cleanup = worker.close()
            report["schema_cleanup"] = cleanup
            report["schema_exit_code"] = cleanup["exit_code"]
            if cleanup["errors"] or cleanup["transport_failed"] or cleanup["exit_code"] != 0:
                report["success"] = False
    except BaseException as error:
        report.update(success=False, cleanup_exception=type(error).__name__)
        try:
            if worker is not None and hasattr(worker, "process"):
                worker.process.kill()
                worker.process.wait(timeout=2)
        except Exception as recovery_error:
            report["cleanup_recovery_exception"] = type(recovery_error).__name__
    finally:
        (Path(output) / "regression-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report
