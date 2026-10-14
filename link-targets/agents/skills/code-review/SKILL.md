---
name: code-review
description: Run an explicitly requested two-phase code review with independent sequential open-ended and checklist reviewers. Do not replace ordinary reviews automatically. Also handle explicit maintenance of this review checklist.
disable-model-invocation: true
---

# Two-phase code review

Use only when the user explicitly requests `code-review`, `/code-review`, `$code-review`, or this two-phase method. Checklist maintenance is a separate explicit mode. This review supplies evidence, not permission to edit, publish, accept risk, or bypass existing Advisor and execution gates.

## Root and reviewer boundaries

Root fixes the target and coordinates; reviewers are independent read-only children. Root must not open, search, embed, or preload [checklist.md](checklist.md) or [checklist-maintenance.md](checklist-maintenance.md) during a review. Pass their resolved locations, never their contents. Phase 1 must not read either file. Phase 2 reads only the checklist; the maintenance guide is read only by an explicitly requested maintenance worker. Do not preload these references through a host's child-skill loading feature.

The isolation rule concerns this review invocation. When reviewing changes to this Skill itself, give the changed checklist and maintenance guide to a separate independent implementation reviewer, outside the runtime Phase 1. A runtime Phase 1 still excludes their bodies and records that exclusion; it cannot claim coverage of those files. Root confirms coverage from the separate implementation review without loading the bodies.

Resolve the loaded entrypoint's final real path using the reference-path procedure in `link-targets/agents/guides/README.md`, then resolve the two references inside this Skill directory and verify containment and existence without reading their bodies. Fix the work repository separately. Stop on an inaccessible or ambiguous source.

Use the host's available native child mechanism with a fresh, non-inherited context for each phase's first dispatch. A Codex native review child is distinct from the user-visible investigation-task workflow; do not substitute one silently if that workflow was requested. Codex children use a read-only behavior contract; do not claim a separate OS sandbox. Claude children use a new non-fork Agent context and only required read tools; CLI probes may supply temporary agent definitions within an authorized output directory. Do not install persistent agent definitions or change host settings for ordinary review.

Honor externally selected model and effort independently under the existing delegation contract. Inherit unspecified fields where supported, otherwise retain host defaults. Record requested settings and runtime-confirmed effective settings separately. Unsupported explicit settings, missing tools, failed startup, or unverifiable independence stop the affected review; never silently substitute a model, route, or self-review. Children must not edit, commit, change settings, publish, launch other children, or expand permissions.

## Fix the review input

Before dispatch, record a small request/result record in the existing task output or an authorized local artifact; no dedicated ledger framework is required:

- Work root, requirements and acceptance criteria, fixed base SHA and candidate SHA/tree or reproducible content manifest, and comparison definition (for a PR, its fixed merge-base diff).
- The complete change inventory, including modes, additions, removals, renames, binary/gitlink changes and explicitly included dirty/untracked files. Record excluded pre-existing changes and ignored files. A commit hash alone does not identify dirty content.
- Verification commands, required coverage, existing results and their versions/configuration/dependencies, unavailable checks, and editing authorization. Review does not grant editing authority.
- Role, fresh/reused context identity, model/effort source, read boundaries, and stop budget. Reuse a child only under the existing revision-bound delegation rules; its old verdict never automatically covers new content.

Send a self-contained request with the goal, requirements, target identity, full change inventory, complete diff or a verifiable retrieval method, permitted surrounding repository context, exclusions, read-only constraints, expected result, and stop conditions. Both phases need the entire base-to-candidate change set, not merely the latest fix. Avoid truncated terminal output: retrieve in bounded per-file chunks, match inventory and target identities before/after capture, and explicitly inspect non-text changes. Missing coverage or changed identity is `NEEDS_EVIDENCE`, never clean.

Do not include the other phase's findings, checklist text, suspected answers, or prior review conclusions in either phase's initial request. Requirements and factual verification evidence may be shared. Root can subsequently request a targeted correction check with the finding and changed scope.

## Phase 1: open-ended review

1. Dispatch an independent child for a free review of the entire permitted change set, with necessary repository context. Do not give it checklist guidance. Ask for concrete defect, severity/impact, location, requirement or failing scenario, supporting evidence, uncertainty, and actual coverage. Separate material defects, minor quality issues and optional suggestions.
2. Root verifies evidence, merges duplicates by underlying defect, and classifies findings by impact. Material defects prevent convergence. Resolve ambiguity with Advisor when required by existing rules; root retains the classification decision. Minor issues can be deferred to Phase 2 when covered there, or separately recorded; they are not hidden as clean. Optional preferences alone do not require another iteration.
3. An authorized implementer fixes accepted findings. During convergence, review existing findings, the correction diff, affected callers/invariants and necessary dependency boundaries. Re-execute invalidated checks. Record resolved, unresolved, rejected-with-evidence, deferred-minor, and optional findings distinctly.
4. After material findings first reach Clean, perform one full open-ended review under the same criteria, covering the current complete base-to-candidate difference. The initial review is not the post-Clean review. Do not omit it merely because targeted checks passed. Only an explicit scoped user waiver can omit it; record the omission rather than claiming it ran.
5. If this full review finds material defects, fix and verify them. For later local fixes, check the delta and its effects. For substantive control-flow, API, design, safety, or invariant changes, root decides whether another full review is necessary from the impact and records the rationale and coverage when not repeating it. Required re-review and unresolved defects cannot be converted to PASS by a round limit.
6. Before Phase 2, root verifies all required checks are valid for this candidate and that material findings and required re-reviews have converged.

## Phase 2: checklist review

Start only after Phase 1 convergence and its verification gate. Use another fresh context, without Phase 1 findings. Give it the resolved checklist location and the entire fixed base-to-final-candidate difference. It may inspect the repository to establish conventions or dependencies; evaluate only checklist criteria. Do not restart unrestricted free review or fix unrelated existing problems.

The child reports the checklist content identity, every active stable ID, applicability (`APPLICABLE`, `NOT_APPLICABLE`, `UNVERIFIED`), result (`PASS`, `FINDING`, `UNVERIFIED`, or `NOT_APPLICABLE`), reason, evidence/location, severity/impact, and actual changed-file coverage. Not applicable requires a reason; missing evidence is unverified. Root checks returned ID inventory/count and coverage against the child's version-bound attestation without reading the checklist. Missing IDs, incomplete diff coverage or unsupported PASS require evidence reacquisition.

- A minor meaning-preserving fix gets local verification of the changed text and affected IDs by the checklist reviewer, plus any invalidated automated checks. Preserve the whole-diff coverage record for unchanged content; do not imply a new full review ran.
- A material defect or change affecting behavior, API, design, safety or invariants returns to Phase 1. Fix, converge, perform necessary full review and verification, then dispatch Phase 2 for the revised full change set in an independent context. Record which checklist IDs require rechecking; prior judgments are version-bound.
- If a checklist observation reveals a possible material issue outside its evaluation scope, report the evidence to root for Phase 1 routing without expanding Phase 2 into free review.

Never update the checklist or read its maintenance guide during normal review. An explicit maintenance request dispatches a separate worker to the guide and checklist within authorized edit scope, followed by independent review and validation of the changed contract. Keep maintenance findings separate from the reviewed product's findings.

## Evidence, stop conditions and completion

At Phase 1 completion and again before final completion, root checks verification validity. A reusable result has the command, exit/result, scope, content identity, tool/configuration/dependency conditions, and an impact assessment proving intervening changes do not invalidate it. Reuse those results; rerun only invalidated checks. Whitespace checks do not prove lint, format or unit tests. Unknown version, skipped execution, failure or unavailable checks cannot become successful evidence. History-only reorganization may preserve content tests when tree/configuration identities match, but commit-granularity checks must be updated.

Stop as incomplete on startup/途中失敗 (interrupted execution), missing evidence, unresolved material defects, unverified applicable checklist IDs, invalid required checks, changed target, unsupported settings or stalled correction. Respect existing lifecycle limits; absent another agreed budget, two evidence-based fixes failing on the same finding trigger stop and escalation, not PASS. Record reason, impact, outstanding checks, and the smallest alternative evidence route. A user can change a verification requirement explicitly; report such a waiver separately from performed validation.

Completion requires full target coverage, material findings resolved, post-Clean full review and other required re-reviews complete, every checklist ID accounted for, no unresolved accepted minor finding (unless explicitly deferred with reason and impact), and valid required verification. Root reports base/candidate, inclusions/exclusions, classifications, correction and review coverage, validation reuse/reruns, remaining optional/deferred items and uncertainty. Separate review completion from existing execution/Advisor gates and external authorization.

For a comparison, use the same fixture, requirements and comparable externally selected settings in independent ordinary and two-phase runs. Judge known material-defect detection, severe misses, false positives and evidence quality before cost. Report review rounds, dispatch counts, tokens/cache and elapsed time only when observed, with measurement boundaries; label list-price calculations as estimates and unavailable billing/credits as unavailable. Do not standardize a quality regression on the strength of lower cost or a single small fixture.
