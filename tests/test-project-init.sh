#!/bin/sh
set -u

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-project-init-test.XXXXXX") || exit 1
cleanup() {
  find "$WORK" -depth -type f -exec rm -f {} \; 2>/dev/null || :
  find "$WORK" -depth -type l -exec rm -f {} \; 2>/dev/null || :
  find "$WORK" -depth -type d -exec rmdir {} \; 2>/dev/null || :
}
trap 'cleanup' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_status() { expected=$1 actual=$2 label=$3; [ "$actual" -eq "$expected" ] || fail "$label (expected status $expected, got $actual)"; }
assert_file() { [ -f "$1" ] && [ ! -L "$1" ] || fail "expected regular file: $1"; }
assert_not_exists() { [ ! -e "$1" ] && [ ! -L "$1" ] || fail "unexpected path: $1"; }
assert_contains() { printf '%s' "$1" | grep -F -- "$2" >/dev/null || fail "$3 (missing: $2)"; }
assert_no_temps() { found=$(find "$1" -name '.*.tmp.*' -print -quit); [ -z "$found" ] || fail "temporary file remains: $found"; }
run() { output=$("$@" 2>&1); status=$?; }

run "$CLI" init --help
assert_status 0 "$status" 'init help'
for option in TARGET --project-name --profile --model --planner-model --coder-model --reviewer-model --ponytail-mode --yes --dry-run; do assert_contains "$output" "$option" 'init help documents options'; done
run "$CLI" init; assert_status 2 "$status" 'missing target'
run "$CLI" init "$WORK/unknown" --unknown; assert_status 2 "$status" 'unknown option'
run "$CLI" init "$WORK/force" --force; assert_status 2 "$status" 'force is refused'
run "$CLI" init "$WORK/profile" --profile other; assert_status 2 "$status" 'unsupported profile'

existing="$WORK/existing project"; mkdir "$existing" || fail 'cannot create fixture'
run "$CLI" init "$existing"
assert_status 0 "$status" 'initial creation in existing directory'
for file in .ccb/project.conf .ccb/models.conf .ccb/skills.conf .ccb/agents.conf .ccb/context/project.md AGENTS.md; do assert_file "$existing/$file"; done
assert_contains "$(cat "$existing/.ccb/project.conf")" 'CCB_PROJECT_NAME=existing project' 'basename project name'
assert_contains "$(cat "$existing/.ccb/project.conf")" 'CCB_TEMPLATE_VERSION=1.7.0' 'template version'
assert_contains "$(cat "$existing/.ccb/context/project.md")" 'Project: existing project' 'context name'
assert_contains "$(cat "$existing/AGENTS.md")" 'Read .ccb/context/project.md' 'agent guidance'
assert_no_temps "$existing"

before_conf=$(cat "$existing/.ccb/project.conf")
run "$CLI" init "$existing"
assert_status 0 "$status" 'idempotent invocation'
for file in .ccb/project.conf .ccb/models.conf .ccb/skills.conf .ccb/agents.conf .ccb/context/project.md AGENTS.md; do assert_contains "$output" "SKIP $file" 'idempotent plan'; done
[ "$(cat "$existing/.ccb/project.conf")" = "$before_conf" ] || fail 'SKIP rewrote project.conf'
assert_no_temps "$existing"

partial="$WORK/partial"; mkdir -p "$partial/.ccb" || fail 'cannot create partial fixture'
cp "$existing/.ccb/project.conf" "$partial/.ccb/project.conf" || fail 'cannot seed partial fixture'
run "$CLI" init "$partial" --project-name 'existing project'
assert_status 0 "$status" 'partial initialization'
assert_contains "$output" 'SKIP .ccb/project.conf' 'partial SKIP'
assert_contains "$output" 'CREATE .ccb/context/project.md' 'partial context CREATE'
assert_contains "$output" 'CREATE .ccb/models.conf' 'partial models CREATE'
assert_contains "$output" 'CREATE .ccb/skills.conf' 'partial skills CREATE'
assert_contains "$output" 'CREATE .ccb/agents.conf' 'partial agents CREATE'
assert_contains "$output" 'CREATE AGENTS.md' 'partial AGENTS CREATE'

conflict="$WORK/conflict"; mkdir "$conflict" || fail 'cannot create conflict fixture'
printf 'user content\n' >"$conflict/AGENTS.md"
run "$CLI" init "$conflict"
assert_status 1 "$status" 'managed conflict'
assert_contains "$output" 'CONFLICT AGENTS.md' 'conflict plan'
assert_not_exists "$conflict/.ccb/project.conf"
[ "$(cat "$conflict/AGENTS.md")" = 'user content' ] || fail 'conflicting file changed'
assert_no_temps "$conflict"

dry="$WORK/dry run"; run "$CLI" init "$dry" --yes --dry-run
assert_status 0 "$status" 'dry run absent target'
assert_contains "$output" 'CREATE .ccb/project.conf' 'dry-run CREATE'
assert_contains "$output" 'CREATE .ccb/models.conf' 'dry-run models CREATE'
assert_contains "$output" 'CREATE .ccb/skills.conf' 'dry-run skills CREATE'
assert_contains "$output" 'CREATE .ccb/agents.conf' 'dry-run agents CREATE'
assert_not_exists "$dry"

run "$CLI" init "$existing" --dry-run
assert_status 0 "$status" 'dry run identical target'
assert_contains "$output" 'SKIP AGENTS.md' 'dry-run SKIP'

link="$WORK/link"; mkdir "$link" || fail 'cannot create symlink fixture'
ln -s "$existing/AGENTS.md" "$link/AGENTS.md" || fail 'cannot create symlink'
run "$CLI" init "$link"
assert_status 1 "$status" 'symlink conflict'
assert_contains "$output" 'symbolic links are not accepted: AGENTS.md' 'symlink explanation'

parent_bad="$WORK/parent-bad"; mkdir "$parent_bad" || fail 'cannot create parent fixture'
printf 'not a directory\n' >"$parent_bad/.ccb"
run "$CLI" init "$parent_bad"
assert_status 1 "$status" 'incompatible .ccb parent'
assert_not_exists "$parent_bad/AGENTS.md"

injection="$WORK/project..demo"; literal='Projet $(touch /tmp/ccb-project-init-injected) ; `touch /tmp/ccb-project-init-injected-2` "démo" avec '\''apostrophe'
rm -f /tmp/ccb-project-init-injected /tmp/ccb-project-init-injected-2
run "$CLI" init "$injection" --yes --project-name "$literal"
assert_status 0 "$status" 'literal project name'
assert_contains "$(cat "$injection/.ccb/project.conf")" "$literal" 'literal name in config'
assert_not_exists /tmp/ccb-project-init-injected
assert_not_exists /tmp/ccb-project-init-injected-2

for unsafe in / "$HOME" "$ROOT" "$WORK/.git" "$WORK/.git/child"; do
  run "$CLI" init "$unsafe" --dry-run
  assert_status 2 "$status" "unsafe target: $unsafe"
done

printf 'project-init tests passed\n'
