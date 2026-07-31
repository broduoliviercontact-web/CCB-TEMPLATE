# V2 quickstart

CCB-TEMPLATE prepares a project for the official
[Claude Code Bridge](https://github.com/SeemSeam/claude_codex_bridge). It does not run a second
orchestrator and does not use OpenCode. Every `ccb` command below is the official globally
installed binary; this V2 branch has no local `./ccb` wrapper.

## 1. Install prerequisites

Install the official CCB globally and confirm that it is at least 8.4.3:

```sh
npm install -g @seemseam/ccb@latest
ccb --version
```

Install tmux, Claude Code and Ollama through their official installation methods. Start Ollama,
then confirm its Cloud models are visible with `ollama list`.

CCB requires Python 3.10+ with `tomllib` (or `tomli`), `aiohttp` and `cryptography`. A dedicated
virtual environment avoids changing system Python:

```sh
python3.13 -m venv ~/.venvs/ccb-8.4.3
~/.venvs/ccb-8.4.3/bin/python -m pip install --upgrade pip
~/.venvs/ccb-8.4.3/bin/python -m pip install aiohttp cryptography
export CCB_PYTHON="$HOME/.venvs/ccb-8.4.3/bin/python"
```

Do not use `--break-system-packages`.

## 2. Verify Claude Code and Ollama

Claude Code uses Ollama's Anthropic-compatible local endpoint. Set these values in the shell used
for a manual check; the V2 generated agent configuration writes the harmless literal `ollama` and
the loopback URL into each agent environment:

```sh
export ANTHROPIC_AUTH_TOKEN=ollama
export ANTHROPIC_BASE_URL=http://localhost:11434
claude --model kimi-k2.7-code:cloud -p 'Reply only: connection check.'
```

## 3. Preview and install

`--profile web` selects the standard built-in asset preset. It is the only preset supported by
V2.0.0; external or specialized profile directories are not installed.

Preview without writing files:

```sh
./install.sh /chemin/du/projet \
  --name "Nom du projet" \
  --profile web \
  --claude-ollama-cloud \
  --dry-run
```

Install after reviewing the preflight:

```sh
./install.sh /chemin/du/projet \
  --name "Nom du projet" \
  --profile web \
  --claude-ollama-cloud \
  --yes
```

### Token optimization

Token optimization is enabled by default and integrates the external RTK terminal filter and Tilth
MCP server. Install and initialize RTK yourself, then confirm npx can resolve
Tilth:

```sh
brew install rtk-ai/tap/rtk
rtk init -g
npx tilth --version
```

The installer creates `.mcp.json` using the pinned command `npx -y tilth@0.9.0 --mcp` and a concise
`.claude/rules/token-optimization.md`. Pass `--no-token-optimization` to skip this integration. The bootstrap
does not run RTK initialization or replace an existing `.mcp.json`, rule or `CLAUDE.md`. It does
prewarm Tilth once per managed agent home with `npx -y tilth@0.9.0 --version` and links the local
Claude Code CLI into each isolated home. It also seeds Claude Code onboarding/project trust state
so first-start agents do not wait on the theme picker or RTK external-import prompt. RTK filters
primarily terminal output; its estimates do not guarantee a matching reduction in Claude usage.
Tilth is started by npx when Claude Code starts the MCP server, using the prewarmed isolated cache.

## 4. Validate and start

```sh
cd /chemin/du/projet
ccb config validate
ccb
```

CCB runs in tmux. Detach with `Ctrl-b` then `d`; reattach from a terminal with `tmux attach`.
Stop an active CCB workspace explicitly with `ccb kill`.
