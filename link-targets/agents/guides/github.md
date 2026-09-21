# GitHub service contract

GitHub service/API 上の Issue、Pull Request、review、comment、label、release、repository metadata などを read / write するときに適用する。
この guide は GitHub 操作一般の解説ではなく、共通規約と通常の GitHub 知識だけでは判断がぶれる GitHub service 固有事項だけを保持する normative contract である。一般的な authorization、approval request、external posting、write lifecycle、retry はそれぞれの責務を持つ共通 contract に委譲し、ここへ重複して追加しない。
この contract 自体を変更・再設計するときは [`github.design.md`](github.design.md) も参照する。

## Scope

- 対象は GitHub という外部 service/API 上の read / write である。
- Git repository / Git transport は、remote が GitHub でも対象外である。`git clone/fetch/pull/push` に加え、`gh repo clone`、`gh pr checkout` など実質的に Git transport / local checkout を主目的とする操作も、コマンド名ではなく操作の意味で分類する。
- GitHub service/API 操作の標準経路は、実行環境によらず公式 `gh` / `gh api` とする。host が別経路を提供していても、この contract の fallback または代替経路として Connector、MCP、app integration、browser、direct HTTP、別 CLI、別 account へ切り替えない。
- host 固有の integration workflow は、それ自体が明示的に採用された場合だけ別 workflow として扱う。この規則は各製品にその能力が存在しないことを意味しない。
- 本 guide は behavioral contract であり、host 側の permissions、hooks、managed settings 等による technical enforcement を定義しない。

## Access failure の診断

- 単発の `gh` access/auth/connectivity failure だけで永続的な credential failure と断定しない。
- 外部効果を伴わない GitHub access を同じ標準経路で 1 回 retry し、実効的な利用可能性を確認する。retry も失敗した場合は別経路へ fallback せず停止する。
- この retry は read-only の診断であり、write の再送、ambiguous outcome、read-back、retry lifecycle を定めない。それらは共通 contract の責務とする。

## Resource identity

- Issue / Pull Request の番号など、repository を欠く識別子を単独で完全な resource identity として扱わない。
- 番号だけでは repository、resource type、対象を一意に固定できない場合、推測で補完しない。
- review comment と review thread は別 resource として扱う。comment の Hide と thread の Resolve を相互の代替操作として扱わない。

## Pull Request template

- Pull Request 作成時は repository が提供する GitHub の PR template を尊重する。
- 複数の template 候補から適切なものを安定して特定できない場合、推測で一つを選ばない。
- template を特定できた場合は、その構成とチェック項目を保持して本文を作成する。

## Maintenance rule

GitHub 固有の規則を追加するのは、共通 contract と通常の GitHub 知識だけでは resource / effect / read-back 等の判断が安定しない場合に限る。網羅的な操作一覧、一般 workflow、共通責務の再記述は追加しない。
