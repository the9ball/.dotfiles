---
name: github
description: GitHub service/API の Issue、Pull Request、review、comment、label、release、metadata を read または write するときに使う。Git transport だけでは発動しない。
---

# GitHub service workflow

## Discovery contract

- Positive trigger: GitHub service/API 上の resource を read または write する。
- Negative trigger: Git repository の local checkout や Git transport だけを操作する。
- Conditional dependency: common policy kernel を適用し、再設計材料が必要な場合は本 Skill 内の非runtime Design section を参照する。共通 authorization は重複定義しない。
- Failure mode: GitHub service contract を解決できない場合は別経路へ fallback せず、fail-safe に停止する。

## Runtime contract

この Skill が discovery されたときだけ、下記の Guide section を normative contract として適用する。条件付き依存は必要な場合だけ読み込み、解決不能なら推測による代替や silent omission をせず fail-safe に停止する。

常時適用される共通 policy kernel は link-targets/agents/AGENTS.md とする。GitHub service contract の再設計・review 時は、本 Skill 内の非runtime Design section を参照する。

## Guide

GitHub service/API 上の Issue、Pull Request、review、comment、label、release、repository metadata などを read / write するときに適用する。
この guide は GitHub 操作一般の解説ではなく、共通規約と通常の GitHub 知識だけでは判断がぶれる GitHub service 固有事項だけを保持する normative contract である。一般的な authorization、approval request、external posting、write lifecycle、retry はそれぞれの責務を持つ共通 contract に委譲し、ここへ重複して追加しない。
この contract 自体を変更・再設計するときは、下記の非runtime Design section を必要なときだけ参照する。

### Scope

- 対象は GitHub という外部 service/API 上の read / write である。
- Git repository / Git transport は、remote が GitHub でも対象外である。`git clone/fetch/pull/push` に加え、`gh repo clone`、`gh pr checkout` など実質的に Git transport / local checkout を主目的とする操作も、コマンド名ではなく操作の意味で分類する。
- GitHub service/API 操作の標準経路は、実行環境によらず公式 `gh` / `gh api` とする。host が別経路を提供していても、この contract の fallback または代替経路として Connector、MCP、app integration、browser、direct HTTP、別 CLI、別 account へ切り替えない。
- host 固有の integration workflow は、それ自体が明示的に採用された場合だけ別 workflow として扱う。この規則は各製品にその能力が存在しないことを意味しない。
- 本 guide は behavioral contract であり、host 側の permissions、hooks、managed settings 等による technical enforcement を定義しない。

### Access failure の診断

- 単発の `gh` access/auth/connectivity failure だけで永続的な credential failure と断定しない。
- 外部効果を伴わない GitHub access を同じ標準経路で 1 回 retry し、実効的な利用可能性を確認する。retry も失敗した場合は別経路へ fallback せず停止する。
- この retry は read-only の診断であり、write の再送、ambiguous outcome、read-back、retry lifecycle を定めない。それらは共通 contract の責務とする。

### Resource identity

- Issue / Pull Request の番号など、repository を欠く識別子を単独で完全な resource identity として扱わない。
- 番号だけでは repository、resource type、対象を一意に固定できない場合、推測で補完しない。
- review comment と review thread は別 resource として扱う。comment の Hide と thread の Resolve を相互の代替操作として扱わない。
- review comment の Hide または review thread の Resolve を試行する前に、選択した標準経路で対象 ID、現在の状態、本文を read-back できることを確認する。read-back 能力が利用不能または確認不能な場合は `NEEDS_EVIDENCE` として停止し、操作を試行しない。

### Pull Request template

- Pull Request 作成時は repository が提供する GitHub の PR template を尊重する。
- 複数の template 候補から適切なものを安定して特定できない場合、推測で一つを選ばない。
- template を特定できた場合は、その構成とチェック項目を保持して本文を作成する。

### Maintenance rule

GitHub 固有の規則を追加するのは、共通 contract と通常の GitHub 知識だけでは resource / effect / read-back 等の判断が安定しない場合に限る。網羅的な操作一覧、一般 workflow、共通責務の再記述は追加しない。


## Design (nonruntime)

This section preserves GitHub contract rationale and reconsideration material. It is not part of the runtime contract and does not override the Guide section.

GitHub Skill runtime contract の将来の設計判断に必要な選択肢、再検討材料、責務境界を記録する。
通常の GitHub 操作では不要で、`github` Skill の編集・再設計・不確実な境界判断・review 時に参照する。この section は非規範的であり、runtime contract と矛盾する場合は Skill の `## Guide` section を優先する。

### 設計意図

#### service/API と Git transport を分離する

GitHub が提供元でも、Issue/PR API と repository transport では対象 resource、effect、失敗モデルが異なる。`gh` という同じ CLI を使うかではなく、操作の意味が GitHub service/API か Git transport / local checkout かで分類する。

#### 標準経路を host 能力から独立させる

runtime ごとの integration availability を fallback 順序へ組み込むと、同じ guide でも実行経路と失敗時挙動が変わる。そのため service/API の標準経路を `gh` / `gh api` に固定し、host 固有 integration は明示的に採用された別 workflow として分離する。

#### GitHub 固有差分だけを保持する

authorization、approval request、external posting、write retry 等を GitHub guide が再定義すると、共通 contract の変更時に意味が分岐する。GitHub 側には resource identity、PR template、review comment / thread のように通常知識だけでは agent 判断がぶれやすい差分だけを残す。

### 責務境界

`github` Skill は GitHub service/API の scope、標準経路、GitHub 固有 resource semantics を所有する。

一方、以下は所有しない。

- Git repository / Git transport / local checkout の lifecycle
- external operation の authorization boundary、approval consumption、ambiguous outcome、write retry
- approval request の discovery、collection、提示 workflow
- user-visible external posting の一般的な文章・公開規則
- Issue/PR maintenance、review response、REVIEW-SUMMARY、HANDOFF の workflow
- host ごとの technical enforcement や integration capability catalog

### 再検討材料

#### read-only 診断 retry の一般化

単発の access/auth/connectivity failure を永続的 failure と即断しない規則は、Git transport や他の外部 service にも一般化できる可能性がある。共通化する場合は、外部効果がないこと、retry budget、write retry との区別、適用可能な failure class を共通 contract 側で十分に定義できることを再検討条件とする。

#### Skill entrypoint への routing 移行

GitHub 操作時の Skill discovery と責務発生時の conditional load は現在 `github` Skill / `reference-map.json` が保証する。今後も progressive disclosure を維持し、approval-request と authorization を独立した責務として保ち、GitHub write というだけで approval-request を常時 load しない。

#### GitHub 固有規則の追加条件

新しい規則候補は、通常の GitHub knowledge で安定して判断できるか、共通 contract が既に所有していないかを先に確認する。GitHub 固有の resource/effect/read-back の差分が実運用で反復して判断をぶらす場合だけ normative Skill Guide への追加を検討する。
