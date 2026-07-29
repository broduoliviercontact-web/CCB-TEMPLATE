#!/bin/sh

v2_render_config() {
  output=$1 name=$2 profile=$3 manager_model=${4:-glm-5.2:cloud} graph_model=${5:-qwen3.5:397b-cloud} developer_model=${6:-kimi-k2.7-code:cloud} reviewer_model=${7:-kimi-k2.6:cloud} token_monitoring=${8:-0}
  v2_is_safe_name "$name" || v2_die 'project name contains an unsafe line break'
  [ "$profile" = web ] || v2_die 'unsupported profile'
  for model in "$manager_model" "$graph_model" "$developer_model" "$reviewer_model"; do
    v2_is_cloud_model "$model" || v2_die "invalid Ollama Cloud model: $model"
  done
  case "$token_monitoring" in 0|1) : ;; *) v2_die 'token monitoring must be enabled or disabled' ;; esac
  manager_base_url=http://localhost:11434
  graph_base_url=$manager_base_url developer_base_url=$manager_base_url reviewer_base_url=$manager_base_url
  if [ "$token_monitoring" -eq 1 ]; then
    manager_base_url=http://127.0.0.1:11435/manager
    graph_base_url=http://127.0.0.1:11435/graph
    developer_base_url=http://127.0.0.1:11435/developer
    reviewer_base_url=http://127.0.0.1:11435/reviewer
  fi
  cat >"$output" <<EOF
version = 2
entry_window = "main"

[windows]
main = "manager:claude"
design = "graph:claude"
build = "developer:claude"
review = "reviewer:claude"

[agents.manager]
model = "$manager_model"
description = "Planifie, délègue et consolide sans modifier les fichiers applicatifs."

[agents.manager.provider_profile]
inherit_api = false
inherit_auth = false

[agents.manager.env]
ANTHROPIC_AUTH_TOKEN = "ollama"
ANTHROPIC_BASE_URL = "$manager_base_url"

[agents.graph]
model = "$graph_model"
description = "Analyse l’architecture et les dépendances en lecture seule."

[agents.graph.provider_profile]
inherit_api = false
inherit_auth = false

[agents.graph.env]
ANTHROPIC_AUTH_TOKEN = "ollama"
ANTHROPIC_BASE_URL = "$graph_base_url"

[agents.developer]
model = "$developer_model"
description = "Implémente les changements autorisés et exécute les validations pertinentes."

[agents.developer.provider_profile]
inherit_api = false
inherit_auth = false

[agents.developer.env]
ANTHROPIC_AUTH_TOKEN = "ollama"
ANTHROPIC_BASE_URL = "$developer_base_url"

[agents.reviewer]
model = "$reviewer_model"
description = "Relit en lecture seule les risques, régressions et validations."

[agents.reviewer.provider_profile]
inherit_api = false
inherit_auth = false

[agents.reviewer.env]
ANTHROPIC_AUTH_TOKEN = "ollama"
ANTHROPIC_BASE_URL = "$reviewer_base_url"
EOF
}
