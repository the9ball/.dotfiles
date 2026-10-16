# Issue #138 implementation and runtime evaluation

The later [anchoring-quality pilot](code-review-quality.md) compares A/B/C on
new frozen fixtures in both Codex and Claude Code. Its quality measurements are separate
from this implementation/convergence evaluation; H1/H2/H3 remain indeterminate.

Date: 2026-10-15 JST. Design source: [Issue #138](https://github.com/the9ball/.dotfiles/issues/138), its [REVIEW-SUMMARY](https://github.com/the9ball/.dotfiles/issues/138#issuecomment-6172286907), [DIG-LOG](https://github.com/the9ball/.dotfiles/issues/138#issuecomment-6172285984), and [preimplementation measurements](https://github.com/the9ball/.dotfiles/issues/138#issuecomment-6173038586).

## Implementation and execution contract

The implementation adds `SKILL.md`, `checklist.md`, and `checklist-maintenance.md` under `link-targets/agents/skills/code-review/`, plus the minimal Codex invocation policy `agents/openai.yaml`. Root coordinates independent sequential read-only reviewers, classifies and deduplicates findings, fixes versions and coverage, and checks validation validity. Runtime Root and Phase 1 never load checklist or maintenance bodies. A separate implementation Advisor covers those files when reviewing this Skill itself.

Invocation is explicit. Codex metadata disables implicit invocation; the Claude frontmatter disables model invocation. A same-named host command is not proof of loading this implementation: select and confirm the actual entrypoint. No existing review workflow, persistent host settings, or retired workflow files were replaced or deleted.

Work base: `b2047fb19322aec7cacbcd3b974cd0e64b38e259`. Implementation snapshot tested initially: `85b7164aadc58cb5f97cb3a4538b9a8fda1d36b3`. A later entrypoint clarification pins the selected invocation source after the host smoke test exposed name ambiguity; it does not alter phase transitions. The final candidate receives fresh independent review.

The user authorized implementation, tests, independent review, commits, one branch push, an optional result comment on Issue #138, and one linked PR. Merge, Issue close, unrelated edits, credential changes and persistent host configuration changes are excluded. Pre-existing `aqua.yaml` and untracked `skills/.trash/` are excluded and retained. Requested user review is AUTO, effective NONE because the user explicitly requested autonomous convergence; review level AUTO resolves to ADVISOR, required by the new delegation/evidence/PASS contract. One slice covers all implementation files and this evaluation record. Spot review is skipped because the full bounded slice already covers all affected boundaries; no additional Advisor checkpoint or new framework is needed.

## Static verification

| Check | Observed result |
| --- | --- |
| `python -B link-targets/agents/tools/validate-instructions.py` via default launcher | Exit 1 before script startup: uv trampoline cannot spawn its Python child |
| `python -B link-targets/agents/tools/test-instructions.py` via default launcher | Same launcher failure, exit 1 |
| Both commands via the existing concrete Python 3.13.15 interpreter, same `-B` arguments | Validator PASS: 79 sources, 100 references; all 58 regression tests PASS |
| `git diff --check` for authorized changes | PASS |
| Bundled skill-creator `quick_validate.py`, UTF-8 explicitly enabled | Exit 1: its narrow frontmatter allowlist rejects Claude's `disable-model-invocation` |

The concrete interpreter is the existing host-local recovery route; no Python installation, PATH or junction repair was performed. The bundled quick validator also initially failed under Windows' default cp932 decoding; UTF-8 removed that environmental failure but exposed the schema limitation. Its rejection is retained as a failed supplementary check, not reported as passed. The field is documented by [Claude skills](https://code.claude.com/docs/en/skills); Codex invocation policy is documented by [OpenAI skills](https://learn.chatgpt.com/docs/build-skills). Independent Advisor reviewed this distinction. Shared validator/regression checks cover repository instruction contracts; they do not establish every host's discovery behavior.

## Common fixture and methodology

Ordinary and two-phase initial reviews use identical requirements and identical two-file additions, in separate fresh contexts. No known-answer list or another phase's findings is sent to an initial reviewer. Root later deduplicates symptoms by underlying defect. Model and effort overrides are omitted in both arms: existing host defaults/inheritance remain unchanged. Claude message/modelUsage records identify `claude-opus-5-5` for roots and children. Native Codex tool output does not expose effective model/effort or usage counters, so those values are unavailable, not inferred from role names.

The candidate exports these three functions; dictionaries/lists are supplied by callers. Correctness requirements: reject a nonowner with `PermissionError`, discount nonnegative amounts **at least** 100 by 10%, and return a fresh tag list without mutating input; duplicates are allowed. All named functions require accurate Python docstrings, and usage documentation must accurately state public contracts. Rounding, malformed inputs, additional type checks and complete API reference formatting are outside the fixture contract.

Initial `account.py`:

```python
"""Small account utility fixture for independent review comparisons."""


def read_note(record, requester_id):
    """Return a note only to its record owner; reject others."""
    return record['note']


def discount(amount):
    """Discount amounts at least 100 by ten percent."""
    return amount * 0.9 if amount > 100 else amount


def add_tag(tags, tag):
    """Return a fresh tag list without modifying the caller's list."""
    tags.append(tag)
    return tags
```

Initial `usage.md` states owner rejection, a discount "only above 100", and a fresh list permitting duplicates. Ground truth has three material implementation defects and one incorrect documentation boundary. Concrete reproductions are nonowner 2 reading owner 1's note, `discount(100)` returning 100 instead of 90, and `tags=['a']` being mutated with returned object identical to the input.

V1 adds the owner equality guard, uses `>= 100`, and returns `[*tags, tag]`; V2 corrects the usage threshold. V4 expands documentation to state existing return/exception/rate/nonmutation contracts. A deliberately bad V3 changes the threshold to 200. All revisions are separate fixed artifacts; negative-case findings are expected test results, not unresolved implementation defects.

The final common toy Git comparison is empty base `fb215d30ee0de2d2284e4ca8a40e89258f2f3dbc` to `c51e7a0b6d381089c39dfac0e7d5663dd3882770`, tree `a7a3e4d5050095137d0b2c43bda65670ff17ecc5`. Only `account.py` and `usage.md`, both mode 100644 additions, are included. A single contract-correct feature commit was constructed on a separate temporary branch; the original experimental history remains unchanged. The prior V4 tree is identical, making this a real test of content-check reuse and commit-check invalidation, without destructive history rewriting.

Raw SHA256 fingerprints: initial code `3BD53B1612FBA0BB123091F8E73EA4935C76411797109188161AB8CCA69297DD`; corrected/final code `CBDCA62345431993FE105687E63CE7A74899A8ECDFFAF1D1E30D143BB34812F7`; final documentation `C0DB7F0764F5B3730AFDAAFBD93DFB8772D6108931337982DC9490AD0A9B32AF`. Coordinator verified final Git blob bytes equal the corresponding snapshots, rather than treating hash labels as proof. These fingerprints reflect actual host bytes, including line endings.

Seven behavioral assertions actually passed on V1: reject nonowner, return owner's note, amounts 99/100/101, preserve original tag list, and return the correct fresh list. The same assertions ran again successfully against the final Git candidate after the V3 negative test. V3 actually exited 1 with `AssertionError: discount boundary regression`. Tests cover behavior; fixture-format compliance is unverified because no EditorConfig Core/formatter is available, and formatting was not a required fixture acceptance gate.

## Runtime acceptance evidence

| Required behavior | Codex native runtime | Claude Code 2.1.296 |
| --- | --- | --- |
| Independent sequential Phase 1 / Phase 2 | Fresh `fork_turns=none` reviewers; previous reviewer completes before next phase | Foreground non-fork general-purpose Agents; stream events show serial calls and completion |
| Phase 1 excludes checklist | Bounded requests/actual declared read scopes exclude both references | Phase 1 Read events and initial prompts exclude both references |
| Root excludes checklist bodies | Root reads metadata/hashes and returned inventory only | All recorded Root checklist Read calls = 0; no maintenance Read calls by any runtime role |
| Phase 2 covers full base-to-candidate changes | Both whole added files, actual Git diff and inventory reconciled | Full materialized Git patches plus both sources; hunk/source comparison performed |
| Per-ID results | All seven `CRQ-001` through `CRQ-007`, version-bound | All seven IDs; local summaries sometimes omit hyphens, coordinator reconciles against attested stable IDs |
| Material correction then post-Clean full review | Initial -> targeted correction -> fresh full free review -> Phase 2 | Initial -> correction -> stop for unresolved documentation -> corrected candidate -> targeted and fresh full review -> Phase 2 |
| Minor correction stays local | Usage-only correction, affected IDs and new commit evidence checked locally | Documentation omissions fixed with local CRQ-003/004 check; commit topology separately checked locally |
| Material Phase 2 correction returns to Phase 1 | Actual V3 source delta caused fresh full Phase 1, material defect and failed test, STOPPED | Same actual V3 delta caused fresh Phase 1, material defect and failed test, STOPPED |
| Startup/evidence/unverified checks stop | Unavailable agent_type errors without fallback; missing required file -> NEEDS_EVIDENCE; CRQ-007 without actual commits -> UNVERIFIED until evidence supplied | safe-mode custom Agent startup failed without self-review; absent Agent smoke and missing required evidence stopped; unresolved findings did not proceed to Phase 2 |
| Reuse and necessary reruns | Unchanged code reused behavioral evidence for docs/history; V3 invalidated affected evidence | Same scope-based reuse; V3 invalidation and real failed assertion; coordinator reran final-candidate assertions |

No checklist or maintenance auto-update occurred. The actual checklist fingerprint throughout runtime tests was `2FE9E949A390971DBB863D4194BF7D6FC534F2D675FB0D42D6CBB5E8FC642B72`; active ID count seven, retired IDs none. Final Codex outcomes are PASS for 001/002/003/004/007 and NOT_APPLICABLE for 005/006. Final Claude outcomes are PASS for 001/003/004/005/007 and NOT_APPLICABLE for 002/006. The applicability differences reflect different assessments of an empty comparison base and obsolete-content relevance; both account for every ID and leave no accepted finding unverified.

Root independently checks native reviewer evidence against fixture content, hashes and actual Git records. Claude's metadata-limited continuation Roots explicitly distinguish primary-asserted hashes/path resolution from calculations they cannot run. Primary physically verifies those records and audits stream events; a child's self-report alone is not the overall acceptance evidence. Intermediate Claude summaries do not embed all previous local-review evidence; the coordinator retains and checks the complete process records rather than silently treating each summary as a self-contained full review.

## Quality comparison

| Initial review | Known material defects detected | Severe misses | Accepted false material findings | Documentation boundary detected |
| --- | ---: | ---: | ---: | --- |
| Codex ordinary | 3/3 | 0 | 0 | Yes |
| Codex two-phase initial Phase 1 | 3/3 | 0 | 0 | Yes |
| Claude ordinary | 3/3 | 0 | 0 | Yes |
| Claude two-phase initial Phase 1 | 3/3 | 0 | 0 | Yes |

All accepted material findings have concrete valid scenarios and locations. Claude's ordinary output reports eight symptom-level findings for four underlying defects, plus completeness suggestions; coordinator deduplicates the symptoms. It labels some corrective actions as optional despite their associated material defect, so those labels are not used to waive fixes. Documentation completeness produced one additional minor issue with ambiguous "accurately state" interpretation, then was explicitly corrected. There is no verified false **material** finding; minor/optional false-positive rate is not reliably established by this small sample.

Claude classifies the wrong threshold documentation as material and stops earlier; Codex classifies its correction as minor. Claude later detects defective intermediate toy commits when actual per-commit patches become available, while Codex had accepted the earlier sequence from coarse evidence. Corrected final single-commit topology receives local PASS in both hosts. These differences are recorded; equal detection of three seeded bugs is not proof of generally equal review quality.

## Measured cost and measurement limits

The later [review-only cost measurement](code-review-cost.md) separates ordinary review, initial Phase 1, post-Clean full review, Phase 2 and Root control on a fixed normal-case fixture. The historical Claude convergence-to-ordinary ratio below (about 8.9x) is not a review-only multiplier. Stage receipts for the new measurement are retained separately in [JSON](code-review-cost-results.json).

Ordinary measurements cover one initial reviewer pass. Two-phase measurements cover correction convergence, post-Clean full review, checklist review and necessary local/evidence checks. Their work boundaries differ, so a percentage cost-saving or speed comparison would be misleading. Diagnostic startup/plan-mode/slash probes, deliberately failing V3 and missing-evidence probes, implementation Advisors, outer primary orchestration and internal automatic approval reviews are excluded from the positive comparison totals, not asserted cost-free.

| Host / arm | Successful reviewer spawns | Other reviewer dispatches | Observed elapsed boundary | Token counters | USD estimate |
| --- | ---: | --- | --- | --- | --- |
| Codex ordinary | 1 | 0 | 22 seconds, first/last observed reviewer clock | Unavailable | Unavailable |
| Codex two-phase positive convergence | 6 | 1 same-epoch Phase 2 clarification | Sum of stage clock intervals 685 seconds, including Root work/waits, excluding coordinator gaps | Unavailable | Unavailable |
| Claude ordinary | 1 | 0 | 61,546 ms, final CLI duration | input 8; output 6,389; cache read 15,357; creation 13,857 | 0.2225514 |
| Claude two-phase positive convergence, four CLI processes | 7 | 0 | Sum of CLI durations 491,084 ms; excludes inter-process coordinator gaps | input 86; output 49,255; cache read 457,949; creation 131,934 | 1.9859258 |

Claude totals use each final `modelUsage` exactly once; duplicated streaming message usage is not added. Cache read/creation and normal input are separate Claude fields, unlike Codex's counters in the prior investigation. USD values have runtime `costBasis: list`: client list-price **estimates**, not measured billing/contract credits. No precise credit consumption or child-vs-root token allocation is claimed. Host-default effort was not exposed, so cross-host model/effort equivalence and speed conclusions remain unverified.

Positive Claude components (duration ms / list USD estimate): initial+V1 correction 120,906 / 0.5558356; V2 correction+full review+full Phase 2 187,497 / 0.7058910; local documentation correction 97,217 / 0.3898850; local topology check 85,464 / 0.3343142. Seven child spawns completed, none failed in these positive runs. Separate diagnosis/negative/smoke processes total 0.7377404 estimated USD and are excluded above. Native Codex positive counts exclude its separate V3 child and intentionally failed startup attempt; the test Root coordinator is additional to its six reviewer spawns.

## Host limits and retained uncertainty

- Normal Windows shell startup requires the reviewed elevated backend in this session. Identical bounded operations use that route; it is not a child-only OS sandbox claim.
- Claude safe-mode disables session custom Agent definitions; the first requested custom reviewer failed. An explicitly selected built-in general-purpose route worked. Plan mode separately blocked execution. Subsequent authorized read-only probes use default permission mode and only Read/Agent; one metadata probe additionally allowed narrowly scoped shell metadata commands.
- In that metadata probe, an attempted variable/quoted shell command was denied automatically, then literal metadata commands succeeded. A filename-only `ls -la` executed outside the requested three-command list; no unrelated bodies or writes occurred. This behavioral-boundary deviation is retained. The no-shell continuation path avoids it. No strict universal shell/OS read-only enforcement is claimed.
- An unqualified Claude `/code-review` smoke exposed a same-named built-in command. It explicitly Read the shared entrypoint and stopped because Agent was unavailable. This confirms explicit source loading and stopping, but does **not** establish that the shared Skill won native slash discovery. Codex catalog discovery in a newly restarted session is also unverified. Direct explicit-path contract execution worked in both hosts; final routing guidance requires source confirmation.
- Large/truncated diffs, binary/mode/gitlink changes, renames, deletions, dirty/untracked mixtures, all model/effort override combinations, malicious shell/MCP escape attempts, and production repositories beyond this fixture were not exercised. The Skill specifies fail-closed handling; that specification is not their runtime test result.
- Raw session streams and temporary toy files are transient host artifacts. The durable record keeps fixture definitions, identities, measured totals, read-boundary audit and outcomes rather than publishing local paths or private host configuration. Results were checked before cleanup.

This fixture shows the two-phase procedure functioning, with no seeded material-detection regression. It does not show lower cost or broader quality superiority. Initial rollout remains explicit; ordinary reviews are not automatically standardized onto this workflow.

## Independent review and completion

Initial full implementation Advisor slice: CLEAR at `85b7164aadc58cb5f97cb3a4538b9a8fda1d36b3`, all four files and fixed policy dependencies covered; no material findings. Advisor supports retaining the supplementary validator failure as a schema limitation rather than claiming host incompatibility or rewriting an unrelated validator. Final candidate receives fresh full independent review after routing clarification and this measurement record.

Implementation commits remain separate semantic units; no amend, fixup, autosquash, force push or destructive rewrite is required. Runtime's toy-history construction preserves original refs and verifies tree equality; it is not a rewrite of this PR's branch. Required implementation tests pass via the existing concrete interpreter. Negative tests intentionally stop at defective/missing-evidence candidates; no production defect is accepted through them. External operations occur only after final validation and review, followed by one branch push and a PR linked to Issue #138; merge and Issue close remain excluded.
