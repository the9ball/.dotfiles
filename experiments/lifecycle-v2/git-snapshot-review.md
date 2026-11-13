# Git snapshot review evidence summary

Adoption: **BLOCKED**. Independent Advisor re-review: pending.

The startup-notification fixture previously expected LF even though Python's ordinary text print emits CRLF on Windows. Only its expected expression changed to b"ready" + os.linesep.encode("ascii"). Exact byte comparison remains; no stripping, skips or relaxed timeout assertions were introduced. The focused failed check then passed.

| Suite | Executed | Passed | Failed/errors | Not run |
|---|---:|---:|---:|---:|
| Git adapter | 18 | 18 | 0 | 0 |
| Capture kernel | 11 | 11 | 0 | 0 |
| Advisor negative controls | 9 | 9 | 0 | 0 |
| Schema and safety-stop checks | 3 | 3 | 0 | 0 |
| Total | 41 | 41 | 0 | 0 |

The schema check covers all 24 event payloads, Draft2020-12 metaschema, unknown-field rejection and datetime format assertions. Main and invalid-schema validation used the same absolute PowerShell image and SHA256. Malformed schema failed as expected.

| Advisor finding | Counterexample and correction | Current evidence | Remaining |
|---|---|---|---|
| High: implicit Git metadata link reads | The old metadata junction affected file classification. Validate metadata paths and reparse ancestors before Git and recheck fixed controls. | info, refs and objects junction rejection plus original adapter suite passed. | Independent acceptance; malicious same-user races excluded. |
| Medium: unbounded worker/cleanup | Old response wait blocked and cleanup exceptions bypassed reporting. Bound exchange/owned shutdown; persist failure report. | Startup/reply timeouts, wait exception and unexpected close exception controls passed. | Independent acceptance; OS/storage failure is not guaranteed recoverable. |
| Medium: PowerShell identity mismatch | Old primary and PATH resolution could differ. Pin the same executable/image for both validations. | Hostile PATH and different-image rejection passed; actual negative engine identity matched main. | Independent acceptance; no claim of reproduced false-positive schema success on a second engine. |

These are author-reported results for the isolated source revision. They do not supersede the prior NEEDS_CHANGES verdict. Old raw logs, DBs, epoch snapshots, private review packets and host inventory are deliberately absent. The relocated candidate has not been rerun.
