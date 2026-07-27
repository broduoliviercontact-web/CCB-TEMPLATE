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
printf '%s' "$output" | grep -F 'Runs directory: absent' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Total runs: 0' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Automation support: sequential' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Runs automated successfully: 0' >/dev/null || exit 1
[ ! -e "$target/.ccb/runs" ] || exit 1
mkdir "$target/.ccb/runs"
output=$("$CLI" config "$target") || exit 1
printf '%s' "$output" | grep -F 'Runs directory: present' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Latest run: none' >/dev/null || exit 1
rmdir "$target/.ccb/runs"

start_output=$("$CLI" workflow start feature "$target") || exit 1
run_id=$(printf '%s\n' "$start_output" | sed -n 's/^Run ID: //p')
run_dir="$target/.ccb/runs/$run_id"
printf 'MARKDOWN_SECRET_MUST_NOT_APPEAR\n' >>"$run_dir/context.md"
before=$(find "$target/.ccb/runs" -type f -exec cksum {} \; | sort)
output=$("$CLI" config "$target") || exit 1
after=$(find "$target/.ccb/runs" -type f -exec cksum {} \; | sort)
[ "$before" = "$after" ] || exit 1
printf '%s' "$output" | grep -F 'Pending runs: 1' >/dev/null || exit 1
printf '%s' "$output" | grep -F "Latest run: $run_id" >/dev/null || exit 1
if printf '%s' "$output" | grep -F 'MARKDOWN_SECRET_MUST_NOT_APPEAR' >/dev/null; then exit 1; fi
"$CLI" workflow resume "$run_id" "$target" >/dev/null || exit 1
output=$("$CLI" config "$target") || exit 1
printf '%s' "$output" | grep -F 'In-progress runs: 1' >/dev/null || exit 1

cp -R "$run_dir" "$target/.ccb/runs/20260727-235959-feature-2"
sed "s/CCB_RUN_ID=$run_id/CCB_RUN_ID=20260727-235959-feature-2/; s/CCB_RUN_STATUS=in-progress/CCB_RUN_STATUS=blocked/" "$run_dir/run.conf" >"$target/.ccb/runs/20260727-235959-feature-2/run.conf"
sed 's/CCB_STEP_STATUS=in-progress/CCB_STEP_STATUS=blocked/' "$run_dir/01-manager/step.conf" >"$target/.ccb/runs/20260727-235959-feature-2/01-manager/step.conf"
cp -R "$run_dir" "$target/.ccb/runs/20260727-235959-feature-10"
sed "s/CCB_RUN_ID=$run_id/CCB_RUN_ID=20260727-235959-feature-10/; s/CCB_RUN_STATUS=in-progress/CCB_RUN_STATUS=cancelled/" "$run_dir/run.conf" >"$target/.ccb/runs/20260727-235959-feature-10/run.conf"
cp -R "$run_dir" "$target/.ccb/runs/20260727-110000-feature"
sed "s/CCB_RUN_ID=$run_id/CCB_RUN_ID=20260727-110000-feature/; s/CCB_RUN_STATUS=in-progress/CCB_RUN_STATUS=completed/" "$run_dir/run.conf" >"$target/.ccb/runs/20260727-110000-feature/run.conf"
mkdir "$target/.ccb/runs/invalid-run"
printf 'CCB_EXECUTION_VERSION=1\nCCB_EXECUTION_STATUS=succeeded\nCCB_EXECUTION_PROVIDER=ollama\nCCB_EXECUTION_MODEL=qwen3:8b\nCCB_EXECUTION_ATTEMPT=1\nCCB_EXECUTION_STARTED_AT=2026-07-27T10:00:00+0200\nCCB_EXECUTION_COMPLETED_AT=2026-07-27T10:01:00+0200\nCCB_EXECUTION_ERROR=\n' >"$run_dir/01-manager/execution.conf"
printf 'CCB_EXECUTION_VERSION=1\nCCB_EXECUTION_STATUS=failed\nCCB_EXECUTION_PROVIDER=ollama\nCCB_EXECUTION_MODEL=qwen3:8b\nCCB_EXECUTION_ATTEMPT=1\nCCB_EXECUTION_STARTED_AT=2026-07-27T10:00:00+0200\nCCB_EXECUTION_COMPLETED_AT=2026-07-27T10:01:00+0200\nCCB_EXECUTION_ERROR=request-failed\n' >"$target/.ccb/runs/20260727-235959-feature-2/01-manager/execution.conf"
output=$("$CLI" config "$target") || exit 1
printf '%s' "$output" | grep -F 'Total runs: 5' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Valid runs: 4' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Invalid runs: 1' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Blocked runs: 1' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Cancelled runs: 1' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Completed runs: 1' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Latest run: 20260727-235959-feature-10' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Latest status: cancelled' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Runs with succeeded execution: 1' >/dev/null || exit 1
printf '%s' "$output" | grep -F 'Runs with failed execution: 1' >/dev/null || exit 1
if "$CLI" config >/dev/null 2>&1; then exit 1; fi
printf 'project config tests passed\n'
