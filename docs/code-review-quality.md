# Checklist anchoring pilot: Codex results; Claude blocked

Date: 2026-10-15. Targets: [Issue #138](https://github.com/the9ball/.dotfiles/issues/138)
and [PR #139](https://github.com/the9ball/.dotfiles/pull/139).

**H1, H2 and H3 are Indeterminate.** Codex detected every preregistered material
defect in A, B and C. C cost **1.5728 times B**, with no improvement on the seeded
material or quality problems. One independently confirmed, unseeded performance
regression was found by A in trial 1 and C in trial 2, while B missed it twice.
That is one distinct defect and an unreplicated C success, not proof that C is
superior. Claude authentication failed before inference, so the requested
cross-host comparison remains incomplete. No main measurement was started.

## Conditions and fixed artifacts

The source PR head was `9805d5180768db0b95e048518aac98d72ad5ef6b`, base
`b2047fb19322aec7cacbcd3b974cd0e64b38e259`. New fixtures and ground truth were
committed at `51897a3`; the final premeasurement control revision was `2464f41`.
All subsequent recovery changes preserve every fixture and reviewer-prompt
identity from that revision, as verified by [audit.py](review-quality/audit.py)
and [its results](review-quality/audit-results.json).

The [preregistered protocol](review-quality/protocol.md),
[fixture/answer data](review-quality/fixtures.json),
[manifest](review-quality/manifest.json) and complete source/diff
[evidence](review-quality/evidence/) are retained. Base/candidate identities are
honest content manifests, not invented Git commit IDs. Each fixture has one
changed module, a meaningful base, complete candidate/callers and one declared
feature commit. The absence of actual fixture commit history is a pilot defect
discussed below. Prompt hashes identify canonical LF text; the Windows stdin
files use the same CRLF translation in all arms. They are not wire-byte hashes.

| Fixture | Candidate content lines | Material seeds | Quality seeds | Purpose |
| --- | ---: | ---: | ---: | --- |
| F1 dispatch batching | 69 | 3 P2 | 0 | API response shape, partial batches, permanent exceptions |
| F2 inventory digest | 69 | 0 | 3 P3 | Naming, contradictory output-format description, unused helper |
| F3 report downloads | 71 | 2 P1 + 1 P2 | 2 P3 | Tenant leakage, storage boundary, stale dependency cache, visible surface distractions |
| F4 audit pagination | 64 | 0 | 0 | Clean filtering/pagination change; false-positive control |

Ground truth predates the first reviewer and records cause, impact, severity,
trigger, expected finding, checklist relation and reproduction. Six material
regressions and five quality seeds were verified, including sane baselines and
clean/quality-only behavior: [reproducer](review-quality/reproduce.py),
[recorded results](review-quality/reproduction-results.jsonl). No truth, fixture
kind, expected count, other response or old evaluation result enters a reviewer
prompt. The author, blind scorer and checklist auditor are separate contexts.

## Arms, fairness and settings

A receives a free review without checklist guidance. B receives the checklist
from the start and performs free and checklist work in one fresh context. C
receives a fresh free review followed sequentially by a new checklist-only
context. Both C phases see the same complete changes, and C2 receives no C1
findings. A/C1 free prompts are identical for each fixture. The harness transfers
checklist bytes mechanically into B/C2 input; the Root model never reads the
body. The checklist identity remains
`2fe9e949a390971dbb863d4194bf7d6fc534f2d675fb0d42d6cbb5e8fc642b72`.

There are **zero correction reviews and zero post-Clean full reviews in every
arm**, as explicitly scoped by the user's fixed-change experiment. Continuing
to C2 after a material finding is experimental data collection, never operational
Clean. This experiment does not measure the production post-Clean review's
additional value and does not waive it in the Skill.

Codex CLI 0.162.1 completed four fixtures times two independent trials: 8 A,
8 B, 8 C1 and 8 C2 processes, **32 distinct admitted sessions**. Arm order rotates
by fixture/trial; fixture order reverses in trial 2. All reviewer tool-use counts
are zero; all full-file declarations and eight C1-to-C2 ordering checks pass.
Provider caches are observed, not reset. Codex explicitly carries the existing
CODEX_HOME selection `gpt-6.1-sol` / `medium` into isolated calls and checks it
against the manifest across rounds. Effective backend model/effort is not
independently emitted; configured values are not proof of effective settings.
The primary chat's external settings were not changed.

Claude Code 2.1.296 used safe mode, no session persistence, disabled tools and
unchanged host model/effort defaults. Its attempted first B process returned
`Failed to authenticate: OAuth session expired and could not be refreshed` with
zero input/output usage and zero CLI-estimated cost. Its initialization model
field is not evidence that inference ran. No authentication refresh, account
switch or alternate service was attempted. **Claude A/B/C quality and B/C cost
are NOT MEASURED**, not zero or equal to Codex.

## Blinded scoring and primary quality

The independent scorer received [anonymous findings](review-quality/blind-packet.json)
and truth, without host/arm/stage labels, timings or the
[unblinding map](review-quality/blinding-map.json). Content can still suggest a
review's focus, so label removal is not perfect treatment blinding. Matching
requires the defect's cause, impact and a valid triggering condition, not wording.
All 32 observations and 81 findings are accounted for in the source-bound
[round-1](review-quality/grades-round1.json), [round-2](review-quality/grades-round2.json)
and [merged grades](review-quality/grades.json).

B primary recall uses both finding arrays. Checklist recall also counts a valid
checklist-row link to a free finding: one B documentation finding is stored only
in that array but explicitly referenced by its check. Ignoring the link would
produce an artificial 9/10 versus 10/10 difference. The
[aggregation code](review-quality/analyze.py) counts causes and valid links.

| Codex, two trials | A | B | C final union |
| --- | ---: | ---: | ---: |
| Known material defects detected | 12/12 | 12/12 | 12/12 |
| Predefined outside-checklist material defects | 10/10 | 10/10 | 10/10 |
| P1 misses / P1 opportunities | 0/4 | 0/4 | 0/4 |
| Known quality problems, whole-arm union | 10/10 | 10/10 | 10/10 |
| Known quality problems supported by checklist output/links | N/A | 10/10 | 10/10 |
| Free-output material detection | 12/12 | 12/12 | 12/12 in C1 |

For preregistered material defects, A-found/B-missed, B-missed/C-found,
B-found/C-missed and A-found/C-missed are **all zero** in the eight paired
fixture/trial cells. These repeated opportunities are clustered in two material
fixtures; they are not twelve independent samples of production review quality.
B's free section is an output partition in one combined response, not a timed
observation of cognition before checklist work.

F1-M1's predefined outside classification is contested under a broader reading
of a general compatibility description. Excluding this cause gives 8/8 remaining
outside opportunities in all arms, preserving the absence of a seeded difference.
The strong F3 storage-boundary overlap remains distinct. Outside means outside
the criterion's main concern, not impossible to discover while checking it.

## Additional material observation and false positives

The unseeded queue-copy regression has independent deterministic confirmation:
with successful sends and batch size 1, baseline work traverses N references;
candidate work traverses N(N+1)/2. At N=100 this is 100 versus 5,050, and at N=200,
200 versus 20,100. [Supplemental code](review-quality/additional-evidence.py)
and [results](review-quality/additional-evidence-results.json) measure reference
traversals, not latency or an unmeasured service-level breach. This is workload-
dependent performance evidence and stays outside the frozen denominator.

| Same unseeded cause | A | B | C |
| --- | --- | --- | --- |
| Trial 1 | Found | Missed | Missed |
| Trial 2 | Missed | Missed | Found in C1 |

Thus C adds one exploratory detection relative to B in trial 2, but also misses
the issue found by A in trial 1. A and C each find it once. A post-hoc inclusive
sensitivity calculation gives A 13/14, B 12/14 and C 13/14 material opportunities;
it is not a preregistered detection rate or replication of C superiority.

The blind scorer found **zero confirmed false positives, severity overstatements,
within-response duplicates or optional suggestions incorrectly made mandatory**.
There are zero false findings on the clean fixture across all arms/trials. C has
13 expected repeated seed mentions across its independent phases; final union
deduplication removes them. These confirmations are not additional discoveries.
Small line-reference offsets occur; symbol/source evidence still identifies the
real causes. The sample does not establish a population false-positive rate.

## Checklist evidence and pilot defects

The independent [checklist audit](review-quality/checklist-audit.json) privately
read the pinned checklist and all result rows. It confirms all seven active IDs
in every B/C2 response: each arm has 8 complete inventories, 56 rows, no missing
or duplicate IDs and no broken finding links. It finds no confirmed unsupported
PASS or unrestricted C2 restart; internal discovery paths are unobservable.

**Each arm has 10 UNVERIFIED rows.** Eight concern actual commit-sequence evidence
missing from the synthetic fixture; two concern F1's unstated documentation
policy. They are defensible stops, not successful completion and not missing
checks. The frozen PASS expectations overstate evidence. Naming findings also
defensibly apply to more than one ID, and three F1 documentation links are
contestable. Strict expectation/result disagreements are B 16/56 and C2 15/56;
strict applicability disagreements are 2/56 each. Those are **not error rates**.

The pilot therefore exposes answer-table and evidence-design defects before any
main measurement. It cannot establish complete checklist-quality maintenance.
The requirements also strongly cue seeded defects, producing a ceiling on the
primary material metric. Running more copies of these easy inputs would not
repair that sensitivity problem.

## Reviewer cost and observed time

All amounts below are **API Standard-rate equivalents**, not subscription credits
or actual billing. Rates are 2 USD uncached input, 0.10 USD cached input and 10 USD
output per million tokens; output already includes reasoning. All observed cache
writes are zero. [Official model pricing](https://developers.openai.com/api/docs/models/gpt-6.1-sol)
supports the rate calculation; every one of 32 Codex receipts is independently
recomputed by the audit. Raw usage and responses remain in
[receipts](review-quality/receipts/).

| Codex totals, same eight fixture/trial units | A reference | B | C |
| --- | ---: | ---: | ---: |
| Reviewer launches | 8 | 8 | 16 |
| Input tokens, including cached | 177,552 | 185,996 | 363,514 |
| Cached input tokens | 18,688 | 21,888 | 77,952 |
| Output tokens, including reasoning | 5,175 | 16,916 | 20,678 |
| Standard-rate equivalent USD | 0.3713468 | 0.4995648 | 0.7856992 |
| Sum of process seconds, approximately | 146.7 | 375.3 | 492.5 |

**C/B = 1.5728 times, +0.2861344 USD (+57.3%).** The incremental cost buys zero
additional seeded material/P1/quality detections and one exploratory unseeded
detection in this dataset, with a countervailing miss against A in the other
trial. Dividing 0.2861344 by that one observation is only descriptive, not a
general cost per prevented defect. No repeated C advantage was established.

The observed process-time ratio is approximately 1.31. Two durations were
reconstructed after controller interruptions; one child exit code was not
captured, although its complete answer and explicit `turn.completed` event were
retained. Excluding that F2/C1 quality-only observation changes no primary
material detection and no final checklist-quality union. The primary process
sum is about 16.9 minutes; its first-start/last-finish window is about 30.3 minutes,
including recovery, controller and scoring pauses. Neither is whole-task time.

The outer Root, native scorers and Advisers have **unavailable** token/cost
counters. No Root-inclusive multiplier is claimed. The 1.5728 ratio is observed
cache-state dependent; caches were not reset and a duplicate adds exposure.

## Recovery deviations and budget

The [history](review-quality/protocol.history.md) preserves all deviations.
Two aqua wrappers failed before model startup; a separate Claude process failed
authentication with zero reported usage. Coverage representations included bare
names, line descriptions and file objects. Overly strict admission code rejected
complete replies; source/input identities were verified and original replies
retained without replacement. All prompt and ground-truth identities remain
unchanged across those control fixes.

One recovery assertion compared CRLF bytes to canonical LF text. The shell then
continued to a restart, accidentally producing **one paid B/F2 duplicate**. The
coordinator stopped its controller, kept the original reply irrespective of
content and isolated the duplicate in [diagnostics](review-quality/diagnostics/).
Its 0.068340 USD is excluded from quality/B-to-C comparison but included in the
known operational reviewer subtotal: **1.7249508 USD**. It is not a free retry.

The original cap was 64 model-backed launches and a 10 USD reviewer estimate
budget. The user explicitly approved an increase to **65 launches**, with the
10 USD estimate budget unchanged; 33 model-backed launches have been used,
32 admitted. This permits all 32 originally planned Claude launches. The user
selected reauthentication and continuation on both hosts, but a recovery check
still returned an expired OAuth error with zero reported usage and cost.
Claude trials remain pending until authentication is restored. The
budget excludes unavailable outer Root/native evaluation costs and is not a
provider-enforced guarantee about actual billing.

## Hypotheses and adoption assessment

| Hypothesis | Judgment | Evidence and limit |
| --- | --- | --- |
| H1: combined checklist context reduces free material detection | **Indeterminate** | Seeded ceiling; one A-only exploratory detection, not a repeated between-method effect |
| H2: independent phases suppress that reduction | **Indeterminate** | No seeded B loss to recover; one C-only exploratory recovery and one C miss against A; C also adds inference budget |
| H3: C maintains or improves checklist-quality detection | **Indeterminate** | Both 10/10 known quality problems with valid links; evidence gaps and small sample prevent noninferiority or general superiority claims |

**Coordinator assessment: defer a general adoption judgment.** This pilot does
not justify standardizing C for proven quality superiority, and does not justify
switching to B on a claim of equal quality. It provides a concrete price for C
and one conditional exploratory benefit. Checklist execution remains mandatory
in the intended workflow. No Skill/checklist specification, production review
gate or adoption policy is changed by this report.

## Independent advice and minimum next validation

The independent design Adviser cleared the bounded pilot after coverage/session,
settings and CLI-resolution corrections. Its advice was to retain the ceiling,
small-sample and extra-inference-budget caveats. The blind scorer independently
validated cause matching; the checklist auditor identified the evidence and
answer-table problems above. These are attributable judgments, separate from
the observed counts. Final independent report review is recorded in the
[execution record](review-quality/execution-record.json).

The smallest useful follow-up is to repair fixture evidence first: actual
reproducible base/candidate commits with ancestry and commit-specific patches,
and an explicit applicable documentation-policy boundary. Keep the checklist
unchanged. Replace the strongly cued mixed case with one realistic harder mixed
change whose normal feature brief does not enumerate expected failures, and
freeze new independent truth before review. Validate its sensitivity with two
independent trials in both hosts: **16 reviewer launches** for one fixture,
A/B/C, rather than automatically scaling the current easy set. Fix output
serialization in that new preregistration without changing one arm midstream.
Use a fresh fixed budget and confirm model/effort observability; additional
inference-budget controls would be needed for an isolation-only causal claim.

Claude reauthentication is prerequisite to any cross-host measurement. Do not
reinterpret its startup failure as a quality result. Issue #138's cross-host
anchoring evidence, representative-diff validity, effective settings and
post-Clean full-review incremental value remain unresolved. Merge and Issue
closure remain excluded. This partial pilot report is not completion of all
requested cross-host measurements.

## Reproduction

With an explicit compatible Python interpreter, run `-B` with
`review-quality/reproduce.py`, `review-quality/additional-evidence.py`,
`review-quality/audit.py`, and `review-quality/analyze.py aggregate` from this
repository. Those commands are offline and make no reviewer requests. The
runner's `prepare` and `run` commands are separate; **do not rerun paid reviewers
as part of reproducing this report**. Fresh model runs are nondeterministic and
require a separately fixed execution interval. Historical prompts can be
regenerated from pinned inputs without sending them to a model.

Python AST checks, deterministic reproductions, explicit changed-file
editorconfig-checker checks, identity/session/order/cost audits and Git whitespace
checks passed. EditorConfig Core resolved no applicable properties; no Python
language formatter was available, so language-specific formatting is unverified.
No dependencies, credentials or persistent host settings were changed.
