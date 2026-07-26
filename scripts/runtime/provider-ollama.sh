#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/runtime-lib.sh"
cmd=${1:-}; shift 2>/dev/null || :
available() { command -v ollama >/dev/null 2>&1 || { echo 'Ollama is unavailable' >&2; return 3; }; ollama --version >/dev/null 2>&1 || :; }
listed() { ollama list 2>/dev/null | awk 'NR>1 {print $1}' | while IFS= read -r model; do runtime_model_is_safe "$model" && printf '%s\n' "$model"; done; }
case "$cmd" in
  available) available ;;
  list-models) available && listed ;;
  check)
    model=${1:-}; mode=${2:-}; runtime_model_is_safe "$model" || exit 2; available || exit $?
    case "$mode" in local) listed | grep -Fqx "$model" || { echo "Model is not installed locally: $model" >&2; exit 1; };; local-proxy) listed | grep -Fqx "$model" || runtime_warn "Model not listed locally: $model";; cloud-api) echo 'Direct cloud-api runtime is not implemented in V1.5.0.' >&2; exit 4;; *) exit 2;; esac ;;
  command) model=${1:-}; mode=${2:-}; runtime_model_is_safe "$model" || exit 2; [ "$mode" = cloud-api ] && exit 4; printf 'ollama run %s\n' "$model" ;;
  run)
    model=${1:-}; mode=${2:-}; file=${3:-}; interactive=${4:-0}; runtime_model_is_safe "$model" || exit 2; "$0" check "$model" "$mode" || exit $?
    if [ "$interactive" = 1 ]; then exec ollama run "$model"; fi
    [ -f "$file" ] && [ ! -L "$file" ] || exit 2
    prompt=$(cat "$file"); ollama run "$model" "$prompt" ;;
  *) echo 'usage: provider-ollama.sh available|check|command|list-models|run' >&2; exit 2;;
esac
