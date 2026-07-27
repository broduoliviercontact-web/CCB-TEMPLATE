#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-history.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }
trap 'cleanup' EXIT HUP INT TERM
tests=0
pass() { tests=$((tests + 1)); }
fail() { echo "FAIL: $1" >&2; exit 1; }
run() { output=$("$@" 2>&1); status=$?; }
contains() { printf '%s\n' "$1" | grep -Fq -- "$2" || fail "$3"; pass; }
sequence=0

new_pending() {
  label=$1; sequence=$((sequence + 1)); project="$WORK/$label-$sequence"
  "$CLI" init "$project" --yes >/dev/null || fail "init $label"
  stamp=$(printf '20260729-%06d' "$sequence")
  start=$(CCB_TEST_MODE=1 CCB_TEST_RUN_TIMESTAMP="$stamp" CCB_TEST_NOW=2026-07-29T10:00:00+0200 "$CLI" workflow start feature "$project") || fail "start $label"
  run_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p'); run_dir="$project/.ccb/runs/$run_id"; step_dir="$run_dir/01-manager"
}

new_in_progress() {
  new_pending "$1"
  CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T10:01:00+0200 "$CLI" workflow resume "$run_id" "$project" >/dev/null || fail "resume $1"
}

new_failed() {
  new_in_progress "$1"
  run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T10:02:00+0200 CCB_TEST_PROVIDER_ERROR=unavailable "$CLI" workflow execute-step "$run_id" "$project"
  [ "$status" -eq 1 ] || fail "failed execution $1"
}

new_archived() {
  new_failed "$1"
  "$CLI" workflow retry-step "$run_id" "$project" >/dev/null || fail "archive $1"
  archive="$step_dir/attempts/001.conf"
}

assert_history_invalid() {
  run "$CLI" workflow history "$run_id" "$project"
  [ "$status" -eq 1 ] || fail "$1"
  pass
}

empty="$WORK/empty"; "$CLI" init "$empty" --yes >/dev/null
run "$CLI" workflow history; [ "$status" -eq 2 ] || fail 'missing arguments'; pass
run "$CLI" workflow history bad/id "$empty"; [ "$status" -eq 2 ] || fail 'invalid run id'; pass
run "$CLI" workflow history 20260729-000000-feature "$empty"; [ "$status" -eq 1 ] || fail 'absent run'; pass
run "$CLI" workflow history --latest "$empty"; [ "$status" -eq 1 ] || fail 'latest absent run'; pass
run "$CLI" workflow history 20260729-000000-feature "$empty" extra; [ "$status" -eq 2 ] || fail 'extra argument'; pass
run "$CLI" workflow history --unknown "$empty"; [ "$status" -eq 2 ] || fail 'unknown option'; pass

new_pending initial
before_files=$(find "$project" -type f -exec cksum {} \; | LC_ALL=C sort); before_dirs=$(find "$project" -type d | LC_ALL=C sort)
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail "initial history: $output"; pass
contains "$output" 'Event: run-created' 'run-created missing'
contains "$output" 'Attempts: 0/3' 'unexecuted attempt summary'
contains "$output" 'Current execution: none' 'unexecuted execution summary'
[ "$(printf '%s\n' "$output" | grep -c '^1\. manager$')" -eq 1 ] && [ "$(printf '%s\n' "$output" | grep -c '^2\. developer$')" -eq 1 ] && [ "$(printf '%s\n' "$output" | grep -c '^3\. reviewer$')" -eq 1 ] || fail 'all steps missing'; pass
after_files=$(find "$project" -type f -exec cksum {} \; | LC_ALL=C sort); after_dirs=$(find "$project" -type d | LC_ALL=C sort)
[ "$before_files" = "$after_files" ] && [ "$before_dirs" = "$after_dirs" ] || fail 'history mutated project'; pass
run "$CLI" workflow history --latest "$project"; [ "$status" -eq 0 ] || fail 'latest history'; pass
fake_bin="$WORK/fake-bin"; mkdir "$fake_bin"; provider_witness="$WORK/provider-called"; network_witness="$WORK/network-called"
printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "$provider_witness" >"$fake_bin/ollama"; chmod +x "$fake_bin/ollama"
printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "$network_witness" >"$fake_bin/curl"; chmod +x "$fake_bin/curl"
run env PATH="$fake_bin:$PATH" "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'isolated history'; pass
[ ! -e "$provider_witness" ] && [ ! -e "$network_witness" ] || fail 'history invoked provider or network'; pass

new_in_progress succeeded
response="$WORK/response"; printf '%s\n' 'successful opaque response' >"$response"
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T10:02:00+0200 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow execute-step "$run_id" "$project"
[ "$status" -eq 0 ] || fail 'successful execution'; run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'success history'; pass
contains "$output" 'Event: execution-succeeded' 'execution success event'
contains "$output" 'Attempts: 1/3' 'success attempts summary'
contains "$output" 'Current execution: succeeded' 'success summary status'
timeline_times=$(printf '%s\n' "$output" | awk '/^[0-9]+\. [0-9][0-9][0-9][0-9]-/ { print $2 }')
[ "$timeline_times" = "$(printf '%s\n' "$timeline_times" | LC_ALL=C sort)" ] || fail 'timeline not sorted'; pass

new_failed failed
printf 'SECRET-CONTEXT\n' >>"$run_dir/context.md"; printf 'SECRET-RESULT\n' >>"$step_dir/result.md"
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'failed history'; pass
contains "$output" 'Event: execution-failed' 'execution failure event'
contains "$output" 'Error: present' 'masked error marker'
if printf '%s' "$output" | grep -Eq 'request-failed|SECRET-CONTEXT|SECRET-RESULT|# Step Result'; then fail 'history exposed sensitive content'; fi; pass

new_archived prepared
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'prepared history'; pass
contains "$output" 'Event: retry-prepared' 'retry prepared event'
contains "$output" 'Archived failures: 1' 'archive summary'
contains "$output" 'Attempts: 2/3' 'prepared attempt summary'

run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T10:03:00+0200 CCB_TEST_PROVIDER_ERROR=timeout "$CLI" workflow execute-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'second failure'
"$CLI" workflow retry-step "$run_id" "$project" >/dev/null || fail 'second retry'
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'third attempt history'; pass
contains "$output" 'Archived failures: 2' 'two archives summary'
contains "$output" 'Attempts: 3/3' 'third attempt summary'
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T10:04:00+0200 CCB_TEST_PROVIDER_ERROR=invalid-response "$CLI" workflow execute-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'third failure'
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'limit history'; pass
contains "$output" 'Attempt: 3/3' 'limit event missing'

new_in_progress completed-step
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T10:02:00+0200 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow execute-step "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'completed execute'
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T10:03:00+0200 "$CLI" workflow complete-step "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'completed step'
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'completed step history'; pass
contains "$output" 'Event: step-completed' 'step completed event'

new_pending automated
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T11:00:00+0200 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow run "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'automation success'
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'automation success history'; pass
contains "$output" 'Automation: succeeded' 'automation success summary'
contains "$output" 'Event: orchestration-succeeded' 'automation success event'
contains "$output" 'Event: run-completed' 'run completed event'

new_pending automation-failed
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T11:10:00+0200 CCB_TEST_PROVIDER_ERROR=unavailable "$CLI" workflow run "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'automation failure setup'
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'automation failure history'; pass
contains "$output" 'Automation: failed' 'automation failure summary'
contains "$output" 'Event: orchestration-failed' 'automation failure event'

new_pending automation-interrupted
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T11:20:00+0200 CCB_TEST_ORCHESTRATION_FAIL_POINT=after-resume "$CLI" workflow run "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'automation interruption setup'
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'automation interrupted history'; pass
contains "$output" 'Automation: interrupted' 'automation interruption summary'
contains "$output" 'Event: orchestration-interrupted' 'automation interruption event'

new_pending cancelled
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T12:00:00+0200 "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'cancel history setup'
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'cancelled history'; pass
contains "$output" 'Cancelled: yes' 'cancelled summary'
contains "$output" 'Event: run-cancelled' 'cancelled event'

new_pending stable-order
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T10:00:00+0200 "$CLI" workflow resume "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'stable resume'
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-29T10:00:00+0200 CCB_TEST_PROVIDER_ERROR=unavailable "$CLI" workflow execute-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'stable failure'
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'stable history'; pass
created_line=$(printf '%s\n' "$output" | grep -n 'Event: run-created' | cut -d: -f1); started_line=$(printf '%s\n' "$output" | grep -n 'Event: step-started' | cut -d: -f1); failed_line=$(printf '%s\n' "$output" | grep -n 'Event: execution-failed' | cut -d: -f1)
[ "$created_line" -lt "$started_line" ] && [ "$started_line" -lt "$failed_line" ] || fail 'stable same-timestamp order'; pass

new_archived attempts-symlink
rm -f "$archive"; rmdir "$step_dir/attempts"; ln -s "$WORK" "$step_dir/attempts"; assert_history_invalid 'attempts symlink accepted'
new_archived archive-symlink
rm -f "$archive"; printf '%s\n' outside >"$WORK/outside"; ln -s "$WORK/outside" "$archive"; assert_history_invalid 'archive symlink accepted'
new_archived invalid-name
printf '%s\n' invalid >"$step_dir/attempts/bad.conf"; assert_history_invalid 'invalid archive name accepted'
new_archived hole
cp "$archive" "$step_dir/attempts/003.conf"; sed 's/CCB_ATTEMPT_NUMBER=1/CCB_ATTEMPT_NUMBER=3/' "$step_dir/attempts/003.conf" >"$WORK/archive.003"; cp "$WORK/archive.003" "$step_dir/attempts/003.conf"; assert_history_invalid 'archive hole accepted'
new_archived number-mismatch
sed 's/CCB_ATTEMPT_NUMBER=1/CCB_ATTEMPT_NUMBER=2/' "$archive" >"$WORK/archive.number"; cp "$WORK/archive.number" "$archive"; assert_history_invalid 'archive number mismatch accepted'
new_archived provider-mismatch
sed 's/CCB_STEP_PROVIDER=ollama/CCB_STEP_PROVIDER=remote/' "$step_dir/step.conf" >"$WORK/step.provider"; cp "$WORK/step.provider" "$step_dir/step.conf"; assert_history_invalid 'archive provider mismatch accepted'
new_archived model-mismatch
sed 's/CCB_ATTEMPT_MODEL=qwen3:8b/CCB_ATTEMPT_MODEL=qwen3:4b/' "$archive" >"$WORK/archive.model"; cp "$WORK/archive.model" "$archive"; assert_history_invalid 'archive model mismatch accepted'
new_archived too-many
for n in 2 3 4; do sed "s/CCB_ATTEMPT_NUMBER=1/CCB_ATTEMPT_NUMBER=$n/" "$archive" >"$step_dir/attempts/00$n.conf"; done
assert_history_invalid 'more than three archives accepted'
new_archived execution-count
sed 's/CCB_EXECUTION_ATTEMPT=2/CCB_EXECUTION_ATTEMPT=3/' "$step_dir/execution.conf" >"$WORK/execution.count"; cp "$WORK/execution.count" "$step_dir/execution.conf"; assert_history_invalid 'incoherent execution attempt accepted'
new_archived timestamp-order
sed 's/CCB_ATTEMPT_COMPLETED_AT=2026-07-29T10:02:00+0200/CCB_ATTEMPT_COMPLETED_AT=2026-07-29T09:59:00+0200/' "$archive" >"$WORK/archive.timestamp"; cp "$WORK/archive.timestamp" "$archive"; assert_history_invalid 'incoherent archive timestamp accepted'

new_pending old-d2
run "$CLI" workflow history "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'old D2 run rejected'; pass
[ "$(cat "$ROOT/VERSION")" = 1.7.1 ] || fail 'version changed'; pass
managed=$(find "$project/.ccb" -type f ! -path '*/runs/*' | wc -l | tr -d ' '); managed=$((managed + 1)); [ "$managed" -eq 7 ] || fail 'init file count'; pass

printf 'project history tests passed: %s/%s\n' "$tests" "$tests"
