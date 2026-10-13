# Evaluation notes

These are optional notes for a future evaluation, not runtime instructions or
an instruction to start experiments. They do not change the skill's invocation,
approval, or installation contracts.

## Establish a useful failure case

A practical starting point is an observed loss of a decision, constraint, or
pending step during ordinary work. Record what was available before the
boundary, what became unavailable afterward, and the resulting incorrect action
or rework. Check whether repository files, an Issue, or other ordinary task
records already allow recovery before attributing a benefit to a separate memo.

An artificially shortened context or an injected summary can explore failure
modes, but does not establish that the host's normal compaction loses the same
information. Process restart, session resume, and native compaction are also
different conditions. Preserve host evidence of the boundary actually tested;
a successful compact request alone does not demonstrate a completed boundary.

## Check whether the comparison happened

For a memo condition, verify before the relevant boundary that the memo was
created, populated with the intended state, and updated as the task progressed.
Giving a memo instruction or leaving a template in place is not evidence that
the treatment occurred. If it did not occur, report the comparison as invalid
even when the task itself finished successfully.

Distinguish a manually maintained memo from the complete skill and installed
hooks. Results from one do not validate the others. Compare equivalent task
inputs and recovery opportunities, recording any extra prompts or reminders;
a condition that receives additional task information changes the comparison.

## Interpret the outcome narrowly

Final code correctness can miss a lost pending state, skipped verification, or
forgotten approval boundary. Observe ordinary task actions as well as the final
artifact. A probe that restates a forgotten requirement can repair the very loss
being measured, so distinguish behavior before that probe from behavior after it.

Equal scores in a limited sample mean no added benefit was observed under those
conditions. They do not prove equivalence or that continuity protection is
unnecessary. Conversely, a synthetic failure alone does not establish practical
need. A reproducible failure and recovery attributable to the memo provide a
more useful basis for reassessment.

Historical plans, results, and their limitations are recorded in
[Issue #135](https://github.com/the9ball/.dotfiles/issues/135). Model choices,
versions, commands, environment setup, and measured scores belong in the dated
experiment record rather than in these notes.
