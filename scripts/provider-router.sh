#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
action=${1:-}; provider=${2:-}; shift 2 2>/dev/null || :
case "$provider" in
  ollama)
    case "$action" in check|command) model=${1:-}; target=${2:-}; mode=${3:-}; exec "$SCRIPT_DIR/runtime/provider-ollama.sh" "$action" "$model" "$mode";; run) model=${1:-}; target=${2:-}; mode=${3:-}; file=${4:-}; interactive=${5:-}; exec "$SCRIPT_DIR/runtime/provider-ollama.sh" run "$model" "$mode" "$file" "$interactive";; *) exec "$SCRIPT_DIR/runtime/provider-ollama.sh" "$action";; esac ;;
  *) echo "Unsupported runtime provider: $provider" >&2; exit 2;;
esac
