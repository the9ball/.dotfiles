# GitHub 操作

Issue、Pull Request、レビューコメントなどの GitHub 操作に入る前に読む。
このガイドは `.agents/AGENTS.md` の共通契約と `guides/external-posting.md` を補足し、GitHub 固有の対象特定、調査、操作、投稿内容を定める。
上位の system、ユーザー、リポジトリ、role、skill の指示と承認範囲を上書きしない。

## 共通契約との境界

- clarification、bounded research、autonomous execution の前提は `.agents/AGENTS.md` の共通契約に従う。
- `execution-lifecycle-gate` が所有する execution contract、対象 identity、epoch、承認と権限、review lifecycle、commit、fixup、amend、autosquash、外部操作ゲートをこのガイドで再定義しない。
- #4 の model guide はモデル固有の傾向や補足、#5 の `commit-message.md` はコミットメッセージの形式と履歴規則を担当する。
- #2 の Advisor 固有契約と #6 の rigorous-review 固有契約は、各 role の research budget、bounded verification、`NEEDS_EVIDENCE`、独立性、read-only / evidence 制約を維持する。

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

- read-only 調査は、対象、範囲、予算、停止条件を固定した bounded research として行う。
- ユーザー無応答は scope、権限、外部操作の承認とみなさない。
- 固定時間による fallback は導入せず、経過時間を承認やユーザーの選好、権限判断、設計判断の代替にしない。
- 対象と範囲が固定され、read-only で安全に事実確認でき、ユーザー判断を代替しない場合に限り、condition-based fallback として調査を継続できる。
- scope 拡張、新たな権限、不可逆操作、外部操作、ユーザーの選好や設計判断が必要な事項は停止して確認する。

## 外部操作

- Issue や Pull Request の作成、更新、close、merge、ラベル変更、assign、review request、approve、request changes、返信、コメント投稿は、依頼された操作だけを行う。
- 外部操作の前に、ユーザーの明示的な指示、対象、操作、実際に送信する内容、反映先、公開範囲、必要な権限を固定する。
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

## 投稿文面

- `guides/external-posting.md` に従い、ユーザーの明示がない限りローカル絶対パス、ローカル配置、一時ファイル、sandbox、workspace、認証情報、内部ログを含めない。
- 投稿文面に必要なファイル名や行番号は、受け手が利用できるリポジトリ相対パスと公開 URL で示す。
- レビュー結果、未確定事項、ユーザー判断が必要な事項を混同せず、確認済みの事実と判断待ちの内容を分けて書く。

## 参照先

- 共通の clarification、bounded research、autonomy、Git 安全、外部操作承認は `.agents/AGENTS.md` を参照する。
- 外部公開文面のローカル環境情報の扱いは `guides/external-posting.md` を参照する。
- コミットメッセージの形式と履歴規則は `guides/commit-message.md` を参照する。
