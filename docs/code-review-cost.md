# Review-only cost measurement for Issue #138 / PR #139

The later [anchoring-quality pilot](code-review-quality.md) measures combined
checklist context versus independent contexts with equal post-Clean pass counts.
Its C/B ratios are 1.5728 for Codex and 1.5446 for Claude Code. That work boundary differs
from this report's ordinary-versus-three-review comparison.

## Result and interpretation

Two ordered pairs per host, measured on 2026-10-15, give **3.80x for Codex** and **3.56x for Claude Code** when dividing the sum of two-phase reviewer estimates by the sum of ordinary reviewer estimates. These are descriptive results for this fixture and observed cache state, not stable intrinsic multipliers. Every two-phase arm includes exactly three independent reviews: initial free review, post-Clean full free review, and checklist review. No repair or local rereview is included.

| Mean USD estimate per arm/stage (two trials) | Codex API Standard-rate equivalent | Claude CLI list estimate |
| --- | ---: | ---: |
| Ordinary, one free review | 0.0256022 | 0.0277159 |
| Phase 1 initial free review | 0.0467840 | 0.0161066 |
| Post-Clean full free review, additional | 0.0066874 | 0.0147766 |
| Phase 2 checklist review, additional | 0.0438722 | 0.0677862 |
| Two-phase reviewer total | 0.0973436 | 0.0986694 |
| Reviewer-only ratio | **3.8022x** | **3.5600x** |
| Ordinary Root gate subtotal | 0.0536830 | 0.0595060 |
| Two-phase Root gate subtotal | 0.1461292 | 0.2191260 |
| Ordinary including measured gates | 0.0792852 | 0.0872219 |
| Two-phase including measured gates | 0.2434728 | 0.3177954 |
| Ratio including measured gates | **3.0708x** | **3.6435x** |

The Root-inclusive result measures the specific **fresh stateless gate** protocol below. It does not estimate the cost of a long-lived production Root, the outer chat, or internal automatic approval reviews. Neither host's USD column measures consumed credits or actual billing. Do not compare the dollar columns as model-quality or billing equivalence.

| Host / ordered pair | Ordinary USD | Two-phase USD | Reviewer ratio | Ratio including measured gates |
| --- | ---: | ---: | ---: | ---: |
| Codex R1: ordinary then two-phase | 0.0465140 | 0.1178004 | 2.5326x | 2.8106x |
| Codex R2: two-phase then ordinary | 0.0046904 | 0.0768868 | 16.3924x | 3.5183x |
| Claude R1: ordinary then two-phase | 0.0401352 | 0.1155260 | 2.8784x | 3.2842x |
| Claude R2: two-phase then ordinary | 0.0152966 | 0.0818128 | 5.3484x | 4.1229x |

Reversing arm order reduces one ordering bias; it does not reset provider caches. All Claude R2 reviewer calls have zero cache creation and fully cached input apart from two/four ordinary input tokens. Its **5.35x** warm-cache result is particularly useful alongside the pooled result. The anticipated “2x plus a small increment” is not established by these measurements. No trial was adjusted to meet that expectation.

## Fixed conditions and session boundaries

- Source implementation: PR #139 head `b82a6353daae7b5adcaf52fe824b13ce0909c067`. Issue #138 and the existing evaluation were read before measurement. The earlier raw sessions were no longer available, and their durable totals do not isolate child/root/repair costs. No old cost value is reused in the new comparison.
- Both hosts used the same standalone Git fixture: empty base `9cdf0cfdf5482690d1fdd0a7f1d4a9eb60727766`, candidate `7f9d01249580a586982ce7c58a3484e5dcbc5006`. One commit, `feat(account): add documented contract-correct utilities`, adds only `account.py` (18 lines) and `usage.md` (13 lines), mode 100644. The complete base-to-candidate diff and single-commit metadata are supplied to every reviewer.
- Requirements: satisfy the three usage contracts below; all named functions require accurate role docstrings. Inputs meet the stated preconditions. Extra validation, type hints, rounding policy and deep copying are not required. The empty base has no surrounding naming conventions. The two files form one utility feature and rollback unit.
- Fixture preparation separately passed AST parsing, formatting verification, and eight behavioral assertions: owner accepted, different owner refused, amounts 99/100/101, expected tags, fresh outer list/nonmutation, duplicates allowed. These checks are excluded from review costs. Reviewers themselves do not run tests; their stated inspection-only limitations are preserved.
- Ordinary, Phase 1 initial, and post-Clean full review receive byte-identical user prompts on both hosts: SHA-256 `9ec03ce57ef789f6d7e060d3c663acb5f22af451d8a1fe946c62021b20a24aad`. No earlier findings, phase label or desired answer is included. Phase 2 receives the same frozen evidence with checklist-only criteria and permission to read the actual checklist. No other reviewer's findings are supplied to any reviewer.
- Checklist SHA-256: `2fe9e949a390971dbb863d4194bf7d6fc534f2d675fb0d42d6cbb5e8fc642b72`. Every Phase 2 reads it once. Root gates receive `SKILL.md`, the fixed manifest and stage replies, but no checklist/maintenance body. Phase 1 and ordinary sessions use no tools and receive neither body.
- One fresh CLI process per reviewer and per Root gate; no continuation/resume. There are **32 unique admitted session IDs**: 16 reviewer launches and 16 gate launches across both hosts. Per host, two ordinary launches and six two-phase launches; two ordinary gates and six two-phase gates. Within each arm, a gate completes before the next stage starts. Gates return STOP on material findings, incomplete scope or unverified applicable checklist checks. All measured gates returned ALLOW with zero material findings. This is permission to advance the benchmark, not an assertion that remaining minor findings were fixed.
- Round 1 order is ordinary + gate, then initial + gate, full + gate, checklist + gate. Round 2 reverses the two arms. Hosts ran concurrently; stages within each host ran sequentially. Wall-clock durations measure subprocess launch to exit, including startup and tool round trips, excluding gaps between calls. No cross-host speed conclusion is drawn.

Codex CLI 0.162.1 uses `exec --json --ephemeral --approve-for-me --skip-git-repo-check --model gpt-6.1-sol -c model_reasoning_effort=medium -`. Model/effort are configured explicitly and held fixed; its stream does not independently identify the effective backend model/effort. The read-only behavioral contract is used with the existing Windows backend; no child-only OS sandbox claim is made. In admitted Phase 2 runs, one explicit `cmd.exe` `type` read loads the canonical checklist; no fallback tool or other file is read.

Claude Code 2.1.296 uses `--safe-mode --no-session-persistence --permission-mode default --permission-prompts none --model claude-opus-5-5 --effort medium --tools Read --allowedTools Read --disallowedTools mcp__* --add-dir <repository> --output-format stream-json --verbose --print`. The final `modelUsage` identifies `claude-opus-5-5` for every call. Medium effort is requested consistently; provider caps/effective effort are not independently emitted. Only Phase 2 uses Read. Reviewer processes do not spawn children. These are explicit contract-execution measurements, not native slash-command discovery tests.

After **all measurements completed**, a reporting audit accidentally printed one Codex tool result containing the checklist body into the outer report-writing chat. This is an outer-session read-boundary deviation. It did not enter any measured Root or free-review context and no subsequent reviewer measurement used that chat. The 32-session tool audit separately verifies the measured boundaries. Do not claim that the outer chat never saw the body throughout report preparation.

### Fixture contents

`account.py`, SHA-256 `fcd5f5e22681bd864a56865b81c61ebba8dccf4d6debe8cec2e183a0ee4142f6`:

```python
"""Small account utilities with caller-provided validated inputs."""


def read_note(record, requester_id):
    """Return the owner's note; reject any different requester with PermissionError."""
    if requester_id != record["owner_id"]:
        raise PermissionError("Not the record owner")
    return record["note"]


def discount(amount):
    """Return a ten-percent discount for amounts at least 100, otherwise unchanged."""
    return amount * 0.9 if amount >= 100 else amount


def add_tag(tags, tag):
    """Return a fresh outer list with the tag, preserving input and allowing duplicates."""
    return [*tags, tag]
```

`usage.md`, SHA-256 `b6e6dceabe974050240ba579e383864c6156bfb6e15ea52e09fd8261101c2b25`:

```markdown
# Account utility contracts

Callers supply a built-in dictionary containing `owner_id` and `note`, nonempty
string owner/requester IDs, a finite nonnegative `int` or `float` amount, and a
built-in tag list. Input validation beyond these preconditions is outside scope.

`read_note(record, requester_id)` returns `record["note"]` when requester ID
equals owner ID; otherwise it raises `PermissionError` before returning the note.
`discount(amount)` returns `amount * 0.9` for amounts at least 100 and returns
`amount` otherwise. Floating-point representation and rounding policy are outside
scope. `add_tag(tags, tag)` returns a fresh outer list containing the original
elements followed by the tag. The input list is unchanged; duplicate tags are
allowed. The functions require no new dependency or infrastructure.
```

## Per-call measurements

Every row below represents **one launch**. Model/effort are the fixed per-host settings above. Codex Input includes Cache read; do not add them. Claude Input, Cache read and Cache write/creation are disjoint: free-review total input is 4,645 tokens and Phase 2 total is 11,322. Codex reasoning-output counters are subsets of Output and are retained in the JSON record without adding them again. One final `turn.completed.usage` or Claude `modelUsage` is counted per process; streaming duplicates are excluded.

Codex USD is a counter-based API Standard-rate equivalent: `(uncached input * 2 + cached input * 0.1 + output * 10) / 1,000,000`. Cache-write tokens are zero in every admitted Codex call. These rates come from the [official model pricing](https://developers.openai.com/api/docs/models/gpt-6.1-sol); this is not a CLI billing receipt. Claude USD comes from the final `total_cost_usd`, with `modelUsage.costBasis: list`; it is a client estimate, not observed credit consumption.

The accompanying [per-call JSON evidence](code-review-cost-results.json) preserves all admitted usage counters, costs, durations, session identities, prompt/output hashes, structured findings, all checklist results and separate excluded diagnostic receipts. Absolute host paths are replaced with portable placeholders. Session identities establish separate contexts, not billing identities. The executable measurement helper and raw private streams are transient; no large measurement framework or dependency was added.

### Codex reviewer calls

| Round / stage | Input | Cache read | Cache write | Output | USD estimate | Seconds | Material / minor |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| R1 / ordinary | 22367 | 0 | 0 | 178 | 0.0465140 | 8.97 | 0 / 0 |
| R1 / phase1 | 22367 | 0 | 0 | 173 | 0.0464640 | 9.27 | 0 / 0 |
| R1 / full | 22367 | 19584 | 0 | 175 | 0.0092744 | 10.37 | 0 / 0 |
| R1 / phase2 | 46096 | 22400 | 0 | 1243 | 0.0620620 | 27.43 | 0 / 0 |
| R2 / phase1 | 22367 | 0 | 0 | 237 | 0.0471040 | 11.18 | 0 / 0 |
| R2 / full | 22367 | 22144 | 0 | 144 | 0.0041004 | 7.70 | 0 / 0 |
| R2 / phase2 | 46096 | 41984 | 0 | 1326 | 0.0256824 | 25.89 | 0 / 0 |
| R2 / ordinary | 22367 | 22144 | 0 | 203 | 0.0046904 | 8.83 | 0 / 0 |

### Codex Root gate calls

| Round / stage | Input | Cache read | Cache write | Output | USD estimate | Seconds | Material / minor |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| R1 / ordinary gate | 26413 | 0 | 0 | 92 | 0.0537460 | 6.25 | 0 / 0 |
| R1 / phase1 gate | 26415 | 0 | 0 | 95 | 0.0537800 | 6.66 | 0 / 0 |
| R1 / full gate | 26537 | 0 | 0 | 94 | 0.0540140 | 6.72 | 0 / 0 |
| R1 / phase2 gate | 27543 | 0 | 0 | 111 | 0.0561960 | 6.73 | 0 / 0 |
| R2 / phase1 gate | 26494 | 0 | 0 | 112 | 0.0541080 | 7.11 | 0 / 0 |
| R2 / full gate | 26617 | 19584 | 0 | 119 | 0.0172144 | 8.35 | 0 / 0 |
| R2 / phase2 gate | 27738 | 0 | 0 | 147 | 0.0569460 | 7.20 | 0 / 0 |
| R2 / ordinary gate | 26425 | 0 | 0 | 77 | 0.0536200 | 6.27 | 0 / 0 |

### Claude reviewer calls

| Round / stage | Input | Cache read | Cache write | Output | USD estimate | Seconds | Material / minor |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| R1 / ordinary | 2 | 1556 | 3087 | 756 | 0.0401352 | 13.10 | 0 / 1 |
| R1 / phase1 | 2 | 4643 | 0 | 761 | 0.0161566 | 10.76 | 0 / 1 |
| R1 / full | 2 | 4643 | 0 | 640 | 0.0137366 | 9.22 | 0 / 1 |
| R1 / phase2 | 4 | 7024 | 4294 | 2493 | 0.0856328 | 27.46 | 0 / 1 |
| R2 / phase1 | 2 | 4643 | 0 | 756 | 0.0160566 | 10.32 | 0 / 1 |
| R2 / full | 2 | 4643 | 0 | 744 | 0.0158166 | 10.71 | 0 / 1 |
| R2 / phase2 | 4 | 11318 | 0 | 2383 | 0.0499396 | 26.32 | 0 / 0 |
| R2 / ordinary | 2 | 4643 | 0 | 718 | 0.0152966 | 10.14 | 0 / 1 |

### Claude Root gate calls

| Round / stage | Input | Cache read | Cache write | Output | USD estimate | Seconds | Material / minor |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| R1 / ordinary gate | 2 | 2290 | 6023 | 546 | 0.0595700 | 8.46 | 0 / 1 |
| R1 / phase1 gate | 2 | 2290 | 6068 | 505 | 0.0591100 | 8.03 | 0 / 1 |
| R1 / full gate | 2 | 2290 | 6508 | 772 | 0.0679700 | 10.52 | 0 / 1 |
| R1 / phase2 gate | 2 | 2290 | 8407 | 856 | 0.0848420 | 11.17 | 0 / 1 |
| R2 / phase1 gate | 2 | 2290 | 5951 | 908 | 0.0662340 | 12.26 | 0 / 1 |
| R2 / full gate | 2 | 2290 | 6530 | 937 | 0.0714460 | 12.67 | 0 / 1 |
| R2 / phase2 gate | 2 | 2290 | 8278 | 1098 | 0.0886500 | 14.10 | 0 / 1 |
| R2 / ordinary gate | 2 | 2290 | 5997 | 550 | 0.0594420 | 8.31 | 0 / 1 |


## Checklist outcomes and review quality

| Active ID | Codex R1 | Codex R2 | Claude R1 | Claude R2 |
| --- | --- | --- | --- | --- |
| CRQ-001 | Applicable / PASS | Applicable / PASS | Applicable / PASS | Applicable / PASS |
| CRQ-002 | Not applicable | Not applicable | Not applicable | Not applicable |
| CRQ-003 | Applicable / PASS | Applicable / PASS | Applicable / PASS | Applicable / PASS |
| CRQ-004 | Applicable / PASS | Applicable / PASS | Applicable / minor FINDING | Applicable / PASS |
| CRQ-005 | Applicable / PASS | Applicable / PASS | Not applicable | Not applicable |
| CRQ-006 | Not applicable | Not applicable | Not applicable | Not applicable |
| CRQ-007 | Applicable / PASS | Applicable / PASS | Applicable / PASS | Applicable / PASS |

Every ID has applicability, result, reason and bounded evidence in the retained record; no applicable check was unverified. The CRQ-005 classification differs: Codex inspects the additions and passes; Claude excludes replacement/deletion cleanup against an empty base while citing that scope. Neither claims an unavailable check passed. Both Phase 2 calls cover both complete added files and the proposed single commit.

All sixteen reviewer calls find zero material defects. Codex reports zero minor findings. Claude reports one minor wording ambiguity in `discount`'s docstring in every free review and first checklist review; its second checklist review treats the implementation/usage contract as sufficiently clear and returns no minor finding. The code and usage contract explicitly return the discounted price. This wording issue is retained, not repaired or reclassified to manufacture Clean. Optional naming/documentation suggestions remain separate in the JSON.

No fixture was excluded for a material finding and no fixture was changed after freezing. Zero material findings under these preconditions makes these normal-case review-only trials eligible. This does not prove absence of every latent bug, assess material-detection sensitivity, or demonstrate quality superiority. The earlier seeded-defect study remains a separate quality result.

## Cache effects, Root boundaries and excluded work

Ordinary versus initial Phase 1 uses identical prompt bytes and 22,367 total input tokens in Codex. R1 costs are nearly equal (0.0465140 versus 0.0464640). In R2 ordinary reads 22,144 cached tokens while initial Phase 1 has zero cached tokens; their 0.0046904 versus 0.0471040 difference follows that cache asymmetry, not a larger Phase 1 diff. Outputs differ by only 34 tokens. Claude R1 ordinary creates 3,087 cache tokens while Phase 1 reads the already cached 4,643; their outputs differ by five tokens. R2 ordinary/Phase 1 share the same cached-input counts and costs are close (0.0152966 versus 0.0160566). No provider cache reset/isolation was available, so same user input/model/effort does not imply same billed cache state.

A **counterfactual cache-neutral diagnostic**, repricing all measured Codex input as uncached at the same Standard rates, gives mean ordinary 0.046639 USD, initial 0.046784, full 0.046329, checklist 0.105037, two-phase 0.198150: **4.2486x**. This is theoretical repricing of measured tokens, not another observed trial. It helps explain why a single pooled cached ratio is not the intrinsic cost of the procedure.

Phase 2 has an additional model/tool round trip to load the real checklist. Its summed input is about 2.06x the Codex free-review input and 2.44x the Claude free-review input; its per-ID reasons/evidence also produce substantially more output. The additional post-Clean full review is another complete independent free review. The token receipts, not the launch count alone, determine the estimates.

Root gates judge actual stage replies before progression. This benchmark deliberately starts a fresh Root process for each gate, resupplying `SKILL.md`, manifest and earlier replies, to make control counters separable. The reported Root subtotal is therefore sensitive to contract retransmission and cache creation, particularly in Claude. It is **not** the marginal cost of continuing an existing production Root context. Gate minor counts can carry forward an earlier unresolved minor finding even when the latest checklist reports none. Main-chat preparation/orchestration/analysis/reporting, fixture preparation, internal auto-approval computation and subsequent GitHub operations are not separately metered; they are excluded and **not asserted zero**. No new design Advisor consultation was used in these reviewer totals.

Two initial Codex pairs are excluded in their entirety because Phase 2 mixed real checklist reading with Windows PowerShell DLL startup failures, a fallback read-tool attempt and eventual recovery. They found no material defects but did not provide a clean cost boundary for the prescribed successful read. After diagnosing the read path, both complete Codex pairs were rerun with one explicit successful `cmd.exe` read, retaining the same fixture, model, effort and free-review prompt. This is a host-read execution adjustment, not a Skill specification change. Claude's two clean pairs did not need rerunning.

| Separately excluded work | Calls | Estimated USD | Treatment |
| --- | ---: | ---: | --- |
| Codex initial diagnostic pairs: reviewers | 8 | 0.3654720 | All excluded, not selective expensive-stage removal |
| Codex initial diagnostic pairs: Root gates | 8 | 0.4393580 | All excluded |
| Total excluded diagnostic pairs | 16 | **0.8048300** | API Standard-rate equivalent; full per-call counters retained separately |
| Fixture creation/checks, reporting, outer orchestration, GitHub operations | Not model-metered separately | Unavailable | Outside review-only total; no zero-cost claim |

The original [implementation evaluation](code-review-evaluation.md) reports ordinary 0.2225514 and convergence 1.9859258 Claude USD (about **8.9x**). The latter includes seven reviewer launches, fixes/local checks and four CLI Root processes; the former is one initial review. Their unequal work boundaries cannot estimate review-method-only cost. Today's fixture has no known material defects, performs no repair, retains all three prescribed review stages, and accounts for gates separately. The difference from 8.9x is not evidence of an optimization or an 8.9-to-3.56 cost saving on equivalent work.

## Improvement opportunities and decision

The highest-cost incremental step here is checklist review; Root contract retransmission is also substantial in the stateless gate protocol. Potential improvements that preserve the existing contract are:

1. Keep one Root context for a fixed review identity rather than resupplying the full contract in each fresh gate; continue using independent reviewer contexts. Measure the marginal control cost separately before claiming savings.
2. Keep fixed contract/manifest prefixes stable and separate changing receipts to improve cache reuse. Cache savings remain provider-dependent and should not determine the quality gate.
3. Bound per-ID explanation length while retaining every ID, applicability, reason and concrete evidence, especially for exclusions. Validate that shorter output does not hide unverified checks or substantive findings.
4. Use a known-working read path and narrowly available tools so checklist review does not pay for unrelated host troubleshooting. The successful direct read in this benchmark is evidence for this host, not a universal host guarantee.

These are measurement-informed options, not adopted policy changes. Removing the post-Clean full review or required checklist evidence to approach a target multiplier would change the confirmed design and is not justified by this cost sample. No Skill behavior or deployment standard is changed. No design-change decision is needed to complete this measurement; broader adoption still needs cost/quality evidence from representative diffs and controlled cache conditions. PR merge and Issue close remain outside this task.
