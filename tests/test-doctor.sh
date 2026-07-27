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

legacy="$WORK/legacy project"; "$CLI" init "$legacy" --yes >/dev/null
sed 's/CCB_TEMPLATE_VERSION=1.7.0/CCB_TEMPLATE_VERSION=1.6.0/' "$legacy/.ccb/project.conf" >"$legacy/.ccb/project.next" && mv "$legacy/.ccb/project.next" "$legacy/.ccb/project.conf"
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
