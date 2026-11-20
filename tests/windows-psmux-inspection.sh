#!/usr/bin/env bash
# Exercise the documented inspection block with stubs, never an installed psmux.
set -eu
repository_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_directory=$(mktemp -d)

# Remove only files created inside this test's fresh temporary directory.
cleanup() {
	rm -f "$fixture_directory/psmux" "$fixture_directory/cygpath" "$fixture_directory/inspect.sh" "$fixture_directory/calls" "$fixture_directory/output"
	rmdir "$fixture_directory"
}
trap cleanup EXIT

sed -n '/<!-- daily-inspection:start -->/,/<!-- daily-inspection:end -->/p' "$repository_directory/docs/windows-psmux-daily.md" |
	sed '1,2d;$d;/^```$/d' > "$fixture_directory/inspect.sh"
[[ -s $fixture_directory/inspect.sh ]]
cat > "$fixture_directory/cygpath" <<'STUB'
#!/usr/bin/env bash
[[ $# == 2 && $1 == -w && $2 == '/fixture local/Dotfiles/PsmuxDaily/registry' ]] || exit 92
if [[ ${INSPECTION_CASE-} == conversion-failure ]]; then exit 23; fi
printf '%s\n' 'C:\fixture local\Dotfiles\PsmuxDaily\registry'
STUB
cat > "$fixture_directory/psmux" <<'STUB'
#!/usr/bin/env bash
set -eu
[[ $PSMUX_DATA_DIR == 'C:\fixture local\Dotfiles\PsmuxDaily\registry' && $PSMUX_NO_WARM == 1 ]] || exit 91
for name in PSMUX_SESSION PSMUX_SESSION_NAME PSMUX_SESSION_DISPLAY_NAME PSMUX_REMOTE_ATTACH PSMUX_TARGET_SESSION PSMUX_ACTIVE TMUX TMUX_PANE; do
	[[ ! ${!name+x} ]] || exit 91
done
printf '%s\n' "$*" >> "$INSPECTION_LOG"
case "$*" in
	'-f NUL -L dotfiles-session1 list-sessions -F #{session_name}')
		case "$INSPECTION_CASE" in
			query-failure) exit 24 ;;
			missing-main) printf '%s\n' other-main ;;
			success|client-failure) printf '%s\n' other main ;;
			*) exit 91 ;;
		esac
		;;
	'-f NUL -L dotfiles-session1 list-clients -t main')
		if [[ $INSPECTION_CASE == client-failure ]]; then exit 25; fi
		printf '%s\n' 'fixture-client'
		;;
	*) exit 91 ;;
esac
STUB
chmod +x "$fixture_directory/psmux" "$fixture_directory/cygpath"
export PATH="$fixture_directory:$PATH" BASH_ENV=/dev/null
export INSPECTION_LOG="$fixture_directory/calls"
export LOCALAPPDATA='/fixture local' PSMUX_DATA_DIR=parent-registry PSMUX_NO_WARM=parent-warm
for name in PSMUX_SESSION PSMUX_SESSION_NAME PSMUX_SESSION_DISPLAY_NAME PSMUX_REMOTE_ATTACH PSMUX_TARGET_SESSION PSMUX_ACTIVE TMUX TMUX_PANE; do
	export "$name=parent-marker"
done
parent_environment=$(export -p)
for INSPECTION_CASE in success missing-main query-failure client-failure conversion-failure; do
	export INSPECTION_CASE
	: > "$INSPECTION_LOG"
	# Sourcing checks that even failure leaves the calling shell's routing unchanged.
	# shellcheck disable=SC1091
	if source "$fixture_directory/inspect.sh" > "$fixture_directory/output" 2>&1; then inspection_exit=0; else inspection_exit=$?; fi
	case "$INSPECTION_CASE" in
		success) expected_exit=0; expected_calls=2 ;;
		missing-main) expected_exit=1; expected_calls=1 ;;
		query-failure) expected_exit=24; expected_calls=1 ;;
		client-failure) expected_exit=25; expected_calls=2 ;;
		conversion-failure) expected_exit=23; expected_calls=0 ;;
	esac
	[[ $inspection_exit == "$expected_exit" && $(wc -l < "$INSPECTION_LOG") -eq $expected_calls ]]
	[[ $PSMUX_DATA_DIR == parent-registry && $PSMUX_NO_WARM == parent-warm ]]
	for name in PSMUX_SESSION PSMUX_SESSION_NAME PSMUX_SESSION_DISPLAY_NAME PSMUX_REMOTE_ATTACH PSMUX_TARGET_SESSION PSMUX_ACTIVE TMUX TMUX_PANE; do
		[[ ${!name} == parent-marker ]]
	done
	printf 'PASS %s\n' "$INSPECTION_CASE"
done
unset INSPECTION_CASE
[[ $(export -p) == "$parent_environment" ]]
unset LOCALAPPDATA
: > "$INSPECTION_LOG"
# shellcheck disable=SC1091
if source "$fixture_directory/inspect.sh" > "$fixture_directory/output" 2>&1; then inspection_exit=0; else inspection_exit=$?; fi
[[ $inspection_exit == 1 && ! -s $INSPECTION_LOG && ! ${LOCALAPPDATA+x} ]]
printf '%s\n' 'PASS missing-localappdata' '6 inspection cases passed; no real psmux invoked.'
