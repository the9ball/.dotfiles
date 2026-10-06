# Fresh-context acceptance scenarios

These are manual contract checks, not proof that a particular runtime isolates context. Record actual runtime evidence and artifact comparison when exercising the skill.

| Scenario | Required behavior | Evidence to inspect |
| --- | --- | --- |
| Short source uses implicit agreements from conversation | Root fixes permitted inputs and dispatches a verified fresh child; length does not exempt isolation | Route, runtime context mode/session, verification basis, fixed inputs |
| Explicit full rewrite of a self-contained short source | Root execution is eligible when conversation context has no material effect and delegation adds no isolation benefit | Source and route rationale |
| Runtime lacks fresh-context support | Report the limitation and stop reconstruction for target-specific confirmation; no silent root/inherited fallback | Limitation and pending confirmation, or exact user override |
| Non-inheriting creation option exists but session history/isolation is unverifiable | Do not claim freshness from the option alone; report and stop for confirmation | Documented context behavior and session-history evidence, missing verification |
| Existing child contains another task's discussion | Do not reuse it as fresh; create a verified clean context with the permitted inputs | Previous session history, new session identity and fixed inputs |
| Same reconstruction continues with only permitted inputs | Reuse only when isolation, target/epoch, runtime identity, and authorization remain verified | Boundary check, session/epoch identity and material consultations |
| Root answers a narrow question with an unresolved proposal | Preserve the source/version or exact user input and unresolved status; map it to output or disposition | Ledger entry, returned evidence and output status |
| Root supplies a broad discussion history after dispatch | Stop treating the child as fresh and restart from curated inputs; keep prior artifacts as evidence, not authoritative restart source | Consultation, old artifacts, restart inputs and fresh verification |
| Source exists only as text in the conversation | Retain its exact text separately from surrounding discussion; pass it as a permitted source input | Exact comparison source and input boundary |
| Child reports success but output omits a condition or adds an approval | Root detects the discrepancy from actual source/output/ledger and withholds acceptance until resolved | Source-item mapping, certainty comparison and actual artifact differences |
| User explicitly selects root execution for one conversation-dependent target | Record the exact override and target; preserve all source/comparison/approval/permission rules | User instruction, scoped route exception, source/output/ledger verification |

Independent comparison is a step against the retained source and does not require a separate agent. Existing out-of-scope and stop conditions still apply to every scenario.
