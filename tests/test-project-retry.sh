#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-retry.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }
trap 'cleanup' EXIT HUP INT TERM
tests=0
pass() { tests=$((tests + 1)); }
fail() { echo "FAIL: $1" >&2; exit 1; }
run() { output=$("$@" 2>&1); status=$?; }
contains() { printf '%s\n' "$1" | grep -Fq -- "$2" || fail "$3"; pass; }

sequence=0
new_failed() {
  label=$1; sequence=$((sequence + 1)); project="$WORK/$label-$sequence"
  "$CLI" init "$project" --yes >/dev/null || fail "init $label"
  stamp=$(printf '20260727-%06d' "$sequence")
  start=$(CCB_TEST_RUN_TIMESTAMP="$stamp" "$CLI" workflow start feature "$project") || fail "start $label"
  run_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p'); run_dir="$project/.ccb/runs/$run_id"; step_dir="$run_dir/01-manager"
  "$CLI" workflow resume "$run_id" "$project" >/dev/null || fail "resume $label"
  run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=unavailable "$CLI" workflow execute-step "$run_id" "$project"
  [ "$status" -eq 1 ] || fail "provider failure $label"
  grep -Fqx 'CCB_EXECUTION_STATUS=failed' "$step_dir/execution.conf" || fail "failed metadata $label"
}

empty="$WORK/empty"; "$CLI" init "$empty" --yes >/dev/null
run "$CLI" workflow retry-step; [ "$status" -eq 2 ] || fail 'missing arguments'; pass
run "$CLI" workflow retry-step invalid/id "$empty"; [ "$status" -eq 2 ] || fail 'invalid id code'; pass
run "$CLI" workflow retry-step 20260727-000000-feature "$empty"; [ "$status" -eq 1 ] || fail 'absent run code'; pass
run "$CLI" workflow retry-step --latest "$empty"; [ "$status" -eq 1 ] || fail 'latest without run'; pass
run "$CLI" workflow retry-step 20260727-000000-feature "$empty" extra; [ "$status" -eq 2 ] || fail 'extra argument'; pass

new_failed explicit
printf '\nSECRET-MARKDOWN $(touch "%s") `touch "%s"` ${HOME} <script>alert(1)</script>\n' "$WORK/witness" "$WORK/witness-2" >>"$run_dir/context.md"
before_run=$(cksum "$run_dir/run.conf"); before_step=$(cksum "$step_dir/step.conf"); before_context=$(cksum "$run_dir/context.md"); before_input=$(cksum "$step_dir/input.md"); before_result=$(cksum "$step_dir/result.md")
run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 0 ] || fail "explicit retry: $output"; pass
contains "$output" 'Provider executed: no' 'retry executed provider'
run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'already prepared retry accepted'; pass
[ "$before_run" = "$(cksum "$run_dir/run.conf")" ] && [ "$before_step" = "$(cksum "$step_dir/step.conf")" ] && [ "$before_context" = "$(cksum "$run_dir/context.md")" ] && [ "$before_input" = "$(cksum "$step_dir/input.md")" ] && [ "$before_result" = "$(cksum "$step_dir/result.md")" ] || fail 'retry changed immutable files'; pass
[ -f "$step_dir/attempts/001.conf" ] && [ ! -L "$step_dir/attempts/001.conf" ] || fail 'attempt 1 archive unsafe'; pass
grep -Fqx 'CCB_ATTEMPT_NUMBER=1' "$step_dir/attempts/001.conf" && grep -Fqx 'CCB_ATTEMPT_STATUS=failed' "$step_dir/attempts/001.conf" || fail 'attempt 1 archive content'; pass
if grep -Eq 'SECRET-MARKDOWN|touch|script|HOME|prompt|context.md|input.md|HTTP' "$step_dir/attempts/001.conf"; then fail 'sensitive content archived'; fi; pass
[ -z "$(find "$step_dir" \( -name '.ccb-retry-transaction.*' -o -name '.retry-publish.*' \) -print -quit)" ] || fail 'successful retry left temporary'; pass
grep -Fqx 'CCB_EXECUTION_ATTEMPT=2' "$step_dir/execution.conf" && grep -Fqx 'CCB_EXECUTION_ERROR=retry-prepared' "$step_dir/execution.conf" || fail 'attempt 2 not prepared'; pass
[ ! -e "$WORK/witness" ] && [ ! -e "$WORK/witness-2" ] || fail 'anti-injection witness created'; pass
status_output=$("$CLI" workflow status "$run_id" "$project") || fail status
contains "$status_output" 'Execution attempt: 2' 'status attempt'
contains "$status_output" 'Archived attempts: 1' 'status archive count'
inspect_output=$("$CLI" workflow inspect "$run_id" "$project") || fail inspect
contains "$inspect_output" 'Maximum attempts: 3' 'inspect maximum'
contains "$inspect_output" 'Last archived status: failed' 'inspect archived status'
history_output=$("$CLI" workflow history "$run_id" "$project") || fail history
contains "$history_output" 'Event: retry-prepared' 'history retry event'
if printf '%s' "$inspect_output" | grep -Fq 'SECRET-MARKDOWN'; then fail 'inspect leaked content'; fi; pass

run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=timeout "$CLI" workflow execute-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'attempt 2 failure'; pass
grep -Fqx 'CCB_EXECUTION_ATTEMPT=2' "$step_dir/execution.conf" || fail 'execute did not use attempt 2'; pass
run "$CLI" workflow retry-step --latest "$project"; [ "$status" -eq 0 ] || fail 'latest retry attempt 2'; pass
grep -Fqx 'CCB_ATTEMPT_NUMBER=2' "$step_dir/attempts/002.conf" && grep -Fqx 'CCB_EXECUTION_ATTEMPT=3' "$step_dir/execution.conf" || fail 'attempt 3 preparation'; pass
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=invalid-response "$CLI" workflow execute-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'attempt 3 failure'; pass
run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'attempt 4 accepted'
contains "$output" 'workflow step retry limit reached' 'retry limit diagnostic'

new_failed automatic
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$WORK/missing" "$CLI" workflow run "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'workflow run retried automatically'; pass
grep -Fqx 'CCB_EXECUTION_ATTEMPT=1' "$step_dir/execution.conf" || fail 'automatic retry changed attempt'; pass
"$CLI" workflow retry-step "$run_id" "$project" >/dev/null || fail 'prepare automation retry'
printf '%s\n' 'manual retry automation result' >"$WORK/response"
CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$WORK/response" "$CLI" workflow run "$run_id" "$project" >/dev/null || fail 'workflow run after manual retry'; pass
grep -Fqx 'CCB_RUN_STATUS=completed' "$run_dir/run.conf" || fail 'workflow did not complete after retry'; pass
grep -Fqx 'CCB_EXECUTION_ATTEMPT=2' "$step_dir/execution.conf" || fail 'workflow run wrong retry attempt'; pass

new_failed incompatible
cp "$step_dir/execution.conf" "$WORK/failed.conf"
cp "$run_dir/run.conf" "$WORK/incompatible-run.conf"
for incompatible_status in pending blocked completed cancelled; do
  sed "s/CCB_RUN_STATUS=in-progress/CCB_RUN_STATUS=$incompatible_status/" "$WORK/incompatible-run.conf" >"$run_dir/run.conf"
  run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail "$incompatible_status run retried"
  pass
done
cp "$WORK/incompatible-run.conf" "$run_dir/run.conf"
cp "$step_dir/step.conf" "$WORK/incompatible-step.conf"
sed 's/CCB_STEP_STATUS=in-progress/CCB_STEP_STATUS=completed/; s/^CCB_STEP_COMPLETED_AT=.*/CCB_STEP_COMPLETED_AT=2026-07-27T12:00:00+0200/' "$WORK/incompatible-step.conf" >"$step_dir/step.conf"
run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'completed step retried'; pass
cp "$WORK/incompatible-step.conf" "$step_dir/step.conf"
mv "$step_dir/execution.conf" "$WORK/missing-execution.conf"
run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'missing execution retried'; pass
mv "$WORK/missing-execution.conf" "$step_dir/execution.conf"
sed 's/CCB_EXECUTION_STATUS=failed/CCB_EXECUTION_STATUS=running/; s/^CCB_EXECUTION_COMPLETED_AT=.*/CCB_EXECUTION_COMPLETED_AT=/; s/^CCB_EXECUTION_ERROR=.*/CCB_EXECUTION_ERROR=/' "$WORK/failed.conf" >"$step_dir/execution.conf"
run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'running execution retried'; pass
sed 's/CCB_EXECUTION_STATUS=failed/CCB_EXECUTION_STATUS=succeeded/; s/^CCB_EXECUTION_ERROR=.*/CCB_EXECUTION_ERROR=/' "$WORK/failed.conf" >"$step_dir/execution.conf"
run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'succeeded execution retried'; pass
cp "$WORK/failed.conf" "$step_dir/execution.conf"; printf '\nExplicit result.\n' >>"$step_dir/result.md"
run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'explicit result retried'; pass

new_failed locks
mkdir "$run_dir/.ccb-execution-lock"; run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'execution lock ignored'; rmdir "$run_dir/.ccb-execution-lock"; pass
mkdir "$run_dir/.ccb-orchestration-lock"; run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'orchestration lock ignored'; rmdir "$run_dir/.ccb-orchestration-lock"; pass
mkdir "$run_dir/.ccb-transaction.residual"; run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'transaction residue ignored'; rmdir "$run_dir/.ccb-transaction.residual"; pass

new_failed symlinkdir
ln -s "$WORK" "$step_dir/attempts"
run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'attempts symlink accepted'; rm -f "$step_dir/attempts"; pass
new_failed symlinkarchive
mkdir "$step_dir/attempts"; printf '%s\n' outside >"$WORK/outside"; ln -s "$WORK/outside" "$step_dir/attempts/001.conf"
run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'archive symlink accepted'; pass

printf 'CCB_ATTEMPT_VERSION=1\nCCB_ATTEMPT_NUMBER=1\nCCB_ATTEMPT_STATUS=failed\nCCB_ATTEMPT_PROVIDER=ollama\nCCB_ATTEMPT_MODEL=qwen3:8b\nCCB_ATTEMPT_STARTED_AT=2026-07-27T10:00:00+0200\nCCB_ATTEMPT_COMPLETED_AT=2026-07-27T10:01:00+0200\nCCB_ATTEMPT_ERROR=request-failed\n' >"$WORK/valid-attempt.conf"
cp "$WORK/valid-attempt.conf" "$WORK/invalid-attempt.conf"; printf 'CCB_UNKNOWN=1\n' >>"$WORK/invalid-attempt.conf"
if ( . "$ROOT/scripts/runtime/runtime-lib.sh"; . "$ROOT/scripts/project-execution-lib.sh"; project_execution_attempt_parse_conf "$WORK/invalid-attempt.conf" ); then fail 'unknown archive key accepted'; fi; pass
cp "$WORK/valid-attempt.conf" "$WORK/invalid-attempt.conf"; printf 'CCB_ATTEMPT_STATUS=failed\n' >>"$WORK/invalid-attempt.conf"
if ( . "$ROOT/scripts/runtime/runtime-lib.sh"; . "$ROOT/scripts/project-execution-lib.sh"; project_execution_attempt_parse_conf "$WORK/invalid-attempt.conf" ); then fail 'duplicate archive key accepted'; fi; pass

for point in before-archive after-archive before-execution-conf after-execution-conf; do
  new_failed "rollback-$point"; before=$(cksum "$step_dir/execution.conf")
  run env CCB_TEST_MODE=1 CCB_TEST_RETRY_FAIL_POINT="$point" "$CLI" workflow retry-step "$run_id" "$project"
  [ "$status" -eq 1 ] || fail "$point returned success"
  [ "$before" = "$(cksum "$step_dir/execution.conf")" ] || fail "$point changed execution metadata"
  [ ! -e "$step_dir/attempts/001.conf" ] || fail "$point left archive"
  [ -z "$(find "$step_dir" \( -name '.ccb-retry-transaction.*' -o -name '.retry-publish.*' \) -print -quit)" ] || fail "$point left temporary"
  run "$CLI" workflow retry-step "$run_id" "$project"; [ "$status" -eq 0 ] || fail "$point rollback was not retryable"
  pass
done

pending="$WORK/pending"; "$CLI" init "$pending" --yes >/dev/null
managed=$(find "$pending/.ccb" -type f | wc -l | tr -d ' '); managed=$((managed + 1)); [ "$managed" -eq 7 ] || fail 'init file count'; pass
start=$(CCB_TEST_RUN_TIMESTAMP=20260727-230000 "$CLI" workflow start feature "$pending"); pending_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p')
run "$CLI" workflow retry-step "$pending_id" "$pending"; [ "$status" -eq 1 ] || fail 'pending run retried'; pass
"$CLI" workflow cancel "$pending_id" "$pending" >/dev/null || fail 'cancel retry compatibility run'
run "$CLI" workflow retry-step "$pending_id" "$pending"; [ "$status" -eq 1 ] || fail 'cancelled run retried'; pass
[ "$(cat "$ROOT/VERSION")" = 1.7.1 ] || fail version; pass

printf 'project retry tests passed: %s/%s\n' "$tests" "$tests"
