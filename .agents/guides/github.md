# GitHub 操作

Issue、Pull Request、レビューコメントなどの GitHub 操作に入る前に読む。
このガイドは `.agents/AGENTS.md` の共通契約と `guides/external-posting.md` を補足し、GitHub 固有の対象特定、操作、投稿内容を定める。
上位の system、ユーザー、リポジトリ、role、skill の指示と承認範囲を上書きしない。

## 共通契約との境界

- clarification、bounded research、autonomous execution、無応答、scope・permission、不可逆操作、一般的な外部操作承認は `.agents/AGENTS.md` の共通契約に従う。
- lifecycle、model、Advisor、rigorous-review、commit-message、external-posting の固有契約は各 Skill / guide に従い、このガイドでは GitHub 固有の差分だけを定める。

## 実行手段と失敗時の停止

- GitHub CLI が利用可能な場合は `gh` を既定の操作手段とする。
- `gh` の未導入、未認証、権限不足、接続失敗が発生した場合は停止し、必要な操作、対象、理由を示してユーザーへ確認する。
- 前項の失敗時に、ブラウザ、別 CLI、別 API、別アカウントへ黙って切り替えない。
- 権限エラーの原因を特定する読み取り専用の確認は行ってよいが、資格情報の変更や別の保存先への切替は確認なしに行わない。

## 対象の固定

- Issue または Pull Request の URL や番号が指定され、対象リポジトリが一意なら、指定された対象を直接取得する。
- 一意な対象を指定された場合に不要な検索を行わず、検索結果を理由に別の Issue、Pull Request、リポジトリへ読み替えない。
- 番号だけで対象リポジトリ、Issue と Pull Request の別、または対象の種類が曖昧な場合は停止して確認する。
- 操作前に owner、repository、Issue または Pull Request の番号、対象の種類、実行する操作を固定する。
- 状態による条件分岐がある操作では、対象 identity に加えて確認した状態と、その状態を確認する理由を固定する。

## Read-only 調査と無応答

- 共通の read-only 調査、condition-based fallback、無応答時の扱いは `.agents/AGENTS.md` に従う。

## 外部操作

- GitHub の Issue、Pull Request、レビュー操作は、依頼された操作だけを対象にする。
- 各操作の前に、対象 identity、操作、送信本文、反映先、公開範囲を固定し、`.agents/AGENTS.md` の外部操作承認を適用する。
- Issue 本文の更新とコメント投稿は別操作として扱い、それぞれの対象、操作、本文、公開範囲を個別に固定する。
- 計画への同意や Advisor の `CLEAR` は、Issue や Pull Request の外部投稿、更新、実装採用の承認とはみなさない。
- コメント投稿だけが目的で、状態に依存する条件がなく、対象 identity、投稿本文、公開範囲、権限が固定され、状態確認が本文生成に不要な場合は、不要な状態確認を省略できる。
- 状態確認を省略しても、対象 identity、投稿本文、公開範囲、権限の固定は省略しない。

## Pull Request Template

- Pull Request を作成する前に、GitHub が認識する標準配置を確認する。
- 標準配置には、リポジトリ root の `pull_request_template.md`、`docs/pull_request_template.md`、`.github/pull_request_template.md`、および各ディレクトリの `PULL_REQUEST_TEMPLATE/` が含まれる。
- 候補は `.github/pull_request_template.md`、`.github/PULL_REQUEST_TEMPLATE/`、`pull_request_template.md`、`PULL_REQUEST_TEMPLATE/`、`docs/pull_request_template.md`、`docs/PULL_REQUEST_TEMPLATE/` の順に確認する。
- 複数のテンプレート候補がある場合は、対象と選択方法を明示的に固定し、推測で一つを選ばない。
- 該当するテンプレートが特定できた場合は、その構成とチェック項目に従って本文を作成する。

## レビューコメントへの対応

- 修正だけでレビューコメントへの対応が完了する場合は、不要な返信を行わない。
- 返信が必要な場合は、対象のレビューコメントまたはスレッドに限定する。
- 別スレッドや Issue 本文への説明を追加する場合は、別の外部操作として対象と本文を固定する。
- PRのreview threadのResolveおよびreview commentのHideは、このガイドの実行手段、失敗時停止、外部操作承認に従うGitHub固有の外部操作として扱う。
- 具体的なAPI名やmutationは固定しない。

## 投稿文面

- 公開文面は `guides/external-posting.md` に従い、GitHub 上で参照可能なリポジトリ相対パスと公開 URL を使う。
- レビュー結果、未確定事項、ユーザー判断が必要な事項を混同せず、確認済みの事実と判断待ちの内容を分けて書く。

## 参照先

- 共通の clarification、bounded research、autonomy、Git 安全、外部操作承認は `.agents/AGENTS.md` を参照する。
- 外部公開文面のローカル環境情報の扱いは `guides/external-posting.md` を参照する。
- コミットメッセージの形式と履歴規則は `guides/commit-message.md` を参照する。
