# V2 troubleshooting

## CCB cannot find Python

Set `CCB_PYTHON` to an executable Python 3.10+ that can import `tomllib` (or `tomli`), `aiohttp`
and `cryptography`. If it is missing or invalid, the bootstrap tries `python3.14` down to
`python3` and reports each rejected candidate. Create a virtual environment rather than changing
system Python; do not use `--break-system-packages`.

## CCB is older than 8.4.3 or resolves the wrong binary

Run `ccb --version` and inspect `command -v ccb`. Install or update the official global CCB. A
repository-local `./ccb` is the deprecated V1 wrapper and must not be used for V2 projects.

## Ollama or a Cloud model is unavailable

Start Ollama and run `ollama list`. The required models are `glm-5.2:cloud`,
`qwen3.5:397b-cloud`, `gemma4:31b-cloud`, `kimi-k2.7-code:cloud` and
`deepseek-v4-pro:cloud`. A model-retired HTTP 410 response means that the requested model must
be replaced; do not restore the removed V1 coding fallback.

## Claude Code, tmux or configuration issues

Use `ANTHROPIC_AUTH_TOKEN=ollama` and `ANTHROPIC_BASE_URL=http://localhost:11434` for the
Ollama-compatible Claude Code connection. Claude Code may warn about `.local/bin` inside an
isolated provider home; verify the official Claude installation remains available on PATH.

If CCB is detached, use `tmux attach`. If `ccb` appears blocked while starting, wait for its
startup diagnostics before retrying; use `ccb kill` only to stop a workspace deliberately. For a
TOML validation error, inspect `.ccb/ccb.config` and rerun `ccb config validate`.
