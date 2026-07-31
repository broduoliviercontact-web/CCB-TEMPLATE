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

## 2. Run doctor

From the template clone, run the standard diagnostic:

```sh
./ccb-template doctor
```

It reports all mandatory prerequisites in one pass using `[OK]` and `[MISSING]`. Missing RTK, npx
or Tilth does not fail the standard diagnostic because those components are optional.

Use the full diagnostic when you plan to enable optional RTK, Tilth or local token monitoring:

```sh
./ccb-template doctor --full
```

`doctor --full` still exits with status 1 only when a mandatory prerequisite is missing. Optional
components are reported as `[WARNING]`.

## 3. Verify Claude Code and Ollama

Claude Code uses Ollama's Anthropic-compatible local endpoint. Set these values in the shell used
for a manual check; the V2 generated agent configuration writes the harmless literal `ollama` and
the loopback URL into each agent environment:

```sh
export ANTHROPIC_AUTH_TOKEN=ollama
export ANTHROPIC_BASE_URL=http://localhost:11434
claude --model kimi-k2.7-code:cloud -p 'Reply only: connection check.'
```

## 4. Create a project

The shortest path derives the project name from the target folder, selects recommended installed
Cloud models automatically, leaves local monitoring off and asks one main confirmation:

```sh
./ccb-template init /chemin/du/projet
```

Use advanced mode only when you want to choose each agent model, disable RTK/Tilth, or enable local
token monitoring:

```sh
./ccb-template init /chemin/du/projet --advanced
```

The initializer creates no commit, pushes nothing, deploys nothing and does not start CCB without
asking after the files are written. It prepares each CCB agent's isolated Claude Code home with the
local Claude Code CLI link and onboarding/project-trust state required by the native Claude
provider.

## 5. Non-interactive install

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

The standard install enables RTK and Tilth token optimization by default. Dependency-free
minimalist rules inspired by [Ponytail](https://github.com/dietrichgebert/ponytail) are also
included in the generated agent skills; this is not the full or official Ponytail plugin.

Install and initialize RTK yourself, then confirm npx can resolve Tilth:

```sh
brew install rtk-ai/tap/rtk
rtk init -g
npx tilth --version
```

The installer creates `.mcp.json` using the pinned command `npx -y tilth@0.9.0 --mcp` and a concise
`.claude/rules/token-optimization.md`. The bootstrap does not run RTK initialization or replace an
existing `.mcp.json`, rule or `CLAUDE.md`. It does prewarm Tilth once per managed agent home with
`npx -y tilth@0.9.0 --version`. RTK filters primarily terminal output; its estimates do not
guarantee a matching reduction in Claude usage. Tilth is started by npx when Claude Code starts the
MCP server, using the prewarmed isolated cache.

Use `--no-token-optimization` with `install.sh`, or answer `n` in `ccb-template init --advanced`,
only when the RTK/Tilth integration should be skipped.

## 6. Validate and start

```sh
cd /chemin/du/projet
ccb config validate
ccb
```

CCB runs in tmux. Detach with `Ctrl-b` then `d`; reattach from a terminal with `tmux attach`.
Stop an active CCB workspace explicitly with `ccb kill`.
