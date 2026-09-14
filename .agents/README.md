# OBSOLETE

このディレクトリは旧来の共有ツリーです。
正本は [`../link-targets/agents/`](../link-targets/agents/) へ移動しました。

既存参照が移行中に切れてエラーになることを避けるため、参照の切替完了まで一時的に残しています。
このディレクトリは編集せず、修正は `../link-targets/agents/` 側だけに行ってください。
旧ツリーとの二重編集・同期は行いません。
切替前に旧ツリーへ加えられた変更がある場合は、リンクを張り直す前に新しい正本へ手動で突合してください。切替後の rollback bridge として残す場合も、旧側は編集禁止です。

## runtime link / junction の張り直し

次のリンクを新しい正本へ変更します。

```text
~/.agents        -> repo/link-targets/agents
~/.claude/skills -> repo/link-targets/agents/skills
~/.claude/agents -> repo/link-targets/claude/agents
```

既存パスが symlink / junction であることを確認してから、各 OS の方法で既存リンクを削除し、新しい target を指定して作り直してください。
通常のファイルやディレクトリを自動的に削除・置換してはいけません。

chezmoi の管理スクリプトは target mismatch を自動修復しないため、runtime link / junction の張り直しを `chezmoi apply` より先に行います。
その後 `chezmoi diff`、`chezmoi apply`、`chezmoi verify --exclude=scripts` の順で確認します。

参照の移行と動作確認が完了したら、このディレクトリを削除します。
