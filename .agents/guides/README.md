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

- `instruction root` は、共有 instruction tree の canonical source と`.agents/reference-map.json`を含む repository の root を指す。このリポジトリでは`.dotfiles`がその root である。
- `work root` は、現在の依頼で変更・レビューする対象 repository の root を指す。Git の対象、差分、target identity、dirty state は instruction root から導出せず、依頼と現在の Git 状態から別途固定する。
- shared reference の本文から別のファイルを参照するときは、instruction root 基準の論理相対パス（例：`.agents/guides/<name>.md`）を使う。
- Skill の位置を基準にした`../../`や、ホスト固有の絶対パスを shared reference の本文へ書かない。host integration は実行時に instruction root を解決してから論理相対パスを使う。
- host integration、AGENTS.md、または Skill が instruction root を解決するときは、読み込まれたファイルまたは Skill の symlink / junction を実体パスへ解決してから、その実体パスの祖先をたどって`.agents/reference-map.json`を見つけ、map所在ディレクトリから JSON の`repository_root`を解決する。mapが見つからない、JSONを構造として読めない、または解決先が存在しない場合は停止する。現在の作業ディレクトリやホスト固有の絶対パスを暗黙の基準にしない。
- instruction-root 相対パスを Markdown のリンク先にする場合は、リンク元から実際に解決できるファイル相対先を使う。論理パスを表示するだけの場合は code span を使い、ネストしたファイルから解決不能な root-relative destination を作らない。
- `.agents/tools/validate-reference-map.py`を明示的な Python 3 実行で呼び出し、参照先不存在、caller 0件、循環参照を検出する。検証に失敗した状態で参照経路を移行しない。
- reference map の edge は既定で読み込み依存として循環検査する。単なる手動ナビゲーションリンクは`acyclic: false`を付け、読み込み依存と混同しない。

## 分類の用途

- reference map の`classification`は、既存資産の棚卸しとレビュー範囲を示す inventory metadata であり、Skill 発動、モデル抑制、権限、承認、安全ゲートの認可情報として扱わない。
- model-scaffolding の抑制や遅延ロードを追加する場合は、classification だけで判断せず、明示的な model / capability profile、混在条項の分離、代表タスクの比較実験を別途用意する。repository、safety、approval、secret、Git、ユーザー変更保護はモデル条件から独立させる。
