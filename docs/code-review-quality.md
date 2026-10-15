# Checklist anchoring pilot: Codex and Claude Code

Date: 2026-10-15. Targets: [Issue #138](https://github.com/the9ball/.dotfiles/issues/138)
and [PR #139](https://github.com/the9ball/.dotfiles/pull/139).

**H1, H2 and H3 are Indeterminate (判断不能).** Both hosts detected every
preregistered material defect in A, B and C. C cost **1.5728 times B in Codex**
and **1.5446 times B in Claude Code**, with no additional seeded material,
major or quality detections. Codex has one exploratory C-versus-B detection of
an unseeded performance cause, plus a C miss relative to A in the other trial;
Claude detects that cause in every arm/trial. This does not establish a stable
quality gain for the extra cost. There are 64 admitted reviews on four fixtures,
two independent trials per host. This is the bounded pilot, not a completed
confirmatory main study; stimulus and evidence defects require repair first.

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

Each host completed four fixtures times two independent trials: 8 A, 8 B,
8 C1 and 8 C2 processes, **32 distinct admitted sessions per host**. Arm order
rotates by fixture/trial/host; fixture order reverses in trial 2. All reviewer
tool-use counts are zero; all full-file declarations and 16 C1-to-C2 ordering
checks pass. The fixtures, diffs, requirements and canonical prompt identities
remain unchanged between hosts and trials. Reviewer processes are ephemeral
and cannot consult truth, old reviews or other arm results.
Provider caches are observed, not reset. Codex CLI 0.162.1 explicitly carries the existing
CODEX_HOME selection `gpt-6.1-sol` / `medium` into isolated calls and checks it
against the manifest across rounds. Effective backend model/effort is not
independently emitted; configured values are not proof of effective settings.
The primary chat's external settings were not changed.

Claude Code 2.1.296 used safe mode, no session persistence, disabled tools and
unchanged host model/effort defaults. All 32 successful receipts identify the
same effective model, **`claude-opus-5-5`**; the runner rejects changes. Effective
effort is not independently attested. Earlier OAuth failures returned zero usage
and cost; after the user's `retry`, authentication status and reviewer execution
recovered through the same route. The coordinator made no credential, account,
service or persistent-setting change. Model/effort differ or are incompletely
observable across products, so quality and cost comparisons remain within host.

## Blinded scoring and primary quality

The independent scorer received [anonymous findings](review-quality/blind-packet.json)
and truth, without host/arm/stage labels, timings or the
[unblinding map](review-quality/blinding-map.json). Content can still suggest a
review's focus, so label removal is not perfect treatment blinding. Matching
requires the defect's cause, impact and a valid triggering condition, not wording.
All **64 observations and 193 finding entries** are accounted for in the
source-bound Codex [round-1](review-quality/grades-round1.json) and
[round-2](review-quality/grades-round2.json), Claude
[round-1](review-quality/grades-claude-round1.json) and
[round-2](review-quality/grades-claude-round2.json), and
[merged grades](review-quality/grades.json). Fixture construction, Codex scoring,
Claude scoring and checklist audits use separate contexts. Claude's scorer
retains its own earlier anonymous judgments between rounds, but never receives
host/arm labels or the unblinding map. Reviewer trials themselves never resume.
Scoring corrections restore the same synthetic commit summaries supplied to
reviewers and distinguish explicit optional suggestions from false defect claims;
they do not alter reviewers or frozen truth. Full details are in the
[append-only history](review-quality/protocol.history.md).

B primary recall uses both finding arrays. Checklist recall also counts a valid
checklist-row link to a free finding. Equivalent duplicate mentions also satisfy
their section's coverage without adding defects. Ignoring links or valid
duplicates would manufacture checklist misses. The
[aggregation code](review-quality/analyze.py) counts distinct causes and links,
validates disjoint grading, and retains duplicate/error counts separately.

| Each host separately, two trials | A | B | C final union |
| --- | ---: | ---: | ---: |
| Known material defects detected | 12/12 | 12/12 | 12/12 |
| Predefined outside-checklist material defects | 10/10 | 10/10 | 10/10 |
| P1 misses / P1 opportunities | 0/4 | 0/4 | 0/4 |
| Known quality problems, whole-arm union | 10/10 | 10/10 | 10/10 |
| Known quality problems supported by checklist output/links | N/A | 10/10 | 10/10 |
| Free-output material detection | 12/12 | 12/12 | 12/12 in C1 |

For preregistered material defects, A-found/B-missed, B-missed/C-found,
B-found/C-missed and A-found/C-missed are **all zero** in the eight paired
fixture/trial cells **per host**, all recorded in
[summary.json](review-quality/summary.json). These opportunities cluster in two material
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
| Codex trial 1 | Found | Missed | Missed |
| Codex trial 2 | Missed | Missed | Found in C1 |
| Claude trial 1 | Found, optional | Found, optional | Found in C1, optional |
| Claude trial 2 | Found, optional | Found, optional | Found in C1, optional |

In Codex, C adds one exploratory detection relative to B in trial 2, but also misses
the issue found by A in trial 1. A and C each find it once. A post-hoc inclusive
sensitivity calculation gives A 13/14, B 12/14 and C 13/14 material opportunities;
it is not a preregistered detection rate or replication of C superiority.
Claude has no between-arm difference on this cause (2/2 per arm). Its explicit
optional classification correctly avoids claiming an unmeasured service-level
failure; matching the underlying performance cause is separate from mandatory
repair status. No extra unseeded P1 defect was demonstrated.

Codex has zero confirmed false positives, severity overstatements or within-
response duplicates. Claude's scored counts below are finding-entry counts,
not independent population samples or a comparison of model families.

| Claude, two trials | A | B | C across both phases |
| --- | ---: | ---: | ---: |
| Unsupported defect claims | 0 | 1 | 3 |
| Severity overstatements against frozen severities | 8 | 10 | 11 |
| Within-response repeated cause entries | 0 | 4 | 0 |
| Explicit optional suggestions without established defect | 4 | 2 | 6 |
| Explicit optional suggestions made mandatory, confirmed | 0 | 0 | 0 |

Two unsupported C claims concern expanded documentation on the clean fixture;
the other C claim and B's claim concern weak documentation demands in F3.
Optional expansions are not counted as false positives. Three B duplicates
repeat the same F2 quality causes across output sections, and one repeats a
material cache cause through documentation framing; these may clarify checklist
accounting but do not discover new defects. Independent C phases also repeat
causes; final union deduplication removes them. C produces more responses, so
raw error counts alone do not establish a quality rate or causal penalty.

Claude B and C also each surface four post-hoc, summary-level commit-cohesion
quality observations (F1/F3 in both trials), while A does not. These are qualified
judgments about the proposed single-commit metadata, not verified Git ancestry
or additions to the known-defect denominator. Severity overstatements include
F1 material defects raised from P2 to P1 and documentation issues raised from
P3 to P2. One subsidiary scheduler-count claim is wrong (1, not0), while the
matched ValueError mechanism remains valid. Small line-reference offsets and
conditional secondary impacts are retained in the grades rather than treated
as independent defects. These observations prevent an unqualified quality-
equivalence claim even though known-defect recall is saturated.

## Checklist evidence and pilot defects

The independent Codex [checklist audit](review-quality/checklist-audit.json) privately
read the pinned checklist and all result rows. It confirms all seven active IDs
in every B/C2 response: each arm has 8 complete inventories, 56 rows, no missing
or duplicate IDs and no broken finding links. It finds no confirmed unsupported
PASS or unrestricted C2 restart; internal discovery paths are unobservable.

**Each Codex arm has 10 UNVERIFIED rows.** Eight concern actual commit-sequence evidence
missing from the synthetic fixture; two concern F1's unstated documentation
policy. They are defensible stops, not successful completion and not missing
checks. The frozen PASS expectations overstate evidence. Naming findings also
defensibly apply to more than one ID, and three F1 documentation links are
contestable. Strict expectation/result disagreements are B 16/56 and C2 15/56;
strict applicability disagreements are 2/56 each. Those are **not error rates**.

The independent [Claude checklist audit](review-quality/checklist-audit-claude.json)
verifies all 36 declared files, including the same private checklist and 32
normalized receipts. B/C2 each have 8 complete inventories, 56 rows, zero missing
or duplicate IDs and zero broken links; quality-seed linkage is 10/10 each.

| Claude rows | B | C2 |
| --- | ---: | ---: |
| PASS | 24 | 24 |
| FINDING | 24 | 22 |
| NOT_APPLICABLE | 8 | 8 |
| UNVERIFIED | 0 | 2 |

Per-ID applicability/result distributions and case rationales are preserved in
the audit. Naive fixture-result disagreements are 12 per arm, with defensible
naming and proposed-commit judgments among them. F1's unspecified documentation
policy and F2's absent actual history explain C2's two cautious UNVERIFIED rows;
bounded local/source-summary judgments in other receipts can also be defensible.
Missing actual Git history limits all topology claims, including PASS. The audit
also identifies F1 C2 PASS/routing tension where implementation-description
divergence was acknowledged, and weak escalation of optional F4 documentation.
All eight C2 free arrays are empty; material observations are criterion-linked
or explicitly routed. No unrestricted C2 restart is confirmed. Internal
attention and per-response checklist-content identity attestation remain
unobservable; harness hashes fix the actual supplied checklist identity.

The pilot therefore exposes answer-table and evidence-design defects before any
main measurement. It cannot establish complete checklist-quality maintenance.
The requirements also strongly cue seeded defects, producing a ceiling on the
primary material metric. Running more copies of these easy inputs would not
repair that sensitivity problem.

## Reviewer cost and observed time

Codex amounts below are **API Standard-rate equivalents**; Claude amounts are
**CLI-reported estimates**. Neither measures subscription credits or actual
billing. Codex rates are 2 USD uncached input, 0.10 USD cached input and 10 USD
output per million tokens; output already includes reasoning. All observed cache
writes in Codex are zero. [Official model pricing](https://developers.openai.com/api/docs/models/gpt-6.1-sol)
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

| Claude totals, same eight fixture/trial units | A reference | B | C |
| --- | ---: | ---: | ---: |
| Reviewer launches | 8 | 8 | 16 |
| Uncached input tokens | 16 | 16 | 32 |
| Cache creation input tokens | 22,501 | 40,141 | 67,726 |
| Cache read input tokens | 32,999 | 30,049 | 57,957 |
| Output tokens | 16,680 | 38,372 | 56,862 |
| CLI-estimated USD | 0.5202718 | 1.0946418 | 1.6907674 |
| Sum of process seconds, approximately | 191.0 | 387.2 | 618.1 |

Claude's input field excludes cache creation/read; do not interpret 16 as all
prompt tokens or compare it directly to Codex's inclusive input field. Raw
receipts retain cache durations and thinking details. **Claude C/B = 1.5446,
+0.5961256 USD (+54.5%)**, with a process-time ratio of 1.60. This increment buys
zero additional known material/P1/quality detections, zero additional performance
cause detections and zero additional summary-level commit-quality observations
relative to B. C's higher raw unsupported-claim count is a caution, not proof
of worse population quality. No stable quality improvement offsets the observed
extra cost in this sample.

Codex's observed process-time ratio is approximately 1.31. Two durations were
reconstructed after controller interruptions; one child exit code was not
captured, although its complete answer and explicit `turn.completed` event were
retained. Excluding that F2/C1 quality-only observation changes no primary
material detection and no final checklist-quality union. The primary process
sum is about 16.9 minutes; its first-start/last-finish window is about 30.3 minutes,
including recovery, controller and scoring pauses. Neither is whole-task time.

The outer Root, native scorers and Advisers have **unavailable** input/output/
cached-token and cost counters. They are not represented as zero; no Root-
inclusive multiplier is claimed. The deterministic controller launches 65
model-backed reviewer processes (64 primary plus the isolated duplicate);
outer control, scoring and waiting time are outside reviewer process times.
Both cost ratios depend on observed cache state. Caches were not reset; the
duplicate adds Codex exposure and host runs are separated by an authentication
pause. Within-host counterbalancing reduces order bias without eliminating it.

## Recovery deviations and budget

The [history](review-quality/protocol.history.md) preserves all deviations.
Two aqua wrappers failed before model startup; two separate Claude processes failed
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
known Codex operational reviewer subtotal: **1.7249508 USD**. It is not a free retry.

The original cap was 64 model-backed launches and a 10 USD reviewer estimate
budget. The user explicitly approved an increase to **65 launches**, with the
10 USD estimate budget unchanged. **65 model-backed launches were used, 64
admitted**: 33 Codex including the excluded duplicate, 32 Claude. The primary
reviewer estimate sum is 4.9622918 USD, or **5.0306318 USD including the duplicate**,
within the total budget and each 5 USD host budget. Authentication recovered
through the existing route after the user's retry; failed authentication and
wrapper processes are separate pre-inference diagnostics. The estimate budget
excludes unavailable outer Root/native evaluation costs and is not a provider-
enforced guarantee about actual billing. No main-study trials were launched.

## Hypotheses and adoption assessment

| Hypothesis | Judgment | Evidence and limit |
| --- | --- | --- |
| H1: combined checklist context reduces free material detection | **Indeterminate / 判断不能** | Both hosts at seeded ceiling; Codex has one A-only exploratory detection, not a repeated effect, and Claude has no such difference |
| H2: independent phases suppress that reduction | **Indeterminate / 判断不能** | No seeded B loss to recover; one Codex C-only exploratory recovery and one C miss against A; Claude shows no relative gain; C also adds inference budget |
| H3: C maintains or improves checklist-quality detection | **Indeterminate / 判断不能** | B/C each 10/10 known quality problems per host, with valid links; classification drift, evidence gaps and small sample prevent noninferiority or superiority claims |

**Coordinator assessment: defer a general adoption judgment.** This pilot does
not justify standardizing C for proven quality superiority, and does not justify
switching to B on a claim of equal quality. It provides a concrete price for C
and one conditional, unreplicated exploratory benefit. Checklist execution remains mandatory
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

Issue #138 now has a bounded cross-host A/B/C pilot and measured B/C reviewer
costs. Its general anchoring claim, representative-diff validity, effective
effort confirmation and post-Clean full-review incremental value remain
unresolved. This report cannot support treating those acceptance conditions as
proven or adopting C for demonstrated superiority. Merge and Issue closure
remain excluded. No Skill or checklist specification is changed.

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
