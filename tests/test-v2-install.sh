#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
INSTALL="$ROOT/install.sh"
TMP_BASE=${TMPDIR:-/tmp}
TMP_BASE=${TMP_BASE%/}
[ -n "$TMP_BASE" ] || TMP_BASE=/
if [ "$TMP_BASE" = / ]; then
  WORK=$(mktemp -d '/ccb-v2-install.XXXXXX')
else
  WORK=$(mktemp -d "$TMP_BASE/ccb-v2-install.XXXXXX")
fi
listener_pid=
trap 'if [ -n "${listener_pid:-}" ]; then kill "$listener_pid" 2>/dev/null || :; fi; rm -rf "$WORK"' EXIT HUP INT TERM
BIN="$WORK/bin"
mkdir -p "$BIN"
PYTHON_FOR_TESTS=$(command -v python3 2>/dev/null || true)
[ -n "$PYTHON_FOR_TESTS" ] || { echo 'FAIL: python3 is required to test JSON merging' >&2; exit 1; }

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
kimi-k2.7-code:cloud c 1 now
kimi-k2.6:cloud d 1 now
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
cat >"$BIN/python-good" <<EOF
#!/bin/sh
case "\${2:-}" in
  *sys.version_info*) echo 3.12; exit 0 ;;
  *importlib.util*) exit 0 ;;
  *) exec "$PYTHON_FOR_TESTS" "\$@" ;;
esac
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

TOKEN_BIN="$WORK/token-bin"
RTK_ONLY_BIN="$WORK/rtk-only-bin"
mkdir -p "$TOKEN_BIN" "$RTK_ONLY_BIN"
cat >"$TOKEN_BIN/rtk" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$WORK/rtk.calls"
exit 94
EOF
cat >"$TOKEN_BIN/npx" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$WORK/npx.calls"
exit 95
EOF
cp "$TOKEN_BIN/rtk" "$RTK_ONLY_BIN/rtk"
chmod +x "$TOKEN_BIN"/* "$RTK_ONLY_BIN"/*

ENV="PATH=$BIN:$PATH CCB_PYTHON=$BIN/python-good"

help=$($INSTALL --help)
assert_contains "$help" '--claude-ollama-cloud'
assert_contains "$help" '--token-optimization'
assert_contains "$help" '--no-token-optimization'
assert_contains "$help" 'web is the only preset currently supported'
if rg -n 'profiles/' "$ROOT/install.sh" "$ROOT/scripts/v2"; then fail 'V2 bootstrap reads a removed profiles directory'; fi

dry="$WORK/dry"
run env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$dry" --name Dry --profile web --claude-ollama-cloud --no-token-optimization --dry-run
[ "$status" -eq 0 ] || fail "dry-run failed: $output"
[ ! -e "$dry" ] || fail 'dry-run wrote the target'
assert_contains "$output" 'DRY RUN — no files were modified.'

default_missing_rtk="$WORK/default-missing-rtk"
run env PATH="$BIN:/usr/bin:/bin" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$default_missing_rtk" --name DefaultMissingRTK --profile web --claude-ollama-cloud --dry-run
[ "$status" -ne 0 ] || fail 'default installation accepted missing RTK'
assert_contains "$output" 'RTK is required with --token-optimization'
[ ! -e "$default_missing_rtk" ] || fail 'default installation without RTK wrote the target'

opt_out_without_tools="$WORK/opt-out-without-token-tools"
run env PATH="$BIN:/usr/bin:/bin" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$opt_out_without_tools" --name OptOutWithoutTools --profile web --claude-ollama-cloud --no-token-optimization --dry-run
[ "$status" -eq 0 ] || fail "opt-out installation was blocked without RTK/npx: $output"
[ ! -e "$opt_out_without_tools" ] || fail 'opt-out dry-run without RTK/npx wrote the target'

token_missing_rtk="$WORK/token-missing-rtk"
run env PATH="$BIN:/usr/bin:/bin" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$token_missing_rtk" --name TokenMissingRTK --profile web --claude-ollama-cloud --token-optimization --dry-run
[ "$status" -ne 0 ] || fail 'missing RTK was accepted with --token-optimization'
assert_contains "$output" 'RTK is required with --token-optimization'
assert_contains "$output" 'brew install rtk-ai/tap/rtk'
assert_contains "$output" 'rtk init -g'
[ ! -e "$token_missing_rtk" ] || fail 'missing RTK wrote the target'

token_missing_npx="$WORK/token-missing-npx"
run env PATH="$RTK_ONLY_BIN:$BIN:/usr/bin:/bin" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$token_missing_npx" --name TokenMissingNPX --profile web --claude-ollama-cloud --token-optimization --dry-run
[ "$status" -ne 0 ] || fail 'missing npx was accepted with --token-optimization'
assert_contains "$output" 'npx is required with --token-optimization'
[ ! -e "$token_missing_npx" ] || fail 'missing npx wrote the target'

token_dry="$WORK/token-dry"
run env PATH="$TOKEN_BIN:$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$token_dry" --name TokenDry --profile web --claude-ollama-cloud --token-optimization --dry-run
[ "$status" -eq 0 ] || fail "token-optimization dry-run failed: $output"
[ ! -e "$token_dry" ] || fail 'token-optimization dry-run wrote the target'
assert_contains "$output" '[PLAN] create Tilth MCP configuration:'
assert_contains "$output" "$token_dry/.claude/rules/token-optimization.md"

invalid_profile="$WORK/invalid-profile"
run env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$invalid_profile" --name InvalidProfile --profile python --claude-ollama-cloud --dry-run
[ "$status" -ne 0 ] || fail 'unsupported profile succeeded'
assert_contains "$output" '--profile supports only the built-in web preset'
[ ! -e "$invalid_profile" ] || fail 'unsupported profile wrote the target'

run sh -c "printf '' | env PATH='$BIN:$PATH' CCB_PYTHON='$BIN/python-good' '$INSTALL' '$WORK/non-tty' --name NonTTY --profile web --claude-ollama-cloud"
[ "$status" -ne 0 ] || fail 'non-TTY install without --yes succeeded'
[ ! -e "$WORK/non-tty" ] || fail 'non-TTY refusal wrote files'

project="$WORK/project"
run env PATH="$TOKEN_BIN:$BIN:$PATH" CCB_PYTHON="$BIN/python-good" ANTHROPIC_AUTH_TOKEN='CCB_TEMPLATE_SIMULATED_TOKEN_DO_NOT_PERSIST' "$INSTALL" "$project" --name 'Web Project' --profile web --claude-ollama-cloud --yes
[ "$status" -eq 0 ] || fail "installation failed: $output"
cmp -s "$project/.ccb/ccb.config" "$ROOT/tests/fixtures/ccb.config.expected" || fail 'configuration is not deterministic expected output'
for agent in manager graph developer reviewer; do
  grep -Fq "[agents.$agent]" "$project/.ccb/ccb.config" || fail "missing agent $agent"
  grep -Fq "[agents.$agent.provider_profile]" "$project/.ccb/ccb.config" || fail "missing provider profile $agent"
  grep -A2 -F "[agents.$agent.provider_profile]" "$project/.ccb/ccb.config" | grep -Fqx 'inherit_api = false' || fail "missing inherit_api $agent"
  grep -A2 -F "[agents.$agent.provider_profile]" "$project/.ccb/ccb.config" | grep -Fqx 'inherit_auth = false' || fail "missing inherit_auth $agent"
  [ -f "$project/.ccb/agents/$agent/memory.md" ] || fail "missing memory $agent"
  [ -f "$project/.ccb/agents/$agent/CLAUDE.md" ] || fail "missing role brief $agent"
done
[ -f "$project/CLAUDE.md" ] || fail 'missing shared project CLAUDE.md'
for skill in ccb-manager-planning ccb-graph-analysis ccb-developer-delivery ccb-reviewer-audit; do
  [ -f "$project/.claude/skills/$skill/SKILL.md" ] || fail "missing default skill $skill"
done
grep -Fqx 'ANTHROPIC_AUTH_TOKEN = "ollama"' "$project/.ccb/ccb.config" || fail 'missing literal Ollama authentication marker'
grep -Fqx 'ANTHROPIC_BASE_URL = "http://localhost:11434"' "$project/.ccb/ccb.config" || fail 'missing Ollama base URL'
retired_prefix=qwen3-coder
retired_model=$retired_prefix:480b-cloud
if rg -n "$retired_model|sk-ant-|Bearer [A-Za-z0-9]" "$ROOT/install.sh" "$ROOT/scripts/v2" "$ROOT/assets" "$project/.ccb" >/dev/null; then fail 'new V2 files contain a retired model or sensitive token'; fi
grep -Fxv -- '--version' "$WORK/ccb.calls" >/dev/null && fail 'installer executed ccb beyond --version' || :
[ ! -e "$WORK/claude.calls" ] || fail 'installer executed Claude Code'
[ -f "$project/.mcp.json" ] || fail 'default installation did not create a Tilth MCP configuration'
[ -f "$project/.claude/rules/token-optimization.md" ] || fail 'default installation did not create Claude token-optimization files'

custom_models="$WORK/custom-models"
run env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$custom_models" --name CustomModels --profile web --claude-ollama-cloud --no-token-optimization --manager-model kimi-k2.6:cloud --graph-model glm-5.2:cloud --developer-model qwen3.5:397b-cloud --reviewer-model kimi-k2.7-code:cloud --yes
[ "$status" -eq 0 ] || fail "custom model installation failed: $output"
grep -A1 -F '[agents.manager]' "$custom_models/.ccb/ccb.config" | grep -Fqx 'model = "kimi-k2.6:cloud"' || fail 'manager custom model was not rendered'
grep -A1 -F '[agents.graph]' "$custom_models/.ccb/ccb.config" | grep -Fqx 'model = "glm-5.2:cloud"' || fail 'graph custom model was not rendered'
grep -A1 -F '[agents.developer]' "$custom_models/.ccb/ccb.config" | grep -Fqx 'model = "qwen3.5:397b-cloud"' || fail 'developer custom model was not rendered'
grep -A1 -F '[agents.reviewer]' "$custom_models/.ccb/ccb.config" | grep -Fqx 'model = "kimi-k2.7-code:cloud"' || fail 'reviewer custom model was not rendered'

cli_project="$WORK/cli-project"
run sh -c "printf '%s\\n' 'CLI Project' 1 2 3 4 n n y n n | env PATH='$BIN:$PATH' CCB_PYTHON='$BIN/python-good' '$ROOT/ccb-template' init '$cli_project'"
[ "$status" -eq 0 ] || fail "interactive CLI failed: $output"
[ -d "$cli_project/.git" ] || fail 'interactive CLI did not initialise Git'
grep -A1 -F '[agents.manager]' "$cli_project/.ccb/ccb.config" | grep -Fqx 'model = "glm-5.2:cloud"' || fail 'interactive CLI did not select manager model'
grep -A1 -F '[agents.reviewer]' "$cli_project/.ccb/ccb.config" | grep -Fqx 'model = "kimi-k2.6:cloud"' || fail 'interactive CLI did not select reviewer model'
[ ! -e "$cli_project/.mcp.json" ] || fail 'interactive CLI ignored token-optimization opt-out'
assert_contains "$output" 'CCB was not started.'

monitored_project="$WORK/monitored-project"
"$PYTHON_FOR_TESTS" -c 'import socket, time; sock = socket.socket(); sock.bind(("127.0.0.1", 11435)); sock.listen(); time.sleep(30)' >/dev/null 2>&1 &
listener_pid=$!
sleep 0.1
run env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$monitored_project" --name MonitoredProject --profile web --claude-ollama-cloud --no-token-optimization --token-monitoring --yes
[ "$status" -eq 0 ] || fail "token monitoring installation failed: $output"
[ -f "$monitored_project/.ccb/token-proxy.py" ] || fail 'token monitoring proxy was not installed'
[ "$(cat "$monitored_project/.ccb/token-monitor-python")" = "$BIN/python-good" ] || fail 'token monitoring did not retain the validated Python interpreter'
[ -f "$monitored_project/.ccb/token-monitor/pricing.json" ] || fail 'token monitoring pricing configuration was not installed'
monitor_port=$(cat "$monitored_project/.ccb/token-monitor/port")
[ "$monitor_port" != 11435 ] || fail 'token monitoring reused occupied port 11435'
[ "$(cat "$monitored_project/.ccb-template/token-monitor/port")" = "$monitor_port" ] || fail 'token monitor durable port backup differs'
for agent in manager graph developer reviewer; do
  grep -Fqx "ANTHROPIC_BASE_URL = \"http://127.0.0.1:$monitor_port/$agent\"" "$monitored_project/.ccb/ccb.config" || fail "$agent token monitoring endpoint was not rendered"
done
if rg -n 'unset .*;;' "$monitored_project/.ccb"; then fail 'generated CCB files contain malformed unset syntax'; fi
[ -f "$monitored_project/.ccb-template/token-monitor/token-proxy.py" ] || fail 'token monitor durable proxy backup was not installed'
[ -f "$monitored_project/.ccb-template/token-monitor/pricing.json" ] || fail 'token monitor durable pricing backup was not installed'
printf '%s\n' '{"models":{"kimi-k2.7-code:cloud":{"input_per_million_usd":2,"output_per_million_usd":8}}}' >"$monitored_project/.ccb/token-monitor/pricing.json"
printf '%s\n' '{"timestamp":"2026-07-29T22:00:00+00:00","agent":"manager","model":"kimi-k2.7-code:cloud","input_tokens":1000000,"output_tokens":500000,"duration_ms":100}' >"$monitored_project/.ccb/token-monitor/usage.jsonl"
run "$ROOT/ccb-template" monitor "$monitored_project"
[ "$status" -eq 0 ] || fail "token usage dashboard failed: $output"
assert_contains "$output" 'Estimated cost'
assert_contains "$output" '$6.0000'
run "$ROOT/ccb-template" monitor price "$monitored_project"
[ "$status" -eq 0 ] || fail "pricing command failed: $output"
assert_contains "$output" 'input_per_million_usd'

run sh -c "printf '%s\\n' 'Implement the login screen.' '.' | '$ROOT/ccb-template' brief '$cli_project'"
[ "$status" -eq 0 ] || fail "brief command failed: $output"
brief_file=$(find "$cli_project/.ccb/briefs" -name 'brief-*.md' -type f -print -quit)
[ -n "$brief_file" ] || fail 'brief command did not create a brief file'
grep -Fqx 'Implement the login screen.' "$brief_file" || fail 'brief command did not preserve brief content'

run "$ROOT/ccb-template" manager-prompt "$cli_project" "$(basename "$brief_file")"
[ "$status" -eq 0 ] || fail "manager-prompt command failed: $output"
assert_contains "$output" "Read .ccb/briefs/$(basename "$brief_file")"
assert_contains "$output" 'delegate architecture'

token_project="$WORK/token project"
run env PATH="$TOKEN_BIN:$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$token_project" --name 'Token Project' --profile web --claude-ollama-cloud --token-optimization --yes
[ "$status" -eq 0 ] || fail "token-optimization installation failed: $output"
[ -f "$token_project/.claude/rules/token-optimization.md" ] || fail 'token-optimization rule was not installed'
[ -f "$token_project/.mcp.json" ] || fail 'Tilth MCP configuration was not installed'
grep -Fqx -- '- Keep responses concise by default: do not restate the request or add a preamble.' "$token_project/.claude/rules/token-optimization.md" || fail 'token-optimization rule is missing concise-response guidance'
grep -Fqx -- '- Prefer targeted changes to broad rewrites; provide detail when the user asks for it or validation evidence requires it.' "$token_project/.claude/rules/token-optimization.md" || fail 'token-optimization rule is missing targeted-change guidance'
"$PYTHON_FOR_TESTS" -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    document = json.load(source)
assert document == {"mcpServers": {"tilth": {"command": "npx", "args": ["-y", "tilth@0.9.0", "--mcp"]}}}
' "$token_project/.mcp.json" || fail 'Tilth MCP configuration is not deterministic'
[ ! -e "$WORK/rtk.calls" ] || fail 'installer executed RTK'
[ ! -e "$WORK/npx.calls" ] || fail 'installer executed npx or Tilth'

merged_mcp="$WORK/merged-mcp"
mkdir "$merged_mcp"
cat >"$merged_mcp/.mcp.json" <<'EOF'
{
  "mcpServers": {
    "other": {
      "command": "other-server",
      "args": ["--safe"]
    },
    "tilth": {
      "command": "old-tilth"
    }
  },
  "metadata": {
    "keep": true
  }
}
EOF
env PATH="$TOKEN_BIN:$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$merged_mcp" --name MergedMCP --profile web --claude-ollama-cloud --token-optimization --yes >/dev/null
"$PYTHON_FOR_TESTS" -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    document = json.load(source)
assert document["mcpServers"]["other"] == {"command": "other-server", "args": ["--safe"]}
assert document["mcpServers"]["tilth"] == {"command": "npx", "args": ["-y", "tilth@0.9.0", "--mcp"]}
assert document["metadata"] == {"keep": True}
' "$merged_mcp/.mcp.json" || fail 'MCP merge did not preserve other servers or deterministically update Tilth'

invalid_mcp="$WORK/invalid-mcp"
mkdir "$invalid_mcp"
printf '{ invalid JSON\n' >"$invalid_mcp/.mcp.json"
invalid_before=$(cat "$invalid_mcp/.mcp.json")
run env PATH="$TOKEN_BIN:$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$invalid_mcp" --name InvalidMCP --profile web --claude-ollama-cloud --token-optimization --yes
[ "$status" -ne 0 ] || fail 'invalid MCP JSON was accepted'
assert_contains "$output" 'refusing invalid or incompatible MCP configuration'
[ "$(cat "$invalid_mcp/.mcp.json")" = "$invalid_before" ] || fail 'invalid MCP JSON was altered'
[ ! -e "$invalid_mcp/.ccb/ccb.config" ] || fail 'invalid MCP JSON wrote CCB configuration before refusal'

incompatible_mcp="$WORK/incompatible-mcp"
mkdir "$incompatible_mcp"
printf '{"mcpServers": []}\n' >"$incompatible_mcp/.mcp.json"
incompatible_before=$(cat "$incompatible_mcp/.mcp.json")
run env PATH="$TOKEN_BIN:$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$incompatible_mcp" --name IncompatibleMCP --profile web --claude-ollama-cloud --token-optimization --yes
[ "$status" -ne 0 ] || fail 'incompatible MCP structure was accepted'
[ "$(cat "$incompatible_mcp/.mcp.json")" = "$incompatible_before" ] || fail 'incompatible MCP JSON was altered'

linked_mcp="$WORK/linked-mcp"
mkdir "$linked_mcp"
printf '{"mcpServers": {}}\n' >"$WORK/mcp-outside.json"
ln -s "$WORK/mcp-outside.json" "$linked_mcp/.mcp.json"
linked_before=$(cat "$WORK/mcp-outside.json")
run env PATH="$TOKEN_BIN:$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$linked_mcp" --name LinkedMCP --profile web --claude-ollama-cloud --token-optimization --yes
[ "$status" -ne 0 ] || fail 'symbolic MCP configuration was accepted'
assert_contains "$output" 'refusing symbolic link:'
[ "$(cat "$WORK/mcp-outside.json")" = "$linked_before" ] || fail 'symbolic MCP target was altered'

preserve_rule="$WORK/preserve-rule"
mkdir -p "$preserve_rule/.claude/rules"
printf 'user token rule\n' >"$preserve_rule/.claude/rules/token-optimization.md"
printf 'user CLAUDE memory\n' >"$preserve_rule/CLAUDE.md"
run env PATH="$TOKEN_BIN:$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$preserve_rule" --name PreserveRule --profile web --claude-ollama-cloud --token-optimization --yes
[ "$status" -eq 0 ] || fail "existing rule installation failed: $output"
[ "$(cat "$preserve_rule/.claude/rules/token-optimization.md")" = 'user token rule' ] || fail 'existing token-optimization rule was overwritten'
[ "$(cat "$preserve_rule/CLAUDE.md")" = 'user CLAUDE memory' ] || fail 'CLAUDE.md was changed'
assert_contains "$output" "preserved: $preserve_rule/.claude/rules/token-optimization.md"
grep -Fxv -- '--version' "$WORK/ccb.calls" >/dev/null && fail 'token-optimization executed ccb beyond --version' || :
[ ! -e "$WORK/claude.calls" ] || fail 'token-optimization executed Claude Code'
[ ! -e "$WORK/rtk.calls" ] || fail 'token-optimization executed RTK'
[ ! -e "$WORK/npx.calls" ] || fail 'token-optimization executed npx or Tilth'

second="$WORK/second"
env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$second" --name 'Other name' --profile web --claude-ollama-cloud --no-token-optimization --yes >/dev/null
cmp -s "$project/.ccb/ccb.config" "$second/.ccb/ccb.config" || fail 'configuration changed with project name'

preserve="$WORK/preserve"
mkdir -p "$preserve/.ccb"
printf 'custom memory\n' >"$preserve/.ccb/ccb_memory.md"
env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$preserve" --name Preserve --profile web --claude-ollama-cloud --no-token-optimization --yes >/dev/null
[ "$(cat "$preserve/.ccb/ccb_memory.md")" = 'custom memory' ] || fail 'existing memory was overwritten'

conflict="$WORK/conflict"
mkdir -p "$conflict/.ccb"
printf 'existing config\n' >"$conflict/.ccb/ccb.config"
run env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$conflict" --name Conflict --profile web --claude-ollama-cloud --no-token-optimization --yes
[ "$status" -ne 0 ] || fail 'existing ccb.config was overwritten'
[ "$(cat "$conflict/.ccb/ccb.config")" = 'existing config' ] || fail 'ccb.config changed after refusal'

linked="$WORK/linked"
mkdir "$linked"
ln -s "$WORK/elsewhere" "$linked/.ccb"
run env PATH="$BIN:$PATH" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$linked" --name Linked --profile web --claude-ollama-cloud --no-token-optimization --yes
[ "$status" -ne 0 ] || fail 'symbolic .ccb directory accepted'

python_deps="$WORK/python-deps"
mkdir "$python_deps"
cp "$BIN/python-missing-deps" "$python_deps/python3.14"
cp "$BIN/python-good" "$python_deps/python3.13"
chmod +x "$python_deps"/*
run env -u CCB_PYTHON PATH="$python_deps:$BIN:/usr/bin:/bin" "$INSTALL" "$WORK/python-deps-target" --name PythonDeps --profile web --claude-ollama-cloud --no-token-optimization --dry-run
[ "$status" -eq 0 ] || fail "missing-dependencies fallback failed: $output"
assert_contains "$output" "Python candidate rejected: $python_deps/python3.14 (missing tomllib/tomli, aiohttp, or cryptography)"
assert_contains "$output" "Python: $python_deps/python3.13 (3.12)"

python_old="$WORK/python-old-fallback"
mkdir "$python_old"
cp "$BIN/python-old" "$python_old/python3.14"
cp "$BIN/python-good" "$python_old/python3.13"
chmod +x "$python_old"/*
run env -u CCB_PYTHON PATH="$python_old:$BIN:/usr/bin:/bin" "$INSTALL" "$WORK/python-old-fallback-target" --name PythonOld --profile web --claude-ollama-cloud --no-token-optimization --dry-run
[ "$status" -eq 0 ] || fail "old-Python fallback failed: $output"
assert_contains "$output" "Python candidate rejected: $python_old/python3.14 (requires Python 3.10+, found 3.9)"
assert_contains "$output" "Python: $python_old/python3.13 (3.12)"

python_ccb="$WORK/python-ccb-fallback"
mkdir "$python_ccb"
cp "$BIN/python-good" "$python_ccb/python3.14"
chmod +x "$python_ccb/python3.14"
run env PATH="$python_ccb:$BIN:/usr/bin:/bin" CCB_PYTHON="$BIN/python-old" "$INSTALL" "$WORK/python-ccb-fallback-target" --name PythonCCB --profile web --claude-ollama-cloud --no-token-optimization --dry-run
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
run env -u CCB_PYTHON PATH="$python_none:$BIN:/usr/bin:/bin" "$INSTALL" "$WORK/python-none-target" --name PythonNone --profile web --claude-ollama-cloud --no-token-optimization --dry-run
[ "$status" -ne 0 ] || fail 'no-compatible-Python case succeeded'
assert_contains "$output" 'no compatible Python found'

python_priority="$WORK/python-priority"
mkdir "$python_priority"
cp "$BIN/python-missing-deps" "$python_priority/python3.14"
chmod +x "$python_priority/python3.14"
run env PATH="$python_priority:$BIN:/usr/bin:/bin" CCB_PYTHON="$BIN/python-good" "$INSTALL" "$WORK/python-priority-target" --name PythonPriority --profile web --claude-ollama-cloud --no-token-optimization --dry-run
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
run env PATH="$oldbin:$PATH" CCB_PYTHON="$oldbin/python-good" "$INSTALL" "$WORK/ccb-old" --name OldCCB --profile web --claude-ollama-cloud --no-token-optimization --dry-run
[ "$status" -ne 0 ] || fail 'CCB 8.4.2 accepted'
assert_contains "$output" '8.4.3+'

if [ "${CCB_TEMPLATE_RUN_CLOUD_TESTS:-0}" = 1 ]; then
  for model in glm-5.2:cloud qwen3.5:397b-cloud kimi-k2.7-code:cloud kimi-k2.6:cloud; do
    ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_BASE_URL=http://localhost:11434 claude --model "$model" -p 'Reply only: CCB template model check.' >/dev/null
  done
  echo '[OK] Optional Cloud model tests passed (4 models)'
else
  echo '[SKIP] Optional Cloud model tests (set CCB_TEMPLATE_RUN_CLOUD_TESTS=1 to run)'
fi

echo '[OK] V2 install tests passed (token-optimization coverage included)'
