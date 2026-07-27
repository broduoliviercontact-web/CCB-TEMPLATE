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
run_id=$(basename "$run_dir")
run "$CLI" workflow resume "$run_id" "$project"; [ "$status" -eq 0 ] || fail resume
run "$CLI" workflow complete-step "$run_id" "$project"
[ "$status" -eq 1 ] || fail 'initial result template accepted by complete-step'
grep -Fqx 'Status: pending' "$run_dir/01-manager/result.md" || fail 'rejected template was modified'

witness="$WORK/command-substitution-witness"
printf '# Step Result\n\nStatus: pending\n\nCompleted literally: $(touch "%s")\n' "$witness" >"$run_dir/01-manager/result.md"
run "$CLI" workflow complete-step --latest "$project"; [ "$status" -eq 0 ] || fail "complete-step: $output"
grep -Fqx 'Status: completed' "$run_dir/01-manager/result.md" || fail 'result status was not completed'
grep -Fq 'Status: completed' "$run_dir/02-developer/input.md" || fail 'next input did not receive completed result'
grep -Fq 'Completed literally: $(touch "' "$run_dir/02-developer/input.md" || fail 'literal command substitution was not transferred'
grep -Fq "$witness" "$run_dir/02-developer/input.md" || fail 'literal witness path was not transferred'
[ ! -e "$witness" ] || fail 'transferred Markdown executed command substitution'
[ -z "$(find "$run_dir/01-manager" -name '.result.md.completed.*' -print -quit)" ] || fail 'prepared result temporary remains'

create_transaction_run() {
  run "$CLI" workflow start feature "$project"
  [ "$status" -eq 0 ] || fail "transaction run start: $output"
  transaction_run_id=$(printf '%s\n' "$output" | sed -n 's/^Run ID: //p' | head -1)
  transaction_run_dir="$project/.ccb/runs/$transaction_run_id"
  run "$CLI" workflow resume "$transaction_run_id" "$project"
  [ "$status" -eq 0 ] || fail "transaction run resume: $output"
  printf '# Step Result\n\nStatus: pending\n\nTransaction result for %s.\n' "$transaction_run_id" >"$transaction_run_dir/01-manager/result.md"
}

snapshot_intermediate() {
  cksum "$transaction_run_dir/run.conf" \
    "$transaction_run_dir/01-manager/step.conf" \
    "$transaction_run_dir/01-manager/result.md" \
    "$transaction_run_dir/02-developer/input.md" \
    "$transaction_run_dir/02-developer/step.conf"
}

assert_no_transaction_residue() {
  residue=$(find "$transaction_run_dir" \( -name '.ccb-transaction.*' -o -name '.ccb-publish.*' -o -name '*.old' -o -name '*.new' \) -print -quit)
  [ -z "$residue" ] || fail "transaction residue remains: $residue"
}

for fail_point in before-publish after-current-step after-result after-next-input after-next-step before-run after-run; do
  create_transaction_run
  before=$(snapshot_intermediate)
  run env CCB_TEST_FAIL_POINT="$fail_point" "$CLI" workflow complete-step "$transaction_run_id" "$project"
  [ "$status" -ne 0 ] || fail "$fail_point did not fail"
  after=$(snapshot_intermediate)
  [ "$before" = "$after" ] || fail "$fail_point did not roll back byte-for-byte"
  grep -Fqx 'CCB_RUN_STATUS=in-progress' "$transaction_run_dir/run.conf" || fail "$fail_point changed run status"
  assert_no_transaction_residue
  run "$CLI" workflow inspect "$transaction_run_id" "$project"; [ "$status" -eq 0 ] || fail "$fail_point left run uninspectable"
  run "$CLI" workflow complete-step "$transaction_run_id" "$project"; [ "$status" -eq 0 ] || fail "$fail_point retry: $output"
  assert_no_transaction_residue
done

create_final_transaction_run() {
  create_transaction_run
  run "$CLI" workflow complete-step "$transaction_run_id" "$project"; [ "$status" -eq 0 ] || fail 'prepare final run step 1'
  run "$CLI" workflow resume "$transaction_run_id" "$project"; [ "$status" -eq 0 ] || fail 'resume final run step 2'
  printf '# Step Result\n\nStatus: pending\n\nSecond transaction result.\n' >"$transaction_run_dir/02-developer/result.md"
  run "$CLI" workflow complete-step "$transaction_run_id" "$project"; [ "$status" -eq 0 ] || fail 'prepare final run step 2'
  run "$CLI" workflow resume "$transaction_run_id" "$project"; [ "$status" -eq 0 ] || fail 'resume final run step 3'
  printf '# Step Result\n\nStatus: pending\n\nFinal transaction result.\n' >"$transaction_run_dir/03-reviewer/result.md"
}

snapshot_final() {
  cksum "$transaction_run_dir/run.conf" \
    "$transaction_run_dir/03-reviewer/step.conf" \
    "$transaction_run_dir/03-reviewer/result.md"
}

for fail_point in after-current-step after-result before-run after-run; do
  create_final_transaction_run
  before=$(snapshot_final)
  run env CCB_TEST_FAIL_POINT="$fail_point" "$CLI" workflow complete-step "$transaction_run_id" "$project"
  [ "$status" -ne 0 ] || fail "final $fail_point did not fail"
  after=$(snapshot_final)
  [ "$before" = "$after" ] || fail "final $fail_point did not roll back byte-for-byte"
  assert_no_transaction_residue
  run "$CLI" workflow complete-step "$transaction_run_id" "$project"; [ "$status" -eq 0 ] || fail "final $fail_point retry: $output"
  grep -Fqx 'CCB_RUN_STATUS=completed' "$transaction_run_dir/run.conf" || fail "final $fail_point retry did not complete run"
  grep '^CCB_RUN_COMPLETED_AT=.' "$transaction_run_dir/run.conf" >/dev/null || fail "final $fail_point omitted completed_at"
  assert_no_transaction_residue
done

create_transaction_run
before=$(snapshot_intermediate)
run env CCB_TEST_FINAL_VALIDATION=corrupt-run-status "$CLI" workflow complete-step "$transaction_run_id" "$project"
[ "$status" -ne 0 ] || fail 'final validation corruption was accepted'
after=$(snapshot_intermediate)
[ "$before" = "$after" ] || fail 'final validation failure did not roll back byte-for-byte'
assert_no_transaction_residue
run "$CLI" workflow complete-step "$transaction_run_id" "$project"; [ "$status" -eq 0 ] || fail "final validation retry: $output"
assert_no_transaction_residue
printf 'project runs tests passed\n'
