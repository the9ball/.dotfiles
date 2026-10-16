"""Reproduce an unseeded batching regression without changing frozen ground truth."""

from collections import deque
import json
from pathlib import Path


class CountingDeque(deque):
    """Count references traversed when queue snapshots are materialized."""

    def __init__(self):
        """Initialize an empty queue and an independent traversal counter."""
        super().__init__()
        self.references_yielded = 0

    def __iter__(self):
        """Count each deque element visited by a copying iteration."""
        for value in super().__iter__():
            self.references_yielded += 1
            yield value


class SuccessfulTransport:
    """Accept every batch so queue traversal, rather than failure, is measured."""

    def send(self, batch):
        """Accept a complete atomic batch without retaining queue references."""
        assert batch


def count_copy_traversals(source, count):
    """Run a successful flush and return copied-reference work for a fixed backlog."""
    namespace = {"__name__": "supplemental_fixture"}
    exec(compile(source, "dispatch.py", "exec"), namespace)
    namespace["deque"] = CountingDeque
    queue = namespace["NoticeQueue"](SuccessfulTransport(), batch_size=1)
    for position in range(count):
        queue.enqueue("recipient", str(position))
    assert queue.flush() == list(range(1, count + 1))
    assert not queue.pending
    return queue.pending.references_yielded


def main():
    """Verify linear baseline work and quadratic candidate work on unchanged sources."""
    directory = Path(__file__).resolve().parent
    fixtures = json.loads((directory / "fixtures.json").read_text(encoding="utf-8"))["fixtures"]
    fixture = next(fixture for fixture in fixtures if fixture["id"] == "F1")
    observations = []
    for count in (100, 200):
        baseline = count_copy_traversals(fixture["base_files"]["dispatch.py"], count)
        candidate = count_copy_traversals(fixture["candidate_files"]["dispatch.py"], count)
        assert baseline == count
        assert candidate == count * (count + 1) // 2
        observations.append({"queued_notices": count, "baseline_references_copied": baseline, "candidate_references_copied": candidate})
    print(json.dumps({
        "id": "EXTRA-F1-batching-work", "classification": "valid unseeded performance regression",
        "frozen_ground_truth_unchanged": True, "observations": observations,
        "measurement": "Deterministic reference-traversal counts, not elapsed-time benchmark",
    }, indent=2))


if __name__ == "__main__":
    main()
