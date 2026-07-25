#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
CLI="$TEMPLATE_ROOT/scripts/ccb.sh"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ccb-cli-test.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

"$CLI" help >/dev/null
test "$("$CLI" version)" = 1.2.0
"$CLI" profiles | grep -Fq 'generic'
"$CLI" profile show generic | grep -Fq 'ID: generic'
if "$CLI" profile show unknown >/dev/null 2>&1; then echo "unknown profile was accepted" >&2; exit 1; fi
if "$CLI" unknown >/dev/null 2>&1; then echo "unknown command was accepted" >&2; exit 1; else test "$?" -eq 2; fi
NO_COLOR=1 "$CLI" profiles | grep -q 'generic'
CCB_ASCII=1 "$CLI" profiles | grep -q 'generic'
printf 'q\n' | "$CLI" | grep -q 'CCB CONTROL ROOM'

repo="$TEMP_ROOT/project"
mkdir -p "$repo"
git init -q "$repo"
git -C "$repo" config user.name "CCB CLI Test"
git -C "$repo" config user.email "ccb-cli-test@example.invalid"
printf 'fixture\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm fixture
"$CLI" install "$repo" --profile react-web >/dev/null
"$CLI" validate "$repo" >/dev/null
"$CLI" doctor "$repo" >/dev/null
"$CLI" status "$repo" | grep -Fq 'Active profile: react-web'

echo "[OK] CLI integration tests passed"
