#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
INSTALL="$ROOT/install.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-v2-install.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
BIN="$WORK/bin"
mkdir -p "$BIN"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { printf '%s\n' "$1" | grep -Fq -- "$2" || fail "missing $2"; }
run() {
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
  return 0
}

cat >"$BIN/tmux" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$BIN/claude" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$WORK/claude.calls"
exit 77
EOF
cat >"$BIN/ollama" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$WORK/ollama.calls"
case "\${1:-}" in
  list) cat <<'MODELS'
NAME ID SIZE MODIFIED
glm-5.2:cloud a 1 now
qwen3.5:397b-cloud b 1 now
gemma4:31b-cloud c 1 now
kimi-k2.7-code:cloud d 1 now
deepseek-v4-pro:cloud e 1 now
MODELS
  ;;
  *) exit 88 ;;
esac
EOF
cat >"$BIN/ccb" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$WORK/ccb.calls"
case "\${1:-}" in --version) echo 'ccb (Claude Code Bridge) v8.4.3 test' ;; *) exit 91 ;; esac
EOF
cat >"$BIN/python-good" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -c ]; then echo 3.12; exit 0; fi
exit 1
EOF
cat >"$BIN/python-old" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -c ]; then echo 3.9; exit 0; fi
exit 1
EOF
cat >"$BIN/python-missing-deps" <<'EOF'
#!/bin/sh
case "${2:-}" in
  *sys.version_info*) echo 3.14; exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN"/*

ENV="PATH=$BIN:$PATH CCB_PYTHON=$BIN/python-good"

help=$($INSTALL --help)
assert_contains "$help" '--claude-ollama-cloud'

dry="$WORK/dry"
run env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$dry" --name Dry --profile web --claude-ollama-cloud --dry-run
[ "$status" -eq 0 ] || fail "dry-run failed: $output"
[ ! -e "$dry" ] || fail 'dry-run wrote the target'
assert_contains "$output" 'DRY RUN — no files were modified.'

run sh -c "printf '' | env PATH='$BIN:$PATH' CCB_PYTHON='$BIN/python-good' '$INSTALL' '$WORK/non-tty' --name NonTTY --profile web --claude-ollama-cloud"
[ "$status" -ne 0 ] || fail 'non-TTY install without --yes succeeded'
[ ! -e "$WORK/non-tty" ] || fail 'non-TTY refusal wrote files'

project="$WORK/project"
run env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" ANTHROPIC_AUTH_TOKEN='CCB_TEMPLATE_SIMULATED_TOKEN_DO_NOT_PERSIST' "$INSTALL" "$project" --name 'Web Project' --profile web --claude-ollama-cloud --yes
[ "$status" -eq 0 ] || fail "installation failed: $output"
cmp -s "$project/.ccb/ccb.config" "$ROOT/tests/fixtures/ccb.config.expected" || fail 'configuration is not deterministic expected output'
for agent in manager graph graphiste developer reviewer; do
  grep -Fq "[agents.$agent]" "$project/.ccb/ccb.config" || fail "missing agent $agent"
  grep -Fq "[agents.$agent.provider_profile]" "$project/.ccb/ccb.config" || fail "missing provider profile $agent"
  grep -A2 -F "[agents.$agent.provider_profile]" "$project/.ccb/ccb.config" | grep -Fqx 'inherit_api = false' || fail "missing inherit_api $agent"
  grep -A2 -F "[agents.$agent.provider_profile]" "$project/.ccb/ccb.config" | grep -Fqx 'inherit_auth = false' || fail "missing inherit_auth $agent"
  [ -f "$project/.ccb/agents/$agent/memory.md" ] || fail "missing memory $agent"
done
grep -Fqx 'ANTHROPIC_AUTH_TOKEN = "ollama"' "$project/.ccb/ccb.config" || fail 'missing literal Ollama authentication marker'
grep -Fqx 'ANTHROPIC_BASE_URL = "http://localhost:11434"' "$project/.ccb/ccb.config" || fail 'missing Ollama base URL'
retired_prefix=qwen3-coder
retired_model=$retired_prefix:480b-cloud
if rg -n "$retired_model|sk-ant-|Bearer [A-Za-z0-9]" "$ROOT/install.sh" "$ROOT/scripts/v2" "$ROOT/assets" "$project/.ccb" >/dev/null; then fail 'new V2 files contain a retired model or sensitive token'; fi
grep -Fxv -- '--version' "$WORK/ccb.calls" >/dev/null && fail 'installer executed ccb beyond --version' || :
[ ! -e "$WORK/claude.calls" ] || fail 'installer executed Claude Code'

second="$WORK/second"
env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$second" --name 'Other name' --profile web --claude-ollama-cloud --yes >/dev/null
cmp -s "$project/.ccb/ccb.config" "$second/.ccb/ccb.config" || fail 'configuration changed with project name'

preserve="$WORK/preserve"
mkdir -p "$preserve/.ccb"
printf 'custom memory\n' >"$preserve/.ccb/ccb_memory.md"
env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$preserve" --name Preserve --profile web --claude-ollama-cloud --yes >/dev/null
[ "$(cat "$preserve/.ccb/ccb_memory.md")" = 'custom memory' ] || fail 'existing memory was overwritten'

conflict="$WORK/conflict"
mkdir -p "$conflict/.ccb"
printf 'existing config\n' >"$conflict/.ccb/ccb.config"
run env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$conflict" --name Conflict --profile web --claude-ollama-cloud --yes
[ "$status" -ne 0 ] || fail 'existing ccb.config was overwritten'
[ "$(cat "$conflict/.ccb/ccb.config")" = 'existing config' ] || fail 'ccb.config changed after refusal'

linked="$WORK/linked"
mkdir "$linked"
ln -s "$WORK/elsewhere" "$linked/.ccb"
run env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$linked" --name Linked --profile web --claude-ollama-cloud --yes
[ "$status" -ne 0 ] || fail 'symbolic .ccb directory accepted'

python_deps="$WORK/python-deps"
mkdir "$python_deps"
cp "$BIN/python-missing-deps" "$python_deps/python3.14"
cp "$BIN/python-good" "$python_deps/python3.13"
chmod +x "$python_deps"/*
run env PATH="$python_deps:$BIN:/usr/bin:/bin" "$INSTALL" "$WORK/python-deps-target" --name PythonDeps --profile web --claude-ollama-cloud --dry-run
[ "$status" -eq 0 ] || fail "missing-dependencies fallback failed: $output"
assert_contains "$output" "Python candidate rejected: $python_deps/python3.14 (missing tomllib/tomli, aiohttp, or cryptography)"
assert_contains "$output" "Python: $python_deps/python3.13 (3.12)"

python_old="$WORK/python-old-fallback"
mkdir "$python_old"
cp "$BIN/python-old" "$python_old/python3.14"
cp "$BIN/python-good" "$python_old/python3.13"
chmod +x "$python_old"/*
run env PATH="$python_old:$BIN:/usr/bin:/bin" "$INSTALL" "$WORK/python-old-fallback-target" --name PythonOld --profile web --claude-ollama-cloud --dry-run
[ "$status" -eq 0 ] || fail "old-Python fallback failed: $output"
assert_contains "$output" "Python candidate rejected: $python_old/python3.14 (requires Python 3.10+, found 3.9)"
assert_contains "$output" "Python: $python_old/python3.13 (3.12)"

python_ccb="$WORK/python-ccb-fallback"
mkdir "$python_ccb"
cp "$BIN/python-good" "$python_ccb/python3.14"
chmod +x "$python_ccb/python3.14"
run env PATH="$python_ccb:$BIN:/usr/bin:/bin" CCB_PYTHON="$BIN/python-old" "$INSTALL" "$WORK/python-ccb-fallback-target" --name PythonCCB --profile web --claude-ollama-cloud --dry-run
[ "$status" -eq 0 ] || fail "CCB_PYTHON fallback failed: $output"
assert_contains "$output" "Python candidate rejected: $BIN/python-old (requires Python 3.10+, found 3.9)"
assert_contains "$output" "Python: $python_ccb/python3.14 (3.12)"

python_none="$WORK/python-none"
mkdir "$python_none"
cp "$BIN/python-missing-deps" "$python_none/python3.14"
cp "$BIN/python-old" "$python_none/python3.13"
cp "$BIN/python-old" "$python_none/python3.12"
cp "$BIN/python-old" "$python_none/python3.11"
cp "$BIN/python-old" "$python_none/python3.10"
cp "$BIN/python-old" "$python_none/python3"
chmod +x "$python_none"/*
run env PATH="$python_none:$BIN:/usr/bin:/bin" "$INSTALL" "$WORK/python-none-target" --name PythonNone --profile web --claude-ollama-cloud --dry-run
[ "$status" -ne 0 ] || fail 'no-compatible-Python case succeeded'
assert_contains "$output" 'no compatible Python found'

python_priority="$WORK/python-priority"
mkdir "$python_priority"
cp "$BIN/python-missing-deps" "$python_priority/python3.14"
chmod +x "$python_priority/python3.14"
run env PATH="$python_priority:$BIN:/usr/bin:/bin" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$WORK/python-priority-target" --name PythonPriority --profile web --claude-ollama-cloud --dry-run
[ "$status" -eq 0 ] || fail "CCB_PYTHON priority failed: $output"
assert_contains "$output" "Python: $BIN/python-good (3.12)"
if printf '%s\n' "$output" | grep -Fq 'python3.14'; then fail 'compatible CCB_PYTHON did not retain priority'; fi

oldbin="$WORK/old-bin"
mkdir "$oldbin"
cp "$BIN"/tmux "$BIN"/claude "$BIN"/ollama "$BIN"/python-good "$oldbin/"
cat >"$oldbin/ccb" <<'EOF'
#!/bin/sh
echo 'ccb (Claude Code Bridge) v8.4.2 test'
EOF
chmod +x "$oldbin"/*
run env PATH="$oldbin:$PATH" CCB_PYTHON="$oldbin/python-good" "$INSTALL" "$WORK/ccb-old" --name OldCCB --profile web --claude-ollama-cloud --dry-run
[ "$status" -ne 0 ] || fail 'CCB 8.4.2 accepted'
assert_contains "$output" '8.4.3+'

if [ "${CCB_TEMPLATE_RUN_CLOUD_TESTS:-0}" = 1 ]; then
  for model in glm-5.2:cloud qwen3.5:397b-cloud gemma4:31b-cloud kimi-k2.7-code:cloud deepseek-v4-pro:cloud; do
    ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_BASE_URL=http://localhost:11434 claude --model "$model" -p 'Reply only: CCB template model check.' >/dev/null
  done
  echo '[OK] Optional Cloud model tests passed (5 models)'
else
  echo '[SKIP] Optional Cloud model tests (set CCB_TEMPLATE_RUN_CLOUD_TESTS=1 to run)'
fi

echo '[OK] V2 install tests passed (16 scenarios)'
