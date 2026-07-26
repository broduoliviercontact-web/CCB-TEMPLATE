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
