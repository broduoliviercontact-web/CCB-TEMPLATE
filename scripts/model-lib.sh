#!/bin/sh

model_name_is_safe() { case "$1" in ''|*[!A-Za-z0-9._:/-]*) return 1;; *) return 0;; esac; }
model_mode_is_valid() { case "$1" in local|local-proxy|cloud-api) return 0;; *) return 1;; esac; }
model_is_cloud() { case "$1" in *:cloud|*-cloud) return 0;; *) return 1;; esac; }
model_recommendations() {
  cat <<'EOF'
balanced-cloud: glm-5.2:cloud, qwen3.5:cloud, gemma4:cloud, kimi-k2.7-code:cloud, deepseek-v4-pro:cloud
coding-cloud: qwen3.5:cloud, qwen3-coder:480b-cloud, gpt-oss:120b-cloud
local-lightweight: choose installed local models with ./scripts/ccb.sh models list
EOF
}
models_conf_validate() {
  file=$1
  [ -f "$file" ] || return 1
  provider= mode= host= manager= graph= graphiste= developer= reviewer=
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; CCB_MODEL_PROVIDER=*) provider=${line#*=};; CCB_OLLAMA_MODE=*) mode=${line#*=};; CCB_OLLAMA_HOST=*) host=${line#*=};; CCB_MODEL_MANAGER=*) manager=${line#*=};; CCB_MODEL_GRAPH=*) graph=${line#*=};; CCB_MODEL_GRAPHISTE=*) graphiste=${line#*=};; CCB_MODEL_DEVELOPER=*) developer=${line#*=};; CCB_MODEL_REVIEWER=*) reviewer=${line#*=};; CCB_MODEL_FALLBACK=*) :;; *) return 1;; esac
  done <"$file"
  [ "$provider" = ollama ] && model_mode_is_valid "$mode" && [ -n "$host" ] || return 1
  for model in "$manager" "$graph" "$graphiste" "$developer" "$reviewer"; do model_name_is_safe "$model" || return 1; done
}
