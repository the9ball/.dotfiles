# 第三者由来ファイルの通知

最終確認日: 2026-08-31

この文書は、リポジトリ内で確認できた第三者由来ファイルの出所とライセンス表示を記録するものです。リポジトリ全体へ一括してライセンスを付与するものではありません。出所またはライセンスが未確認の項目は、公開・再配布の許諾が確認できたものとして扱わないでください。

## Git の bash completion

対象: [`git-completion/git-completion.bash`](git-completion/git-completion.bash)

- ファイル先頭の表示は「GNU General Public License, version 2.0」です。
- Git の upstream にある completion スクリプトを、2026-08-13 の最新確認コミット `05e2ab1f31dd79ab6e17fc8f69a640ac8d0169d5` から取得しています。
- upstream（固定コミット）: <https://github.com/git/git/blob/05e2ab1f31dd79ab6e17fc8f69a640ac8d0169d5/contrib/completion/git-completion.bash>
- upstream（現行ブランチ）: <https://github.com/git/git/blob/master/contrib/completion/git-completion.bash>
- 2026-08-31 の確認では、ローカルファイルと固定コミットの内容・SHA-256（`D44CA9E259C05E1DFEBDAC7F005C50BD26D3771B2F83D68D3FCBED43A9AAAE2D`）が一致しました。
- ファイル内に取り込まれている `bash_completion` 部分は、別途「GPL version 2、または（選択により）それ以降」と表示されています。
- GPLv2 の本文と配布条件: <https://github.com/git/git/blob/master/COPYING>
- 配布時は、ファイル内にある両方の著作権表示・ライセンス表示を保持し、このファイルをリポジトリ全体のライセンス表示で上書きしないでください。

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
