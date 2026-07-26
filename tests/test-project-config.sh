#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-config.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }
trap 'cleanup' EXIT HUP INT TERM
target="$WORK/project with spaces"
"$CLI" init "$target" --profile audio --yes >/dev/null
output=$("$CLI" config "$target") || { echo 'FAIL: config rejected valid project' >&2; exit 1; }
printf '%s' "$output" | grep -F 'Profile: audio' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Provider: ollama' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Coder model:' >/dev/null || exit 1
if "$CLI" config >/dev/null 2>&1; then exit 1; fi
printf 'project config tests passed\n'
