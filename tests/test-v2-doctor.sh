#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-v2-doctor.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { printf '%s\n' "$1" | grep -Fq -- "$2" || fail "missing $2"; }
assert_not_exists() { [ ! -e "$1" ] || fail "unexpected file: $1"; }
run() {
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
  return 0
}

PYTHON_FOR_TESTS=$(command -v python3 2>/dev/null || true)
[ -n "$PYTHON_FOR_TESTS" ] || fail 'python3 is required for doctor tests'

UTIL_BIN="$WORK/util-bin"
BIN="$WORK/bin"
FULL_BIN="$WORK/full-bin"
mkdir -p "$UTIL_BIN" "$BIN" "$FULL_BIN"
for tool in dirname basename sed awk grep wc uname cat; do
  tool_path=$(command -v "$tool" 2>/dev/null || true)
  [ -n "$tool_path" ] || fail "missing test utility: $tool"
  ln -s "$tool_path" "$UTIL_BIN/$tool"
done

cat >"$BIN/python-good" <<EOF
#!/bin/sh
case "\${2:-}" in
  *sys.version_info*) echo 3.12; exit 0 ;;
  *importlib.util*) exit 0 ;;
  *) exec "$PYTHON_FOR_TESTS" "\$@" ;;
esac
EOF
chmod +x "$BIN/python-good"

run env PATH="$UTIL_BIN" CCB_PYTHON="$BIN/python-good" "$ROOT/ccb-template" doctor
[ "$status" -eq 1 ] || fail "doctor without mandatory tools should fail: $output"
assert_contains "$output" '[OK] platform:'
assert_contains "$output" '[OK] Python 3.10+'
assert_contains "$output" '[MISSING] tmux is required'
assert_contains "$output" '[MISSING] git is required'
assert_contains "$output" '[MISSING] official ccb is required'
assert_contains "$output" '[MISSING] Claude Code CLI is required'
assert_contains "$output" '[MISSING] Ollama is required'

cat >"$FULL_BIN/tmux" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$FULL_BIN/git" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$FULL_BIN/ccb" <<'EOF'
#!/bin/sh
case "${1:-}" in
  --version) echo 'ccb (Claude Code Bridge) v8.4.3 test' ;;
  *) exit 91 ;;
esac
EOF
cat >"$FULL_BIN/claude" <<'EOF'
#!/bin/sh
exit 77
EOF
cat >"$FULL_BIN/ollama" <<'EOF'
#!/bin/sh
case "${1:-}" in
  list) cat <<'MODELS'
NAME ID SIZE MODIFIED
fallback:cloud a 1 now
MODELS
  ;;
  *) exit 88 ;;
esac
EOF
chmod +x "$FULL_BIN"/*

run env PATH="$FULL_BIN:$UTIL_BIN" CCB_PYTHON="$BIN/python-good" "$ROOT/ccb-template" doctor --full
[ "$status" -eq 0 ] || fail "doctor --full should pass with optional warnings only: $output"
assert_contains "$output" '[OK] Ollama reachable with 1 Cloud model(s)'
assert_contains "$output" '[WARNING] optional RTK is unavailable'
assert_contains "$output" '[WARNING] optional npx is unavailable'
assert_contains "$output" '[OK] optional local monitoring proxy asset is present'

OLD_BIN="$WORK/old-bin"
mkdir "$OLD_BIN"
cp "$FULL_BIN"/tmux "$FULL_BIN"/git "$FULL_BIN"/claude "$FULL_BIN"/ollama "$OLD_BIN/"
cat >"$OLD_BIN/ccb" <<'EOF'
#!/bin/sh
echo 'ccb (Claude Code Bridge) v8.4.2 test'
EOF
chmod +x "$OLD_BIN"/*
run env PATH="$OLD_BIN:$UTIL_BIN" CCB_PYTHON="$BIN/python-good" "$ROOT/ccb-template" doctor
[ "$status" -eq 1 ] || fail "doctor should fail for old CCB: $output"
assert_contains "$output" '[MISSING] official ccb 8.4.3+ is required'

OPTIONAL_BIN="$WORK/optional-bin"
mkdir "$OPTIONAL_BIN"
cp "$FULL_BIN"/* "$OPTIONAL_BIN/"
cat >"$OPTIONAL_BIN/rtk" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$WORK/rtk.calls"
exit 94
EOF
cat >"$OPTIONAL_BIN/npx" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$WORK/npx.calls"
exit 95
EOF
cat >"$OPTIONAL_BIN/npm" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$WORK/npm.calls"
case "\$*" in
  'view --offline tilth@0.9.0 version') echo 0.9.0; exit 0 ;;
  *) exit 96 ;;
esac
EOF
chmod +x "$OPTIONAL_BIN"/*

run env PATH="$OPTIONAL_BIN:$UTIL_BIN" CCB_PYTHON="$BIN/python-good" "$ROOT/ccb-template" doctor --full
[ "$status" -eq 0 ] || fail "doctor --full with optional tools failed: $output"
assert_contains "$output" '[OK] optional RTK:'
assert_contains "$output" '[OK] optional npx:'
assert_contains "$output" '[OK] optional Tilth package tilth@0.9.0 is available in the local npm cache'
assert_not_exists "$WORK/rtk.calls"
assert_not_exists "$WORK/npx.calls"
[ "$(cat "$WORK/npm.calls")" = 'view --offline tilth@0.9.0 version' ] || fail 'doctor --full did not use the read-only Tilth availability check'

run "$ROOT/ccb-template" doctor --unexpected
[ "$status" -eq 2 ] || fail 'unknown doctor argument should exit 2'
assert_contains "$output" 'unknown doctor argument'

echo '[OK] V2 doctor tests passed (6 checks)'
