#!/bin/sh
set -u

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-upgrade-test.XXXXXX") || exit 1
cleanup() { find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :; find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :; }
trap 'cleanup' EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { output=$("$@" 2>&1); status=$?; }
assert() { [ "$1" = "$2" ] || fail "$3 (expected $1, got $2)"; }
contains() { printf '%s' "$1" | grep -Fq -- "$2" || fail "$3"; }

make_legacy() {
  dir=$1; mkdir -p "$dir/.ccb/context" || exit 1
  "$CLI" init "$dir" --yes >/dev/null || exit 1
  sed 's/CCB_TEMPLATE_VERSION=1.7.1/CCB_TEMPLATE_VERSION=1.6.0/' "$dir/.ccb/project.conf" >"$dir/.ccb/project.next" && mv "$dir/.ccb/project.next" "$dir/.ccb/project.conf"
  printf '# Project context\n\nProject: %s\nProfile: generic\n\n## Profile guidance\n\nMake cautious changes and validate before modifying project files.\n\nSafety: Keep credentials out of project files and review changes before committing.\n\n## Model routing\n\nProvider: ollama\nDefault: qwen3:8b\nPlanner: qwen3:8b\nCoder: qwen2.5-coder:7b\nReviewer: qwen3:8b\n' "$(basename "$dir")" >"$dir/.ccb/context/project.md"
  printf '# Agent guidance\n\nRead .ccb/context/project.md before modifying files.\nRead .ccb/models.conf before selecting a model or agent role.\nFollow project safety conventions.\n' >"$dir/AGENTS.md"
  rm -f "$dir/.ccb/skills.conf"
  rm -f "$dir/.ccb/agents.conf"
}

run "$CLI" upgrade --help; assert 0 "$status" 'help status'; contains "$output" '--dry-run' 'help documents dry run'
run "$CLI" upgrade; assert 2 "$status" 'missing target'
run "$CLI" upgrade "$WORK/nope" --yes; assert 1 "$status" 'missing target rejected'
run "$CLI" upgrade "$WORK/nope" --ponytail-mode BAD --yes; assert 2 "$status" 'invalid mode rejected'

legacy="$WORK/legacy"; make_legacy "$legacy"
before=$(cksum "$legacy/.ccb/project.conf" "$legacy/.ccb/context/project.md" "$legacy/AGENTS.md")
run "$CLI" upgrade "$legacy" --dry-run; assert 0 "$status" 'legacy dry run'; contains "$output" 'UPDATE   .ccb/project.conf' 'project update plan'; contains "$output" 'CREATE   .ccb/skills.conf' 'skills create plan'; contains "$output" 'DRY RUN' 'dry run notice'
after=$(cksum "$legacy/.ccb/project.conf" "$legacy/.ccb/context/project.md" "$legacy/AGENTS.md"); [ "$before" = "$after" ] || fail 'dry run modified files'
run "$CLI" upgrade "$legacy"; assert 2 "$status" 'noninteractive confirmation required'
run "$CLI" upgrade "$legacy" --yes; assert 0 "$status" 'upgrade applies'; grep -Fqx 'CCB_TEMPLATE_VERSION=1.6.1' "$legacy/.ccb/project.conf" || fail 'version not updated'; grep -Fqx 'CCB_SKILL_PONYTAIL_MODE=full' "$legacy/.ccb/skills.conf" || fail 'skills not created'; contains "$(cat "$legacy/AGENTS.md")" '## Ponytail' 'agents updated'
[ ! -e "$legacy/.ccb/agents.conf" ] || fail 'historical upgrade created agents.conf'
run "$CLI" upgrade "$legacy" --dry-run; assert 0 "$status" 'already current'; contains "$output" 'Result: already up to date' 'already current result'; contains "$output" 'SKIP     AGENTS.md' 'all skip'

conflict="$WORK/conflict"; make_legacy "$conflict"; printf 'user additions\n' >>"$conflict/AGENTS.md"
run "$CLI" upgrade "$conflict" --dry-run; assert 1 "$status" 'custom agents conflict'; contains "$output" 'CONFLICT AGENTS.md' 'conflict plan'; [ ! -e "$conflict/.ccb/skills.conf" ] || fail 'conflict wrote skills'
printf 'project-upgrade tests passed\n'
