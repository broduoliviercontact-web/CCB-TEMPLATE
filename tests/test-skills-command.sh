#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd); CLI="$ROOT/scripts/ccb.sh"; WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-skills-command.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }; trap 'cleanup' EXIT HUP INT TERM
"$CLI" init "$WORK/project with spaces" --yes >/dev/null
out=$("$CLI" skills "$WORK/project with spaces") || exit 1; printf '%s' "$out" | grep -F 'Mode: full' >/dev/null || exit 1
out=$("$CLI" skills "$WORK/project with spaces" --agent codex) || exit 1; printf '%s' "$out" | grep -F 'codex plugin add ponytail@ponytail' >/dev/null || exit 1
if "$CLI" skills "$WORK/project with spaces" --agent unknown >/dev/null 2>&1; then exit 1; fi
printf 'skills command tests passed\n'
