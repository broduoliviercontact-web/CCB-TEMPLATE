#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-profiles.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }
trap 'cleanup' EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { output=$("$@" 2>&1); status=$?; }
for profile in generic web node python audio; do
  target="$WORK/$profile project"; run "$CLI" init "$target" --profile "$profile" --yes
  [ "$status" -eq 0 ] || fail "profile $profile was rejected: $output"
  grep -Fqx "CCB_PROJECT_PROFILE=$profile" "$target/.ccb/project.conf" || fail "project profile missing: $profile"
  grep -Fq '## Profile guidance' "$target/.ccb/context/project.md" || fail "guidance missing: $profile"
  run "$CLI" init "$target" --profile "$profile"
  [ "$status" -eq 0 ] || fail "profile $profile is not idempotent"
  for file in .ccb/project.conf .ccb/models.conf .ccb/context/project.md AGENTS.md; do printf '%s' "$output" | grep -F "SKIP $file" >/dev/null || fail "SKIP missing: $file"; done
done
run "$CLI" init "$WORK/unknown" --profile react --yes; [ "$status" -eq 2 ] || fail 'unknown profile accepted'
printf '%s' "$output" | grep -F 'supported profiles: generic, web, node, python, audio' >/dev/null || fail 'supported profiles missing'
printf 'project profile tests passed\n'
