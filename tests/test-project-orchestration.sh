#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-orchestration.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }
trap 'cleanup' EXIT HUP INT TERM
tests=0
ok() { tests=$((tests + 1)); }
fail() { echo "FAIL: $1" >&2; exit 1; }
contains() { printf '%s\n' "$1" | grep -Fq -- "$2" || fail "$3"; ok; }

project="$WORK/automation project"
"$CLI" init "$project" --project-name 'Automation Project' --profile web --yes >/dev/null || fail init
start=$(CCB_TEST_MODE=1 CCB_TEST_NOW=2026-07-27T12:00:00+0200 CCB_TEST_RUN_TIMESTAMP=20260727-120000 "$CLI" workflow start feature "$project") || fail start
run_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p')
run_dir="$project/.ccb/runs/$run_id"
response="$WORK/provider-response.txt"; witness="$WORK/witness"; witness2="$WORK/witness-2"
{
  printf '%s\n' 'Automated agent result.'
  printf '$(touch "%s")\n' "$witness"
  printf '`touch "%s"`\n' "$witness2"
  printf '%s\n' '${HOME}' '../../etc/passwd' '```sh' 'rm -rf /<script>alert(1)</script>'
} >"$response"
output=$(CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" CCB_TEST_NOW=2026-07-27T12:01:00+0200 "$CLI" workflow run "$run_id" "$project") || fail 'complete sequential run'
contains "$output" '[OK] workflow automation completed' 'completion output'
grep -Fqx 'CCB_RUN_STATUS=completed' "$run_dir/run.conf" || fail 'run completed'; ok
grep -Fqx 'CCB_ORCHESTRATION_STATUS=succeeded' "$run_dir/orchestration.conf" || fail 'orchestration succeeded'; ok
grep -Fqx 'CCB_ORCHESTRATION_ACTIONS=9' "$run_dir/orchestration.conf" || fail 'action count'; ok
[ ! -e "$run_dir/.ccb-orchestration-lock" ] || fail 'success lock residue'; ok
for step in "$run_dir"/[0-9][0-9]-*; do grep -Fqx 'CCB_STEP_STATUS=completed' "$step/step.conf" || fail 'step not completed'; grep -Fqx 'CCB_EXECUTION_STATUS=succeeded' "$step/execution.conf" || fail 'execution not succeeded'; done; ok
grep -Fq '${HOME}' "$run_dir/01-manager/result.md" || fail 'literal variable lost'; ok
grep -Fq '<script>alert(1)</script>' "$run_dir/03-reviewer/result.md" || fail 'literal html lost'; ok
[ ! -e "$witness" ] && [ ! -e "$witness2" ] || fail 'untrusted data executed'; ok
output=$("$CLI" workflow run "$run_id" "$project") || fail idempotence
contains "$output" '[OK] workflow run already completed' idempotence
status=$("$CLI" workflow status "$run_id" "$project") || fail status
contains "$status" 'Automation status: succeeded' 'status automation'
inspect=$("$CLI" workflow inspect --latest "$project") || fail inspect
contains "$inspect" 'Automation' 'inspect section'
contains "$inspect" 'Lock: absent' 'inspect lock'
if printf '%s' "$inspect" | grep -Fq 'Automated agent result.'; then fail 'inspect leaked result'; fi; ok
config=$("$CLI" config "$project") || fail config
contains "$config" 'Runs automated successfully: 1' 'config automation count'
"$CLI" doctor "$project" --no-ollama --strict >/dev/null || fail 'doctor strict'; ok

resume_project="$WORK/resume"
"$CLI" init "$resume_project" --yes >/dev/null || fail 'resume init'
start=$(CCB_TEST_RUN_TIMESTAMP=20260727-130000 "$CLI" workflow start feature "$resume_project") || fail 'resume start'
resume_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p')
if CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" CCB_TEST_ORCHESTRATION_FAIL_POINT=after-execute "$CLI" workflow run --latest "$resume_project" >/dev/null 2>&1; then fail 'fail point accepted as success'; fi; ok
resume_run="$resume_project/.ccb/runs/$resume_id"
grep -Fqx 'CCB_ORCHESTRATION_STATUS=interrupted' "$resume_run/orchestration.conf" || fail 'interrupted checkpoint'; ok
[ ! -e "$resume_run/.ccb-orchestration-lock" ] || fail 'interrupted lock residue'; ok
config=$("$CLI" config "$resume_project") || fail 'interrupted config'
contains "$config" 'Runs with interrupted automation: 1' 'interrupted automation count'
before_attempt=$(sed -n 's/^CCB_EXECUTION_ATTEMPT=//p' "$resume_run/01-manager/execution.conf")
CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow run --latest "$resume_project" >/dev/null || fail 'resume after execute'
after_attempt=$(sed -n 's/^CCB_EXECUTION_ATTEMPT=//p' "$resume_run/01-manager/execution.conf")
[ "$before_attempt" = "$after_attempt" ] || fail 'step executed twice'; ok

sequence=0
for point in after-resume after-complete before-next-step before-success; do
  sequence=$((sequence + 1)); interrupted_project="$WORK/interrupted-$sequence"
  "$CLI" init "$interrupted_project" --yes >/dev/null || fail "init $point"
  start=$(CCB_TEST_RUN_TIMESTAMP="20260727-15$(printf '%02d' "$sequence")00" "$CLI" workflow start feature "$interrupted_project") || fail "start $point"
  interrupted_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p'); interrupted_run="$interrupted_project/.ccb/runs/$interrupted_id"
  if CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" CCB_TEST_ORCHESTRATION_FAIL_POINT="$point" "$CLI" workflow run --latest "$interrupted_project" >/dev/null 2>&1; then fail "fail point $point returned success"; fi
  grep -Fqx 'CCB_ORCHESTRATION_STATUS=interrupted' "$interrupted_run/orchestration.conf" || fail "checkpoint $point"
  [ ! -e "$interrupted_run/.ccb-orchestration-lock" ] || fail "lock residue $point"
  CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow run --latest "$interrupted_project" >/dev/null || fail "resume $point"
  grep -Fqx 'CCB_RUN_STATUS=completed' "$interrupted_run/run.conf" || fail "completion $point"
  grep -Fqx 'CCB_ORCHESTRATION_STATUS=succeeded' "$interrupted_run/orchestration.conf" || fail "final orchestration $point"
  ok
done

failed_project="$WORK/provider-failure"
"$CLI" init "$failed_project" --yes >/dev/null; start=$(CCB_TEST_RUN_TIMESTAMP=20260727-160000 "$CLI" workflow start feature "$failed_project"); failed_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p'); failed_run="$failed_project/.ccb/runs/$failed_id"
if CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=unavailable "$CLI" workflow run --latest "$failed_project" >/dev/null 2>&1; then fail 'provider failure returned success'; fi
grep -Fqx 'CCB_ORCHESTRATION_STATUS=failed' "$failed_run/orchestration.conf" || fail 'failed orchestration checkpoint'; ok
config=$("$CLI" config "$failed_project") || fail 'failed config'
contains "$config" 'Runs with failed automation: 1' 'failed automation count'
[ ! -e "$failed_run/.ccb-orchestration-lock" ] && [ ! -e "$failed_run/.ccb-execution-lock" ] || fail 'failure lock residue'; ok
if CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow run --latest "$failed_project" >/dev/null 2>&1; then fail 'failed execution was retried'; fi; ok
attempt=$(sed -n 's/^CCB_EXECUTION_ATTEMPT=//p' "$failed_run/01-manager/execution.conf"); [ "$attempt" = 1 ] || fail 'failed execution attempt changed'; ok
"$CLI" workflow retry-step "$failed_id" "$failed_project" >/dev/null || fail 'manual retry preparation for automation'
grep -Fqx 'CCB_EXECUTION_ATTEMPT=2' "$failed_run/01-manager/execution.conf" || fail 'automation retry attempt not prepared'; ok
CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow run "$failed_id" "$failed_project" >/dev/null || fail 'automation did not resume after manual retry'; ok
grep -Fqx 'CCB_RUN_STATUS=completed' "$failed_run/run.conf" || fail 'retried automation did not complete'; ok

corrupt="$WORK/corrupt-orchestration.conf"
cp "$run_dir/orchestration.conf" "$corrupt"; printf 'CCB_ORCHESTRATION_STATUS=succeeded\n' >>"$corrupt"
if ( . "$ROOT/scripts/project-orchestration-lib.sh"; project_orchestration_parse_conf "$corrupt" ); then fail 'duplicate key accepted'; fi; ok

locked="$WORK/locked"
"$CLI" init "$locked" --yes >/dev/null; start=$(CCB_TEST_RUN_TIMESTAMP=20260727-140000 "$CLI" workflow start feature "$locked"); locked_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p'); locked_run="$locked/.ccb/runs/$locked_id"
mkdir "$locked_run/.ccb-orchestration-lock"
for action in resume execute-step complete-step; do if "$CLI" workflow "$action" "$locked_id" "$locked" >/dev/null 2>&1; then fail "manual $action ignored lock"; fi; done; ok
if "$CLI" workflow run "$locked_id" "$locked" >/dev/null 2>&1; then fail 'second automation ignored lock'; fi; ok
rmdir "$locked_run/.ccb-orchestration-lock"

if "$CLI" workflow run >/dev/null 2>&1; then fail 'missing run accepted'; else [ "$?" -eq 2 ] || fail 'missing run code'; fi; ok
if "$CLI" workflow run bad/id "$project" >/dev/null 2>&1; then fail 'unsafe id accepted'; else [ "$?" -eq 2 ] || fail 'unsafe id code'; fi; ok
if "$CLI" workflow run "$run_id" "$project" extra >/dev/null 2>&1; then fail 'extra argument accepted'; else [ "$?" -eq 2 ] || fail 'extra argument code'; fi; ok

cancel_project="$WORK/cancelled automation"; "$CLI" init "$cancel_project" --yes >/dev/null
cancel_start=$(CCB_TEST_RUN_TIMESTAMP=20260728-235800 "$CLI" workflow start feature "$cancel_project"); cancel_id=$(printf '%s\n' "$cancel_start" | sed -n 's/^Run ID: //p')
"$CLI" workflow cancel "$cancel_id" "$cancel_project" >/dev/null || fail 'automation cancellation setup'
if "$CLI" workflow run "$cancel_id" "$cancel_project" >/dev/null 2>&1; then fail 'cancelled run automated'; fi; ok

printf 'project orchestration tests passed: %s/%s\n' "$tests" "$tests"
