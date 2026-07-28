# V2 architecture

CCB-TEMPLATE is a bootstrap template, not a workflow engine. It initializes a project, renders
`.ccb/ccb.config`, and installs a shared memory, five role memories and the project policy.

The official global CCB owns the multi-pane workspace and launches the configured Claude Code
agents. Claude Code performs each agent turn. Ollama provides the local Anthropic-compatible API
endpoint and executes the selected Cloud models. The template does not call Ollama directly,
interpret model replies or persist its own workflow results. OpenCode is not used.

There is no local `./ccb` command or V1 workflow runtime in this branch. Every `ccb` invocation
is the official global binary.

## Agent topology

| Agent | Model | Responsibility |
| --- | --- | --- |
| manager | `glm-5.2:cloud` | Plans, delegates and consolidates. |
| graph | `qwen3.5:397b-cloud` | Read-only architecture analysis. |
| graphiste | `gemma4:31b-cloud` | Text-only UX/UI and accessibility guidance. |
| developer | `kimi-k2.7-code:cloud` | Implements approved changes. |
| reviewer | `deepseek-v4-pro:cloud` | Read-only review and validation. |

The official `.ccb/ccb.config` declares the windows, agent model, description, isolated provider
profile and the per-agent Ollama compatibility environment. `.ccb/ccb_memory.md` holds durable
shared context. Each `.ccb/agents/<agent>/memory.md` holds durable role-specific context.

No template action pushes, deploys or interprets a model response.
