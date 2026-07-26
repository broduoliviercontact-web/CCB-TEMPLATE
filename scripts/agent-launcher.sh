#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
RESOLVE="$SCRIPT_DIR/model-resolve.sh"
ROUTER="$SCRIPT_DIR/provider-router.sh"
role=${1:-}; shift 2>/dev/null || :
case "$role" in manager|graph|graphiste|developer|reviewer) ;; *) echo 'usage: agent-launcher.sh AGENT [TARGET] [OPTIONS]' >&2; exit 2;; esac
target=.
case "${1:-}" in ''|--*) ;; *) target=$1; shift;; esac
[ -d "$target" ] && [ ! -L "$target" ] || { echo 'error: invalid target' >&2; exit 2; }
target=$(CDPATH= cd "$target" && pwd)
prompt= prompt_file= stdin_mode=0 dry=0 context=1 show=0
while [ "$#" -gt 0 ]; do
  case "$1" in --prompt) shift; prompt=${1:-};; --prompt-file) shift; prompt_file=${1:-};; --stdin) stdin_mode=1;; --dry-run) dry=1;; --no-context) context=0;; --with-context) context=1;; --show-prompt) show=1;; *) echo "error: unknown option: $1" >&2; exit 2;; esac
  shift
done
sources=0; [ -n "$prompt" ] && sources=$((sources+1)); [ -n "$prompt_file" ] && sources=$((sources+1)); [ "$stdin_mode" -eq 1 ] && sources=$((sources+1)); [ "$sources" -le 1 ] || { echo 'error: select one prompt source' >&2; exit 2; }
if [ -n "$prompt_file" ]; then [ -f "$prompt_file" ] && [ ! -L "$prompt_file" ] || { echo 'error: unsafe prompt file' >&2; exit 2; }; prompt=$(cat "$prompt_file"); fi
if [ "$stdin_mode" -eq 1 ]; then prompt=$(cat); fi
if [ -z "$prompt" ] && [ ! -t 0 ]; then echo 'error: provide --prompt, --prompt-file, or --stdin' >&2; exit 2; fi
model=$($RESOLVE "$role" "$target") || exit $?
mode=$(awk -F= '$1=="CCB_OLLAMA_MODE" {print $2}' "$target/.ccb/models.conf")
provider=$(awk -F= '$1=="CCB_MODEL_PROVIDER" {print $2}' "$target/.ccb/models.conf")
provider=${provider:-ollama}
system="$target/.ccb/agent-runtime/$role.system.md"; [ -f "$system" ] || system="$SCRIPT_DIR/../agent-runtime/$role.system.md"
final="[CCB ROLE]\n$role\n[PROJECT]\n$target\n[SYSTEM]\n$(cat "$system")\n[USER MISSION]\n$prompt"
if [ "$context" -eq 1 ] && [ -f "$target/.ccb/AGENT_POLICY.md" ]; then final="$final\n[POLICY]\n$(head -c 12000 "$target/.ccb/AGENT_POLICY.md")"; fi
if [ "$dry" -eq 1 ]; then printf 'Agent: %s\nModel: %s\nProvider: %s\nMode: %s\nTarget: %s\nRuntime: provider-router run ...\n' "$role" "$model" "$provider" "$mode" "$target"; [ "$show" -eq 1 ] && printf '%b\n' "$final"; exit 0; fi
tmp=$(mktemp "${TMPDIR:-/tmp}/ccb-agent-prompt.XXXXXX") || exit 1; trap 'rm -f "$tmp"' EXIT HUP INT TERM
printf '%b' "$final" >"$tmp"
if [ -z "$prompt" ] && [ -t 0 ]; then "$ROUTER" run "$provider" "$model" "$target" "$mode" "$tmp" 1; else "$ROUTER" run "$provider" "$model" "$target" "$mode" "$tmp" 0; fi
status=$?; rm -f "$tmp"; trap - EXIT HUP INT TERM; exit "$status"
