# 用途別ガイド

特定の作業に入るときだけ読む詳細な指針を置くディレクトリ。

`~/.dotfiles/.agents/AGENTS.md` は全作業で常時読み込まれるため、項目を増やすほど個々の指示の遵守率が下がる。そのため、常時必要ではない詳細はここへ切り出し、AGENTS.md 側には発動条件と最小限の核だけを残す。

## 置き方の規約

- ファイル名は ASCII の kebab-case にする。
- shared reference として維持する各ファイルは、`.agents/reference-map.json` に分類、参照元、参照目的、解決パスを登録する。`inbound_required` が true のファイルは、少なくとも一つの AGENTS.md、Skill、または host integration から参照されていなければならない。
- 各ファイルは AGENTS.md、Skill、または host integration のいずれかから発動経路を持つこと。参照のないファイルは読まれない。
- AGENTS.md と矛盾する内容を書かない。矛盾する場合は AGENTS.md が優先される。
- AGENTS.md 側には、このディレクトリのファイルを読まなくても最低限機能する核を残す。読み込みが行われなかった場合に効果がゼロになる構成にしない。

## 参照パス

- shared reference の本文から別のファイルを参照するときは、repository root 基準の論理相対パス（例：`.agents/guides/<name>.md`）を使う。
- Skill の位置を基準にした`../../`や、ホスト固有の絶対パスを shared reference の本文へ書かない。host integration は実行時に repository root を解決してから論理相対パスを使う。
- host integration または Skill が repository root を解決するときは、Skill tree の祖先をたどって`.agents/reference-map.json`を見つけ、map所在ディレクトリから JSON の`repository_root`を解決する。mapが見つからない、JSONを構造として読めない、または解決先が存在しない場合は停止する。現在の作業ディレクトリやホスト固有の絶対パスを暗黙の基準にしない。
- repository-root 相対パスを Markdown のリンク先にする場合は、リンク元から実際に解決できるファイル相対先を使う。論理パスを表示するだけの場合は code span を使い、ネストしたファイルから解決不能な root-relative destination を作らない。
- `.agents/tools/validate-reference-map.py`を明示的な Python 3 実行で呼び出し、参照先不存在、caller 0件、循環参照を検出する。検証に失敗した状態で参照経路を移行しない。
- reference map の edge は既定で読み込み依存として循環検査する。単なる手動ナビゲーションリンクは`acyclic: false`を付け、読み込み依存と混同しない。
