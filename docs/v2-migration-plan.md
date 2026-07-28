# Migration V2 — Lot 1

Lot 1 adds a parallel bootstrap for the official
[Claude Code Bridge](https://github.com/SeemSeam/claude_codex_bridge). It does not start CCB,
Claude Code, tmux or a model. The legacy V1 CLI remains temporarily untouched.

`install.sh` checks the official global CCB version, local prerequisites and the five selected
Ollama Cloud models. It then creates the official `.ccb/ccb.config`, shared memory, role
memories and policy through atomic writes. Existing memories are preserved and an existing
`ccb.config` is a conflict.

The V2 configuration contains only the literal Ollama compatibility marker `ollama` and the
loopback endpoint. It never writes a bearer token or another user credential.

The next migration lot will validate the configuration against CCB 8.4.3+ and remove the V1
runtime only after the new path is proven.
