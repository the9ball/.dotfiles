# 用途別ガイドと共有契約

Skill discovery 後に読み込む詳細な指針と、Skill が条件付きで解決する共有契約を置くディレクトリ。移行済み workflow の normative runtime contract は対応する `SKILL.md` の `## Guide` section が所有し、このディレクトリを Skill からロードする構造にはしない。

`~/.dotfiles/link-targets/agents/AGENTS.md` は全作業で常時読み込まれるため、項目を増やすほど個々の指示の遵守率が下がる。そのため、常時必要ではない詳細は対応 Skill の discovery metadata と runtime Guide section へ切り出し、AGENTS.md 側には policy kernel だけを残す。

第一陣で移行した runtime contract は対応する Skill の `## Guide` section を唯一の正本とする。Claude Code の自然言語 discovery が Issue #75 で検証されるまで、旧 guide path は `reference-map.json` の `compatibility_fallbacks` registry に一時的な shim として登録し、tracked な global Claude host layer (`chezmoi/dot_claude/CLAUDE.md`) から到達可能にする。shim は Skill への到達経路だけを持ち、runtime contract を複製しない。#75 完了後に shim と host fallback を削除し、retired path 検査へ戻す。

## 置き方の規約

- ファイル名は ASCII の kebab-case にする。
- shared reference として維持する各ファイルは、`link-targets/agents/reference-map.json` に分類、参照元、参照目的、解決パスを登録する。`inbound_required` が true のファイルは、少なくとも一つの AGENTS.md、Skill、または host integration から参照されていなければならない。
- 各ファイルは AGENTS.md、Skill、または host integration のいずれかから発動経路を持つこと。参照のないファイルは読まれない。Skill の runtime contract は Skill 自体に完結させ、Skill から旧 guide をロードする構造は残さない。移行期間の host fallback shim は、逆方向に Skill を指す compatibility edge として明示する。
- `*.design.md` は対応する normative / runtime contract の複製や変更履歴ではなく、将来の選択肢、再検討材料・条件、責務境界などの非規範 design companion とする。通常 runtime ではロードせず、companion を持つ Skill の contract を変更・再設計・review するときだけ参照する。
- AGENTS.md と矛盾する内容を書かない。矛盾する場合は AGENTS.md が優先される。
- AGENTS.md 側には、このディレクトリのファイルを読まなくても最低限機能する核を残す。読み込みが行われなかった場合に効果がゼロになる構成にしない。

## 参照パス

- `instruction root` は、共有 instruction tree の canonical source と`link-targets/agents/reference-map.json`を含む repository の root を指す。このリポジトリでは`.dotfiles`がその root である。
- `work root` は、現在の依頼で変更・レビューする対象 repository の root を指す。Git の対象、差分、target identity、dirty state は instruction root から導出せず、依頼と現在の Git 状態から別途固定する。
- shared reference の本文から別のファイルを参照するときは、instruction root 基準の論理相対パス（例：`link-targets/agents/guides/<name>.md`）を使う。
- Skill の位置を基準にした`../../`や、ホスト固有の絶対パスを shared reference の本文へ書かない。host integration は実行時に instruction root を解決してから論理相対パスを使う。
- host integration、AGENTS.md、または Skill が instruction root を解決するときは、読み込まれたファイルまたは Skill の symlink / junction を実体パスへ解決してから、その実体パスの祖先をたどって`link-targets/agents/reference-map.json`を見つけ、map所在ディレクトリから JSON の`repository_root`を解決する。mapが見つからない、JSONを構造として読めない、または解決先が存在しない場合は停止する。現在の作業ディレクトリやホスト固有の絶対パスを暗黙の基準にしない。
- instruction-root 相対パスを Markdown のリンク先にする場合は、リンク元から実際に解決できるファイル相対先を使う。論理パスを表示するだけの場合は code span を使い、ネストしたファイルから解決不能な root-relative destination を作らない。Skill は自身の `## Guide` を normative source とし、guide path を runtime loader として参照しない。
- `link-targets/agents/tools/validate-reference-map.py`を明示的な Python 3 実行で呼び出し、参照先不存在、caller 0件、循環参照、Skill discovery metadata、compatibility fallback の単一 owner、retired path の不正な残存を検出する。検証に失敗した状態で参照経路を移行しない。
- reference map の edge は既定で読み込み依存として循環検査する。`acyclic: false` は、validator が allowlist する非依存 edge にだけ、`acyclic_reason` と併せて指定する。現在許可する組み合わせは、`reference-index` / `manual-navigation`、`host-reference` / `manual-navigation`、および常時適用 kernel への優先関係を記録する `policy-reference` / `policy-precedence` である。`workflow-reference`、`contract-reference`、`policy-routing`、`conditional-reference` などの読み込み依存は除外せず、循環があれば依存関係を整理する。

## 分類の用途

- reference map の`classification`は、既存資産の棚卸しとレビュー範囲を示す inventory metadata であり、Skill 発動、モデル抑制、権限、承認、安全ゲートの認可情報として扱わない。
- model-scaffolding の抑制や遅延ロードを追加する場合は、classification だけで判断せず、明示的な model / capability profile、混在条項の分離、代表タスクの比較実験を別途用意する。repository、safety、approval、secret、Git、ユーザー変更保護はモデル条件から独立させる。
