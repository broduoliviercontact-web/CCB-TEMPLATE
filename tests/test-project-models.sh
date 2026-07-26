#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-models.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }
trap 'cleanup' EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { output=$("$@" 2>&1); status=$?; }
target="$WORK/models"; run "$CLI" init "$target" --profile web --model registry/model:tag --coder-model qwen2.5-coder:7b --yes
[ "$status" -eq 0 ] || fail "custom models rejected: $output"
grep -Fqx 'CCB_MODEL_PROVIDER=ollama' "$target/.ccb/models.conf" || fail 'provider missing'
grep -Fqx 'CCB_MODEL_DEFAULT=registry/model:tag' "$target/.ccb/models.conf" || fail 'default override missing'
grep -Fqx 'CCB_MODEL_PLANNER=registry/model:tag' "$target/.ccb/models.conf" || fail 'planner priority missing'
grep -Fqx 'CCB_MODEL_CODER=qwen2.5-coder:7b' "$target/.ccb/models.conf" || fail 'coder priority missing'
"$ROOT/scripts/model-resolve.sh" developer "$target" | grep -Fxq qwen2.5-coder:7b || fail 'resolver mapping missing'
bad="$WORK/bad"; run "$CLI" init "$bad" --model '$(touch /tmp/ccb-model-injected)' --yes; [ "$status" -eq 2 ] || fail 'unsafe model accepted'; [ ! -e /tmp/ccb-model-injected ] || fail 'model value was executed'; [ ! -e "$bad" ] || fail 'unsafe model wrote target'
printf 'different\n' >"$target/.ccb/models.conf"; run "$CLI" init "$target" --profile web --model registry/model:tag --coder-model qwen2.5-coder:7b; [ "$status" -eq 1 ] || fail 'models conflict not detected'; printf '%s' "$output" | grep -F 'CONFLICT .ccb/models.conf' >/dev/null || fail 'models conflict plan missing'
printf 'project model tests passed\n'
