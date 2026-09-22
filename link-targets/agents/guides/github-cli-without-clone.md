# clone せずに GitHub リポジトリの内容を変更する

> **Maintenance note:** このガイドは GPT-Chat から参照される外部向け shared reference である。repository 内の runtime caller が少なくても、未参照ファイルとして削除しない。

GitHub CLI (`gh`) を使い、`git clone` せずに GitHub 上のファイル、branch、commit、Pull Request を操作するときの実用ガイド。
GitHub service/API の normative contract は `link-targets/agents/guides/github.md` を優先し、この文書は操作方法のリファレンスとして扱う。

## 基本方針

対象を変数にすると再利用しやすい。

```bash
REPO="owner/repository"
BRANCH="main"
```

単一ファイルの作成・更新・削除には Contents API、複数ファイルを1コミットにまとめる場合は Git Data API を使う。
レビューを経る変更では、base branch を直接更新せず、topic branch を作って PR にする。

## ファイルを読む

raw content を取得する。

```bash
gh api \
  "repos/$REPO/contents/path/to/file?ref=$BRANCH" \
  -H "Accept: application/vnd.github.raw+json"
```

metadata や blob SHA が必要なら通常の JSON response を使う。

```bash
gh api "repos/$REPO/contents/path/to/file?ref=$BRANCH"
```

## 単一ファイルを作成・更新する

新規作成では `sha` は不要。更新では現在の blob SHA が必要。

```bash
SHA=$(gh api "repos/$REPO/contents/path/to/file?ref=$BRANCH" --jq '.sha')
CONTENT=$(base64 < /tmp/new-file | tr -d '\n')

gh api --method PUT \
  "repos/$REPO/contents/path/to/file" \
  -f message="Update file" \
  -f content="$CONTENT" \
  -f sha="$SHA" \
  -f branch="$BRANCH"
```

新規作成時は同じ PUT から `-f sha="$SHA"` を除く。
Contents API は1回の更新ごとに commit を作るため、複数ファイルを1コミットにしたい場合には向かない。

## ファイルを削除する

```bash
SHA=$(gh api "repos/$REPO/contents/path/to/file?ref=$BRANCH" --jq '.sha')

gh api --method DELETE \
  "repos/$REPO/contents/path/to/file" \
  -f message="Delete file" \
  -f sha="$SHA" \
  -f branch="$BRANCH"
```

同一 branch に対する Contents API の write は競合を避けるため逐次実行する。

## topic branch を作る

base branch の commit SHA から新しい ref を作る。

```bash
BASE_BRANCH="main"
TOPIC_BRANCH="docs/update-guide"

BASE_SHA=$(gh api "repos/$REPO/git/ref/heads/$BASE_BRANCH" --jq '.object.sha')

gh api --method POST \
  "repos/$REPO/git/refs" \
  -f ref="refs/heads/$TOPIC_BRANCH" \
  -f sha="$BASE_SHA"
```

以後の Contents API 操作では `BRANCH="$TOPIC_BRANCH"` を指定する。

## 複数ファイルを1コミットにまとめる

Git Data API を使い、現在の commit → base tree → new tree → new commit → ref update の順に進める。

```bash
COMMIT_SHA=$(gh api "repos/$REPO/git/ref/heads/$BRANCH" --jq '.object.sha')
TREE_SHA=$(gh api "repos/$REPO/git/commits/$COMMIT_SHA" --jq '.tree.sha')
```

既存 tree を保持したまま変更対象だけを置き換える。

```json
{
  "base_tree": "<TREE_SHA>",
  "tree": [
    {
      "path": "README.md",
      "mode": "100644",
      "type": "blob",
      "content": "New README"
    },
    {
      "path": "config/app.conf",
      "mode": "100644",
      "type": "blob",
      "content": "foo=bar"
    }
  ]
}
```

JSON を `/tmp/tree.json` に保存した場合:

```bash
NEW_TREE=$(gh api --method POST "repos/$REPO/git/trees" \
  --input /tmp/tree.json --jq '.sha')
```

commit object を作る。

```json
{
  "message": "Update multiple files",
  "tree": "<NEW_TREE>",
  "parents": ["<COMMIT_SHA>"]
}
```

`/tmp/commit.json` に保存した場合:

```bash
NEW_COMMIT=$(gh api --method POST "repos/$REPO/git/commits" \
  --input /tmp/commit.json --jq '.sha')

gh api --method PATCH \
  "repos/$REPO/git/refs/heads/$BRANCH" \
  -f sha="$NEW_COMMIT"
```

`base_tree` を省略すると既存ファイルを保持しない tree を意図せず作る可能性があるため、部分更新では必ず現在の tree を base にする。

## Pull Request を作る

topic branch に commit が存在する状態で:

```bash
gh pr create \
  --repo "$REPO" \
  --head "$TOPIC_BRANCH" \
  --base "$BASE_BRANCH" \
  --title "Update configuration" \
  --body "Update configuration without cloning the repository."
```

repository に PR template がある場合は、その構成とチェック項目を保持する。

## 使い分け

| 目的 | 推奨手段 |
| --- | --- |
| ファイルを読む | `gh api` Contents API |
| 1ファイルを作成・更新・削除 | Contents API |
| 数ファイルを変更し、commit が分かれてよい | Contents API を逐次実行 |
| 複数ファイルを1コミットにする | Git Data API |
| レビューを経て反映する | topic branch → API write → PR |
| 大量変更、build、test、複雑な差分確認 | local checkout / `git clone` |

## 注意事項

- write には対象 repository への適切な権限が必要。
- `.github/workflows` など一部の path では追加権限が必要になる場合がある。
- branch protection や ruleset がある場合は、その制約に従う。
- API write 前に対象 repository、branch、path、現在の SHA を確認する。
- timeout や不明応答の直後に write を再送せず、remote state を read-back して結果を確認する。
- 大量変更やローカルでの build/test が必要な作業では、clone / checkout の方が単純で安全なことが多い。

## 公式リファレンス

- GitHub CLI: [`gh api`](https://cli.github.com/manual/gh_api)
- GitHub REST API: [Repository contents](https://docs.github.com/en/rest/repos/contents)
- GitHub REST API: [Git references](https://docs.github.com/en/rest/git/refs)
- GitHub REST API: [Git trees](https://docs.github.com/en/rest/git/trees) / [Git commits](https://docs.github.com/en/rest/git/commits)
- GitHub CLI: [`gh pr create`](https://cli.github.com/manual/gh_pr_create)
