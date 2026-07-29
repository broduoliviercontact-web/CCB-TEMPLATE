# V2 troubleshooting

## CCB cannot find Python

Set `CCB_PYTHON` to an executable Python 3.10+ that can import `tomllib` (or `tomli`), `aiohttp`
and `cryptography`. If it is missing or invalid, the bootstrap tries `python3.14` down to
`python3` and reports each rejected candidate. Create a virtual environment rather than changing
system Python; do not use `--break-system-packages`.

## CCB is older than 8.4.3 or resolves the wrong binary

Run `ccb --version` and inspect `command -v ccb`. Install or update the official global CCB.
There is no repository-local `./ccb` on the V2 branch; the legacy wrapper is available only in
the `v1.8.0` tag.

## Ollama or a Cloud model is unavailable

Start Ollama and run `ollama list`. The required models are `glm-5.2:cloud`,
`qwen3.5:397b-cloud`, `kimi-k2.7-code:cloud` and
`kimi-k2.6:cloud`. A model-retired HTTP 410 response means that the requested model must
be replaced; do not restore the removed V1 coding fallback.

## Claude Code, tmux or configuration issues

Use `ANTHROPIC_AUTH_TOKEN=ollama` and `ANTHROPIC_BASE_URL=http://localhost:11434` for the
Ollama-compatible Claude Code connection. Claude Code may warn about `.local/bin` inside an
isolated provider home; verify the official Claude installation remains available on PATH.

If CCB is detached, use `tmux attach`. If `ccb` appears blocked while starting, wait for its
startup diagnostics before retrying; use `ccb kill` only to stop a workspace deliberately. For a
TOML validation error, inspect `.ccb/ccb.config` and rerun `ccb config validate`.

## Token optimization prerequisites or MCP configuration

`--token-optimization` is optional. If RTK is missing on macOS, install and initialize it only
after choosing its telemetry settings yourself:

```sh
brew install rtk-ai/tap/rtk
rtk init -g
```

The mode also requires `npx`; install Node.js/npm through their official distribution, then
check `npx tilth --version`. Tilth is not downloaded during bootstrap: Claude Code later starts
the project MCP command `npx -y tilth@0.9.0 --mcp`. If an existing `.mcp.json` is invalid or its
`mcpServers` member is not an object, repair it manually and retry; the bootstrap leaves it
unchanged on refusal. Existing `.claude/rules/token-optimization.md` files are preserved.
