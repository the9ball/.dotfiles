# Git 操作とレビュー範囲

Git の状態取得、変更、復旧、差分・レビュー範囲の固定に入る前に読む詳細ガイド。
`.agents/AGENTS.md`、root `AGENTS.md`、`commit-message.md` の責務を補足し、コミットメッセージ形式は定義しない。

## 状態取得と index.lock

- リポジトリ状態の参照だけを目的とするコマンドでは、可能な限り `git --no-optional-locks` をサブコマンドより前に指定する。
- インデックス、作業ツリー、参照、履歴を更新し得るコマンドには `--no-optional-locks` を指定しない。
- `index.lock` エラーが出た場合は、エラーに表示されたパスまたは `git rev-parse --git-path index.lock` で対象を特定する。
- 同じリポジトリまたは worktree を操作中の Git プロセスがある場合は、その終了を待ってから再試行する。
- ロックファイルの削除やプロセスの停止は、原因を read-only で確認し、作成元プロセスが終了した残留ロックだと確認できた場合でも、ユーザーの明示的な承認なしに行わない。

## 権限エラー

- アクセス拒否、認証・認可不足、sandbox 制約などが原因と考えられる場合は、必要な操作、対象、理由を示して確認を得る。
- 原因確認の read-only 操作以外で、ブラウザ、別 CLI・API、別アカウント、別保存先へ黙って切り替えない。
- Git 管理領域の `index.lock` を作成・更新できず同一コマンドが権限エラーになった場合は、その同一 Git コマンドだけを権限昇格して再実行してよい。
- 通常権限で Git 管理領域へ書き込めないことが事前に分かる環境では、index を更新する Git コマンドを最初から権限昇格してよい。ただし上位ポリシーの確認を優先する。
- ロックの存在、別 Git プロセス、残留ロックを権限不足として扱わない。ロック削除、資格情報変更、別経路への切替はこの例外に含めない。

## 差分・レビュー範囲の固定

- 実質レビューの前に比較基準、終端状態、対象 identity、含める状態、除外する状態を一意に固定する。`HEAD` だけで基準と終端を同時に決めない。
- PR または URL が指定された場合は、提供元の固定 base/head SHA と差分定義に一致するコミット済み差分を対象とし、移動するローカル base、index、working tree、untracked を暗黙に混ぜない。
- `staged` は `HEAD` 基準の index、`直近commit` は `HEAD^..HEAD`、`未commit` または `作業ツリー` は `HEAD` 基準の staged・unstaged・非ignored untracked とする。ignored の扱いは明示する。
- `upstreamとの差分` は、明示がなければ現在 branch の追跡先 `@{u}` から `HEAD` までのコミット済み変更とする。`@{u}` を PR base や release branch と同一視しない。
- identity には commit/PR の base・target SHA、staged の index snapshot、作業ツリーの index・追跡ファイル snapshot、対象 untracked の path・hash manifest を含める。
- 「レビューして」などで比較基準や終端が一意でない場合は、branch、追跡先、PR base/head、`HEAD`、dirty 状態を read-only で確認し、原則1問で候補を提示する。確認前にレビューや dispatch を始めない。
- `@{u}` 解決不能、PR head と local `HEAD` の不一致、対象の変化がある場合は、推測や新旧証拠の混在をせず範囲を再確認する。
- レビュー結果の冒頭に比較基準、終端 ref/SHA または snapshot identity、含めた状態、除外した状態、untracked の扱いを記載する。

## Git の範囲制御

- formatter、lint、Git 操作で scope 外の大量変更が生成された場合は自動的に含めず、分離または停止して確認する。
- 破壊的な操作、履歴書き換え、force push、ロック削除は `.agents/AGENTS.md` の明示承認境界を満たさない限り行わない。
