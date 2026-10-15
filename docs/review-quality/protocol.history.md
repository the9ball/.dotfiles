# Pilot protocol and harness correction history

## 2026-10-15: admission formatting and interruption recovery

The preregistered source, truth and all reviewer prompts were fixed at `2464f41`.
After Codex A/F1/R1 and B/F1/R1 completed, B's coverage entry included a file name,
line range and candidate identity. The original exact-string admission guard
rejected it even though its declared file coverage was complete. Root inspected
only coverage, usage and session metadata, verified the full declaration and
its pinned candidate, and retained the original observation without rerunning it.
The rejection record remains available. This is an admission correction, not a
new reviewer answer or a repaired candidate.

The next harness revision accepts either the exact expected file name or that
same name followed by a colon and reviewer-provided line details; unknown or
missing files still fail. Explicit `--resume` skips only existing observations
whose prompt hashes and declared coverage still match. The runner and manifest
identities advance; all fixture and prompt hashes remain byte-identical. The
original source remains recoverable from Git. Final independent review must
verify this preservation rather than claim its earlier design verdict covers
the changed runner. No fourth design checkpoint is requested.

A subsequent B/F2/R1 answer represented the same declaration as an object with
`file`, `scope` and `identity`. Its source coverage and candidate identity were
also complete. The parser now accepts explicit `file`/`path` objects as well as
strings; unrecognized shapes and unknown/missing files still stop. No prompt or
finding was changed and this original observation was also retained. Its exact
process duration had not been persisted before the parser exception: the receipt
labels its duration as reconstructed from raw-output creation/last-write times,
not an exact subprocess measurement. Subsequent invocations save execution
timings before parsing, avoiding that loss. These are two output-representation
corrections, not model retries or fixture tuning after seeing detection results.

Claude's first correctly resolved process returned an expired OAuth error, zero
usage and zero CLI-estimated cost. It is recorded separately from the two aqua
wrapper diagnostics. No automatic authentication refresh or alternate account
was attempted. The authentication failure consumes one additional diagnostic
process attempt beyond the premeasurement wrapper count; it does not consume a
model-backed reviewer trial. Any further Claude run depends on user-reported
authentication recovery. No model-backed reviewer is silently replaced.
