#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/ccb"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-v1.8.0-quickstart.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }
trap 'cleanup' EXIT HUP INT TERM
tests=0
pass() { tests=$((tests + 1)); }
fail() { echo "FAIL: $1" >&2; exit 1; }
response="$WORK/provider-response"; printf 'simulated provider result\n' >"$response"
run() { output=$(CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$response" "$@" 2>&1); status=$?; }

project="$WORK/top chef"
run "$CLI" quickstart "$project" --name "Top Chef" --profile web --cloud --run feature --yes
[ "$status" -eq 0 ] || fail "quickstart new target: $output"
printf '%s' "$output" | grep -Fq 'CCB project ready.' || fail 'quickstart summary'; pass
[ -d "$project/.ccb" ] && [ -f "$project/.ccb/models.conf" ] || fail 'bootstrap files'; pass
grep -Fqx 'CCB_MODEL_PRESET=coding-cloud' "$project/.ccb/models.conf" || fail 'cloud preset'; pass
grep -Fqx 'CCB_OLLAMA_MODE=local-proxy' "$project/.ccb/models.conf" || fail 'cloud mode'; pass
grep -Fqx 'CCB_MODEL_MANAGER=glm-5.2:cloud' "$project/.ccb/models.conf" &&
grep -Fqx 'CCB_MODEL_GRAPH=qwen3.5:397b-cloud' "$project/.ccb/models.conf" &&
grep -Fqx 'CCB_MODEL_GRAPHISTE=gemma4:31b-cloud' "$project/.ccb/models.conf" &&
grep -Fqx 'CCB_MODEL_DEVELOPER=kimi-k2.7-code:cloud' "$project/.ccb/models.conf" &&
grep -Fqx 'CCB_MODEL_REVIEWER=deepseek-v4-pro:cloud' "$project/.ccb/models.conf" &&
grep -Fqx 'CCB_MODEL_FALLBACK=qwen3-coder:480b-cloud' "$project/.ccb/models.conf" || fail 'coding-cloud assignments'; pass
grep -Fq 'CCB_RUN_STATUS=completed' "$project/.ccb/runs"/*/run.conf || fail 'feature run completed'; pass
if grep -Fq 'qwen3:8b' "$project/.ccb/models.conf" || grep -Fq 'qwen2.5-coder:7b' "$project/.ccb/models.conf"; then fail 'local model selected'; fi; pass

empty="$WORK/empty"; mkdir "$empty"
run "$CLI" quickstart "$empty" --project-name Empty --profile generic --no-run --yes
[ "$status" -eq 0 ] || fail "empty target: $output"; [ ! -d "$empty/.ccb/runs" ] || fail 'no-run created a run'; pass

before=$(find "$empty" -type f -exec cksum {} \; | LC_ALL=C sort)
run "$CLI" quickstart "$empty" --profile generic --dry-run --yes
[ "$status" -eq 0 ] || fail 'dry-run failed'; after=$(find "$empty" -type f -exec cksum {} \; | LC_ALL=C sort)
[ "$before" = "$after" ] || fail 'dry-run modified target'; pass

run "$CLI" quickstart "$empty" --project-name Empty --profile generic --no-run --yes
[ "$status" -eq 0 ] || fail 'idempotent quickstart'; printf '%s' "$output" | grep -Fq 'CCB project ready.' || fail 'idempotent summary'; pass

printf 'user data\n' >"$empty/notes.txt"
run "$CLI" quickstart "$empty" --project-name Empty --profile generic --no-run --yes
[ "$status" -eq 0 ] && [ -f "$empty/notes.txt" ] || fail 'user file changed'; pass

conflict="$WORK/conflict"; mkdir "$conflict"; printf 'not CCB\n' >"$conflict/.ccb"
run "$CLI" quickstart "$conflict" --profile generic --no-run --yes
[ "$status" -ne 0 ] || fail 'incompatible target accepted'; printf '%s' "$output" | grep -Fq 'Project bootstrap failed' || fail 'conflict diagnostic'; pass

link="$WORK/link"; ln -s "$empty" "$link"
run "$CLI" quickstart "$link" --yes
[ "$status" -ne 0 ] || fail 'symlink target accepted'; pass

rollback="$WORK/rollback"
run env CCB_TEST_QUICKSTART_FAIL_STAGE=bootstrap "$CLI" quickstart "$rollback" --yes
[ "$status" -ne 0 ] && [ ! -e "$rollback" ] || fail 'bootstrap rollback'; pass
run env CCB_TEST_QUICKSTART_FAIL_STAGE=config "$CLI" quickstart "$empty" --yes
[ "$status" -ne 0 ] || fail 'config fail hook ignored'; pass
run env CCB_TEST_QUICKSTART_FAIL_STAGE=doctor "$CLI" quickstart "$empty" --yes
[ "$status" -ne 0 ] || fail 'doctor fail hook ignored'; pass

legacy="$WORK/legacy"; ./scripts/ccb.sh init "$legacy" --yes >/dev/null
sed -i.bak 's/CCB_MODEL_PROVIDER=.*/CCB_MODEL_PROVIDER=ollama/; /CCB_MODEL_PRESET/d; /CCB_OLLAMA_MODE/d; /CCB_OLLAMA_HOST/d; /CCB_MODEL_MANAGER/d; /CCB_MODEL_GRAPH/d; /CCB_MODEL_GRAPHISTE/d; /CCB_MODEL_DEVELOPER/d; /CCB_MODEL_FALLBACK/d' "$legacy/.ccb/models.conf"
run "$CLI" config "$legacy"; [ "$status" -eq 0 ] || fail 'legacy config'; pass
run "$CLI" doctor "$legacy" --no-ollama --strict; [ "$status" -eq 0 ] || fail 'legacy doctor'; pass

role="$WORK/role"; ./scripts/ccb.sh init "$role" --yes >/dev/null; ./scripts/ccb.sh models setup "$role" --preset coding-cloud --mode local-proxy --yes >/dev/null
run "$CLI" config "$role"; [ "$status" -eq 0 ] && printf '%s' "$output" | grep -Fq 'Manager model: glm-5.2:cloud' || fail 'role config'; pass
run "$CLI" doctor "$role" --no-ollama --strict; [ "$status" -eq 0 ] || fail 'role doctor'; pass
run "$CLI" workflow start feature "$role"; [ "$status" -eq 0 ] && printf '%s' "$output" | grep -Fq 'Execution started: no' || fail 'role workflow'; pass

spaces="$WORK/relative path"; (cd "$WORK" && CCB_TEST_MODE=1 "$CLI" quickstart "relative path" --project-name 'Name With Spaces' --no-run --yes >/dev/null) || fail 'relative target'; [ -d "$spaces/.ccb" ] || fail 'relative target missing'; pass

printf 'quickstart tests passed: %s/%s\n' "$tests" "$tests"
