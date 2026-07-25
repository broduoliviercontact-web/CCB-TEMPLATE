#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
CLI="$TEMPLATE_ROOT/scripts/ccb.sh"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ccb-setup-test.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM
repo="$TEMP_ROOT/project"
mkdir -p "$repo"
git init -q "$repo"
git -C "$repo" config user.name "CCB Setup Test"
git -C "$repo" config user.email "ccb-setup-test@example.invalid"
printf 'fixture\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm fixture

"$CLI" setup "$repo" --profile react-web --dry-run | grep -Fq 'DRY RUN'
test ! -e "$repo/.ccb"
"$CLI" setup "$repo" --profile react-web --yes >/dev/null
test "$(cat "$repo/.ccb/active-profile")" = react-web
"$TEMPLATE_ROOT/scripts/validate-ccb.sh" "$repo" >/dev/null
if printf '' | "$CLI" setup "$repo" --profile generic >/dev/null 2>&1; then
  echo "non-interactive setup without --yes was accepted" >&2
  exit 1
fi
echo "[OK] guided setup integration tests passed"
