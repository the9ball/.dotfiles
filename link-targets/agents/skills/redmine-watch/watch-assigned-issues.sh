#!/usr/bin/env bash
# Redmine で一度でも自分が担当になったチケットを監視し、
# 前回のポーリング以降に他人が加えた変更だけを1チケット1行で標準出力へ流す。
# Claude Code の Monitor ツールから persistent 指定で常駐させて使う。
#
# 重要: 標準出力の1行が1通知(= モデル1ターン = クレジット消費)になる。
# Redmine API が返すのはチケットの現在値であってイベント列ではないため、
# 「どの journal まで見たか」を状態ファイルに持って差分を取る。
#
# 「過去に担当した」を Redmine 側へ問い合わせる手段は無い。そのため担当中に一度検知した
# チケットをローカルの監視リストへ積み、担当が外れた後もリストから引き続き追跡する。
#
# ## 不変条件
#
# 標準出力への書き込みと状態ファイルの更新を同一トランザクションにはできない。
# したがって「重複ゼロかつ取りこぼしゼロ」は原理的に保証できない。
# **取りこぼしを避け、重複を限定する**方を選ぶ。具体的には次を守る。
#
# 1. 通知を出した後にだけ、そのチケットの journal 位置を進める。逆順にしない。
# 2. 状態の確定はチケット単位で、一時ファイルへ書いて mv で原子的に置き換える。
#    途中で止まっても、再送されるのは処理中だった1チケットぶんに収まる。
# 3. 終了判定・初回発見・取得解析の判断材料が欠けたとき、その対象について通知も
#    journal 位置の前進も確定しない。
# 4. 所有権を失ったと分かった時点で、状態を書かずに退く。書いてしまうと
#    新しい所有者がその変更を「既知」として読み飛ばし、通知が誰にも届かなくなる。

set -u

polling_interval_seconds="${REDMINE_WATCH_INTERVAL_SECONDS:-3600}"
owner_token_check_interval_seconds="${REDMINE_WATCH_OWNER_CHECK_INTERVAL_SECONDS:-5}"
# 1リクエストの実測は約0.4秒。15秒は平均の数十倍で、短すぎると
# ネットワークの揺らぎを誤ってタイムアウトとして扱うため、この値を既定にする。
redmine_cli_timeout_seconds="${REDMINE_WATCH_CLI_TIMEOUT_SECONDS:-15}"
state_directory="${REDMINE_WATCH_STATE_DIRECTORY:-${HOME}/.claude/.redmine-watch}"
redmine_cli_directory="${REDMINE_WATCH_CLI_DIRECTORY:-${HOME}/tools/Redmine.Cli}"
redmine_cli_path="${redmine_cli_directory}/redmine.exe"
state_file="${state_directory}/watched-issues.tsv"
self_user_id_file="${state_directory}/self-user-id"
status_reference_cache_file="${state_directory}/status-reference.json"
owner_token_file="${state_directory}/owner-token"
discovery_page_size=100

# 何回連続で Redmine への問い合わせに失敗したら1行だけ知らせるか。
# 失敗が無音のままだと、API キーの失効と「変更が無い」の区別が付かない。
reference_failure_notice_threshold=3

# 設定ミスで暴走しないよう数値を検証する。非数値だと [ "abc" -gt 0 ] がエラーになり、
# 待機ループが1度も回らずにポーリングが連続実行される。
case "${polling_interval_seconds}" in
  ''|0|*[!0-9]*) polling_interval_seconds=3600 ;;
esac
case "${owner_token_check_interval_seconds}" in
  ''|0|*[!0-9]*) owner_token_check_interval_seconds=5 ;;
esac
case "${redmine_cli_timeout_seconds}" in
  ''|0|*[!0-9]*) redmine_cli_timeout_seconds=15 ;;
esac

# 二重起動の抑止。review-watch と同じ所有トークン方式。
# 起動したプロセスが自分のトークンをファイルへ書いて所有権を主張し、
# 各プロセスは読み直して、自分のトークンでなければ退く。後から起動した方が勝つ。
# 外から全員を止めるにはこのファイルへどのプロセスのものでもない値を書く。
#
# kill でプロセスを撃つ方式は採らない。Monitor がこのスクリプトを起動する際のラッパーの
# コマンドラインにもスクリプトのパスが含まれるため、パターンマッチで撃つと
# 起動したばかりの自分の親を殺してしまう。
owner_token="$$-$(date +%s)"

# 状態ファイルの有無だけで初回起動を判定する。**行数では判定しない。**
# 空ファイルは「未初期化」と「初期化済みだが監視対象ゼロ」の両方を表しうるため、
# 行数で見ると全件終了した後の正しい空状態を初回扱いし、その後に新しく担当になった
# チケットの通知を握りつぶす。ファイルの存在は「確定したスナップショットがある」ことだけを表す。
# この意味を保つため、起動時に touch でファイルを作らない。
if [ -f "${state_file}" ]; then
  is_first_run=0
else
  is_first_run=1
fi

if ! mkdir -p "${state_directory}" 2>/dev/null; then
  printf 'Redmine監視の起動に失敗: 状態ディレクトリを作成できない (%s)\n' "${state_directory}"
  exit 1
fi

# CLI は実行ディレクトリの .redmine-cli.local.json から接続設定を読む。
# 環境変数 REDMINE_URL / REDMINE_API_KEY が無い環境でも動くようにここへ移動しておく。
cd "${redmine_cli_directory}" 2>/dev/null || {
  printf 'Redmine監視の起動に失敗: CLI のディレクトリが見つからない (%s)\n' "${redmine_cli_directory}"
  exit 1
}

# Windows 版 jq は stdout をテキストモードで開くため、出力の行末に CR が付く。
# そのまま状態ファイルへ書くとチケット ID が "30708\r" になり、次のポーリングで
# 既知判定に失敗して同じチケットを二重登録する(実測あり)。値として使う jq はすべてこれを通す。
# jq の終了コードをそのまま返すため、パイプではなく変数経由で CR を落とす
# (パイプにすると $? が tr のものになり、jq の失敗を検出できない)。
# 終了コードだけを見る jq -e は素の jq のまま使う。
jq_strip() {
  local jq_output
  jq_output="$(jq "$@")" || return $?
  printf '%s\n' "${jq_output}" | tr -d '\r'
}

# チケット URL の組み立てに使うベース URL。環境変数を優先し、無ければローカル設定から読む。
# 設定ファイルには API キーも入っているので、url 以外は取り出さない。
redmine_base_url="${REDMINE_URL:-}"
if [ -z "${redmine_base_url}" ]; then
  redmine_base_url="$(jq_strip -r '.default.url // empty' ".redmine-cli.local.json" 2>/dev/null || true)"
fi
redmine_base_url="${redmine_base_url%/}"

# stdin は CLI に渡さない。取得パスで標準入力を取り合わないようにするため。
run_redmine() {
  timeout "${redmine_cli_timeout_seconds}" "${redmine_cli_path}" "$@" --json 2>/dev/null < /dev/null
}

# 所有トークンが自分のものかどうか。ファイルが無い場合も奪われたものとして扱う。
is_still_owner() {
  [ "$(cat "${owner_token_file}" 2>/dev/null || true)" = "${owner_token}" ]
}

# 次のポーリングまで待つ。待っている間も所有権を確認し、奪われていたら 1 を返す。
wait_until_next_poll() {
  local remaining_seconds="${polling_interval_seconds}"
  local chunk_seconds
  while [ "${remaining_seconds}" -gt 0 ]; do
    chunk_seconds="${owner_token_check_interval_seconds}"
    if [ "${chunk_seconds}" -gt "${remaining_seconds}" ]; then
      chunk_seconds="${remaining_seconds}"
    fi
    sleep "${chunk_seconds}"
    remaining_seconds=$((remaining_seconds - chunk_seconds))
    is_still_owner || return 1
  done
  return 0
}

# ---------------------------------------------------------------------------
# 監視リストの状態管理
#
# committed_* はディスク上のスナップショットの写し、pending_* はこのポーリングで
# 処理する作業リスト(committed + 今回の発見分)。発見しただけのチケットは
# committed に入れない。取得に失敗したまま確定させると、担当になったことを
# 知らせないまま「既知」にしてしまう。
# ---------------------------------------------------------------------------
committed_issue_ids=()
committed_journal_ids=()

find_committed_index() {
  local target_issue_id="$1"
  local index=0
  while [ "${index}" -lt "${#committed_issue_ids[@]}" ]; do
    if [ "${committed_issue_ids[index]}" = "${target_issue_id}" ]; then
      printf '%s' "${index}"
      return 0
    fi
    index=$((index + 1))
  done
  return 1
}

set_committed_journal_id() {
  local issue_id="$1"
  local journal_id="$2"
  local index
  if index="$(find_committed_index "${issue_id}")"; then
    committed_journal_ids[index]="${journal_id}"
  else
    committed_issue_ids+=("${issue_id}")
    committed_journal_ids+=("${journal_id}")
  fi
}

remove_committed_issue() {
  local issue_id="$1"
  local index
  index="$(find_committed_index "${issue_id}")" || return 0
  unset 'committed_issue_ids[index]'
  unset 'committed_journal_ids[index]'
  committed_issue_ids=(${committed_issue_ids[@]+"${committed_issue_ids[@]}"})
  committed_journal_ids=(${committed_journal_ids[@]+"${committed_journal_ids[@]}"})
}

# 監視リストを原子的に確定する。所有権を失っていたら書かずに退く。
# 一時ファイルは同じディレクトリに作る(別ファイルシステムをまたぐと mv が原子的でなくなる)。
commit_state() {
  is_still_owner || exit 0
  local temporary_file="${state_file}.tmp.$$"
  local index=0
  : > "${temporary_file}" || return 1
  {
    while [ "${index}" -lt "${#committed_issue_ids[@]}" ]; do
      printf '%s\t%s\n' "${committed_issue_ids[index]}" "${committed_journal_ids[index]}" || return 1
      index=$((index + 1))
    done
  } >> "${temporary_file}" || return 1
  if mv -f "${temporary_file}" "${state_file}"; then
    return 0
  fi
  sleep 1
  mv -f "${temporary_file}" "${state_file}" || return 1
}

commit_state_or_exit() {
  if ! commit_state; then
    printf 'Redmine監視を停止: 監視リストの状態を保存できない\n'
    exit 1
  fi
}

# ディスクから監視リストを読み直す。手で編集された場合もこれで拾う。
# 壊れた行と重複した ID はここで捨てる(重複を残すと、そのチケットは毎回2通知になる)。
load_committed_state() {
  committed_issue_ids=()
  committed_journal_ids=()
  [ -f "${state_file}" ] || return 0
  local issue_id journal_id
  while IFS=$'\t' read -r issue_id journal_id; do
    case "${issue_id}" in
      ''|*[!0-9]*) continue ;;
    esac
    # -1 は「基準未確定」を表す正当な値なので、それ以外の非数値だけを弾く。
    case "${journal_id}" in
      -1) ;;
      ''|*[!0-9]*) journal_id="-1" ;;
    esac
    find_committed_index "${issue_id}" >/dev/null && continue
    committed_issue_ids+=("${issue_id}")
    committed_journal_ids+=("${journal_id}")
  done < "${state_file}"
}

# ---------------------------------------------------------------------------
# ステータスの参照表
#
# 終了判定(isClosed)とステータス名の解決に使う。取得できないループで
# 「終了かどうか分からないまま通知する」と、終了済みチケットの変更で課金通知が出る。
# 最後に成功した内容をディスクへキャッシュし、それも無い場合はそのループを丸ごと見送る。
# ---------------------------------------------------------------------------
status_name_map='{}'
closed_status_ids='[]'
have_status_reference=0

load_status_reference() {
  local statuses_json="$1"
  local fetched_map fetched_closed
  fetched_map="$(printf '%s' "${statuses_json}" | jq_strip -c '[.statuses[] | {key: (.id | tostring), value: .name}] | from_entries' 2>/dev/null)" || return 1
  fetched_closed="$(printf '%s' "${statuses_json}" | jq_strip -c '[.statuses[] | select(.isClosed == true) | .id]' 2>/dev/null)" || return 1
  # 空・壊れた応答で良いキャッシュを潰さない。
  case "${fetched_map}" in
    ''|'{}') return 1 ;;
  esac
  case "${fetched_closed}" in
    ''|'[]') return 1 ;;
  esac
  status_name_map="${fetched_map}"
  closed_status_ids="${fetched_closed}"
  have_status_reference=1
  return 0
}

save_status_reference_cache() {
  local statuses_json="$1"
  local temporary_file="${status_reference_cache_file}.tmp.$$"
  printf '%s' "${statuses_json}" > "${temporary_file}" || return 1
  mv -f "${temporary_file}" "${status_reference_cache_file}"
}

remove_stale_temporary_files() {
  local candidate
  for candidate in "${state_file}.tmp."* "${status_reference_cache_file}.tmp."*; do
    [ -f "${candidate}" ] || continue
    rm -f -- "${candidate}" 2>/dev/null || true
  done
}

# journal の差分を1行の通知文へ畳む jq プログラム。
# 属性変更の oldValue/newValue は ID の生値なので、そのまま出しても読めない。
# ステータスだけは対応表で名前に引き直し、それ以外の属性は「〜変更」とだけ書く
# (詳細は通知後に issues show --include journals で読めるので、通知は差し戻しの検知に絞る)。
read -r -d '' summarize_changes_program <<'JQ_PROGRAM_EOF'
def one_line: gsub("[\r\n\t]+"; " ") | gsub("  +"; " ") | sub("^ +"; "") | sub(" +$"; "");
def shorten($limit): if (length > $limit) then (.[0:$limit] + "…") else . end;
def dedupe: reduce .[] as $item ([]; if (index($item) != null) then . else . + [$item] end);
def status_label:
  if (. == null or . == "") then "なし"
  else (tostring | . as $id | $status_names[$id] // ("ID:" + $id))
  end;

.issue as $issue
| [ $issue.journals[]?
    | select(.id > $last_journal_id)
    | select((.user.id // -1) != $self_user_id) ] as $new_journals
| if ($new_journals | length) == 0 then empty else
    ($new_journals | map(.user.name // "不明") | dedupe | join(", ")) as $actors
  | ($new_journals | map(select((.notes // "") != ""))) as $comment_journals
  | ([ $new_journals[] | .details[]?
       | if .property == "attr" then
           (if .name == "status_id" then
              "ステータス " + (.oldValue | status_label) + "→" + (.newValue | status_label)
            elif .name == "assigned_to_id" then "担当者変更"
            elif .name == "priority_id" then "優先度変更"
            elif .name == "tracker_id" then "トラッカー変更"
            elif .name == "done_ratio" then "進捗変更"
            elif .name == "due_date" then "期日変更"
            elif .name == "start_date" then "開始日変更"
            elif .name == "subject" then "件名変更"
            elif .name == "description" then "説明変更"
            elif .name == "fixed_version_id" then "対象バージョン変更"
            elif .name == "parent_id" then "親チケット変更"
            elif .name == "project_id" then "プロジェクト移動"
            else ((.name // "属性") + " 変更")
            end)
         elif .property == "cf" then "カスタム項目変更"
         elif .property == "attachment" then "添付追加"
         elif .property == "relation" then "関連チケット変更"
         else "その他変更"
         end ] | dedupe) as $change_labels
  | (if ($comment_journals | length) == 0 then []
     elif ($comment_journals | length) == 1 then
       ["コメント「" + ($comment_journals[0].notes | one_line | shorten(60)) + "」"]
     else ["コメント" + (($comment_journals | length) | tostring) + "件"]
     end) as $comment_labels
  | (($change_labels + $comment_labels) | join(", ")) as $summary
  | (("Redmine更新: #" + ($issue.id | tostring)
      + " " + (($issue.subject // "") | one_line | shorten(60))
      + " [" + ($issue.status.name // "?") + "]"
      + " — " + $actors + ": " + (if $summary == "" then "更新あり" else $summary end)
      + " " + $issue_base_url + "/issues/" + ($issue.id | tostring)) | one_line)
  end
JQ_PROGRAM_EOF

# 所有権を主張する。これで先に動いていたプロセスは次の確認で自分から退く。
if ! printf '%s\n' "${owner_token}" 2>/dev/null > "${owner_token_file}"; then
  printf 'Redmine監視の起動に失敗: 所有トークンを書き込めない (%s)\n' "${owner_token_file}"
  exit 1
fi

# 先行プロセスが待機中であれば、この待ちで退いてくれる。
# 先行プロセスが取得パスの途中だった場合はこの待ちでは足りないが、
# 取得パスの中でも所有権を確認し、失った側は状態を書かずに退くので取りこぼしにはならない
# (代わりに、こちらが同じ変更を再検知して通知する = 重複に倒す)。
sleep "$((owner_token_check_interval_seconds + 1))"
is_still_owner || exit 0

if [ -z "${redmine_base_url}" ]; then
  printf 'Redmine監視: 接続先 URL を解決できなかった。通知の URL が不完全になる\n'
fi

# 前回までに取得できていたステータス参照表を復元する。
if [ -f "${status_reference_cache_file}" ]; then
  load_status_reference "$(cat "${status_reference_cache_file}" 2>/dev/null || true)" || true
fi

self_user_id="$(cat "${self_user_id_file}" 2>/dev/null || true)"
case "${self_user_id}" in
  ''|*[!0-9]*) self_user_id="" ;;
esac

consecutive_reference_failures=0
consecutive_discovery_failures=0
status_cache_save_failure_warned=0

while true; do
  remove_stale_temporary_files

  # --- ステータス参照表の更新と、疎通の確認 ---------------------------------
  statuses_json="$(run_redmine statuses list || true)"
  if [ -n "${statuses_json}" ] && load_status_reference "${statuses_json}"; then
    if ! save_status_reference_cache "${statuses_json}"; then
      if [ "${status_cache_save_failure_warned}" -eq 0 ]; then
        printf 'Redmine監視: ステータス参照表を保存できない。監視は継続する\n'
        status_cache_save_failure_warned=1
      fi
    fi
    if [ "${consecutive_reference_failures}" -ge "${reference_failure_notice_threshold}" ]; then
      printf 'Redmine監視: Redmine への問い合わせが復旧した\n'
    fi
    consecutive_reference_failures=0
  else
    consecutive_reference_failures=$((consecutive_reference_failures + 1))
    # 閾値ちょうどの1回だけ知らせる。復旧するまで再通知しない。
    if [ "${consecutive_reference_failures}" -eq "${reference_failure_notice_threshold}" ]; then
      printf 'Redmine監視: Redmine への問い合わせが%d回連続で失敗している。API キーの失効や接続設定を確認する\n' \
        "${consecutive_reference_failures}"
    fi
  fi

  # 終了判定ができないループでは、通知も journal 位置の前進もせずに次回へ持ち越す。
  if [ "${have_status_reference}" -eq 0 ]; then
    wait_until_next_poll || exit 0
    continue
  fi

  # --- 自分のユーザー ID ----------------------------------------------------
  # 自分が付けた変更を通知しないために要る。この CLI は管理者権限が必要な
  # /users.json を使わないので、担当チケットの assignedTo から拾う。
  # 担当中のチケットが1件も無いと取れないので、取れるまで毎ループ試す。
  # 分からない間は誰の変更も通知する(黙るより鳴るほうが安全側)。
  if [ -z "${self_user_id}" ]; then
    detected_user_id="$(run_redmine issues list --assigned-to me --status all --limit 1 | jq_strip -r '.issues[0].assignedTo.id // empty' 2>/dev/null || true)"
    case "${detected_user_id}" in
      ''|*[!0-9]*) : ;;
      *)
        self_user_id="${detected_user_id}"
        printf '%s\n' "${self_user_id}" > "${self_user_id_file}"
        ;;
    esac
  fi

  # --- 監視リストの読み込みと発見パス ---------------------------------------
  load_committed_state

  pending_issue_ids=()
  pending_journal_ids=()
  index=0
  while [ "${index}" -lt "${#committed_issue_ids[@]}" ]; do
    pending_issue_ids+=("${committed_issue_ids[index]}")
    pending_journal_ids+=("${committed_journal_ids[index]}")
    index=$((index + 1))
  done

  # いま自分が担当している未完了チケットを作業リストへ積む。journal 位置は -1
  # (基準未確定)にしておき、取得パスで現在の最大 journal ID を基準として据える。
  # ここで 0 を入れると、登録前から付いていたコメントが全部「新着」になる。
  newly_discovered_issue_ids=""
  discovery_complete=1
  discovery_total_count=""
  discovery_fetched_count=0
  discovery_offset=0
  while true; do
    discovery_json="$(run_redmine issues list --assigned-to me --status open --limit "${discovery_page_size}" --offset "${discovery_offset}" || true)"
    if [ -z "${discovery_json}" ]; then
      discovery_complete=0
      break
    fi

    if ! printf '%s' "${discovery_json}" | jq -e '
      (.issues | type == "array") and
      (.totalCount | type == "number" and floor == . and . >= 0)
    ' >/dev/null 2>&1; then
      discovery_complete=0
      break
    fi

    if ! discovery_page_total_count="$(printf '%s' "${discovery_json}" | jq_strip -r '.totalCount' 2>/dev/null)"; then
      discovery_complete=0
      break
    fi
    if [ -z "${discovery_total_count}" ]; then
      discovery_total_count="${discovery_page_total_count}"
    elif [ "${discovery_page_total_count}" != "${discovery_total_count}" ]; then
      discovery_complete=0
      break
    fi

    if ! printf '%s' "${discovery_json}" | jq -e 'all(.issues[]; (.id | type == "number" and floor == . and . >= 0))' >/dev/null 2>&1; then
      discovery_complete=0
      break
    fi
    if ! discovery_page_count="$(printf '%s' "${discovery_json}" | jq_strip -r '.issues | length' 2>/dev/null)"; then
      discovery_complete=0
      break
    fi
    if ! discovered_ids="$(printf '%s' "${discovery_json}" | jq_strip -r '.issues[].id' 2>/dev/null)"; then
      discovery_complete=0
      break
    fi

    while IFS= read -r discovered_issue_id; do
      case "${discovered_issue_id}" in
        ''|*[!0-9]*) continue ;;
      esac
      already_pending=0
      index=0
      while [ "${index}" -lt "${#pending_issue_ids[@]}" ]; do
        if [ "${pending_issue_ids[index]}" = "${discovered_issue_id}" ]; then
          already_pending=1
          break
        fi
        index=$((index + 1))
      done
      [ "${already_pending}" -eq 1 ] && continue
      pending_issue_ids+=("${discovered_issue_id}")
      pending_journal_ids+=("-1")
      newly_discovered_issue_ids+="${discovered_issue_id}"$'\n'
    done <<< "${discovered_ids}"

    discovery_fetched_count=$((discovery_fetched_count + discovery_page_count))
    if [ "${discovery_fetched_count}" -gt "${discovery_total_count}" ]; then
      discovery_complete=0
      break
    fi
    [ "${discovery_fetched_count}" -eq "${discovery_total_count}" ] && break
    if [ "${discovery_page_count}" -eq 0 ]; then
      discovery_complete=0
      break
    fi
    discovery_offset="${discovery_fetched_count}"
  done

  if [ "${is_first_run}" -eq 1 ]; then
    if [ "${discovery_complete}" -eq 1 ]; then
      if [ "${consecutive_discovery_failures}" -ge "${reference_failure_notice_threshold}" ]; then
        printf 'Redmine監視: 初回の担当チケット発見が復旧した\n'
      fi
      consecutive_discovery_failures=0
    else
      consecutive_discovery_failures=$((consecutive_discovery_failures + 1))
      if [ "${consecutive_discovery_failures}" -eq "${reference_failure_notice_threshold}" ]; then
        printf 'Redmine監視: 初回の担当チケット発見が%d回連続で不完全。次回も再試行する\n' \
          "${consecutive_discovery_failures}"
      fi
    fi
  else
    consecutive_discovery_failures=0
  fi

  # --- 取得パス -------------------------------------------------------------
  # 担当が外れたチケットは一覧クエリで拾えないため、ここは1件1リクエストになる。
  index=0
  while [ "${index}" -lt "${#pending_issue_ids[@]}" ]; do
    watched_issue_id="${pending_issue_ids[index]}"
    recorded_journal_id="${pending_journal_ids[index]}"
    index=$((index + 1))

    # 所有権を失っていたらここで退く。状態は書かない。
    # 書いてしまうと、新しい所有者がこの変更を「既知」として読み飛ばす。
    is_still_owner || exit 0

    issue_json="$(run_redmine issues show "${watched_issue_id}" --include journals || true)"

    # 取得に失敗したチケットは確定させず、次のポーリングへ持ち越す。
    # ここで落とすと、通信エラーで監視対象が静かに消える。
    if [ -z "${issue_json}" ] || ! printf '%s' "${issue_json}" | jq -e '.issue.id' >/dev/null 2>&1; then
      continue
    fi

    # 終了ステータスは両分岐で使うので、journal 差分の分岐前に判定材料だけ取る。
    if ! current_status_id="$(printf '%s' "${issue_json}" | jq_strip -r '.issue.status.id // empty' 2>/dev/null)"; then
      continue
    fi
    case "${current_status_id}" in
      ''|*[!0-9]*) continue ;;
    esac
    issue_is_closed=0
    if [ -n "${current_status_id}" ] &&
       printf '%s' "${closed_status_ids}" | jq -e --argjson status_id "${current_status_id}" 'index($status_id) != null' >/dev/null 2>&1; then
      issue_is_closed=1
    fi

    if ! latest_journal_id="$(printf '%s' "${issue_json}" | jq_strip -r '
      if (.issue.journals | type) != "array" then error("journals")
      else
        [.issue.journals[] | .id] as $journal_ids
        | if ($journal_ids | length) == 0 then 0
          elif all($journal_ids[]; (type == "number" and floor == . and . >= 0)) then ($journal_ids | max)
          else error("journal id")
          end
      end
    ' 2>/dev/null)"; then
      continue
    fi
    case "${latest_journal_id}" in
      ''|*[!0-9]*) continue ;;
    esac

    if [ "${recorded_journal_id}" = "-1" ]; then
      # 基準未確定の終了チケットは、既存か新着かを区別できないので無通知で落とす。
      if [ "${issue_is_closed}" -eq 1 ]; then
        remove_committed_issue "${watched_issue_id}"
        [ "${is_first_run}" -eq 0 ] && commit_state_or_exit
        continue
      fi
      # 監視に加わったばかりのチケット。既存の journal は初期値として飲み込む。
      # 担当になったこと自体は、初回起動を除いて知らせる。
      if [ "${is_first_run}" -eq 0 ] && printf '%s' "${newly_discovered_issue_ids}" | grep -Fxq "${watched_issue_id}"; then
        if ! issue_subject="$(printf '%s' "${issue_json}" | jq_strip -r '(.issue.subject // "") | gsub("[\r\n\t]+"; " ")' 2>/dev/null)"; then
          continue
        fi
        if ! issue_status_name="$(printf '%s' "${issue_json}" | jq_strip -r '(.issue.status.name // "?") | gsub("[\r\n\t]+"; " ")' 2>/dev/null)"; then
          continue
        fi
        if ! printf 'Redmine担当追加: #%s %s [%s] %s/issues/%s\n' \
             "${watched_issue_id}" \
             "${issue_subject}" \
             "${issue_status_name}" \
             "${redmine_base_url}" \
             "${watched_issue_id}"; then
          # 通知を出せなかった。確定させずに退く(出力先が閉じている)。
          exit 1
        fi
      fi
      set_committed_journal_id "${watched_issue_id}" "${latest_journal_id}"
      [ "${is_first_run}" -eq 0 ] && commit_state_or_exit
      continue
    fi

    notification_line="$(
      printf '%s' "${issue_json}" | jq_strip -r \
        --argjson last_journal_id "${recorded_journal_id}" \
        --argjson self_user_id "${self_user_id:--1}" \
        --argjson status_names "${status_name_map}" \
        --arg issue_base_url "${redmine_base_url}" \
        "${summarize_changes_program}" 2>/dev/null
    )" || {
      # jq が落ちた。「変更なし」と区別が付かないまま journal 位置を進めると
      # この回に検知すべきだった変更が永久に失われるので、確定させずに持ち越す。
      continue
    }

    if [ -n "${notification_line}" ]; then
      printf '%s\n' "${notification_line}" || exit 1
    fi

    # journal 差分を通知した後で終了チケットを落とす。差し戻し変更を先に知らせる。
    if [ "${issue_is_closed}" -eq 1 ]; then
      remove_committed_issue "${watched_issue_id}"
    else
      set_committed_journal_id "${watched_issue_id}" "${latest_journal_id}"
    fi
    [ "${is_first_run}" -eq 0 ] && commit_state_or_exit
  done

  # 初回起動は通知を出さないので、確定を1回にまとめられる。
  # 途中で止まっても状態ファイルが生まれず、次回もやり直しから始まる。
  if [ "${is_first_run}" -eq 1 ] && [ "${discovery_complete}" -eq 1 ]; then
    commit_state_or_exit
    is_first_run=0
  fi

  # 所有権を奪われていたらここで終わる。
  # トークンファイルは新しい所有者のものなので消さないこと。
  wait_until_next_poll || exit 0
done
