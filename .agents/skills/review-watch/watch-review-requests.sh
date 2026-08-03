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

# GitHub の検索インデックスは反映が遅れるため、まだレビューを提出していない PR が
# 一時的に検索結果から消えることがある。この回数だけ連続で不在だった PR を初めて忘れる。
# 1 にすると検索の揺れで二重通知が起きやすく、大きくすると再依頼の検知が遅れる。
absence_count_before_forgetting=2

mkdir -p "${state_directory}"
touch "${state_file}"

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

  sleep "${polling_interval_seconds}"
done
