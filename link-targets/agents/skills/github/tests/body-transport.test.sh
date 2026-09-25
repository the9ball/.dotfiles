#!/usr/bin/env bash
set -euo pipefail

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
mock_bin="$test_root/bin"
mkdir -p -- "$mock_bin"
export BODY_TRANSPORT_TEST_ROOT="$test_root"

cat > "$mock_bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

# Catch the fixture command without invoking the real GitHub CLI.
if [[ "$#" -eq 2 && "$1" == auth && "$2" == refresh ]]; then
  : > "$BODY_TRANSPORT_TEST_ROOT/gh-auth-refresh-fired"
  exit 0
fi

if [[ "$#" -ne 7 ]]; then
  printf 'unexpected gh argument count: %s\n' "$#" >&2
  exit 2
fi

[[ "$1" == issue ]]
[[ "$2" == comment ]]
[[ "$3" == 89 ]]
[[ "$4" == --repo ]]
[[ "$5" == the9ball/.dotfiles ]]
[[ "$6" == --body-file ]]
[[ -n "${GH_CAPTURE_FILE:-}" ]]
cp -- "$7" "$GH_CAPTURE_FILE"
MOCK_GH
chmod +x -- "$mock_bin/gh"
export PATH="$mock_bin:$PATH"
cd "$test_root"

VAR='expanded value'
cat > "$test_root/body.md" <<'BODY'
Issue #89 body transport fixture.

Backticks: `gh auth refresh`
Command substitution: $(touch body-transport-evaluated)
Parameter expansion: $VAR and ${HOME}
Quotes: 'single-quoted' and "double-quoted"

Multiline Markdown:
```sh
printf '%s\n' "$VAR"
```
BODY

GH_CAPTURE_FILE="$test_root/captured.md" gh issue comment 89 --repo the9ball/.dotfiles --body-file "$test_root/body.md"
cmp -- "$test_root/body.md" "$test_root/captured.md"
[[ ! -e "$test_root/gh-auth-refresh-fired" ]]
[[ ! -e "$test_root/body-transport-evaluated" ]]
printf 'body transport preserves literal content without executing its text\n'
