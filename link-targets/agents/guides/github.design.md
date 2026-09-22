# GitHub service contract — design notes

companion runtime guide の将来の設計判断に必要な選択肢、再検討材料、責務境界を記録する。
通常の GitHub 操作では不要で、`github` Skill の編集・再設計・不確実な境界判断・review 時に参照する。本書は非規範的であり、runtime contract と矛盾する場合は Skill の `## Guide` section を優先する。

## 設計意図

### service/API と Git transport を分離する

GitHub が提供元でも、Issue/PR API と repository transport では対象 resource、effect、失敗モデルが異なる。`gh` という同じ CLI を使うかではなく、操作の意味が GitHub service/API か Git transport / local checkout かで分類する。

### 標準経路を host 能力から独立させる

runtime ごとの integration availability を fallback 順序へ組み込むと、同じ guide でも実行経路と失敗時挙動が変わる。そのため service/API の標準経路を `gh` / `gh api` に固定し、host 固有 integration は明示的に採用された別 workflow として分離する。

### GitHub 固有差分だけを保持する

authorization、approval request、external posting、write retry 等を GitHub guide が再定義すると、共通 contract の変更時に意味が分岐する。GitHub 側には resource identity、PR template、review comment / thread のように通常知識だけでは agent 判断がぶれやすい差分だけを残す。

## 責務境界

`github` Skill は GitHub service/API の scope、標準経路、GitHub 固有 resource semantics を所有する。

一方、以下は所有しない。

- Git repository / Git transport / local checkout の lifecycle
- external operation の authorization boundary、approval consumption、ambiguous outcome、write retry
- approval request の discovery、collection、提示 workflow
- user-visible external posting の一般的な文章・公開規則
- Issue/PR maintenance、review response、REVIEW-SUMMARY、HANDOFF の workflow
- host ごとの technical enforcement や integration capability catalog

## 再検討材料

### read-only 診断 retry の一般化

単発の access/auth/connectivity failure を永続的 failure と即断しない規則は、Git transport や他の外部 service にも一般化できる可能性がある。共通化する場合は、外部効果がないこと、retry budget、write retry との区別、適用可能な failure class を共通 contract 側で十分に定義できることを再検討条件とする。

### Skill entrypoint への routing 移行

GitHub 操作時の Skill discovery と責務発生時の conditional load は現在 `github` Skill / `reference-map.json` が保証する。今後も progressive disclosure を維持し、approval-request と authorization を独立した責務として保ち、GitHub write というだけで approval-request を常時 load しない。

### GitHub 固有規則の追加条件

新しい規則候補は、通常の GitHub knowledge で安定して判断できるか、共通 contract が既に所有していないかを先に確認する。GitHub 固有の resource/effect/read-back の差分が実運用で反復して判断をぶらす場合だけ normative guide への追加を検討する。
