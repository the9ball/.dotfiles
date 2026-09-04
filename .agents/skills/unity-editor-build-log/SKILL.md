---
name: unity-editor-build-log
description: Windows Unity Editor.log から、最後に完了した Player Build または Script Compilation の区間を分類付きで安全に抽出する。
---

# Unity Editor build log

対象は既定の `C:\Users\syasui\AppData\Local\Unity\Editor\Editor.log` です。適用時は、root が読み取り専用のサブエージェントへ自己完結した調査を委譲し、サブエージェントが同梱スクリプトを実行して境界検出と切り出しを行います。root はログ全量を事前表示せず、サブエージェントが返した分類・境界・要約とマスク済み最新ブロックを検証してユーザーへ返します。

サブエージェントへの指示には、次を含めてください。

1. 固定対象 `C:\Users\syasui\AppData\Local\Unity\Editor\Editor.log` を読み取り専用で扱い、`C:\Users\syasui\.dotfiles\.agents\skills\unity-editor-build-log\scripts\extract-unity-build-log.ps1` を実行する。
2. 必要なら fixture 検証のためだけに `-LogFilePath` を指定する（実ログは変更せず、ファイルをロックしない）。
3. 分類、開始・終了行、結果、切り詰め有無、マスク済み最新ブロックを root に返す。秘密値を再掲せず、非ゼロ終了時はエラー概要だけ返して本文を推測しない。

実行例:

```powershell
& "C:\Users\syasui\.dotfiles\.agents\skills\unity-editor-build-log\scripts\extract-unity-build-log.ps1"
& "C:\Users\syasui\.dotfiles\.agents\skills\unity-editor-build-log\scripts\extract-unity-build-log.ps1" -LogFilePath .\Editor.log -MaximumOutputLines 10000 -MaximumOutputCharacters 500000
```

スクリプトは `FileShare.ReadWrite` の共有読み取りを使い、Player Build と Script Compilation を型付きイベントとして1回の前方走査で対応付けます。`BuildPlayerWindow` などスタックトレースのメソッド名、`##### Output`、`*** Tundra requires additional run` は開始・終端に使いません。最後の開始に対応する終了がなければ、古い成功結果へフォールバックせず「最新ビルド未完了」として非ゼロ終了します。境界が検出できない場合も本文を推測せず非ゼロ終了します。出力区間ではキー付きの access token、Bearer、password、secret、client_secret/clientSecret、Authorization、serial/license key、api key 等を `<redacted>` にマスクし、キーと値が改行された一般的な形式にも対応します。

出力には `総行数`、`読み取り時ファイル長`、`最終更新UTC`、およびスナップショット安定性を含めます。root が境界を検証する時点で対象ファイルの総行数・ファイル長・最終更新UTCのいずれかがスナップショットと一致しない場合、その抽出結果を採用せず同じスクリプトを再実行してください。入力サイズ上限を超えた場合や読み取り中にファイルが変化した場合も、ログ本文や例外本文を表示せず固定の日本語エラー分類だけを返します。

行数・文字数の上限に達した場合は、可能な範囲でブロックの先頭と末尾を残し、省略数と省略マーカーを出力します。
