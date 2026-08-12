---
name: git-history-rewrite
description: >
  `git rebase -i` を使わずに、コミット履歴の書き換え(並べ替え・squash・分割・drop・過去コミットの修正・
  ベース付け替え)を非対話で行う手順。cherry-pick による履歴リプレイ、目的別の最短手段の選択、
  `git range-diff` による書き換え結果の検証、元ブランチへの反映までを定める。
  「コミットをまとめたい」「順番を入れ替えたい」「途中のコミットを直したい」「rebase したい」
  「履歴を整理したい」といった依頼、および rebase 中のコンフリクト対応で参照する。
---

# Git History Rewrite (非対話)

`git rebase -i` はハーネス規約で使用禁止(対話エディタを開くコマンド)。
`GIT_SEQUENCE_EDITOR` / `sequence.editor` で todo を機械的に書き換える回避策も**使わない**
(規約の趣旨に反し、todo の書き換えミスが静かに履歴を壊すため)。
代わりに、目的に応じた非対話コマンドか、cherry-pick による履歴リプレイを使う。

## 手順の全体像

0. 事前確認 → 1. 手段の選択 → 2. 実行 → 3. 検証 → 4. 元ブランチへの反映 → 5. 後始末

検証(3)を省略してはならない。書き換えの事故は差分を見るまで気づけない。

## 0. 事前確認

```bash
git status --porcelain
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
git log --oneline --no-decorate <base>..HEAD
```

- 作業ツリーがクリーンでなければ、履歴書き換えを始めない。ユーザーに commit か stash を確認する。
- `git rev-parse HEAD` の出力(元の tip の SHA)を必ず控える。以降これを `<orig>` と呼ぶ。
  reflog だけに頼らない(手順の途中で見失うと復旧が面倒になる)。
- `<base>` は書き換えの起点。分からなければ `git merge-base HEAD origin/main` などで候補を出し、
  ユーザーに確認する。推測で決めない。
- 元ブランチが push 済みかどうかを確認する(`git rev-parse --abbrev-ref '@{upstream}'`)。
  push 済みなら、後の反映が force push を伴うことを先に伝える。

## 1. 手段の選択

cherry-pick リプレイは万能だが手数が多い。目的が下の表の上3行に収まるなら、そちらを使う。

| やりたいこと | 手段 |
|---|---|
| 直近1件のメッセージ・内容の修正 | `git commit --amend`(メッセージは `-m` で渡す) |
| 直近N件を1つにまとめる | `git reset --soft HEAD~N` + `git commit -m "..."` |
| ベースの付け替えのみ(順序・内容はそのまま) | `git rebase --onto <new-base> <old-base> <branch>` |
| 末尾以外のコミットの修正・並べ替え・分割・drop | cherry-pick リプレイ(手順2) |

`git rebase --onto` は非対話なので使ってよい。`-i` を付けてはならない。

## 2. cherry-pick リプレイ

```bash
# 一時ブランチをベースから作る(-C ではなく -c を使う)
git switch -c rewrite/<元ブランチ名> <base>

# 目的の順序で積み上げる
git cherry-pick <sha-a>
git cherry-pick <sha-b> <sha-c>
```

- **`-C` ではなく `-c` を使う。** `-C` は同名ブランチを強制的に作り直すため、前回の試行が
  黙って消える。既に存在してエラーになった場合は、中身を確認してからユーザーに扱いを確認する。
- 「`switch -C` してから `reset --hard <base>`」の2段構えは不要。`switch -c <一時ブランチ名> <base>` の
  1コマンドで足りる。ここで作るのは元ブランチとは別名の新しいブランチであり、元ブランチは動かないので、
  元の tip(`<orig>`)は失われない。

操作ごとの型:

- **drop**: その SHA を cherry-pick しない。
- **並べ替え**: cherry-pick の順序を変える。
- **squash**: まとめる範囲を `git cherry-pick -n <sha>...` でインデックスに重ね、最後に `git commit -m "..."`。
- **メッセージ変更**: `git cherry-pick <sha>` の後に `git commit --amend -m "..."`。
  `-e` / `--edit` はエディタを開くので使わない。
- **内容の修正**: 対象を cherry-pick した直後にファイルを編集し、`git add` + `git commit --amend --no-edit`。
- **分割**: `git cherry-pick -n <sha>` でコミットせずに取り込み、`git reset HEAD` で unstage してから、
  必要な塊ごとに `git add` + `git commit` を繰り返す。

## コンフリクト対応

```bash
git status                       # 衝突ファイルと進行状況
# ファイルを解決してから
git add <解決したファイル>
git -c core.editor=true cherry-pick --continue
```

- `cherry-pick --continue` は、元の cherry-pick に `-e` / `--edit` を付けていなければエディタを
  開かない(git 2.55 で確認済み。`core.editor=vim` でもハングしない)。上の `git -c core.editor=true` の
  前置は、`-e` を付けてしまった場合などに備えた保険。害はないので付けておく(これは todo の機械的
  書き換えとは別物で、単に停止を防ぐためのもの)。
- `git config --get rerere.enabled` が `true` なら、衝突解決が記録され同じ衝突に再遭遇したとき
  自動適用される。リプレイをやり直す可能性がある場合は、事前に有効化しておくと手戻りが軽くなる
  (グローバル設定の変更はユーザーに確認する)。
- **`git cherry-pick --skip` を自分の判断で使ってはならない。** コミットを丸ごと捨てる操作なので、
  意図した drop 以外では必ずユーザーに確認する。
- 解決方針が読めない衝突は、無理に解決しない。`git cherry-pick --abort` で一時ブランチを直前の
  状態に戻し(元ブランチは無傷)、衝突の内容をユーザーに報告して指示を仰ぐ。
- 残りの pick は `.git/sequencer/todo` で確認できる。

## 3. 検証(必須)

役割の違う2つの確認を両方行う。合否を機械的に判定できるのは前者だけで、後者は目で見るためのもの。

### 3-1. ツリー一致(合否ゲート)

並べ替え・squash・メッセージ変更のみで、最終的な内容が元と変わらないはずの場合:

```bash
git diff <orig> HEAD             # 出力が空であること
```

空でなければ、cherry-pick の取りこぼしか衝突解決のミス。反映に進まず、原因を特定してやり直す。

意図した drop / 内容修正を含む場合は空にならないので、出力がその意図した変更**だけ**であることを確認する。

### 3-2. コミット単位のレビュー

```bash
git range-diff <base>..<orig> <base>..HEAD
```

`=`(不変) / `!`(変化) / `<` `>`(片側のみ) の記号で、コミットの対応関係を確認する。見るべきは、
消したはずのコミットが消えているか、意図しないメッセージ変更が混じっていないか、分割が意図どおりの
粒度になっているか。

- **range-diff にコミット内容の差分が出ること自体は異常ではない。** 同じ箇所を触るコミットの順序を
  変えれば、最終ツリーが完全一致していても個々のコミットのパッチは変わる。差分の有無を合否判定に
  使ってはならない(合否は 3-1 で見る)。

検証結果は、書き換え前後のコミット一覧とあわせてユーザーに報告する。

## 4. 元ブランチへの反映

**この操作はユーザーの明示的な承認を得てから行う。** 承認前は一時ブランチのまま止める。

```bash
git branch -f <元ブランチ> HEAD
git switch <元ブランチ>
```

push 済みブランチの場合、push には必ず `--force-with-lease` を使う。素の `--force` は使わない。

```bash
git push --force-with-lease origin <元ブランチ>
```

push はユーザーから明示的に指示されたときだけ行う。検証が通っただけでは push しない。

## 5. 後始末

```bash
git branch -d rewrite/<元ブランチ名>
```

- 一時ブランチの削除は `-d`(マージ済みのみ削除)を使う。`-D` は使わない。
- 元ブランチや控えておいた `<orig>` は、ユーザーが結果を確認するまで参照可能なままにしておく。

## やってはならないこと

- `git rebase -i` の使用、および `GIT_SEQUENCE_EDITOR` / `sequence.editor` による todo の機械的書き換え。
- 検証(手順3)を飛ばして反映・push すること。
- ユーザー承認なしの `git branch -f` / `git push --force*` / `git reset --hard` / `cherry-pick --skip`。
- 作業ツリーが汚れた状態での履歴書き換え開始。
