# Modify the contents of a GitHub repository without cloning

> **Maintenance note:** This guide is an external shared reference referenced by GPT-Chat. It does not require an activation path in the repository runtime; its registration under `external_consumers` in `reference-map.json` is treated as the reason for keeping it.

A practical guide to working with files, branches, commits, and pull requests on GitHub using the GitHub CLI (`gh`) and without `git clone`.
The GitHub service/API normative contract prioritizes `link-targets/agents/skills/github/SKILL.md`, and this document is treated as a reference for operating methods. External write authorization follows `link-targets/agents/skills/external-operation-authorization/SKILL.md`. GitHub token / repository permission and the semantic authorization boundary granted by the user are treated as different things.

## Basic policy

Making the target a variable makes it easier to reuse.

```bash
REPO="owner/repository"
BRANCH="main"
```

Use the Contents API to create, update, or delete a single file, and use the Git Data API to combine multiple files into one commit.
For changes that go through review, create a topic branch and make it a PR instead of updating the base branch directly.

## Read file

Get raw content.

```bash
gh api \
  "repos/$REPO/contents/path/to/file?ref=$BRANCH" \
  -H "Accept: application/vnd.github.raw+json"
```

If you need metadata or blob SHA, use regular JSON response.

```bash
gh api "repos/$REPO/contents/path/to/file?ref=$BRANCH"
```

## Create/update a single file

`sha` is not required for new creation. Update requires current blob SHA.

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

When creating a new file, remove `-f sha="$SHA"` from the same PUT.
The Contents API creates a commit for each update, so it is not suitable if you want to combine multiple files into one commit.

## Delete file

```bash
SHA=$(gh api "repos/$REPO/contents/path/to/file?ref=$BRANCH" --jq '.sha')

gh api --method DELETE \
  "repos/$REPO/contents/path/to/file" \
  -f message="Delete file" \
  -f sha="$SHA" \
  -f branch="$BRANCH"
```

Execute Contents API writes to the same branch sequentially to avoid conflicts.

## Create a topic branch

Create a new ref from the base branch's commit SHA.

```bash
BASE_BRANCH="main"
TOPIC_BRANCH="docs/update-guide"

BASE_SHA=$(gh api "repos/$REPO/git/ref/heads/$BASE_BRANCH" --jq '.object.sha')

gh api --method POST \
  "repos/$REPO/git/refs" \
  -f ref="refs/heads/$TOPIC_BRANCH" \
  -f sha="$BASE_SHA"
```

Specify `BRANCH="$TOPIC_BRANCH"` in subsequent Contents API operations.

## Combine multiple files into one commit

Using Git Data API, proceed in the order of current commit → base tree → new tree → new commit → ref update.

```bash
COMMIT_SHA=$(gh api "repos/$REPO/git/ref/heads/$BRANCH" --jq '.object.sha')
TREE_SHA=$(gh api "repos/$REPO/git/commits/$COMMIT_SHA" --jq '.tree.sha')
```

Replace only the changes while keeping the existing tree.

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

If you save JSON to `/tmp/tree.json`:

```bash
NEW_TREE=$(gh api --method POST "repos/$REPO/git/trees" \
  --input /tmp/tree.json --jq '.sha')
```

Create a commit object.

```json
{
  "message": "Update multiple files",
  "tree": "<NEW_TREE>",
  "parents": ["<COMMIT_SHA>"]
}
```

If saved to `/tmp/commit.json`:

```bash
NEW_COMMIT=$(gh api --method POST "repos/$REPO/git/commits" \
  --input /tmp/commit.json --jq '.sha')

gh api --method PATCH \
  "repos/$REPO/git/refs/heads/$BRANCH" \
  -f sha="$NEW_COMMIT"
```

If `base_tree` is omitted, a tree that does not hold existing files may be unintentionally created, so be sure to use the current tree as the base for partial updates.

## Create a pull request

With a commit on topic branch:

```bash
gh pr create \
  --repo "$REPO" \
  --head "$TOPIC_BRANCH" \
  --base "$BASE_BRANCH" \
  --title "Update configuration" \
  --body "Update configuration without cloning the repository."
```

If there is a PR template in the repository, retain its configuration and check items.

## Choosing a method

| Purpose | Recommended method |
| --- | --- |
| Read file | `gh api` Contents API |
| Create/update/delete 1 file | Contents API |
| Change several files where separate commits are acceptable | Execute Contents API sequentially |
| Combining multiple files into one commit | Git Data API |
| Reflect after review | topic branch → API write → PR |
| Mass changes, build, test, complex difference checking | local checkout / `git clone` |

## External write authorization and read-back

Contents API, ref update, Git Data API, and PR creation are each treated as independent logical operations. Immediately before each write, confirm that the target repository/resource, operation, semantic content, destination, acting principal, account, and permissions are within the authorization boundary granted by the user.

Instead of treating it as complete just by a successful response, check the external effects by reading back the remote state corresponding to the logical operation, such as the target file SHA, ref SHA, commit, PR, etc. For timeout and unknown responses, the outcome is ambiguous, and the same write is not retransmitted until it is confirmed that it has not been applied. Do not retransmit successful logical operations.

The details of authorization boundary recording, consumption, retry budget, ambiguous outcome, and post-operation recording are defined canonically in `link-targets/agents/skills/external-operation-authorization/SKILL.md` and are not duplicated in this guide.

## Precautions

- write requires appropriate permissions to the target repository. This is checked separately from the user's authorization for external operations.
- Some paths, such as `.github/workflows`, may require additional privileges.
- If there is a branch protection or ruleset, follow its restrictions.
- Check the target repository, branch, path, and current SHA before API write.
- Do not resend write immediately after timeout or unknown response, read-back the remote state and check the result.
- For tasks that require large-scale changes or local build/test, clone/checkout is often simpler and safer.

## Official reference

- GitHub CLI: [`gh api`](https://cli.github.com/manual/gh_api)
- GitHub REST API: [Repository contents](https://docs.github.com/en/rest/repos/contents)
- GitHub REST API: [Git references](https://docs.github.com/en/rest/git/refs)
- GitHub REST API: [Git trees](https://docs.github.com/en/rest/git/trees) / [Git commits](https://docs.github.com/en/rest/git/commits)
- GitHub CLI: [`gh pr create`](https://cli.github.com/manual/gh_pr_create)
