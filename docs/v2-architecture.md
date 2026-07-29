# V2 architecture

CCB-TEMPLATE is a bootstrap template, not a workflow engine. It initializes a project, renders
`.ccb/ccb.config`, and installs a shared memory, four role memories and the project policy.

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
| developer | `kimi-k2.7-code:cloud` | Implements approved changes. |
| reviewer | `kimi-k2.6:cloud` | Read-only review and validation. |

The official `.ccb/ccb.config` declares the windows, agent model, description, isolated provider
profile and the per-agent Ollama compatibility environment. `.ccb/ccb_memory.md` holds durable
shared context. Each `.ccb/agents/<agent>/memory.md` holds durable role-specific context.
The bootstrap also creates a common project `CLAUDE.md`, role briefs under
`.ccb/agents/<agent>/CLAUDE.md`, and project-local skills under `.claude/skills/`. CCB-managed
agent homes are runtime-owned, so role memories remain the durable instruction channel for its
isolated agents.

No template action pushes, deploys or interprets a model response.

## Token optimization

By default, the bootstrap adds only project-native Claude Code inputs:
`.mcp.json` configures the pinned Tilth stdio server through `npx`, and
`.claude/rules/token-optimization.md` provides concise usage guidance for Tilth and RTK. RTK
and Tilth remain external tools; the bootstrap neither installs, initializes nor runs them. Pass
`--no-token-optimization` to omit these inputs.

CCB 8.4.3 projects each Claude agent into an isolated managed home. Its documented MCP
projection includes current project/workspace MCP metadata when configuration inheritance is
enabled; V2 leaves that inheritance enabled. CCB does not document native project rules as a
managed-home projection. The rule is therefore supplied for Claude Code's native project rule
loader, without a claim that CCB itself duplicates it into every isolated home.
