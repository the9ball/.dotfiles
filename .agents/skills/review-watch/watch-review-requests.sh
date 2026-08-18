#!/usr/bin/env bash
# GitHub で自分がレビュアーに指名された Pull Request を監視し、
# 新しく検知したものだけを1行ずつ標準出力へ流す。
# Claude Code の Monitor ツールから persistent 指定で常駐させて使う。
#
# 重要: 標準出力の1行が1通知(= モデル1ターン = クレジット消費)になる。
# gh search prs が返すのは「今レビューを待たれている PR の一覧」というスナップショットで
# あってイベント列ではないため、状態ファイルとの差分を取らないと同じ PR を
# ポーリングごとに通知し続けてしまう。既知の PR は決して出力しないこと。

set -u

polling_interval_seconds="${REVIEW_WATCH_INTERVAL_SECONDS:-60}"
state_directory="${REVIEW_WATCH_STATE_DIRECTORY:-${HOME}/.claude/.review-watch}"
state_file="${state_directory}/seen-pull-requests.tsv"
search_result_limit="${REVIEW_WATCH_SEARCH_LIMIT:-50}"

# 二重起動の抑止。所有トークンを書いたファイルを1つ置き、ループごとに読み直す。
# 中身が自分のトークンでなければ、より新しいプロセスに所有権を奪われたと見なして退く。
# 起動側は何もしなくてよく、外から全員を止めるにはこのファイルへ
# どのプロセスのものでもない値を書く(例: echo stop > owner-token)。
#
# kill でプロセスを撃つ方式は採らない。Monitor がこのスクリプトを起動する際の
# ラッパーのコマンドラインにもスクリプトのパスが含まれるため、パターンマッチで
# 撃つと起動したばかりの自分の親を殺してしまう。
owner_token_file="${state_directory}/owner-token"
owner_token_check_interval_seconds="${REVIEW_WATCH_OWNER_CHECK_INTERVAL_SECONDS:-5}"
owner_token="$$-$(date +%s)"

# GitHub の検索インデックスは反映が遅れるため、まだレビューを提出していない PR が
# 一時的に検索結果から消えることがある。この回数だけ連続で不在だった PR を初めて忘れる。
# 1 にすると検索の揺れで二重通知が起きやすく、大きくすると再依頼の検知が遅れる。
absence_count_before_forgetting=2

mkdir -p "${state_directory}"
touch "${state_file}"

# 所有トークンが自分のものかどうか。ファイルが無い場合も奪われたものとして扱う
# (外から削除するのも全員を止める手段になる)。
is_still_owner() {
  [ "$(cat "${owner_token_file}" 2>/dev/null || true)" = "${owner_token}" ]
}

# 次のポーリングまで待つ。待っている間も所有権を確認し、奪われていたら 1 を返す。
# sleep を刻むのは、退くまでの間だけ新旧2プロセスが状態ファイルを共有してしまい、
# その窓で PR を取りこぼしうるため。刻み幅がそのまま取りこぼし窓の上限になる。
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

# 所有権を主張する。これで先に動いていたプロセスは次の確認で自分から退く。
printf '%s\n' "${owner_token}" > "${owner_token_file}"

# 先行プロセスが退くまで待ってから最初のポーリングに入る。
# 待たないと、両方が生きている間に検知した PR を先行プロセスが状態ファイルへ
# 「既知」として書き込み、こちらが黙って読み飛ばす(= レビュー依頼の取りこぼし)。
sleep "$((owner_token_check_interval_seconds + 1))"
is_still_owner || exit 0

while true; do
  # 一時的な API 失敗で監視全体を落とさない。失敗した回は「該当なし」として扱う。
  search_output="$(
    gh search prs --review-requested=@me --state=open --limit "${search_result_limit}" \
      --json url,title,repository,number \
      --jq '.[] | [.url, .repository.nameWithOwner, (.number | tostring), .title] | @tsv' \
      2>/dev/null || true
  )"

  current_urls="$(printf '%s\n' "${search_output}" | cut -f1 | grep -v '^$' || true)"

  # 新規検知分だけを通知する。
  while IFS=$'\t' read -r pull_request_url repository_full_name pull_request_number pull_request_title; do
    [ -z "${pull_request_url}" ] && continue
    if cut -f1 "${state_file}" | grep -Fxq "${pull_request_url}"; then
      continue
    fi

    # 変更ファイル数だけは検知時点で添える。
    # AI が見ているファイル数と突き合わせる基準値になるうえ、新規 PR にしか問い合わせないので安い。
    changed_files_count="$(
      gh pr view "${pull_request_url}" --json changedFiles --jq '.changedFiles' 2>/dev/null || echo '?'
    )"

    printf 'レビュー依頼: %s #%s %s (変更ファイル %s件) %s\n' \
      "${repository_full_name}" \
      "${pull_request_number}" \
      "${pull_request_title}" \
      "${changed_files_count}" \
      "${pull_request_url}"

    printf '%s\t0\n' "${pull_request_url}" >> "${state_file}"
  done <<< "${search_output}"

  # 状態ファイルを書き直す。
  # 検索結果に残っているものは不在カウントを 0 に戻し、消えているものはカウントを進め、
  # 閾値に達した行は落とす(= レビューを提出したので忘れてよい)。
  updated_state_lines=""
  while IFS=$'\t' read -r recorded_url recorded_absence_count; do
    [ -z "${recorded_url}" ] && continue
    case "${recorded_absence_count}" in
      ''|*[!0-9]*) recorded_absence_count=0 ;;
    esac
    if printf '%s\n' "${current_urls}" | grep -Fxq "${recorded_url}"; then
      updated_state_lines+="${recorded_url}"$'\t'"0"$'\n'
    elif [ "${recorded_absence_count}" -lt "${absence_count_before_forgetting}" ]; then
      updated_state_lines+="${recorded_url}"$'\t'"$((recorded_absence_count + 1))"$'\n'
    fi
  done < "${state_file}"
  printf '%s' "${updated_state_lines}" > "${state_file}"

  # 所有権を奪われていたらここで終わる。
  # トークンファイルは新しい所有者のものなので消さないこと。
  wait_until_next_poll || exit 0
done
