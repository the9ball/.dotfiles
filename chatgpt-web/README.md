# ChatGPT Web カスタム指示

ChatGPT Web には、GitHub 上で管理する [custom-instructions.md](custom-instructions.md) を読み込むための短い指示だけを設定します。実際のカスタム指示の正本は `custom-instructions.md` です。

## ChatGPT Web に設定するテキスト

以下のコードブロックを ChatGPT Web のカスタム指示欄にコピーしてください。

```text
Read https://github.com/the9ball/.dotfiles/blob/master/chatgpt-web/custom-instructions.md and follow its instructions for this conversation. If you cannot retrieve the file, do not assume its contents; tell me that the instructions could not be loaded.
```

## 設定・更新手順

1. ChatGPT Web の設定から **パーソナライズ → カスタム指示** を開きます（画面上の名称は変更される場合があります）。
2. 上記コードブロックの内容をコピーしてカスタム指示欄に貼り付け、保存します。
3. 今後は原則として `custom-instructions.md` の変更をGitHubの `master` に反映するだけでよく、読み込み先URLを変更しない限り、Web側の指示を書き換える必要はありません。

**注意:** ChatGPT Web が外部ファイルを自動で取得・再取得することは保証されません。会話ごとに読み込みが行われるか、取得に失敗した場合の挙動は実環境で確認してください。取得できない場合、正本の内容を推測して適用しないよう、上記の指示で明示しています。

個人情報、トークン、秘密情報、ホスト固有の絶対パスは正本に記載しないでください。Skill の詳細な動作規約は各 `SKILL.md`、エージェント共通規約は `AGENTS.md` が正本です。
