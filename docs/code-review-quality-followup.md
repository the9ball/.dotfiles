# Astra-low consultation and additional anchoring sensitivity pilot

Date: 2026-10-15. Targets: [Issue #138](https://github.com/the9ball/.dotfiles/issues/138), [PR #139](https://github.com/the9ball/.dotfiles/pull/139).

**Quality discrimination failed again: the Codex pilot reached the material-defect ceiling.** A, B and C each detected both fixed material defects, including the P1 cause. The preregistered stop was applied before the planned sixteen-launch cross-host measurement. Four Codex reviewer processes completed; **zero additional Claude reviewer processes and zero main-study processes** ran. H1, H2 and H3 remain **indeterminate / 判断不能**. No general adoption or rejection decision is justified.

The reviewer estimate was B **0.0773776 USD**, C **0.1487876 USD**, C/B **1.9229**, increment **0.0714100 USD**. This is one exploratory within-host pilot comparison with observed cache state, not a replacement for the previous two-host 1.54–1.57 ratios. It buys no additional fixed material or confirmed quality detection in this case. Actual billing, subscription credits and outer Root/evaluator/Adviser expense are unavailable.

## Consultation, stimulus and truth

A fresh Adviser was requested as `gpt-6-astra` / `low` before case construction. Native dispatch confirms those requested fields but does not independently attest effective backend settings. Its independent proposal was a stock-allocation service, replacing the tentative combined import/snapshot/queue design. It warned that difficulty alone does not measure anchoring, and that C adds inference opportunity as well as isolation. [Consultation and proposal dispositions](review-quality-followup/design-consultation.md) distinguish the advice from coordinator decisions. In particular, the separate-fixture A/B pilot proposal was modified to a same-fixture A/B/C pilot to exercise C's actual path without adding another fixture. All later uses would have been exploratory.

The fixture is a standard-library Python/SQLite inventory service with six Python files plus README. The service grows from 151 to 167 lines, excluding tests/docs. Four files change: allocator, API, README and public tests. Existing catalog, repository and expiry code supply surrounding dependencies. A real predecessor commit and a coherent feature commit are retained in the [Git bundle](review-quality-followup/artifacts/reservation.bundle):

| Identity | Fixed value |
| --- | --- |
| Fixture base | `fcdc1ba6ef2ab53821d7a691e7c3b5b6e152d086` |
| Fixture candidate | `41c8c08a85e184017f6d0ea275abf2ad1622d776` |
| Governing repository source | `6f40592f1945dc47805af7055355a84c1321cb79` |
| Final pretrial source/audit target | `08f66765ecd4e724e7622f085862a1b4da2d6042` |
| Review evidence SHA-256 | `09ae9e8f6345a04d2a2c7a12c64cd0d956c68e0b1626d2487f5ed8a4af7081e3` |

[Public evidence](review-quality-followup/artifacts/evidence.json) contains all base/candidate files, full diff, actual commit patches, ordinary feature requirements, explicit documentation policy and recorded public tests. [Frozen truth](review-quality-followup/artifacts/truth.json) was fixed before any reviewer; it contains cause, trigger, impact, local severity, code/commit, checklist relationship, matching criteria and private reproductions. Private checks are absent from fixture commits and reviewer inputs. Baseline public tests 6/6 and candidate tests 8/8 pass; both private checks pass in base and fail by assertion in candidate. [Captured reproduction results](review-quality-followup/artifacts/reproduction-results.json) distinguish those intended failures from test execution errors.

| Cause | Severity | Mechanism | Primary checklist relation |
| --- | --- | --- | --- |
| M1 | P1 | Repeated canonical-SKU lines are individually checked against initial availability, allowing aggregate overselling | Outside dedicated quality criteria |
| M2 | P2 | In-place quantity adjustment leaves the scheduled release quantity stale; expiry corrupts available stock | Outside, with plausible documentation/dependency overlap |
| Q1 | P3 | README promises `reservations`, implementation returns `items` | CRQ-004 |
| Q2 | P3 | Replaced flow leaves an unreferenced helper within the complete supplied service | CRQ-005, bounded contract |

The independent [pretrial audit](review-quality-followup/pretrial-audit.md) corrected overly narrow M1 matching, overbroad Q2 reachability wording, launch-accounting failure paths and coverage-format mismatch before measurement. Five mocked controller guard tests pass without paid requests. A renewed audit allowed the pilot only, explicitly warning that the small, transparent change might still saturate. Actual Git history and policy evidence repair prior fixture defects, but do not by themselves increase discovery difficulty.

## Method and isolation

The [preregistered protocol](review-quality-followup/protocol.md) specifies A free review, B free plus checklist in one fresh context from the start, and C sequential independent free/checklist contexts. A/C1 canonical user prompts are identical; all methods see the same complete code, requirements and diff. No repair or post-Clean full review is performed in any arm. C2 receives no C1 findings. These are experimental discovery responses, not production convergence or permission to proceed with unresolved defects.

The outer author/coordinator read the existing checklist during the user-requested preflight and knows truth. It is separate from the review Root: the deterministic [controller](review-quality-followup/run.py) constructs prompts from public evidence and mechanically transfers checklist bytes for B/C2, without loading truth or author discussions. Reviewers are instructed not to use tools; observed tool calls are checked and none occurred. Neutral directories, fresh ephemeral sessions and zero tool observations support behavioral isolation; no child-only OS access guarantee is claimed. The independent pretrial evaluator inspected this boundary and found no private-test leakage in the public source or patches.

Codex CLI `0.162.1` explicitly carries the existing `gpt-6.1-sol` / `medium` configuration into all four calls. Effective backend model/effort is not independently emitted. Primary chat settings were unchanged. Claude execution remained planned only, using unchanged host defaults; no current Claude settings or performance measurement is asserted. The user approved the native-subagent route as an exception because the investigation-task API required by the local delegation Skill was unavailable.

Four complete unique sessions, complete declared four-file coverage, seven rows per B/C2, exact stdin/prompt hashes, C1-before-C2 order and event-to-receipt replay pass the [receipt audit](review-quality-followup/pilot-receipt-audit.json). Coverage is declared and supported by visible evidence, not a measurement of internal attention. Each launch has a durable pre-process reservation; unresolved launches/failures block continuation rather than disappearing from cost accounting. No failed or excluded reviewer observation occurred.

## Independent scoring and checklist evidence

A separate fresh scorer received anonymous observations and truth/public evidence, excluding host, method, stage, trial, cost and the mapping. Each response was scored separately before C was unioned by cause. This is partial blinding because response structure can suggest focus. The initial packet omitted checklist rows; a completeness correction restored them without changing reviewers, identities, truth or anonymous IDs. Initial packet/grades remain retained, and the same still-blinded scorer corrected only Q2 recognition. See [final independent grades](review-quality-followup/pilot-grades.json), [independent checklist audit](review-quality-followup/pilot-checklist-audit.json) and [adjudication history](review-quality-followup/adjudication.md).

| Codex pilot, one observation per arm | A | B | C union |
| --- | ---: | ---: | ---: |
| Fixed material detection | 2/2 | 2/2 | 2/2 |
| Fixed outside-checklist material detection | 2/2 | 2/2 | 2/2 |
| P1 misses | 0/1 | 0/1 | 0/1 |
| Confirmed fixed quality findings | 1/2 | 1/2 | 1/2 |
| Quality causes recognized, including explicit UNVERIFIED | 1/2 | 2/2 | 2/2 |
| Confirmed unsupported causes | 0 | 0 | 0 |
| Severity overstatements against frozen local definitions, entries | 1 | 2 | 2 |

C1 itself detects both material causes and Q1. C2 independently routes both material causes in limitations; those observations are credited rather than erased by output location. A-found/B-missed, B-missed/C-found and C-missed/B-found are all zero for fixed material causes. Excluding M2 under a broader checklist-overlap interpretation leaves M1 detected in all methods and changes no directional conclusion.

Both B and C2 report Q1 as CRQ-004 FINDING, and explicitly recognize Q2 under CRQ-005 but return UNVERIFIED because hypothetical external consumers cannot be excluded. The auditor considers this overconservative for a bounded unused-helper finding while agreeing that mandatory removal is a separate question. Strict quality findings remain 1/2, cause recognition 2/2; UNVERIFIED is neither omitted checking nor a false PASS. Each response has all seven IDs and no broken links; six rows have supported judgments and CRQ-005 is contested. B's CRQ-006 NOT_APPLICABLE and C2's APPLICABLE/PASS use defensible different readings of a new dependency edge. Minor C2 line-reference imprecision does not invalidate its underlying evidence.

No confirmed optional suggestion made mandatory or unsupported causal claim was scored. However, all four responses additionally flag absent deadline enforcement. That behavior predates the change; the brief does not clearly distinguish a caller precondition from rejection behavior. It remains a separately recorded pre-existing/contract-ambiguous observation, outside the denominator and without automatic mandatory-regression status. The zero confirmed unsupported-cause count is not evidence of a zero false-positive rate. The frozen P2 expiry cause is raised to P1 in A/B/C1; the frozen P3 documentation cause is raised to P2 in B/C2. Major misses are never offset by minor findings.

## Reviewer cost and observed time

Codex estimates reuse the prior measurement's Standard-rate equivalents of 2 USD uncached input, 0.10 USD cached input and 10 USD output per million tokens. Output includes reasoning and is not charged twice. These are explicit retained conversion rates, not a claim about actual charges or credits. All cache writes are zero. [Per-call receipts and normalized event logs](review-quality-followup/receipts/) retain the observed usage; [aggregation](review-quality-followup/pilot-summary.json) is deterministic.

| Pilot stage | Input incl. cache | Cached input | Output incl. reasoning | USD estimate | Process seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| A | 31,933 | 0 | 911 | 0.0729760 | 25.59 |
| B | 32,990 | 7,296 | 2,526 | 0.0773776 | 68.42 |
| C1 | 31,937 | 7,296 | 955 | 0.0595616 | 30.19 |
| C2 | 32,993 | 0 | 2,324 | 0.0892260 | 59.61 |
| C total | 64,930 | 7,296 | 3,279 | 0.1487876 | 89.80 |

Total reviewer estimate **0.2991412 USD**, process-time sum **183.81 seconds**. C/B **1.9229**, +**0.0714100 USD** (+92.29%), process-time ratio approximately **1.3125**. Provider caches were observed, not reset; A/C1's identical user prompts still have slightly different inclusive input counts, whose backend origin is not independently observable. A/B/C ran once in that order, so cache/order variation is not counterbalanced at pilot size. No stable cost multiplier or marginal cost per prevented serious defect is established. All spend is within the 12 USD estimate management boundary; the unused planned budget is not a measured saving on equivalent work.

Outer Root, fixture author, native scorer/auditors and Advisers have unavailable token/cost counters. They remain a separate unavailable category, not zero and not included in the reviewer-only ratio. There is no model-backed review Root cost in this experiment; the outer author still has unmeasured control cost.

## Stop, hypotheses and next evidence

The [pilot admission record](review-quality-followup/pilot-admission.json) rejects main measurement under the predeclared ceiling stop. The planned two-host/two-trial sixteen reviewer launches did not run. No post-result fixture edits, additional trial or selective pooling occurred. This pilot cannot establish repeatability across trials or hosts.

| Hypothesis | Judgment | Evidence boundary |
| --- | --- | --- |
| H1: combined checklist interferes with free discovery | **Indeterminate / 判断不能** | No fixed material A/B difference, ceiling, one pilot cell |
| H2: independent phases reduce that interference | **Indeterminate / 判断不能** | No B material loss to recover; C adds inference opportunity; no repeat/cross-host evidence |
| H3: independent phases maintain checklist quality | **Indeterminate / 判断不能** | Same confirmed/recognized causes and one contested UNVERIFIED per arm; no noninferiority evidence |

The coordinator defers general adoption. This dataset establishes neither C superiority nor B/C equivalence and supplies no reason to delete or omit the mandatory checklist. The observed extra C expense is not offset by additional fixed detection here; it also cannot prove that C is never worthwhile.

The next useful step is **stimulus redesign before more trials**. This fixture's meaningful changes still fit two short allocator methods. Repeated-SKU overselling can be found locally without following alias resolution; expiry's dependency chain is short. The feature brief naturally directs attention to both neighborhoods. Artificially adding files or checklist noise would not fix that weakness. A future separately budgeted candidate should start from a realistic existing change and caller structure, preferably a historical regression or naturally arising multi-file interaction, use an independent author/ground-truth audit, and pass a held-out sensitivity pilot before paying for the two-host matrix. Trial-number expansion, a new fixture and any targeted diagnostic need a new reason/estimate; none runs automatically from this report. Isolation-only causal claims additionally need an inference-budget control beyond A/B/C.

Issue #138 gains actual fixture Git history, explicit policy evidence, fixed truth, independent audit/scoring and a reproducible ceiling stop. Its general anchoring claim, representative-diff validation, cross-host replication, effective-effort attestation and post-Clean review value remain unresolved. No Skill/checklist behavior, PR merge, Issue state or production adoption policy changes are made. Final independent Adviser findings are recorded separately from the measured counts.

## Offline reproduction

With an explicitly selected compatible Python interpreter, use `-B docs/review-quality-followup/test_controller.py`, `-B docs/review-quality-followup/evaluate.py audit --interval pilot` and `-B docs/review-quality-followup/evaluate.py aggregate --interval pilot`. They make no model requests. To regenerate the fixture, run `-B docs/review-quality-followup/build_fixture.py --output <new-output-directory>` and verify the two Git identities; wall-clock test-duration strings can differ. Clone the saved bundle into a new directory to inspect its full history. Do not invoke `run.py pilot/main` to reproduce the report: those are paid operations, completed labels are protected, and main admission is false.
