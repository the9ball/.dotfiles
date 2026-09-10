# 委譲とエージェントセッション

サブエージェントを dispatch または再利用する前に読む詳細ガイド。
`.agents/AGENTS.md` の共通契約を補足し、委譲・handoff・セッション identity の詳細を所有する。

## 委譲の判断

- サブエージェントを使える場合は、引き継ぎ・統合・検証のコストが作業の効果を上回らない限り委譲する。
- 短く自己完結した作業、ユーザー判断を頻繁に必要とする作業、または子へ渡す文脈が作業そのものと同程度以上になる作業は root で行う。
- 子が必要なファイル・ツール・認証・実行環境へ届かない場合、機密情報を安全に渡せない場合、または独立して進められない場合は委譲しない。
- `zero-base-rewrite` など特定 Skill の固有 workflow は、共通委譲規則で再定義せず、該当 Skill の契約を優先する。
- `zero-base-rewrite` を使う長文・複数工程の文書作業では、root が対象読者、目的、出力形式、変更範囲、承認状態を固定して調整・最終検証を担当し、子は自己完結した指示を受けて専用作業ディレクトリに source snapshot、output、比較台帳を作成する。root は実ファイルと差分を再確認して受け入れ、snapshot・ledger・skill の保存条件を優先する。

## handoff と権限

- handoff には目的、対象、対象外、制約、完了条件、検証方法、見積り超過時の停止・確認条件を含め、会話の暗黙前提なしで作業できる形にする。
- 委譲先へ渡す権限・承認範囲・外部操作権限を拡張しない。編集ゲート承認前に許可するのは read-only の作業だけとする。
- 「一つずつ」「順番に」の指定は並行させない。共有作業ツリーではファイル単位の編集担当を一つに固定し、担当が完了するまで root は同じ範囲を編集しない。
- worktree の作成・選択・移動・削除を委譲先の判断で行わない。別の作業ディレクトリが必要なら、ユーザーの承認とリポジトリ固有運用を先に確認する。

## role と model

- 役割固有のモデル制約は、その role に限り低コストモデル優先より先に適用する。利用不能時に判断 role を黙って別 role へ置き換えない。
- agent 定義が自動起動を禁じる場合は、一般の委譲既定より agent 定義を優先する。
- 選択可能な場合は、タスクを十分遂行できる範囲で最も低コストのモデルを選ぶ。モデル固有の調整が必要なら対応する model guide を併読する。

### モデルguideの対応表

モデル固有の調整が必要なときだけ、選択したモデルに対応する guide
を補助資料として読む。モデルguideは共通契約や role / skill 固有契約を
上書きせず、実行環境で利用できることを確認してから適用する。

| 選択モデル | 対応guide |
| --- | --- |
| `gpt-6-astra` | `model-gpt-6-astra.md` |
| `gpt-5.6` alias または GPT-5.6 family | `model-gpt-5.6.md` |

対応表にないモデル、または利用できない guide は推測で適用しない。

## 結果の検証

- 子の報告を事実の証拠とみなさず、root が差分、対象ファイル、ログ、検証結果を現物で照合する。
- 子が変更した場合も、承認済みの対象・操作・範囲を越えていないことを root が確認する。外部操作・公開・権限変更は子の判断だけで行わない。

## セッション identity と再利用

- 再利用単位は一つの明示的な判断を表す `engagement_id` とし、キーは `(root_session_id, engagement_id, role)` とする。同じ root でも判断が異なる場合は別 engagement とする。
- root が engagement、target epoch、再利用可否、共有台帳を所有する。起動器は handle の解決・再開・新規作成・失敗理由・実効 handle の返却だけを担当し、Advisor、Reviewer、Respondent を含む role は handle 管理を変更しない。
- 同一 engagement・role の dispatch は直列化する。同じ handle は runtime が同じ target・epoch で再開成功を明示した場合だけ使い、再開失敗や epoch 変更を台帳へ記録して旧判断を再利用しない。
- Advisor、Reviewer、Respondent へは root ID、engagement ID、role、台帳版、target identity、epoch identity を渡し、epoch 変更時は旧判断の再利用状態を現物から再検証する。
- Reviewer、Respondent、Advisor は role ごとに独立した context を持ち、互いの handle を共有しない。Advisor の出力は出所付きの助言であり、root の最終判断を代行しない。

## Evidence child

- 実質的な探索、仕様・挙動・依存関係の確認、再現、証拠収集は、必要性を確認したうえで read-only の `scount` Evidence child へ委譲する。Reviewer／Respondent が独立性のために対象を直接検証する場合は例外として扱う。
- `scount` はファイル、workspace、台帳を変更せず、子を起動せず、権限拡張、外部変更、外部送信、判断やレビュー状態の確定を行わない。
- packet には固定した request、取得元、版または source hash、確認方法、取得できなかった証拠、不確実性を含める。root は target・epoch と現物を照合してから採用する。
- 同じ target・epoch で runtime が再開成功を明示した場合だけ child context を再利用する。target または epoch が変われば packet・context・判断を無効化し、自動移送・自動 retry をしない。
- 判断 role が `NEEDS_EVIDENCE` を返した場合は、root が request、許可範囲、予算、終了条件を固定して証拠取得を再 dispatch する。照合不能なら `NEEDS_EVIDENCE` または gate の `BLOCKED` を維持する。
