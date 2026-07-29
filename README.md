# CCB Template

[![Validate CCB Template](https://github.com/broduoliviercontact-web/CCB-TEMPLATE/actions/workflows/validate.yml/badge.svg)](https://github.com/broduoliviercontact-web/CCB-TEMPLATE/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## CCB-TEMPLATE 2.0.0

CCB-TEMPLATE configures the official [SeemSeam/claude_codex_bridge](https://github.com/SeemSeam/claude_codex_bridge).
It is a bootstrap template: it verifies prerequisites, generates the official project configuration
and installs reusable text assets. It is not an orchestration engine and does not use OpenCode.
It requires official CCB 8.4.3 or later.

```sh
./install.sh /chemin/du/projet \
  --name "Nom du projet" \
  --profile web \
  --claude-ollama-cloud \
  --yes

cd /chemin/du/projet
ccb config validate
ccb
```

Every `ccb` command in this branch denotes the official globally installed CCB binary. The
repository-local `./ccb` command has been removed, as have the V1 provider router, direct Ollama
runtime and home-grown workflows. The installer never pushes or deploys automatically, never
interprets model responses and never starts CCB or a Cloud model by itself.

`--profile web` selects the standard built-in asset preset. It is the only preset supported by
V2.0.0 and does not load a `profiles/` directory.

### Optional token optimization

Add `--token-optimization` to prepare only the generated project for the external RTK terminal
filter and the Tilth MCP code-navigation server. It is optional: standard CCB installation does
not require RTK, Node.js, npm or npx. The mode verifies `rtk` and `npx`, writes project-local
`.mcp.json` with the pinned `npx -y tilth@0.9.0 --mcp` server, and adds a concise
`.claude/rules/token-optimization.md` without replacing an existing user rule or `CLAUDE.md`.
It never installs or initializes either tool.

```sh
brew install rtk-ai/tap/rtk
rtk init -g
npx tilth --version
```

RTK mainly filters verbose terminal output; any advertised percentage is an estimate and does
not guarantee an equivalent reduction in Claude usage. Tilth is downloaded and launched by npx
only when Claude Code starts the configured MCP server, never by this bootstrap.

The generated official configuration uses four Claude Code agents through Ollama's
Anthropic-compatible local endpoint:

| Agent | Model |
| --- | --- |
| manager | `glm-5.2:cloud` |
| graph | `qwen3.5:397b-cloud` |
| developer | `kimi-k2.7-code:cloud` |
| reviewer | `kimi-k2.6:cloud` |

See the [V2 quickstart](docs/v2-quickstart.md), [architecture](docs/v2-architecture.md),
[migration guide](docs/v2-migration-from-v1.md), [migration plan](docs/v2-migration-plan.md) and
[troubleshooting](docs/v2-troubleshooting.md).

## V1.8.0 archive

The V1 engine and all of its former commands are unavailable on `refactor/official-ccb-v2`.
They remain intact in the immutable `v1.8.0` tag for historical reference and existing V1 projects:

```sh
git show v1.8.0:README.md
```

The V1 profiles, skills, prompts and manuals were removed with the runtime; consult the tag when
maintaining an existing V1 project. V2 installs only the policy and memories under `assets/`.

## License

This template is distributed under the [MIT License](LICENSE).
