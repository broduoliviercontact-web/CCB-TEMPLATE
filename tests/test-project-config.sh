#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd); CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-config.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }
trap 'cleanup' EXIT HUP INT TERM
tests=0; pass() { tests=$((tests + 1)); }; fail() { echo "FAIL: $1" >&2; exit 1; }
contains() { printf '%s\n' "$1" | grep -Fq -- "$2" || fail "$3"; pass; }
start_run() { sequence=$((sequence + 1)); started=$(CCB_TEST_RUN_TIMESTAMP="$(printf '20260730-%06d' "$sequence")" "$CLI" workflow start feature "$target") || fail "start $1"; run_id=$(printf '%s\n' "$started" | sed -n 's/^Run ID: //p'); run_dir="$target/.ccb/runs/$run_id"; }

target="$WORK/project with spaces"; "$CLI" init "$target" --profile audio --yes >/dev/null || fail init
output=$("$CLI" config "$target") || fail 'config without runs'
contains "$output" 'Workflow reliability' 'reliability section missing'
contains "$output" 'Manual retry support: enabled' 'retry support missing'
contains "$output" 'Maximum attempts per step: 3' 'retry maximum missing'
contains "$output" 'Cancelled runs: 0' 'initial cancelled count'
contains "$output" 'Runs with archived retries: 0' 'initial retry count'
contains "$output" 'Archived failed attempts: 0' 'initial archive count'
contains "$output" 'Runs at retry limit: 0' 'initial limit count'
contains "$output" 'Workflow observability' 'observability section missing'
contains "$output" 'History command: enabled' 'history support missing'
contains "$output" 'Runs with execution history: 0' 'initial execution history count'
[ ! -e "$target/.ccb/runs" ] || fail 'config created runs directory'; pass

sequence=0; start_run pending
printf 'CONFIG_SECRET_MARKDOWN\n' >>"$run_dir/context.md"
output=$("$CLI" config "$target") || fail 'config pending run'
contains "$output" 'Valid runs: 1' 'pending run invalid'
contains "$output" 'Runs with execution history: 0' 'pending run has history'

start_run retry
"$CLI" workflow resume "$run_id" "$target" >/dev/null || fail 'retry resume'
CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=unavailable "$CLI" workflow execute-step "$run_id" "$target" >/dev/null 2>&1
"$CLI" workflow retry-step "$run_id" "$target" >/dev/null || fail 'retry archive one'
output=$("$CLI" config "$target") || fail 'config one retry'
contains "$output" 'Runs with archived retries: 1' 'one retry run count'
contains "$output" 'Archived failed attempts: 1' 'one archive count'
CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=timeout "$CLI" workflow execute-step "$run_id" "$target" >/dev/null 2>&1
"$CLI" workflow retry-step "$run_id" "$target" >/dev/null || fail 'retry archive two'
CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=invalid-response "$CLI" workflow execute-step "$run_id" "$target" >/dev/null 2>&1
output=$("$CLI" config "$target") || fail 'config retry limit'
contains "$output" 'Archived failed attempts: 2' 'two archive count'
contains "$output" 'Runs at retry limit: 1' 'retry limit count'

start_run cancelled
"$CLI" workflow cancel "$run_id" "$target" >/dev/null || fail cancel

response="$WORK/response"; printf '%s\n' 'Config automation response.' >"$response"
start_run succeeded
CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow run "$run_id" "$target" >/dev/null || fail 'successful automation'
start_run failed
CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=unavailable "$CLI" workflow run "$run_id" "$target" >/dev/null 2>&1
start_run interrupted
CCB_TEST_MODE=1 CCB_TEST_ORCHESTRATION_FAIL_POINT=after-resume "$CLI" workflow run "$run_id" "$target" >/dev/null 2>&1

mkdir "$target/.ccb/runs/invalid-run"
before_files=$(find "$target" -type f -exec cksum {} \; | LC_ALL=C sort); before_dirs=$(find "$target" -type d | LC_ALL=C sort)
output=$("$CLI" config "$target") || fail 'combined config'
after_files=$(find "$target" -type f -exec cksum {} \; | LC_ALL=C sort); after_dirs=$(find "$target" -type d | LC_ALL=C sort)
[ "$before_files" = "$after_files" ] && [ "$before_dirs" = "$after_dirs" ] || fail 'config mutated project'; pass
contains "$output" 'Total runs: 7' 'combined total count'
contains "$output" 'Valid runs: 6' 'combined valid count'
contains "$output" 'Invalid runs: 1' 'combined invalid count'
contains "$output" 'Cancelled runs: 1' 'combined cancelled count'
contains "$output" 'Runs with archived retries: 1' 'combined retry count'
contains "$output" 'Archived failed attempts: 2' 'combined archive count'
contains "$output" 'Runs at retry limit: 1' 'combined limit count'
contains "$output" 'Runs with execution history: 3' 'combined history count'
contains "$output" 'Runs with successful orchestration: 1' 'successful orchestration count'
contains "$output" 'Runs with failed orchestration: 1' 'failed orchestration count'
contains "$output" 'Runs with interrupted orchestration: 1' 'interrupted orchestration count'
if printf '%s' "$output" | grep -Eq 'CONFIG_SECRET_MARKDOWN|request-failed|invalid-response|Config automation response'; then fail 'config exposed sensitive content'; fi; pass
if "$CLI" config >/dev/null 2>&1; then fail 'config accepted missing target'; fi; pass

printf 'project config tests passed: %s/%s\n' "$tests" "$tests"
