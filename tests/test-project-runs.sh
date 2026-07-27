#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd); CLI="$ROOT/scripts/ccb.sh"; WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-runs-test.XXXXXX") || exit 1
cleanup(){ find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }; trap 'cleanup' EXIT HUP INT TERM
fail(){ echo "FAIL: $*" >&2; exit 1; }; run(){ output=$("$@" 2>&1); status=$?; }
project="$WORK/run project"; "$CLI" init "$project" --yes >/dev/null; [ ! -e "$project/.ccb/runs" ] || fail 'init created runs'
run "$CLI" workflow start feature "$project"; [ "$status" -eq 0 ] || fail start; printf '%s' "$output" | grep -Fq 'Execution: disabled' || fail execution
run_dir=$(find "$project/.ccb/runs" -mindepth 1 -maxdepth 1 -type d -print | head -1); [ -f "$run_dir/run.conf" ] && [ -f "$run_dir/context.md" ] || fail snapshot; [ -f "$run_dir/01-manager/step.conf" ] && [ -f "$run_dir/02-developer/input.md" ] && [ -f "$run_dir/03-reviewer/result.md" ] || fail steps
grep -Fqx 'CCB_RUN_STATUS=pending' "$run_dir/run.conf" || fail status; grep -Fqx 'CCB_STEP_STATUS=ready' "$run_dir/01-manager/step.conf" || fail ready
run "$CLI" workflow start nope "$project"; [ "$status" -eq 2 ] || fail invalid-workflow
run "$CLI" workflow status "$run_dir" "$project"; [ "$status" -eq 2 ] || fail invalid-run-id
run "$CLI" workflow status --latest "$project"; [ "$status" -eq 0 ] || fail latest; printf '%s' "$output" | grep -Fq 'Steps:' || fail status-output
run "$CLI" workflow inspect --latest "$project"; [ "$status" -eq 0 ] || fail inspect; printf '%s' "$output" | grep -Fq 'Result:' || fail inspect-output
printf 'project runs tests passed\n'
