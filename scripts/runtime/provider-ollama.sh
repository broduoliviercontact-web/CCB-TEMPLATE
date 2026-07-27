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
  generate-file)
    model=${1:-}; prompt_file=${2:-}; output_file=${3:-}
    runtime_model_is_safe "$model" || exit 2
    [ -f "$prompt_file" ] && [ ! -L "$prompt_file" ] && [ -n "$output_file" ] || exit 2
    case "${CCB_TEST_PROVIDER_ERROR:-}" in
      '') :;;
      timeout) [ "${CCB_TEST_MODE:-}" = 1 ] || exit 2; exit 28;;
      unavailable) [ "${CCB_TEST_MODE:-}" = 1 ] || exit 2; exit 7;;
      invalid-response) [ "${CCB_TEST_MODE:-}" = 1 ] || exit 2; exit 65;;
      empty-response) [ "${CCB_TEST_MODE:-}" = 1 ] || exit 2; : >"$output_file"; exit 0;;
      oversized-response) [ "${CCB_TEST_MODE:-}" = 1 ] || exit 2; exit 67;;
      *) exit 2;;
    esac
    if [ "${CCB_TEST_MODE:-}" = 1 ]; then
      response_file=${CCB_TEST_PROVIDER_RESPONSE_FILE:-}
      [ -f "$response_file" ] && [ ! -L "$response_file" ] || exit 65
      cp "$response_file" "$output_file" || exit 1
      exit 0
    fi
    [ -z "${CCB_TEST_PROVIDER_RESPONSE_FILE:-}" ] && [ -z "${CCB_TEST_PROVIDER_ERROR:-}" ] || exit 2
    command -v curl >/dev/null 2>&1 || exit 7
    request_file=$(mktemp "${TMPDIR:-/tmp}/ccb-ollama-request.XXXXXX") || exit 1
    raw_file=$(mktemp "${TMPDIR:-/tmp}/ccb-ollama-response.XXXXXX") || { rm -f "$request_file"; exit 1; }
    trap 'rm -f "$request_file" "$raw_file"' EXIT HUP INT TERM
    runtime_ollama_request_file "$model" "$prompt_file" "$request_file" || exit 1
    curl --silent --show-error --fail --proto '=http' --noproxy '*' --max-redirs 0 --connect-timeout 5 --max-time 120 --max-filesize 1048576 \
      -H 'Content-Type: application/json' --data-binary "@$request_file" \
      'http://127.0.0.1:11434/api/generate' -o "$raw_file" || exit $?
    runtime_ollama_extract_response "$raw_file" "$output_file" || exit 65
    ;;
  *) echo 'usage: provider-ollama.sh available|check|command|list-models|run|generate-file' >&2; exit 2;;
esac
