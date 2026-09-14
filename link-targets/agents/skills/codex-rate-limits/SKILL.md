---
name: codex-rate-limits
description: Read Codex Desktop rate-limit reset times and available reset-credit expirations in Japan time. Use only for an explicit request to inspect Codex usage limits; Windows Codex Desktop only.
---

# Codex-only execution gate

このスキルは Windows 版 OpenAI Codex Desktop 専用です。Claude Code、他のエージェント、CLI、IDE、クラウド環境では実行しないでください。実行環境を確認できない場合は停止してください。

自然言語の指示だけをセキュリティ境界として扱わず、必ず同梱スクリプト自身の実行環境検査を通してください。`--force`、環境変数、設定ファイルでガードを回避しないでください。

## 実行

明示的なスキル呼び出しのときだけ、次の固定スクリプトを実行してください。

```powershell
& "$env:USERPROFILE\.agents\skills\codex-rate-limits\scripts\read_codex_rate_limits.ps1"
```

スクリプトは実行可能な Codex Desktop の署名付き同梱 `codex.exe` を探索し、スキル配置から Codex ホームを検証したうえで app-server を起動します。親プロセスの環境変数や認証ファイルを直接読み取ったり、変更したりしないでください。

app-server へ送信してよい要求は固定されています。

1. `initialize`
2. `initialized` 通知
3. `account/rateLimits/read`

任意のRPCメソッド、引数、実行ファイル、app-server引数を追加しないでください。`account/rateLimitResetCredit/consume` を含むリセット、消費、交換、ログイン、設定変更系の操作は絶対に呼び出さないでください。

## 出力

スクリプトの整形済み出力だけを使用してください。通常利用枠とリセットクレジットを別区分で表示します。

- 通常利用枠は `rateLimitsByLimitId` を優先し、なければ `rateLimits` を使用する。
- 各枠の `primary` と `secondary` の `resetsAt` を日本時間（JST、UTC+09:00）で表示する。
- `rateLimitResetCredits.availableCount` を利用可能総数として表示する。
- `credits` が提供されている場合は、各 `expiresAt` を日本時間で一覧する。
- 詳細件数が `availableCount` より少なくても、取得できた詳細だけを表示し、総数との差を明示する。
- `null`、空配列、欠落フィールド、不正な時刻は推測せず「未提供」「詳細0件」「変換不可」などと表示する。
- credit ID、アカウントID、メールアドレス、トークン、生JSON、stderrを表示しない。

## 安全と失敗時の扱い

Codex Desktop の同梱実行ファイルを特定できない、署名が検証できない、候補が複数ある、`initialize` の `codexHome` が期待値と一致しない、認証が必要、またはタイムアウトした場合は、アカウント照会を成功扱いにせず停止してください。PATH上の独立CLI、ダウンロードしたCLI、同梱実行ファイルのコピーへフォールバックしないでください。

このスキルは読み取り専用ですが、app-server内部のログや認証状態更新まで一切発生しないことは保証しません。スキル自身はファイル出力、キャッシュ、認証情報の保存を行いません。

実行後にリセット権が減っていないか確認するため、リセット操作を実行してはいけません。
