#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
CLI="$TEMPLATE_ROOT/scripts/ccb.sh"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ccb-cli-test.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

assert_contains() {
  output=$1
  expected=$2
  label=$3
  printf '%s\n' "$output" | grep -Fq -- "$expected" || {
    echo "assertion failed: $label (expected: $expected)" >&2
    exit 1
  }
}

help_output=$("$CLI" help)
assert_contains "$help_output" 'init TARGET [OPTIONS]' 'help documents project bootstrap'
assert_contains "$help_output" 'config TARGET' 'help documents bootstrap config'
assert_contains "$help_output" 'skills TARGET' 'help documents skills'
assert_contains "$help_output" 'upgrade TARGET [OPTIONS]' 'help documents project upgrade'
assert_contains "$help_output" 'agents [TARGET]' 'help documents declarative agents'
assert_contains "$help_output" 'agent show ROLE' 'help documents agent show'
assert_contains "$help_output" 'workflow show|plan NAME' 'help documents workflows'
assert_contains "$help_output" 'doctor [TARGET]' 'help documents doctor'
version_output=$("$CLI" version)
[ "$version_output" = 1.7.0 ] || {
  echo "assertion failed: version is $version_output (expected: 1.7.0)" >&2
  exit 1
}
init_help=$("$CLI" init --help 2>&1)
assert_contains "$init_help" 'init TARGET' 'project bootstrap help is available'
assert_contains "$init_help" '--ponytail-mode' 'init documents Ponytail mode'
"$CLI" skills --help >/dev/null 2>&1
"$CLI" upgrade --help >/dev/null 2>&1
"$CLI" models presets | grep -Fq balanced-cloud || { echo 'assertion failed: models presets lists balanced-cloud' >&2; exit 1; }
"$CLI" models recommendations | grep -Fq balanced-cloud || { echo 'assertion failed: model recommendations list balanced-cloud' >&2; exit 1; }
"$CLI" mascots | grep -Fq terminal-bot || { echo 'assertion failed: mascots list terminal-bot' >&2; exit 1; }
"$CLI" mascot show terminal-bot | grep -Fq '[NEUTRAL]' || { echo 'assertion failed: mascot show reports neutral mood' >&2; exit 1; }
"$CLI" mascot moods terminal-bot | grep -Fq goodbye || { echo 'assertion failed: mascot moods lists goodbye' >&2; exit 1; }
if "$CLI" --mood invalid/value >/dev/null 2>&1; then echo "invalid mood was accepted" >&2; exit 1; fi
"$CLI" profiles | grep -Fq 'generic'
"$CLI" profile show generic | grep -Fq 'ID: generic'
if "$CLI" profile show unknown >/dev/null 2>&1; then echo "unknown profile was accepted" >&2; exit 1; fi
if "$CLI" unknown >/dev/null 2>&1; then echo "unknown command was accepted" >&2; exit 1; else test "$?" -eq 2; fi
NO_COLOR=1 "$CLI" profiles | grep -q 'generic'
CCB_ASCII=1 "$CLI" profiles | grep -q 'generic'
printf 'q\n' | "$CLI" | grep -q 'CCB CONTROL ROOM'
for mascot in terminal-bot radio-bot synth-bot server-bot space-bot; do
  printf 'q\n' | CCB_NO_ANIMATION=1 CCB_MASCOT="$mascot" "$CLI" | grep -Fq "Mascot: $(printf '%s' "$mascot" | tr '-' ' ' | sed 's/\b\([a-z]\)/\1/')" || :
done
printf 'q\n' | CCB_NO_ANIMATION=1 CCB_MASCOT=terminal-bot "$CLI" | grep -Fq 'Mascot: Terminal Bot'
printf 'q\n' | CCB_NO_ANIMATION=1 "$CLI" --mascot radio-bot | grep -Fq 'Mascot: Radio Bot'
if "$CLI" --mascot invalid/id >/dev/null 2>&1; then echo "unsafe mascot accepted" >&2; exit 1; fi
printf 'q\n' | env CCB_ASCII=1 CCB_NO_ANIMATION=1 CCB_MASCOT=terminal-bot "$CLI" >/dev/null

repo="$TEMP_ROOT/project"
mkdir -p "$repo"
git init -q "$repo"
git -C "$repo" config user.name "CCB CLI Test"
git -C "$repo" config user.email "ccb-cli-test@example.invalid"
printf 'fixture\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm fixture
"$CLI" install "$repo" --profile react-web >/dev/null
"$CLI" validate "$repo" >/dev/null
"$CLI" doctor --no-ollama >/dev/null
"$CLI" status "$repo" | grep -Fq 'Active profile: react-web'

echo "[OK] CLI integration tests passed"
