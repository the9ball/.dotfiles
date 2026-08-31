# 第三者由来ファイルの通知

最終確認日: 2026-08-31

この文書は、リポジトリ内で確認できた第三者由来ファイルの出所とライセンス表示を記録するものです。リポジトリ全体へ一括してライセンスを付与するものではありません。出所またはライセンスが未確認の項目は、公開・再配布の許諾が確認できたものとして扱わないでください。

## GDB スクリプトの互換性

`gdbscript/dumpmap` と `gdbscript/stlcontainers` は、2012 年に追加された別々のスクリプトです。どちらも libstdc++ の非公開メンバ（`_M_impl`、`_M_rep`、`_M_value_field` など）の配置を直接参照しています。

GCC 5 では `std::string` と `std::list` を含む新しい C++11 ABI が導入されました。現在の libstdc++ では、C++11 用の木構造ノードや `std::string` の内部メンバも当時の前提と異なります。したがって、これらのマクロは現代のGCC/GDBで一部または全てが動作しない可能性があります。

- GCC の dual ABI の説明: <https://gcc.gnu.org/onlinedocs/gcc-8.5.0/libstdc%2B%2B/manual/manual/using_dual_abi.html>
- 現在の `std::_Rb_tree_node` の実装: <https://github.com/gcc-mirror/gcc/blob/master/libstdc%2B%2B-v3/include/bits/stl_tree.h>
- 現在の `std::basic_string` の実装: <https://gcc.gnu.org/onlinedocs/libstdc%2B%2B/latest-doxygen/a00515_source.html>

この環境ではGDB本体を検出できなかったため、実行時の互換性は未検証です。GDB/libstdc++ には標準コンテナ向けの Python pretty-printer が用意されているため、新しい環境ではそちらを優先し、これらのスクリプトはレガシー扱いで対象ツールチェーンごとに確認してください。<https://gcc.gnu.org/onlinedocs/libstdc%2B%2B/manual/debug.html>

## Git の bash completion

対象: [`git-completion/git-completion.bash`](git-completion/git-completion.bash)

- ファイル先頭の表示は「GNU General Public License, version 2.0」です。
- Git の upstream にある completion スクリプトを基にしたファイルです。
- upstream: <https://github.com/git/git/blob/master/contrib/completion/git-completion.bash>
- GPLv2 の本文と配布条件: <https://github.com/git/git/blob/master/COPYING>
- 配布時は、ファイル内の著作権表示・ライセンス表示を保持し、このファイルをリポジトリ全体のライセンス表示で上書きしないでください。

## STL 用 GDB マクロ

対象: [`gdbscript/stlcontainers`](gdbscript/stlcontainers)

- upstream source: <https://www.yolinux.com/TUTORIALS/src/dbinit_stl_views-1.03.txt>
- 2026-08-31 の確認では、ローカルファイルと上記ソースの内容・SHA-256が一致しました。
- 元ファイルは Dan Marinescu をマクロ作者、Anders Elton を変更者として記載し、ライセンス表示は `License GPL` までです。
- 元ファイルには GPL の版および `or later` の指定がありません。このリポジトリでは GPL の版を推測して補いません。
- 正確なライセンス版と再配布条件を確認できるまで、リポジトリ独自のライセンスを適用したり、再配布可能と断定したりしないでください。

## 追加の GDB マクロ

対象: [`gdbscript/dumpmap`](gdbscript/dumpmap)

- `dumpstlht`、`dumpvec`、`dumpstlrbt` などの別系統のコマンドを定義しています。
- ファイル内に著作権表示、ライセンス表示、外部出典の記載は確認できていません。
- `stlcontainers` と同じ Git コミットで追加されたことは、同一の出所・著作者・ライセンスを示すものではありません。
- 出所と再配布権限が確認できるまで、権利未確認のファイルとして扱います。

## サブモジュール

次のサブモジュールは、固定したコミットに Apache License 2.0 の `LICENSE` を含みます。

- `kube-ps1`: <https://github.com/jonmosco/kube-ps1/blob/52bd1ecf61a9640e743281efe3a66330e64b3574/LICENSE>
- `kubectx`: <https://github.com/ahmetb/kubectx/blob/c8393ea883fb241764d8d6ca2851685e1ad5fe02/LICENSE>

親リポジトリの gitlink だけを配布する場合、サブモジュールの実体と `LICENSE` は含まれません。再帰的に取得・配布する場合は、各サブモジュールのライセンスを維持してください。

## Agent Skills

次のローカル fork は、各ディレクトリの `PROVENANCE.md` と `LICENSE` に出所・ライセンスを記録しています。

- `cognitive-rhythm-writing`: <https://gist.github.com/k16shikano/eb2929f13ed19c97188393d297be8432>、Unlicense
- `japanese-tech-writing`: <https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d>、Unlicense
- `conversation-handoff`: <https://gist.github.com/tegnike/09dbb98711d8b91e66de21611f5b88ff>、MIT License

その他のローカル管理 skills については、2026-08-31 の追跡ファイル走査で逐語的な外部出典は見つかりませんでした。ただし、これは独自著作物であることの法的な証明ではありません。

gh-stack、Datadog、dotnet などの第三者 skill/plugin 本体はリポジトリへ vendor せず、ロックファイルと復元手順だけを管理しています。作業ディレクトリ全体をアーカイブする場合は、無視されている第三者実体が混入しないこと、および混入させる場合は upstream の `LICENSE`/`NOTICE` も含めることを確認してください。
