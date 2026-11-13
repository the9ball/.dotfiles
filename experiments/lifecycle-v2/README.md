# Lifecycle v2: Git snapshot adapter review candidate

Adoption gate: **BLOCKED**. This experimental directory is a Draft PR review candidate. It does not install or modify active Skills, authorize real operations, dispatch reviews, replace authentication, or enable production use. An independent Advisor CLEAR and operational integration validation remain separate requirements.

## Component and security boundary

The adapter pins the Git image and a closed command vocabulary, sanitizes its child environment, and captures branch, HEAD, real index, status, known-file content and modes. capture_kernel.verify_pair rejects changes against both the expected baseline and the capture pair. Unknown files, unsupported structures, metadata links/reparse points and command failures fail closed. The adapter does not grant dispatch authority. The Coordinator remains simulation_only. Same-user malicious concurrent filesystem races and OS-enforced isolation are outside this profile.

The Windows Git location/image digest is an explicit supported-deployment constraint, not a portable auto-discovery mechanism. A different installation is unsupported until separately configured and reviewed; do not disable the digest check.

## Review scope and dependencies

Primary files: git_snapshot_adapter.py, test_git_snapshot_adapter.py, schema_worker_session.py, test_git_snapshot_advisor_fixes.py and verify_git_snapshot_interval1.py. All are under implementation/.

The accompanying kernel, strict-JSON helpers, reducer, simulation Coordinator/store, schema, worker and test modules are required import dependencies of this existing runner. They are supplied as unchanged supporting source, not a proposal to deploy lifecycle v2. In particular, the runner imports RecordedResult from verify_epoch11.py, which imports other existing test modules. Omitting those bodies would make the candidate's imports incomplete. No historical result directories, fixtures or databases are supplied. Do not run the standalone historical epoch/exploration entrypoints: they are included only because of the existing import graph.

## Validation already performed

See git-snapshot-review.md. Forty-one checks passed in the original isolated layout. These source copies are byte-identical to those inputs; the relocated review tree has not been executed. Passing results do not establish runtime authority or independently clear the three Advisor findings.

For a future validation, use the explicit Python interpreter, a fixed PowerShell image selected via LIFECYCLE_SCHEMA_PWSH, and only verify_git_snapshot_interval1.py. Its output argument must be a newly created unique directory under the review checkout's .local/lifecycle-v2-integration-results/git-snapshot/interval1/. The schema remains adjacent to implementation/ and no old result paths are required for these 41 tests. Test output, databases, logs and environment paths must remain untracked.

## Pending decisions

Independent re-review, validation of this relocated layout, actual authority/Git dispatch integration, real clock/guardian assumptions and operational recovery remain unapproved or unverified. The PR is for source inspection and discussion. Do not interpret publication or Draft PR creation as release or adoption approval.
