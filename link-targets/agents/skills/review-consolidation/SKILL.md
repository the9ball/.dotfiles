---
name: review-consolidation
description: 明示的に呼び出されたときだけ、Issue / Pull Request に散在するレビュー情報を論点単位で圧縮し、現在の work plan と review state を REVIEW-SUMMARY と body に整合させる。
---

# Review consolidation

## Discovery contract

- Positive trigger: ユーザーまたは対象タスクが `review-consolidation` を明示的に呼び出し、Issue / Pull Request のレビュー状態を集約する。
- Negative trigger: 通常の Issue / Pull Request 操作、レビュー対応、HANDOFF、または明示的な呼び出しのない保守である。
- Conditional dependency: GitHub service、authorization、approval request、external posting の対応 Skill は、その責務が発生した場合だけ解決する。
- Failure mode: 条件付き依存または対象履歴を解決できない場合は推測や別経路への silent fallback をせず、fail-safe に停止する。

## Runtime contract

この Skill が明示的に discovery されたときだけ、下記の Contract と orchestration を normative contract として適用する。条件付き依存は必要な場合だけ読み込み、解決不能なら推測による代替や silent omission をせず fail-safe に停止する。

## Guide

この Skill は自動 trigger を持たない。ユーザーまたは対象タスクが `review-consolidation` を明示的に呼び出した場合だけ使う。
責務は、散在したレビュー情報を意味的に圧縮し、現在の work plan と review state を整合させることに限定する。

### Trigger and scope

- 会話から対象 Issue / PR を一意に判断できる場合は推定してよいが、開始時に対象を可視化する。一意でなければ確認する。
- work-plan source は現在の作業 scope を所有する artifact とする。Issue 段階では Issue body、実装中は PR がその PR scope の現在形を持つ。
- 1 Issue から複数 PR を通常ケースとして扱う。複数 Issue から 1 PR は標準 workflow で自動判断せず、明示指示に従う。
- PR で確定した全体計画への影響は原則 merge 後の元 Issue 保守で還元し、merge 前同期は明示指示がある場合だけ行う。
- merge、Issue close、HANDOFF、個別レビュー reply、inline comment Hide、review thread Resolve、approval / authorization はこの Skill の独自責務にしない。
- GitHub service/API 操作、authorization、approval request、external posting、retry / ambiguous outcome は既存の共通 contract を必要に応じて適用し、この Skill で再定義しない。

### Contract

#### Work plan and body

- body に固定 section schema を要求しない。現在の work plan を自己完結して理解できる状態を目指し、必要なら全体を再構成して重複・obsolete な記述を整理する。
- 実行・設計に必要な理由だけを body に残し、議論履歴は REVIEW-SUMMARY へ寄せる。未確定事項も current work state として body に明示する。
- maintenance 開始時に body と最新 checkpoint の意味的一貫性を確認する。新しいレビュー判断がなく body だけ古い場合は body repair のみ行い、新 Summary は作らない。
#### REVIEW-SUMMARY checkpoint

REVIEW-SUMMARY を review maintenance の永続 checkpoint とする。有効な Summary は次を必須とする。

`<!-- REVIEW-SUMMARY -->`

- `今回確定したこと`
- `未確定として残ること`

両見出しを必須とし、該当事項がなければ `なし` と記載する。

- Summary は原コメント単位ではなく論点単位で整理する。同一論点は統合し、1 コメント内の独立論点は分解してよい。
- 採用 / 却下などの固定 taxonomy は設けず、結論と後から理解するために必要な最小限の理由を自然文で残す。
- 原コメント ID / URL、文字数、項目数は規定しない。
- 過去の有効な Summary は編集・Hide しない。未確定事項は後続 Summary へ引き継ぎ、ユーザー回答で解消した場合も新しい review state update として新 Summary を作る。
- `review round` 等は処理中の alias に使えても、独立した永続状態にしない。
- 通常の review-consolidation では個別レビューコメントへ reply せず、各指摘への判断・回答を論点単位で REVIEW-SUMMARY へ集約する。

#### Checkpoint and history recovery

- checkpoint 候補を決める前に top-level comments の必要な全件取得を完了し、取得完全性を確認する。完全性を確認できなければ checkpoint を確定せず停止・報告する。checkpoint はその取得集合にある「最新の有効な REVIEW-SUMMARY」とし、marker / 見出しだけで機械判定せず、状態復元に信頼できるかを意味的に判断する。invalid / minimized な候補はそれ自体を checkpoint に採用せず、信頼できる地点まで遡って recovery する。
- checkpoint がある通常処理では、そこから後のレビューを差分として扱う。ただし visible な top-level comments は確認し、過去の取りこぼしや cleanup 候補を検出する。
- checkpoint がない場合は、hidden / minimized 済み top-level comments と PR inline review comments / threads を含むレビュー関連履歴を確認し、現在状態を再構築する。Hide 状態を処理済みの証明にしない。
- 新しい conversation / thread で十分な事前読込がなければ full history audit を基本とし、必要な履歴を既に読んでいる場合は差分でよい。
- 状態を信頼して構築できない場合は、信頼できる地点まで必要な範囲を遡り、必要なら full history まで戻る。履歴から解消不能な矛盾は推測せず未確定へ戻す。
- 壊れた Summary は checkpoint として存在しなかったものとして直前の有効な checkpoint から再処理する。再走査で既存の有効な判断を再確認しただけなら新 Summary へ再掲しない。
- 過去の取りこぼしや矛盾は過去 Summary を書き換えず、現在の新しい判断対象として扱う。
- invalid Summary を Hide できるのは、その固有の判断理由・反論・検証結果・未解決情報が新しい valid Summary / body 等へ失われず移管され、置換先を説明でき、Hide 直前の再取得で対象が変化していない場合だけとする。満たせなければ visible のまま残し、Hide した場合はユーザーへ通知する。
#### Snapshot and review inputs

- 1 回の処理開始時に対象レビュー集合を snapshot として固定し、処理中に追加されたレビューを現在 snapshot へ継ぎ足さない。snapshot や comment ID 集合は永続化しない。
- 完了前に snapshot 後の新規レビューを一度確認する。新規レビューがあれば今回の対象には追加せず、未処理情報が残ることをユーザーへ通知して終了し、自動で次処理を開始しない。
- レビュー入力かどうかは author ではなく内容で判断し、human / AI / bot / user-posted AI を区別しない。
- PR inline review comments / threads は入力として読むが、inline comment Hide / review thread Resolve は Skill 範囲外とする。
- レビューか曖昧なコメントは必要に応じて確認する。Hide 安全性が曖昧なら visible のまま残す。
- 非レビューのコメントや artifact は cleanup 対象にしない。判断の参考として参照した情報でも、それ自体がレビュー入力でなければ Hide しない。

#### Cleanup boundary

- Skill 内の cleanup は、レビューとして扱った top-level comment の Hide に限定する。
- 意味ある情報が body / REVIEW-SUMMARY へ保存され、通常表示価値がなくなったと判断できる原コメントだけを Hide 候補にする。未確定事項を含んでいても、その状態が保存されていればよい。
- 各 Hide 候補は実行直前に再取得し、snapshot 時点から本文・更新状態・minimized 状態に意味ある変化がないことを確認する。変化または取得不能があればその候補を Hide せず、stale な判断で cleanup を続けない。
- REVIEW-SUMMARY と今回必要な body 更新の成立を read-back できない場合は後続 Hide へ進まない。これは review-consolidation 固有の cleanup precondition であり、共通 authorization / retry の再定義ではない。
- Hide reason / category は固定しない。有効な REVIEW-SUMMARY は Hide 対象外とし、無効 Summary だけを上記の履歴保全条件の例外候補とする。

#### Ordering and failure

基本順序は次のとおり。

1. 履歴・checkpoint・body を取得し、必要な整合確認を行う。
2. snapshot を固定する。
3. レビューを論点単位に集約して判断する。
4. REVIEW-SUMMARY を投稿する。
5. 必要なら body を現在状態へ更新する。
6. top-level comments を必要に応じて Hide する。
7. snapshot 後の新規レビューを確認して最終報告する。
- Summary 成立後に body 更新や cleanup が失敗しても rollback しない。Summary 成功 + body 失敗でも checkpoint は有効とし、後続 maintenance で body を self-heal できるようにする。
- body は状態変化がある場合だけ更新する。write 直前に body を再取得し、snapshot 時点から意味ある変更があれば書き込まず停止・報告する。
- 失敗、部分失敗、意図した処理を完了できなかった事項は必ずユーザーへ通知する。

### Orchestration and context management

1. 読み込まれた Skill の symlink / junction を実体パスへ解決し、その祖先から `link-targets/agents/reference-map.json` を見つけ、map の `repository_root` から instruction root を固定する。work root や Git 対象は依頼から別途固定する。
2. GitHub service/API を扱う場合は `link-targets/agents/skills/github/SKILL.md` を適用する。外部効果には `link-targets/agents/guides/external-operation-authorization.md`、permission / judgment には `link-targets/agents/skills/approval-request-workflow/SKILL.md`、user-visible posting には `link-targets/agents/skills/external-posting/SKILL.md` をそれぞれ必要な場合だけ適用する。
3. main context へ大量の raw comments / API response を不必要に流し込まない。取得・抽出・整理への subagent 利用は任意であり、main agent が最終的な coverage と判断責任を持つ。
4. 固定 taxonomy、固定 body schema、comment-ID ledger、永続 snapshot、phase state を追加せず、状態が怪しい場合に履歴を再読込して同じ意味状態へ収束させる。
