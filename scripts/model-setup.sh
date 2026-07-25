#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/model-lib.sh"
target=${1:-.}
mode=${2:-local-proxy}
[ -d "$target" ] || { echo "error: target directory does not exist" >&2; exit 1; }
target=$(CDPATH= cd "$target" && pwd)
model_mode_is_valid "$mode" || { echo "error: invalid Ollama mode" >&2; exit 2; }
[ -d "$target/.ccb" ] || { echo "error: CCB is not installed" >&2; exit 1; }
if [ "$mode" = cloud-api ] && [ -z "${OLLAMA_API_KEY:-}" ]; then echo "[WARN] OLLAMA_API_KEY is not set; it was not requested or stored." >&2; fi
mkdir -p "$target/.ccb"
cat >"$target/.ccb/models.conf" <<EOF
# CCB agent model configuration (non-secret).
# Never store API keys or authentication tokens in this file.
CCB_MODEL_PROVIDER=ollama
CCB_OLLAMA_MODE=$mode
CCB_OLLAMA_HOST=$( [ "$mode" = cloud-api ] && printf https://ollama.com/api || printf http://localhost:11434 )
CCB_MODEL_MANAGER=glm-5.2:cloud
CCB_MODEL_GRAPH=qwen3.5:cloud
CCB_MODEL_GRAPHISTE=gemma4:cloud
CCB_MODEL_DEVELOPER=kimi-k2.7-code:cloud
CCB_MODEL_REVIEWER=deepseek-v4-pro:cloud
CCB_MODEL_FALLBACK=gpt-oss:120b-cloud
EOF
echo "updated: $target/.ccb/models.conf"
