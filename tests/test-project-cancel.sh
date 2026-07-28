#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-cancel.XXXXXX") || exit 1
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
  stamp=$(printf '20260728-%06d' "$sequence")
  start=$(CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-28T09:00:00+0200 CCB_TEST_RUN_TIMESTAMP="$stamp" "$CLI" workflow start feature "$project") || fail "start $label"
  run_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p')
  run_dir="$project/.ccb/runs/$run_id"; step_dir="$run_dir/01-manager"
}

new_in_progress() {
  new_pending "$1"
  "$CLI" workflow resume "$run_id" "$project" >/dev/null || fail "resume $1"
}

snapshot_cancelled_files() {
  cksum "$run_dir/run.conf" "$step_dir/step.conf" ${orchestration_file:+"$orchestration_file"}
}

assert_no_residue() {
  residue=$(find "$run_dir" \( -name '.ccb-transaction.*' -o -name '.ccb-retry-transaction.*' -o -name '.ccb-publish.*' -o -name '*.old' -o -name '*.new' \) -print -quit)
  [ -z "$residue" ] || fail "transaction residue remains: $residue"
  pass
}

empty="$WORK/empty"; "$CLI" init "$empty" --yes >/dev/null
run "$CLI" workflow cancel; [ "$status" -eq 2 ] || fail 'missing arguments code'; pass
run "$CLI" workflow cancel bad/id "$empty"; [ "$status" -eq 2 ] || fail 'invalid run id code'; pass
run "$CLI" workflow cancel 20260728-000000-feature "$empty"; [ "$status" -eq 1 ] || fail 'absent run code'; pass
run "$CLI" workflow cancel --latest "$empty"; [ "$status" -eq 1 ] || fail 'latest without run code'; pass
run "$CLI" workflow cancel 20260728-000000-feature "$empty" extra; [ "$status" -eq 2 ] || fail 'extra argument code'; pass

new_pending explicit
before_context=$(cksum "$run_dir/context.md"); before_input=$(cksum "$step_dir/input.md"); before_result=$(cksum "$step_dir/result.md")
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-28T10:00:00+0200 "$CLI" workflow cancel "$run_id" "$project"
[ "$status" -eq 0 ] || fail "explicit cancel: $output"; pass
contains "$output" 'Provider executed: no' 'cancel executed provider'
grep -Fqx 'CCB_RUN_STATUS=cancelled' "$run_dir/run.conf" || fail 'run not cancelled'; pass
grep -Fqx 'CCB_RUN_UPDATED_AT=2026-07-28T10:00:00+0200' "$run_dir/run.conf" || fail 'updated_at missing'; pass
grep -Fqx 'CCB_RUN_COMPLETED_AT=2026-07-28T10:00:00+0200' "$run_dir/run.conf" || fail 'completed_at missing'; pass
grep -Fqx 'CCB_STEP_STATUS=skipped' "$step_dir/step.conf" || fail 'ready step not skipped'; pass
grep -Fqx 'CCB_STEP_STATUS=pending' "$run_dir/02-developer/step.conf" && grep -Fqx 'CCB_STEP_STATUS=pending' "$run_dir/03-reviewer/step.conf" || fail 'future step changed'; pass
[ "$before_context" = "$(cksum "$run_dir/context.md")" ] && [ "$before_input" = "$(cksum "$step_dir/input.md")" ] && [ "$before_result" = "$(cksum "$step_dir/result.md")" ] || fail 'Markdown changed'; pass
status_output=$("$CLI" workflow status "$run_id" "$project") || fail status
contains "$status_output" 'Status: cancelled' 'status not cancelled'
contains "$status_output" 'Completed: 2026-07-28T10:00:00+0200' 'status completion missing'
contains "$status_output" 'Cancellation: final' 'status final missing'
inspect_output=$("$CLI" workflow inspect "$run_id" "$project") || fail inspect
contains "$inspect_output" 'Status: cancelled' 'inspect not cancelled'
if printf '%s' "$inspect_output" | grep -Fq '# Step'; then fail 'inspect leaked Markdown'; fi; pass
history_output=$("$CLI" workflow history "$run_id" "$project") || fail 'cancel history'
contains "$history_output" 'Event: run-cancelled' 'cancel history event'
before=$(cksum "$run_dir/run.conf" "$step_dir/step.conf")
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'second cancel succeeded'; contains "$output" 'workflow run is already cancelled' 'cancelled diagnostic'
[ "$before" = "$(cksum "$run_dir/run.conf" "$step_dir/step.conf")" ] || fail 'second cancel mutated run'; pass
for action in resume execute-step complete-step retry-step run; do
  run "$CLI" workflow "$action" "$run_id" "$project"
  [ "$status" -eq 1 ] || fail "$action accepted cancelled run"
  pass
done

new_pending latest
run "$CLI" workflow cancel --latest "$project"; [ "$status" -eq 0 ] || fail 'latest cancel'; pass

new_pending pending-step
sed 's/CCB_STEP_STATUS=ready/CCB_STEP_STATUS=pending/' "$step_dir/step.conf" >"$WORK/step.pending"
cp "$WORK/step.pending" "$step_dir/step.conf"
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'pending current step cancel'; pass
grep -Fqx 'CCB_STEP_STATUS=skipped' "$step_dir/step.conf" || fail 'pending current step not skipped'; pass

new_in_progress in-progress
printf 'opaque $(touch "%s")\n<script>alert(1)</script>\n' "$WORK/witness" >>"$run_dir/context.md"
printf 'opaque $(touch "%s")\n' "$WORK/witness-2" >>"$step_dir/input.md"
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=unavailable "$CLI" workflow execute-step "$run_id" "$project"
[ "$status" -eq 1 ] || fail 'failure preparation'; "$CLI" workflow retry-step "$run_id" "$project" >/dev/null || fail 'retry archive preparation'
before_result=$(cksum "$step_dir/result.md"); before_input=$(cksum "$step_dir/input.md"); before_execution=$(cksum "$step_dir/execution.conf"); before_archive=$(cksum "$step_dir/attempts/001.conf")
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 0 ] || fail "in-progress cancel: $output"; pass
grep -Fqx 'CCB_STEP_STATUS=blocked' "$step_dir/step.conf" || fail 'in-progress step not blocked'; pass
[ "$before_result" = "$(cksum "$step_dir/result.md")" ] && [ "$before_input" = "$(cksum "$step_dir/input.md")" ] && [ "$before_execution" = "$(cksum "$step_dir/execution.conf")" ] && [ "$before_archive" = "$(cksum "$step_dir/attempts/001.conf")" ] || fail 'execution history changed'; pass
[ ! -e "$WORK/witness" ] && [ ! -e "$WORK/witness-2" ] || fail 'untrusted content executed'; pass

new_in_progress blocked
sed 's/CCB_RUN_STATUS=in-progress/CCB_RUN_STATUS=blocked/' "$run_dir/run.conf" >"$WORK/run.blocked"; cp "$WORK/run.blocked" "$run_dir/run.conf"
sed 's/CCB_STEP_STATUS=in-progress/CCB_STEP_STATUS=blocked/' "$step_dir/step.conf" >"$WORK/step.blocked"; cp "$WORK/step.blocked" "$step_dir/step.conf"
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'blocked cancel'; pass
grep -Fqx 'CCB_STEP_STATUS=blocked' "$step_dir/step.conf" || fail 'blocked step changed'; pass

new_in_progress completed-history
printf '# Step Result\n\nStatus: pending\n\nCompleted history.\n' >"$step_dir/result.md"
"$CLI" workflow complete-step "$run_id" "$project" >/dev/null || fail 'completed history setup'
completed_step="$run_dir/01-manager"; step_dir="$run_dir/02-developer"
before_completed_step=$(cksum "$completed_step/step.conf"); before_completed_result=$(cksum "$completed_step/result.md")
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'run with completed history cancel'; pass
[ "$before_completed_step" = "$(cksum "$completed_step/step.conf")" ] && [ "$before_completed_result" = "$(cksum "$completed_step/result.md")" ] || fail 'completed history changed'; pass
grep -Fqx 'CCB_STEP_STATUS=skipped' "$step_dir/step.conf" && grep -Fqx 'CCB_STEP_STATUS=pending' "$run_dir/03-reviewer/step.conf" || fail 'later transitions invalid'; pass

new_in_progress skipped-history
printf '# Step Result\n\nStatus: pending\n\nSkipped history setup.\n' >"$step_dir/result.md"
"$CLI" workflow complete-step "$run_id" "$project" >/dev/null || fail 'skipped history setup'
sed 's/CCB_STEP_STATUS=completed/CCB_STEP_STATUS=skipped/' "$run_dir/01-manager/step.conf" >"$WORK/step.skipped"; cp "$WORK/step.skipped" "$run_dir/01-manager/step.conf"
before_skipped_step=$(cksum "$run_dir/01-manager/step.conf")
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'run with skipped history cancel'; pass
[ "$before_skipped_step" = "$(cksum "$run_dir/01-manager/step.conf")" ] || fail 'skipped history changed'; pass

new_pending completed
sed 's/CCB_RUN_STATUS=pending/CCB_RUN_STATUS=completed/; s/^CCB_RUN_COMPLETED_AT=.*/CCB_RUN_COMPLETED_AT=2026-07-28T11:00:00+0200/' "$run_dir/run.conf" >"$WORK/run.completed"; cp "$WORK/run.completed" "$run_dir/run.conf"
before=$(cksum "$run_dir/run.conf")
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'completed cancel succeeded'; contains "$output" 'completed workflow run cannot be cancelled' 'completed diagnostic'
[ "$before" = "$(cksum "$run_dir/run.conf")" ] || fail 'completed run mutated'; pass

new_pending locks
mkdir "$run_dir/.ccb-execution-lock"
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'execution lock ignored'; contains "$output" 'workflow step execution is currently locked' 'execution lock diagnostic'
rmdir "$run_dir/.ccb-execution-lock"; mkdir "$run_dir/.ccb-orchestration-lock"
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'orchestration lock ignored'; contains "$output" 'workflow run is controlled by an active automation' 'orchestration lock diagnostic'
rmdir "$run_dir/.ccb-orchestration-lock"

mkdir "$run_dir/.ccb-transaction.residual"
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'C3 transaction ignored'; pass
rmdir "$run_dir/.ccb-transaction.residual"; mkdir "$step_dir/.ccb-retry-transaction.residual"
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'retry transaction ignored'; pass
rmdir "$step_dir/.ccb-retry-transaction.residual"

new_pending corrupt
printf 'CCB_RUN_STATUS=pending\n' >>"$run_dir/run.conf"
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'corrupt run cancelled'; pass

new_in_progress corrupt-execution
printf 'CCB_EXECUTION_VERSION=1\n' >"$step_dir/execution.conf"
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'corrupt execution history cancelled'; pass

new_pending orchestration
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-28T11:00:00+0200 CCB_TEST_ORCHESTRATION_FAIL_POINT=after-resume "$CLI" workflow run "$run_id" "$project"
[ "$status" -eq 1 ] || fail 'orchestration history preparation'; orchestration_file="$run_dir/orchestration.conf"
before_started=$(sed -n 's/^CCB_ORCHESTRATION_STARTED_AT=//p' "$orchestration_file"); before_actions=$(sed -n 's/^CCB_ORCHESTRATION_ACTIONS=//p' "$orchestration_file")
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-28T12:00:00+0200 "$CLI" workflow cancel "$run_id" "$project"
[ "$status" -eq 0 ] || fail "historical orchestration cancel: $output"; pass
grep -Fqx 'CCB_ORCHESTRATION_STATUS=interrupted' "$orchestration_file" && grep -Fqx 'CCB_ORCHESTRATION_ERROR=cancelled-by-user' "$orchestration_file" || fail 'orchestration cancellation state'; pass
[ "$before_started" = "$(sed -n 's/^CCB_ORCHESTRATION_STARTED_AT=//p' "$orchestration_file")" ] && [ "$before_actions" = "$(sed -n 's/^CCB_ORCHESTRATION_ACTIONS=//p' "$orchestration_file")" ] || fail 'orchestration history lost'; pass
grep -Fqx 'CCB_ORCHESTRATION_COMPLETED_AT=2026-07-28T12:00:00+0200' "$orchestration_file" || fail 'orchestration completion missing'; pass

new_pending running-orchestration
run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-28T11:00:00+0200 CCB_TEST_ORCHESTRATION_FAIL_POINT=after-resume "$CLI" workflow run "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'running metadata preparation'
sed 's/CCB_ORCHESTRATION_STATUS=interrupted/CCB_ORCHESTRATION_STATUS=running/; s/^CCB_ORCHESTRATION_COMPLETED_AT=.*/CCB_ORCHESTRATION_COMPLETED_AT=/' "$run_dir/orchestration.conf" >"$WORK/orchestration.running"; cp "$WORK/orchestration.running" "$run_dir/orchestration.conf"
run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'running orchestration cancelled'; contains "$output" 'controlled by an active automation' 'running orchestration diagnostic'

for point in before-publish after-current-step after-orchestration before-run after-run; do
  new_pending "rollback-$point"
  run env CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-28T11:00:00+0200 CCB_TEST_ORCHESTRATION_FAIL_POINT=after-resume "$CLI" workflow run "$run_id" "$project"
  [ "$status" -eq 1 ] || fail "$point orchestration setup"
  orchestration_file="$run_dir/orchestration.conf"; before=$(snapshot_cancelled_files)
  run env CCB_TEST_MODE=1 CCB_TEST_CANCEL_FAIL_POINT="$point" "$CLI" workflow cancel "$run_id" "$project"
  [ "$status" -eq 1 ] || fail "$point returned success"
  [ "$before" = "$(snapshot_cancelled_files)" ] || fail "$point did not roll back byte-for-byte"
  pass
  assert_no_residue
  run "$CLI" workflow cancel "$run_id" "$project"; [ "$status" -eq 0 ] || fail "$point rollback not retryable"; pass
  assert_no_residue
done

new_pending old-d2
run "$CLI" workflow status "$run_id" "$project"; [ "$status" -eq 0 ] || fail 'D2 run invalid'; pass
[ "$(cat "$ROOT/VERSION")" = 1.8.0 ] || fail 'version changed'; pass
managed=$(find "$project/.ccb" -type f ! -path '*/runs/*' | wc -l | tr -d ' '); managed=$((managed + 1)); [ "$managed" -eq 7 ] || fail 'init file count'; pass

printf 'project cancel tests passed: %s/%s\n' "$tests" "$tests"
