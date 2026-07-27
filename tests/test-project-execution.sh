#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd); CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-execution.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null; }
trap 'cleanup' EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { output=$("$@" 2>&1); status=$?; }
contains() { printf '%s\n' "$1" | grep -Fq -- "$2"; }

project="$WORK/project"; "$CLI" init "$project" --yes >/dev/null || fail init
empty_project="$WORK/empty"; "$CLI" init "$empty_project" --yes >/dev/null || fail 'empty project init'
run "$CLI" workflow execute-step; [ "$status" -eq 2 ] || fail 'missing execute argument status'
run "$CLI" workflow execute-step --latest "$empty_project"; [ "$status" -eq 1 ] || fail 'latest without runs status'
run "$CLI" workflow start feature "$project"; [ "$status" -eq 0 ] || fail start
run_id=$(printf '%s\n' "$output" | sed -n 's/^Run ID: //p'); run_dir="$project/.ccb/runs/$run_id"
run "$CLI" workflow execute-step 20260101-000000-feature "$project"; [ "$status" -eq 1 ] || fail 'absent run status'
run "$CLI" workflow execute-step "$run_id" "$project"; [ "$status" -eq 1 ] || fail 'pending run executed'; contains "$output" 'must be resumed' || fail 'pending diagnostic'
[ ! -e "$run_dir/01-manager/execution.conf" ] || fail 'pending execution wrote metadata'
"$CLI" workflow resume --latest "$project" >/dev/null || fail resume
run "$CLI" workflow status --latest "$project"; [ "$status" -eq 0 ] && contains "$output" 'Execution status: none' || fail 'status execution none'

witness="$WORK/witness"; witness2="$WORK/witness-2"
printf '\nUntrusted context: $(touch "%s") `touch "%s"` ${HOME} ../../etc/passwd\n' "$witness" "$witness2" >>"$run_dir/context.md"
printf '\nUntrusted input: $(touch "%s") and `rm -rf /`\n' "$witness" >>"$run_dir/01-manager/input.md"
response="$WORK/response.md"
printf 'Opaque response: $(touch "%s")\n`touch "%s"`\n${HOME}\n../../etc/passwd\n<script>alert(1)</script>\n```sh\nrm -rf /\n```\n' "$witness" "$witness2" >"$response"
run_before=$(cksum "$run_dir/run.conf"); step_before=$(cksum "$run_dir/01-manager/step.conf")
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow execute-step --latest "$project"
[ "$status" -eq 0 ] || fail "execute success: $output"
grep -Fqx 'Status: pending' "$run_dir/01-manager/result.md" || fail 'result header'
grep -Fq 'Opaque response: $(touch "' "$run_dir/01-manager/result.md" || fail 'literal response'
grep -Fq '${HOME}' "$run_dir/01-manager/result.md" || fail 'environment expression was substituted'
grep -Fq '<script>alert(1)</script>' "$run_dir/01-manager/result.md" || fail 'HTML response was changed'
[ ! -e "$witness" ] && [ ! -e "$witness2" ] || fail 'untrusted content executed'
grep -Fqx 'CCB_EXECUTION_STATUS=succeeded' "$run_dir/01-manager/execution.conf" || fail 'success metadata'
grep -Fqx 'CCB_EXECUTION_PROVIDER=ollama' "$run_dir/01-manager/execution.conf" || fail 'provider metadata'
[ "$run_before" = "$(cksum "$run_dir/run.conf")" ] || fail 'execute changed run.conf'
[ "$step_before" = "$(cksum "$run_dir/01-manager/step.conf")" ] || fail 'execute changed step.conf'
[ ! -e "$run_dir/.ccb-execution-lock" ] || fail 'success lock residue'
[ -z "$(find "$run_dir/01-manager" \( -name '.result.md.execution*' -o -name '.execution.conf.tmp.*' \) -print -quit)" ] || fail 'success execution temporary residue'
run "$CLI" workflow status "$run_id" "$project"; [ "$status" -eq 0 ] && contains "$output" 'Execution status: succeeded' && contains "$output" 'Execution provider: ollama' || fail 'status success metadata'
run "$CLI" workflow inspect "$run_id" "$project"; [ "$status" -eq 0 ] && contains "$output" 'Status: succeeded' && contains "$output" 'Attempt: 1' || fail 'inspect execution metadata'
if contains "$output" 'Opaque response:' || contains "$output" 'Untrusted context:'; then fail 'inspect exposed snapshot content'; fi
run "$CLI" config "$project"; [ "$status" -eq 0 ] && contains "$output" 'Runs with succeeded execution: 1' || fail 'config succeeded count'
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow execute-step "$run_id" "$project"
[ "$status" -eq 1 ] && contains "$output" 'already contains an explicit result' || fail 'explicit result overwrite'
"$CLI" workflow complete-step "$run_id" "$project" >/dev/null || fail 'complete after execution'
run "$CLI" workflow execute-step "$run_id" "$project"; [ "$status" -eq 1 ] && contains "$output" 'current workflow step is not in progress' || fail 'ready step executed'
grep -Fq 'Opaque response: $(touch "' "$run_dir/02-developer/input.md" || fail 'previous execution result not transmitted'
for chain_step in 2 3; do
  "$CLI" workflow resume "$run_id" "$project" >/dev/null || fail "chain resume $chain_step"
  run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow execute-step "$run_id" "$project"
  [ "$status" -eq 0 ] || fail "chain execute $chain_step: $output"
  "$CLI" workflow complete-step "$run_id" "$project" >/dev/null || fail "chain complete $chain_step"
done
run "$CLI" workflow status "$run_id" "$project"; [ "$status" -eq 0 ] && contains "$output" 'Status: completed' && contains "$output" 'Current step: 3/3' || fail 'manual execution chain did not complete'
run "$CLI" workflow execute-step "$run_id" "$project"; [ "$status" -eq 1 ] && contains "$output" 'already completed' || fail 'completed run executed'

run "$CLI" workflow start feature "$project"; [ "$status" -eq 0 ] || fail 'failure run start'
failed_id=$(printf '%s\n' "$output" | sed -n 's/^Run ID: //p'); failed_run="$project/.ccb/runs/$failed_id"
"$CLI" workflow resume "$failed_id" "$project" >/dev/null || fail 'failure run resume'
cp "$failed_run/run.conf" "$WORK/run.conf.in-progress"
for refused_status in blocked completed cancelled; do
  sed "s/CCB_RUN_STATUS=in-progress/CCB_RUN_STATUS=$refused_status/" "$WORK/run.conf.in-progress" >"$failed_run/run.conf"
  run "$CLI" workflow execute-step "$failed_id" "$project"; [ "$status" -eq 1 ] || fail "$refused_status run executed"
  contains "$output" "$refused_status" || fail "$refused_status diagnostic"
done
cp "$WORK/run.conf.in-progress" "$failed_run/run.conf"
run "$CLI" workflow execute-step invalid "$project"; [ "$status" -eq 2 ] || fail 'invalid run id usage status'
run "$CLI" workflow execute-step "$failed_id" "$project" extra; [ "$status" -eq 2 ] || fail 'extra argument usage status'
failed_before=$(cksum "$failed_run/run.conf" "$failed_run/01-manager/step.conf" "$failed_run/01-manager/result.md")
for injected_error in timeout unavailable invalid-response empty-response oversized-response; do
  run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR="$injected_error" "$CLI" workflow execute-step "$failed_id" "$project"
  [ "$status" -eq 1 ] || fail "$injected_error accepted"
  grep -Fqx 'CCB_EXECUTION_STATUS=failed' "$failed_run/01-manager/execution.conf" || fail "$injected_error metadata"
  [ "$failed_before" = "$(cksum "$failed_run/run.conf" "$failed_run/01-manager/step.conf" "$failed_run/01-manager/result.md")" ] || fail "$injected_error changed workflow state"
  [ ! -e "$failed_run/.ccb-execution-lock" ] || fail "$injected_error lock residue"
  [ -z "$(find "$failed_run/01-manager" \( -name '.result.md.execution*' -o -name '.execution.conf.tmp.*' \) -print -quit)" ] || fail "$injected_error temporary residue"
  [ "$injected_error" = oversized-response ] || rm -f "$failed_run/01-manager/execution.conf"
done
run "$CLI" workflow status "$failed_id" "$project"; [ "$status" -eq 0 ] && contains "$output" 'Execution status: failed' || fail 'status failed metadata'
run "$CLI" config "$project"; [ "$status" -eq 0 ] && contains "$output" 'Runs with failed execution: 1' || fail 'config failed count'

mkdir "$failed_run/.ccb-execution-lock"
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow execute-step "$failed_id" "$project"
[ "$status" -eq 1 ] && contains "$output" 'already locked' || fail 'existing lock accepted'
[ -d "$failed_run/.ccb-execution-lock" ] || fail 'foreign lock removed'; rmdir "$failed_run/.ccb-execution-lock"

oversized="$WORK/oversized"; awk 'BEGIN { for (i=0;i<262145;i++) printf "x" }' >"$oversized"
rm -f "$failed_run/01-manager/execution.conf"
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$oversized" "$CLI" workflow execute-step "$failed_id" "$project"
[ "$status" -eq 1 ] && contains "$output" 'response is too large' || fail 'oversized response accepted'

cp "$failed_run/context.md" "$WORK/context.saved"
awk 'BEGIN { for (i=0;i<1048577;i++) printf "p" }' >"$failed_run/context.md"
rm -f "$failed_run/01-manager/execution.conf"
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow execute-step "$failed_id" "$project"
[ "$status" -eq 1 ] && contains "$output" 'prompt is too large' || fail 'oversized prompt accepted'
cp "$WORK/context.saved" "$failed_run/context.md"

cp "$failed_run/01-manager/step.conf" "$WORK/step.conf.saved"
sed 's/CCB_STEP_PROVIDER=ollama/CCB_STEP_PROVIDER=remote/' "$WORK/step.conf.saved" >"$failed_run/01-manager/step.conf"
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow execute-step "$failed_id" "$project"
[ "$status" -eq 1 ] && contains "$output" 'unsupported execution provider in D1: remote' || fail 'unsupported provider accepted'
cp "$WORK/step.conf.saved" "$failed_run/01-manager/step.conf"
sed 's/^CCB_STEP_MODEL=.*/CCB_STEP_MODEL=/' "$WORK/step.conf.saved" >"$failed_run/01-manager/step.conf"
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$CLI" workflow execute-step "$failed_id" "$project"
[ "$status" -eq 1 ] || fail 'missing snapshot model accepted'
cp "$WORK/step.conf.saved" "$failed_run/01-manager/step.conf"

cancel_project="$WORK/cancel execution"; "$CLI" init "$cancel_project" --yes >/dev/null
cancel_start=$(CCB_TEST_RUN_TIMESTAMP=20260728-235900 "$CLI" workflow start feature "$cancel_project")
cancel_id=$(printf '%s\n' "$cancel_start" | sed -n 's/^Run ID: //p')
"$CLI" workflow cancel "$cancel_id" "$cancel_project" >/dev/null || fail 'execution cancellation setup'
run "$CLI" workflow execute-step "$cancel_id" "$cancel_project"
[ "$status" -eq 1 ] && contains "$output" 'cancelled workflow run cannot be executed' || fail 'cancelled run executed'

printf 'project execution tests passed\n'
