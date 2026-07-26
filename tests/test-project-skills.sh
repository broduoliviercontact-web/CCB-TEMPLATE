#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd); CLI="$ROOT/scripts/ccb.sh"; WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-skills-test.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }; trap 'cleanup' EXIT HUP INT TERM
fail(){ echo "FAIL: $*" >&2; exit 1; }; run(){ output=$("$@" 2>&1); status=$?; }
for mode in off lite full ultra; do target="$WORK/$mode project"; run "$CLI" init "$target" --ponytail-mode "$mode" --yes; [ "$status" -eq 0 ] || fail "$mode rejected"; grep -Fqx "CCB_SKILL_PONYTAIL_MODE=$mode" "$target/.ccb/skills.conf" || fail 'mode missing'; done
grep -Fqx 'CCB_SKILL_PONYTAIL=disabled' "$WORK/off project/.ccb/skills.conf" || fail off-status
grep -Fqx 'CCB_SKILL_PONYTAIL=enabled' "$WORK/full project/.ccb/skills.conf" || fail full-status
run "$CLI" init "$WORK/bad" --ponytail-mode FULL --yes; [ "$status" -eq 2 ] || fail 'invalid mode accepted'; [ ! -e "$WORK/bad" ] || fail 'invalid mode wrote target'
run "$CLI" init "$WORK/full project" --ponytail-mode full; [ "$status" -eq 0 ] || fail idempotence; for f in .ccb/project.conf .ccb/models.conf .ccb/skills.conf .ccb/context/project.md AGENTS.md; do printf '%s' "$output" | grep -F "SKIP $f" >/dev/null || fail "missing skip $f"; done
run "$CLI" init "$WORK/full project" --ponytail-mode lite; [ "$status" -eq 1 ] || fail 'mode change should conflict'
printf 'project skills tests passed\n'
