#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-doctor-test.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }
trap 'cleanup' EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { output=$("$@" 2>&1); status=$?; }
contains() { printf '%s' "$1" | grep -F -- "$2" >/dev/null; }

run "$CLI" doctor --help; [ "$status" -eq 0 ] || fail 'help status'; for option in TARGET --strict --no-ollama --format; do contains "$output" "$option" || fail "help missing $option"; done
run "$CLI" doctor --unknown; [ "$status" -eq 2 ] || fail 'unknown option status'
run "$CLI" doctor --format json; [ "$status" -eq 2 ] || fail 'unknown format status'
run "$CLI" doctor --no-ollama; [ "$status" -eq 0 ] || fail "template doctor failed: $output"; contains "$output" 'CCB Doctor' || fail 'template heading'; contains "$output" 'Summary:' || fail 'template summary'

project="$WORK/audio project"; "$CLI" init "$project" --profile audio --yes >/dev/null
before=$(cksum "$project/.ccb/models.conf")
run "$CLI" doctor "$project" --no-ollama; [ "$status" -eq 0 ] || fail "valid project doctor failed: $output"; contains "$output" 'project.profile — audio' || fail 'profile result'; contains "$output" 'ollama — disabled' || fail 'ollama skip'; after=$(cksum "$project/.ccb/models.conf"); [ "$before" = "$after" ] || fail 'doctor modified project'
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 0 ] || fail 'strict valid project failed'
mkdir "$project/.ccb/runs"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 0 ] || fail 'strict empty runs directory failed'
rmdir "$project/.ccb/runs"

run "$CLI" workflow start feature "$project"; [ "$status" -eq 0 ] || fail 'doctor run start'
doctor_run_id=$(printf '%s\n' "$output" | sed -n 's/^Run ID: //p')
doctor_run="$project/.ccb/runs/$doctor_run_id"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 0 ] || fail "pending run rejected: $output"
run "$CLI" workflow resume --latest "$project"; [ "$status" -eq 0 ] || fail 'doctor run resume'
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 0 ] || fail "in-progress run rejected: $output"
mkdir "$doctor_run/.ccb-execution-lock"
run "$CLI" doctor "$project" --no-ollama; [ "$status" -eq 0 ] || fail 'normal execution lock warning failed'; contains "$output" 'project.runs.execution_locks — residual' || fail 'execution lock warning missing'
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted execution lock residue'
[ -d "$doctor_run/.ccb-execution-lock" ] || fail 'doctor removed execution lock'; rmdir "$doctor_run/.ccb-execution-lock"
printf 'CCB_EXECUTION_VERSION=1\nCCB_EXECUTION_STATUS=running\nCCB_EXECUTION_PROVIDER=ollama\nCCB_EXECUTION_MODEL=qwen3:8b\nCCB_EXECUTION_ATTEMPT=1\nCCB_EXECUTION_STARTED_AT=2026-07-27T10:00:00+0200\nCCB_EXECUTION_COMPLETED_AT=\nCCB_EXECUTION_ERROR=\n' >"$doctor_run/01-manager/execution.conf"
mkdir "$doctor_run/.ccb-execution-lock"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 0 ] || fail "coherent running execution rejected: $output"
rm -f "$doctor_run/01-manager/execution.conf"; rmdir "$doctor_run/.ccb-execution-lock"
cp "$doctor_run/run.conf" "$WORK/in-progress-run.saved"; cp "$doctor_run/01-manager/step.conf" "$WORK/in-progress-step.saved"
sed 's/CCB_RUN_STATUS=in-progress/CCB_RUN_STATUS=blocked/' "$WORK/in-progress-run.saved" >"$doctor_run/run.conf"
sed 's/CCB_STEP_STATUS=in-progress/CCB_STEP_STATUS=blocked/' "$WORK/in-progress-step.saved" >"$doctor_run/01-manager/step.conf"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 0 ] || fail "blocked run rejected: $output"
cp "$WORK/in-progress-run.saved" "$doctor_run/run.conf"; cp "$WORK/in-progress-step.saved" "$doctor_run/01-manager/step.conf"
cp "$doctor_run/01-manager/step.conf" "$WORK/step.saved"
sed 's/^CCB_STEP_STARTED_AT=.*/CCB_STEP_STARTED_AT=/' "$WORK/step.saved" >"$doctor_run/01-manager/step.conf"
run "$CLI" doctor "$project" --no-ollama; [ "$status" -eq 0 ] || fail 'normal doctor rejected timestamp warning'; contains "$output" "project.run.$doctor_run_id — inconsistent" || fail 'missing timestamp warning'
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict doctor accepted missing started_at'
cp "$WORK/step.saved" "$doctor_run/01-manager/step.conf"
printf 'Literal doctor execution result.\n' >"$WORK/doctor-response"
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$WORK/doctor-response" "$CLI" workflow execute-step --latest "$project"; [ "$status" -eq 0 ] || fail "doctor execute step: $output"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 0 ] || fail "valid execution metadata rejected: $output"
cp "$doctor_run/01-manager/execution.conf" "$WORK/execution.saved"
printf 'CCB_EXECUTION_STATUS=succeeded\n' >>"$doctor_run/01-manager/execution.conf"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted duplicate execution key'
cp "$WORK/execution.saved" "$doctor_run/01-manager/execution.conf"
printf 'CCB_UNKNOWN=1\n' >>"$doctor_run/01-manager/execution.conf"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted unknown execution key'
cp "$WORK/execution.saved" "$doctor_run/01-manager/execution.conf"
rm -f "$doctor_run/01-manager/execution.conf"; ln -s "$WORK/execution.saved" "$doctor_run/01-manager/execution.conf"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted execution metadata symlink'
rm -f "$doctor_run/01-manager/execution.conf"; cp "$WORK/execution.saved" "$doctor_run/01-manager/execution.conf"
printf 'residual\n' >"$doctor_run/01-manager/.result.md.execution-residual"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted execution temporary residue'
[ -f "$doctor_run/01-manager/.result.md.execution-residual" ] || fail 'doctor removed execution temporary'; rm -f "$doctor_run/01-manager/.result.md.execution-residual"
run "$CLI" workflow complete-step --latest "$project"; [ "$status" -eq 0 ] || fail "doctor complete step 1: $output"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 0 ] || fail "between-step state rejected: $output"
run "$CLI" workflow resume --latest "$project"; [ "$status" -eq 0 ] || fail 'doctor resume step 2'
printf '# Step Result\n\nStatus: pending\n\nSecond doctor result.\n' >"$doctor_run/02-developer/result.md"
run "$CLI" workflow complete-step --latest "$project"; [ "$status" -eq 0 ] || fail 'doctor complete step 2'
run "$CLI" workflow resume --latest "$project"; [ "$status" -eq 0 ] || fail 'doctor resume step 3'
printf '# Step Result\n\nStatus: pending\n\nFinal doctor result.\n' >"$doctor_run/03-reviewer/result.md"
run "$CLI" workflow complete-step --latest "$project"; [ "$status" -eq 0 ] || fail 'doctor complete final step'
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 0 ] || fail "completed run rejected: $output"

printf 'CCB_ORCHESTRATION_VERSION=1\nCCB_ORCHESTRATION_STATUS=succeeded\nCCB_ORCHESTRATION_MODE=sequential\nCCB_ORCHESTRATION_STARTED_AT=2026-07-27T10:00:00+0200\nCCB_ORCHESTRATION_UPDATED_AT=2026-07-27T10:03:00+0200\nCCB_ORCHESTRATION_COMPLETED_AT=2026-07-27T10:03:00+0200\nCCB_ORCHESTRATION_CURRENT_STEP=3\nCCB_ORCHESTRATION_STEPS_COMPLETED=3\nCCB_ORCHESTRATION_STEP_COUNT=3\nCCB_ORCHESTRATION_ACTIONS=9\nCCB_ORCHESTRATION_ERROR=\n' >"$doctor_run/orchestration.conf"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 0 ] || fail "valid orchestration rejected: $output"
cp "$doctor_run/orchestration.conf" "$WORK/orchestration.saved"
printf 'CCB_ORCHESTRATION_STATUS=succeeded\n' >>"$doctor_run/orchestration.conf"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted duplicate orchestration key'
cp "$WORK/orchestration.saved" "$doctor_run/orchestration.conf"
rm -f "$doctor_run/orchestration.conf"; ln -s "$WORK/orchestration.saved" "$doctor_run/orchestration.conf"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted orchestration symlink'
rm -f "$doctor_run/orchestration.conf"; cp "$WORK/orchestration.saved" "$doctor_run/orchestration.conf"
mkdir "$doctor_run/.ccb-orchestration-lock"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted residual orchestration lock'
[ -d "$doctor_run/.ccb-orchestration-lock" ] || fail 'doctor removed orchestration lock'; rmdir "$doctor_run/.ccb-orchestration-lock"
printf 'residual\n' >"$doctor_run/.orchestration.conf.tmp.residual"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted orchestration temporary residue'
[ -f "$doctor_run/.orchestration.conf.tmp.residual" ] || fail 'doctor removed orchestration temporary'; rm -f "$doctor_run/.orchestration.conf.tmp.residual"

cp "$doctor_run/run.conf" "$WORK/run.saved"
sed 's/^CCB_RUN_COMPLETED_AT=.*/CCB_RUN_COMPLETED_AT=/' "$WORK/run.saved" >"$doctor_run/run.conf"
before=$(cksum "$doctor_run/run.conf")
run "$CLI" doctor "$project" --no-ollama; [ "$status" -eq 0 ] || fail 'normal completed_at warning failed'
after=$(cksum "$doctor_run/run.conf"); [ "$before" = "$after" ] || fail 'doctor modified corrupt run'
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted missing run completed_at'
cp "$WORK/run.saved" "$doctor_run/run.conf"
cp "$doctor_run/01-manager/result.md" "$WORK/result.saved"
sed 's/^Status: completed$/Status: pending/' "$WORK/result.saved" >"$doctor_run/01-manager/result.md"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted pending completed result'
cp "$WORK/result.saved" "$doctor_run/01-manager/result.md"
cp "$doctor_run/02-developer/input.md" "$WORK/input.saved"
sed 's|Source: ../01-manager/result.md|Source: ../03-reviewer/result.md|' "$WORK/input.saved" >"$doctor_run/02-developer/input.md"
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted incorrect transmission source'
cp "$WORK/input.saved" "$doctor_run/02-developer/input.md"
mkdir "$doctor_run/.ccb-transaction.residual"
printf 'residual\n' >"$doctor_run/.ccb-transaction.residual/run.conf.old"
run "$CLI" doctor "$project" --no-ollama; [ "$status" -eq 0 ] || fail 'normal residual warning failed'; contains "$output" 'project.runs.transactions — residual' || fail 'transaction residual warning missing'
[ -f "$doctor_run/.ccb-transaction.residual/run.conf.old" ] || fail 'doctor removed transaction residual'
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict accepted transaction residual'
rm -f "$doctor_run/.ccb-transaction.residual/run.conf.old"; rmdir "$doctor_run/.ccb-transaction.residual"

d3="$WORK/d3 project"; "$CLI" init "$d3" --yes >/dev/null
start=$(CCB_TEST_RUN_TIMESTAMP=20260730-120000 "$CLI" workflow start feature "$d3"); d3_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p'); d3_run="$d3/.ccb/runs/$d3_id"; d3_step="$d3_run/01-manager"
"$CLI" workflow resume "$d3_id" "$d3" >/dev/null || fail 'D3 retry resume'
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=unavailable "$CLI" workflow execute-step "$d3_id" "$d3"; [ "$status" -eq 1 ] || fail 'D3 first failure'
"$CLI" workflow retry-step "$d3_id" "$d3" >/dev/null || fail 'D3 first retry'
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 0 ] || fail "valid first retry rejected: $output"
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=timeout "$CLI" workflow execute-step "$d3_id" "$d3"; [ "$status" -eq 1 ] || fail 'D3 second failure'
"$CLI" workflow retry-step "$d3_id" "$d3" >/dev/null || fail 'D3 second retry'
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 0 ] || fail "valid second retry rejected: $output"
run env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_ERROR=invalid-response "$CLI" workflow execute-step "$d3_id" "$d3"; [ "$status" -eq 1 ] || fail 'D3 limit failure'
before=$(find "$d3/.ccb/runs" -type f -exec cksum {} \; | LC_ALL=C sort)
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 0 ] || fail "valid retry limit rejected: $output"
after=$(find "$d3/.ccb/runs" -type f -exec cksum {} \; | LC_ALL=C sort); [ "$before" = "$after" ] || fail 'Doctor changed valid D3 history'

cp "$d3_step/execution.conf" "$WORK/d3-execution.saved"; cp "$d3_step/step.conf" "$WORK/d3-step.saved"
cp "$d3_step/attempts/001.conf" "$WORK/d3-attempt-1.saved"; cp "$d3_step/attempts/002.conf" "$WORK/d3-attempt-2.saved"
rm -f "$d3_step/attempts/002.conf"; sed 's/CCB_ATTEMPT_NUMBER=2/CCB_ATTEMPT_NUMBER=3/' "$WORK/d3-attempt-2.saved" >"$d3_step/attempts/003.conf"
run "$CLI" doctor "$d3" --no-ollama; [ "$status" -eq 0 ] || fail 'normal Doctor rejected archive-hole warning'; contains "$output" "project.run.$d3_id — inconsistent" || fail 'archive-hole warning missing'
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict Doctor accepted archive hole'
rm -f "$d3_step/attempts/003.conf"; cp "$WORK/d3-attempt-2.saved" "$d3_step/attempts/002.conf"
sed 's/CCB_ATTEMPT_NUMBER=2/CCB_ATTEMPT_NUMBER=1/' "$WORK/d3-attempt-2.saved" >"$d3_step/attempts/002.conf"
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict Doctor accepted archive number mismatch'; cp "$WORK/d3-attempt-2.saved" "$d3_step/attempts/002.conf"
sed 's/CCB_STEP_PROVIDER=ollama/CCB_STEP_PROVIDER=remote/' "$WORK/d3-step.saved" >"$d3_step/step.conf"
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict Doctor accepted provider mismatch'; cp "$WORK/d3-step.saved" "$d3_step/step.conf"
sed 's/CCB_ATTEMPT_MODEL=qwen3:8b/CCB_ATTEMPT_MODEL=qwen3:4b/' "$WORK/d3-attempt-2.saved" >"$d3_step/attempts/002.conf"
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict Doctor accepted model mismatch'; cp "$WORK/d3-attempt-2.saved" "$d3_step/attempts/002.conf"
rm -f "$d3_step/attempts/002.conf"; ln -s "$WORK/d3-attempt-2.saved" "$d3_step/attempts/002.conf"
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict Doctor accepted archive symlink'; rm -f "$d3_step/attempts/002.conf"; cp "$WORK/d3-attempt-2.saved" "$d3_step/attempts/002.conf"
mv "$d3_step/attempts" "$WORK/d3-attempts.saved"; ln -s "$WORK/d3-attempts.saved" "$d3_step/attempts"
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict Doctor accepted attempts symlink'; rm -f "$d3_step/attempts"; mv "$WORK/d3-attempts.saved" "$d3_step/attempts"
sed 's/CCB_EXECUTION_ATTEMPT=3/CCB_EXECUTION_ATTEMPT=2/' "$WORK/d3-execution.saved" >"$d3_step/execution.conf"
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict Doctor accepted incoherent execution attempt'; cp "$WORK/d3-execution.saved" "$d3_step/execution.conf"
mkdir "$d3_step/.ccb-retry-transaction.residual"
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict Doctor accepted retry transaction residue'; rmdir "$d3_step/.ccb-retry-transaction.residual"
mkdir "$d3_run/.ccb-transaction.cancel-residual"
run "$CLI" doctor "$d3" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict Doctor accepted cancel transaction residue'; rmdir "$d3_run/.ccb-transaction.cancel-residual"

cancel_ready="$WORK/cancel ready"; "$CLI" init "$cancel_ready" --yes >/dev/null; start=$(CCB_TEST_RUN_TIMESTAMP=20260730-130000 "$CLI" workflow start feature "$cancel_ready"); cancel_ready_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p'); "$CLI" workflow cancel "$cancel_ready_id" "$cancel_ready" >/dev/null
run "$CLI" doctor "$cancel_ready" --no-ollama --strict; [ "$status" -eq 0 ] || fail "cancelled ready run rejected: $output"
cancel_active="$WORK/cancel active"; "$CLI" init "$cancel_active" --yes >/dev/null; start=$(CCB_TEST_RUN_TIMESTAMP=20260730-140000 "$CLI" workflow start feature "$cancel_active"); cancel_active_id=$(printf '%s\n' "$start" | sed -n 's/^Run ID: //p'); "$CLI" workflow resume "$cancel_active_id" "$cancel_active" >/dev/null; "$CLI" workflow cancel "$cancel_active_id" "$cancel_active" >/dev/null
run "$CLI" doctor "$cancel_active" --no-ollama --strict; [ "$status" -eq 0 ] || fail "cancelled active run rejected: $output"
cancel_active_run="$cancel_active/.ccb/runs/$cancel_active_id"; cp "$cancel_active_run/run.conf" "$WORK/cancel-run.saved"; sed 's/^CCB_RUN_COMPLETED_AT=.*/CCB_RUN_COMPLETED_AT=/' "$WORK/cancel-run.saved" >"$cancel_active_run/run.conf"
before=$(cksum "$cancel_active_run/run.conf"); run "$CLI" doctor "$cancel_active" --no-ollama; [ "$status" -eq 0 ] || fail 'normal Doctor rejected cancelled warning'; after=$(cksum "$cancel_active_run/run.conf"); [ "$before" = "$after" ] || fail 'Doctor repaired cancelled run'
run "$CLI" doctor "$cancel_active" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict Doctor accepted cancelled run without completed_at'

legacy="$WORK/legacy project"; "$CLI" init "$legacy" --yes >/dev/null
sed 's/CCB_TEMPLATE_VERSION=1.7.1/CCB_TEMPLATE_VERSION=1.6.0/' "$legacy/.ccb/project.conf" >"$legacy/.ccb/project.next" && mv "$legacy/.ccb/project.next" "$legacy/.ccb/project.conf"
rm -f "$legacy/.ccb/skills.conf"
rm -f "$legacy/.ccb/agents.conf"
run "$CLI" doctor "$legacy" --no-ollama; [ "$status" -eq 0 ] || fail 'legacy doctor should warn, not fail'; contains "$output" 'project.upgrade — run: ccb.sh upgrade TARGET --yes' || fail 'legacy upgrade recommendation missing'

chmod 666 "$project/.ccb/models.conf"
run "$CLI" doctor "$project" --no-ollama; [ "$status" -eq 0 ] || fail 'warning should not fail normal doctor'; contains "$output" 'project.models_conf.permissions — 666' || fail 'permission warning missing'
run "$CLI" doctor "$project" --no-ollama --strict; [ "$status" -eq 1 ] || fail 'strict warning should fail'
chmod 644 "$project/.ccb/models.conf"
printf 'CCB_MODEL_PROVIDER=unknown\n' >"$project/.ccb/models.conf"
run "$CLI" doctor "$project" --no-ollama; [ "$status" -eq 1 ] || fail 'invalid models should fail'; contains "$output" 'project.models_conf — invalid' || fail 'invalid config missing'

fake="$WORK/fake-bin"; mkdir "$fake"
cat >"$fake/ollama" <<'EOF'
#!/bin/sh
case "$1" in --version) echo ollama-test;; list) printf 'NAME ID\nqwen3:8b x\nqwen2.5-coder:7b y\n';; *) exit 9;; esac
EOF
chmod 755 "$fake/ollama"
"$CLI" init "$WORK/ollama" --yes >/dev/null
run env PATH="$fake:$PATH" "$CLI" doctor "$WORK/ollama"; [ "$status" -eq 0 ] || fail "fake Ollama doctor failed: $output"; contains "$output" 'ollama.command — available' || fail 'Ollama availability missing'

printf 'doctor tests passed\n'
