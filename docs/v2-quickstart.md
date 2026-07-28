# V2 quickstart

CCB-TEMPLATE prepares a project for the official
[Claude Code Bridge](https://github.com/SeemSeam/claude_codex_bridge). It does not run a second
orchestrator and does not use OpenCode.

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

## 4. Validate and start

```sh
cd /chemin/du/projet
ccb config validate
ccb
```

CCB runs in tmux. Detach with `Ctrl-b` then `d`; reattach from a terminal with `tmux attach`.
Stop an active CCB workspace explicitly with `ccb kill`.
