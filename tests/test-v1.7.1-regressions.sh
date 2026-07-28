#!/bin/sh
set -u

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-v1.7.1.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }
trap 'cleanup' EXIT HUP INT TERM
tests=0
pass() { tests=$((tests + 1)); }
fail() { echo "FAIL: $*" >&2; exit 1; }
contains() { printf '%s\n' "$1" | grep -Fq -- "$2" || fail "$3"; pass; }

project="$WORK/role models"
"$CLI" init "$project" --yes >/dev/null || fail 'role project init'
"$CLI" models setup "$project" --preset balanced-cloud --yes >/dev/null || fail 'role model setup'
for key in CCB_MODEL_PROVIDER CCB_OLLAMA_MODE CCB_OLLAMA_HOST CCB_MODEL_PRESET CCB_MODEL_MANAGER CCB_MODEL_GRAPH CCB_MODEL_GRAPHISTE CCB_MODEL_DEVELOPER CCB_MODEL_REVIEWER CCB_MODEL_FALLBACK; do
  grep -Eq "^${key}=.+" "$project/.ccb/models.conf" || fail "generated models.conf missing $key"
done
pass

validate_output=$("$CLI" models validate "$project") || fail 'role models validate'
contains "$validate_output" '(roles format)' 'role format was not reported'
printf '%s\n' '# TOKEN=regression-marker-must-not-be-shown' >>"$project/.ccb/models.conf"
show_output=$("$CLI" models show "$project") || fail 'role models show'
contains "$show_output" 'CCB_MODEL_MANAGER=glm-5.2:cloud' 'models show manager'
contains "$show_output" 'CCB_MODEL_GRAPH=qwen3.5:cloud' 'models show graph'
contains "$show_output" 'CCB_MODEL_GRAPHISTE=gemma4:cloud' 'models show graphiste'
contains "$show_output" 'CCB_MODEL_DEVELOPER=qwen3-coder:480b-cloud' 'models show developer'
contains "$show_output" 'CCB_MODEL_REVIEWER=deepseek-v4-pro:cloud' 'models show reviewer'
if printf '%s\n' "$show_output" | grep -Fq 'regression-marker-must-not-be-shown'; then fail 'models show exposed ignored secret-like content'; fi
pass

config_output=$("$CLI" config "$project") || fail 'config with role models'
contains "$config_output" 'Model configuration: roles' 'config role format'
contains "$config_output" 'Manager model: glm-5.2:cloud' 'config manager model'
contains "$config_output" 'Graph model: qwen3.5:cloud' 'config graph model'
contains "$config_output" 'Graphiste model: gemma4:cloud' 'config graphiste model'
contains "$config_output" 'Developer model: qwen3-coder:480b-cloud' 'config developer model'
contains "$config_output" 'Reviewer model: deepseek-v4-pro:cloud' 'config reviewer model'
"$CLI" doctor "$project" --no-ollama >/dev/null || fail 'normal Doctor rejected role format'; pass
"$CLI" doctor "$project" --no-ollama --strict >/dev/null || fail 'strict Doctor rejected role format'; pass

start_output=$(CCB_TEST_RUN_TIMESTAMP=20260727-171100 "$CLI" workflow start feature "$project") || fail 'workflow start with role models'
run_id=$(printf '%s\n' "$start_output" | sed -n 's/^Run ID: //p')
run_dir="$project/.ccb/runs/$run_id"
grep -Fqx 'CCB_STEP_MODEL=glm-5.2:cloud' "$run_dir/01-manager/step.conf" || fail 'manager snapshot model'
grep -Fqx 'CCB_STEP_MODEL=qwen3-coder:480b-cloud' "$run_dir/02-developer/step.conf" || fail 'developer snapshot model'
grep -Fqx 'CCB_STEP_MODEL=deepseek-v4-pro:cloud' "$run_dir/03-reviewer/step.conf" || fail 'reviewer snapshot model'
pass
inspect_output=$("$CLI" workflow inspect "$run_id" "$project") || fail 'inspect role models'
contains "$inspect_output" 'Model: glm-5.2:cloud' 'inspect manager model'
contains "$inspect_output" 'Model: qwen3-coder:480b-cloud' 'inspect developer model'
contains "$inspect_output" 'Model: deepseek-v4-pro:cloud' 'inspect reviewer model'

"$CLI" workflow resume "$run_id" "$project" >/dev/null || fail 'resume no-newline run'
without_newline="$WORK/without-newline"
printf '%s' 'Ollama response without final newline.' >"$without_newline"
CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$without_newline" "$CLI" workflow execute-step "$run_id" "$project" >/dev/null || fail 'execute response without newline'
[ "$(tail -c 1 "$run_dir/01-manager/result.md" | wc -l | tr -d ' ')" = 1 ] || fail 'published result lacks final newline'
grep -Fqx 'Ollama response without final newline.' "$run_dir/01-manager/result.md" || fail 'no-newline response content changed'
pass
"$CLI" workflow complete-step "$run_id" "$project" >/dev/null || fail 'complete no-newline step'
grep -Fqx -- '----- END PREVIOUS RESULT -----' "$run_dir/02-developer/input.md" || fail 'end marker is not on its own line'
grep -Fqx 'Ollama response without final newline.' "$run_dir/02-developer/input.md" || fail 'no-newline response not transmitted'
pass

with_newline="$WORK/with-newline"
printf '%s\n' 'Ollama response with final newline.' >"$with_newline"
CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$with_newline" "$CLI" workflow run "$run_id" "$project" >/dev/null || fail 'complete manager-developer-reviewer orchestration'
grep -Fqx 'CCB_RUN_STATUS=completed' "$run_dir/run.conf" || fail 'orchestration did not complete'
grep -Fqx 'Ollama response with final newline.' "$run_dir/02-developer/result.md" || fail 'newline response content changed'
grep -Fqx 'Ollama response with final newline.' "$run_dir/03-reviewer/result.md" || fail 'reviewer response missing'
grep -Fqx -- '----- END PREVIOUS RESULT -----' "$run_dir/03-reviewer/input.md" || fail 'newline response marker is malformed'
pass

legacy="$WORK/legacy models"
"$CLI" init "$legacy" --model legacy-default:latest --planner-model legacy-planner:latest --coder-model legacy-coder:latest --reviewer-model legacy-reviewer:latest --yes >/dev/null || fail 'legacy project init'
sed 's/CCB_TEMPLATE_VERSION=1.8.0/CCB_TEMPLATE_VERSION=1.7.0/' "$legacy/.ccb/project.conf" >"$legacy/.ccb/project.next" || fail 'prepare V1.7.0 project metadata'
mv "$legacy/.ccb/project.next" "$legacy/.ccb/project.conf" || fail 'publish V1.7.0 project metadata'
legacy_validate=$("$CLI" models validate "$legacy") || fail 'legacy models validate'
contains "$legacy_validate" '(legacy format)' 'legacy format was not reported'
legacy_show=$("$CLI" models show "$legacy") || fail 'legacy models show'
contains "$legacy_show" 'CCB_MODEL_PLANNER=legacy-planner:latest' 'legacy models show planner'
legacy_config=$("$CLI" config "$legacy") || fail 'legacy config'
contains "$legacy_config" 'Manager model: legacy-planner:latest' 'legacy manager mapping'
contains "$legacy_config" 'Graph model: legacy-planner:latest' 'legacy graph mapping'
contains "$legacy_config" 'Graphiste model: legacy-planner:latest' 'legacy graphiste mapping'
contains "$legacy_config" 'Developer model: legacy-coder:latest' 'legacy developer mapping'
contains "$legacy_config" 'Fallback model: legacy-default:latest' 'legacy fallback mapping'
"$CLI" doctor "$legacy" --no-ollama >/dev/null || fail 'normal Doctor rejected legacy format'; pass
"$CLI" doctor "$legacy" --no-ollama --strict >/dev/null || fail 'strict Doctor rejected legacy format'; pass
legacy_start=$(CCB_TEST_RUN_TIMESTAMP=20260727-171200 "$CLI" workflow start design "$legacy") || fail 'legacy workflow start'
legacy_id=$(printf '%s\n' "$legacy_start" | sed -n 's/^Run ID: //p')
grep -Fqx 'CCB_STEP_MODEL=legacy-planner:latest' "$legacy/.ccb/runs/$legacy_id/01-manager/step.conf" || fail 'legacy manager snapshot'
grep -Fqx 'CCB_STEP_MODEL=legacy-planner:latest' "$legacy/.ccb/runs/$legacy_id/02-graphiste/step.conf" || fail 'legacy graphiste snapshot'
grep -Fqx 'CCB_STEP_MODEL=legacy-reviewer:latest' "$legacy/.ccb/runs/$legacy_id/03-reviewer/step.conf" || fail 'legacy reviewer snapshot'
pass

residue=$(find "$WORK" \( -name '.ccb-execution-lock' -o -name '.ccb-orchestration-lock' -o -name '.ccb-transaction.*' -o -name '.ccb-retry-transaction.*' -o -name '.ccb-publish.*' -o -name '.result.md.execution-*' \) -print -quit)
[ -z "$residue" ] || fail "workflow residue remains: $residue"
pass
printf 'V1.7.1 regression tests passed: %s/%s\n' "$tests" "$tests"
