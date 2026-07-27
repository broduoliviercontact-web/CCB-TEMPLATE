#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd); CLI="$ROOT/scripts/ccb.sh"; WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-agents-test.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }; trap 'cleanup' EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }; run() { output=$("$@" 2>&1); status=$?; }; has() { printf '%s' "$1" | grep -Fq -- "$2" || fail "$3"; }
target="$WORK/agents project"; run "$CLI" init "$target" --profile web --yes; [ "$status" -eq 0 ] || fail init
[ -f "$target/.ccb/agents.conf" ] && [ ! -L "$target/.ccb/agents.conf" ] || fail 'agents file missing'; grep -Fqx 'CCB_AGENTS_VERSION=1' "$target/.ccb/agents.conf" || fail schema; grep -Fqx 'CCB_AGENT_DEFAULT=manager' "$target/.ccb/agents.conf" || fail default
run "$CLI" agents "$target"; [ "$status" -eq 0 ] || fail list; has "$output" 'Enforcement: declarative only' enforcement; has "$output" 'developer' developer; has "$output" 'ollama' provider
run "$CLI" agent show developer "$target"; [ "$status" -eq 0 ] || fail show; has "$output" 'Access: write' access; has "$output" 'Model role: coder' modelrole
run "$CLI" agent validate "$target"; [ "$status" -eq 0 ] || fail validate; has "$output" '5 agent roles' count
run "$CLI" init "$target" --profile web --yes; [ "$status" -eq 0 ] || fail idempotent; has "$output" 'SKIP .ccb/agents.conf' skip
printf 'USER_CUSTOM_KEY=keep\n' >>"$target/.ccb/agents.conf"; run "$CLI" init "$target" --profile web --yes; [ "$status" -eq 1 ] || fail conflict; has "$output" 'CONFLICT .ccb/agents.conf' conflict
bad="$WORK/bad"; "$CLI" init "$bad" --yes >/dev/null; printf 'CCB_AGENT_DEVELOPER_ACCESS=WRITE\n' >>"$bad/.ccb/agents.conf"; run "$CLI" agent validate "$bad"; [ "$status" -eq 1 ] || fail duplicate-invalid
printf 'project agents tests passed\n'
