#!/bin/sh

v2_render_config() {
  output=$1 name=$2 profile=$3
  v2_is_safe_name "$name" || v2_die 'project name contains an unsafe line break'
  [ "$profile" = web ] || v2_die 'unsupported profile'
  cat >"$output" <<'EOF'
version = 2
entry_window = "main"

[windows]
main = "manager:claude"
design = "graph:claude"
build = "developer:claude"
review = "reviewer:claude"

[agents.manager]
model = "glm-5.2:cloud"
description = "Planifie, délègue et consolide sans modifier les fichiers applicatifs."

[agents.manager.provider_profile]
inherit_api = false
inherit_auth = false

[agents.manager.env]
ANTHROPIC_AUTH_TOKEN = "ollama"
ANTHROPIC_BASE_URL = "http://localhost:11434"

[agents.graph]
model = "qwen3.5:397b-cloud"
description = "Analyse l’architecture et les dépendances en lecture seule."

[agents.graph.provider_profile]
inherit_api = false
inherit_auth = false

[agents.graph.env]
ANTHROPIC_AUTH_TOKEN = "ollama"
ANTHROPIC_BASE_URL = "http://localhost:11434"

[agents.developer]
model = "kimi-k2.7-code:cloud"
description = "Implémente les changements autorisés et exécute les validations pertinentes."

[agents.developer.provider_profile]
inherit_api = false
inherit_auth = false

[agents.developer.env]
ANTHROPIC_AUTH_TOKEN = "ollama"
ANTHROPIC_BASE_URL = "http://localhost:11434"

[agents.reviewer]
model = "kimi-k2.6:cloud"
description = "Relit en lecture seule les risques, régressions et validations."

[agents.reviewer.provider_profile]
inherit_api = false
inherit_auth = false

[agents.reviewer.env]
ANTHROPIC_AUTH_TOKEN = "ollama"
ANTHROPIC_BASE_URL = "http://localhost:11434"
EOF
}
