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
model_preset_is_safe() { case "$1" in ''|*[!a-z0-9-]*) return 1;; *) return 0;; esac; }
model_host_is_safe() {
  case "$1" in
    https://ollama.com/api) return 0;;
    http://localhost:*|http://127.0.0.1:*) port=${1##*:}; case "$port" in ''|*[!0-9]*) return 1;; *) return 0;; esac;;
    *) return 1;;
  esac
}
model_preset_parse() {
  preset_reset=1; PRESET_ID= PRESET_NAME= PRESET_DESCRIPTION= MANAGER_MODEL= GRAPH_MODEL= GRAPHISTE_MODEL= DEVELOPER_MODEL= REVIEWER_MODEL= FALLBACK_MODEL=
  file=$1; [ -s "$file" ] && [ ! -L "$file" ] || return 1
  seen=' '
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; PRESET_ID=*|PRESET_NAME=*|PRESET_DESCRIPTION=*|MANAGER_MODEL=*|GRAPH_MODEL=*|GRAPHISTE_MODEL=*|DEVELOPER_MODEL=*|REVIEWER_MODEL=*|FALLBACK_MODEL=*) key=${line%%=*}; value=${line#*=};; *) return 1;; esac
    case "$seen" in *" $key "*) return 1;; *) seen="$seen$key ";; esac
    case "$key" in PRESET_ID) PRESET_ID=$value;; PRESET_NAME) PRESET_NAME=$value;; PRESET_DESCRIPTION) PRESET_DESCRIPTION=$value;; MANAGER_MODEL) MANAGER_MODEL=$value;; GRAPH_MODEL) GRAPH_MODEL=$value;; GRAPHISTE_MODEL) GRAPHISTE_MODEL=$value;; DEVELOPER_MODEL) DEVELOPER_MODEL=$value;; REVIEWER_MODEL) REVIEWER_MODEL=$value;; FALLBACK_MODEL) FALLBACK_MODEL=$value;; esac
  done <"$file"
  model_preset_is_safe "$PRESET_ID" && [ -n "$PRESET_NAME" ] && [ -n "$PRESET_DESCRIPTION" ] || return 1
  for value in "$MANAGER_MODEL" "$GRAPH_MODEL" "$GRAPHISTE_MODEL" "$DEVELOPER_MODEL" "$REVIEWER_MODEL" "$FALLBACK_MODEL"; do [ -z "$value" ] || model_name_is_safe "$value" || return 1; done
}
models_conf_parse() {
  file=$1
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  MODEL_CONF_FORMAT= MODEL_CONF_PROVIDER= MODEL_CONF_MODE= MODEL_CONF_HOST= MODEL_CONF_PRESET=
  MODEL_CONF_DEFAULT= MODEL_CONF_PLANNER= MODEL_CONF_CODER= MODEL_CONF_MANAGER=
  MODEL_CONF_GRAPH= MODEL_CONF_GRAPHISTE= MODEL_CONF_DEVELOPER= MODEL_CONF_REVIEWER= MODEL_CONF_FALLBACK=
  seen=' '
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue;;
      CCB_MODEL_PROVIDER=*|CCB_OLLAMA_MODE=*|CCB_OLLAMA_HOST=*|CCB_MODEL_PRESET=*|CCB_MODEL_DEFAULT=*|CCB_MODEL_PLANNER=*|CCB_MODEL_CODER=*|CCB_MODEL_MANAGER=*|CCB_MODEL_GRAPH=*|CCB_MODEL_GRAPHISTE=*|CCB_MODEL_DEVELOPER=*|CCB_MODEL_REVIEWER=*|CCB_MODEL_FALLBACK=*) key=${line%%=*}; value=${line#*=};;
      *) return 1;;
    esac
    case "$seen" in *" $key "*) return 1;; *) seen="$seen$key ";; esac
    case "$key" in
      CCB_MODEL_PROVIDER) MODEL_CONF_PROVIDER=$value;; CCB_OLLAMA_MODE) MODEL_CONF_MODE=$value;;
      CCB_OLLAMA_HOST) MODEL_CONF_HOST=$value;; CCB_MODEL_PRESET) MODEL_CONF_PRESET=$value;;
      CCB_MODEL_DEFAULT) MODEL_CONF_DEFAULT=$value;; CCB_MODEL_PLANNER) MODEL_CONF_PLANNER=$value;;
      CCB_MODEL_CODER) MODEL_CONF_CODER=$value;; CCB_MODEL_MANAGER) MODEL_CONF_MANAGER=$value;;
      CCB_MODEL_GRAPH) MODEL_CONF_GRAPH=$value;; CCB_MODEL_GRAPHISTE) MODEL_CONF_GRAPHISTE=$value;;
      CCB_MODEL_DEVELOPER) MODEL_CONF_DEVELOPER=$value;; CCB_MODEL_REVIEWER) MODEL_CONF_REVIEWER=$value;;
      CCB_MODEL_FALLBACK) MODEL_CONF_FALLBACK=$value;;
    esac
  done <"$file"
  [ "$MODEL_CONF_PROVIDER" = ollama ] || return 1
  if [ -n "$MODEL_CONF_DEFAULT" ] || [ -n "$MODEL_CONF_PLANNER" ] || [ -n "$MODEL_CONF_CODER" ]; then
    [ -z "$MODEL_CONF_MODE$MODEL_CONF_HOST$MODEL_CONF_PRESET$MODEL_CONF_MANAGER$MODEL_CONF_GRAPH$MODEL_CONF_GRAPHISTE$MODEL_CONF_DEVELOPER$MODEL_CONF_FALLBACK" ] || return 1
    for model in "$MODEL_CONF_DEFAULT" "$MODEL_CONF_PLANNER" "$MODEL_CONF_CODER" "$MODEL_CONF_REVIEWER"; do model_name_is_safe "$model" || return 1; done
    MODEL_CONF_FORMAT=legacy
    MODEL_CONF_MANAGER=$MODEL_CONF_PLANNER; MODEL_CONF_GRAPH=$MODEL_CONF_PLANNER; MODEL_CONF_GRAPHISTE=$MODEL_CONF_PLANNER
    MODEL_CONF_DEVELOPER=$MODEL_CONF_CODER; MODEL_CONF_FALLBACK=$MODEL_CONF_DEFAULT
  else
    model_mode_is_valid "$MODEL_CONF_MODE" && model_host_is_safe "$MODEL_CONF_HOST" && model_preset_is_safe "$MODEL_CONF_PRESET" || return 1
    case "$MODEL_CONF_MODE:$MODEL_CONF_HOST" in cloud-api:https://ollama.com/api|local:http://localhost:*|local:http://127.0.0.1:*|local-proxy:http://localhost:*|local-proxy:http://127.0.0.1:*) :;; *) return 1;; esac
    for model in "$MODEL_CONF_MANAGER" "$MODEL_CONF_GRAPH" "$MODEL_CONF_GRAPHISTE" "$MODEL_CONF_DEVELOPER" "$MODEL_CONF_REVIEWER" "$MODEL_CONF_FALLBACK"; do model_name_is_safe "$model" || return 1; done
    MODEL_CONF_FORMAT=roles
    MODEL_CONF_DEFAULT=$MODEL_CONF_FALLBACK; MODEL_CONF_PLANNER=$MODEL_CONF_MANAGER; MODEL_CONF_CODER=$MODEL_CONF_DEVELOPER
  fi
}
models_conf_validate() { models_conf_parse "$1"; }
