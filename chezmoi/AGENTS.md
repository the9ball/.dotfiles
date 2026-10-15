# chezmoi

## スクリプトの実行順序

- `.chezmoiscripts/run_before_00-aqua-policy`の`00-`は、ポリシー検証ガードを最初に実行するために予約する。PowerShell版とPOSIX版の両方を維持し、この名前より先に実行される`run_before`を追加しない。
- 新しい`run_before`（`run_once_before`、`run_onchange_before`を含む）には、`10-`、`20-`など10以上の2桁番号を付ける。スクリプト間に順序依存がある場合は、その依存と理由をコメントに明記する。
- `run_after`と`run_onchange_after`への一律の番号付けは要求しない。
