# rigorous-review Cost optimization and follow-up notes

This is a handover memo managed by Git, and is not the original implementation plan. Detailed methods, target runtimes, dependencies, budgets, and acceptance conditions will be reviewed at the start of each phase.

## Current status (2026-09-05)

The old measurement implementation of Phase A was saved in the Git history `2342b5e9f251761a117c39a22e51e524e7867fcf` as an observe-only study result, but it has been deleted from the current tree. Normal operation uses legacy strict flow without measurement. If you wish to restart Phase A/E in the future, do not restore the old implementation as is, but reconfirm the schema, runtime, and best practices at that time before redesigning. Phases B to D have not been applied.

Restarting Phase B requires a guaranteed runtime boundary that covers all dispatch paths, or a design decision to limit all role dispatch to a single harness.

## Future Phase

- Phase A (Measurement): Maintain measurement contracts for execution costs and output, and prepare comparable fixtures and actual measurements.
- Phase B (preflight/epoch): Establish physical verification and dispatch boundaries before starting role, confirm owner and fail-closed conditions.
- Phase C (packet/JCS): Define the packet schema, contents/path boundaries, and JCS method according to the implementation that can be verified at that time.
- Phase D (budget/delta): Design a budget checkpoint and differential ledger to maintain stop/restart/approval history.
- Phase E (comparison/go-no-go): Compare legacy and candidate methods in separate engagements, confirm quality, evidence coverage, and cost, and then decide on default.
