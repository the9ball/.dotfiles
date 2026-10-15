# Anchoring-quality pilot preregistration

This protocol is fixed before any reviewer measurement. Source: Issue #138 / PR
#139 at `9805d5180768db0b95e048518aac98d72ad5ef6b`; PR base
`b2047fb19322aec7cacbcd3b974cd0e64b38e259`. It evaluates the mechanism with new
synthetic changes, not the quality of the Skill implementation itself.

## Scope and authorization

The user requests quality-first measurement, repository artifacts, commits and
push to the existing PR branch, and one result comment on PR #139. The user also
explicitly approved independent CLI sessions and available subagents as an
alternative to the unavailable user-visible investigation-task API. No Skill,
checklist, persistent host setting, unrelated file, merge or Issue-close change
is authorized. Existing `aqua.yaml` changes and untracked `skills/.trash/` are
excluded. All new files belong under `docs/review-quality/`, plus one summary
`docs/code-review-quality.md` and links in existing evaluation documents.

Requested user review AUTO resolves to NONE: no additional regular user review
was requested. Requested review level ADVISOR is explicit in the user request.
Independent design advice precedes measurement; a fresh final Advisor reviews
the fixed committed report, scoring and evidence. Advisor advice is not a
measurement, user acceptance, or a substitute for actual validation.

## Questions and outcomes

- H1: making the checklist available in the same context reduces unrestricted
  material-defect detection (A versus B).
- H2: independent contexts suppress this reduction (B versus C, with A as the
  free-review reference).
- H3: C maintains or improves checklist-quality detection relative to B.

Every hypothesis receives Supported, Not supported, or Indeterminate. A single
success does not establish superiority. Absence of observed differences in this
small pilot does not establish equivalence or noninferiority. Ceiling effects,
ambiguous scoring, contradictory hosts/trials and weak stimulus sensitivity
lead to Indeterminate where they prevent a justified directional conclusion.
Report descriptive counts and rates; no significance or population-quality
claim is planned. No equivalence margin or adequate confirmatory sample exists.

## Fixed design

Four new fixtures: material-only, quality-only, mixed with visible surface
distractions, and clean. The fixture author is independent of the coordinator
and reads the actual checklist privately to classify overlap. Root receives
ground truth but never checklist text. Reviewer evidence strips fixture kind,
ground truth, reproductions and expected counts. Reviewers see only neutral file
names, full base and candidate source, complete diff, requirements and commit
metadata. SHA-256 manifests fix the complete inputs. These are content manifests,
not fictitious Git commit SHAs. No existing fixture answers are reused.

A: one unrestricted inspection; no checklist. B: one unrestricted and checklist
inspection in the same fresh context, checklist embedded from the start. C: one
unrestricted inspection followed by a new independent checklist-only process.
A and C's unrestricted prompts are byte-identical for each fixture. Both C
phases receive the same complete change evidence. C2 receives no C1 findings.
The harness mechanically transfers the pinned checklist bytes into B and C2
inputs; Root never reads or prints them. No reviewer has filesystem tools or
permission to consult additional artifacts. Codex tool use is prohibited and
audited; Claude tools are disabled. Root input rendering and scoring artifacts
never contain checklist text. Replies identify checklist IDs with case-specific
evidence, without reproducing item titles/text.

There are zero correction passes and zero post-Clean full passes in **all** arms,
as explicitly scoped by the user's fixed-change detection experiment. A finding
does not prevent collection of the remaining experimental stages, and is never
interpreted as operational Clean or permission to advance the reviewed change.
This experimental bypass does not alter the production Skill.

Four fixtures times two independent trials times two hosts, with four reviewer
launches per fixture/trial/host (A, B, C1, C2): maximum **64 launches**. Each host
runs sequentially, C1 completes before C2. Hosts may run concurrently. Latin-style
rotations vary arm order by fixture, trial and host; round 2 reverses fixture
order. This balances exposure but does not reset server caches. No resumed or
forked reviewer sessions. Session IDs must be unique across admitted calls.

Codex resolves the existing CODEX_HOME model/effort configuration and explicitly
carries those fields into `--ignore-user-config` calls, suppressing unrelated
MCP/configuration and instruction-file discovery. At preregistration the selected
fields are `gpt-6.1-sol` / `medium`; the primary chat remains unchanged. All Codex
arms use identical execution configuration. The stream does not independently
attest the backend model/effort. Claude safe-mode calls omit model/effort overrides
and use the same host defaults in every arm; the result must identify
`claude-opus-5-5` consistently. Effective Claude effort is not independently
attested. These are host-specific comparisons; do not pool host quality as if
settings or models were equivalent across products. CLI versions and arguments
are saved in the report and runner.

## Budget and pilot decision

This is a bounded pilot, not a commitment to automatic main measurement. Maximum
64 reviewer launches, no hidden replacement runs and no correction reruns.
Reviewer API-rate equivalent budget is **10 USD total**, split 5 USD per host;
before a call reserve 0.40 USD and stop launching if the host budget cannot cover
it. Claude also receives its per-process 0.40 USD CLI guard. Codex usage is known
only on completion, so its estimate is a between-call control rather than a
provider-enforced billing cap; an unexpectedly expensive in-flight call may
exceed the reservation and must be disclosed. Subscription credits, actual
billing, the outer Root and native Advisor costs are unavailable and are not
represented as zero or included in this numeric reviewer budget. No external
API key purchase, credential change or dependency install is authorized.

Each invocation waits for completion; silence is not a timeout or reason to
retry. Failed/incomplete calls are recorded separately, never counted as clean;
the affected comparison stops. An unexpected model, tool use, missing source
coverage, identity change or leakage stops the affected experiment. Preliminary
evaluation after round 1 checks plumbing and stimulus adequacy; round 2 is
performed only if the inputs and scoring remain valid. Fixture/protocol changes
after measurement invalidate pooling and require a new preregistration; do not
silently rerun until an effect appears. If the pilot saturates or cannot expose
anchoring, stop after its planned trials and propose a minimal harder follow-up.

## Scoring

Freeze ground truth before the first reviewer starts. Reproduce every material
seed and validate the clean candidate. Ground truth records severity, cause,
impact, trigger, expected observation, relation to checklist and reproduction.
An independent scorer receives anonymized outputs and truth, without host/arm
labels, other trial comparisons, private reviewer prompts or earlier evaluation.
The scorer does not run reviewers or alter ground truth. Root verifies matching
against actual source, reproductions and outputs before unblinding aggregation.

A match requires the correct underlying cause and impact, plus a valid condition
consistent with the reproduction; wording need not match. Broad warnings without
a concrete mechanism are insufficient. Matching uses all B findings for primary
material recall so relabeling an issue into its checklist section cannot create
an artificial B miss. Separately report B's free section and C1, recognizing that
B's output sections are not separately timed cognitive phases. C final is the
deduplicated union of C1/C2. Checklist recall uses B's checklist output and C2;
also report whole-arm union if unrestricted review detects a quality issue.

For each observation record matched truth IDs with finding IDs and reasons,
unmatched extra findings, duplicates, severity overstatements, and optional
suggestions incorrectly made mandatory. A new reproducible defect can be a valid
unseeded finding: document it and assess sensitivity without retroactively
changing the preregistered known-defect denominator. Ambiguity is recorded, not
automatically scored as false positive. P1 is a serious defect under the stated
contract; P2 is a material correctness defect; P3 is a minor quality problem.
Unsupported severity upgrades are counted independently from defect matching.

Primary: known material recall, outside-checklist material recall, P1 misses,
A-detected/B-missed, B-missed/C-detected, C-only new misses, by host/fixture/trial.
Checklist: quality-seed recall, every active ID accounted for, applicability and
evidence validity, missing/unsupported results. False positives and duplicates
remain separate. Per-item applicability judgments are audited by an independent
checklist-aware evaluator without disclosing its body to Root.

Costs: retain input/output/cache tokens, CLI estimates or Standard-rate estimates,
elapsed process time, launches, and observed metadata. Codex pricing at the
measurement date: 2 USD input / 0.10 cached input / 10 output per million tokens;
reasoning is already inside output and is not added twice. Claude CLI cost is an
estimate and its receipt is preserved. Report ratio of summed C reviewer cost to
summed B reviewer cost per host, additional dollars, and material/P1 detections
gained or lost for that increment. Root has deterministic harness control but
outer-chat cost is unavailable; no Root-inclusive ratio will be invented.

## Implementation and validation bounds

Fixture construction and reproductions: two files, approximately 350-650 lines
of data/test source. Harness/evidence/aggregation: approximately 250-450 executable
lines, plus 100-250 scoring/aggregation lines if needed. Report/protocol, generated
evidence and receipts are excluded from executable estimates. No new classes,
packages or persistent settings. One logical evaluation unit; commits may
separate frozen inputs and measured evidence for auditability without rewriting
existing history. Required checks: reproduction runner, syntax compilation,
explicit changed-file formatting verification, manifest and session isolation
audits, scoring reconciliation, and Git whitespace checks. Unavailable formatting
coverage is disclosed. Independent design and final advice cover methodology,
fairness, leakage, scoring and strength of conclusions.

## 承認候補

なし。指定対象への結果コメント・評価文書の commit/push と代替実行経路は明示許可済み。
試行・費用・編集・外部操作の範囲を超える場合は、この許可を拡張して解釈しない。
