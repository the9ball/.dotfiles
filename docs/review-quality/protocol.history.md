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

During F2 recovery, a byte-hash assertion compared the Windows CRLF input file to
the canonical LF prompt hash. The assertion correctly stopped recovery, but the
shell continued to the next command and accidentally restarted the controller.
One B/F2 duplicate completed (0.068340 USD estimate). Root stopped only the owned
controller, preserved the original B/F2 answer as primary, and isolated the
duplicate in `diagnostics/`; findings from the duplicate are excluded regardless
of their content. An already-started C1/F2 child completed naturally and is
retained from its explicit `turn.completed` event and valid complete answer.
Its exit code was not captured and its time is reconstructed from raw-file
timestamps. Both timestamp limitations remain in the receipts. This procedural
deviation and extra cache exposure limit cost/order interpretation.

The prompt hashes in the original manifest identify canonical LF text, not the
CRLF-translated Windows stdin bytes. All processes used the same translation;
universal-newline decoding of the retained input file verified exact canonical
identity. No reviewer prompt was changed during recovery. Any future claim about
wire-byte hashes must make this distinction. The extra paid duplicate counts
against the global model-launch budget and is disclosed separately from the
primary B/C reviewer ratio.

Claude's first correctly resolved process returned an expired OAuth error, zero
usage and zero CLI-estimated cost. It is recorded separately from the two aqua
wrapper diagnostics. No automatic authentication refresh or alternate account
was attempted. The authentication failure consumes one additional diagnostic
process attempt beyond the premeasurement wrapper count; it does not consume a
model-backed reviewer trial. Any further Claude run depends on user-reported
authentication recovery. No model-backed reviewer is silently replaced.
