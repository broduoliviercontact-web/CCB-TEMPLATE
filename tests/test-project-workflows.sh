#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd); CLI="$ROOT/scripts/ccb.sh"; WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-workflows-test.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }; trap 'cleanup' EXIT HUP INT TERM
fail(){ echo "FAIL: $*" >&2; exit 1; }; run(){ output=$("$@" 2>&1); status=$?; }
project="$WORK/project with spaces"; run "$CLI" init "$project" --yes; [ "$status" -eq 0 ] || fail init; [ -f "$project/.ccb/workflows.conf" ] || fail missing
run "$CLI" workflows "$project"; [ "$status" -eq 0 ] || fail list; printf '%s' "$output" | grep -Fq 'feature' || fail feature
run "$CLI" workflow show feature "$project"; [ "$status" -eq 0 ] || fail show; printf '%s' "$output" | grep -Fq 'Execution: disabled' || fail disabled
run "$CLI" workflow plan feature "$project"; [ "$status" -eq 0 ] || fail plan; printf '%s' "$output" | grep -Fq 'No agents will be executed' || fail noexecution
run "$CLI" workflow validate "$project"; [ "$status" -eq 0 ] || fail validate
run "$CLI" init "$project" --yes; [ "$status" -eq 0 ] || fail idempotent; printf '%s' "$output" | grep -Fq 'SKIP .ccb/workflows.conf' || fail skip
printf 'project workflows tests passed\n'
