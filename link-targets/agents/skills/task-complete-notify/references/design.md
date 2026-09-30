# Task-complete notification: design record

This document is a design record for mapping the current contract of `task-complete-notify` to the reason for its adoption.
The usage procedure and safety boundaries at runtime are based on the parent document [`SKILL.md`](../SKILL.md).

## Current invariants

- From the arm input, normalize the standalone UUID candidates and determine the target only when there is only one different candidate. Repetition of the same UUID is allowed.
- The canonical URI is `codex://threads/<UUID>`. Legacy formats and any extra path, query, or fragment are rejected.
- Relaxed UUID extraction is applied only to external arm input, and internal values of hooks, transcript metadata, state, and watchers are verified as exact matches using strict parser.
- Before arming, check `session_index.jsonl` of the Codex home selected by the current process and `session_meta` at the beginning of the active rollout of the same home. State is not created unless `id == session_id == target`, `thread_source == user`, and parentlessness are satisfied.
- Place the runtime state in `$CODEX_HOME\.task-complete-notify` which is resolved at runtime. Use `.codex` in the user profile only when `CODEX_HOME` is not set.
- `armedAtUtc` is the only expiration date standard recorded in the request when arming, and applies a fixed 24-hour TTL only to `armed`. Missing, invalid, and overflow cases are expired with fail closed, and related routes of arm, stop, and watcher lazily delete requests first, and checkpoints are post-processed with best-effort. Do not extend TTL at checkpoint side time.
- `attempting` is not subject to TTL cleaning and does not prevent Stop transmission/terminalization. Expired requests are not passed to the notification process, and if there is a lock conflict, the next scan will be retried.
- Cancel rereads the state of the specified thread in the order of coordination lock → per-thread lock, and deletes only `armed`, removing the request first and then the checkpoint. `attempting` does not delete it, returns `too_late`, returns `busy` if it is locked or the status is uncertain, returns `Ok=true, Status=not_armed` if it is absent, expired, or consumed, and does not create a terminal/tombstone. Cancel does not re-verify active ownership and is an operation for the generation at the time of execution.
- Make Stop hook the primary detector, JSONL watcher as an explicit fallback, and do not enable both as independent senders.
- JSONL watcher treats LF as a record commit boundary. An LF-terminated line that fails strict UTF-8/JSON parsing is permanently malformed under the append-only writer contract. Advance the cursor to `NextOffset` without retaining or outputting the malformed content. Leave only a trailing partial line without LF for the next scan. If evidence shows that the writer rewrites the same byte range after LF, reevaluate this policy and change the checkpoint schema.
- Stop hook is a synchronous call, but it is fixed to the hierarchy of thread lock 10 seconds + notifier child 35 seconds + post-processing margin 5 seconds < helper wrapper 55 seconds < hook setting upper limit 90 seconds. The HTTP settings for notifier are connect timeout 10 seconds and operation inactivity timeout 20 seconds, which are not treated as upper limits for the entire HTTP. Even if it fails, the turn result will not be changed and no asynchronous workers will be introduced.
- stdin reads the standard input stream as an explicit UTF-8 `StreamReader` at each boundary, and does not assume a change in `Console.InputEncoding` or a console connection.
- Attempt the send API only once per generation and consume the result to the terminal state. No retry or automatic retransmission is performed.
- Do not save or output topic, secret, raw arm input, prompt/response, thread title, and repository path in state, stdout/stderr, and hook output.
- Before enabling a hook or watcher, check the combination of permission profile and sandbox that is actually selected in the target session using the canary. The required permissions are limited to reading the session index/transcript of the same home, limited writing to the root of the same home state, and HTTPS communication to `ntfy.sh`, and the skill does not automatically change the Codex settings.

## Reason for judgment

### Don't take UUID on first match

Codex logs, Markdown, and quotes can contain multiple UUIDs. If you prioritize first match or canonical URI, you run the risk of silently selecting another thread. Therefore, we only deduplicate repeats of the same UUID, and if there are multiple different UUIDs, we stop as `thread_ambiguous`.

Partial matches in which ASCII alphanumeric characters, underscore, and hyphen are directly connected to UUID will not be considered as candidates. The arm input is limited to UTF-8 4 KiB to prevent the entire input from becoming too large, and the full text of the extracted source is not retained.

### Separate strict parser and arm extractor

If you use partial matching for hook and state values, there is a possibility of picking up a different UUID from corrupted metadata or altered state. Therefore, use `Extract-ArmThreadId` for external inputs and a strict `Normalize-CodexThreadId` for internal boundaries.

### Divide state into Codex home units

In the shared state in skill checkout, request, watcher lock, and checkpoint conflict when `.codex` and `.codex-personal` are used at the same time. By simultaneously deriving the state and sessions root from the home that Codex actually uses, you can make the resident watcher for each home independent.

The state directory is not created during installation, but only after arming after confirming that the target is managed by the current home. This is to avoid creating a new runtime directory just by trying an unknown home or an unknown UUID.

`CODEX_HOME` is selected only from the process environment. It does not infer an alternate home from the input value or overwrite an arbitrary home in the WSL envelope. If the WSL side cannot inherit the current session environment, it will fail to avoid registering the wrong home.

### Request-owned TTL and lazy cleanup

We use an absolute TTL of 24 hours from the arm time to set an upper limit without adding resident workers or retransmission mechanisms while reservations wait for a future turn. If you use only the `armedAtUtc` of the request for judgment and treat the checkpoint copy or missing time as an auxiliary value, you can prevent old checkpoints from extending their lifespan or sending from unknown times. Deadline determination is limited to existing execution points of arm, stop, and watcher, and expired requests are logically invalidated and then physically deleted. Since the request is deleted first, the watcher cannot reconstruct the notification target using only the remains of the checkpoint.

### Handling LFed malformed lines

The JSONL fallback scans each rollout with one monotonically advancing cursor. For an append-only writer that defines LF as the record commit boundary, a line ending in LF that fails strict UTF-8 decoding or JSON parsing is permanently malformed. Discard it immediately so it does not block detection of later records. Retrying forever at that offset would starve a valid `task_complete` record behind it. Do not store raw bytes or decoded text in state; keep only the existing path and offset in the checkpoint.

This judgment assumes that the rollout writer does not update the LF-completed range. If the writer implementation or trace disproves that assumption, redesign for bounded retry/discard that preserves the same range and failure count across restarts. Even then, do not save or output the malformed content, and define the failure count as the number of observations.

### Linearization of cancel

cancel does not create a new state machine and acquires coordination and thread locks already shared by arm/stop/watcher in the same order. We recheck `armed` under lock before deleting the request, so Stop's `attempting` claim does not intersect with unconditional file deletion. If the lock cannot be acquired in time, the request body is read twice to check stability, but except for stable `attempting`, set `busy` to be safe. Since it is an explicit cancel on a per-thread basis, re-arming between calls is not constrained by a generation token, and the contract leaves a constraint that subsequent cancels target the generation at that point.

### Double check index and transcript

`session_index.jsonl` is used to quickly narrow down candidates for the same home, but the validity of the rollout cannot be confirmed with the index alone. The final judgment is `session_meta` at the beginning of active rollout and confirms that it is the root user session. It does not judge only filename matches or accept archived rollouts.

### Use `references/design.md` instead of README

`SKILL.md` concentrates on how to call and the current contract, and the reason for adoption, rejection proposal, evidence, and maintenance conditions are separated into this design record. This is because if you copy the README separately, the usage instructions and contract will likely become obsolete.

This file does not record the local absolute path, username, real UUID, thread name, prompt/transcript content, topic, credential, or private config values. Issues are referred to as provenance links, but the summary is self-contained so that even if you can't read the issue, you can understand the current decision.

### Separate diagnostic scripts from production routes

The terminal display comparison script is separated from the production adapter, hook, and watcher because it performs an actual ntfy publish, and is placed in `scripts/diagnostics/`. These scripts do not launch automatically through the acceptance path; they run only for an explicitly requested display check. Messages, topics, prompts, and responses other than random values are not handled.

## Verification and maintenance

When changing specifications, treat the following as the same change:

1. Current contract of `SKILL.md`
2. Adapter/detector/sender in `scripts/` and diagnostic materials in `scripts/diagnostics/`
3. Acceptance conditions for `tests/task-complete-notify.tests.ps1`
4. Invariant conditions and reasons for this design record decision
5. GitHub Issue #3 body and judgment history comments

At a minimum, we will re-verify the ambiguity of input extraction, wrong-home rejection and state not created, lock separation for each home, one-time stop/watcher, fail-closed cleaning of 24-hour TTL and incorrect time, conflict between cancel and stop, natural termination of watcher, and non-leakage of secret values.
Acceptance tests for a fully malformed JSONL line verify detection of a valid `task_complete` after invalid JSON/UTF-8, checkpoint persistence across restart, no output of malformed content, and retrying a partial line that does not yet end in LF.

## Evidence link

- [GitHub Issue #3: notification-skill](https://github.com/the9ball/.dotfiles/issues/3)
- [Issue #3 initial process-reuse draft](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5628328226)
- [Issue #3 final contract discussion](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5629234932)
- [Issue #3 implementation and verification record](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5630098951)
- [Issue #3 review-response policy](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5632941893)
- [Issue #3 live-canary result](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5633214614)
