---
name: unity-editor-build-log
description: Safely extract, with a classification, the last completed Player Build or Script Compilation interval from the Windows Unity Editor.log.
---

# Unity Editor build log

The target is Unity's standard Windows `Editor.log` under the current user's local application-data directory. When this skill applies, root delegates a self-contained investigation to a read-only subagent, which runs the bundled script to detect the boundaries and cut out the interval. Root does not display the whole log in advance; it verifies the classification, boundaries, summary, and masked latest block that the subagent returns, and then returns them to the user.

Include the following in the instructions to the subagent:

1. Treat the default Unity `Editor.log` resolved by the bundled script from the current user's local application-data directory as read-only, and run the bundled `scripts\extract-unity-build-log.ps1` from this Skill directory.
2. If necessary, specify `-LogFilePath` only for fixture verification (the real log is not modified, and the file is not locked).
3. Return to root the classification, the start and end lines, the result, whether it was truncated, and the masked latest block. Do not reprint secret values. On a non-zero exit, return only the error summary and do not guess at the body.

Execution example:

```powershell
& .\scripts\extract-unity-build-log.ps1
& .\scripts\extract-unity-build-log.ps1 -LogFilePath .\Editor.log -MaximumOutputLines 10000 -MaximumOutputCharacters 500000
```

The script uses shared reads (`FileShare.ReadWrite` and `FileShare.Delete`) and pairs Player Build and Script Compilation as typed events in a single forward scan. Even when events of the same kind are nested, the start position is kept on a stack, so the outer interval is not lost. Method names in stack traces such as `BuildPlayerWindow`, `##### Output`, and `*** Tundra requires additional run` are not used as a start or an end. If the last start has no matching end, the script does not fall back to an old successful result; it exits non-zero as "the latest build is incomplete" (`最新未完了`). If no boundary can be detected, it likewise does not guess at the body and exits non-zero. In the output interval, keyed access tokens, Bearer, password, secret, client_secret/clientSecret, Authorization, serial/license key, api key, and the like are masked as `<redacted>`, and the common form in which the key and the value are on separate lines is handled too.

The output includes the script's literal fields `総行数` (total lines), `読み取り時ファイル長` (file length at read time), `作成UTC` (creation time), `最終更新UTC` (last update time), `スナップショットSHA256` (snapshot hash), and `スナップショット安定` (snapshot stability). When root verifies the boundaries, if any of the target file's total line count, file length, creation time, last update time, or content hash differs from the snapshot, do not adopt that extraction result and run the same script again. If the input size limit is exceeded or the file changes while it is being read, the script does not display the log body or the exception body, and returns only a fixed Japanese error classification.

If the maximum number of lines or characters is reached, the script keeps as much of the beginning and end of the block as it can, and outputs the number of omitted items and an omission marker.
